param(
  [string]$Url = "",
  [string]$RoomName = "",
  [ValidateSet("video", "audio")]
  [string]$Mode = "video",
  [string]$GameProductName = "",
  [string]$SystemAudioDevice = "",
  [string]$ArchiveRoot = "",
  [string]$SessionFile = "",
  [string]$CommentCrawlerPath = "",
  [switch]$DisableComments,
  [switch]$DisableAutoMetadata,
  [int]$MetadataTimeoutSeconds = 10,
  [int]$FrameRate = 15
)

$ErrorActionPreference = "Stop"

function Get-SafeFileName {
  param([string]$Name)
  $invalid = [System.IO.Path]::GetInvalidFileNameChars()
  $escaped = ($invalid | ForEach-Object { [regex]::Escape([string]$_) }) -join "|"
  $safe = ($Name -replace $escaped, "_").Trim()
  if (-not $safe) {
    return "unknown-room"
  }
  return $safe
}

function Resolve-FfmpegPath {
  $preferred = Join-Path $env:USERPROFILE "Tools\ffmpeg\bin\ffmpeg.exe"
  if (Test-Path -LiteralPath $preferred) {
    return (Get-Item -LiteralPath $preferred).FullName
  }
  $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
  if (-not $cmd) {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  }
  if ($cmd) {
    return $cmd.Source
  }
  throw "ffmpeg was not found. Install ffmpeg or add it to PATH."
}

function Resolve-PythonPath {
  $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
  if (-not $cmd) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
  }
  if ($cmd) {
    return $cmd.Source
  }
  return ""
}

function Resolve-CommentCrawlerPath {
  param([string]$RequestedPath)
  if ($RequestedPath) {
    return $RequestedPath
  }
  return (Join-Path $PSScriptRoot "douyin-comment-crawler.py")
}

function Resolve-MetadataScriptPath {
  return (Join-Path $PSScriptRoot "resolve-douyin-live-metadata.py")
}

function Resolve-LiveMetadata {
  param(
    [string]$LiveUrl,
    [string]$OutputPath,
    [int]$TimeoutSeconds
  )
  $metadata = [ordered]@{
    room_name = ""
    game_product_name = ""
    viewer_count = ""
    confidence = 0
    source = "disabled"
    error = ""
  }
  if (-not $LiveUrl) {
    return [pscustomobject]$metadata
  }
  $pythonPath = Resolve-PythonPath
  $metadataScript = Resolve-MetadataScriptPath
  if (-not $pythonPath) {
    $metadata.source = "failed"
    $metadata.error = "python not found"
    return [pscustomobject]$metadata
  }
  if (-not (Test-Path -LiteralPath $metadataScript)) {
    $metadata.source = "failed"
    $metadata.error = "metadata resolver not found: $metadataScript"
    return [pscustomobject]$metadata
  }
  try {
    $args = @(
      $metadataScript,
      "--url", $LiveUrl,
      "--output", $OutputPath,
      "--timeout", "$TimeoutSeconds"
    )
    $output = & $pythonPath @args 2>&1 | Out-String
    if (Test-Path -LiteralPath $OutputPath) {
      return (Get-Content -Raw -Encoding utf8 -LiteralPath $OutputPath | ConvertFrom-Json)
    }
    return ($output | ConvertFrom-Json)
  } catch {
    $metadata.source = "failed"
    $metadata.error = $_.Exception.Message
    return [pscustomobject]$metadata
  }
}

function Get-DouyinRoomFallbackName {
  param([string]$LiveUrl)
  $roomId = "unknown"
  if ($LiveUrl -match "live\.douyin\.com/(\d+)") {
    $roomId = $Matches[1]
  }
  $douyinText = -join ([char]0x6296, [char]0x97F3, [char]0x76F4, [char]0x64AD, [char]0x95F4)
  return "$douyinText-$roomId"
}

function Invoke-FfmpegDeviceList {
  param([string]$FfmpegPath)
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    return (& $FfmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Out-String)
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
}

function Get-DirectShowAudioDevices {
  param([string]$FfmpegPath)
  $deviceOutput = Invoke-FfmpegDeviceList -FfmpegPath $FfmpegPath
  $devices = New-Object System.Collections.Generic.List[string]
  $inAudio = $false
  foreach ($line in ($deviceOutput -split "`r?`n")) {
    if ($line -notmatch "Alternative name" -and $line -match '^\[.*?\]\s+"(.+?)"\s+\(audio\)') {
      $devices.Add($Matches[1]) | Out-Null
      continue
    }
    if ($line -match "DirectShow audio devices") {
      $inAudio = $true
      continue
    }
    if ($inAudio -and $line -match "DirectShow video devices") {
      break
    }
    if ($inAudio -and $line -notmatch "Alternative name" -and $line -match '^\[dshow.*?\]\s+"(.+?)"') {
      $devices.Add($Matches[1]) | Out-Null
    }
  }
  return $devices
}

