param(
  [string]$SessionFile = "",
  [string]$Hotword = "",
  [switch]$SkipTranscription
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SessionFile) {
  $archiveFolderName = -join ([char]0x76F4, [char]0x64AD, [char]0x5F55, [char]0x6587, [char]0x4EF6, [char]0x5B58, [char]0x6863)
  $SessionFile = Join-Path (Join-Path ([Environment]::GetFolderPath("Desktop")) $archiveFolderName) "live-monitor-session.json"
}

if (-not (Test-Path -LiteralPath $SessionFile)) {
  throw "Session file not found: $SessionFile"
}

$session = Get-Content -Raw -Encoding utf8 -LiteralPath $SessionFile | ConvertFrom-Json
$pidValue = [int]$session.pid
$mediaPath = [string]$session.media_path
$mode = [string]$session.mode
$roomDir = [string]$session.room_dir
$baseName = [string]$session.base_name
$commentsPath = [string]$session.comments_path
$commentsLog = [string]$session.comments_log
$commentsErrorLog = [string]$session.comments_error_log
$commentsPid = $null
if ($session.comments_pid -ne $null -and "$($session.comments_pid)" -ne "") {
  $commentsPid = [int]$session.comments_pid
}

$process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
if (-not $process -and $mediaPath) {
  $mediaFileName = [System.IO.Path]::GetFileName($mediaPath)
  $processInfo = Get-CimInstance Win32_Process -Filter "name = 'ffmpeg.exe'" |
    Where-Object { $_.CommandLine -like "*$mediaFileName*" } |
    Select-Object -First 1
  if ($processInfo) {
    $process = Get-Process -Id $processInfo.ProcessId -ErrorAction SilentlyContinue
    $pidValue = [int]$processInfo.ProcessId
  }
}

if ($process) {
  Stop-Process -Id $pidValue -Force
  Start-Sleep -Seconds 2
  Write-Host "Recording stopped."
} else {
  Write-Warning "Recording process was not running."
}

$commentsStopped = $false
if ($commentsPid) {
  $commentsProcess = Get-Process -Id $commentsPid -ErrorAction SilentlyContinue
  if (-not $commentsProcess -and $commentsPath) {
    $commentsFileName = [System.IO.Path]::GetFileName($commentsPath)
    $commentsProcessInfo = Get-CimInstance Win32_Process -Filter "name = 'python.exe'" |
      Where-Object { $_.CommandLine -like "*$commentsFileName*" } |
      Select-Object -First 1
    if ($commentsProcessInfo) {
      $commentsProcess = Get-Process -Id $commentsProcessInfo.ProcessId -ErrorAction SilentlyContinue
      $commentsPid = [int]$commentsProcessInfo.ProcessId
    }
  }
  if ($commentsProcess) {
    Stop-Process -Id $commentsPid -Force
    Start-Sleep -Seconds 1
    $commentsStopped = $true
    Write-Host "Comment crawler stopped."
  }
}

if (-not (Test-Path -LiteralPath $mediaPath)) {
  throw "Expected media file was not found: $mediaPath"
}

$mediaItem = Get-Item -LiteralPath $mediaPath
if ($mediaItem.Length -le 0) {
  throw "Media file is empty: $mediaPath"
}

$audioPath = ""
$assetsDir = ""
if ($mode -eq "video") {
  $assetsDir = Join-Path $roomDir "$baseName-assets"
  powershell -ExecutionPolicy Bypass -File (Join-Path $scriptDir "extract-recording-assets.ps1") -VideoPath $mediaPath -OutputDir $assetsDir
  $extractedAudio = Join-Path $assetsDir "audio.wav"
  if (-not (Test-Path -LiteralPath $extractedAudio)) {
    throw "Extracted audio file was not found: $extractedAudio"
  }
  $audioPath = Join-Path $roomDir "$baseName.wav"
  Copy-Item -LiteralPath $extractedAudio -Destination $audioPath -Force
} elseif ($mode -eq "audio") {
  $audioPath = $mediaPath
  $assetsDir = $roomDir
} else {
  throw "Unsupported session mode: $mode"
}

$transcriptJson = ""
$transcriptMarkdown = ""
if (-not $SkipTranscription) {
  $transcribeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $scriptDir "transcribe-recording-audio.ps1"),
    "-AudioPath", $audioPath,
    "-OutputDir", $roomDir
  )
  if ($Hotword) {
    $transcribeArgs += @("-Hotword", $Hotword)
  }
  powershell @transcribeArgs
  $transcriptJson = Join-Path $roomDir "$baseName-funasr.json"
  $transcriptMarkdown = Join-Path $roomDir "$baseName-funasr.md"
}

$session | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date).ToString("s") -Force
$session | Add-Member -NotePropertyName media_size_bytes -NotePropertyValue $mediaItem.Length -Force
$session | Add-Member -NotePropertyName assets_dir -NotePropertyValue $assetsDir -Force
$session | Add-Member -NotePropertyName audio_path -NotePropertyValue $audioPath -Force
$session | Add-Member -NotePropertyName transcript_json -NotePropertyValue $transcriptJson -Force
$session | Add-Member -NotePropertyName transcript_markdown -NotePropertyValue $transcriptMarkdown -Force
$commentsCount = 0
if ($commentsPath -and (Test-Path -LiteralPath $commentsPath)) {
  $commentsCount = (Get-Content -LiteralPath $commentsPath | Measure-Object -Line).Lines
}
$session | Add-Member -NotePropertyName comments_path -NotePropertyValue $commentsPath -Force
$session | Add-Member -NotePropertyName comments_log -NotePropertyValue $commentsLog -Force
$session | Add-Member -NotePropertyName comments_error_log -NotePropertyValue $commentsErrorLog -Force
$session | Add-Member -NotePropertyName comments_count -NotePropertyValue $commentsCount -Force
$session | Add-Member -NotePropertyName comments_stopped -NotePropertyValue $commentsStopped -Force

$session | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SessionFile -Encoding utf8
if ($session.pointer_session_file) {
  $session | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $session.pointer_session_file -Encoding utf8
}

Write-Host "Media file: $mediaPath"
Write-Host "Audio file: $audioPath"
if ($transcriptMarkdown) {
  Write-Host "Transcript Markdown: $transcriptMarkdown"
  Write-Host "Transcript JSON: $transcriptJson"
}
if ($commentsPath) {
  Write-Host "Comments JSONL: $commentsPath"
  Write-Host "Comments count: $commentsCount"
}
Write-Host "Archive folder: $roomDir"
