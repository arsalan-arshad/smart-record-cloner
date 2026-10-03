@isTest
private class DeepCloneServiceTest {
    @testSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Acme Test Corp',
            BillingCity = 'San Francisco',
            Phone = '555-1234',
            Website = 'https://acme.test'
        );
        Map<String, SObjectField> accFields = Schema.SObjectType.Account.fields.getMap();
        if (
            accFields.containsKey('BillingCountryCode') &&
            accFields.get('BillingCountryCode').getDescribe().isCreateable()
        ) {
            testAcc.put('BillingCountryCode', 'US');
            testAcc.put('BillingStateCode', 'CA');
        } else if (
            accFields.containsKey('BillingCountry') && accFields.get('BillingCountry').getDescribe().isCreateable()
        ) {
            testAcc.put('BillingCountry', 'United States');
            testAcc.put('BillingState', 'California');
        }
        insert testAcc;

        List<Contact> testContacts = new List<Contact>{
            new Contact(FirstName = 'Alice', LastName = 'Smith', Email = 'alice@acme.test', AccountId = testAcc.Id),
            new Contact(FirstName = 'Bob', LastName = 'Jones', Email = 'bob@acme.test', AccountId = testAcc.Id)
        };
        insert testContacts;

        List<Opportunity> testOpps = new List<Opportunity>{
            new Opportunity(
                Name = 'Acme Deal Q1',
                StageName = 'Closed Won',
                CloseDate = Date.today().addDays(-10),
                AccountId = testAcc.Id
            ),
            new Opportunity(
                Name = 'Acme Active Pipeline',
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(20),
                AccountId = testAcc.Id
            )
        };
        insert testOpps;
    }

    @isTest
    static void testGetCloneConfigSuccess() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        Test.startTest();
        DeepCloneService.CloneConfig config = DeepCloneService.getCloneConfig(acc.Id);
        Test.stopTest();

        Assert.areNotEqual(null, config, 'Config should not be null');
        Assert.areEqual(acc.Id, config.recordId, 'Record ID should match');
        Assert.areEqual('Account', config.sObjectName, 'SObject name should be Account');
        Assert.areEqual('Acme Test Corp', config.recordName, 'Record name should match');
        Assert.areEqual(
            'Clone of Acme Test Corp',
            config.defaultNewRecordName,
            'Default clone name should prefix Clone of'
        );
        Assert.isTrue(config.childRelationships.size() > 0, 'Should find child relationships');

        Boolean foundContacts = false;
        for (DeepCloneService.ChildRelationshipMeta rel : config.childRelationships) {
            if (rel.relationshipName == 'Contacts') {
                foundContacts = true;
                Assert.areEqual(2, rel.recordCount, 'Should detect 2 contacts');
                Assert.isTrue(rel.isDefaultSelected, 'Contacts should be default selected');
            }
        }
        Assert.isTrue(foundContacts, 'Should include Contacts relationship');
    }

    @isTest
    static void testGetCloneConfigNullId() {
        try {
            DeepCloneService.getCloneConfig(null);
            Assert.fail('Expected CloneException on null recordId');
        } catch (DeepCloneService.CloneException ex) {
            Assert.isTrue(ex.getMessage().contains('cannot be null'), 'Message should indicate null recordId');
        }
    }

    @isTest
    static void testDeepCloneWithChildRecords() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Acme Test Corp (Cloned)';
        req.childRelationshipNames = new List<String>{ 'Contacts' };

        Test.startTest();
        DeepCloneService.CloneResult result = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Clone should succeed: ' + result.errorMessage);
        Assert.areNotEqual(null, result.newRecordId, 'New record ID must be generated');
        Assert.areNotEqual(acc.Id, result.newRecordId, 'New record ID must be different from source');
        Assert.areEqual(2, result.totalChildrenCloned, 'Should clone 2 contacts');
        Assert.areEqual(2, result.clonedCountsByRelationship.get('Contacts'), 'Counts map should show 2 contacts');

        Account clonedAcc = [SELECT Id, Name, Phone FROM Account WHERE Id = :result.newRecordId];
        Assert.areEqual('Acme Test Corp (Cloned)', clonedAcc.Name, 'Cloned account name should match newRecordName');
        Assert.areEqual('555-1234', clonedAcc.Phone, 'Phone field should carry over');

        List<Contact> clonedContacts = [
            SELECT Id, FirstName, LastName, Email, AccountId
            FROM Contact
            WHERE AccountId = :result.newRecordId
        ];
        Assert.areEqual(2, clonedContacts.size(), 'Should have inserted 2 contacts linked to cloned account');
    }

    @isTest
    static void testDeepCloneOpportunityWithResetStatus() {
        Opportunity opp = [SELECT Id, Name, StageName, CloseDate FROM Opportunity WHERE Name = 'Acme Deal Q1' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = opp.Id;
        req.newRecordName = 'Acme Deal Q1 (Renewal)';
        req.resetStatus = true;

        Test.startTest();
        DeepCloneService.CloneResult result = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Clone should succeed: ' + result.errorMessage);
        Opportunity clonedOpp = [SELECT Id, Name, StageName, CloseDate FROM Opportunity WHERE Id = :result.newRecordId];
        Assert.areEqual('Acme Deal Q1 (Renewal)', clonedOpp.Name);
        Assert.areEqual('Prospecting', clonedOpp.StageName, 'Stage should be reset to Prospecting');
        Assert.isTrue(clonedOpp.CloseDate >= Date.today(), 'CloseDate should be reset to future date');
    }

    @isTest
    static void testDeepCloneWithFieldOverrides() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Acme Partner';
        req.fieldOverrides = new Map<String, Object>{ 'Website' => 'https://partner.acme.test', 'Phone' => '555-9999' };

        Test.startTest();
        DeepCloneService.CloneResult result = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Clone should succeed');
        Account clonedAcc = [SELECT Website, Phone FROM Account WHERE Id = :result.newRecordId];
        Assert.areEqual('https://partner.acme.test', clonedAcc.Website, 'Website should be overridden');
        Assert.areEqual('555-9999', clonedAcc.Phone, 'Phone should be overridden');
    }

    @isTest
    static void testDeepCloneNullRequest() {
        try {
            DeepCloneService.deepClone(null);
            Assert.fail('Expected exception on null request');
        } catch (DeepCloneService.CloneException ex) {
            Assert.isTrue(ex.getMessage().contains('required'), 'Should indicate request is required');
        }
    }

    @isTest
    static void testDeepCloneParentOnly() {
        Account acc = [SELECT Id, Name FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Acme Solo Parent';
        req.childRelationshipNames = new List<String>();

        Test.startTest();
        DeepCloneService.CloneResult result = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Clone should succeed');
        Assert.areEqual(0, result.totalChildrenCloned, 'No children should be cloned');
    }

    @isTest
    static void testChildRelationshipMetaComparator() {
        DeepCloneService.ChildRelationshipMeta rel1 = new DeepCloneService.ChildRelationshipMeta();
        rel1.childLabel = 'Contacts';
        rel1.recordCount = 5;

        DeepCloneService.ChildRelationshipMeta rel2 = new DeepCloneService.ChildRelationshipMeta();
        rel2.childLabel = 'Cases';
        rel2.recordCount = 2;

        DeepCloneService.ChildRelationshipMeta rel3 = new DeepCloneService.ChildRelationshipMeta();
        rel3.childLabel = 'Assets';
        rel3.recordCount = 0;

        List<DeepCloneService.ChildRelationshipMeta> listMeta = new List<DeepCloneService.ChildRelationshipMeta>{
            rel3,
            rel2,
            rel1
        };
        listMeta.sort();

        Assert.areEqual('Contacts', listMeta[0].childLabel, 'Highest record count should be first');
        Assert.areEqual('Cases', listMeta[1].childLabel, 'Second highest record count should be second');
        Assert.areEqual('Assets', listMeta[2].childLabel, 'Zero count should be last');
    }

    @isTest
    static void testDeepCloneCase() {
        Case testCase = new Case(Subject = 'Issue with router', Status = 'Working', Origin = 'Web');
        insert testCase;

        DeepCloneService.CloneConfig config = DeepCloneService.getCloneConfig(testCase.Id);
        Assert.areEqual('Case', config.sObjectName);
        Assert.areEqual('Issue with router', config.recordName);
        Assert.isTrue(config.isNameEditable);

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = testCase.Id;
        req.newRecordName = 'Cloned Router Issue';
        req.resetStatus = true;

        Test.startTest();
        DeepCloneService.CloneResult res = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(res.isSuccess);
        Case clonedCase = [SELECT Subject, Status FROM Case WHERE Id = :res.newRecordId];
        Assert.areEqual('Cloned Router Issue', clonedCase.Subject);
        Assert.areEqual('New', clonedCase.Status);
    }

    @isTest
    static void testDeepCloneWithDateShiftAndChildSuffix() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Shifted Acme Corp';
        req.childRelationshipNames = new List<String>{ 'Opportunities', 'Contacts' };
        req.dateShiftDays = 30;
        req.childNameSuffix = '[Clone]';
        req.onlyActiveChildren = false;

        Test.startTest();
        DeepCloneService.CloneResult res = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Clone should succeed');
        List<Opportunity> clonedOpps = [
            SELECT Name, CloseDate
            FROM Opportunity
            WHERE AccountId = :res.newRecordId
        ];
        Assert.isTrue(clonedOpps.size() > 0, 'Should have cloned opportunities');
        for (Opportunity opp : clonedOpps) {
            Assert.isTrue(opp.Name.endsWith('[Clone]'), 'Opportunity name should end with [Clone]');
        }
    }

    @isTest
    static void testDeepCloneWithActiveOnlyFilter() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Test Corp' LIMIT 1];

        DeepCloneService.CloneRequest req = new DeepCloneService.CloneRequest();
        req.recordId = acc.Id;
        req.newRecordName = 'Active Only Acme Corp';
        req.childRelationshipNames = new List<String>{ 'Opportunities' };
        req.onlyActiveChildren = true;

        Test.startTest();
        DeepCloneService.CloneResult res = DeepCloneService.deepClone(req);
        Test.stopTest();

        Assert.isTrue(res.isSuccess, 'Clone should succeed');
        List<Opportunity> clonedOpps = [
            SELECT Name, StageName
            FROM Opportunity
            WHERE AccountId = :res.newRecordId
        ];
        Assert.isTrue(clonedOpps.size() > 0, 'Should have cloned active opportunity');
        for (Opportunity opp : clonedOpps) {
            Assert.areNotEqual('Closed Won', opp.StageName, 'Closed deal must not be cloned');
        }
    }
}
