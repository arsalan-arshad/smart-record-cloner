import { createElement } from 'lwc';
import SmartRecordCloner from 'c/smartRecordCloner';
import getCloneConfig from '@salesforce/apex/DeepCloneController.getCloneConfig';
import cloneRecord from '@salesforce/apex/DeepCloneController.cloneRecord';

jest.mock('@salesforce/apex/DeepCloneController.getCloneConfig', () => ({ default: jest.fn() }), { virtual: true });

jest.mock('@salesforce/apex/DeepCloneController.cloneRecord', () => ({ default: jest.fn() }), { virtual: true });

jest.mock(
    'lightning/actions',
    () => ({
        CloseActionScreenEvent: class CloseActionScreenEvent extends CustomEvent {
            constructor() {
                super('close');
            }
        }
    }),
    { virtual: true }
);

const MOCK_CONFIG = {
    recordId: '001000000000001AAA',
    sObjectName: 'Account',
    sObjectLabel: 'Account',
    recordName: 'Acme Test Corp',
    nameFieldName: 'Name',
    isNameEditable: true,
    defaultNewRecordName: 'Clone of Acme Test Corp',
    totalRelatedRecords: 6,
    childRelationships: [
        {
            relationshipName: 'Contacts',
            childSObjectName: 'Contact',
            childLabel: 'Contacts',
            childPluralLabel: 'Contacts',
            foreignKeyField: 'AccountId',
            recordCount: 4,
            isDefaultSelected: true,
            isCascadeDelete: false
        },
        {
            relationshipName: 'Cases',
            childSObjectName: 'Case',
            childLabel: 'Cases',
            childPluralLabel: 'Cases',
            foreignKeyField: 'AccountId',
            recordCount: 2,
            isDefaultSelected: true,
            isCascadeDelete: false
        }
    ]
};

const MOCK_CLONE_RESULT = {
    isSuccess: true,
    originalRecordId: '001000000000001AAA',
    newRecordId: '001000000000002BBB',
    newRecordName: 'Clone of Acme Test Corp',
    totalChildrenCloned: 6,
    clonedCountsByRelationship: {
        Contacts: 4,
        Cases: 2
    },
    errorMessage: null
};

describe('c-smart-record-cloner', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function flushPromises() {
        return new Promise((resolve) => setTimeout(resolve, 0));
    }

    it('renders initial loading state then displays clone configuration form', async () => {
        getCloneConfig.mockResolvedValue(MOCK_CONFIG);

        const element = createElement('c-smart-record-cloner', {
            is: SmartRecordCloner
        });
        element.recordId = '001000000000001AAA';
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        expect(getCloneConfig).toHaveBeenCalled();

        const inputs = Array.from(element.shadowRoot.querySelectorAll('lightning-input'));
        const nameInput = inputs.find((inp) => inp.label === 'New Record Name');
        expect(nameInput).not.toBeNull();
        expect(nameInput.value).toBe('Clone of Acme Test Corp');

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBe(2);
    });

    it('toggles select all and deselect all correctly', async () => {
        getCloneConfig.mockResolvedValue(MOCK_CONFIG);

        const element = createElement('c-smart-record-cloner', {
            is: SmartRecordCloner
        });
        element.recordId = '001000000000001AAA';
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        const buttons = Array.from(element.shadowRoot.querySelectorAll('lightning-button'));
        const deselectBtn = buttons.find((btn) => btn.label === 'Deselect All');
        expect(deselectBtn).toBeDefined();
        deselectBtn.click();
        await flushPromises();

        const inputs = Array.from(element.shadowRoot.querySelectorAll('tbody lightning-input'));
        inputs.forEach((cb) => {
            expect(cb.checked).toBe(false);
        });

        const selectAllBtn = buttons.find((btn) => btn.label === 'Select All');
        expect(selectAllBtn).toBeDefined();
        selectAllBtn.click();
        await flushPromises();

        const updatedInputs = Array.from(element.shadowRoot.querySelectorAll('tbody lightning-input'));
        updatedInputs.forEach((cb) => {
            expect(cb.checked).toBe(true);
        });
    });

    it('executes cloneRecord and renders success view with review hook', async () => {
        getCloneConfig.mockResolvedValue(MOCK_CONFIG);
        cloneRecord.mockResolvedValue(MOCK_CLONE_RESULT);

        const element = createElement('c-smart-record-cloner', {
            is: SmartRecordCloner
        });
        element.recordId = '001000000000001AAA';
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        const buttons = Array.from(element.shadowRoot.querySelectorAll('lightning-button'));
        const cloneButton = buttons.find((btn) => btn.label === 'Clone Record');
        expect(cloneButton).toBeDefined();
        cloneButton.click();

        await flushPromises();
        await flushPromises();

        expect(cloneRecord).toHaveBeenCalledTimes(1);

        const successTitle = element.shadowRoot.querySelector('.slds-text-heading_large');
        expect(successTitle).not.toBeNull();
        expect(successTitle.textContent).toContain('Record Cloned Successfully');

        const reviewCard = element.shadowRoot.querySelector('.review-hook-card');
        expect(reviewCard).not.toBeNull();
        expect(reviewCard.textContent).toContain('Saved you 15 minutes?');
    });
});
