#!/usr/bin/env bash
#
# stop-system.sh - システム停止スクリプト (v0.2.0)
# タスクセッションを停止
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
TASK_SESSION="${SCRIPT_DIR}/core/task-session.sh"
TASK_MANAGER="${SCRIPT_DIR}/core/task-manager.sh"

#
# タスクセッションのログ保存
#
save_task_session_logs() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        return 0
    fi

    log_info "Saving logs for task session: ${task_id}"

    local log_base="${LOG_DIR}/sessions/${task_id}_shutdown_$(date +%Y%m%d_%H%M%S)"

    # 各ペインのログをキャプチャ
    local pane_count
    pane_count=$(tmux list-panes -t "$session_name" 2>/dev/null | wc -l | tr -d ' ')

    for ((i=0; i<pane_count; i++)); do
        local log_file="${log_base}_pane${i}.log"
        tmux capture-pane -t "${session_name}.${i}" -p -S -1000 > "$log_file" 2>/dev/null || true
        log_debug "Pane ${i} log saved: ${log_file}"
    done

    log_success "Task session logs saved"
}

#
# タスクセッション名の取得（task-session.shから関数をインポート）
#
get_task_session_name() {
    local task_id="$1"
    echo "${TMUX_SESSION_PREFIX}-task-${task_id}"
}

#
# タスクステータスのチェック
#
check_task_status() {
    local task_id="$1"

    # タスク情報を取得
    local task_file=""

    # 全ディレクトリを検索
    for dir in queue in-progress reviews completed; do
        local file_path="${TASK_DIR}/${dir}/${task_id}.json"
        if [[ -f "$file_path" ]]; then
            task_file="$file_path"
            break
        fi
    done

    if [[ -z "$task_file" ]]; then
        log_warn "Task file not found: ${task_id}"
        return 0
    fi

    local status
    status=$(json_get "$task_file" '.status')

    if [[ "$status" == "in-progress" ]]; then
        log_warn "Task is still in progress: ${task_id}"
        local description
        description=$(json_get "$task_file" '.description')
        echo "  Task: ${description}"
        return 1
    fi

    return 0
}

#
# タスクセッションの停止
#
stop_task_session() {
    local task_id="$1"
    local force="$2"

    log_info "Stopping task session: ${task_id}"

    # タスクステータスのチェック
    if [[ "$force" == "false" ]]; then
        if ! check_task_status "$task_id"; then
            echo ""
            read -p "Task is in progress. Continue with shutdown? (y/N): " -n 1 -r
            echo ""

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Shutdown cancelled"
                return 1
            fi
        fi
    fi

    # ログ保存
    save_task_session_logs "$task_id"

    # セッション停止
    "$TASK_SESSION" kill "$task_id"

    # Worktreeクリーンアップ
    cleanup_worktrees "$task_id"

    log_success "Task session stopped: ${task_id}"
}

#
# 全タスクセッションの停止
#
stop_all_task_sessions() {
    local force="$1"

    log_info "Stopping all task sessions..."

    # アクティブなタスクセッションを検索
    local session_pattern="${TMUX_SESSION_PREFIX}-task-"
    local session_count=0
    local stopped_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^${session_pattern} ]]; then
            local session_name="${line%%:*}"
            local task_id="${session_name#${TMUX_SESSION_PREFIX}-task-}"

            session_count=$((session_count + 1))

            log_info "Found task session: ${task_id}"

            # タスクステータスのチェック（強制モードでない場合）
            if [[ "$force" == "false" ]]; then
                if ! check_task_status "$task_id"; then
                    log_warn "Skipping in-progress task: ${task_id}"
                    echo "  Use --force to stop anyway"
                    continue
                fi
            fi

            # ログ保存
            save_task_session_logs "$task_id"

            # セッション停止
            "$TASK_SESSION" kill "$task_id"

            # Worktreeクリーンアップ
            cleanup_worktrees "$task_id"

            stopped_count=$((stopped_count + 1))
        fi
    done < <(tmux list-sessions 2>/dev/null || true)

    if [[ $session_count -eq 0 ]]; then
        log_info "No task sessions found"
    else
        log_success "Stopped ${stopped_count} of ${session_count} task session(s)"

        if [[ $stopped_count -lt $session_count ]]; then
            log_warn "$((session_count - stopped_count)) session(s) skipped due to in-progress tasks"
        fi
    fi
}

