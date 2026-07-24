// ignore_for_file: avoid_print
/// Download + vinculação multiplataforma TDLib (Android jniLibs + Maven local; iOS estático).
///
/// Fontes (open-source / TDLib 1.8.65, alinhadas ao pacote libtdjson 0.3.0):
/// - Android: https://github.com/up9cloud/android-libtdjson
/// - iOS:     https://github.com/up9cloud/ios-libtdjson (xcframework ESTÁTICO — App Store TN2435)
///
/// Uso (em flutter_app/):
///   dart run tool/setup_tdlib.dart
///   dart run tool/download_tdlib.dart --android-only
///   dart run tool/download_tdlib.dart --ios-only
///
/// Temporários: D:\TEMPORARIOS\tdlib_download (Windows) ou ./build/tdlib_download
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const String kTdlibVersionTag = 'v1.8.65';
const String kTdlibVersion = '1.8.65';

const String kAndroidReleaseBase =
    'https://github.com/up9cloud/android-libtdjson/releases/download/$kTdlibVersionTag';
const String kIosReleaseBase =
    'https://github.com/up9cloud/ios-libtdjson/releases/download/$kTdlibVersionTag';

Future<void> main(List<String> args) async {
  final androidOnly = args.contains('--android-only');
  final iosOnly = args.contains('--ios-only');
  final doAndroid = !iosOnly;
  final doIos = !androidOnly;

  final flutterAppRoot = Directory.current.path;
  final pubspec = File(p.join(flutterAppRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    stderr.writeln(
      'Execute a partir de flutter_app/ (pubspec.yaml não encontrado).',
    );
    exit(1);
  }

  final tmpRoot = _tempRoot();
  await Directory(tmpRoot).create(recursive: true);
  print('TDLib $kTdlibVersionTag  (OS: ${Platform.operatingSystem})');
  print('Temp: $tmpRoot');

  if (doAndroid) {
    final jniDest = await _downloadAndroid(flutterAppRoot, tmpRoot);
    await _publishAndroidLocalMaven(flutterAppRoot, jniDest);
  }
  if (doIos) {
    await _downloadIosStatic(flutterAppRoot, tmpRoot);
    await _configureIosPodfile(flutterAppRoot);
  }

  print('');
  print('Concluído.');
  print('Android: jniLibs + local-maven io.github.up9cloud:td:$kTdlibVersion');
  print('iOS:     Frameworks/libtdjson-static.xcframework + Podfile (estático)');
  print('');
  print('Credenciais: flutter_app/.env (TELEGRAM_API_ID / TELEGRAM_API_HASH)');
}

String _tempRoot() {
  if (Platform.isWindows) {
    final d = r'D:\TEMPORARIOS\tdlib_download';
    Directory(d).createSync(recursive: true);
    return d;
  }
  return p.join(Directory.current.path, 'build', 'tdlib_download');
}

Future<String> _downloadAndroid(String flutterAppRoot, String tmpRoot) async {
  print('\n=== Android (jniLibs + Maven local) ===');
  final url = '$kAndroidReleaseBase/jniLibs.tar.gz';
  final tarPath = p.join(tmpRoot, 'android_jniLibs.tar.gz');
  await _downloadFile(url, tarPath);

  final extractDir = p.join(tmpRoot, 'android_extract');
  await _extractTarGz(tarPath, extractDir);

  final jniDest = Directory(
    p.join(flutterAppRoot, 'android', 'app', 'src', 'main', 'jniLibs'),
  );
  await jniDest.create(recursive: true);

  final abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
  var copied = 0;
  for (final abi in abis) {
    final srcSo = _findFile(extractDir, 'libtdjson.so', preferDirNamed: abi);
    if (srcSo == null) {
      print('  AVISO: libtdjson.so não encontrado para $abi');
      continue;
    }
    final destDir = Directory(p.join(jniDest.path, abi));
    await destDir.create(recursive: true);
    final dest = p.join(destDir.path, 'libtdjson.so');
    await File(srcSo).copy(dest);
    final kb = (File(dest).lengthSync() / 1024).round();
    print('  OK $abi/libtdjson.so ($kb KB)');
    copied++;
  }
  if (copied == 0) {
    stderr.writeln('Falha: nenhum .so Android copiado. Conteúdo em $extractDir');
    exit(2);
  }
  return jniDest.path;
}

/// Publica AAR em android/local-maven para o plugin libtdjson resolver
/// `io.github.up9cloud:td:1.8.65` **sem** GITHUB_TOKEN.
Future<void> _publishAndroidLocalMaven(
  String flutterAppRoot,
  String jniLibsRoot,
) async {
  print('\n=== Android local-maven (io.github.up9cloud:td:$kTdlibVersion) ===');
  final mavenDir = Directory(
    p.join(
      flutterAppRoot,
      'android',
      'local-maven',
      'io',
      'github',
      'up9cloud',
      'td',
      kTdlibVersion,
    ),
  );
  await mavenDir.create(recursive: true);

  final archive = Archive();
  const manifest = '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="io.github.up9cloud.td" />
''';
  final manifestBytes = utf8.encode(manifest);
  archive.addFile(
    ArchiveFile('AndroidManifest.xml', manifestBytes.length, manifestBytes),
  );

  final abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
  var added = 0;
  for (final abi in abis) {
    final so = File(p.join(jniLibsRoot, abi, 'libtdjson.so'));
    if (!so.existsSync()) continue;
    final bytes = await so.readAsBytes();
    archive.addFile(
      ArchiveFile('jni/$abi/libtdjson.so', bytes.length, bytes),
    );
    added++;
  }
  if (added == 0) {
    stderr.writeln('Falha: sem .so para montar AAR Maven local');
    exit(4);
  }

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    stderr.writeln('Falha ao compactar AAR');
    exit(4);
  }
  final aarPath = p.join(mavenDir.path, 'td-$kTdlibVersion.aar');
  await File(aarPath).writeAsBytes(zipBytes, flush: true);

  final pom = '''<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.github.up9cloud</groupId>
  <artifactId>td</artifactId>
  <version>$kTdlibVersion</version>
  <packaging>aar</packaging>
  <name>tdjson Android prebuilt</name>
  <description>Vendored by tool/setup_tdlib.dart — Gestão YAHWEH</description>
</project>
''';
  await File(p.join(mavenDir.path, 'td-$kTdlibVersion.pom'))
      .writeAsString(pom);

  final mb = (zipBytes.length / (1024 * 1024)).toStringAsFixed(1);
  print('  OK $aarPath ($mb MB, $added ABIs)');
}

Future<void> _downloadIosStatic(String flutterAppRoot, String tmpRoot) async {
  print('\n=== iOS (xcframework ESTÁTICO — App Store) ===');
  // Preferir estático (TN2435: App Store rejeita dylib custom).
  final url = '$kIosReleaseBase/libtdjson-static.xcframework.tar.gz';
  final tarPath = p.join(tmpRoot, 'ios_libtdjson_static.xcframework.tar.gz');
  await _downloadFile(url, tarPath);

  final extractDir = p.join(tmpRoot, 'ios_extract_static');
  await _extractTarGz(tarPath, extractDir);

  final frameworksDir = Directory(
    p.join(flutterAppRoot, 'ios', 'Frameworks'),
  );
  await frameworksDir.create(recursive: true);

  final xc = _findDirectory(extractDir, 'libtdjson-static.xcframework') ??
      _findDirectory(extractDir, 'libtdjson.xcframework');
  if (xc == null) {
    stderr.writeln(
      'Falha: libtdjson-static.xcframework não encontrado em $extractDir',
    );
    exit(3);
  }

  final dest = p.join(frameworksDir.path, 'libtdjson-static.xcframework');
  if (Directory(dest).existsSync()) {
    await Directory(dest).delete(recursive: true);
  }
  await _copyDirectory(xc, dest);
  print('  OK ios/Frameworks/libtdjson-static.xcframework');

  // Podspec local (fallback offline / reforço estático).
  final podspecPath = p.join(frameworksDir.path, 'YahwehTdjsonStatic.podspec');
  await File(podspecPath).writeAsString('''
Pod::Spec.new do |s|
  s.name             = 'YahwehTdjsonStatic'
  s.version          = '$kTdlibVersion'
  s.summary          = 'TDLib JSON static xcframework (Gestão YAHWEH)'
  s.homepage         = 'https://github.com/up9cloud/ios-libtdjson'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Gestao YAHWEH' => 'dev@local' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.5'
  s.vendored_frameworks = 'libtdjson-static.xcframework'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '\$(inherited) -force_load "\${PODS_XCFRAMEWORKS_BUILD_DIR}/YahwehTdjsonStatic/libtdjson_static.a" -lz -lc++',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
''');
  print('  OK ios/Frameworks/YahwehTdjsonStatic.podspec');

  await File(p.join(frameworksDir.path, 'TDLIB_README.txt')).writeAsString(
    'libtdjson-static.xcframework ($kTdlibVersionTag) — gerado por tool/setup_tdlib.dart\n'
    'Linkagem ESTÁTICA (App Store TN2435).\n'
    'O plugin pub libtdjson puxa flutter_libtdjson via CocoaPods (também estático).\n'
    'Podfile do Runner recebe bloco de reforço gerado automaticamente.\n',
  );
}

/// Reforça no Podfile a linkagem ESTÁTICA (TN2435).
///
/// O plugin pub `libtdjson` já depende de `flutter_libtdjson` (CocoaPods trunk,
/// xcframework estático). Não injetamos um 2º pod para evitar símbolos duplicados.
/// O xcframework em ios/Frameworks/ + YahwehTdjsonStatic.podspec ficam como
/// fallback offline (Codemagic) — ativar manualmente só se o trunk falhar.
Future<void> _configureIosPodfile(String flutterAppRoot) async {
  print('\n=== iOS Podfile (link estático) ===');
  final podfile = File(p.join(flutterAppRoot, 'ios', 'Podfile'));
  if (!podfile.existsSync()) {
    stderr.writeln('AVISO: ios/Podfile não encontrado — pulando patch');
    return;
  }

  var content = await podfile.readAsString();

  // Remove bloco antigo que injetava pod duplicado (versões anteriores do script).
  content = content.replaceAll(
    RegExp(
      r'# BEGIN_YAHWEH_TDLIB_STATIC[\s\S]*?# END_YAHWEH_TDLIB_STATIC\s*',
      multiLine: true,
    ),
    '',
  );

  const noteBegin = '# BEGIN_YAHWEH_TDLIB_NOTE';
  const noteEnd = '# END_YAHWEH_TDLIB_NOTE';
  final note = '''
$noteBegin
  # TDLib iOS: linkagem ESTÁTICA via pod trunk `flutter_libtdjson` (plugin libtdjson).
  # App Store TN2435 — sem dylib custom. Fallback offline: ios/Frameworks/YahwehTdjsonStatic.podspec
  # (não ativar junto do trunk — símbolos duplicados).
$noteEnd
''';

  if (content.contains(noteBegin) && content.contains(noteEnd)) {
    content = content.replaceAll(
      RegExp('$noteBegin[\\s\\S]*?$noteEnd', multiLine: true),
      note.trimRight(),
    );
  } else {
    final anchor = RegExp(
      r'(flutter_install_all_ios_pods[^\n]*\n)',
      multiLine: true,
    );
    if (anchor.hasMatch(content)) {
      content = content.replaceFirstMapped(anchor, (m) => '${m[1]}\n$note');
    } else {
      content = '$content\n$note\n';
    }
  }

  const postBegin = '# BEGIN_YAHWEH_TDLIB_POST_INSTALL';
  const postEnd = '# END_YAHWEH_TDLIB_POST_INSTALL';
  final postBlock = '''
$postBegin
    # TDLib estático: garante -lz/-lc++ nos pods do motor (FFI → DynamicLibrary.process).
    installer.pods_project.targets.each do |target|
      next unless ['libtdjson', 'flutter_libtdjson'].include?(target.name)
      target.build_configurations.each do |config|
        flags = config.build_settings['OTHER_LDFLAGS'] || ['\$(inherited)']
        flags = [flags] unless flags.is_a?(Array)
        flags << '-lz' unless flags.any? { |f| f.to_s == '-lz' }
        flags << '-lc++' unless flags.any? { |f| f.to_s == '-lc++' }
        config.build_settings['OTHER_LDFLAGS'] = flags
        config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      end
    end
$postEnd
''';

  if (content.contains(postBegin) && content.contains(postEnd)) {
    content = content.replaceAll(
      RegExp('$postBegin[\\s\\S]*?$postEnd', multiLine: true),
      postBlock.trimRight(),
    );
  } else if (content.contains('post_install do |installer|')) {
    content = content.replaceFirst(
      'post_install do |installer|',
      'post_install do |installer|\n$postBlock',
    );
  } else {
    content = '''
$content

post_install do |installer|
$postBlock
end
''';
  }

  await podfile.writeAsString(content);
  print('  OK Podfile atualizado (nota TN2435 + post_install estático)');
}

Future<void> _downloadFile(String url, String destPath) async {
  print('  Download: $url');
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final res = await client.send(req);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} ao baixar $url');
    }
    final sink = File(destPath).openWrite();
    var received = 0;
    final total = res.contentLength ?? 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0 && received % (5 * 1024 * 1024) < chunk.length) {
        final pct = (100 * received / total).toStringAsFixed(0);
        stdout.write(
          '\r  … $pct% (${(received / 1024 / 1024).toStringAsFixed(1)} MB)',
        );
      }
    }
    await sink.close();
    stdout.writeln();
    print(
      '  Salvo: $destPath (${(received / 1024 / 1024).toStringAsFixed(1)} MB)',
    );
  } finally {
    client.close();
  }
}

Future<void> _extractTarGz(String tarGzPath, String outDir) async {
  final out = Directory(outDir);
  if (out.existsSync()) {
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);

  final bytes = await File(tarGzPath).readAsBytes();
  final tarBytes = GZipDecoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(tarBytes, verify: true);

  for (final file in archive) {
    final name = file.name;
    if (name.isEmpty) continue;
    final outPath = p.join(outDir, name);
    if (file.isFile) {
      final f = File(outPath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(file.content as List<int>);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
  print('  Extraído → $outDir');
}

String? _findFile(
  String root,
  String fileName, {
  String? preferDirNamed,
}) {
  final matches = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File) continue;
    if (p.basename(entity.path) != fileName) continue;
    matches.add(entity.path);
  }
  if (matches.isEmpty) return null;
  if (preferDirNamed != null) {
    for (final m in matches) {
      if (m.replaceAll('\\', '/').contains('/$preferDirNamed/')) return m;
    }
  }
  return matches.first;
}

String? _findDirectory(String root, String dirName) {
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is Directory && p.basename(entity.path) == dirName) {
      return entity.path;
    }
  }
  return null;
}

Future<void> _copyDirectory(String src, String dest) async {
  await Directory(dest).create(recursive: true);
  await for (final entity in Directory(src).list(recursive: false)) {
    final name = p.basename(entity.path);
    final target = p.join(dest, name);
    if (entity is Directory) {
      await _copyDirectory(entity.path, target);
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}
