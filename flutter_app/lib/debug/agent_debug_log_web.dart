import 'dart:convert';
import 'dart:html' as html;

void agentDebugLogPost(Map<String, dynamic> payload) {
  try {
    html.HttpRequest.request(
      'http://127.0.0.1:7480/ingest/f78b8c1e-408c-4ba9-8fed-4f186b1306c8',
      method: 'POST',
      sendData: jsonEncode(payload),
      requestHeaders: {
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': '7f8fb5',
      },
    );
  } catch (_) {}
}
