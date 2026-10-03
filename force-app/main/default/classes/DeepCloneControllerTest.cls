@isTest
private class DeepCloneControllerTest {
    @testSetup
    static void setupTestData() {
        Account testAcc = new Account(Name = 'Universal Containers', BillingCity = 'New York');
        Map<String, SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        if (
            accFields.containsKey('BillingCountryCode') &&
            accFields.get('BillingCountryCode').getDescribe().isCreateable()
        ) {
            testAcc.put('BillingCountryCode', 'US');
            testAcc.put('BillingStateCode', 'NY');
        } else if (
            accFields.containsKey('BillingCountry') && accFields.get('BillingCountry').getDescribe().isCreateable()
        ) {
            testAcc.put('BillingCountry', 'United States');
            testAcc.put('BillingState', 'New York');
        }
        insert testAcc;

        Contact testContact = new Contact(
            FirstName = 'Sarah',
            LastName = 'Connor',
            Email = 'sarah@universal.test',
            AccountId = testAcc.Id
        );
        insert testContact;
    }

    @isTest
    static void testGetCloneConfigSuccess() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        Test.startTest();
        DeepCloneService.CloneConfig config = DeepCloneController.getCloneConfig(acc.Id);
        Test.stopTest();

        Assert.areNotEqual(null, config);
        Assert.areEqual(acc.Id, config.recordId);
        Assert.areEqual('Universal Containers', config.recordName);
    }

    @isTest
    static void testGetCloneConfigError() {
        try {
            Test.startTest();
            DeepCloneController.getCloneConfig(null);
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ahe) {
            Assert.isTrue(ahe != null, 'Caught expected AuraHandledException');
        }
    }

    @isTest
    static void testCloneRecordSuccess() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        Test.startTest();
        DeepCloneService.CloneResult res = DeepCloneController.cloneRecord(
            acc.Id,
            'Universal Containers (Branch)',
            new List<String>{ 'Contacts' },
            false,
            null,
            0,
            null,
            false
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess);
        Assert.areNotEqual(null, res.newRecordId);
        Assert.areEqual(1, res.totalChildrenCloned);
    }

    @isTest
    static void testCloneRecordFailure() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];
        delete acc;

        try {
            Test.startTest();
            DeepCloneController.cloneRecord(acc.Id, 'Fail Test', null, false, null, 0, null, false);
            Test.stopTest();
            Assert.fail('Expected AuraHandledException on deleted record');
        } catch (AuraHandledException ahe) {
            Assert.isTrue(ahe != null);
        }
    }

    @isTest
    static void testDeepCloneInvocableSuccess() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        DeepCloneInvocable.InvocableRequest req = new DeepCloneInvocable.InvocableRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Invocable Copy';
        req.childRelationshipsCsv = 'Contacts';
        req.resetStatus = false;

        Test.startTest();
        List<DeepCloneInvocable.InvocableResult> results = DeepCloneInvocable.execute(
            new List<DeepCloneInvocable.InvocableRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(1, results[0].totalChildrenCloned);
        Assert.areNotEqual(null, results[0].clonedRecordId);
    }

    @isTest
    static void testDeepCloneInvocableAllChildren() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        DeepCloneInvocable.InvocableRequest req = new DeepCloneInvocable.InvocableRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Invocable All Copy';
        req.childRelationshipsCsv = 'ALL';

        Test.startTest();
        List<DeepCloneInvocable.InvocableResult> results = DeepCloneInvocable.execute(
            new List<DeepCloneInvocable.InvocableRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].isSuccess);
        Assert.isTrue(results[0].totalChildrenCloned >= 1);
    }

    @isTest
    static void testDeepCloneInvocableNullRequest() {
        Test.startTest();
        List<DeepCloneInvocable.InvocableResult> results = DeepCloneInvocable.execute(null);
        Test.stopTest();

        Assert.areEqual(0, results.size());
    }

    @isTest
    static void testDeepCloneInvocableError() {
        DeepCloneInvocable.InvocableRequest req = new DeepCloneInvocable.InvocableRequest();
        req.recordId = null;

        Test.startTest();
        List<DeepCloneInvocable.InvocableResult> results = DeepCloneInvocable.execute(
            new List<DeepCloneInvocable.InvocableRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isFalse(results[0].isSuccess);
        Assert.areNotEqual(null, results[0].errorMessage);
    }

    @isTest
    static void testCloneRecordException() {
        try {
            Test.startTest();
            DeepCloneController.cloneRecord(null, 'Fail', null, false, null, 0, null, false);
            Test.stopTest();
            Assert.fail('Expected AuraHandledException on null recordId');
        } catch (AuraHandledException ahe) {
            Assert.isTrue(ahe != null);
        }
    }

    @isTest
    static void testCloneRecordWithDifferentiatorParams() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        Test.startTest();
        DeepCloneService.CloneResult res = DeepCloneController.cloneRecord(
            acc.Id,
            'Universal Containers (Advanced)',
            new List<String>{ 'Contacts' },
            false,
            null,
            30,
            '(Copy)',
            true
        );
        Test.stopTest();

        Assert.isTrue(res.isSuccess);
        Assert.areNotEqual(null, res.newRecordId);
        Assert.areEqual(1, res.totalChildrenCloned);
    }

    @isTest
    static void testDeepCloneInvocableWithDifferentiators() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Universal Containers' LIMIT 1];

        DeepCloneInvocable.InvocableRequest req = new DeepCloneInvocable.InvocableRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Invocable AI Copy';
        req.childRelationshipsCsv = 'Contacts';
        req.resetStatus = false;
        req.dateShiftDays = 45;
        req.childNameSuffix = '[AI Clone]';
        req.onlyActiveChildren = true;

        Test.startTest();
        List<DeepCloneInvocable.InvocableResult> results = DeepCloneInvocable.execute(
            new List<DeepCloneInvocable.InvocableRequest>{ req }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].isSuccess);
        Assert.areEqual(1, results[0].totalChildrenCloned);
    }
}
