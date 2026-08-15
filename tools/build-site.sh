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
rm -rf site book-src-* book-plain-*

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

  # PLAIN 收的是「還沒接頁尾」的乾淨正文，稍後輸出成 txt/ 與 full.txt，
  # 給不跑 JavaScript 的抓取器（含 AI 檢索器）直接讀。
  # 放在 book src 之外，否則 mdBook 會把它整包複製進輸出，多一份重複檔。
  local PLAIN="book-plain-$lang"
  rm -rf "$PLAIN"; mkdir -p "$PLAIN"
  local chapters="" chapters2="" i=0 f name t
  for f in $(ls "$src_dir"/*.md | sort); do
    name="$(printf 'ch%02d' "$i")"
    if [ "$lang" = zh-Hans ]; then
      strip_footer "$f" > "$SRC/.tmp"; to_hans "$SRC/.tmp" "$SRC/$name.md"; rm -f "$SRC/.tmp"
    else
      strip_footer "$f" > "$SRC/$name.md"
    fi
    t="$(head -1 "$SRC/$name.md" | sed 's/^#\+[[:space:]]*//')"
    cp "$SRC/$name.md" "$PLAIN/$name.txt"
    { echo; echo "$footer"; } >> "$SRC/$name.md"
    if [ "$i" -lt "$VOL2_START" ]; then
      chapters="${chapters}- [${t}](${name}.md)"$'\n'
    else
      chapters2="${chapters2}- [${t}](${name}.md)"$'\n'
    fi
    i=$((i + 1))
  done
  local LAST_CH; LAST_CH="$(printf 'ch%02d' $((i - 1)))"
  echo "    章節 $i 篇"

  # ---- 設定集 ----
  local docs="" out
  for f in "$doc_dir"/*.md; do
    out="$(basename "$f" .md)"
    # 內部工作流程文件不上讀者網站
    # 伏筆追蹤是寫作用的對照表，內容即劇透，不上讀者網站
    case "$out" in 圖片生成|純文字入口|伏筆追蹤) continue ;; esac
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
    cp "$SRC/$out.md" "$PLAIN/$out.txt"
    { echo; echo "$footer"; } >> "$SRC/$out.md"
    t="$(head -1 "$SRC/$out.md" | sed 's/^#\+[[:space:]]*//')"
    docs="${docs}- [${t}](${out}.md)"$'\n'
  done
  sed -i "s#(../LICENSE)#($REPO_URL/blob/main/LICENSE)#g" "$SRC"/*.md "$PLAIN"/*.txt

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
| [Plain text, one file]($SITE_URL/en/full.txt) | Feeding the whole book to an AI or a script |

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
    local OTH='## 其他' OTH1='- [設定集：角色](characters.md)・[劍關規則](world.md)'
    local OTH2="- [原始倉庫]($REPO_URL) — 修訂歷史、回報錯字"
    local OTH3="- [全文純文字檔]($SITE_URL/full.txt) — 一個網址拿到整本，適合丟給 AI 或其他工具讀"
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
$OTH3

---

$switcher

$footer
EOF
    if [ "$lang" = zh-Hans ]; then
      to_hans "$SRC/index.md" "$SRC/.i"; mv "$SRC/.i" "$SRC/index.md"
    fi
  fi

  # ---- 404 ----
  # 常有人（和 AI 抓取器）照 GitHub 的檔案路徑猜網址，例如
  # /src/01-渡劫大殿外.md。mdBook 會用 404.md 當自訂錯誤頁，
  # 在這裡把正確的路徑規則講清楚，猜錯也能自己走回來。
  if [ "$lang" = en ]; then
    cat > "$SRC/404.md" <<EOF
# Page not found

That URL may have been guessed from the GitHub file paths. This site uses different ones.

| What you want | URL |
|---|---|
| Whole book, one plain-text file | [$SITE_URL/en/full.txt]($SITE_URL/en/full.txt) |
| A single chapter, plain text | \`$SITE_URL/en/txt/ch01.txt\` (ch00–$LAST_CH) |
| A single chapter, web page | \`$SITE_URL/en/ch01.html\` (ch00–$LAST_CH) |
| Machine-readable index | [$SITE_URL/llms.txt]($SITE_URL/llms.txt) |

[→ Home]($SITE_URL/en/)
EOF
  else
    local NF='找不到這一頁' NFL='這個網址可能是照 GitHub 上的檔案路徑猜的，本站的路徑規則不一樣。'
    local C1='你想找的' C2='網址'
    local R1='全文，單一純文字檔' R2='單章，純文字' R3='單章，網頁' R4='給程式／AI 的索引'
    cat > "$SRC/404.md" <<EOF
# $NF

$NFL

| $C1 | $C2 |
|---|---|
| $R1 | [$SITE_URL/full.txt]($SITE_URL/full.txt) |
| $R2 | \`$SITE_URL/txt/ch01.txt\`（ch00–$LAST_CH） |
| $R3 | \`$SITE_URL/ch01.html\`（ch00–$LAST_CH） |
| $R4 | [$SITE_URL/llms.txt]($SITE_URL/llms.txt) |

[→ 回首頁]($SITE_URL/)
EOF
    if [ "$lang" = zh-Hans ]; then
      to_hans "$SRC/404.md" "$SRC/.n"; mv "$SRC/.n" "$SRC/404.md"
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

  # ---- 純文字鏡像 ----
  # GitHub 的 blob 頁靠 JavaScript 渲染，而且中文檔名會被編碼成
  # %E6%B8%A1%E5%8A%AB…，不少抓取器（含 AI 檢索器）因此讀不到正文。
  # 這裡再輸出一份 ASCII 路徑、純文字、免 JS 的鏡像：
  #   full.txt      整本一個網址
  #   txt/chNN.txt  單章一個網址
  local OUT="site${out_sub:+/$out_sub}"
  local URL="$SITE_URL${out_sub:+/$out_sub}"
  mkdir -p "$OUT/txt"
  cp "$PLAIN/"*.txt "$OUT/txt/"

  local head_by head_read head_repo head_lic head_note
  case "$lang" in
    en)
      head_by='Author: Yang Hou'; head_read='Read online: '; head_repo='Source repository: '
      head_lic='Licence: CC BY-NC-ND 4.0 — free to read, credit required, no commercial use, no derivative works.'
      head_note='Full text in one file. Rebuilt automatically on every update.' ;;
    zh-Hans)
      head_by='作者：Yang Hou'; head_read='在线阅读：'; head_repo='原始仓库：'
      head_lic='授权：CC BY-NC-ND 4.0 — 免费阅读，转载请标示作者与出处，禁止商业使用与改作。'
      head_note='本檔為全書純文字合訂本，每次更新後自動重建。' ;;
    *)
      head_by='作者：Yang Hou'; head_read='線上閱讀：'; head_repo='原始倉庫：'
      head_lic='授權：CC BY-NC-ND 4.0 — 免費閱讀，轉載請標示作者與出處，禁止商業使用與改作。'
      head_note='本檔為全書純文字合訂本，每次更新後自動重建。' ;;
  esac
  {
    echo "$title"
    echo "$head_by"
    echo "$head_read$URL/"
    echo "$head_repo$REPO_URL"
    echo "$head_lic"
    echo
    echo "$head_note"
    # 先章節（chNN 已是閱讀順序），再設定集
    for f in "$OUT/txt/"ch[0-9][0-9].txt; do
      echo; echo '════════════════════════════════════════'; echo
      cat "$f"
    done
    for f in "$OUT/txt/"*.txt; do
      case "$(basename "$f")" in ch[0-9][0-9].txt) continue ;; esac
      echo; echo '════════════════════════════════════════'; echo
      cat "$f"
    done
  } > "$OUT/full.txt"
  echo "    → $OUT/full.txt（$(wc -c < "$OUT/full.txt") bytes）"
}

build_lang zh-Hant src            docs             ""        "劍人"
build_lang zh-Hans src            docs             "zh-Hans" "剑人"
build_lang en      i18n/en        i18n/en/docs     "en"      "Bastard Blade"

############ 讓機器找得到：robots.txt / sitemap.xml / llms.txt ############
echo
echo "############ 檢索入口 ############"

# ---- robots.txt ----
# 站台原本沒有 robots.txt（404 等同全部允許），這裡寫明白，
# 順便把 sitemap 位置告訴爬蟲。
cat > site/robots.txt <<EOF
# 《劍人》線上閱讀站 — 全站公開，歡迎檢索
# 作品採 CC BY-NC-ND 4.0：可讀、可引用、可轉貼（須標示作者與出處），
# 不可商業使用、不可改作。

User-agent: *
Allow: /

# 純文字鏡像（免 JavaScript，路徑全 ASCII）：
#   $SITE_URL/full.txt
#   $SITE_URL/txt/ch01.txt

Sitemap: $SITE_URL/sitemap.xml
EOF
echo "    → site/robots.txt"

# ---- sitemap.xml ----
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
  for f in $(find site -name '*.html' ! -name '404.html' | sed 's#^site##' | sort); do
    # index.html 收成目錄網址，其餘照原樣
    loc="$SITE_URL${f%index.html}"
    case "$f" in */index.html) ;; *) loc="$SITE_URL$f" ;; esac
    echo "  <url><loc>$loc</loc></url>"
  done
  for f in $(find site \( -path '*/txt/*.txt' -o -name 'full.txt' \) | sed 's#^site##' | sort); do
    echo "  <url><loc>$SITE_URL$f</loc></url>"
  done
  echo '</urlset>'
} > site/sitemap.xml
echo "    → site/sitemap.xml（$(grep -c '<url>' site/sitemap.xml) 個網址）"

