import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// YouTube / MP4 no Android/iOS — WebView HTML5 (padrão Cursos).
class ChurchYoutubeEmbed extends StatefulWidget {
  const ChurchYoutubeEmbed({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.autoplay = true,
    this.posterUrl,
    this.onReady,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final bool autoplay;
  final String? posterUrl;
  final VoidCallback? onReady;

  @override
  State<ChurchYoutubeEmbed> createState() => _ChurchYoutubeEmbedState();
}

class _ChurchYoutubeEmbedState extends State<ChurchYoutubeEmbed> {
  WebViewController? _controller;
  var _ready = false;
  var _notifiedReady = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant ChurchYoutubeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.autoplay != widget.autoplay) {
      _notifiedReady = false;
      _initController();
    }
  }

  void _notifyReady() {
    if (_notifiedReady) return;
    _notifiedReady = true;
    widget.onReady?.call();
  }

  String _escapeAttr(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  void _initController() {
    final yt = widget.youtubeVideoId?.trim();
    final mp4 = widget.mp4Url?.trim();
    final poster = widget.posterUrl?.trim();
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'flutterReady',
        onMessageReceived: (_) => _notifyReady(),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _notifyReady()),
      );

    if (yt != null && yt.isNotEmpty) {
      c.loadHtmlString(_youtubeApiHtml(yt, autoplay: widget.autoplay));
    } else if (mp4 != null && mp4.isNotEmpty) {
      c.loadHtmlString(_mp4Html(mp4, poster));
    }

    setState(() {
      _controller = c;
      _ready = true;
    });
  }

  String _youtubeApiHtml(String videoId, {required bool autoplay}) {
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:#000;overflow:hidden}
  #player{width:100%;height:100%}
</style>
</head><body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
function onYouTubeIframeAPIReady(){
  new YT.Player('player',{
    videoId:'$videoId',
    playerVars:{autoplay:${autoplay ? 1 : 0},rel:0,modestbranding:1,playsinline:1,fs:1,iv_load_policy:3},
    events:{
      onReady:function(e){
        try{ window.flutterReady && flutterReady.postMessage('1'); }catch(x){}
        if($autoplay){try{e.target.playVideo();}catch(x){}}
      }
    }
  });
}
</script>
</body></html>
''';
  }

  String _mp4Html(String mp4, String? poster) {
    final escaped = _escapeAttr(mp4);
    final autoplayAttr = widget.autoplay ? 'autoplay' : '';
    final posterAttr = (poster != null && poster.isNotEmpty)
        ? 'poster="${_escapeAttr(poster)}"'
        : '';
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  *{margin:0;padding:0}
  html,body{width:100%;height:100%;background:#000}
  video{width:100%;height:100%;object-fit:contain;background:#000}
</style>
</head><body>
<video id="v" controls playsinline preload="auto" $autoplayAttr $posterAttr src="$escaped"></video>
<script>
(function(){
  var v=document.getElementById('v');
  function ready(){ try { window.flutterReady && window.flutterReady.postMessage('1'); } catch(e){} }
  v.addEventListener('loadeddata', ready, {once:true});
  if(v.readyState >= 2) ready();
})();
</script>
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const ColoredBox(
        color: Color(0xFF0F0F0F),
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    return WebViewWidget(controller: _controller!);
  }
}
