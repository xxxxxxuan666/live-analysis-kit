param(
  [int]$DurationSeconds = 300,
  [string]$OutputDir = ".",
  [string]$FileName = ""
)

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
  Write-Error "ffmpeg was not found in PATH. Install ffmpeg first, then run this script again."
  exit 1
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($FileName)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $FileName = "douyin-live-$stamp.mp4"
}

$output = Join-Path $OutputDir $FileName

Write-Host "Recording the visible desktop for $DurationSeconds seconds."
Write-Host "Before continuing, make sure only the authorized Douyin live room and intended recording area are visible."

& ffmpeg -y `
  -f gdigrab `
  -framerate 15 `
  -i desktop `
  -t $DurationSeconds `
  -c:v libx264 `
  -preset ultrafast `
  -pix_fmt yuv420p `
  $output

if ($LASTEXITCODE -ne 0) {
  Write-Error "ffmpeg recording failed."
  exit $LASTEXITCODE
}

Write-Host "Saved recording to: $output"
