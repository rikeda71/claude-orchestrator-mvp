#!/usr/bin/env bash
#
# start-system.sh - システム起動スクリプト
# Claude Orchestratorシステム全体を起動
#

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通ユーティリティの読み込み
# shellcheck source=./utils/common.sh
source "${SCRIPT_DIR}/utils/common.sh"
# shellcheck source=./utils/logger.sh
source "${SCRIPT_DIR}/utils/logger.sh"

# コアスクリプトのパス
SESSION_MANAGER="${SCRIPT_DIR}/core/session-manager.sh"
MESSENGER="${SCRIPT_DIR}/core/messenger.sh"
TASK_MANAGER="${SCRIPT_DIR}/core/task-manager.sh"

#
# 前提条件のチェック
#
check_prerequisites() {
    log_info "Checking prerequisites..."

    # 必須コマンドのチェック
    check_required_commands tmux git jq

    # 設定ファイルのチェック
    if [[ ! -f "$TARGET_PROJECT_CONF" ]]; then
        log_warn "Target project configuration not found: ${TARGET_PROJECT_CONF}"
        log_warn "Please create config/target-project.conf from the example"

        # テンプレートの存在確認
        local template="${TARGET_PROJECT_CONF}.example"
        if [[ -f "$template" ]]; then
            log_info "Example configuration available at: ${template}"
        fi
    fi

    # TARGET_PROJECT_PATHの確認
    if [[ -n "${TARGET_PROJECT_PATH:-}" ]]; then
        if [[ ! -d "$TARGET_PROJECT_PATH" ]]; then
            log_warn "Target project path does not exist: ${TARGET_PROJECT_PATH}"
            log_warn "Please update config/target-project.conf with correct path"
        else
            log_success "Target project found: ${TARGET_PROJECT_PATH}"
        fi
    else
        log_warn "TARGET_PROJECT_PATH not configured"
        log_info "System will run in standalone mode (no external project management)"
    fi

    log_success "Prerequisites check complete"
}

#
# ディレクトリ構造の初期化
#
init_directories() {
    log_info "Initializing directory structure..."

    # 必要なディレクトリの作成
    ensure_dir "$PIPE_DIR"
    ensure_dir "$LOG_DIR"
    ensure_dir "${LOG_DIR}/sessions"
    ensure_dir "${LOG_DIR}/system"
    ensure_dir "${LOG_DIR}/tasks"
    ensure_dir "$TASK_DIR/queue"
    ensure_dir "$TASK_DIR/in-progress"
    ensure_dir "$TASK_DIR/completed"
    ensure_dir "$TASK_DIR/reviews"
    ensure_dir "$WORKTREE_BASE"
    ensure_dir "${ORCHESTRATOR_ROOT}/communication/buffers"

    # セッションディレクトリの作成
    for role in pjm eng1 eng2 reviewer docs; do
        ensure_dir "${ORCHESTRATOR_ROOT}/sessions/${role}"
    done

    log_success "Directory structure initialized"
}

#
# 通信パイプの初期化
#
init_communication() {
    log_info "Initializing communication system..."

    # パイプの作成
    "$MESSENGER" init-pipes

    log_success "Communication system initialized"
}

#
# セッションの起動
#
start_sessions() {
    log_info "Starting sessions..."

    # Phase 1: PjMとeng1のみ起動
    local roles=("pjm" "eng1")

    for role in "${roles[@]}"; do
        log_info "Creating session: ${role}"
        "$SESSION_MANAGER" create "$role"
        sleep 1
    done

    log_success "Sessions started"
}

#
# セッションの状態確認
#
verify_sessions() {
    log_info "Verifying sessions..."

    "$SESSION_MANAGER" list

    # ヘルスチェック
    "$SESSION_MANAGER" health

    log_success "Session verification complete"
}

#
# システムログの開始
#
start_logging() {
    log_info "Starting system logging..."

    log_system "orchestrator" "INFO" "System startup initiated"

    log_success "System logging started"
}

#
# ウェルカムメッセージの表示
#
show_welcome() {
    cat <<'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          Claude Orchestrator System Started                  ║
║                                                               ║
║  Multi-Claude Workflow Management System                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    log_info "System is ready!"
    echo ""
    log_info "Active Sessions:"
    "$SESSION_MANAGER" list
    echo ""
    log_info "Available Commands:"
    echo "  - Attach to PjM session:   tmux attach -t ${TMUX_SESSION_PREFIX}-pjm"
    echo "  - Attach to eng1 session:  tmux attach -t ${TMUX_SESSION_PREFIX}-eng1"
    echo "  - View all sessions:       ./scripts/core/session-manager.sh list"
    echo "  - Create a task:           ./scripts/core/task-manager.sh create feature \"description\""
    echo "  - Stop system:             ./scripts/stop-system.sh"
    echo ""
    log_info "System logs: ${LOG_DIR}"
    echo ""
}

#
# 初期タスクの作成（オプション）
#
create_sample_tasks() {
    local create_samples="${1:-false}"

    if [[ "$create_samples" != "true" ]]; then
        return 0
    fi

    log_info "Creating sample tasks..."

    # サンプルタスクの作成
    "$TASK_MANAGER" create feature "システムのセットアップと動作確認" eng1 pjm
    "$TASK_MANAGER" create docs "READMEの更新" docs pjm

    log_success "Sample tasks created"
}

#
# メイン処理
#
main() {
    local create_samples="false"

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-samples)
                create_samples="true"
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [options]

Options:
  --with-samples    Create sample tasks after startup
  --help, -h        Show this help message

Description:
  Starts the Claude Orchestrator system with the following steps:
  1. Check prerequisites
  2. Initialize directories
  3. Setup communication pipes
  4. Start tmux sessions (pjm, eng1)
  5. Initialize logging

After startup, you can:
  - Attach to sessions using tmux
  - Create and manage tasks
  - Monitor system logs

Examples:
  $0                    # Start system normally
  $0 --with-samples     # Start with sample tasks
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # 初期化
    init_common
    init_logger

    log_info "=== Claude Orchestrator System Startup ==="
    log_system "orchestrator" "INFO" "Starting system..."

    # 起動シーケンス
    check_prerequisites
    init_directories
    init_communication
    start_logging
    start_sessions

    # 少し待機してセッションが安定するのを待つ
    sleep 2

    verify_sessions

    # サンプルタスクの作成（オプション）
    create_sample_tasks "$create_samples"

    # ウェルカムメッセージ
    show_welcome

    log_system "orchestrator" "INFO" "System startup complete"
    log_success "=== System startup complete ==="
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
