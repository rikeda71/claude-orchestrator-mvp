#!/usr/bin/env bash
#
# stop-system.sh - システム停止スクリプト
# Claude Orchestratorシステムを安全に停止
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

#
# 進行中タスクの確認
#
check_running_tasks() {
    log_info "Checking for running tasks..."

    local in_progress_dir="${TASK_DIR}/in-progress"
    local task_count=0

    if [[ -d "$in_progress_dir" ]]; then
        task_count=$(find "$in_progress_dir" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [[ $task_count -gt 0 ]]; then
        log_warn "Found ${task_count} task(s) in progress"
        echo ""
        echo "Tasks in progress:"

        for task_file in "${in_progress_dir}"/*.json; do
            [[ -f "$task_file" ]] || continue

            local task_id
            task_id=$(json_get "$task_file" '.id')
            local description
            description=$(json_get "$task_file" '.description')
            local assigned_to
            assigned_to=$(json_get "$task_file" '.assigned_to')

            echo "  - ${task_id} (${assigned_to}): ${description}"
        done

        echo ""
        return 1
    else
        log_success "No tasks in progress"
        return 0
    fi
}

#
# セッションへの終了通知
#
notify_sessions() {
    log_info "Notifying sessions about shutdown..."

    for role in pjm eng1; do
        local session_name
        session_name=$(get_session_name "$role")

        if tmux_session_exists "$session_name"; then
            # メッセージ送信
            "$MESSENGER" send system "$role" "System is shutting down..." 2>/dev/null || true

            # セッションログに記録
            log_session "$role" "INFO" "Shutdown notification sent"
        fi
    done

    # 通知が届くまで少し待機
    sleep 1

    log_success "Shutdown notifications sent"
}

#
# セッションのログ保存
#
save_session_logs() {
    log_info "Saving session logs..."

    for role in pjm eng1; do
        local session_name
        session_name=$(get_session_name "$role")

        if tmux_session_exists "$session_name"; then
            # セッション出力のキャプチャ
            local capture_file="${LOG_DIR}/sessions/${role}_shutdown_$(date +%Y%m%d_%H%M%S).log"
            "$SESSION_MANAGER" capture "$role" 1000 > "$capture_file" 2>/dev/null || true

            log_debug "Session log saved: ${capture_file}"
        fi
    done

    log_success "Session logs saved"
}

#
# セッションの停止
#
stop_sessions() {
    log_info "Stopping sessions..."

    # ビューアセッションの停止
    local viewer_session="${TMUX_SESSION_PREFIX}-viewer"
    if tmux_session_exists "$viewer_session"; then
        log_info "Stopping viewer session"
        tmux kill-session -t "$viewer_session" 2>/dev/null || true
    fi

    # 通常のセッションの停止
    for role in pjm eng1 eng2 reviewer docs; do
        local session_name
        session_name=$(get_session_name "$role")

        if tmux_session_exists "$session_name"; then
            log_info "Stopping session: ${role}"
            "$SESSION_MANAGER" kill "$role"
            log_session "$role" "INFO" "Session stopped"
        fi
    done

    log_success "Sessions stopped"
}

#
# 通信パイプのクリーンアップ
#
cleanup_pipes() {
    log_info "Cleaning up communication pipes..."

    "$MESSENGER" cleanup-pipes

    log_success "Communication pipes cleaned up"
}

#
# メッセージのクリーンアップ
#
cleanup_messages() {
    log_info "Cleaning up messages..."

    "$MESSENGER" cleanup 0

    log_success "Messages cleaned up"
}

#
# システムステータスの保存
#
save_system_status() {
    log_info "Saving system status..."

    local status_file="${LOG_DIR}/system/shutdown_status_$(date +%Y%m%d_%H%M%S).json"

    cat > "$status_file" <<EOF
{
  "shutdown_time": "$(timestamp)",
  "sessions_stopped": ["pjm", "eng1"],
  "task_counts": {
    "pending": $(find "${TASK_DIR}/queue" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' '),
    "in_progress": $(find "${TASK_DIR}/in-progress" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' '),
    "review": $(find "${TASK_DIR}/reviews" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' '),
    "completed": $(find "${TASK_DIR}/completed" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  }
}
EOF

    log_debug "System status saved: ${status_file}"
    log_success "System status saved"
}

#
# 終了メッセージの表示
#
show_goodbye() {
    cat <<'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          Claude Orchestrator System Stopped                  ║
║                                                               ║
║  Thank you for using the system!                             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    log_info "System stopped successfully"
    echo ""
    log_info "Logs saved in: ${LOG_DIR}"
    log_info "To restart: ./scripts/start-system.sh"
    echo ""
}

#
# メイン処理
#
main() {
    local force="false"
    local skip_task_check="false"

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force="true"
                skip_task_check="true"
                shift
                ;;
            --skip-task-check)
                skip_task_check="true"
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [options]

Options:
  --force, -f           Force shutdown even with tasks in progress
  --skip-task-check     Skip checking for tasks in progress
  --help, -h            Show this help message

Description:
  Safely stops the Claude Orchestrator system with the following steps:
  1. Check for running tasks (optional)
  2. Notify sessions about shutdown
  3. Save session logs
  4. Stop all tmux sessions
  5. Clean up communication pipes
  6. Save system status

Examples:
  $0                    # Normal shutdown (checks for running tasks)
  $0 --force            # Force shutdown
  $0 --skip-task-check  # Skip task check but ask for confirmation
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

    log_info "=== Claude Orchestrator System Shutdown ==="
    log_system "orchestrator" "INFO" "Starting shutdown sequence..."

    # 進行中タスクのチェック
    if [[ "$skip_task_check" == "false" ]]; then
        if ! check_running_tasks; then
            if [[ "$force" == "false" ]]; then
                echo ""
                read -p "Continue with shutdown? (y/N): " -n 1 -r
                echo ""

                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Shutdown cancelled"
                    exit 0
                fi
            else
                log_warn "Force shutdown requested, ignoring running tasks"
            fi
        fi
    fi

    # 停止シーケンス
    notify_sessions
    save_session_logs
    stop_sessions
    cleanup_pipes
    cleanup_messages
    save_system_status

    # 終了メッセージ
    show_goodbye

    log_system "orchestrator" "INFO" "System shutdown complete"
    log_success "=== System shutdown complete ==="
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