function Resolve-SystemAudioDevice {
  param(
    [string]$FfmpegPath,
    [string]$RequestedDevice
  )
  if ($RequestedDevice) {
    return $RequestedDevice
  }

  $devices = Get-DirectShowAudioDevices -FfmpegPath $FfmpegPath
  $stereoMixCn = -join ([char]0x7ACB, [char]0x4F53, [char]0x58F0, [char]0x6DF7, [char]0x97F3)
  $speakerCn = -join ([char]0x626C, [char]0x58F0, [char]0x5668)
  $microphoneCn = -join ([char]0x9EA6, [char]0x514B, [char]0x98CE)
  $includePatterns = @("stereo mix", $stereoMixCn, "virtual audio", "virtual-audio", "cable", "vb-audio", "voicemeeter", "obs", "desktop audio", "sound capture", "loopback", "speaker", $speakerCn)
  $excludePatterns = @("microphone", "mic", "array", $microphoneCn)

  foreach ($device in $devices) {
    $lower = $device.ToLowerInvariant()
    $isExcluded = $false
    foreach ($pattern in $excludePatterns) {
      if ($lower.Contains($pattern)) {
        $isExcluded = $true
        break
      }
    }
    if ($isExcluded) {
      continue
    }
    foreach ($pattern in $includePatterns) {
      if ($lower.Contains($pattern.ToLowerInvariant())) {
        return $device
      }
    }
  }

  if ($devices.Count -gt 0) {
    $deviceList = $devices -join "; "
  } else {
    $deviceList = "(none found)"
  }
  throw "No system audio device found. Configure Stereo Mix, virtual audio cable, OBS audio, or pass -SystemAudioDevice. DirectShow audio devices: $deviceList"
}

$ffmpegPath = Resolve-FfmpegPath
$resolvedAudioDevice = Resolve-SystemAudioDevice -FfmpegPath $ffmpegPath -RequestedDevice $SystemAudioDevice

if (-not $ArchiveRoot) {
  $archiveFolderName = -join ([char]0x76F4, [char]0x64AD, [char]0x5F55, [char]0x6587, [char]0x4EF6, [char]0x5B58, [char]0x6863)
  $ArchiveRoot = Join-Path ([Environment]::GetFolderPath("Desktop")) $archiveFolderName
}
New-Item -ItemType Directory -Force -Path $ArchiveRoot | Out-Null
$ArchiveRoot = (Resolve-Path -LiteralPath $ArchiveRoot).Path

$preArchiveDir = Join-Path $ArchiveRoot "_metadata"
New-Item -ItemType Directory -Force -Path $preArchiveDir | Out-Null
$preMetadataStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$autoMetadataPath = Join-Path $preArchiveDir "$preMetadataStamp-auto-metadata.json"
$autoMetadata = [pscustomobject]@{
  room_name = ""
  game_product_name = ""
  viewer_count = ""
  confidence = 0
  source = "not_requested"
  error = ""
}
if ($Url -and -not $DisableAutoMetadata -and ((-not $RoomName) -or (-not $GameProductName))) {
  $autoMetadata = Resolve-LiveMetadata -LiveUrl $Url -OutputPath $autoMetadataPath -TimeoutSeconds $MetadataTimeoutSeconds
}
if ((-not $RoomName) -and $autoMetadata.room_name) {
  $RoomName = [string]$autoMetadata.room_name
}
if (-not $RoomName) {
  $RoomName = Get-DouyinRoomFallbackName -LiveUrl $Url
}
if ((-not $GameProductName) -and $autoMetadata.game_product_name) {
  $GameProductName = [string]$autoMetadata.game_product_name
}

$safeRoomName = Get-SafeFileName -Name $RoomName
$safeGameProductName = Get-SafeFileName -Name $GameProductName
$archiveDate = Get-Date -Format "yyyyMMdd"
if ($GameProductName) {
  $archiveFolderBaseName = "$safeGameProductName-$safeRoomName-$archiveDate"
} else {
  $archiveFolderBaseName = "$safeRoomName-$archiveDate"
}
$archiveFolderName = Get-SafeFileName -Name $archiveFolderBaseName
$roomDir = Join-Path $ArchiveRoot $archiveFolderName
New-Item -ItemType Directory -Force -Path $roomDir | Out-Null
$roomDir = (Resolve-Path -LiteralPath $roomDir).Path

if (-not $SessionFile) {
  $SessionFile = Join-Path $roomDir "live-monitor-session.json"
}
$sessionDir = Split-Path -Parent $SessionFile
if ($sessionDir) {
  New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
}

