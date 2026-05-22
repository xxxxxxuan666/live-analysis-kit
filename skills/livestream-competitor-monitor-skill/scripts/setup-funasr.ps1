param(
  [string]$EnvDir = ""
)

$skillDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $EnvDir) {
  $EnvDir = Join-Path $skillDir ".venv-funasr"
}

$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
  Write-Host "uv was not found. Installing uv for Python environment management..."
  $installScript = Join-Path $env:TEMP "uv-install.ps1"
  Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile $installScript -UseBasicParsing
  powershell -ExecutionPolicy Bypass -File $installScript
  $candidate = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
  if (Test-Path -LiteralPath $candidate) {
    $env:Path = "$([System.IO.Path]::GetDirectoryName($candidate));$env:Path"
  }
  $uv = Get-Command uv -ErrorAction SilentlyContinue
}

if (-not $uv) {
  Write-Error "uv installation failed or uv is not in PATH."
  exit 1
}

if (-not (Test-Path -LiteralPath $EnvDir)) {
  & $uv.Source venv --python 3.10 $EnvDir
}

$python = Join-Path $EnvDir "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
  Write-Error "Python executable not found after venv creation: $python"
  exit 1
}

& $uv.Source pip install --python $python -U pip
& $uv.Source pip install --python $python -U torch torchaudio --index-url https://download.pytorch.org/whl/cpu
& $uv.Source pip install --python $python -U funasr modelscope huggingface_hub soundfile

Write-Host "FunASR environment ready."
Write-Host "Python: $python"
