<#
.SYNOPSIS
  把台詞合成到 16:9 畫面下方的字幕條，輸出 3:2。

.DESCRIPTION
  圖片只負責圖片，台詞一律在這裡合成——生成的畫面永遠不含文字。
  只 pad 不 scale，像素硬邊完整保留。

  文字走 drawtext 的 textfile= 而非 text=，避開中文與 ：！～ 的跳脫問題。
  超過單行上限會自動斷成兩行；兩行還放不下就報錯——那代表這句台詞該拆節拍。

.EXAMPLE
  .\tools\compose-subtitle.ps1 -In assets/ch/s01-c-1.png -Text '你才有病！你全家都有病！' -Out assets/ch/ch01-02.png

.EXAMPLE
  .\tools\compose-subtitle.ps1 -In assets/ch/s01-a-1.png -Text '喲！這不是師弟嗎？你的病越來越嚴重了！' -Out assets/ch/ch01-01.png -MaxChars 20
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $In,
  [Parameter(Mandatory)][string] $Text,
  [Parameter(Mandatory)][string] $Out,
  [string] $Font     = 'C:\Windows\Fonts\msjh.ttc',   # 微軟正黑體
  [string] $BandBG   = '0x12121a',
  [string] $TextRGB  = '0xf2f2f2',
  [int]    $MaxChars = 30                             # 單行上限（全形字）
                                                      # 30 是拿全書 337 拍實測出來的：
                                                      # 22 有 30 拍放不下，30 只剩 5 拍，
                                                      # 而那 5 拍本來就該拆成兩個節拍。
                                                      # 1536 幅寬下 30 字約 1260px，餘白 276px。
)

$ErrorActionPreference = 'Stop'

$ff = (Get-Command ffmpeg  -ErrorAction SilentlyContinue).Source
if (-not $ff) { $ff = 'D:\tease69\tools\ffmpeg\bin\ffmpeg.exe' }
if (-not (Test-Path $ff)) { throw '找不到 ffmpeg' }

$fp = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source
if (-not $fp) { $fp = Join-Path (Split-Path $ff) 'ffprobe.exe' }
if (-not (Test-Path $fp)) { throw '找不到 ffprobe' }

if (-not (Test-Path $In))   { throw "找不到來源圖：$In" }
if (-not (Test-Path $Font)) { throw "找不到字型：$Font（用 -Font 指定）" }

# ---- 尺寸：16:9 往下 pad 成 3:2 ----
$wh = (& $fp -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $In).Trim()
$W, $H = $wh.Split('x') | ForEach-Object { [int]$_ }

$outH = [math]::Round($W * 2 / 3)
$band = $outH - $H
if ($band -lt 40) { throw "字幕條只有 ${band}px——來源不是 16:9？實際 ${W}x${H}" }

# ---- 斷行 ----
$lines = @()
if ($Text.Length -le $MaxChars) {
  $lines = @($Text)
} else {
  # 優先在標點後斷，找不到就硬切
  $cut = -1
  foreach ($p in '。','！','？','—','，','、','…') {
    $i = $Text.LastIndexOf($p, [math]::Min($MaxChars, $Text.Length - 1))
    if ($i -gt $cut) { $cut = $i }
  }
  if ($cut -lt [int]($MaxChars / 3)) { $cut = $MaxChars - 1 }
  $lines = @($Text.Substring(0, $cut + 1), $Text.Substring($cut + 1))
}
if ($lines.Count -gt 2 -or $lines[-1].Length -gt $MaxChars) {
  throw "兩行放不下（$($Text.Length) 字）——這句台詞該拆成兩個節拍"
}

# ---- 排版 ----
$size = [math]::Round($band * 0.26)
$lead = [math]::Round($size * 1.35)
$block = $lines.Count * $lead
$y0 = $H + [math]::Round(($band - $block) / 2) + [math]::Round(($lead - $size) / 2)

# drawtext 的 fontfile 在 Windows 要跳脫磁碟機代號的冒號
$fontEsc = ($Font -replace '\\', '/') -replace '^([A-Za-z]):', '$1\:'

# ---- 文字寫成 UTF-8 無 BOM 暫存檔，避開跳脫地獄 ----
$tmp = @()
$draw = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $f = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($f, $lines[$i], (New-Object System.Text.UTF8Encoding $false))
  $tmp += $f
  $tf = ($f -replace '\\', '/') -replace '^([A-Za-z]):', '$1\:'
  $y  = $y0 + $i * $lead
  $draw += "drawtext=fontfile='${fontEsc}':textfile='${tf}':fontcolor=${TextRGB}:fontsize=${size}:x=(w-text_w)/2:y=${y}"
}

$outDir = Split-Path $Out -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

$vf = "pad=${W}:${outH}:0:0:color=${BandBG}," + ($draw -join ',')

try {
  & $ff -y -loglevel error -i $In -vf $vf -pix_fmt rgb24 $Out
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg 失敗（exit $LASTEXITCODE）" }
} finally {
  $tmp | ForEach-Object { Remove-Item $_ -ErrorAction SilentlyContinue }
}

'{0}  {1}x{2} → {3}x{4}（字幕條 {5}px、{6} 行）' -f `
  (Split-Path $Out -Leaf), $W, $H, $W, $outH, $band, $lines.Count
