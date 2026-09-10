#!/bin/sh
# git-author-guard —— git 署名防護，一支腳本，靠 basename($0) 分派給四個 hook。
# 由 core.hooksPath 指過來（見 install.sh）。
#
# 允許的 author 讀自同目錄 authors.allow（一行一個 email）。
# 查的是 `git var GIT_AUTHOR_IDENT` —— 那是「生效後」的身分，
# --author=／GIT_AUTHOR_EMAIL／env 都已經套進去，所以蓋不掉這道檢查（已實測）。
# 擋不掉的只有 `git -c core.hooksPath=/dev/null` —— 那條由 agent 層 deny（見 README）。
#
# 注意：不要用 set -u。hook 由 /bin/sh 在 C locale 下跑，
#       `$VAR` 後面緊接中文（如 $ALLOW。）會被 set -u 誤判為未定義變數。全程改用 ${VAR}。
set -e

hook=$(basename "$0")
hookdir=$(cd "$(dirname "$0")" && pwd)

# 允許清單來源：同目錄 authors.allow（一行一個 email）。讀不到才用內建預設。
# 分享成通用插件時只換 authors.allow，程式碼不動。
ALLOWFILE="${hookdir}/authors.allow"
if [ -f "${ALLOWFILE}" ]; then
  ALLOWLIST=$(grep -vE '^\s*#|^\s*$' "${ALLOWFILE}" | tr -d ' ')
else
  # 沒有 authors.allow：不曉得誰算合法，安全起見一律拒（fail-closed）。
  echo "🔴 git-author-guard：找不到 ${ALLOWFILE}，無法判斷允許的身分，拒絕提交。" >&2
  echo "   cp ${hookdir}/authors.allow.example ${hookdir}/authors.allow 並填入允許的 email。" >&2
  exit 1
fi
# 給訊息用的第一個允許值
ALLOW=$(printf '%s\n' "${ALLOWLIST}" | head -1)

is_allowed() {  # $1=email → 0 表示在清單內
  printf '%s\n' "${ALLOWLIST}" | grep -qxF "$1"
}

author_email()    { git var GIT_AUTHOR_IDENT 2>/dev/null    | sed -n 's/.*<\(.*\)>.*/\1/p'; }
committer_email() { git var GIT_COMMITTER_IDENT 2>/dev/null | sed -n 's/.*<\(.*\)>.*/\1/p'; }

reject() {
  echo "🔴 git-author-guard：${1}" >&2
  echo "   允許的 author 只有 ${ALLOW} 。修法：" >&2
  echo "   git -C <repo> config --local user.email ${ALLOW}，" >&2
  echo "   並移除命令列的 --author= 或 GIT_AUTHOR_*／GIT_COMMITTER_* 環境變數後重來。" >&2
  exit 1
}

check_ident() {
  ae=$(author_email); ce=$(committer_email)
  is_allowed "${ae}" || reject "author = <${ae:-空}> 不允許"
  is_allowed "${ce}" || reject "committer = <${ce:-空}> 不允許"
}

classify() {  # 印出不允許原因；允許則不印
  who=$1
  if is_allowed "${who}"; then return; fi
  case "${who}" in
    *@local|*@localhost|*@*.local) echo "<${who}> 是 @local 類" ;;
    *hotmail.com|*gmail.com)        echo "<${who}> 是個人信箱" ;;
    *)                              echo "<${who}> 不在允許清單" ;;
  esac
}

case "${hook}" in
  prepare-commit-msg|pre-commit|pre-merge-commit)
    check_ident
    ;;
  pre-push)
    # 只掃「遠端還沒有的新 commit」，不掃整段歷史（史裡有同事 gmail，不能誤擋）。
    # stdin 每行: <local ref> <local sha> <remote ref> <remote sha>
    bad=0
    while read -r lref lsha rref rsha; do
      [ "${lsha}" = "0000000000000000000000000000000000000000" ] && continue
      if printf '%s' "${rsha}" | grep -q '^0*$'; then
        range="${lsha}"                                  # 遠端無此分支：排除所有已在遠端的
        for r in $(git for-each-ref --format='%(objectname)' refs/remotes 2>/dev/null); do
          range="${range} ^${r}"
        done
      else
        range="${rsha}..${lsha}"                         # 一般：只掃新增段
      fi
      for sha in $(git rev-list ${range} 2>/dev/null); do
        for who in "$(git log -1 --format='%ae' "${sha}")" "$(git log -1 --format='%ce' "${sha}")"; do
          why=$(classify "${who}")
          [ -n "${why}" ] && { echo "🔴 pre-push 擋下：${sha} 署名 ${why}，不准推" >&2; bad=1; }
        done
      done
    done
    [ "${bad}" = 0 ] || { echo "   這些是你這次要推、遠端還沒有的 commit。修掉署名再推。" >&2; exit 1; }
    ;;
esac
