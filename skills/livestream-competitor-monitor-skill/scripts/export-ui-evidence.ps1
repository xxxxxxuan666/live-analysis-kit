param(
  [Parameter(Mandatory=$true)]
  [string]$SourceImage,
  [string]$OutputDir = "",
  [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

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

function Invoke-FfmpegImageExport {
  param(
    [string]$FfmpegPath,
    [string]$InputPath,
    [string]$OutputPath,
    [string]$VideoFilter,
    [bool]$ShouldOverwrite
  )
  if ((Test-Path -LiteralPath $OutputPath) -and -not $ShouldOverwrite) {
    return
  }
  $overwriteFlag = "-n"
  if ($ShouldOverwrite) {
    $overwriteFlag = "-y"
  }
  $args = @(
    "-hide_banner",
    "-loglevel", "error",
    $overwriteFlag,
    "-i", $InputPath,
    "-frames:v", "1",
    "-vf", $VideoFilter,
    "-q:v", "2",
    "-update", "1",
    $OutputPath
  )
  & $FfmpegPath @args | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed while exporting UI evidence image: $OutputPath"
  }
}

function New-Text {
  param([int[]]$CodePoints)
  return -join ($CodePoints | ForEach-Object { [char]$_ })
}

if (-not (Test-Path -LiteralPath $SourceImage)) {
  throw "Source image not found: $SourceImage"
}

$sourceItem = Get-Item -LiteralPath $SourceImage
if (-not $OutputDir) {
  $OutputDir = Join-Path $sourceItem.DirectoryName "ui-evidence"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

$ffmpegPath = Resolve-FfmpegPath
$labelTitle = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x6807, 0x9898, 0x8D34, 0x7247)
$labelDownload = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x5546, 0x54C1, 0x5361, 0x798F, 0x5229, 0x5165, 0x53E3)
$labelSubtitle = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x5F15, 0x5BFC, 0x8BED, 0x5B57, 0x5E55)
$labelCountdown = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x5012, 0x8BA1, 0x65F6, 0x4F18, 0x60E0, 0x6302, 0x4EF6)
$labelComment = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x8BC4, 0x8BBA, 0x533A, 0x53EF, 0x89C1, 0x4FE1, 0x606F)
$labelOverall = New-Text @(0x0055, 0x0049, 0x622A, 0x56FE, 0x002D, 0x7EFC, 0x5408, 0x753B, 0x9762)
$captionTitle = New-Text @(0x6807, 0x9898, 0x002F, 0x8D34, 0x7247)
$captionDownload = New-Text @(0x5546, 0x54C1, 0x5361, 0x002F, 0x798F, 0x5229, 0x5165, 0x53E3)
$captionSubtitle = New-Text @(0x5F15, 0x5BFC, 0x8BED, 0x002F, 0x5B57, 0x5E55)
$captionCountdown = New-Text @(0x5012, 0x8BA1, 0x65F6, 0x002F, 0x4F18, 0x60E0, 0x002F, 0x6302, 0x4EF6)
$captionComment = New-Text @(0x8BC4, 0x8BBA, 0x533A, 0x53EF, 0x89C1, 0x4FE1, 0x606F)
$captionOverall = New-Text @(0x7EFC, 0x5408, 0x753B, 0x9762)

# Stable labels for tests/report templates: UI截图-标题贴片, UI截图-商品卡福利入口, UI截图-引导语字幕, UI截图-倒计时优惠挂件, UI截图-评论区可见信息, UI截图-综合画面.
$items = @(
  [pscustomobject]@{
    label = $labelTitle
    caption = $captionTitle
    file_name = "01-title-overlay.jpg"
    selection = $labelTitle
    filter = "crop=620:220:0:120"
    width = 520
  },
  [pscustomobject]@{
    label = $labelDownload
    caption = $captionDownload
    file_name = "02-download-entry.jpg"
    selection = $labelDownload
    filter = "crop=900:230:440:820"
    width = 520
  },
  [pscustomobject]@{
    label = $labelSubtitle
    caption = $captionSubtitle
    file_name = "03-subtitle-social-proof.jpg"
    selection = $labelSubtitle
    filter = "crop=780:420:430:190"
    width = 520
  },
  [pscustomobject]@{
    label = $labelCountdown
    caption = $captionCountdown
    file_name = "04-countdown-widget.jpg"
    selection = $labelCountdown
    filter = "crop=360:170:960:120"
    width = 420
  },
  [pscustomobject]@{
    label = $labelComment
    caption = $captionComment
    file_name = "05-comment-area.jpg"
    selection = $labelComment
    filter = "crop=450:830:1420:130"
    width = 520
  },
  [pscustomobject]@{
    label = $labelOverall
    caption = $captionOverall
    file_name = "06-overall-live-room.jpg"
    selection = $labelOverall
    filter = "scale=940:-2"
    width = 650
  }
)

$manifestImages = New-Object System.Collections.Generic.List[object]
foreach ($item in $items) {
  $outputPath = Join-Path $OutputDir $item.file_name
  Invoke-FfmpegImageExport -FfmpegPath $ffmpegPath -InputPath $sourceItem.FullName -OutputPath $outputPath -VideoFilter $item.filter -ShouldOverwrite ([bool]$Overwrite)
  $manifestImages.Add([pscustomobject]@{
    label = $item.label
    caption = $item.caption
    file = (Get-Item -LiteralPath $outputPath).FullName
    selection = $item.selection
    width = $item.width
  }) | Out-Null
}

$manifestPath = Join-Path $OutputDir "ui-evidence-manifest.json"
$manifest = [pscustomobject]@{
  generated_at = (Get-Date).ToString("s")
  source_image = $sourceItem.FullName
  images = $manifestImages
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host "UI evidence manifest: $manifestPath"
foreach ($image in $manifestImages) {
  Write-Host "$($image.label): $($image.file)"
}
