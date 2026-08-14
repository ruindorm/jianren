<#
.SYNOPSIS
  用 Pika API 呼叫 GPT Image 2 生成圖片。

.DESCRIPTION
  預設一律使用最低品質（1K / low）。這是刻意的預設值，不是省略設定的結果 ——
  實測 1K/low 比 2K/high 便宜約 47 倍、快 6 倍，而且文字渲染反而更準確。
  只有在明確需要放大輸出或極高細節時，才手動指定 -Quality / -Resolution。

  比例（-AspectRatio）沒有預設值，必須依用途明確指定。詳見 docs/圖片生成.md。

.EXAMPLE
  .\tools\gen-image.ps1 -PromptFile prompt.txt -AspectRatio 2:3 -Out assets/cover.png

.EXAMPLE
  .\tools\gen-image.ps1 -Prompt "pixel art sword" -AspectRatio 16:9 -Out out.png -Quality high
#>
[CmdletBinding()]
param(
  [string]   $Prompt,
  [string]   $PromptFile,

  [Parameter(Mandatory)]
  [ValidateSet('1:1','2:3','3:2','3:4','4:3','4:5','5:4','9:16','16:9','21:9')]
  [string]   $AspectRatio,

  [Parameter(Mandatory)]
  [string]   $Out,

  [ValidateSet('low','medium','high','auto')]
  [string]   $Quality = 'low',          # 預設最低，除非特別要求

  [ValidateSet('1K','2K','4K')]
  [string]   $Resolution = '1K',        # 預設最低，除非特別要求

  [ValidateSet('png','jpeg','webp')]
  [string]   $OutputFormat = 'png',

  [ValidateSet('auto','opaque','transparent')]
  [string]   $Background,

  [int]      $NumImages = 1,
  [string]   $EnvFile = 'D:\RU專案\.env',
  [int]      $TimeoutMinutes = 8
)

$ErrorActionPreference = 'Stop'

if (-not $Prompt -and -not $PromptFile) { throw '需要 -Prompt 或 -PromptFile' }
if ($PromptFile) { $Prompt = Get-Content $PromptFile -Raw -Encoding UTF8 }

# --- 金鑰：只從 .env 讀進記憶體，不印出、不寫入任何輸出 ---
$line = Get-Content $EnvFile -ErrorAction Stop | Select-String '^PIKA_API_KEY='
if (-not $line) { throw "在 $EnvFile 找不到 PIKA_API_KEY" }
$key = $line.ToString().Split('=', 2)[1].Trim()
$H = @{ 'X-API-Key' = $key; 'Content-Type' = 'application/json' }

$api  = 'https://api.dev.pika.art'
$path = '/v1/media/openai/gpt-image-2/text-to-image'

# --- 送出前先確認餘額（此端點免費） ---
$before = (Invoke-RestMethod -Uri "$api/billing/balance" -Headers $H).balance_micro_usd
Write-Host ("餘額      : USD {0}" -f ($before / 1e6))
Write-Host ("設定      : {0} / {1} / quality={2} / {3} 張" -f $AspectRatio, $Resolution, $Quality, $NumImages)

$payload = @{
  prompt        = $Prompt
  num_images    = $NumImages
  aspect_ratio  = $AspectRatio
  output_format = $OutputFormat
  resolution    = $Resolution
  quality       = $Quality
}
if ($Background) { $payload.background = $Background }
$body = $payload | ConvertTo-Json -Depth 5

$job = Invoke-RestMethod -Method Post -Uri "$api$path" -Headers $H `
        -Body ([Text.Encoding]::UTF8.GetBytes($body))
Write-Host "job       : $($job.id)"

$t0 = Get-Date
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
  Start-Sleep -Seconds 5
  $s = Invoke-RestMethod -Uri "$api/v1/media/jobs/$($job.id)" -Headers $H
} while ($s.status -notin @('completed','failed') -and (Get-Date) -lt $deadline)

if ($s.status -ne 'completed') {
  $s | ConvertTo-Json -Depth 6 | Write-Host
  throw "生成未完成：$($s.status)"
}

$c = Invoke-RestMethod -Uri "$api/v1/media/jobs/$($job.id)/content" -Headers $H
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
Invoke-WebRequest -Uri $c.url -OutFile $Out

$after = (Invoke-RestMethod -Uri "$api/billing/balance" -Headers $H).balance_micro_usd
Write-Host ""
Write-Host ("完成      : $Out  ({0} KB)" -f [math]::Round((Get-Item $Out).Length / 1KB, 1))
Write-Host ("用時      : {0}s" -f [math]::Round(((Get-Date) - $t0).TotalSeconds))
Write-Host ("花費      : USD {0}" -f (($before - $after) / 1e6))
Write-Host ("剩餘      : USD {0}" -f ($after / 1e6))
