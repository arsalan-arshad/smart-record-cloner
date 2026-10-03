/**
 * @description Lightning Controller for Smart Record Cloner LWC.
 * Exposes methods to retrieve clone configuration/metadata and execute deep clone transactions.
 */
public with sharing class DeepCloneController {
    @AuraEnabled(cacheable=true)
    public static DeepCloneService.CloneConfig getCloneConfig(Id recordId) {
        try {
            return DeepCloneService.getCloneConfig(recordId);
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());
            ahe.setMessage(ex.getMessage());
            throw ahe;
        }
    }

    @AuraEnabled
    public static DeepCloneService.CloneResult cloneRecord(
        Id recordId,
        String newRecordName,
        List<String> childRelationshipNames,
        Boolean resetStatus,
        Map<String, Object> fieldOverrides
    ) {
        try {
            DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
            req.recordId = recordId;
            req.newRecordName = newRecordName;
            req.childRelationshipNames = childRelationshipNames;
            req.resetStatus = resetStatus != null ? resetStatus : false;
            req.fieldOverrides = fieldOverrides;

            DeepCloneService.CloneResult result = DeepCloneService.deepClone(req);
            if (!result.isSuccess) {
                throw new AuraHandledException(result.errorMessage);
            }
            return result;
        } catch (Exception ex) {
            AuraHandledException ahe = new AuraHandledException(ex.getMessage());
            ahe.setMessage(ex.getMessage());
            throw ahe;
        }
    }
}