# ---- llms.txt ----
# https://llmstxt.org/ 的慣例：放在站根，給 LLM 用的一頁式索引。
# 目的很單純——AI 只要抓到這一個網址，就知道全文在哪裡、該抓哪個檔。
list_txt() {  # $1 = 輸出子目錄（空 = 正體中文），$2 = chapters|docs
  local d="site${1:+/$1}/txt" base="$SITE_URL${1:+/$1}" f n t
  for f in "$d"/*.txt; do
    n="$(basename "$f")"
    case "$2:$n" in
      chapters:ch[0-9][0-9].txt) ;;
      docs:ch[0-9][0-9].txt)     continue ;;
      docs:*)                    ;;
      *)                         continue ;;
    esac
    t="$(head -1 "$f" | sed 's/^#\+[[:space:]]*//')"
    echo "- [$t]($base/txt/$n)"
  done
}
{
  cat <<EOF
# 劍人 / Bastard Blade

> 一部修真吐槽喜劇。男主角有一把嘴很賤的 AI 佩劍，全宗門都以為他走火入魔、
> 整天自言自語——只有那把劍知道，他們正在為劍關決戰計算勝率。
> A xianxia comedy about a cultivator whose AI sword has a filthy mouth.

作者 Yang Hou・授權 CC BY-NC-ND 4.0（免費閱讀，轉載須標示作者與出處，
禁止商業使用與改作）・原始倉庫 $REPO_URL

**要一次拿到全文，抓下面這一個網址就夠了。** 純文字、免 JavaScript、路徑全 ASCII。

## 全文（單一檔案）

- [正體中文全文]($SITE_URL/full.txt)
- [简体中文全文]($SITE_URL/zh-Hans/full.txt)
- [English full text]($SITE_URL/en/full.txt)

## 正體中文・分章

EOF
  list_txt "" chapters
  echo
  echo "## 正體中文・設定集"
  echo
  list_txt "" docs
  echo
  echo "## English — by chapter"
  echo
  list_txt en chapters
  echo
  echo "## English — reference"
  echo
  list_txt en docs
  echo
  cat <<EOF
## 简体中文

- [分章目錄]($SITE_URL/zh-Hans/) — 由正體中文以 OpenCC 自動轉換，
  純文字檔在 $SITE_URL/zh-Hans/txt/ 下，命名與正體中文相同。

## 其他

- [網頁版首頁]($SITE_URL/)（有目錄、上下頁、深色模式）
- [全書單頁列印版]($SITE_URL/print.html)
- [sitemap.xml]($SITE_URL/sitemap.xml)
EOF
} > site/llms.txt
echo "    → site/llms.txt"

echo
echo "完成："
find site -maxdepth 2 -name index.html | sort
echo
echo "給 AI / 爬蟲的入口："
echo "    $SITE_URL/llms.txt"
echo "    $SITE_URL/full.txt"
echo "    $SITE_URL/sitemap.xml"
