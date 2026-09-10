#!/usr/bin/env node
// PreToolUse deny —— 補 git hook 擋不掉的那條：`git -c core.hooksPath=/dev/null commit`。
// Claude Code 與 Codex 共用同一份 PreToolUse 合約（stdin JSON → stdout JSON），
// 所以這一支同時給兩家用（在各自 settings 的 PreToolUse 陣列「追加」一項，不改 OMC 那支）。
//
// 只擋「明確要繞過署名門」的少數幾種命令，不擋一般 git commit／push（agent 在其他 repo 仍要能正常提交）。
// 失敗一律放行（fail-open）：這支的作用是攔那幾個危險 flag，不是當第二個權限系統。
import process from 'node:process';

const ALLOW_PASS = () => { process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true })); process.exit(0); };

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => {
  let data; try { data = JSON.parse(raw || '{}'); } catch { return ALLOW_PASS(); }
  const tool = data.tool_name || data.toolName || '';
  if (tool !== 'Bash' && tool !== 'bash' && tool !== 'shell') return ALLOW_PASS();
  const cmd = (data.tool_input || data.toolInput || {}).command || '';
  if (!cmd) return ALLOW_PASS();

  // 只針對「動到 git 提交/身分」的命令。每條都有具體、無正當用途的危險理由。
  const RULES = [
    { re: /\bgit\b[^\n]*\s-c\s+core\.hookspath\s*=/i,
      why: '用 -c core.hooksPath= 繞過署名 hook —— 這是唯一 git hook 擋不掉的路，禁止。要跑 hook 就別加這個。' },
    { re: /\bGIT_CONFIG_(COUNT|KEY_\d+)\b[^\n]*hookspath/i,
      why: '用 GIT_CONFIG_* 注入 core.hooksPath 繞過署名 hook，禁止。' },
    { re: /\bcore\.hookspath\s*=\s*(\/dev\/null|['"]?\s*['"]?$|\/)/i,
      why: '把 core.hooksPath 設成空/停用署名 hook，禁止。' },
    { re: /\bgit\s+commit-tree\b/i,
      why: 'git commit-tree 直接造 commit、完全跳過所有 hook，禁止。用一般 git commit。' },
    { re: /\bgit\s+config\s+(--global\s+|--system\s+)?(--global\s+|--system\s+)?user\.(name|email)\b/i,
      why: '改 global/system 的 git user.name/email 會動到全域署名（：只准設 --local）。' },
    { re: /\bgit\s+config\b(?![^\n]*--(get|list))[^\n]*\bcore\.hookspath\b/i,
      why: '改 git 的 core.hooksPath（設定/清除/unset）會動到署名 hook 的掛載，禁止手動改；用 git-hooks/install.sh。（讀取 --get/--list 不擋）' },
  ];
  for (const r of RULES) {
    if (r.re.test(cmd)) {
      process.stdout.write(JSON.stringify({
        continue: true,
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: `[git-author-guard] 這個命令被擋下：${r.why}`,
        },
      }));
      process.exit(0);
    }
  }
  ALLOW_PASS();
});
process.stdin.on('error', ALLOW_PASS);
