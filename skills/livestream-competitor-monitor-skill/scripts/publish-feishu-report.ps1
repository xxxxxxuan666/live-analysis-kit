param(
  [Parameter(Mandatory=$true)]
  [string]$ReportPath,
  [Parameter(Mandatory=$true)]
  [string]$Title,
  [string]$Doc = "",
  [string]$MainScreenshot = "",
  [string]$UiEvidenceDir = "",
  [string]$UiEvidenceManifest = "",
  [switch]$SkipImages
)

$ErrorActionPreference = "Stop"

function Resolve-LarkCli {
  $cmd = Get-Command lark-cli.cmd -ErrorAction SilentlyContinue
  if (-not $cmd) {
    $cmd = Get-Command lark-cli -ErrorAction SilentlyContinue
  }
  if (-not $cmd) {
    throw "lark-cli was not found. Install or authenticate lark-cli before publishing Feishu reports."
  }
  return $cmd.Source
}

function Invoke-LarkCli {
  param(
    [string]$CliPath,
    [string[]]$Arguments
  )
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    if ($CliPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
      $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $CliPath @Arguments 2>&1
    } else {
      $output = & $CliPath @Arguments 2>&1
    }
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $exitCode = $LASTEXITCODE
  $text = ($output | Out-String).Trim()
  if ($exitCode -ne 0) {
    throw "lark-cli failed with exit code $exitCode. Output: $text"
  }
  return $text
}

function ConvertFrom-LarkJson {
  param([string]$Text)
  try {
    return ($Text | ConvertFrom-Json)
  } catch {
    $first = $Text.IndexOf("{")
    $last = $Text.LastIndexOf("}")
    if ($first -ge 0 -and $last -gt $first) {
      return ($Text.Substring($first, $last - $first + 1) | ConvertFrom-Json)
    }
  }
  return $null
}

function Get-RelativePath {
  param(
    [string]$BaseDir,
    [string]$Path
  )
  $baseUri = [System.Uri]((Resolve-Path -LiteralPath $BaseDir).Path.TrimEnd("\") + "\")
  $pathUri = [System.Uri]((Resolve-Path -LiteralPath $Path).Path)
  return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace("/", "\")
}

function New-Text {
  param([int[]]$CodePoints)
  return -join ($CodePoints | ForEach-Object { [char]$_ })
}

if (-not (Test-Path -LiteralPath $ReportPath)) {
  throw "Report Markdown file not found: $ReportPath"
}

$reportItem = Get-Item -LiteralPath $ReportPath
$workDir = $reportItem.DirectoryName
$previousLocation = Get-Location
$cliPath = Resolve-LarkCli
$docRef = $Doc
$imagesInserted = 0
$mainScreenshotCaption = New-Text @(0x76F4, 0x64AD, 0x622A, 0x56FE, 0xFF08, 0x5F55, 0x5236, 0x5F00, 0x59CB, 0x65F6, 0xFF09)
$basicInfoSelection = New-Text @(0x76F4, 0x64AD, 0x95F4, 0x57FA, 0x672C, 0x4FE1, 0x606F)

try {
  Set-Location -LiteralPath $workDir
  $reportRef = "@./$($reportItem.Name)"
  if ($Doc) {
    Invoke-LarkCli -CliPath $cliPath -Arguments @(
      "docs", "+update",
      "--api-version", "v2",
      "--doc", $Doc,
      "--command", "overwrite",
      "--doc-format", "markdown",
      "--content", $reportRef
    ) | Out-Null
    Invoke-LarkCli -CliPath $cliPath -Arguments @(
      "docs", "+update",
      "--doc", $Doc,
      "--new-title", $Title,
      "--mode", "append",
      "--markdown", " "
    ) | Out-Null
  } else {
    $createOutput = Invoke-LarkCli -CliPath $cliPath -Arguments @(
      "docs", "+create",
      "--api-version", "v2",
      "--title", $Title,
      "--doc-format", "markdown",
      "--content", $reportRef
    )
    $createJson = ConvertFrom-LarkJson -Text $createOutput
    if ($createJson -and $createJson.data -and $createJson.data.document -and $createJson.data.document.url) {
      $docRef = [string]$createJson.data.document.url
    } else {
      $docRef = $createOutput
    }
    Invoke-LarkCli -CliPath $cliPath -Arguments @(
      "docs", "+update",
      "--doc", $docRef,
      "--new-title", $Title,
      "--mode", "append",
      "--markdown", " "
    ) | Out-Null
  }

  if (-not $SkipImages) {
    if ($MainScreenshot -and (Test-Path -LiteralPath $MainScreenshot)) {
      $mainRel = Get-RelativePath -BaseDir $workDir -Path $MainScreenshot
      Invoke-LarkCli -CliPath $cliPath -Arguments @(
        "docs", "+media-insert",
        "--doc", $docRef,
        "--file", $mainRel,
        "--type", "image",
        "--caption", $mainScreenshotCaption,
        "--selection-with-ellipsis", $basicInfoSelection,
        "--width", "800",
        "--align", "center"
      ) | Out-Null
      $imagesInserted += 1
    }

    if (-not $UiEvidenceManifest -and $UiEvidenceDir) {
      $UiEvidenceManifest = Join-Path $UiEvidenceDir "ui-evidence-manifest.json"
    }
    if ($UiEvidenceManifest -and (Test-Path -LiteralPath $UiEvidenceManifest)) {
      $manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $UiEvidenceManifest | ConvertFrom-Json
      $manifestImages = @($manifest.images)
      foreach ($image in $manifestImages) {
        $imagePath = [string]$image.file
        if (-not $imagePath -or -not (Test-Path -LiteralPath $imagePath)) {
          continue
        }
        $imageRel = Get-RelativePath -BaseDir $workDir -Path $imagePath
        $selection = [string]$image.selection
        if (-not $selection) {
          $selection = [string]$image.label
        }
        $caption = [string]$image.caption
        if (-not $caption) {
          $caption = [string]$image.label
        }
        $width = "520"
        if ($image.width) {
          $width = [string]$image.width
        }
        Invoke-LarkCli -CliPath $cliPath -Arguments @(
          "docs", "+media-insert",
          "--doc", $docRef,
          "--file", $imageRel,
          "--type", "image",
          "--caption", $caption,
          "--selection-with-ellipsis", $selection,
          "--width", $width,
          "--align", "center"
        ) | Out-Null
        $imagesInserted += 1
      }
    }
  }
} finally {
  Set-Location -LiteralPath $previousLocation
}

[pscustomobject]@{
  ok = $true
  doc = $docRef
  title = $Title
  images_inserted = $imagesInserted
  manifest = $UiEvidenceManifest
} | ConvertTo-Json -Depth 4
