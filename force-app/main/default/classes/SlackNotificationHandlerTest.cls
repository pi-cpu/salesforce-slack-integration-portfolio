@IsTest
private class SlackNotificationHandlerTest {
    // シンプルなモック：Slack側は200を返すだけ
    private class OkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assertEquals('POST', req.getMethod());
            System.assert(req.getBody().contains('"blocks"')); // Block Kit が含まれること
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    @IsTest static void testPostBlockKit() {
        // CMDTがあればそれを使う。なければConfのデフォルトで通る前提
        Account a = new Account(Name='テスト株式会社'); insert a;
        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        Opportunity o = new Opportunity(
            Name='Block Kitテスト商談',
            StageName='Proposal/Price Quote',
            CloseDate=Date.today().addDays(30),
            Amount=1200000,
            AccountId=a.Id,
            OwnerId=u.Id,
            Probability=50
        );
        insert o;

        Test.setMock(HttpCalloutMock.class, new OkMock());
        Test.startTest();
        System.enqueueJob(new SlackNotificationHandler.QueueJob(new List<Id>{ o.Id }));
        Test.stopTest(); // Queueable実行＆HTTP送信
    }
}