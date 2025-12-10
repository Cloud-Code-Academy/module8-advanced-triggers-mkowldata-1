public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    public override void beforeUpdate() {
        OpportunityHelper.amountValidation(Trigger.new);
        OpportunityHelper.setPrimaryContactOnOpportunityToAccountCEO(Trigger.new);
        OpportunityHelper.appendStageChangeDescription((List<Opportunity>)Trigger.new, (Map<Id, Opportunity>)Trigger.oldMap);
        
    }

    public override void beforeDelete() {
        OpportunityHelper.preventDeleteClosedOpp(Trigger.old);
    }

    public override void beforeInsert() {
        OpportunityHelper.setDefaultOpportunityType(Trigger.new);
    }

    public override void afterInsert() {
        OpportunityHelper.createTaskForNewOpportunity(Trigger.new);
    }

    public override void afterDelete() {
        OpportunityHelper.deletedOpportunity(Trigger.old);
    }

    public override void afterUndelete() {
        OpportunityHelper.undeletedOpportunityAssignPrimaryContact((Map<Id, Opportunity>)Trigger.newMap);
    }
}