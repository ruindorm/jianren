#!/usr/bin/env bash
# 產生 mdBook 閱讀網站。
# 由 src/*.md 與 docs/*.md 生成 book-src/，再交給 mdbook 建成 site/。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC=book-src
rm -rf "$SRC" site
mkdir -p "$SRC"

REPO_URL="https://github.com/ruindorm/jianren"
FOOTER='<div class="jr-footer">《劍人》© 2026 Yang Hou・<a href="https://creativecommons.org/licenses/by-nc-nd/4.0/deed.zh_TW">CC BY-NC-ND 4.0</a><br>免費閱讀。轉載請標示作者與出處，禁止商業使用與改作。</div>'

# 移除章節檔尾端的「--- / 導覽 / 版權」區塊（網站有自己的上下頁）
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

echo "==> 生成章節"
CHAPTER_LIST=""
i=0
for f in $(ls src/*.md | sort); do
  title="$(head -1 "$f" | sed 's/^#\+[[:space:]]*//')"
  name="$(printf 'ch%02d' "$i")"
  { strip_footer "$f"; echo; echo "$FOOTER"; } > "$SRC/$name.md"
  CHAPTER_LIST="${CHAPTER_LIST}- [${title}](${name}.md)"$'\n'
  echo "    $name  ← $(basename "$f")"
  i=$((i + 1))
done

echo "==> 生成設定集"
copy_doc() {  # $1=來源 $2=輸出名
  { cat "$1"; echo; echo "$FOOTER"; } > "$SRC/$2.md"
}
copy_doc docs/角色設定.md          characters
copy_doc docs/世界觀-劍關規則.md   world
copy_doc docs/伏筆追蹤.md          foreshadowing
copy_doc docs/版權說明.md          license-notice

# 設定集裡的相對連結指向倉庫檔案，網站上換成 GitHub 連結
sed -i "s#(../LICENSE)#($REPO_URL/blob/main/LICENSE)#g" "$SRC"/*.md

echo "==> 生成首頁"
cat > "$SRC/index.md" <<EOF
# 劍人

<div class="jr-hero">
<div class="jr-tagline">降伏賤人，我的劍，是用來把妹的</div>
</div>

一部修真吐槽喜劇。

男主角有一把嘴很賤的 AI 佩劍，全宗門都以為他走火入魔、整天自言自語——
只有那把劍知道，他們正在為劍關決戰計算勝率。

**[→ 從楔子開始讀](ch00.md)**

---

## 下載全文

| 格式 | 適合 |
|---|---|
| [EPUB]($REPO_URL/releases/download/latest/jianren.epub) | 手機、電子書閱讀器 |
| [TXT]($REPO_URL/releases/download/latest/jianren-full.txt) | 純文字，任何裝置 |
| [Markdown]($REPO_URL/releases/download/latest/jianren-full.md) | 單一檔案，保留格式 |
| [分章 TXT]($REPO_URL/releases/download/latest/jianren-chapters-txt.zip) | 一章一檔，方便轉貼 |

檔案在每次章節更新後自動重建，永遠是最新版本。

---

## 版權

**本作品免費公開閱讀，作者保留全部著作權。**

可以：閱讀、分享連結、轉貼（須標示作者與出處）、引用評論
不可以：商業使用、改寫續寫、翻譯、改編、匿名搬運、冒名投稿

詳見 [版權說明](license-notice.md)。想改編、翻譯或商業合作，歡迎來信 pftmax@gmail.com 洽談。

---

## 其他

- [設定集：角色](characters.md)・[劍關規則](world.md)・[伏筆追蹤](foreshadowing.md)
- [原始倉庫]($REPO_URL) — 修訂歷史、回報錯字

$FOOTER
EOF

echo "==> 生成 SUMMARY.md"
{
  echo "# 目錄"
  echo
  echo "[劍人](index.md)"
  echo
  echo "# 第一卷　劍關"
  echo
  printf '%s' "$CHAPTER_LIST"
  echo
  echo "# 設定集"
  echo
  echo "- [角色設定](characters.md)"
  echo "- [世界觀：劍關規則](world.md)"
  echo "- [伏筆追蹤](foreshadowing.md)"
  echo
  echo "# 其他"
  echo
  echo "- [版權說明](license-notice.md)"
} > "$SRC/SUMMARY.md"

echo "==> mdbook build"
mdbook build

echo
echo "完成：site/"
ls site | head -20
