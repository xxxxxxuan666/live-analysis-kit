param(
  [Parameter(Mandatory=$true)]
  [string]$CommentsPath,
  [string]$OutputJson = "",
  [string]$OutputMarkdown = "",
  [int]$Top = 20
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CommentsPath)) {
  throw "Comments JSONL file not found: $CommentsPath"
}

$commentItem = Get-Item -LiteralPath $CommentsPath
if (-not $OutputJson) {
  $OutputJson = Join-Path $commentItem.DirectoryName "$($commentItem.BaseName)-summary.json"
}
if (-not $OutputMarkdown) {
  $OutputMarkdown = Join-Path $commentItem.DirectoryName "$($commentItem.BaseName)-summary.md"
}

function New-Text {
  param([int[]]$CodePoints)
  return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-CommentText {
  param([object]$Record)
  foreach ($field in @("content", "text", "comment", "message", "msg")) {
    if ($Record.PSObject.Properties.Name -contains $field) {
      $value = [string]$Record.$field
      if ($value.Trim()) {
        return $value.Trim()
      }
    }
  }
  return ""
}

function Test-ContainsAny {
  param(
    [string]$Text,
    [string[]]$Tokens
  )
  foreach ($token in $Tokens) {
    if ($Text.Contains($token)) {
      return $true
    }
  }
  return $false
}

$tokenSets = @{
  download_intent = @(
    (New-Text @(0x4E0B, 0x8F7D)),
    (New-Text @(0x5DF2, 0x4E0B, 0x8F7D)),
    (New-Text @(0x8BD5, 0x8BD5)),
    (New-Text @(0x5C0F, 0x624B, 0x67C4)),
    (New-Text @(0x94FE, 0x63A5)),
    (New-Text @(0x5165, 0x53E3)),
    (New-Text @(0x54EA, 0x91CC, 0x4E0B)),
    (New-Text @(0x5728, 0x54EA, 0x4E0B))
  )
  welfare_question = @(
    (New-Text @(0x798F, 0x888B)),
    (New-Text @(0x5468, 0x5361)),
    (New-Text @(0x6708, 0x5361)),
    (New-Text @(0x706F, 0x724C)),
    (New-Text @(0x798F, 0x5229)),
    (New-Text @(0x600E, 0x4E48, 0x9886)),
    (New-Text @(0x600E, 0x4E48, 0x62FF)),
    (New-Text @(0x793C, 0x7269)),
    (New-Text @(0x5956, 0x52B1))
  )
  server_or_id = @(
    (New-Text @(0x533A)),
    (New-Text @(0x670D)),
    "ID",
    "id",
    (New-Text @(0x738B, 0x56FD)),
    (New-Text @(0x8054, 0x76DF)),
    "_"
  )
  product_question = @(
    (New-Text @(0x597D, 0x73A9, 0x5417)),
    (New-Text @(0x600E, 0x4E48, 0x73A9)),
    (New-Text @(0x600E, 0x4E48)),
    (New-Text @(0x4E3A, 0x4EC0, 0x4E48)),
    (New-Text @(0x591A, 0x5C11)),
    (New-Text @(0x5417)),
    "?",
    (New-Text @(0xFF1F))
  )
  positive_signal = @(
    (New-Text @(0x597D, 0x73A9)),
    (New-Text @(0x4E0D, 0x9519)),
    (New-Text @(0x559C, 0x6B22)),
    (New-Text @(0x8F7B, 0x677E)),
    (New-Text @(0x51C6, 0x5907, 0x597D, 0x4E86)),
    (New-Text @(0x53EF, 0x4EE5)),
    (New-Text @(0x6709, 0x610F, 0x601D))
  )
}

function Get-Category {
  param([string]$Text)
  if (Test-ContainsAny -Text $Text -Tokens $tokenSets.download_intent) {
    return "download_intent"
  }
  if (Test-ContainsAny -Text $Text -Tokens $tokenSets.welfare_question) {
    return "welfare_question"
  }
  if ((Test-ContainsAny -Text $Text -Tokens $tokenSets.server_or_id) -or ($Text -match "[0-9]{3,}")) {
    return "server_or_id"
  }
  if (Test-ContainsAny -Text $Text -Tokens $tokenSets.positive_signal) {
    return "positive_signal"
  }
  if (Test-ContainsAny -Text $Text -Tokens $tokenSets.product_question) {
    return "product_question"
  }
  return "other"
}

$records = New-Object System.Collections.Generic.List[object]
$contents = New-Object System.Collections.Generic.List[string]
foreach ($line in Get-Content -LiteralPath $CommentsPath -Encoding utf8) {
  if (-not $line.Trim()) {
    continue
  }
  try {
    $record = $line | ConvertFrom-Json
    $text = Get-CommentText -Record $record
    if ($text) {
      $records.Add($record) | Out-Null
      $contents.Add($text) | Out-Null
    }
  } catch {
    continue
  }
}

$categoryOrder = @("download_intent", "welfare_question", "server_or_id", "product_question", "positive_signal", "other")
$categoryCounts = @{}
foreach ($category in $categoryOrder) {
  $categoryCounts[$category] = 0
}
$examples = @{}
foreach ($category in $categoryOrder) {
  $examples[$category] = New-Object System.Collections.Generic.List[string]
}

foreach ($text in $contents) {
  $category = Get-Category -Text $text
  $categoryCounts[$category] = [int]$categoryCounts[$category] + 1
  if ($examples[$category].Count -lt 8) {
    $examples[$category].Add($text) | Out-Null
  }
}

$topComments = $contents |
  Group-Object |
  Sort-Object Count -Descending |
  Select-Object -First $Top |
  ForEach-Object {
    [pscustomobject]@{
      content = $_.Name
      count = $_.Count
      category = Get-Category -Text $_.Name
    }
  }

$signals = [ordered]@{}
foreach ($category in $categoryOrder) {
  $signals[$category] = [pscustomobject]@{
    count = [int]$categoryCounts[$category]
    examples = @($examples[$category])
  }
}

$summary = [pscustomobject]@{
  comment_summary = [pscustomobject]@{
    source = $commentItem.FullName
    total = $contents.Count
    unique = ($contents | Select-Object -Unique).Count
    top_comments = @($topComments)
  }
  signals = $signals
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputJson -Encoding utf8

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# Comment Interaction Summary") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("- Total comments: $($contents.Count)") | Out-Null
$markdown.Add("- Unique comments: $(($contents | Select-Object -Unique).Count)") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("## Signal Categories") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("| Signal | Count | Examples |") | Out-Null
$markdown.Add("| --- | ---: | --- |") | Out-Null
foreach ($category in $categoryOrder) {
  $sample = (@($examples[$category]) | Select-Object -First 3) -join "; "
  $safeSample = $sample -replace "\|", "/"
  $markdown.Add("| $category | $($categoryCounts[$category]) | $safeSample |") | Out-Null
}
$markdown.Add("") | Out-Null
$markdown.Add("## Top Comments") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("| Comment/Signal | Count | Type |") | Out-Null
$markdown.Add("| --- | ---: | --- |") | Out-Null
foreach ($comment in $topComments) {
  $safeContent = $comment.content -replace "\|", "/"
  $markdown.Add("| $safeContent | $($comment.count) | $($comment.category) |") | Out-Null
}

$markdown | Set-Content -LiteralPath $OutputMarkdown -Encoding utf8

Write-Host "Comment summary JSON: $OutputJson"
Write-Host "Comment summary Markdown: $OutputMarkdown"
Write-Host "Comments total: $($contents.Count)"
