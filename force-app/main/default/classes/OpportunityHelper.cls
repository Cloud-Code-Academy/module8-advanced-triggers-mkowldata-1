public with sharing class OpportunityHelper {
    //if (Trigger.isUpdate && Trigger.isBefore)
    public static void amountValidation(List<Opportunity> opportunities) {
        if (opportunities == null) {
            return;
        }
        for (Opportunity opp : opportunities) {
            if (opp.amount < 5000) {
            opp.addError('Opportunity amount must be greater than 5000');
            }
        }
    }

    public static void preventDeleteClosedOpp(List<Opportunity> opportunities) {
        //if (Trigger.isDelete)
         Set<Id> oppIds = new Map<Id, Opportunity>(opportunities).keyset();

        // query a list of opportunities with accounts that fit the criteria
        List<Opportunity> closedOpps = [SELECT Id, StageName, AccountId, Account.Industry, IsClosed
                                                              FROM Opportunity
                                                              WHERE Id In :oppIds
                                                              AND IsClosed = true
                                                              WITH SECURITY_ENFORCED];
        
        // create a Map to store the Opportunity information for each opportunity ID
        Map<Id, Opportunity> oppIdToOpportunity= new Map<Id, Opportunity>(closedOpps);
        
        // loop through opportunities list to see if the Id is in the Map (fits criteria for error message)
        for (Opportunity opp : opportunities) {
            if (oppIdToOpportunity.containsKey(opp.Id)) {
                Opportunity queriedOpp = oppIdToOpportunity.get(opp.Id);

                if (queriedOpp.StageName =='Closed Won' && queriedOpp.Account.Industry == 'Banking' && queriedOpp.isClosed == true) {
                opp.addError('Cannot delete closed opportunity for a banking account that is won');
            }
            else if (opp.isClosed == true) {
                opp.addError('Cannot delete closed opportunity');
            }
        }
    }
}

    public static void setDefaultOpportunityType(List<Opportunity> opportunities) {
        //if (Trigger.isBefore && Trigger.isInsert)
        if (opportunities == null) {
            return;
        }
        for (Opportunity opp : opportunities) {
            if (opp.Type == null) {
                opp.Type = 'New Customer';
            }
        }
    }

    public static void setPrimaryContactOnOpportunityToAccountCEO(List<Opportunity> opportunities) {
        //if (Trigger.isUpdate && Trigger.isBefore)
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
        Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

        for (Contact cont : contacts.values()) {
            if (!accountIdToContact.containsKey(cont.AccountId)) {
                accountIdToContact.put(cont.AccountId, cont);
            }
        }

        for(Opportunity opp : opportunities){
            if (opp.Primary_Contact__c == null) {
                if (accountIdToContact.containsKey(opp.AccountId)) {
                    opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                }
            }
        }
    }

    public static void createTaskForNewOpportunity(List<Opportunity> opportunities) {
        //Trigger.isAfter && Trigger.isInsert
        List<Task> newOpportunityTask = new List<Task>();

        for (Opportunity opp : opportunities) {
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            newOpportunityTask.add(tsk);
        }
        insert newOpportunityTask;
    }

    public static void appendStageChangeDescription(List<Opportunity> opportunities, Map<Id, Opportunity> oldMap) {
        //Trigger.isBefore && Trigger.isUpdate
        
        for (Opportunity opp : opportunities) {
            //get the old version from the map we are passing in
            Opportunity oldOpp = oldMap.get(opp.Id);

            // check to see if StageName was changed
            if (opp.StageName != null && oldOpp.StageName != null && opp.StageName != oldOpp.StageName) {
                String currentDesc;
                if(opp.Description != null) {
                    currentDesc = opp.Description;
                } else {
                    currentDesc = '';
                }
                opp.Description = currentDesc + '\n Stage Change:'  + opp.StageName + ': '+ DateTime.now().format();
            }             
        }
    }

    public static void deletedOpportunity(List<Opportunity> opportunities) {
        notifyOwnersOpportunityDeleted(opportunities); 

    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opportunities) {
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            ownerIds.add(opp.OwnerId);
        }
        // get a list of Users
        List<User> userList = [SELECT Id, Email FROM User WHERE Id IN:ownerIds];
        // create a Map of user Id to User
        Map<Id, User> IdUserMap = new Map<Id, User>();
        for (User users : userList) {
            IdUserMap.put(users.Id, users);
        }
        for (Opportunity opp : opportunities) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            String ownerEmail = IdUserMap.get(opp.OwnerId).Email;
            List<String> toAddresses = new List<String> {ownerEmail};
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
            mails.add(mail);
        }        
        
        try {
            Messaging.sendEmail(mails);
        } catch (Exception e){
            System.debug('Exception: ' + e.getMessage());
        }
    }

    /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
    public static void undeletedOpportunityAssignPrimaryContact(Map<Id,Opportunity> oppNewMap) {
        assignPrimaryContact(oppNewMap); 

    }

    private static void assignPrimaryContact(Map<Id,Opportunity> oppNewMap) {        
        // map used to store opps to be updated
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
        // create a set to pull the accountIds for opps
        Set<Id> accountIds = new Set<Id>();

        for (Opportunity opp : oppNewMap.values()) {
            accountIds.add(opp.AccountId);
        }
        //now that we have a set of accountIds lets grab the contacts associated with the AccountIds
        List<Contact> primaryContacts = [SELECT Id, Name, Title, AccountId FROM Contact WHERE AccountId IN : accountIds AND Title = 'VP Sales'];
        //Add the AccountId and Contact to a map
        Map<Id, Contact> accountIdsToContact = new Map<Id, Contact>();

        for (Contact cont : primaryContacts) {
            accountIdsToContact.put(cont.AccountId, cont);
        }
        // check if the opportunity has a primary contact
        // create a list to store opps to update
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        for (Opportunity opp : oppNewMap.values()) {            
            if (opp.Primary_Contact__c == null) {
                //assign the opp to update
                Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                Contact primaryContact = accountIdsToContact.get(opp.AccountId);
                oppToUpdate.Primary_Contact__c = primaryContact.Id;
                oppsToUpdate.add(oppToUpdate);
            }
        }
        update oppsToUpdate;
    }
}