#!/usr/bin/env bash
# git-author-guard 安裝器 —— 把署名防護裝到你指定的 git repo，並接上本機的 AI coding agent。
#
#   ./install.sh <repo> [<repo> ...]     # 裝到這些 repo（core.hooksPath 指到本套 hooks/）
#   ./install.sh --check <repo> ...       # 只檢查，不改
#   ./install.sh --agents-only            # 只接 agent deny（Claude/Codex/Cursor），不動任何 repo
#
# 先決條件：把 hooks/authors.allow.example 複製成 hooks/authors.allow 並填入允許的 email。
# 不會動：全域 git 設定、repo 的既有遠端、各 agent 既有的 hook（deny 是「追加」）。
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$SELF/hooks"
CHECK=0; AGENTS_ONLY=0; REPOS=()
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --agents-only) AGENTS_ONLY=1 ;;
    *) REPOS+=("$a") ;;
  esac
done

if [ ! -f "$HOOKS_DIR/authors.allow" ]; then
  echo "🔴 缺 $HOOKS_DIR/authors.allow"
  echo "   先：cp \"$HOOKS_DIR/authors.allow.example\" \"$HOOKS_DIR/authors.allow\" 並填入允許的 email。"
  exit 1
fi
echo "允許的身分：$(grep -vE '^\s*#|^\s*$' "$HOOKS_DIR/authors.allow" | tr '\n' ' ')"
changed=0

if [ "$AGENTS_ONLY" = 0 ]; then
  [ ${#REPOS[@]} -gt 0 ] || { echo "🔴 沒指定 repo。用法見檔頭，或 --agents-only。"; exit 1; }
  echo "== A/B: git hook（core.hooksPath）=="
  for r in "${REPOS[@]}"; do
    if [ ! -d "$r/.git" ] && ! git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
      echo "  ⚠ 跳過（非 git）: $r"; continue
    fi
    cur=$(git -C "$r" config --local core.hooksPath || echo "")
    if [ "$cur" = "$HOOKS_DIR" ]; then echo "  ✅ 已設: $r"
    elif [ "$CHECK" = 1 ]; then echo "  ❌ 未設: $r（現值: ${cur:-無}）"
    else git -C "$r" config --local core.hooksPath "$HOOKS_DIR"; echo "  → 設定: $r（原: ${cur:-無}）"; changed=1
    fi
  done
fi

# 自動偵測本機有哪些 agent，接上 deny
DENY="$SELF/agents/agent-deny-git.mjs"
CURSOR_RULES="$SELF/agents/cursor-deny-rules.json"

echo "== C: Cursor deny =="
CJSON="$HOME/.cursor/cli-config.json"
if [ -f "$CJSON" ]; then
  if [ "$CHECK" = 1 ]; then
    node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1]));const w=JSON.parse(fs.readFileSync(process.argv[2]));const h=new Set((c.permissions?.deny)||[]);const m=w.filter(x=>!h.has(x));console.log(m.length?"  ❌ 缺 "+m.length+" 條":"  ✅ 齊全")' "$CJSON" "$CURSOR_RULES"
  else
    node -e 'const fs=require("fs");const p=process.argv[1];const c=JSON.parse(fs.readFileSync(p));const w=JSON.parse(fs.readFileSync(process.argv[2]));c.permissions=c.permissions||{allow:[],deny:[]};c.permissions.deny=c.permissions.deny||[];const h=new Set(c.permissions.deny);let n=0;for(const x of w)if(!h.has(x)){c.permissions.deny.push(x);n++}if(n){fs.writeFileSync(p,JSON.stringify(c,null,2));console.log("  → 加了 "+n+" 條")}else console.log("  ✅ 已齊全")' "$CJSON" "$CURSOR_RULES"; changed=1
  fi
else echo "  ⚠ 找不到 $CJSON（Cursor 未裝/未跑過）"; fi

echo "== D/E: Claude Code + Codex PreToolUse deny =="
for cfg in "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json"; do
  name=$(basename "$(dirname "$cfg")")
  [ -f "$cfg" ] || { echo "  ⚠ 找不到 $cfg（$name 未裝）"; continue; }
  present=$(node -e 'const fs=require("fs");const d=JSON.parse(fs.readFileSync(process.argv[1]));const a=(d.hooks&&d.hooks.PreToolUse)||[];console.log(JSON.stringify(a).includes("agent-deny-git.mjs")?"yes":"no")' "$cfg")
  if [ "$present" = yes ]; then echo "  ✅ $name 已含"
  elif [ "$CHECK" = 1 ]; then echo "  ❌ $name 未含"
  else
    node -e 'const fs=require("fs");const p=process.argv[1];const s=process.argv[2];const d=JSON.parse(fs.readFileSync(p));d.hooks=d.hooks||{};d.hooks.PreToolUse=d.hooks.PreToolUse||[];d.hooks.PreToolUse.push({hooks:[{type:"command",command:"node \""+s+"\""}]});fs.writeFileSync(p,JSON.stringify(d,null,2))' "$cfg" "$DENY"
    echo "  → $name 追加 deny（未動原有 hook）"; changed=1
  fi
done

echo
echo "手動收尾："
echo "  · Codex：改了 ~/.codex/hooks.json 後，在 Codex 執行 /hooks 信任，否則不生效。"
echo "  · Grok Build：用它的 /hooks-add 指到 agents/agent-deny-git.mjs（本套沒有它的自動接線）。"
echo "  · Antigravity：若它讀 Claude 相容的 settings，指到同一支 deny；否則手動加。"
[ "$CHECK" = 1 ] && echo "（--check 模式，未改任何東西）" || { [ "$changed" = 1 ] && echo "安裝完成。" || echo "全部已就緒。"; }