#
# システムステータスの保存
#
save_system_status() {
    local stopped_tasks="$1"

    log_info "Saving system status..."

    local status_file="${LOG_DIR}/system/shutdown_status_$(date +%Y%m%d_%H%M%S).json"

    cat > "$status_file" <<EOF
{
  "shutdown_time": "$(timestamp)",
  "architecture_version": "v0.2.0",
  "stopped_tasks": "$stopped_tasks",
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
# Worktreeのクリーンアップ
#
cleanup_worktrees() {
    local task_id="$1"

    if [[ -z "${TARGET_PROJECT_PATH:-}" ]]; then
        log_debug "No target project configured, skipping worktree cleanup"
        return 0
    fi

    if [[ ! -d "${TARGET_PROJECT_PATH}" ]]; then
        log_warn "Target project not found: ${TARGET_PROJECT_PATH}"
        return 0
    fi

    log_info "Cleaning up worktrees for task: ${task_id}..."

    for role in eng1 eng2; do
        local worktree_path="${WORKTREE_BASE}/${role}"

        if [[ -d "$worktree_path" ]]; then
            log_info "Removing worktree: ${worktree_path}"

            local original_dir
            original_dir=$(pwd)
            cd "${TARGET_PROJECT_PATH}"

            if git worktree remove "$worktree_path" --force 2>/dev/null; then
                log_success "Worktree removed: ${worktree_path}"
            else
                log_warn "Failed to remove worktree: ${worktree_path}"
                log_info "You may need to manually remove it with: git worktree remove ${worktree_path}"
            fi

            cd "$original_dir"
        fi
    done
}

#
# 終了メッセージの表示
#
show_goodbye() {
    local task_id="${1:-all}"

    cat <<'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          Claude Orchestrator v0.2.0 Stopped                  ║
║                                                               ║
║  Task Session Architecture                                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    if [[ "$task_id" == "all" ]]; then
        log_info "All task sessions stopped"
    else
        log_info "Task session stopped: ${task_id}"
    fi

    echo ""
    log_info "Logs saved in: ${LOG_DIR}"
    log_info "To restart: ./scripts/start-system.sh [task-id]"
    echo ""
}

#
# メイン処理
#
main() {
    local task_id=""
    local force="false"
    local all_sessions="false"

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force="true"
                shift
                ;;
            --all|-a)
                all_sessions="true"
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [task-id] [options]

Arguments:
  task-id           タスクID（オプション）
                    指定しない場合は全タスクセッションを停止

Options:
  --all, -a         全タスクセッションを停止（明示的）
  --force, -f       進行中タスクも強制停止
  --help, -h        このヘルプメッセージを表示

Description:
  タスクセッション（v0.2.0）を停止します。
  セッション停止前にログを保存し、進行中タスクを確認します。

  v0.2.0では、タスクごとに1つのtmuxセッションを使用します。
  各セッション内でペインを分割して複数のロールを配置しています。

Examples:
  # 特定のタスクセッションを停止
  $0 task-001

  # 全タスクセッションを停止
  $0 --all

  # 進行中タスクも含めて強制停止
  $0 task-001 --force

  # 全タスクを強制停止
  $0 --all --force

Workflow:
  1. タスクステータスのチェック（--forceで省略可）
  2. セッションログの保存
  3. タスクセッション停止
  4. システムステータス保存
EOF
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                task_id="$1"
                shift
                ;;
        esac
    done

    # 初期化
    init_common
    init_logger

    log_info "=== Claude Orchestrator v0.2.0 System Shutdown ==="
    log_system "orchestrator" "INFO" "Starting shutdown sequence (v0.2.0 architecture)..."

    # 停止対象の決定
    if [[ "$all_sessions" == "true" ]] || [[ -z "$task_id" ]]; then
        # 全セッション停止
        stop_all_task_sessions "$force"
        stopped_tasks="all"
    else
        # 特定のタスクセッション停止
        if ! stop_task_session "$task_id" "$force"; then
            exit 1
        fi
        stopped_tasks="$task_id"
    fi

    # システムステータス保存
    save_system_status "$stopped_tasks"

    # 終了メッセージ
    show_goodbye "$stopped_tasks"

    log_system "orchestrator" "INFO" "System shutdown complete (task: ${stopped_tasks})"
    log_success "=== System shutdown complete ==="
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
