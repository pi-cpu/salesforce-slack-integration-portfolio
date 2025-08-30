public with sharing class SlackConfigProvider {
    /** 設定DTO（軽量） */
    public class Conf {
        public Boolean enabled = true;
        public Decimal minAmount;                      // nullで金額判定なし
        public Set<String> targetStages = new Set<String>(); // 空でステージ判定なし
    }

    /**
     * CMDT: Slack_Config__mdt
     * - DeveloperName='Default' を1件用意（推奨）
     * - 将来的に複数レコード運用する場合は、ここで統合ロジックを追加（例：OR結合）
     */
    public static Conf load() {
        Conf c = new Conf();

        try {
            // 代表1件だけ使うパターン（最小構成）
            Slack_Config__mdt m = Slack_Config__mdt.getInstance('Default');
            if (m != null) {
                if (m.Enabled__c != null) c.enabled = m.Enabled__c;
                if (m.MinAmount__c != null) c.minAmount = m.MinAmount__c;

                c.targetStages.clear();
                if (!String.isBlank(m.TargetStages__c)) {
                    for (String s : m.TargetStages__c.split('\\s*,\\s*')) {
                        if (!String.isBlank(s)) c.targetStages.add(s.trim());
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CMDT load failed: ' + e.getMessage());
        }
        return c;
    }
}
