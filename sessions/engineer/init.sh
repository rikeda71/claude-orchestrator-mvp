#!/usr/bin/env bash
#
# Engineerペイン初期化スクリプト
# Claudeを起動し、Engineerとしての役割を開始
#

set -euo pipefail

# 引数の取得
TASK_ID="${1:-}"
ENGINEER_ROLE="${2:-}"
WORK_DIR="${3:-}"
PANE_ID="${4:-}"
ORCHESTRATOR_ROOT="${5:-}"

if [[ -z "$TASK_ID" ]] || [[ -z "$ENGINEER_ROLE" ]] || [[ -z "$WORK_DIR" ]] || [[ -z "$PANE_ID" ]] || [[ -z "$ORCHESTRATOR_ROOT" ]]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <TASK_ID> <ENGINEER_ROLE> <WORK_DIR> <PANE_ID> <ORCHESTRATOR_ROOT>"
    exit 1
fi

# 作業ディレクトリに移動
cd "${WORK_DIR}"

# 環境変数をエクスポート
export TASK_ID
export ENGINEER_ROLE
export WORK_DIR
export PANE_ID
export ORCHESTRATOR_ROOT

# 初期プロンプトファイルを生成
INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/engineer/init-prompt-v0.2.0.txt"
INIT_PROMPT_FILE="/tmp/claude-${ENGINEER_ROLE}-init-${TASK_ID}.txt"

envsubst < "${INIT_PROMPT_TEMPLATE}" > "${INIT_PROMPT_FILE}"

# Claudeを起動（自動実行モード）
exec claude --dangerously-skip-permissions "@${INIT_PROMPT_FILE}"
