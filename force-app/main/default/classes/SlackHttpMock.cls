@IsTest
public class SlackHttpMock implements HttpCalloutMock {
    public static Integer requestCount = 0;
    public static List<String> bodies = new List<String>();
    public static Integer statusCodeToReturn = 200;
    public static String statusMessageToReturn = 'OK';

    public HTTPResponse respond(HTTPRequest req) {
        requestCount++;
        bodies.add(req.getBody());

        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCodeToReturn);
        res.setStatus(statusCodeToReturn + ' ' + statusMessageToReturn);
        res.setBody('{"ok":true}');
        return res;
    }

    public static void reset(Integer code, String msg) {
        requestCount = 0;
        bodies.clear();
        statusCodeToReturn = code;
        statusMessageToReturn = msg;
    }
}
