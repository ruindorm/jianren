#!/usr/bin/env bash
# 產生三語 mdBook 閱讀網站。
#   site/          正體中文（母本）
#   site/zh-Hans/  簡體中文（OpenCC 自動轉換）
#   site/en/       English（人工創譯）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO_URL="https://github.com/ruindorm/jianren"
SITE_URL="https://ruindorm.github.io/jianren"
rm -rf site book-src-*

# 移除章節檔尾端的「--- / 導覽 / 版權」（網站有自己的上下頁）
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

# 簡繁轉換（台灣正體 → 大陸簡體，含用語轉換）
to_hans() {
  if opencc -c tw2sp.json -i "$1" -o "$2" 2>/dev/null; then :
  else opencc -c t2s.json -i "$1" -o "$2"; fi
}

lang_switcher() {  # $1 = 目前語言
  local hant='正體中文' hans='简体中文' en='English'
  case "$1" in
    zh-Hant) hant="<strong>$hant</strong>" ;;
    zh-Hans) hans="<strong>$hans</strong>" ;;
    en)      en="<strong>$en</strong>" ;;
  esac
  echo "<a href=\"$SITE_URL/\">$hant</a>・<a href=\"$SITE_URL/zh-Hans/\">$hans</a>・<a href=\"$SITE_URL/en/\">$en</a>"
}

