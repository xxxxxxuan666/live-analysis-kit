param(
  [Parameter(Mandatory=$true)]
  [string]$VideoPath,
  [string]$OutputDir = "",
  [int]$FrameEverySeconds = 30
)

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
  Write-Error "ffmpeg was not found in PATH."
  exit 1
}

if (-not (Test-Path -LiteralPath $VideoPath)) {
  Write-Error "Video file not found: $VideoPath"
  exit 1
}

if (-not $OutputDir) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
  $OutputDir = Join-Path (Split-Path -Parent $VideoPath) "$base-assets"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$audio = Join-Path $OutputDir "audio.wav"
$framesDir = Join-Path $OutputDir "frames"
$meta = Join-Path $OutputDir "metadata.txt"
New-Item -ItemType Directory -Force -Path $framesDir | Out-Null

& ffmpeg -y -i $VideoPath -vn -ac 1 -ar 16000 $audio
& ffmpeg -y -i $VideoPath -vf "fps=1/$FrameEverySeconds" (Join-Path $framesDir "frame-%04d.jpg")
& ffmpeg -hide_banner -i $VideoPath 2> $meta

Write-Host "Assets extracted."
Write-Host "Audio: $audio"
Write-Host "Frames: $framesDir"
Write-Host "Metadata: $meta"
