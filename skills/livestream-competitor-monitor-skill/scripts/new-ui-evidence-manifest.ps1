param(
  [string]$SourceFrame = "",
  [string]$OutputDir = "",
  [string]$TitleOverlayPath = "",
  [string]$DownloadEntryPath = "",
  [string]$GuidanceSubtitlePath = "",
  [string]$CountdownWidgetPath = "",
  [string]$CommentAreaPath = "",
  [string]$OverallPath = "",
  [switch]$AllowMissing,
  [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

function New-Text {
  param([int[]]$CodePoints)
  return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Resolve-OptionalFile {
  param([string]$Path)
  if (-not $Path) {
    return $null
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "UI evidence image not found: $Path"
  }
  $item = Get-Item -LiteralPath $Path
  $allowedImageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".bmp")
  if ($allowedImageExtensions -notcontains $item.Extension.ToLowerInvariant()) {
    throw "Path is not a supported UI evidence image: $Path"
  }
  return $item.FullName
}

function Get-FirstProvidedPath {
  param([object[]]$Items)
  foreach ($item in $Items) {
    if ($item.source_path) {
      return $item.source_path
    }
  }
  return $null
}

function Copy-UiEvidenceImage {
  param(
    [string]$SourcePath,
    [string]$DestinationDir,
    [string]$BaseName,
    [bool]$ShouldOverwrite
  )

  $sourceItem = Get-Item -LiteralPath $SourcePath
  $extension = $sourceItem.Extension
  if (-not $extension) {
    $extension = ".png"
  }
  $destinationPath = Join-Path $DestinationDir "$BaseName$extension"
  $destinationFullPath = [System.IO.Path]::GetFullPath($destinationPath)
  if ($sourceItem.FullName -eq $destinationFullPath) {
    return $sourceItem.FullName
  }
  if ((Test-Path -LiteralPath $destinationPath) -and -not $ShouldOverwrite) {
    throw "Output image already exists: $destinationPath. Use -Overwrite to replace it."
  }
  Copy-Item -LiteralPath $sourceItem.FullName -Destination $destinationPath -Force:$ShouldOverwrite
  return (Get-Item -LiteralPath $destinationPath).FullName
}

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

# manual UI evidence selection; writes ui-evidence-manifest.json for Feishu publishing.
$items = @(
  [pscustomobject]@{ label = $labelTitle; caption = $captionTitle; key = "title_overlay"; source_path = Resolve-OptionalFile $TitleOverlayPath; file_base = "01-title-overlay"; width = 520 },
  [pscustomobject]@{ label = $labelDownload; caption = $captionDownload; key = "download_entry"; source_path = Resolve-OptionalFile $DownloadEntryPath; file_base = "02-download-entry"; width = 520 },
  [pscustomobject]@{ label = $labelSubtitle; caption = $captionSubtitle; key = "guidance_subtitle"; source_path = Resolve-OptionalFile $GuidanceSubtitlePath; file_base = "03-subtitle-social-proof"; width = 520 },
  [pscustomobject]@{ label = $labelCountdown; caption = $captionCountdown; key = "countdown_widget"; source_path = Resolve-OptionalFile $CountdownWidgetPath; file_base = "04-countdown-widget"; width = 420 },
  [pscustomobject]@{ label = $labelComment; caption = $captionComment; key = "comment_area"; source_path = Resolve-OptionalFile $CommentAreaPath; file_base = "05-comment-area"; width = 520 },
  [pscustomobject]@{ label = $labelOverall; caption = $captionOverall; key = "overall_live_room"; source_path = Resolve-OptionalFile $OverallPath; file_base = "06-overall-live-room"; width = 650 }
)

$firstProvidedPath = Get-FirstProvidedPath $items
if (-not $firstProvidedPath -and -not $AllowMissing) {
  throw "No UI evidence images were provided. Pass at least one image path, or use -AllowMissing."
}

if (-not $OutputDir) {
  if ($SourceFrame -and (Test-Path -LiteralPath $SourceFrame -PathType Leaf)) {
    $OutputDir = Join-Path (Split-Path -Parent (Get-Item -LiteralPath $SourceFrame).FullName) "ui-evidence-manual"
  } elseif ($firstProvidedPath) {
    $OutputDir = Join-Path (Split-Path -Parent $firstProvidedPath) "ui-evidence-manual"
  } else {
    $OutputDir = Join-Path (Get-Location).Path "ui-evidence-manual"
  }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

$manifestImages = New-Object System.Collections.Generic.List[object]
$missingImages = New-Object System.Collections.Generic.List[object]
foreach ($item in $items) {
  if (-not $item.source_path) {
    $missingImages.Add([pscustomobject]@{
      key = $item.key
      label = $item.label
    }) | Out-Null
    if (-not $AllowMissing) {
      Write-Warning "Missing UI evidence image: $($item.key)"
    }
    continue
  }

  $copiedPath = Copy-UiEvidenceImage -SourcePath $item.source_path -DestinationDir $OutputDir -BaseName $item.file_base -ShouldOverwrite ([bool]$Overwrite)
  $manifestImages.Add([pscustomobject]@{
    label = $item.label
    caption = $item.caption
    key = $item.key
    file = $copiedPath
    source_file = $item.source_path
    selection = $item.label
    width = $item.width
  }) | Out-Null
}

$resolvedSourceFrame = ""
if ($SourceFrame -and (Test-Path -LiteralPath $SourceFrame -PathType Leaf)) {
  $resolvedSourceFrame = (Get-Item -LiteralPath $SourceFrame).FullName
}

$manifestPath = Join-Path $OutputDir "ui-evidence-manifest.json"
$manifest = [pscustomobject]@{
  generated_at = (Get-Date).ToString("s")
  selection_mode = "manual UI evidence selection"
  source_frame = $resolvedSourceFrame
  images = $manifestImages
  missing_images = $missingImages
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host "UI evidence manifest: $manifestPath"
foreach ($image in $manifestImages) {
  Write-Host "$($image.label): $($image.file)"
}
if (($missingImages | Measure-Object).Count -gt 0) {
  Write-Host "Missing UI evidence images: $(($missingImages | ForEach-Object { $_.key }) -join ', ')"
}