build_lang() {
  local lang="$1" src_dir="$2" doc_dir="$3" out_sub="$4" title="$5"
  local SRC="book-src-$lang"
  echo
  echo "############ $lang ############"
  rm -rf "$SRC"; mkdir -p "$SRC"

  local switcher; switcher="$(lang_switcher "$lang")"
  local footer notice
  if [ "$lang" = en ]; then
    notice='Free to read. Credit the author and link back when reposting. No commercial use, no derivative works.'
    footer="<div class=\"jr-footer\">$switcher<br><em>Bastard Blade</em> © 2026 Yang Hou・<a href=\"https://creativecommons.org/licenses/by-nc-nd/4.0/\">CC BY-NC-ND 4.0</a><br>$notice</div>"
  elif [ "$lang" = zh-Hans ]; then
    notice='免费阅读。转载请标示作者与出处，禁止商业使用与改作。'
    footer="<div class=\"jr-footer\">$switcher<br>《剑人》© 2026 Yang Hou・<a href=\"https://creativecommons.org/licenses/by-nc-nd/4.0/deed.zh\">CC BY-NC-ND 4.0</a><br>$notice</div>"
  else
    notice='免費閱讀。轉載請標示作者與出處，禁止商業使用與改作。'
    footer="<div class=\"jr-footer\">$switcher<br>《劍人》© 2026 Yang Hou・<a href=\"https://creativecommons.org/licenses/by-nc-nd/4.0/deed.zh_TW\">CC BY-NC-ND 4.0</a><br>$notice</div>"
  fi

  # ---- 章節 ----
  # 第一卷為索引 0-13（楔子 + 第一～十三章），第十四章起為第二卷
  local VOL2_START=14
  local chapters="" chapters2="" i=0 f name t
  for f in $(ls "$src_dir"/*.md | sort); do
    name="$(printf 'ch%02d' "$i")"
    if [ "$lang" = zh-Hans ]; then
      strip_footer "$f" > "$SRC/.tmp"; to_hans "$SRC/.tmp" "$SRC/$name.md"; rm -f "$SRC/.tmp"
    else
      strip_footer "$f" > "$SRC/$name.md"
    fi
    t="$(head -1 "$SRC/$name.md" | sed 's/^#\+[[:space:]]*//')"
    { echo; echo "$footer"; } >> "$SRC/$name.md"
    if [ "$i" -lt "$VOL2_START" ]; then
      chapters="${chapters}- [${t}](${name}.md)"$'\n'
    else
      chapters2="${chapters2}- [${t}](${name}.md)"$'\n'
    fi
    i=$((i + 1))
  done
  echo "    章節 $i 篇"

  # ---- 設定集 ----
  local docs="" out
  for f in "$doc_dir"/*.md; do
    out="$(basename "$f" .md)"
    # 內部工作流程文件不上讀者網站
    case "$out" in 圖片生成) continue ;; esac
    case "$out" in
      角色設定) out=characters ;;
      世界觀-劍關規則) out=world ;;
      伏筆追蹤) out=foreshadowing ;;
      版權說明) out=license-notice ;;
    esac
    if [ "$lang" = zh-Hans ]; then
      to_hans "$f" "$SRC/$out.md"
    else
      cp "$f" "$SRC/$out.md"
    fi
    { echo; echo "$footer"; } >> "$SRC/$out.md"
    t="$(head -1 "$SRC/$out.md" | sed 's/^#\+[[:space:]]*//')"
    docs="${docs}- [${t}](${out}.md)"$'\n'
  done
  sed -i "s#(../LICENSE)#($REPO_URL/blob/main/LICENSE)#g" "$SRC"/*.md

  # ---- 首頁 ----
  # 封面（mdBook 會把 src 裡的非 md 檔一起複製到輸出）
  case "$lang" in
    en) cp assets/cover-en.jpg "$SRC/cover.jpg" ;;
    *)  cp assets/cover-zh.jpg "$SRC/cover.jpg" ;;
  esac
  local cover_img='<img class="jr-cover" src="cover.jpg" alt="cover">'

  local dl_base="$REPO_URL/releases/download/latest"
  local ep tx md zp
  case "$lang" in
    en)      ep=bastard-blade.epub; tx=bastard-blade-full.txt; md=bastard-blade-full.md; zp=bastard-blade-chapters-txt.zip ;;
    zh-Hans) ep=jianren-hans.epub;  tx=jianren-hans-full.txt;  md=jianren-hans-full.md;  zp=jianren-hans-chapters-txt.zip ;;
    *)       ep=jianren.epub;       tx=jianren-full.txt;       md=jianren-full.md;       zp=jianren-chapters-txt.zip ;;
  esac

  if [ "$lang" = en ]; then
    cat > "$SRC/index.md" <<EOF
# Bastard Blade

<div class="jr-hero">
$cover_img
<div class="jr-tagline">Slay the bastards. My sword is for picking up girls.</div>
</div>

A xianxia comedy.

The protagonist carries an AI sword with a filthy mouth. His whole sect is convinced he has
suffered qi deviation and mutters to himself all day — only the sword knows they are running
win-rate analysis on an upcoming duel.

**[→ Start from the Prologue](ch00.md)**

> Translated from the Chinese 《劍人》. This is a transcreation, not a literal translation —
> see [Translation Notes](translation-notes.md) for what changed and why.

---

## Download

| Format | Best for |
|---|---|
| [EPUB]($dl_base/$ep) | Phones, e-readers |
| [TXT]($dl_base/$tx) | Plain text, anything |
| [Markdown]($dl_base/$md) | Single file, formatting preserved |
| [Chapter TXTs]($dl_base/$zp) | One file per chapter |

Rebuilt automatically on every update.

---

## Copyright

**Free to read. All rights reserved by the author.**

You may read, share, repost with credit, and quote in reviews.
You may not use it commercially, rewrite it, translate it, adapt it, or repost it anonymously.

See the [Copyright & Licence](license-notice.md). For adaptation, translation or commercial
enquiries, write to pftmax@gmail.com.

---

$switcher

$footer
EOF
  else
    local T='劍人' TAG='降伏賤人，我的劍，是用來把妹的'
    local L1='一部修真吐槽喜劇。' L2='男主角有一把嘴很賤的 AI 佩劍，全宗門都以為他走火入魔、整天自言自語——只有那把劍知道，他們正在為劍關決戰計算勝率。'
    local START='**[→ 從楔子開始讀](ch00.md)**'
    local DLH='## 下載全文' DL1='格式' DL2='適合'
    local F1='手機、電子書閱讀器' F2='純文字，任何裝置' F3='單一檔案，保留格式' F4='一章一檔，方便轉貼'
    local NOTE='檔案在每次章節更新後自動重建，永遠是最新版本。'
    local CR='## 版權' CR1='**本作品免費公開閱讀，作者保留全部著作權。**'
    local CR2='可以：閱讀、分享連結、轉貼（須標示作者與出處）、引用評論' CR3='不可以：商業使用、改寫續寫、翻譯、改編、匿名搬運、冒名投稿'
    local CR4='詳見 [版權說明](license-notice.md)。想改編、翻譯或商業合作，歡迎來信 pftmax@gmail.com 洽談。'
    local OTH='## 其他' OTH1='- [設定集：角色](characters.md)・[劍關規則](world.md)・[伏筆追蹤](foreshadowing.md)'
    local OTH2="- [原始倉庫]($REPO_URL) — 修訂歷史、回報錯字"
    cat > "$SRC/index.md" <<EOF
# $T

<div class="jr-hero">
$cover_img
<div class="jr-tagline">$TAG</div>
</div>

$L1

$L2

$START

---

$DLH

| $DL1 | $DL2 |
|---|---|
| [EPUB]($dl_base/$ep) | $F1 |
| [TXT]($dl_base/$tx) | $F2 |
| [Markdown]($dl_base/$md) | $F3 |
| [分章 TXT]($dl_base/$zp) | $F4 |

$NOTE

---

$CR

$CR1

$CR2
$CR3

$CR4

---

$OTH

$OTH1
$OTH2

---

$switcher

$footer
EOF
    if [ "$lang" = zh-Hans ]; then
      to_hans "$SRC/index.md" "$SRC/.i"; mv "$SRC/.i" "$SRC/index.md"
    fi
  fi

  # ---- SUMMARY ----
  local part_story part_story2 part_docs home
  case "$lang" in
    en)      home='Bastard Blade'
             part_story='Volume One — The Sword Gate'
             part_story2='Volume Two — Where the Casket Came From'
             part_docs='Reference' ;;
    zh-Hans) home='剑人'; part_story='第一卷　剑关'; part_story2='第二卷　剑匣的来历'; part_docs='设定集' ;;
    *)       home='劍人'; part_story='第一卷　劍關'; part_story2='第二卷　劍匣的來歷'; part_docs='設定集' ;;
  esac
  {
    echo "# Summary"; echo
    echo "[$home](index.md)"; echo
    echo "# $part_story"; echo
    printf '%s' "$chapters"; echo
    if [ -n "$chapters2" ]; then echo "# $part_story2"; echo; printf '%s' "$chapters2"; echo; fi
    echo "# $part_docs"; echo
    printf '%s' "$docs"
  } > "$SRC/SUMMARY.md"

  # ---- build ----
  MDBOOK_book__src="$SRC" \
  MDBOOK_book__title="$title" \
  MDBOOK_build__build_dir="site${out_sub:+/$out_sub}" \
  mdbook build
  echo "    → site${out_sub:+/$out_sub}"
}

build_lang zh-Hant src            docs             ""        "劍人"
build_lang zh-Hans src            docs             "zh-Hans" "剑人"
build_lang en      i18n/en        i18n/en/docs     "en"      "Bastard Blade"

echo
echo "完成："
find site -maxdepth 2 -name index.html | sort
