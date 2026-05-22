param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startScript = Join-Path $scriptDir "start-live-monitor.ps1"
$stopScript = Join-Path $scriptDir "stop-live-monitor.ps1"
$metadataScript = Join-Path $scriptDir "resolve-douyin-live-metadata.py"
$uiEvidenceScript = Join-Path $scriptDir "export-ui-evidence.ps1"
$manualUiEvidenceScript = Join-Path $scriptDir "new-ui-evidence-manifest.ps1"
$commentSummaryScript = Join-Path $scriptDir "summarize-comments.ps1"
$feishuPublishScript = Join-Path $scriptDir "publish-feishu-report.ps1"
$skillDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $skillDir
$commentCrawlerScript = Join-Path $scriptDir "douyin-comment-crawler.py"
$skillFile = Join-Path $skillDir "SKILL.md"
$caseTemplate = Join-Path $skillDir "assets\douyin-case-analysis-template.md"

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Message
  )
  Assert-True ($Text -match [regex]::Escape($Pattern)) $Message
}

Assert-True (Test-Path -LiteralPath $startScript) "Missing start-live-monitor.ps1"
Assert-True (Test-Path -LiteralPath $stopScript) "Missing stop-live-monitor.ps1"
Assert-True (Test-Path -LiteralPath $metadataScript) "Missing resolve-douyin-live-metadata.py"
Assert-True (Test-Path -LiteralPath $uiEvidenceScript) "Missing export-ui-evidence.ps1"
Assert-True (Test-Path -LiteralPath $manualUiEvidenceScript) "Missing new-ui-evidence-manifest.ps1"
Assert-True (Test-Path -LiteralPath $commentSummaryScript) "Missing summarize-comments.ps1"
Assert-True (Test-Path -LiteralPath $feishuPublishScript) "Missing publish-feishu-report.ps1"
Assert-True (Test-Path -LiteralPath $commentCrawlerScript) "Missing douyin-live-comments crawler.py"
Assert-True (Test-Path -LiteralPath $skillFile) "Missing SKILL.md"
Assert-True (Test-Path -LiteralPath $caseTemplate) "Missing douyin-case-analysis-template.md"

foreach ($scriptToParse in @($startScript, $stopScript, $uiEvidenceScript, $manualUiEvidenceScript, $commentSummaryScript, $feishuPublishScript)) {
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($scriptToParse, [ref]$null, [ref]$parseErrors) | Out-Null
  Assert-True (($parseErrors | Measure-Object).Count -eq 0) "$([System.IO.Path]::GetFileName($scriptToParse)) has parser errors"
}

$startText = Get-Content -Raw -Encoding utf8 -LiteralPath $startScript
$stopText = Get-Content -Raw -Encoding utf8 -LiteralPath $stopScript
$metadataText = Get-Content -Raw -Encoding utf8 -LiteralPath $metadataScript
$uiEvidenceText = Get-Content -Raw -Encoding utf8 -LiteralPath $uiEvidenceScript
$manualUiEvidenceText = Get-Content -Raw -Encoding utf8 -LiteralPath $manualUiEvidenceScript
$commentSummaryText = Get-Content -Raw -Encoding utf8 -LiteralPath $commentSummaryScript
$feishuPublishText = Get-Content -Raw -Encoding utf8 -LiteralPath $feishuPublishScript
$commentCrawlerText = Get-Content -Raw -Encoding utf8 -LiteralPath $commentCrawlerScript
$skillText = Get-Content -Raw -Encoding utf8 -LiteralPath $skillFile
$templateText = Get-Content -Raw -Encoding utf8 -LiteralPath $caseTemplate

foreach ($required in @("RoomName", "Mode", "SystemAudioDevice", "ArchiveRoot", "SessionFile", "GameProductName", "DisableComments", "CommentCrawlerPath")) {
  Assert-Contains $startText $required "start-live-monitor.ps1 missing parameter or field: $required"
}

foreach ($required in @("SessionFile", "transcribe-recording-audio.ps1", "extract-recording-assets.ps1", "transcript_markdown", "comments_path", "comments_pid", "comments_log")) {
  Assert-Contains $stopText $required "stop-live-monitor.ps1 missing stop/transcribe behavior: $required"
}

