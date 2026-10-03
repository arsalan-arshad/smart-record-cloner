import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getCloneConfig from '@salesforce/apex/DeepCloneController.getCloneConfig';
import cloneRecord from '@salesforce/apex/DeepCloneController.cloneRecord';
export default class SmartRecordCloner extends NavigationMixin(LightningElement) {
    _recordId;
    _hasLoadedConfig = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._hasLoadedConfig) {
            this._hasLoadedConfig = true;
            this.loadConfiguration();
        }
    }

    @api objectApiName;
    @api title = 'Smart Record Cloner';

    @track config = {};
    @track relationships = [];
    @track newRecordName = '';
    @track searchKeyword = '';
    @track resetStatus = false;
    @track errorMessage = '';
    @track cloneResult = null;

    isLoading = true;
    loadingMessage = 'Loading record metadata and relationships...';
    isSuccess = false;

    connectedCallback() {
        if (this.recordId && !this._hasLoadedConfig) {
            this._hasLoadedConfig = true;
            this.loadConfiguration();
        }
    }

    async loadConfiguration() {
        this.isLoading = true;
        this.loadingMessage = 'Analyzing record and related child metadata...';
        this.errorMessage = '';

        try {
            const data = await getCloneConfig({ recordId: this.recordId });
            this.config = data;
            this.newRecordName = data.defaultNewRecordName || '';

            if (data.childRelationships) {
                this.relationships = data.childRelationships.map((rel) => ({
                    ...rel,
                    selected: rel.isDefaultSelected,
                    hasRecords: (rel.recordCount || 0) > 0,
                    rowClass: (rel.recordCount || 0) > 0 ? 'slds-hint-parent row-has-records' : 'slds-hint-parent'
                }));
            } else {
                this.relationships = [];
            }
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error Loading Metadata', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get isConfigView() {
        return !this.isLoading && !this.isSuccess;
    }

    get isSuccessView() {
        return !this.isLoading && this.isSuccess;
    }

    get filteredRelationships() {
        if (!this.searchKeyword) {
            return this.relationships;
        }
        const term = this.searchKeyword.toLowerCase();
        return this.relationships.filter(
            (rel) =>
                (rel.childLabel && rel.childLabel.toLowerCase().includes(term)) ||
                (rel.relationshipName && rel.relationshipName.toLowerCase().includes(term)) ||
                (rel.childSObjectName && rel.childSObjectName.toLowerCase().includes(term))
        );
    }

    get selectedChildCount() {
        return this.relationships
            .filter((rel) => rel.selected)
            .reduce((total, rel) => total + (rel.recordCount || 0), 0);
    }

    get totalAvailableRecords() {
        return this.config?.totalRelatedRecords || 0;
    }

    get hasMultipleRelationships() {
        return this.relationships && this.relationships.length > 2;
    }

    get isCloneDisabled() {
        if (this.isLoading) {
            return true;
        }
        if (this.config?.isNameEditable && (!this.newRecordName || !this.newRecordName.trim())) {
            return true;
        }
        return false;
    }

    get clonedBreakdown() {
        if (!this.cloneResult?.clonedCountsByRelationship) {
            return [];
        }
        const counts = this.cloneResult.clonedCountsByRelationship;
        return Object.keys(counts)
            .filter((k) => counts[k] > 0)
            .map((k) => ({
                relName: k,
                count: counts[k]
            }));
    }

    handleNameChange(event) {
        this.newRecordName = event.target.value;
    }

    handleSearchChange(event) {
        this.searchKeyword = event.target.value;
    }

    handleResetStatusChange(event) {
        this.resetStatus = event.target.checked;
    }

    handleCheckboxChange(event) {
        const relName = event.target.dataset.rel;
        const isChecked = event.target.checked;
        this.relationships = this.relationships.map((rel) => {
            if (rel.relationshipName === relName) {
                return { ...rel, selected: isChecked };
            }
            return rel;
        });
    }

    handleSelectAll() {
        this.relationships = this.relationships.map((rel) => ({
            ...rel,
            selected: true
        }));
    }

    handleDeselectAll() {
        this.relationships = this.relationships.map((rel) => ({
            ...rel,
            selected: false
        }));
    }

    async handleClone() {
        this.isLoading = true;
        this.loadingMessage = 'Deep cloning record and reparenting child relationships...';
        this.errorMessage = '';

        const selectedRels = this.relationships.filter((rel) => rel.selected).map((rel) => rel.relationshipName);

        try {
            const result = await cloneRecord({
                recordId: this.recordId,
                newRecordName: this.newRecordName,
                childRelationshipNames: selectedRels,
                resetStatus: this.resetStatus,
                fieldOverrides: null
            });

            this.cloneResult = result;
            this.isSuccess = true;
            this.showToast('Success', `Successfully cloned ${result.newRecordName}`, 'success');
        } catch (error) {
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Cloning Failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleNavigateToNewRecord() {
        if (this.cloneResult?.newRecordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.cloneResult.newRecordId,
                    actionName: 'view'
                }
            });
            this.handleCloseModal();
        }
    }

    handleCancel() {
        this.handleCloseModal();
    }

    handleCloseModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    extractErrorMessage(error) {
        if (!error) return 'An unknown error occurred.';
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
