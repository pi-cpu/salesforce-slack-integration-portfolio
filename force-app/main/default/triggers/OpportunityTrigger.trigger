trigger OpportunityTrigger on Opportunity (after insert, after update) {
    // 対象IDを集める（フェーズ変更 or 金額変更）
    Set<Id> changed = new Set<Id>();
    if (Trigger.isUpdate) {
        for (Opportunity newOpp : Trigger.new) {
            Opportunity oldOpp = Trigger.oldMap.get(newOpp.Id);
            if (newOpp.StageName != oldOpp.StageName || newOpp.Amount != oldOpp.Amount) {
                changed.add(newOpp.Id);
            }
        }
    } else if (Trigger.isInsert) {
        for (Opportunity opp : Trigger.new) changed.add(opp.Id);
    }
    if (changed.isEmpty()) return;

    // Queueable を1回だけ起動（バルク安全）
    System.enqueueJob(new SlackNotificationHandler.QueueJob(new List<Id>(changed)));
}
