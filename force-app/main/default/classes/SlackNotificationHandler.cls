public with sharing class SlackNotificationHandler {

    public static void handleAfter(List<Opportunity> news, Map<Id, Opportunity> oldMap) {
        SlackConfigProvider.Conf conf = SlackConfigProvider.load();
        if (!conf.enabled) return;

        List<Opportunity> targets = new List<Opportunity>();
        for (Opportunity opp : news) {
            Opportunity oldOpp = (oldMap == null) ? null : oldMap.get(opp.Id);
            Boolean changed = (oldOpp == null)
                ? true
                : (opp.StageName != oldOpp.StageName || opp.Amount != oldOpp.Amount);
            if (!changed) continue;

            if (conf.minAmount != null && opp.Amount != null && opp.Amount < conf.minAmount) continue;
            if (!conf.targetStages.isEmpty() && !conf.targetStages.contains(opp.StageName)) continue;

            targets.add(opp);
        }
        if (targets.isEmpty()) return;

        // 1レコード=3ブロック（divider / section / actions）
        List<Object> blocks = new List<Object>();
        for (Opportunity opp : targets) {
            String url = makeRecordUrl('Opportunity', opp.Id);

            blocks.add(divider());
            blocks.add(sectionText('*商談更新* : ' + safe(opp.Name)
                + '\nフェーズ: ' + safe(opp.StageName)
                + '\n金額: ' + (opp.Amount == null ? '-' : String.valueOf(opp.Amount))));

            blocks.add(actionOpenButton('Salesforceで開く', url));
        }

        // 1メッセージあたりの安全上限（例: 45ブロック ≒ 15件分）
        List<List<Object>> chunked = chunkBlocks(blocks, 45);
        System.enqueueJob(new QueueJob(chunked));
    }

    public class QueueJob implements Queueable, Database.AllowsCallouts {
        private List<List<Object>> chunks;
        public QueueJob(List<List<Object>> chunks) { this.chunks = chunks; }
        public void execute(QueueableContext qc) {
            for (List<Object> b : chunks) doPost(JSON.serialize(new Map<String,Object>{ 'blocks' => b }));
        }
    }

    // ==== Block Kit helpers ====
    private static Map<String,Object> divider() {
        return new Map<String,Object>{ 'type' => 'divider' };
    }
    private static Map<String,Object> sectionText(String md) {
        return new Map<String,Object>{
            'type' => 'section',
            'text' => new Map<String,Object>{ 'type' => 'mrkdwn', 'text' => md }
        };
    }
    private static Map<String,Object> actionOpenButton(String label, String url) {
        return new Map<String,Object>{
            'type' => 'actions',
            'elements' => new List<Object>{
                new Map<String,Object>{
                    'type' => 'button',
                    'text' => new Map<String,Object>{ 'type' => 'plain_text', 'text' => label },
                    'url'  => url,
                    'style'=> 'primary' // 任意
                }
            }
        };
    }

    // ==== Util ====
    private static String safe(String s) { return s == null ? '-' : s; }

    private static List<List<Object>> chunkBlocks(List<Object> blocks, Integer maxPerMessage) {
        List<List<Object>> out = new List<List<Object>>();
        List<Object> buf = new List<Object>();
        for (Object b : blocks) {
            if (buf.size() >= maxPerMessage) { out.add(buf); buf = new List<Object>(); }
            buf.add(b);
        }
        if (!buf.isEmpty()) out.add(buf);
        return out;
    }

    // Lightningレコード画面URLを動的生成
    @TestVisible private static String makeRecordUrl(String sobjectApiName, Id recordId) {
        // 例: https://xxx.lightning.force.com/lightning/r/Opportunity/006XXXXXXXXXXXX/view
        String base = URL.getSalesforceBaseUrl().toExternalForm();
        return base + '/lightning/r/' + sobjectApiName + '/' + recordId + '/view';
    }

    // Named Credential（外部ログイン情報）: callout:Slack_Webhook を使用
    @TestVisible private static void doPost(String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Slack_Webhook');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json; charset=utf-8');
        req.setBody(body);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            System.debug(LoggingLevel.ERROR, 'Slack POST failed status=' + res.getStatus() + ' body=' + res.getBody());
        }
    }
}
