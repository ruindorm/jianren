#!/usr/bin/env bash
# 產生三語可下載成書：EPUB、單檔 Markdown、純文字 TXT、分章 TXT。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT=build
rm -rf "$OUT"
mkdir -p "$OUT"

strip_footer() {
  awk '
    { line[NR] = $0 }
    END {
      cut = NR + 1
      for (i = NR; i >= 1; i--) if (line[i] == "---") { cut = i; break }
      for (i = 1; i < cut; i++) print line[i]
    }
  ' "$1"
}

to_hans() {
  if opencc -c tw2sp.json -i "$1" -o "$2" 2>/dev/null; then :
  else opencc -c t2s.json -i "$1" -o "$2"; fi
}

# 封面用 assets/ 裡的正式美術稿；找不到才退回程式生成
make_cover() {  # $1=輸出 $2=主標 $3=副標 $4=字級 $5=來源檔
  if [ -n "${5:-}" ] && [ -f "$5" ]; then cp "$5" "$1"; return 0; fi
  command -v magick >/dev/null 2>&1 && IM=magick || IM=convert
  command -v $IM >/dev/null 2>&1 || return 1
  local FONT
  FONT="$(fc-match -f '%{file}' 'Noto Serif CJK TC:style=Bold' 2>/dev/null || true)"
  [ -f "$FONT" ] || FONT="$(fc-match -f '%{file}' ':lang=zh-tw:weight=bold' 2>/dev/null || true)"
  [ -f "$FONT" ] || return 1
  $IM -size 1200x1800 gradient:'#161622-#2b2438' \
    -font "$FONT" \
    -fill '#e9dfc4' -pointsize "$4" -gravity north -annotate +0+420 "$2" \
    -fill '#9b93b5' -pointsize 44 -annotate +0+880 "$3" \
    -fill '#6f6885' -pointsize 40 -gravity south -annotate +0+180 'Yang Hou' \
    "$1"
}

build_lang() {
  local lang="$1" src_dir="$2" slug="$3" title="$4" tagline="$5" cover_size="$6" rights="$7" front="$8" cover_src="${9:-}"
  echo
  echo "############ $lang ############"
  local W="$OUT/.work-$lang"
  rm -rf "$W"; mkdir -p "$W"

  local f
  for f in $(ls "$src_dir"/*.md | sort); do
    if [ "$lang" = zh-Hans ]; then
      strip_footer "$f" > "$W/.t"; to_hans "$W/.t" "$W/$(basename "$f")"; rm -f "$W/.t"
    else
      strip_footer "$f" > "$W/$(basename "$f")"
    fi
  done
  echo "    章節 $(ls "$W"/*.md | wc -l) 篇"

  cat > "$W/metadata.yaml" <<EOF
---
title: "$title"
subtitle: "$tagline"
author: Yang Hou
language: $lang
rights: "$rights"
publisher: https://github.com/ruindorm/jianren
---
EOF

  local COVER=()
  if make_cover "$W/cover.img" "$title" "$tagline" "$cover_size" "$cover_src" 2>/dev/null; then
    COVER=(--epub-cover-image="$W/cover.img"); echo "    封面 ✓"
  else
    echo "    封面略過"
  fi

  echo "    EPUB"
  pandoc "$W"/*.md --metadata-file="$W/metadata.yaml" \
    --toc --toc-depth=1 --split-level=1 "${COVER[@]}" \
    -o "$OUT/$slug.epub"

  echo "    Markdown"
  {
    echo "# $title"; echo
    echo "> $tagline"; echo
    printf '%s\n\n' "$front"
    for f in "$W"/*.md; do [ "$(basename "$f")" = metadata.yaml ] && continue; cat "$f"; echo; echo; done
  } > "$OUT/$slug-full.md"

  echo "    TXT"
  pandoc "$OUT/$slug-full.md" -t plain --wrap=none -o "$OUT/$slug-full.txt"

  echo "    分章 TXT"
  mkdir -p "$W/txt"
  for f in "$W"/*.md; do
    pandoc "$f" -t plain --wrap=none -o "$W/txt/$(basename "${f%.md}").txt"
  done
  (cd "$W" && zip -qr "../$slug-chapters-txt.zip" txt)
  rm -rf "$W"
}

FRONT_HANT='作者：Yang Hou　原文：https://github.com/ruindorm/jianren

本作品免費閱讀。轉載請標示作者與出處，禁止商業使用與改作（CC BY-NC-ND 4.0）。'

FRONT_EN='By Yang Hou — https://github.com/ruindorm/jianren

Free to read. Credit the author and link back when reposting.
No commercial use, no derivative works (CC BY-NC-ND 4.0).

Transcreated from the Chinese original 《劍人》.'

build_lang zh-Hant src     jianren       '劍人' '降伏賤人，我的劍，是用來把妹的' 300 \
  '© 2026 Yang Hou — CC BY-NC-ND 4.0' "$FRONT_HANT" assets/cover-zh.jpg

build_lang zh-Hans src     jianren-hans  '剑人' '降伏贱人，我的剑，是用来把妹的' 300 \
  '© 2026 Yang Hou — CC BY-NC-ND 4.0' "$(echo "$FRONT_HANT" | sed 's/免費閱讀/免费阅读/; s/轉載請標示作者與出處，禁止商業使用與改作/转载请标示作者与出处，禁止商业使用与改作/')" assets/cover-zh.jpg

build_lang en      i18n/en bastard-blade 'BASTARD BLADE' 'Slay the bastards. My sword is for picking up girls.' 150 \
  '© 2026 Yang Hou — CC BY-NC-ND 4.0' "$FRONT_EN" assets/cover-en.jpg

echo
echo "完成："
ls -lh "$OUT" | grep -v '^total'
