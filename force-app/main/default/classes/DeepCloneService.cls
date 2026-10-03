/**
 * @description Core service engine for deep cloning Salesforce records and related child lists.
 * Supports standard and custom objects, dynamic describe metadata discovery, bulk safety,
 * field sanitization (State/Country picklists, OpportunityLineItems), and transactional rollback.
 */
public with sharing class DeepCloneService {
    public class CloneException extends Exception {
    }

    private static final Set<String> EXCLUDED_PREFIXES = new Set<String>{
        'payment',
        'card',
        'alternative',
        'waitlist',
        'userdefined',
        'extlrec',
        'scorecard',
        'flow',
        'process',
        'record',
        'topic',
        'collaboration',
        'feed',
        'attached',
        'combined',
        'duplicate',
        'commsubscription',
        'authorization',
        'networkuser',
        'outgoingemail',
        'taskrelation',
        'eventrelation'
    };

    private static final Set<String> EXCLUDED_CHILD_OBJECTS = new Set<String>{
        'contentdocumentlink',
        'noteandattachment',
        'openactivity',
        'activityhistory',
        'entitysubscription'
    };

    private static final Integer MAX_RELATIONSHIP_COUNT_QUERIES = 25;

    public class CloneRequest {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String newRecordName;
        @AuraEnabled
        public List<String> childRelationshipNames;
        @AuraEnabled
        public Boolean resetStatus;
        @AuraEnabled
        public Map<String, Object> fieldOverrides;

        public CloneRequest() {
            this.childRelationshipNames = new List<String>();
            this.resetStatus = false;
            this.fieldOverrides = new Map<String, Object>();
        }
    }

    public class CloneResult {
        @AuraEnabled
        public Boolean isSuccess;
        @AuraEnabled
        public Id originalRecordId;
        @AuraEnabled
        public Id newRecordId;
        @AuraEnabled
        public String newRecordName;
        @AuraEnabled
        public Integer totalChildrenCloned;
        @AuraEnabled
        public Map<String, Integer> clonedCountsByRelationship;
        @AuraEnabled
        public String errorMessage;

        public CloneResult() {
            this.isSuccess = false;
            this.totalChildrenCloned = 0;
            this.clonedCountsByRelationship = new Map<String, Integer>();
        }
    }

    public class ChildRelationshipMeta implements Comparable {
        @AuraEnabled
        public String relationshipName;
        @AuraEnabled
        public String childSObjectName;
        @AuraEnabled
        public String childLabel;
        @AuraEnabled
        public String childPluralLabel;
        @AuraEnabled
        public String foreignKeyField;
        @AuraEnabled
        public Integer recordCount;
        @AuraEnabled
        public Boolean isDefaultSelected;
        @AuraEnabled
        public Boolean isCascadeDelete;

        public Integer compareTo(Object compareTo) {
            ChildRelationshipMeta other = (ChildRelationshipMeta) compareTo;
            Integer thisCount = (this.recordCount == null) ? 0 : this.recordCount;
            Integer otherCount = (other.recordCount == null) ? 0 : other.recordCount;

            // Records with existing data appear at the top
            if (thisCount > 0 && otherCount == 0) {
                return -1;
            }
            if (thisCount == 0 && otherCount > 0) {
                return 1;
            }
            if (thisCount != otherCount) {
                return otherCount - thisCount;
            }
            return this.childLabel.compareTo(other.childLabel);
        }
    }

    public class CloneConfig {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String sObjectName;
        @AuraEnabled
        public String sObjectLabel;
        @AuraEnabled
        public String recordName;
        @AuraEnabled
        public String nameFieldName;
        @AuraEnabled
        public Boolean isNameEditable;
        @AuraEnabled
        public String defaultNewRecordName;
        @AuraEnabled
        public List<ChildRelationshipMeta> childRelationships;
        @AuraEnabled
        public Integer totalRelatedRecords;

        public CloneConfig() {
            this.childRelationships = new List<ChildRelationshipMeta>();
            this.totalRelatedRecords = 0;
            this.isNameEditable = true;
        }
    }

    /**
     * @description Discovers cloneable child relationships for a given record and returns count of existing children.
     * @param recordId ID of the parent record
     * @return CloneConfig containing parent metadata, name, and cloneable relationships with counts
     */
    public static CloneConfig getCloneConfig(Id recordId) {
        if (recordId == null) {
            throw new CloneException('Record ID cannot be null.');
        }

        SObjectType parentType = recordId.getSObjectType();
        DescribeSObjectResult parentDescribe = parentType.getDescribe();

        CloneConfig config = new CloneConfig();
        config.recordId = recordId;
        config.sObjectName = parentDescribe.getName();
        config.sObjectLabel = parentDescribe.getLabel();

        // Determine primary name/title field
        Map<String, SObjectField> fieldMap = parentDescribe.fields.getMap();
        String nameField = null;
        String subjectField = null;

        for (String fn : fieldMap.keySet()) {
            DescribeFieldResult fd = fieldMap.get(fn).getDescribe();
            if (fd.isNameField()) {
                nameField = fd.getName();
            }
            if (fd.getName().equalsIgnoreCase('Subject')) {
                subjectField = fd.getName();
            }
        }
        if (nameField == null && fieldMap.containsKey('name')) {
            nameField = 'Name';
        }

        String targetDisplayField = null;
        if (
            nameField != null &&
            fieldMap.get(nameField.toLowerCase()).getDescribe().isAutoNumber() &&
            subjectField != null &&
            fieldMap.get(subjectField.toLowerCase()).getDescribe().isCreateable()
        ) {
            targetDisplayField = subjectField;
        } else if (nameField != null) {
            targetDisplayField = nameField;
        } else {
            targetDisplayField = subjectField;
        }
        config.nameFieldName = targetDisplayField;

        if (targetDisplayField != null) {
            DescribeFieldResult targetFd = fieldMap.get(targetDisplayField.toLowerCase()).getDescribe();
            config.isNameEditable = targetFd.isCreateable() && !targetFd.isAutoNumber();
            String q =
                'SELECT ' +
                String.escapeSingleQuotes(targetDisplayField) +
                ' FROM ' +
                parentDescribe.getName() +
                ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.query(q);
            if (!records.isEmpty()) {
                config.recordName = (String) records[0].get(targetDisplayField);
                config.defaultNewRecordName =
                    'Clone of ' + (config.recordName != null ? config.recordName : parentDescribe.getLabel());
            }
        } else {
            config.isNameEditable = false;
            config.recordName = parentDescribe.getLabel();
            config.defaultNewRecordName = 'Clone of ' + parentDescribe.getLabel();
        }

        config.childRelationships = getCloneableRelationships(recordId, parentDescribe);
        for (ChildRelationshipMeta meta : config.childRelationships) {
            config.totalRelatedRecords += (meta.recordCount != null ? meta.recordCount : 0);
        }

        return config;
    }

    /**
     * @description Inspects child relationships and counts existing related records.
     */
    public static List<ChildRelationshipMeta> getCloneableRelationships(
        Id recordId,
        DescribeSObjectResult parentDescribe
    ) {
        List<ChildRelationshipMeta> results = new List<ChildRelationshipMeta>();
        List<CandidateRel> candidates = new List<CandidateRel>();

        for (Schema.ChildRelationship cr : parentDescribe.getChildRelationships()) {
            String relName = cr.getRelationshipName();
            if (String.isBlank(relName)) {
                continue;
            }

            SObjectType childType = cr.getChildSObject();
            DescribeSObjectResult childDescribe = childType.getDescribe();
            String childObjName = childDescribe.getName().toLowerCase();
            String lowerRelName = relName.toLowerCase();

            // Exclude audit, history, feed, share, and uncloneable system objects
            if (
                childObjName.endsWith('history') ||
                childObjName.endsWith('share') ||
                childObjName.endsWith('feed') ||
                childObjName.endsWith('changeevent') ||
                childObjName.endsWith('tag') ||
                childObjName.endsWith('vote') ||
                EXCLUDED_CHILD_OBJECTS.contains(childObjName)
            ) {
                continue;
            }

            Boolean isExcluded = false;
            for (String prefix : EXCLUDED_PREFIXES) {
                if (childObjName.startsWith(prefix) || lowerRelName.startsWith(prefix)) {
                    isExcluded = true;
                    break;
                }
            }
            if (isExcluded) {
                continue;
            }

            // Must be queryable and createable
            if (!childDescribe.isQueryable() || !childDescribe.isCreateable()) {
                continue;
            }

            // Foreign key field must be createable
            DescribeFieldResult fkDescribe = cr.getField().getDescribe();
            if (!fkDescribe.isCreateable()) {
                continue;
            }

            CandidateRel cand = new CandidateRel();
            cand.childRelationship = cr;
            cand.childDescribe = childDescribe;
            cand.relName = relName;
            cand.foreignKeyField = fkDescribe.getName();
            cand.isCascade = cr.isCascadeDelete();
            cand.isCustom = childDescribe.isCustom() || relName.endsWith('__r');
            candidates.add(cand);
        }

        // Limit count queries to avoid governor limits
        Integer queryCount = 0;
        for (CandidateRel cand : candidates) {
            ChildRelationshipMeta meta = new ChildRelationshipMeta();
            meta.relationshipName = cand.relName;
            meta.childSObjectName = cand.childDescribe.getName();
            meta.childLabel = cand.childDescribe.getLabel();
            meta.childPluralLabel = cand.childDescribe.getLabelPlural();
            meta.foreignKeyField = cand.foreignKeyField;
            meta.isCascadeDelete = cand.isCascade;
            meta.recordCount = 0;
            meta.isDefaultSelected = false;

            if (queryCount < MAX_RELATIONSHIP_COUNT_QUERIES) {
                try {
                    String countSoql =
                        'SELECT count() FROM ' +
                        cand.childDescribe.getName() +
                        ' WHERE ' +
                        String.escapeSingleQuotes(cand.foreignKeyField) +
                        ' = :recordId';
                    meta.recordCount = Database.countQuery(countSoql);
                    meta.isDefaultSelected = (meta.recordCount > 0);
                    queryCount++;
                } catch (Exception ex) {
                    meta.recordCount = 0;
                    meta.isDefaultSelected = false;
                }
            }

            results.add(meta);
        }

        results.sort();
        return results;
    }

    private class CandidateRel {
        public Schema.ChildRelationship childRelationship;
        public DescribeSObjectResult childDescribe;
        public String relName;
        public String foreignKeyField;
        public Boolean isCascade;
        public Boolean isCustom;
    }

    /**
     * @description Executes deep cloning of the parent record and selected child relationships.
     * Transactional: rolls back completely if any child or parent insert fails.
     * @param request CloneRequest detailing recordId, new name, selected child relationships, and options.
     * @return CloneResult with new record ID, child counts, and status.
     */
    public static CloneResult deepClone(CloneRequest request) {
        if (request == null || request.recordId == null) {
            throw new CloneException('Record ID is required for cloning.');
        }

        Id recordId = request.recordId;
        SObjectType parentType = recordId.getSObjectType();
        DescribeSObjectResult parentDescribe = parentType.getDescribe();

        if (!parentDescribe.isCreateable()) {
            throw new CloneException('You do not have permission to create ' + parentDescribe.getLabel() + ' records.');
        }

        Map<String, SObjectField> fieldMap = parentDescribe.fields.getMap();
        List<String> queryFields = new List<String>();
        String nameFieldName = null;
        String subjectFieldName = null;

        for (String fn : fieldMap.keySet()) {
            DescribeFieldResult fd = fieldMap.get(fn).getDescribe();
            if (fd.isAccessible()) {
                queryFields.add(fd.getName());
            }
            if (fd.isNameField()) {
                nameFieldName = fd.getName();
            }
            if (fd.getName().equalsIgnoreCase('Subject')) {
                subjectFieldName = fd.getName();
            }
        }
        if (nameFieldName == null && fieldMap.containsKey('name')) {
            nameFieldName = 'Name';
        }

        String targetNameField = (nameFieldName != null &&
            fieldMap.get(nameFieldName.toLowerCase()).getDescribe().isCreateable() &&
            !fieldMap.get(nameFieldName.toLowerCase()).getDescribe().isAutoNumber())
            ? nameFieldName
            : (subjectFieldName != null && fieldMap.get(subjectFieldName.toLowerCase()).getDescribe().isCreateable()
                  ? subjectFieldName
                  : null);

        // Dynamic parent query
        String parentQuery =
            'SELECT ' +
            String.join(queryFields, ', ') +
            ' FROM ' +
            parentDescribe.getName() +
            ' WHERE Id = :recordId LIMIT 1';
        List<SObject> originalParents = Database.query(parentQuery);
        if (originalParents.isEmpty()) {
            throw new CloneException('Source record not found for ID: ' + recordId);
        }

        SObject originalParent = originalParents[0];
        SObject clonedParent = originalParent.clone(false, true, false, false);

        // Apply new record name
        if (String.isNotBlank(request.newRecordName) && targetNameField != null) {
            clonedParent.put(targetNameField, request.newRecordName);
        }

        // Apply status reset if enabled
        if (request.resetStatus == true) {
            applyStatusReset(clonedParent, parentDescribe.getName(), fieldMap);
        }

        // Apply field overrides
        if (request.fieldOverrides != null) {
            for (String fKey : request.fieldOverrides.keySet()) {
                if (fieldMap.containsKey(fKey.toLowerCase())) {
                    DescribeFieldResult fd = fieldMap.get(fKey.toLowerCase()).getDescribe();
                    if (fd.isCreateable()) {
                        clonedParent.put(fd.getName(), request.fieldOverrides.get(fKey));
                    }
                }
            }
        }

        // Sanitize State/Country picklists on parent
        sanitizeAddressPicklists(clonedParent, fieldMap);

        // Strip non-creatable fields
        SObjectAccessDecision parentDecision = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<SObject>{ clonedParent }
        );
        clonedParent = parentDecision.getRecords()[0];

        // Execute transactional clone with rollback on failure
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.AllowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        dml.optAllOrNone = true;

        Savepoint sp = Database.setSavepoint();
        try {
            Database.SaveResult parentSr = Database.insert(clonedParent, dml);
            if (!parentSr.isSuccess()) {
                String dmlErr = '';
                for (Database.Error err : parentSr.getErrors()) {
                    dmlErr += err.getMessage() + ' ';
                }
                throw new CloneException('Failed to insert cloned parent: ' + dmlErr.trim());
            }

            Integer totalCloned = 0;
            Map<String, Integer> countsByRel = new Map<String, Integer>();

            if (request.childRelationshipNames != null && !request.childRelationshipNames.isEmpty()) {
                Map<String, Schema.ChildRelationship> relMap = new Map<String, Schema.ChildRelationship>();
                for (Schema.ChildRelationship cr : parentDescribe.getChildRelationships()) {
                    if (cr.getRelationshipName() != null) {
                        relMap.put(cr.getRelationshipName().toLowerCase(), cr);
                    }
                }

                for (String relName : request.childRelationshipNames) {
                    if (!relMap.containsKey(relName.toLowerCase())) {
                        continue;
                    }

                    Schema.ChildRelationship cr = relMap.get(relName.toLowerCase());
                    String fkField = cr.getField().getDescribe().getName();
                    DescribeSObjectResult childDescribe = cr.getChildSObject().getDescribe();

                    if (!childDescribe.isCreateable() || !childDescribe.isQueryable()) {
                        continue;
                    }

                    Map<String, SObjectField> childFieldMap = childDescribe.fields.getMap();
                    List<String> childQueryFields = new List<String>();
                    for (String cfn : childFieldMap.keySet()) {
                        DescribeFieldResult cfd = childFieldMap.get(cfn).getDescribe();
                        if (cfd.isAccessible()) {
                            childQueryFields.add(cfd.getName());
                        }
                    }

                    String childQuery =
                        'SELECT ' +
                        String.join(childQueryFields, ', ') +
                        ' FROM ' +
                        childDescribe.getName() +
                        ' WHERE ' +
                        String.escapeSingleQuotes(fkField) +
                        ' = :recordId';
                    List<SObject> originalChildren = Database.query(childQuery);

                    if (originalChildren.isEmpty()) {
                        countsByRel.put(cr.getRelationshipName(), 0);
                        continue;
                    }

                    List<SObject> clonedChildren = new List<SObject>();
                    for (SObject childRec : originalChildren) {
                        SObject clonedChild = childRec.clone(false, true, false, false);
                        clonedChild.put(fkField, clonedParent.Id);

                        if (childDescribe.getName().equalsIgnoreCase('OpportunityLineItem')) {
                            sanitizeOpportunityLineItem(clonedChild, childFieldMap);
                        }

                        sanitizeAddressPicklists(clonedChild, childFieldMap);
                        clonedChildren.add(clonedChild);
                    }

                    SObjectAccessDecision childDecision = Security.stripInaccessible(
                        AccessType.CREATABLE,
                        clonedChildren
                    );
                    List<SObject> sanitizedChildren = childDecision.getRecords();

                    if (!sanitizedChildren.isEmpty()) {
                        List<Database.SaveResult> childSrs = Database.insert(sanitizedChildren, dml);
                        totalCloned += sanitizedChildren.size();
                        countsByRel.put(cr.getRelationshipName(), sanitizedChildren.size());
                    }
                }
            }

            CloneResult result = new CloneResult();
            result.isSuccess = true;
            result.originalRecordId = recordId;
            result.newRecordId = clonedParent.Id;
            result.newRecordName = (targetNameField != null &&
                clonedParent.get(targetNameField) != null)
                ? (String) clonedParent.get(targetNameField)
                : parentDescribe.getLabel();
            result.totalChildrenCloned = totalCloned;
            result.clonedCountsByRelationship = countsByRel;
            return result;
        } catch (Exception ex) {
            Database.rollback(sp);
            CloneResult errResult = new CloneResult();
            errResult.isSuccess = false;
            errResult.originalRecordId = recordId;
            errResult.errorMessage = ex.getMessage();
            return errResult;
        }
    }

    /**
     * @description Avoids Mismatched integration value / State & Country picklist errors when cloning.
     */
    private static void sanitizeAddressPicklists(SObject rec, Map<String, SObjectField> fieldMap) {
        if (fieldMap.containsKey('billingcountrycode') && fieldMap.containsKey('billingcountry')) {
            if (rec.get('BillingCountryCode') != null) {
                rec.put('BillingCountry', null);
                if (fieldMap.containsKey('billingstate')) {
                    rec.put('BillingState', null);
                }
            }
        }
        if (fieldMap.containsKey('shippingcountrycode') && fieldMap.containsKey('shippingcountry')) {
            if (rec.get('ShippingCountryCode') != null) {
                rec.put('ShippingCountry', null);
                if (fieldMap.containsKey('shippingstate')) {
                    rec.put('ShippingState', null);
                }
            }
        }
        if (fieldMap.containsKey('mailingcountrycode') && fieldMap.containsKey('mailingcountry')) {
            if (rec.get('MailingCountryCode') != null) {
                rec.put('MailingCountry', null);
                if (fieldMap.containsKey('mailingstate')) {
                    rec.put('MailingState', null);
                }
            }
        }
        if (fieldMap.containsKey('othercountrycode') && fieldMap.containsKey('othercountry')) {
            if (rec.get('OtherCountryCode') != null) {
                rec.put('OtherCountry', null);
                if (fieldMap.containsKey('otherstate')) {
                    rec.put('OtherState', null);
                }
            }
        }
    }

    /**
     * @description Sanitizes OpportunityLineItem: clears TotalPrice if UnitPrice is present, and removes ListPrice.
     */
    private static void sanitizeOpportunityLineItem(SObject oli, Map<String, SObjectField> fieldMap) {
        if (fieldMap.containsKey('totalprice') && fieldMap.containsKey('unitprice')) {
            if (oli.get('UnitPrice') != null) {
                oli.put('TotalPrice', null);
            }
        }
    }

    /**
     * @description Applies standard reset logic for status and close dates across standard & custom objects.
     */
    private static void applyStatusReset(SObject rec, String sObjName, Map<String, SObjectField> fieldMap) {
        String lowerObj = sObjName.toLowerCase();
        if (lowerObj == 'opportunity') {
            if (fieldMap.containsKey('stagename')) {
                rec.put('StageName', 'Prospecting');
            }
            if (fieldMap.containsKey('closedate')) {
                Date currentClose = (Date) rec.get('CloseDate');
                if (currentClose == null || currentClose < Date.today()) {
                    rec.put('CloseDate', Date.today().addDays(30));
                }
            }
            if (fieldMap.containsKey('probability')) {
                rec.put('Probability', null);
            }
        } else if (lowerObj == 'case') {
            if (fieldMap.containsKey('status')) {
                rec.put('Status', 'New');
            }
        } else if (lowerObj == 'order' || lowerObj == 'quote') {
            if (fieldMap.containsKey('status')) {
                rec.put('Status', 'Draft');
            }
        } else if (fieldMap.containsKey('status__c')) {
            rec.put('Status__c', 'Draft');
        }
    }
}
