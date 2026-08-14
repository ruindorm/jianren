<#
.SYNOPSIS
  把生成好的原圖壓成各平台要用的尺寸與格式（webp / jpg / png）。

.DESCRIPTION
  用 ffmpeg。像素風務必加 -Pixel，改用 nearest-neighbor 縮放，
  否則預設的雙線性內插會把像素硬邊糊掉。

.EXAMPLE
  .\tools\compress-image.ps1 -In assets/cover-en-raw.png -Name cover-en

.EXAMPLE
  .\tools\compress-image.ps1 -In assets/cover-en-pixel-raw.png -Name cover-en-pixel -Pixel
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $In,
  [Parameter(Mandatory)][string] $Name,      # 輸出檔名前綴
  [string] $OutDir = 'assets',
  [string] $Thumb  = '400x600',              # 平台縮圖尺寸，空字串則不產生
  [int]    $Quality = 88,                    # webp 品質
  [switch] $Pixel                            # 像素風：改用 neighbor 縮放
)

$ErrorActionPreference = 'Stop'

$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { $ff = 'D:\tease69\tools\ffmpeg\bin\ffmpeg.exe' }
if (-not (Test-Path $ff)) { throw '找不到 ffmpeg' }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$flags = if ($Pixel) { ':flags=neighbor' } else { '' }

# 全尺寸 webp（網頁用）與 jpg（通用、EPUB 封面用）
& $ff -y -loglevel error -i $In -c:v libwebp -quality $Quality -compression_level 6 "$OutDir/$Name.webp"
& $ff -y -loglevel error -i $In -q:v 2 "$OutDir/$Name.jpg"

# 平台縮圖
if ($Thumb) {
  $w, $h = $Thumb.Split('x')
  $vf = "scale=${w}:${h}${flags}:force_original_aspect_ratio=increase,crop=${w}:${h}"
  & $ff -y -loglevel error -i $In -vf $vf -c:v libwebp -quality 90 "$OutDir/$Name-$Thumb.webp"
  & $ff -y -loglevel error -i $In -vf $vf -q:v 3 "$OutDir/$Name-$Thumb.jpg"
  if ($Pixel) { & $ff -y -loglevel error -i $In -vf $vf "$OutDir/$Name-$Thumb.png" }
}

Get-ChildItem $OutDir -Filter "$Name*" |
  Select-Object Name, @{n='KB'; e={ [math]::Round($_.Length / 1KB, 1) }} |
  Sort-Object Name | Format-Table
