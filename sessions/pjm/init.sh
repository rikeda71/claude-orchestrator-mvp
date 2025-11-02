#!/usr/bin/env bash
#
# PjMペイン初期化スクリプト
# Claudeを起動し、PjMとしての役割を開始
#

set -euo pipefail

# 引数の取得
TASK_ID="${1:-}"
ORCHESTRATOR_ROOT="${2:-}"
USER_INSTRUCTION="${3:-}"

if [[ -z "$TASK_ID" ]] || [[ -z "$ORCHESTRATOR_ROOT" ]] || [[ -z "$USER_INSTRUCTION" ]]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <TASK_ID> <ORCHESTRATOR_ROOT> <USER_INSTRUCTION>"
    exit 1
fi

# 作業ディレクトリに移動
cd "${ORCHESTRATOR_ROOT}/sessions/pjm"

# 環境変数をエクスポート
export TASK_ID
export ORCHESTRATOR_ROOT
export USER_INSTRUCTION

# 初期プロンプトファイルを生成
INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/pjm/init-prompt-v0.2.0.txt"
INIT_PROMPT_FILE="/tmp/claude-pjm-init-${TASK_ID}.txt"

envsubst < "${INIT_PROMPT_TEMPLATE}" > "${INIT_PROMPT_FILE}"

# Claudeを起動（自動実行モード）
exec claude --dangerously-skip-permissions "@${INIT_PROMPT_FILE}"
