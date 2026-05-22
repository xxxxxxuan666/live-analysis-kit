param(
  [string]$Url = "",
  [string]$OutputDir = ".\recordings",
  [string]$AudioDevice = "",
  [string]$SessionFile = ".\recordings\douyin-recording-session.json",
  [int]$FrameRate = 15
)

$preferredFfmpeg = Join-Path $env:USERPROFILE "Tools\ffmpeg\bin\ffmpeg.exe"
if (Test-Path -LiteralPath $preferredFfmpeg) {
  $ffmpegPath = (Get-Item -LiteralPath $preferredFfmpeg).FullName
} else {
  $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
  if (-not $ffmpeg) {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
  }
  if ($ffmpeg) {
    $ffmpegPath = $ffmpeg.Source
  }
}
if (-not $ffmpegPath) {
  Write-Error "ffmpeg was not found in PATH."
  exit 1
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

if ($Url) {
  Start-Process $Url
  Start-Sleep -Seconds 3
}

if (-not $AudioDevice) {
  $deviceOutput = & $ffmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Out-String
  $audioLines = $deviceOutput -split "`r?`n"
  $inAudio = $false
  foreach ($line in $audioLines) {
    if ($line -match 'DirectShow audio devices') { $inAudio = $true; continue }
    if ($inAudio -and $line -match '^\[dshow.*?\]\s+"(.+?)"') {
      $AudioDevice = $Matches[1]
      break
    }
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$output = Join-Path $OutputDir "douyin-live-$stamp.mkv"
$log = Join-Path $OutputDir "douyin-live-$stamp.log"

$args = @(
  "-y",
  "-f", "gdigrab",
  "-framerate", "$FrameRate",
  "-i", "desktop"
)

if ($AudioDevice) {
  $args += @("-f", "dshow", "-i", "`"audio=$AudioDevice`"")
}

$args += @(
  "-c:v", "libx264",
  "-preset", "ultrafast",
  "-pix_fmt", "yuv420p"
)

if ($AudioDevice) {
  $args += @("-c:a", "aac", "-b:a", "128k")
}

$args += @("`"$output`"")

$process = Start-Process -FilePath $ffmpegPath -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardError $log

$session = [ordered]@{
  pid = $process.Id
  ffmpeg_path = $ffmpegPath
  url = $Url
  output = (Resolve-Path -LiteralPath $output -ErrorAction SilentlyContinue).Path
  output_planned = $output
  log = $log
  audio_device = $AudioDevice
  started_at = (Get-Date).ToString("s")
  note = "Say pause, then run stop-douyin-recording.ps1 to stop this ffmpeg recording."
}

$session | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SessionFile -Encoding utf8

Write-Host "Recording started."
Write-Host "PID: $($process.Id)"
Write-Host "Output: $output"
if ($AudioDevice) {
  Write-Host "Audio device: $AudioDevice"
} else {
  Write-Warning "No DirectShow audio device found. For system audio capture, use start-live-monitor.ps1 with Stereo Mix, virtual audio, OBS audio, or -SystemAudioDevice."
}
Write-Host "Session file: $SessionFile"
