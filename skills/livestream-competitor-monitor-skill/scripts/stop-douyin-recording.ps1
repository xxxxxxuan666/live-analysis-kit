param(
  [string]$SessionFile = ".\recordings\douyin-recording-session.json"
)

if (-not (Test-Path -LiteralPath $SessionFile)) {
  Write-Error "Session file not found: $SessionFile"
  exit 1
}

$session = Get-Content -Raw -Encoding utf8 -LiteralPath $SessionFile | ConvertFrom-Json
$pidValue = [int]$session.pid
$output = $session.output_planned

$process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
if (-not $process -and $output) {
  $escapedOutput = [System.IO.Path]::GetFileName($output)
  $processInfo = Get-CimInstance Win32_Process -Filter "name = 'ffmpeg.exe'" |
    Where-Object { $_.CommandLine -like "*$escapedOutput*" } |
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

if (Test-Path -LiteralPath $output) {
  $item = Get-Item -LiteralPath $output
  Write-Host "Output: $($item.FullName)"
  Write-Host "Size bytes: $($item.Length)"
} else {
  Write-Warning "Expected output file was not found: $output"
}

$session | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date).ToString("s") -Force
$session | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SessionFile -Encoding utf8
