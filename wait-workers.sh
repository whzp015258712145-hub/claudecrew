#!/bin/bash
# claudecrew wait-workers.sh — 后台轮询等待所有 Worker 发出「完成信号」
# Usage: wait-workers.sh <expected-worker-count> <results-dir> [max-wait-sec]
#
# ⚠️ 不盯 result 文件（Worker 可能提前写 result 然后还在测试/修改）
# ✅ 只盯 已完成.md 信号文件（Worker 全部工作完成后的最后一步才 touch 它）
#
# 由母 Agent 在后台运行（Bash run_in_background），
# 母 Agent 通过 TaskOutput block=true 等待此脚本返回。
# 脚本每 10 秒检查一次 results/ 目录，

set -euo pipefail

EXPECTED_COUNT="${1:-}"
RESULTS_DIR="${2:-}"
MAX_WAIT="${3:-600}"

if [ -z "$EXPECTED_COUNT" ] || [ -z "$RESULTS_DIR" ]; then
    echo "Usage: wait-workers.sh <expected-worker-count> <results-dir> [max-wait-sec]"
    exit 2
fi

if [ ! -d "$RESULTS_DIR" ]; then
    echo "[claudecrew] 结果目录不存在，等待创建: $RESULTS_DIR"
    mkdir -p "$RESULTS_DIR"
fi

INTERVAL=10
ELAPSED=0
LAST_COUNT=-1

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    # 🔑 只盯 已完成.md 信号文件——Worker 在所有工作（含测试、修改）完成后才创建它
    count=$(find "$RESULTS_DIR" -maxdepth 1 -name '*已完成.md' 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count" != "$LAST_COUNT" ]; then
        echo "[claudecrew] $(date +%H:%M:%S) 进度: ${count}/${EXPECTED_COUNT} Worker 已发出完成信号"
        LAST_COUNT="$count"
    fi

    if [ "$count" -ge "$EXPECTED_COUNT" ]; then
        echo "[claudecrew] ✅ 所有 Worker 完成 (${count}/${EXPECTED_COUNT})"
        echo ""
        echo "完成信号文件:"
        find "$RESULTS_DIR" -maxdepth 1 -name '*已完成.md' | sort | while read -r f; do
            echo "  $(basename "$f")"
        done
        echo ""
        echo "结果文件:"
        find "$RESULTS_DIR" -maxdepth 1 -name 'result-*.md' | sort | while read -r f; do
            echo "  $(basename "$f") ($(wc -c < "$f" | tr -d ' ') 字节)"
        done
        exit 0
    fi

    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "[claudecrew] ⚠️ 超时: ${ELAPSED}s 内仅 ${LAST_COUNT}/${EXPECTED_COUNT} Worker 发出完成信号"
exit 1
