#!/usr/bin/env bash
#
# Documentation Writerペイン初期化スクリプト
# Claudeを起動し、Documentation Writerとしての役割を開始
#

set -euo pipefail

# 引数の取得
TASK_ID="${1:-}"
ROLE="${2:-docs}"
WORK_DIR="${3:-}"
PANE_ID="${4:-}"
ORCHESTRATOR_ROOT="${5:-}"

if [[ -z "$TASK_ID" ]] || [[ -z "$ROLE" ]] || [[ -z "$WORK_DIR" ]] || [[ -z "$PANE_ID" ]] || [[ -z "$ORCHESTRATOR_ROOT" ]]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <TASK_ID> <ROLE> <WORK_DIR> <PANE_ID> <ORCHESTRATOR_ROOT>"
    exit 1
fi

# 作業ディレクトリに移動（sessions/docs/）
# Docs Writer は orchestrator context で動作し、Engineer の worktree と TARGET_PROJECT_PATH に直接アクセス
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
export ROLE
export WORK_DIR
export PANE_ID
export ORCHESTRATOR_ROOT
export TARGET_PROJECT_PATH
export TARGET_PROJECT_MAIN_BRANCH
export NUM_ENGINEERS
export DOCS_ENABLED
export DOCS_TARGETS
export DOCS_AUTO_COMMIT

# 初期プロンプトファイルを生成
INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/docs/init-prompt-v0.4.0.txt"
INIT_PROMPT_FILE="/tmp/claude-docs-init-${TASK_ID}.txt"

# テンプレートが存在しない場合は従来のinit-prompt.txtを使用
if [[ ! -f "$INIT_PROMPT_TEMPLATE" ]]; then
    INIT_PROMPT_TEMPLATE="${ORCHESTRATOR_ROOT}/sessions/docs/init-prompt.txt"
fi

envsubst < "${INIT_PROMPT_TEMPLATE}" > "${INIT_PROMPT_FILE}"

# Claudeを起動（自動実行モード）
exec claude --dangerously-skip-permissions "@${INIT_PROMPT_FILE}"
