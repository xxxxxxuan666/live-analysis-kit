param(
  [Parameter(Mandatory=$true)]
  [string]$AudioPath,
  [string]$OutputDir = "",
  [string]$EnvDir = "",
  [string]$Hotword = ""
)

if (-not (Test-Path -LiteralPath $AudioPath)) {
  Write-Error "Audio file not found: $AudioPath"
  exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillDir = Split-Path -Parent $scriptDir
if (-not $EnvDir) {
  $EnvDir = Join-Path $skillDir ".venv-funasr"
}
if (-not $OutputDir) {
  $OutputDir = Split-Path -Parent $AudioPath
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$python = Join-Path $EnvDir "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
  Write-Host "FunASR environment not found. Running setup-funasr.ps1 first..."
  powershell -ExecutionPolicy Bypass -File (Join-Path $scriptDir "setup-funasr.ps1") -EnvDir $EnvDir
}

if (-not (Test-Path -LiteralPath $python)) {
  Write-Error "Python executable not found: $python"
  exit 1
}

$base = [System.IO.Path]::GetFileNameWithoutExtension($AudioPath)
$json = Join-Path $OutputDir "$base-funasr.json"
$md = Join-Path $OutputDir "$base-funasr.md"

$args = @(
  (Join-Path $scriptDir "transcribe-funasr.py"),
  "--input", (Resolve-Path -LiteralPath $AudioPath).Path,
  "--output-json", $json,
  "--output-md", $md
)
if ($Hotword) {
  $args += @("--hotword", $Hotword)
}

& $python @args
if ($LASTEXITCODE -ne 0) {
  Write-Error "FunASR transcription failed."
  exit $LASTEXITCODE
}

Write-Host "Transcript JSON: $json"
Write-Host "Transcript Markdown: $md"
