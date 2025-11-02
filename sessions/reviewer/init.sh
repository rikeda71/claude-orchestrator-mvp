#!/usr/bin/env bash
#
# Reviewerペイン初期化スクリプト
# Claudeを起動し、Reviewerとしての役割を開始
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

# 作業ディレクトリに移動（sessions/reviewer/）
# Reviewer は orchestrator context で動作し、Engineer の worktree に直接アクセス
cd "${WORK_DIR}"

# 設定ファイルの読み込み
if [[ -f "${ORCHESTRATOR_ROOT}/config/target-project.conf" ]]; then
    # shellcheck source=../../config/target-project.conf
    source "${ORCHESTRATOR_ROOT}/config/target-project.conf"
fi

if [[ -f "${ORCHESTRATOR_ROOT}/config/orchestrator.conf" ]]; then
    # shellcheck source=../../config/orchestrator.conf
    source "${ORCHESTRATOR_ROOT}/config/orchestrator.conf"
fi

# 環境変数をエクスポート
export TASK_ID
export ENGINEER_ROLE
export WORK_DIR
export PANE_ID
export ORCHESTRATOR_ROOT
export TARGET_PROJECT_PATH
export TARGET_PROJECT_MAIN_BRANCH
export REVIEW_REQUIRED
export NUM_ENGINEERS
export ROLE="reviewer"

# 初期プロンプトファイルを生成
INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/reviewer/init-prompt-v0.3.0.txt"
INIT_PROMPT_FILE="/tmp/claude-reviewer-init-${TASK_ID}.txt"

# テンプレートが存在しない場合は従来のinit-prompt.txtを使用
if [[ ! -f "$INIT_PROMPT_TEMPLATE" ]]; then
    INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/reviewer/init-prompt.txt"
fi

envsubst < "${INIT_PROMPT_TEMPLATE}" > "${INIT_PROMPT_FILE}"

# Claudeを起動（自動実行モード）
exec claude --dangerously-skip-permissions "@${INIT_PROMPT_FILE}"