if ($Url -and $DisableComments) {
  Start-Process $Url
  Start-Sleep -Seconds 3
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseName = "$safeRoomName-$stamp"
$log = Join-Path $roomDir "$baseName.log"

$commentsProcess = $null
$commentsPath = ""
$commentsLog = ""
$commentsErrorLog = ""
$commentsStatus = "disabled"
if ($Url -and -not $DisableComments) {
  $commentBaseName = "$safeRoomName-$stamp"
  $commentsPath = Join-Path $roomDir "$commentBaseName-comments.jsonl"
  $commentsLog = Join-Path $roomDir "$commentBaseName-comments.log"
  $commentsErrorLog = Join-Path $roomDir "$commentBaseName-comments.err.log"
  $resolvedCommentCrawlerPath = Resolve-CommentCrawlerPath -RequestedPath $CommentCrawlerPath
  $pythonPath = Resolve-PythonPath
  if ($pythonPath -and (Test-Path -LiteralPath $resolvedCommentCrawlerPath)) {
    try {
      $commentArgs = @(
        "-u",
        "`"$resolvedCommentCrawlerPath`"",
        "--url", "`"$Url`"",
        "--output", "`"$commentsPath`""
      )
      $commentsProcess = Start-Process -FilePath $pythonPath -ArgumentList $commentArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $commentsLog -RedirectStandardError $commentsErrorLog
      $commentsStatus = "started"
    } catch {
      $commentsStatus = "failed: $($_.Exception.Message)"
      Write-Warning "Comment crawler did not start: $($_.Exception.Message)"
    }
  } else {
    if (-not $pythonPath) {
      $commentsStatus = "failed: python not found"
    } else {
      $commentsStatus = "failed: crawler not found: $resolvedCommentCrawlerPath"
    }
    Write-Warning "Comment crawler did not start: $commentsStatus"
  }
}

if ($Mode -eq "video") {
  $mediaPath = Join-Path $roomDir "$baseName.mkv"
  $audioInput = "`"audio=$resolvedAudioDevice`""
  $ffmpegArgs = @(
    "-y",
    "-f", "gdigrab",
    "-framerate", "$FrameRate",
    "-i", "desktop",
    "-f", "dshow",
    "-i", $audioInput,
    "-c:v", "libx264",
    "-preset", "ultrafast",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "128k",
    "`"$mediaPath`""
  )
} else {
  $mediaPath = Join-Path $roomDir "$baseName.wav"
  $audioInput = "`"audio=$resolvedAudioDevice`""
  $ffmpegArgs = @(
    "-y",
    "-f", "dshow",
    "-i", $audioInput,
    "-vn",
    "-ac", "1",
    "-ar", "16000",
    "-c:a", "pcm_s16le",
    "`"$mediaPath`""
  )
}

$process = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs -WindowStyle Hidden -PassThru -RedirectStandardError $log
$pointerSessionFile = Join-Path $ArchiveRoot "live-monitor-session.json"

$session = [ordered]@{
  pid = $process.Id
  ffmpeg_path = $ffmpegPath
  url = $Url
  room_name = $RoomName
  safe_room_name = $safeRoomName
  archive_folder_name = $archiveFolderName
  mode = $Mode
  archive_root = $ArchiveRoot
  room_dir = $roomDir
  base_name = $baseName
  media_path = $mediaPath
  log = $log
  system_audio_device = $resolvedAudioDevice
  game_product_name = $GameProductName
  auto_metadata_path = $autoMetadataPath
  auto_room_name = [string]$autoMetadata.room_name
  auto_game_product_name = [string]$autoMetadata.game_product_name
  auto_viewer_count = [string]$autoMetadata.viewer_count
  metadata_confidence = $autoMetadata.confidence
  metadata_source = [string]$autoMetadata.source
  metadata_error = [string]$autoMetadata.error
  comments_path = $commentsPath
  comments_pid = if ($commentsProcess) { $commentsProcess.Id } else { $null }
  comments_log = $commentsLog
  comments_error_log = $commentsErrorLog
  comments_status = $commentsStatus
  session_file = $SessionFile
  pointer_session_file = $pointerSessionFile
  started_at = (Get-Date).ToString("s")
  note = "Say pause, then run stop-live-monitor.ps1 to stop recording and transcribe."
}

$session | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SessionFile -Encoding utf8
$session | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $pointerSessionFile -Encoding utf8

Write-Host "Live monitor started."
Write-Host "Mode: $Mode"
Write-Host "Room: $RoomName"
if ($GameProductName) {
  Write-Host "Game product: $GameProductName"
}
if ($autoMetadataPath -and (Test-Path -LiteralPath $autoMetadataPath)) {
  Write-Host "Auto metadata: $autoMetadataPath"
}
Write-Host "Archive folder: $roomDir"
Write-Host "System audio device: $resolvedAudioDevice"
if ($commentsPath) {
  Write-Host "Comments file: $commentsPath"
  Write-Host "Comments status: $commentsStatus"
}
Write-Host "PID: $($process.Id)"
Write-Host "Media file: $mediaPath"
Write-Host "Session file: $SessionFile"
Write-Host "Pause command: powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\stop-live-monitor.ps1`""
