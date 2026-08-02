# Rewrite total: módulo Utilitários Controle Total → Gestão Yahweh.
# Destino ativo do shell: flutter_app/lib/ui/pages/
# Também espelha services/utils/constants e lib/pages/ (cópia de paridade).
$ErrorActionPreference = "Stop"
$ctRoot = "C:\Controletotalapp_Independente\flutter_app\lib"
$gyRoot = "C:\gestao_yahweh_premium_final\flutter_app\lib"

function Transform-UtilitariosContent {
    param([string]$content, [switch]$IsScreen)
    $c = $content
    $c = $c -replace "import '\.\./widgets/modern_module_ui\.dart';", "import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';"
    $c = $c -replace "import '\.\./theme/theme_context\.dart';", "import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';"
    $c = $c -replace "import '\.\./constants/", "import 'package:gestao_yahweh/constants/"
    $c = $c -replace "import '\.\./services/", "import 'package:gestao_yahweh/services/"
    $c = $c -replace "import '\.\./utils/", "import 'package:gestao_yahweh/utils/"
    $c = $c -replace "import '\.\./models/user_profile\.dart';`r?`n", ""
    if ($IsScreen) {
        $c = $c -replace "import 'utilitarios_", "import 'package:gestao_yahweh/ui/pages/utilitarios_"
    }
    $c = $c -replace "import 'smart_input_image_ocr_service\.dart';", "import 'package:gestao_yahweh/services/smart_input_image_ocr_service.dart';"
    $c = $c -replace "import 'relatorio_service\.dart';", "import 'package:gestao_yahweh/services/relatorio_service.dart';"
    $c = $c -replace "import '\.\./utils/smart_input_ocr_recognized_postprocess\.dart';", "import 'package:gestao_yahweh/utils/smart_input_ocr_recognized_postprocess.dart';"
    $c = $c -replace "import 'functions_service\.dart';", "import 'package:gestao_yahweh/services/church_functions_service.dart';"
    $c = $c -replace "import 'utilitarios_local_service\.dart';", "import 'package:gestao_yahweh/services/utilitarios_local_service.dart';"
    $c = $c -replace "FirebaseAuth\.instance", "firebaseDefaultAuth"
    $c = $c -replace "import 'package:firebase_auth/firebase_auth\.dart';`r?`n", "import 'package:gestao_yahweh/core/firebase_bootstrap.dart';`n"
    $c = $c -replace "FunctionsService\(\)\.ocrImageForSmartInput", "ChurchFunctionsService.ocrImageForSmartInput"
    $c = $c -replace 'Utilitarios_ControleTotal', 'Utilitarios_GestaoYahweh'
    $c = $c -replace 'controle_total', 'gestao_yahweh'
    $c = $c -replace 'Controle Total App', 'Gestão Yahweh'
    $c = $c -replace 'name="ControleTotal"', 'name="GestaoYahweh"'
    return $c
}

function Write-Transformed {
    param($src, $dst, [switch]$IsScreen)
    if (-not (Test-Path $src)) { throw "Falta origem: $src" }
    $raw = Get-Content -Path $src -Raw -Encoding UTF8
    $out = Transform-UtilitariosContent -content $raw -IsScreen:$IsScreen
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Set-Content -Path $dst -Value $out -Encoding UTF8 -NoNewline
    Write-Host "OK $dst"
}

# Telas / fluxos (ui/pages = shell ativo)
$screenPairs = @(
    @{ src = "screens\utilitarios_screen.dart"; dst = "ui\pages\utilitarios_screen.dart" },
    @{ src = "screens\utilitarios_pdf_tools_flow.dart"; dst = "ui\pages\utilitarios_pdf_tools_flow.dart" },
    @{ src = "screens\utilitarios_document_scanner_flow.dart"; dst = "ui\pages\utilitarios_document_scanner_flow.dart" },
    @{ src = "screens\utilitarios_video_downloader_flow.dart"; dst = "ui\pages\utilitarios_video_downloader_flow.dart" },
    @{ src = "screens\utilitarios_photo_edit_flow.dart"; dst = "ui\pages\utilitarios_photo_edit_flow.dart" },
    @{ src = "screens\utilitarios_photo_collage_flow.dart"; dst = "ui\pages\utilitarios_photo_collage_flow.dart" },
    @{ src = "screens\utilitarios_photo_text_extract_flow.dart"; dst = "ui\pages\utilitarios_photo_text_extract_flow.dart" },
    @{ src = "screens\utilitarios_photo_camera_pdf_flow.dart"; dst = "ui\pages\utilitarios_photo_camera_pdf_flow.dart" }
)

