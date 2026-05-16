#!/bin/bash
# claudecrew launch.sh — Launch a worker/reviewer agent in a new terminal window
# Usage: launch.sh <project-root> <spec-file-path>
#
# 使用 claude -p 直接传入 prompt 并自动发送。
# 跨平台：macOS (iTerm2 → Terminal)、Linux (gnome-terminal → xterm → tmux → 手动)

set -euo pipefail

PROJECT_ROOT="$1"
SPEC_FILE="$2"

if [ -z "$PROJECT_ROOT" ] || [ -z "$SPEC_FILE" ]; then
    echo "Usage: launch.sh <project-root> <spec-file-path>"
    exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd || echo "$PROJECT_ROOT")"
AGENT_ID="$(basename "$SPEC_FILE" .md)"

PROMPT="请阅读文件 ${SPEC_FILE} 并严格执行其中的所有指令。完成该文件中定义的每一个任务步骤（含编写、测试、修改），遵守每一项约束。全部完成后：1) 将结果摘要写入 spec 中「预期产出」指定的 result 文件；2) 作为最后一步，创建空文件 SPEC/<request-dir>/results/<你的 agent-id>已完成.md 作为完成信号——母 Agent 只会通过这个 已完成.md 文件判断你是否完成，所以务必在一切就绪后才创建它。不要做该 spec 文件范围之外的任何事情。"

# ── 转义处理 ─────────────────────────────────────────────
# osascript: 转义单引号 \' → '\''(shell 格式)
SAFE_PROMPT_OSA="${PROMPT//\'/\'\\\'\'}"
# Linux 终端: 转义双引号 " → \"
SAFE_PROMPT_SH="${PROMPT//\"/\\\"}"

CMD="cd '${PROJECT_ROOT}' && claude -p '${SAFE_PROMPT_OSA}'"
CMD_SH="cd \"${PROJECT_ROOT}\" && claude -p \"${SAFE_PROMPT_SH}\""

launch_macos() {
    # 优先 iTerm2（支持 create tab，交互更可靠）
    if command -v osascript &>/dev/null && osascript -e 'tell application "iTerm2" to activate' 2>/dev/null; then
        osascript -e "tell application \"iTerm2\" to tell current window to create tab with default profile command \"${CMD_SH}\"" 2>/dev/null && return 0
    fi
    # fallback: Terminal.app
    if command -v osascript &>/dev/null; then
        osascript -e "tell application \"Terminal\" to activate" 2>/dev/null
        osascript -e "tell application \"Terminal\" to do script \"${CMD}\"" 2>/dev/null && return 0
    fi
    return 1
}

launch_linux() {
    if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "${CMD_SH}; exec bash" &>/dev/null && return 0
    fi
    if command -v xterm &>/dev/null; then
        xterm -e "${CMD_SH}" &>/dev/null && return 0
    fi
    if command -v tmux &>/dev/null && [ -n "${TMUX:-}" ]; then
        tmux new-window "${CMD_SH}" 2>/dev/null && return 0
    fi
    return 1
}

# ── 启动 ──────────────────────────────────────────────────
LAUNCHED=false

if [[ "$OSTYPE" == "darwin"* ]]; then
    launch_macos && LAUNCHED=true
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    launch_linux && LAUNCHED=true
fi

echo ""
echo "═══════════════════════════════════════════"
if $LAUNCHED; then
    echo "  [claudecrew] 已启动 Agent: ${AGENT_ID}"
    echo "  Spec:  ${SPEC_FILE}"
else
    echo "  [claudecrew] ⚠️ 无法自动打开终端窗口"
    echo "  请在新终端中手动执行："
    echo ""
    echo "    cd '${PROJECT_ROOT}' && claude -p '${SAFE_PROMPT_OSA}'"
    echo ""
    echo "  Agent ID: ${AGENT_ID}"
    echo "  Spec:     ${SPEC_FILE}"
fi
echo "═══════════════════════════════════════════"
