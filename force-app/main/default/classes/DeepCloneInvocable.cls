/**
 * @description Invocable Action for deep cloning records from Salesforce Flows and Process Builder.
 */
public with sharing class DeepCloneInvocable {
    public class InvocableRequest {
        @InvocableVariable(label='Source Record ID' description='ID of the record to clone' required=true)
        public Id recordId;

        @InvocableVariable(
            label='New Record Name'
            description='Optional custom name for the cloned parent record'
            required=false
        )
        public String newRecordName;

        @InvocableVariable(
            label='Child Relationships CSV'
            description='Comma-separated child relationship names to clone (or ALL to clone all with records)'
            required=false
        )
        public String childRelationshipsCsv;

        @InvocableVariable(
            label='Reset Status'
            description='Whether to reset status (e.g. Prospecting, Draft, New)'
            required=false
        )
        public Boolean resetStatus;
    }

    public class InvocableResult {
        @InvocableVariable(label='New Cloned Record ID' description='ID of the newly created clone')
        public Id clonedRecordId;

        @InvocableVariable(label='New Record Name' description='Name of the cloned record')
        public String clonedRecordName;

        @InvocableVariable(label='Is Success' description='True if clone succeeded')
        public Boolean isSuccess;

        @InvocableVariable(label='Total Children Cloned' description='Count of child records cloned')
        public Integer totalChildrenCloned;

        @InvocableVariable(label='Error Message' description='Error details if clone failed')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Smart Deep Clone Record'
        description='Deep clones a record and selected child relationships'
        category='Record Operations'
    )
    public static List<InvocableResult> execute(List<InvocableRequest> requests) {
        List<InvocableResult> results = new List<InvocableResult>();
        if (requests == null) {
            return results;
        }

        for (InvocableRequest req : requests) {
            InvocableResult invResult = new InvocableResult();
            try {
                DeepCloneService.CloneRequest cloneReq = new DeepCloneService.CloneRequest();
                cloneReq.recordId = req.recordId;
                cloneReq.newRecordName = req.newRecordName;
                cloneReq.resetStatus = req.resetStatus != null ? req.resetStatus : false;

                if (String.isNotBlank(req.childRelationshipsCsv)) {
                    if (req.childRelationshipsCsv.trim().equalsIgnoreCase('ALL')) {
                        DeepCloneService.CloneConfig cfg = DeepCloneService.getCloneConfig(req.recordId);
                        for (DeepCloneService.ChildRelationshipMeta meta : cfg.childRelationships) {
                            if (meta.recordCount > 0) {
                                cloneReq.childRelationshipNames.add(meta.relationshipName);
                            }
                        }
                    } else {
                        for (String part : req.childRelationshipsCsv.split(',')) {
                            if (String.isNotBlank(part)) {
                                cloneReq.childRelationshipNames.add(part.trim());
                            }
                        }
                    }
                }

                DeepCloneService.CloneResult res = DeepCloneService.deepClone(cloneReq);
                invResult.isSuccess = res.isSuccess;
                invResult.clonedRecordId = res.newRecordId;
                invResult.clonedRecordName = res.newRecordName;
                invResult.totalChildrenCloned = res.totalChildrenCloned;
                invResult.errorMessage = res.errorMessage;
            } catch (Exception ex) {
                invResult.isSuccess = false;
                invResult.errorMessage = ex.getMessage();
                invResult.totalChildrenCloned = 0;
            }
            results.add(invResult);
        }
        return results;
    }
}
