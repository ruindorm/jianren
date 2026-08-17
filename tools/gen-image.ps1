<#
.SYNOPSIS
  用 Pika API 生成圖片。支援 text-to-image 與 image-to-image（多參考圖／遮罩）。

.DESCRIPTION
  預設一律使用最低品質（1K / low）。這是刻意的預設值，不是省略設定的結果 ——
  實測 1K/low 比 2K/high 便宜約 47 倍、快 6 倍，而且文字渲染反而更準確。

  比例（-AspectRatio）沒有預設值，必須依用途明確指定。詳見 docs/圖片生成.md。

  給了 -Image 就自動改走 image-to-image 端點。本機檔案會先上傳取得託管網址，
  http(s) 網址則直接使用。

  各家模型的參數不一樣（見 docs/圖片生成.md 的編輯能力對照）：
    gpt-image-2      quality ✓   mask ✓
    grok / grok-fast quality ✗   mask ✗
    nano-banana-pro  quality ✗   mask ✗
    seedream-pro     quality ✗   mask ✗
  不支援的參數會被自動略去，不會硬送出去讓 API 報錯。

.EXAMPLE
  .\tools\gen-image.ps1 -PromptFile prompt.txt -AspectRatio 2:3 -Out assets/cover.png

.EXAMPLE
  # 多參考圖：角色設定圖 + 場景定位圖 + 構圖草稿
  .\tools\gen-image.ps1 -PromptFile prompts/s01-c-1.txt -AspectRatio 16:9 `
    -Image assets/ref/c01-sheet.png, assets/ref/s01-plate.png, assets/ref/s01-c-block.png `
    -Out assets/ch/s01-c-1-raw.png

.EXAMPLE
  # 遮罩局部重繪：換表演變體，鎖住背景與身體
  .\tools\gen-image.ps1 -Prompt 'the same swordsman, now sneering' -AspectRatio 16:9 `
    -Image assets/ch/s01-c-1-raw.png -Mask assets/mask/face.png `
    -Out assets/ch/s01-c-2-raw.png

.EXAMPLE
  # 三方比稿
  .\tools\gen-image.ps1 -PromptFile p.txt -AspectRatio 16:9 -Model grok -Out out-grok.png
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

  [ValidateSet('gpt-image-2','grok','grok-fast','nano-banana-pro','seedream-pro')]
  [string]   $Model = 'gpt-image-2',

  [string[]] $Image,                    # 參考圖：本機路徑或 http(s) 網址。給了就走 image-to-image
  [string]   $Mask,                     # 遮罩：含 alpha 的 PNG。僅 gpt-image-2

  [ValidateSet('low','medium','high','auto')]
  [string]   $Quality = 'low',          # 預設最低，除非特別要求

  [ValidateSet('1K','2K','4K')]
  [string]   $Resolution = '1K',        # 預設最低，除非特別要求

  [ValidateSet('png','jpeg','webp')]
  [string]   $OutputFormat = 'png',

  [ValidateSet('auto','opaque','transparent')]
  [string]   $Background,

  [int]      $NumImages = 1,
  [string]   $EnvFile,                  # 見下方金鑰解析順序
  [int]      $TimeoutMinutes = 8
)

$ErrorActionPreference = 'Stop'

if (-not $Prompt -and -not $PromptFile) { throw '需要 -Prompt 或 -PromptFile' }
if ($PromptFile) { $Prompt = Get-Content $PromptFile -Raw -Encoding UTF8 }

# --- 模型能力表：不支援的參數不送出 ---
$MODELS = @{
  'gpt-image-2'     = @{ path = 'openai/gpt-image-2';               quality = $true;  mask = $true  }
  'grok'            = @{ path = 'x-ai/grok-imagine-image-quality';  quality = $false; mask = $false }
  'grok-fast'       = @{ path = 'x-ai/grok-imagine-image';          quality = $false; mask = $false }
  'nano-banana-pro' = @{ path = 'google/gemini-3-pro-image';        quality = $false; mask = $false }
  'seedream-pro'    = @{ path = 'bytedance/seedream-5.0-pro';       quality = $false; mask = $false }
}
$M = $MODELS[$Model]

if ($Mask -and -not $M.mask) { throw "$Model 不支援遮罩，只有 gpt-image-2 有 mask_image_url" }
if ($Mask -and -not $Image)  { throw '用 -Mask 必須同時給 -Image（遮罩是套在參考圖上的）' }

