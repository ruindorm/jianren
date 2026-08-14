#!/usr/bin/env bash
# 產生 RoyalRoad 投稿包：建檔欄位稿 + 每章可直接貼上的 HTML + 400x600 封面。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT=build/royalroad
rm -rf "$OUT"
mkdir -p "$OUT/chapters"

echo "==> 章節 HTML"
: > "$OUT/CHAPTER-TITLES.txt"
i=0
for f in $(ls i18n/en/*.md | sort); do
  i=$((i + 1))
  title="$(head -1 "$f" | sed 's/^#\+[[:space:]]*//')"
  num="$(printf '%02d' "$i")"
  slug="$(basename "$f" .md | sed 's/^[0-9]*-//')"

  # 場景標記由引言改成斜體單行（RoyalRoad 編輯器會吃掉 blockquote 樣式）
  # 並移除 H1（RoyalRoad 的章節標題是獨立欄位）
  sed -E 's/^> \*\*(.*)\*\*$/*\1*/' "$f" \
    | sed '1d' \
    | pandoc -f markdown -t html --wrap=none \
    > "$OUT/chapters/${num}-${slug}.html"

  printf '%s\t%s\n' "$num" "$title" >> "$OUT/CHAPTER-TITLES.txt"
  echo "    ${num}-${slug}.html  ← $title"
done

echo "==> 封面 400x600"
command -v magick >/dev/null 2>&1 && IM=magick || IM=convert
FONT="$(fc-match -f '%{file}' 'DejaVu Serif:style=Bold' 2>/dev/null || true)"
[ -f "$FONT" ] || FONT="$(fc-match -f '%{file}' ':weight=bold' 2>/dev/null || true)"
if [ -f "$FONT" ] && $IM -size 400x600 gradient:'#161622-#2b2438' \
    -font "$FONT" \
    -fill '#e9dfc4' -pointsize 54 -gravity north -annotate +0+150 'BASTARD' \
    -fill '#e9dfc4' -pointsize 54 -annotate +0+215 'BLADE' \
    -fill '#9b93b5' -pointsize 15 -annotate +0+320 'My sword is for picking up girls.' \
    -fill '#6f6885' -pointsize 16 -gravity south -annotate +0+50 'YANG HOU' \
    "$OUT/cover-400x600.png" 2>/dev/null; then
  echo "    cover-400x600.png"
else
  echo "    封面略過"
fi

echo "==> 建檔欄位稿"
cat > "$OUT/00-FICTION-SETUP.md" <<'EOF'
# RoyalRoad 建檔欄位稿

建立作品時（Write → Create Fiction）把下面的內容照欄位填入。

---

## Title

```
Bastard Blade
```

## Description（作品簡介）

RoyalRoad 的簡介欄位吃 BBCode。直接貼下面整段：

```
[b]"Master, where bastardry is concerned, your reputation is thoroughly earned. But the biggest bastard in the world is not you. It is someone else."[/b]

His sect thinks he has qi deviation. He mutters to himself constantly, argues with the empty air, and has never once explained why.

He is not insane. He is arguing with his sword.

The sword runs win-rate analysis before duels, offers to configure a git environment before performing a search, and delivers contingency plan summaries at the worst possible moments. It also has a mouth filthier than his — which is impressive, because his is very filthy.

When a rival sect forces open his sect's Sword Gate and puts his senior brother on the ground, he steps into a duel where the rules are simple and horrible: your consciousness is locked inside your own blade, you are handed a mirror of your enemy's sword, and you must use their weapon to destroy their weapon.

He also has to say the activation phrase out loud. In front of everyone.

He configured it himself.

[hr][/hr]

[b]Translated and transcreated from the Chinese original 《劍人》 by the author.[/b]
A comedy first, a cultivation story second. Roughly 7,500 words so far — Volume One is complete.

Free to read here and always will be. Full text, all formats, and the original Chinese:
https://ruindorm.github.io/jianren/
```

## Cover

上傳 `cover-400x600.png`（RoyalRoad 建議 400×600）。
這是程式生成的暫代封面 — 有正式美術稿請直接換掉。

---

## Tags（類型標籤）

RoyalRoad 的標籤是固定清單，請在建檔頁面的清單裡勾選。建議勾這些：

- **Comedy** ← 最重要，這是喜劇不是爽文，標錯會招來錯的讀者
- **Martial Arts**
- **Xianxia**
- **Action**
- **Fantasy**
- **Male Lead**
- **Artificial Intelligence**
- **Satire**

清單會不定期調整，以網站上實際看到的為準。
**Comedy 一定要勾** — 讀者期待設定錯了，評分會很慘。

## Content Warnings

- **Profanity** ← 一定要勾。全篇都是髒話

---

## AI 揭露 — 已查證，結論：不需要標籤，但有前提

RoyalRoad 官方 AI 政策（Royal Road AI-text policy）第 5 條，翻譯有專門條款：

> **5.** If the AI is used for translating a fiction, the novel must be read and
> proofread by someone who knows the language to guarantee the accuracy.
>
> *(Update: **No tag is required for this, as long as a human goes over the translation.**
> As this is likely going to be the new translation standard.*
>
> *If no human reads, proofreads, and edits the translation, then it must be tagged as
> "AI-assisted" as it will retain the AI's tone, and voice.)*

**所以：**

| 你的做法 | 需要的標籤 |
|---|---|
| 你自己從頭讀過英文版、確認語氣與笑點正確 | **不需要任何 AI 標籤** |
| 直接上傳沒讀過 | 必須標 **AI-Assisted** |

原文是你 100% 手寫的，翻譯有人（你）逐句過目——完全落在「無需標籤」那一格。

**唯一的要求是你真的要讀過。** 上傳前把英文版看一遍，順便確認語氣對不對，
不對的地方直接改——那本來就該做，跟 AI 政策無關。

註：該政策頁面標註為 dynamic policy，發布於 2023-06 後仍可能調整。
建檔頁面實際看到的選項若與此不符，以網站當下為準。

---

## 發文節奏建議

第一次投稿不要一口氣全放。RoyalRoad 的推薦機制吃「持續更新」：

1. **第一天**：Prologue + Ch.1 + Ch.2（三章讓人看得出調性）
2. **之後每天一章**，連續放完剩下的
3. 排程功能可以先全部排好，不用每天手動

一次全丟只會在 Latest Updates 上出現一次；分批放會出現十四次。

---

## 章節標題

見 `CHAPTER-TITLES.txt`。每章上傳時：

1. Title 欄位 → 貼該章標題
2. 內文 → 用編輯器的 **HTML / source 模式**，貼對應的 `chapters/NN-*.html` 全部內容
3. 不要貼 Markdown，RoyalRoad 不吃

`chapters/` 裡的 HTML **已經移除章節標題**（RoyalRoad 的標題是獨立欄位，重複會出現兩次）。

---

## Author's Note（每章結尾，選填）

第一章可以放這段：

```
Original Chinese version, all formats, and the setting notes:
https://ruindorm.github.io/jianren/

This is a transcreation, not a literal translation — two jokes had to be rebuilt from
scratch because they depended on characters not speaking English. Notes on what changed:
https://ruindorm.github.io/jianren/en/translation-notes.html
```
EOF

echo
echo "完成：$OUT"
ls -R "$OUT" | head -30