foreach ($required in @("Stereo Mix", "virtual audio", "OBS", "No system audio device")) {
  Assert-Contains $startText $required "start-live-monitor.ps1 missing system-audio guardrail: $required"
}

Assert-True ($startText -notmatch "microphone\s+array") "start-live-monitor.ps1 must not default to microphone-array capture"
Assert-True ($startText -notmatch "Recording\s+video\s+only") "start-live-monitor.ps1 must not silently record without required system audio"
Assert-Contains $startText "Invoke-FfmpegDeviceList" "start-live-monitor.ps1 must isolate ffmpeg device-list stderr from PowerShell error handling"
Assert-Contains $startText "douyin-comment-crawler.py" "start-live-monitor.ps1 must integrate the bundled Douyin comments crawler"
Assert-Contains $startText '$PSScriptRoot' "start-live-monitor.ps1 must resolve the comment crawler from the script root"
Assert-Contains $startText '$archiveDate = Get-Date -Format "yyyyMMdd"' "start-live-monitor.ps1 must date-stamp archive folders"
Assert-Contains $startText '$archiveFolderBaseName = "$safeGameProductName-$safeRoomName-$archiveDate"' "start-live-monitor.ps1 must name archive folders as <game-product-name>-<room-name>-<date>"
Assert-Contains $startText '$archiveFolderBaseName = "$safeRoomName-$archiveDate"' "start-live-monitor.ps1 must fall back to <room-name>-<date> archive folders when game product name is missing"
Assert-Contains $startText 'archive_folder_name = $archiveFolderName' "start-live-monitor.ps1 must persist the archive folder name in the session"
Assert-Contains $startText "-comments.jsonl" "start-live-monitor.ps1 must name comment output files as comments JSONL"
Assert-Contains $startText '$commentBaseName = "$safeRoomName-$stamp"' "start-live-monitor.ps1 must name comment files as <room-name>-<date>-comments.jsonl"
Assert-True ($startText -notmatch '\$safeGameProductName\$safeRoomName-\$stamp') "start-live-monitor.ps1 must not prefix comment files with game product name"
Assert-Contains $startText "comments_path" "start-live-monitor.ps1 must persist the comment JSONL path in the session"
Assert-True ($startText -notmatch '\[Parameter\(Mandatory=\$true\)\]\s*\r?\n\s*\[string\]\$RoomName') "start-live-monitor.ps1 must allow RoomName to be auto-detected"
Assert-Contains $startText "Resolve-LiveMetadata" "start-live-monitor.ps1 must resolve metadata before naming archive folders"
Assert-Contains $startText "resolve-douyin-live-metadata.py" "start-live-monitor.ps1 must call the Douyin metadata resolver"
Assert-True ($startText -notmatch 'if\s*\(\$Url\)\s*\{\s*Start-Process\s+\$Url') "start-live-monitor.ps1 must not directly open an extra live-room page when the comment crawler owns the browser page"
Assert-Contains $startText '$Url -and $DisableComments' "start-live-monitor.ps1 may only open the live-room URL itself when comments are disabled"
Assert-Contains $commentCrawlerText "find_reusable_live_page" "crawler.py must reuse an existing live-room page when possible"
Assert-Contains $commentCrawlerText "close_duplicate_live_pages" "crawler.py must close duplicate live-room pages"
Assert-Contains $commentCrawlerText "bring_to_front" "crawler.py must bring the reused or created live-room page to the front for recording"
foreach ($required in @("auto_metadata_path", "auto_room_name", "auto_game_product_name", "auto_viewer_count", "metadata_confidence")) {
  Assert-Contains $startText $required "start-live-monitor.ps1 missing auto metadata session field: $required"
}
foreach ($required in @("room_name", "game_product_name", "viewer_count", "confidence", "room_id")) {
  Assert-Contains $metadataText $required "resolve-douyin-live-metadata.py missing metadata field: $required"
}
Assert-Contains $stopText "comments_pid" "stop-live-monitor.ps1 must stop the comment crawler process"
Assert-Contains $stopText "comments_count" "stop-live-monitor.ps1 must persist a comment count for analysis"
Assert-Contains $templateText "ui-table-two-columns" "douyin-case-analysis-template.md must mark the UI table as two-column"
Assert-True ($templateText -notmatch "ui-evidence-column") "douyin-case-analysis-template.md must not keep a key screenshot/evidence table column"
Assert-True ($templateText -notmatch "ui-screenshot-section") "douyin-case-analysis-template.md must not include the UI screenshot section by default"
Assert-True ($templateText -notmatch "ui-evidence-image") "douyin-case-analysis-template.md must not include UI evidence images by default"
Assert-Contains $templateText "script-loop-flowchart" "douyin-case-analysis-template.md must include a script loop flowchart marker"
Assert-Contains $templateText "```mermaid" "douyin-case-analysis-template.md must include a Mermaid flowchart for script loops"
Assert-Contains $templateText "flowchart TD" "douyin-case-analysis-template.md must use a top-down script loop flowchart"
Assert-Contains $templateText "script-loop-text-analysis" "douyin-case-analysis-template.md must include structured script loop text analysis"
Assert-Contains $templateText "阶段目的" "douyin-case-analysis-template.md must explain the purpose of each script-loop stage"
Assert-Contains $templateText "关键话术" "douyin-case-analysis-template.md must include key talk-track examples for each script-loop stage"
Assert-Contains $templateText "观众反应" "douyin-case-analysis-template.md must include audience response signals for each script-loop stage"
Assert-Contains $skillText "Do not add a key screenshot/evidence column" "SKILL.md must forbid a screenshot/evidence column in the UI table"
Assert-Contains $skillText "do not include the UI screenshot section by default" "SKILL.md must stop default UI screenshot insertion"
Assert-Contains $uiEvidenceText "ui-evidence-manifest.json" "export-ui-evidence.ps1 must write a manifest for report generation"
Assert-Contains $uiEvidenceText "UI截图-标题贴片" "export-ui-evidence.ps1 must produce stable UI screenshot labels"
Assert-Contains $manualUiEvidenceText "ui-evidence-manifest.json" "new-ui-evidence-manifest.ps1 must write a manifest for report generation"
Assert-Contains $manualUiEvidenceText "TitleOverlayPath" "new-ui-evidence-manifest.ps1 must accept manually selected UI evidence images"
Assert-Contains $manualUiEvidenceText "manual UI evidence selection" "new-ui-evidence-manifest.ps1 must record that evidence was manually selected"
Assert-Contains $manualUiEvidenceText 'selection = $item.label' "new-ui-evidence-manifest.ps1 must use per-image labels as Feishu insertion anchors"
Assert-Contains $manualUiEvidenceText "supported UI evidence image" "new-ui-evidence-manifest.ps1 must reject non-image inputs"
Assert-Contains $commentSummaryText "comment_summary" "summarize-comments.ps1 must produce structured comment summaries"
Assert-Contains $commentSummaryText "download_intent" "summarize-comments.ps1 must classify download intent"
Assert-Contains $feishuPublishText "--new-title" "publish-feishu-report.ps1 must restore Feishu titles after overwrite"
Assert-Contains $feishuPublishText "ui-evidence-manifest.json" "publish-feishu-report.ps1 must insert UI evidence images from the manifest"
Assert-Contains $skillText "manual UI evidence selection" "SKILL.md must default to manual per-stream UI screenshot selection"
Assert-Contains $skillText "fixed-crop fallback only" "SKILL.md must treat fixed crop export as a fallback only"
Assert-Contains $skillText "script loop Mermaid flowchart" "SKILL.md must require a script loop Mermaid flowchart"
Assert-Contains $skillText "structured stage-by-stage text analysis" "SKILL.md must require structured text analysis for script loops"
Assert-Contains $skillText "default video-analysis segment length is 12 minutes" "SKILL.md must set the default video-analysis segment length"
Assert-Contains $skillText "maximum video-analysis segment length is 20 minutes" "SKILL.md must set the maximum video-analysis segment length"
Assert-Contains $skillText "up to 1 hour" "SKILL.md must support long livestream analysis through segmentation"
Assert-Contains $skillText "export-ui-evidence.ps1" "SKILL.md must mention the UI evidence export script"
Assert-Contains $skillText "summarize-comments.ps1" "SKILL.md must mention the comment summary script"
Assert-Contains $skillText "publish-feishu-report.ps1" "SKILL.md must mention the Feishu publish helper"
Assert-Contains $skillText "resolve-douyin-live-metadata.py" "SKILL.md must mention the metadata resolver"

Write-Host "live monitor script checks passed"