# --- 金鑰：只讀進記憶體，不印出、不寫入任何輸出 ---
# 解析順序：環境變數 → -EnvFile → $env:JIANREN_ENV_FILE → 倉庫根目錄 .env
# 不在程式碼裡寫死個人路徑——這是公開倉庫。
$key = $env:PIKA_API_KEY
if (-not $key) {
  $candidates = @($EnvFile, $env:JIANREN_ENV_FILE, (Join-Path $PSScriptRoot '..\.env')) |
                Where-Object { $_ -and (Test-Path $_) }
  foreach ($f in $candidates) {
    $line = Get-Content $f | Select-String '^PIKA_API_KEY='
    if ($line) { $key = $line.ToString().Split('=', 2)[1].Trim(); break }
  }
}
if (-not $key) {
  throw @'
找不到 PIKA_API_KEY。三種設法擇一：
  1. 設環境變數 PIKA_API_KEY
  2. 設環境變數 JIANREN_ENV_FILE 指向你的 .env（例：setx JIANREN_ENV_FILE D:\你的路徑\.env）
  3. 每次呼叫帶 -EnvFile <路徑>
'@
}
$H = @{ 'X-API-Key' = $key; 'Content-Type' = 'application/json' }

$api = 'https://api.dev.pika.art'

# --- 本機檔案先上傳，取得託管網址 ---
function Publish-Local {
  param([string] $Path)
  if ($Path -match '^https?://') { return $Path }
  if (-not (Test-Path $Path))    { throw "找不到參考圖：$Path" }

  $fi = Get-Item $Path
  $ct = switch ($fi.Extension.ToLower()) {
    '.png'  { 'image/png' }  '.jpg' { 'image/jpeg' }  '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' } default { throw "不支援的參考圖格式：$($fi.Extension)" }
  }
  $req = @{ content_type = $ct; size_bytes = $fi.Length } | ConvertTo-Json
  $u = Invoke-RestMethod -Method Post -Uri "$api/v1/media/uploads" -Headers $H `
        -Body ([Text.Encoding]::UTF8.GetBytes($req))

  # 簽章涵蓋 Content-Type 與 Content-Length。PowerShell 會自己算 Content-Length，
  # 且不允許用 -Headers 覆寫這兩個，所以原樣轉送其餘標頭、這兩個交給 PS。
  $put = @{}
  foreach ($p in $u.headers.PSObject.Properties) {
    if ($p.Name -notin @('Content-Type','Content-Length')) { $put[$p.Name] = $p.Value }
  }
  Invoke-WebRequest -Method Put -Uri $u.upload_url -Headers $put `
                    -ContentType $ct -InFile $fi.FullName | Out-Null
  Write-Host ("上傳      : {0} ({1} KB)" -f $fi.Name, [math]::Round($fi.Length / 1KB, 1))
  return $u.url
}

# --- 組 payload ---
$mode    = if ($Image) { 'image-to-image' } else { 'text-to-image' }
$path    = "/v1/media/$($M.path)/$mode"

$payload = @{
  prompt        = $Prompt
  num_images    = $NumImages
  aspect_ratio  = $AspectRatio
  output_format = $OutputFormat
  resolution    = $Resolution
}
# quality 只送給支援的模型。注意：gpt-image-2 的 image-to-image 預設是 medium 不是 low，
# 所以這裡一定要顯式帶上，否則貴約 4 倍。
if ($M.quality)  { $payload.quality = $Quality }
if ($Background) { $payload.background = $Background }

# --- 送出前先確認餘額（此端點免費） ---
$before = (Invoke-RestMethod -Uri "$api/billing/balance" -Headers $H).balance_micro_usd
Write-Host ("餘額      : USD {0}" -f ($before / 1e6))
Write-Host ("模型      : {0}  ({1})" -f $Model, $mode)
Write-Host ("設定      : {0} / {1} / quality={2} / {3} 張" -f `
            $AspectRatio, $Resolution, $(if ($M.quality) { $Quality } else { '不支援' }), $NumImages)

if ($Image) {
  $payload.image_urls = @($Image | ForEach-Object { Publish-Local $_ })
  if ($Mask) { $payload.mask_image_url = Publish-Local $Mask }
}

$body = $payload | ConvertTo-Json -Depth 5
$job  = Invoke-RestMethod -Method Post -Uri "$api$path" -Headers $H `
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