foreach ($p in $screenPairs) {
    Write-Transformed -src "$ctRoot\$($p.src)" -dst "$gyRoot\$($p.dst)" -IsScreen
    # Espelho em lib/pages (paridade / scripts antigos)
    $pagesDst = ($p.dst -replace '^ui\\pages\\', 'pages\')
    Write-Transformed -src "$ctRoot\$($p.src)" -dst "$gyRoot\$pagesDst" -IsScreen
}

# Services / utils / constants
$svcPairs = @(
    "services\utilitarios_local_service.dart",
    "services\utilitarios_pdf_preserve_export.dart",
    "services\utilitarios_photo_service.dart",
    "services\utilitarios_photo_text_extract_service.dart",
    "services\utilitarios_daily_quota_service.dart",
    "services\utilitarios_video_downloader_service.dart",
    "services\utilitarios_video_compress_service.dart",
    "services\utilitarios_video_models.dart",
    "services\utilitarios_video_tools_io.dart",
    "services\utilitarios_video_tools_stub.dart",
    "utils\utilitarios_file_io.dart",
    "utils\utilitarios_web_io_web.dart",
    "utils\utilitarios_web_io_stub.dart",
    "utils\home_shell_layout.dart",
    "constants\utilitarios_export_page_format.dart"
)

foreach ($rel in $svcPairs) {
    Write-Transformed -src "$ctRoot\$rel" -dst "$gyRoot\$rel"
}

# smart_input OCR (se existir no CT)
$ocrSrc = "$ctRoot\services\smart_input_image_ocr_service.dart"
if (Test-Path $ocrSrc) {
    Write-Transformed -src $ocrSrc -dst "$gyRoot\services\smart_input_image_ocr_service.dart"
}

# --- Post-patches GY ---

# utilitarios_screen: isAdmin em vez de UserProfile
foreach ($screenPath in @(
    "$gyRoot\ui\pages\utilitarios_screen.dart",
    "$gyRoot\pages\utilitarios_screen.dart"
)) {
    $screen = Get-Content -Path $screenPath -Raw -Encoding UTF8
    $screen = $screen -replace "import 'package:gestao_yahweh/models/user_profile\.dart';`r?`n", ""
    $screen = $screen -replace "(?m)^\s*final UserProfile profile;\r?\n", ""
    $screen = $screen -replace "(?m)^\s*required this\.profile,\r?\n", ""
    $screen = $screen -replace "bool get _isAdmin => widget\.profile\.isAdmin;", "bool get _isAdmin => widget.isAdmin;"
    # Campo + parâmetro isAdmin (GY não usa UserProfile no shell)
    if ($screen -notmatch '(?m)^\s*final bool isAdmin;') {
        $screen = $screen -replace '(?m)^(\s*final String uid;)', "`$1`r`n  final bool isAdmin;"
    }
    if ($screen -notmatch 'this\.isAdmin\s*=\s*false') {
        $screen = $screen -replace '(required this\.uid,)', "required this.uid,`r`n    this.isAdmin = false,"
    }
    Set-Content -Path $screenPath -Value $screen -Encoding UTF8 -NoNewline
    Write-Host "OK isAdmin patch: $screenPath"
}

# Ícones CT + nav GY
$iconsPath = "$gyRoot\constants\utilitarios_module_icons.dart"
$icons = @"
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';

/// Ícones do módulo Utilitários — espelho Controle Total + nav Gestão Yahweh.
abstract final class UtilitariosModuleIcons {
  UtilitariosModuleIcons._();

  static const IconData nav = kUtilitariosModuleIcon;
  static const IconData pdfWord = Icons.description_rounded;
  static const IconData pdfJpeg = Icons.image_rounded;
  static const IconData pdfPng = Icons.photo_library_rounded;
  static const IconData jpegPdf = Icons.picture_as_pdf_rounded;
  static const IconData pngPdf = Icons.image_aspect_ratio_rounded;
  static const IconData wordPdf = Icons.article_rounded;
  static const IconData pdfExcel = Icons.table_chart_rounded;
  static const IconData excelPdf = Icons.grid_on_rounded;
  static const IconData pdfPpt = Icons.slideshow_rounded;
  static const IconData compress = Icons.compress_rounded;
  static const IconData videoMp4 = Icons.movie_creation_rounded;
  static const IconData audioExtract = Icons.audio_file_rounded;
  static const IconData mergePdf = Icons.merge_type_rounded;
  static const IconData splitPdf = Icons.content_cut_rounded;
  static const IconData editPdf = Icons.draw_rounded;
  static const IconData archiveZip = Icons.folder_zip_rounded;
  static const IconData photoEdit = Icons.auto_awesome_rounded;
  static const IconData photoCameraPdf = Icons.camera_alt_rounded;
  static const IconData documentScanner = Icons.document_scanner_outlined;
  static const IconData photoTextExtract = Icons.document_scanner_rounded;
  static const IconData videoDownload = Icons.cloud_download_rounded;
}
"@
Set-Content -Path $iconsPath -Value $icons -Encoding UTF8 -NoNewline
Write-Host "OK utilitarios_module_icons.dart"

# file_io → YahwehFilePicker
$fileIo = "$gyRoot\utils\utilitarios_file_io.dart"
if (Test-Path $fileIo) {
    $fi = Get-Content -Path $fileIo -Raw -Encoding UTF8
    if ($fi -notmatch 'yahweh_file_picker') {
        $fi = "import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';`n" + $fi
    }
    $fi = $fi -replace 'FilePicker\.platform\.pickFiles', 'YahwehFilePicker.pickFiles'
    $fi = $fi -replace 'FilePicker\.platform\.saveFile', 'YahwehFilePicker.saveFile'
    Set-Content -Path $fileIo -Value $fi -Encoding UTF8 -NoNewline
    Write-Host "OK utilitarios_file_io YahwehFilePicker"
}

# OCR Cloud Vision via ChurchFunctionsService
$ocrPath = "$gyRoot\services\smart_input_image_ocr_service.dart"
if (Test-Path $ocrPath) {
    $ocr = Get-Content -Path $ocrPath -Raw -Encoding UTF8
    if ($ocr -notmatch 'church_functions_service') {
        if ($ocr -match 'firebase_bootstrap') {
            $ocr = $ocr -replace "import 'package:gestao_yahweh/core/firebase_bootstrap.dart';", "import 'package:gestao_yahweh/core/firebase_bootstrap.dart';`nimport 'package:gestao_yahweh/services/church_functions_service.dart';"
        } else {
            $ocr = "import 'package:gestao_yahweh/services/church_functions_service.dart';`n" + $ocr
        }
    }
    $ocr = $ocr -replace "return null; // Cloud Vision:.*", "return await ChurchFunctionsService.ocrImageForSmartInput(base64: b64, mimeType: mime);"
    $ocr = $ocr -replace "FunctionsService\(\)\.ocrImageForSmartInput", "ChurchFunctionsService.ocrImageForSmartInput"
    Set-Content -Path $ocrPath -Value $ocr -Encoding UTF8 -NoNewline
    Write-Host "OK smart_input_image_ocr_service"
}

Write-Host ""
Write-Host "Sincronização Utilitários CT → GY (rewrite total) concluída."
Write-Host "Inclui: PDF fullscreen+Descartar, Scanner, Baixar Vídeo, pdfToVisualDocx, pdf_preserve Syncfusion."
