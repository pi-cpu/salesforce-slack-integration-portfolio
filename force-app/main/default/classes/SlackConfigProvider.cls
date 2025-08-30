public with sharing class SlackConfigProvider {
    /** 設定用の軽量DTO（外部クラスから参照するので public） */
    public class Conf {
        public Boolean enabled = true;                 // 既定ON
        public Decimal minAmount;                      // nullなら金額判定なし
        public Set<String> targetStages = new Set<String>(); // 空ならステージ判定なし
    }

    /**
     * Custom Metadata: Slack_Config__mdt（DeveloperName='Default' を想定）
     * 無ければ安全デフォルトで返す
     */
    public static Conf load() {
        Conf c = new Conf();

        try {
            Slack_Config__mdt m = Slack_Config__mdt.getInstance('Default');
            if (m == null) return c;

            // Enabled
            if (m.Enabled__c != null) c.enabled = m.Enabled__c;

            // MinAmount
            if (m.MinAmount__c != null) c.minAmount = m.MinAmount__c;

            // TargetStages（カンマ区切り）
            c.targetStages.clear();
            if (m.TargetStages__c != null && m.TargetStages__c.trim().length() > 0) {
                for (String s : m.TargetStages__c.split('\\s*,\\s*')) {
                    if (!String.isBlank(s)) c.targetStages.add(s.trim());
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CMDT load failed: ' + e.getMessage());
        }
        return c;
    }
}
