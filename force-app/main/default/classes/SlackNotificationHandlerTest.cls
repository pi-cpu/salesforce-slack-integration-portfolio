@IsTest
private class SlackNotificationHandlerTest {

    // --- CMDTレコードを用意（テスト内のDMLは可） ---
    private static void setConf(Boolean enabled, Decimal minAmount, String stagesCsv) {
        SlackConfigProvider.Conf c = new SlackConfigProvider.Conf();
        c.enabled = enabled;
        c.minAmount = minAmount;
        c.targetStages.clear();
        if (!String.isBlank(stagesCsv)) {
            for (String s : stagesCsv.split('\\s*,\\s*')) {
                if (!String.isBlank(s)) c.targetStages.add(s.trim());
            }
        }
        SlackConfigProvider.setTestConf(c);
    }

    // --- 最小限の商談作成 ---
    private static Opportunity newOpp(String name, String stage, Decimal amount) {
        return new Opportunity(
            Name = name,
            StageName = stage,
            CloseDate = Date.today().addDays(7),
            Amount = amount
        );
    }

    // ========== テスト1：Insertで複数件、フィルタにより通知対象が絞られる ==========
    @IsTest static void testBulkInsertWithFilterAndSuccessPost() {
        setConf(true, 50000, 'Prospecting, Proposal/Price Quote');

        List<Opportunity> opps = new List<Opportunity>{
            newOpp('A-対象(Prospecting 10万)', 'Prospecting', 100000),
            newOpp('B-金額不足(2万)', 'Prospecting', 20000), // 金額で落ちる
            newOpp('C-ステージ対象外', 'Closed Lost', 200000), // ステージで落ちる
            newOpp('D-対象(Proposal 7万)', 'Proposal/Price Quote', 70000)
        };

        Test.startTest();
        SlackHttpMock.reset(200, 'OK');
        Test.setMock(HttpCalloutMock.class, new SlackHttpMock());
        insert opps; // after insert でハンドラー実行→Queueable→HTTPモック
        Test.stopTest(); // Queueable実行

        System.assertEquals(true, SlackHttpMock.requestCount > 0, 'POSTが呼ばれていること');

        // モックに渡されたbody内に「対象レコード名」が含まれているかざっくり検証
        String bodyAll = String.join(SlackHttpMock.bodies, '\n');
        System.assert(bodyAll.contains('A-対象(Prospecting 10万)'), 'Aが含まれる');
        System.assert(!bodyAll.contains('B-金額不足(2万)'), 'Bは含まれない');
        System.assert(!bodyAll.contains('C-ステージ対象外'), 'Cは含まれない');
        System.assert(bodyAll.contains('D-対象(Proposal 7万)'), 'Dが含まれる');
    }

    // ========== テスト2：Updateでステージ/金額の変更のみ通知、HTTP失敗でも落ちない ==========
    @IsTest static void testBulkUpdateChangeDetectionAndFailurePost() {
        // ① Insert時は通知OFF（Queueableをenqueueさせない）
        setConf(false, 0, 'Prospecting, Negotiation/Review');

        // 事前Insert
        List<Opportunity> opps = new List<Opportunity>{
            newOpp('E-変更なし', 'Prospecting', 50000),
            newOpp('F-ステージ変更あり', 'Prospecting', 60000),
            newOpp('G-金額変更あり', 'Negotiation/Review', 70000)
        };
        insert opps;

        // 更新：Eは全く変更なし、Fはステージ変更、Gは金額変更
        opps[0].Description = 'テキストだけ変更（通知対象外）';
        opps[1].StageName = 'Negotiation/Review';
        opps[2].Amount = 90000;

        // ② Update時は通知ON
        setConf(true, 0, 'Prospecting, Negotiation/Review');

        Test.startTest();
        SlackHttpMock.reset(429, 'Too Many Requests'); // 失敗コードで返す
        Test.setMock(HttpCalloutMock.class, new SlackHttpMock());
        update opps; // after update → Queueable → HTTPモック(失敗)
        Test.stopTest();

        // 失敗でも例外で落ちずに完走する想定
        System.assertEquals(true, SlackHttpMock.requestCount > 0, 'POSTが呼ばれていること');

        String bodyAll = String.join(SlackHttpMock.bodies, '\n');
        System.assert(!bodyAll.contains('E-変更なし'), 'Eは含まれない（変更なし）');
        System.assert(bodyAll.contains('F-ステージ変更あり'), 'Fは含まれる（ステージ変更）');
        System.assert(bodyAll.contains('G-金額変更あり'), 'Gは含まれる（金額変更）');
    }

    // ========== テスト3：機能OFFなら何も送らない ==========
    @IsTest static void testDisabledNoPost() {
        setConf(false, 0, null);
        Test.startTest();
        SlackHttpMock.reset(200, 'OK');
        Test.setMock(HttpCalloutMock.class, new SlackHttpMock());
        insert newOpp('H-機能OFF', 'Prospecting', 100000);
        Test.stopTest();
        System.assertEquals(0, SlackHttpMock.requestCount, '機能OFFなのでPOSTなし');
    }

    // ========== テスト4：URL生成（@TestVisible） ==========
    @IsTest static void testMakeRecordUrl() {
        Opportunity o = newOpp('I-URL', 'Prospecting', 10000);
        insert o;
        String url = SlackNotificationHandler.makeRecordUrl('Opportunity', o.Id);
        System.assert(url.startsWith(System.Url.getOrgDomainUrl().toExternalForm()), 'ベースURLから始まる');
        System.assert(url.contains('/lightning/r/Opportunity/' + String.valueOf(o.Id) + '/view'),
            'LightningのレコードURL形式であること');
    }
    // ========== テスト終了後にCMDTのテスト用設定をクリア ==========
    @IsTest static void testClearConf() {
        SlackConfigProvider.clearTestConf();
    }
}
