#!/usr/bin/env bash
# 從 src/*.md 產生可下載的成書檔案。
# 產物放在 build/：EPUB、單檔 Markdown、純文字 TXT。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/chapters"

echo "==> 準備章節（移除頁尾導覽與版權列）"
for f in src/*.md; do
  base="$(basename "$f")"
  # 章節檔尾端是「--- / 上一章·目錄·下一章 / 版權<sub>」，
  # 成書時不需要，砍掉最後一條水平線之後的所有內容。
  awk '
    { line[NR] = $0 }
    END {
      cut = NR + 1
      for (i = NR; i >= 1; i--) if (line[i] == "---") { cut = i; break }
      for (i = 1; i < cut; i++) print line[i]
    }
  ' "$f" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$OUT/chapters/$base"
  echo "    $base"
done

echo "==> 產生封面"
COVER_ARG=()
if command -v magick >/dev/null 2>&1; then IM=magick
elif command -v convert >/dev/null 2>&1; then IM=convert
else IM=""; fi

if [ -n "$IM" ]; then
  FONT="$(fc-match -f '%{file}' 'Noto Serif CJK TC:style=Bold' 2>/dev/null || true)"
  [ -f "$FONT" ] || FONT="$(fc-match -f '%{file}' ':lang=zh-tw:weight=bold' 2>/dev/null || true)"
  [ -f "$FONT" ] || FONT="$(fc-match -f '%{file}' ':lang=zh-tw' 2>/dev/null || true)"
  if [ -n "$FONT" ] && [ -f "$FONT" ]; then
    echo "    字型：$FONT"
    if $IM -size 1200x1800 gradient:'#161622-#2b2438' \
        -font "$FONT" \
        -fill '#e9dfc4' -pointsize 300 -gravity north -annotate +0+420 '劍人' \
        -fill '#9b93b5' -pointsize 46 -annotate +0+880 '降伏賤人，我的劍，是用來把妹的' \
        -fill '#6f6885' -pointsize 40 -gravity south -annotate +0+180 'Yang Hou' \
        "$OUT/cover.png"; then
      COVER_ARG=(--epub-cover-image="$OUT/cover.png")
      echo "    build/cover.png"
    fi
  else
    echo "    找不到中文字型"
  fi
else
  echo "    找不到 ImageMagick"
fi
[ ${#COVER_ARG[@]} -eq 0 ] && echo "    （封面略過，EPUB 仍會正常產生）"

echo "==> EPUB"
pandoc "$OUT"/chapters/*.md \
  --metadata-file=tools/metadata.yaml \
  --toc --toc-depth=1 \
  --split-level=1 \
  "${COVER_ARG[@]}" \
  -o "$OUT/jianren.epub"

echo "==> 單檔 Markdown"
{
  echo "# 劍人"
  echo
  echo "> 降伏賤人，我的劍，是用來把妹的"
  echo
  echo "作者：Yang Hou　原文：https://github.com/ruindorm/jianren"
  echo
  echo "本作品免費閱讀。轉載請標示作者與出處，禁止商業使用與改作（CC BY-NC-ND 4.0）。"
  echo
  for f in "$OUT"/chapters/*.md; do
    cat "$f"
    echo
    echo
  done
} > "$OUT/jianren-full.md"

echo "==> 純文字 TXT"
pandoc "$OUT/jianren-full.md" -t plain --wrap=none -o "$OUT/jianren-full.txt"

echo "==> 各章純文字（方便貼到其他平台）"
mkdir -p "$OUT/txt"
for f in "$OUT"/chapters/*.md; do
  pandoc "$f" -t plain --wrap=none -o "$OUT/txt/$(basename "${f%.md}").txt"
done
(cd "$OUT" && zip -qr jianren-chapters-txt.zip txt)
rm -rf "$OUT/txt" "$OUT/chapters"

echo
echo "完成："
ls -lh "$OUT"
