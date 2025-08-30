public with sharing class SlackNotificationHandler implements System.Queueable, Database.AllowsCallouts {
    
    private Set<Id> oppIds;
    public SlackNotificationHandler(Set<Id> oppIds) { this.oppIds = oppIds; }

    public void execute(QueueableContext qc) {
        postOpportunities(oppIds);
    }

    // 文字列がnull/空白なら代替値を返す
    private static String nvl(String val, String alt) {
        return String.isBlank(val) ? alt : val;
    }

    // 公開API：商談IDの束をBlock Kitでまとめて送る
    public static void postOpportunities(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) return;

        // 設定（CMDT）を読み込み
        SlackConfigProvider.Conf conf = SlackConfigProvider.load();
        if (conf == null || conf.enabled == false) return;

        // 関連を一括取得（Account/Owner）
        List<Opportunity> opps = [
            SELECT Id, Name, Amount, StageName, Probability, Account.Name, Owner.Name, LastModifiedDate
            FROM Opportunity
            WHERE Id IN :oppIds
            ORDER BY LastModifiedDate DESC
            LIMIT 50
        ];

        // 閾値・対象ステージでフィルタ
        List<Opportunity> filtered = new List<Opportunity>();
        for (Opportunity o : opps) {
            Boolean stageOk = (conf.targetStages.isEmpty() || conf.targetStages.contains(o.StageName));
            Boolean amountOk = (conf.minAmount == null || (o.Amount != null && o.Amount >= conf.minAmount));
            if (stageOk && amountOk) filtered.add(o);
        }
        if (filtered.isEmpty()) return;

        // Block Kitのblocksを構築
        List<Object> blocks = new List<Object>();
        blocks.add(sectionText('*商談更新* :bell:（まとめ通知）'));
        blocks.add(divider());

        


        for (Opportunity o : filtered) {
            // 行をfieldsで2列×2段みたいに見せる
            List<Object> fields = new List<Object>{
                mrkdwnField('*顧客:* ' + nvl(o.Account != null ? o.Account.Name : null, '-')),
                mrkdwnField('*担当:* ' + nvl(o.Owner  != null ? o.Owner.Name  : null, '-')),
                mrkdwnField('*フェーズ:* ' + nvl(o.StageName, '-') + ' (' + (o.Probability==null? '—' : String.valueOf(o.Probability.intValue()) + '%') + ')'),
                mrkdwnField('*金額:* ' + formatJPY(o.Amount))
            };
            blocks.add(new Map<String,Object>{
                'type' => 'section',
                'text' => new Map<String,Object>{ 'type' => 'mrkdwn', 'text' => '*' + nvl(o.Name,'(名称なし)') + '*' },
                'fields' => fields
            });
            // レコードの詳細へ飛ぶボタン
            blocks.add(new Map<String,Object>{
                'type' => 'actions',
                'elements' => new List<Object>{
                    new Map<String,Object>{
                        'type' => 'button',
                        'text' => new Map<String,Object>{ 'type' => 'plain_text', 'text' => 'Salesforceで開く' },
                        'url'  => recordUrl(o.Id)
                    }
                }
            });
            blocks.add(divider());
        }

        // リクエストボディ（Block Kitを使うときは text は任意）
        Map<String,Object> payload = new Map<String,Object>{
            'blocks' => blocks
        };
        doPost(JSON.serialize(payload));
    }

    // ========== Slack Block Kit ヘルパ ==========

    private static Map<String,Object> divider() {
        return new Map<String,Object>{ 'type' => 'divider' };
    }
    private static Map<String,Object> sectionText(String md) {
        return new Map<String,Object>{
            'type' => 'section',
            'text' => new Map<String,Object>{ 'type' => 'mrkdwn', 'text' => md }
        };
    }
    private static Map<String,Object> mrkdwnField(String md) {
        return new Map<String,Object>{ 'type' => 'mrkdwn', 'text' => md };
    }

    // 金額を「¥1,234,567」風に
    private static String formatJPY(Decimal amt) {
        if (amt == null) return '—';
        return '¥' + amt.setScale(0).format(); // 組織のロケールに依存
    }

    // レコードへのURL（My Domain/Lightning対応）
    private static String recordUrl(Id recId) {
        String base = URL.getOrgDomainUrl().toExternalForm();
        // Lightning 直リンク
        return base + '/lightning/r/Opportunity/' + recId + '/view';
    }

    // ========== HTTP送信 ==========

    @TestVisible private static void doPost(String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Slack_Webhook'); // Named Credential
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json; charset=utf-8');
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            System.debug(LoggingLevel.ERROR,
                'Slack POST failed status=' + res.getStatus() + ' body=' + res.getBody());
        }
    }
}
