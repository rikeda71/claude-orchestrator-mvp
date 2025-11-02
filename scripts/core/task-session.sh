#!/usr/bin/env bash
#
# task-session.sh - タスクセッション管理
# タスクごとに1つのtmuxセッションを作成・管理
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

#
# タスクセッション名の生成
#
get_task_session_name() {
    local task_id="$1"
    echo "${TMUX_SESSION_PREFIX}-task-${task_id}"
}

#
# タスクセッションのウィンドウ名
#
get_task_window_name() {
    local task_id="$1"
    echo "${task_id}-orchestrator"
}

#
# ペインの作業ディレクトリ取得
#
get_pane_workdir() {
    local role="$1"

    case "$role" in
        pjm)
            echo "${ORCHESTRATOR_ROOT}/sessions/pjm"
            ;;
        eng1|eng2)
            # エンジニアはworktreeで作業
            echo "${WORKTREE_BASE}/${role}"
            ;;
        reviewer)
            echo "${ORCHESTRATOR_ROOT}/sessions/reviewer"
            ;;
        docs)
            echo "${ORCHESTRATOR_ROOT}/sessions/docs"
            ;;
        *)
            die "Unknown role: ${role}"
            ;;
    esac
}

#
# タスクセッションの作成
#
create_task_session() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")
    local window_name
    window_name=$(get_task_window_name "$task_id")

    log_info "Creating task session: ${session_name}"

    # セッションが既に存在する場合はエラー
    if tmux_session_exists "$session_name"; then
        log_error "Task session already exists: ${session_name}"
        return 1
    fi

    # セッション作成
    tmux new-session -d -s "$session_name" -n "$window_name"
    log_success "Task session created: ${session_name}"

    # PjMペイン（ペイン0）の設定
    setup_pjm_pane "$session_name" "$task_id"

    # eng1ペイン（ペイン1）の作成
    create_eng1_pane "$session_name" "$task_id"

    log_success "Task session setup complete: ${session_name}"
}

#
# PjMペインのセットアップ
#
setup_pjm_pane() {
    local session_name="$1"
    local task_id="$2"
    local pjm_workdir
    pjm_workdir=$(get_pane_workdir "pjm")

    log_debug "Setting up PjM pane..."

    # 作業ディレクトリへ移動
    tmux send-keys -t "${session_name}.0" "cd ${pjm_workdir}" C-m

    # 環境変数設定
    tmux send-keys -t "${session_name}.0" "export TASK_ID=${task_id}" C-m
    tmux send-keys -t "${session_name}.0" "export ORCHESTRATOR_ROOT=${ORCHESTRATOR_ROOT}" C-m

    # Claudeを起動（通常モード）
    log_debug "Starting Claude in PjM pane (normal mode)..."
    tmux send-keys -t "${session_name}.0" "claude" C-m

    # 少し待機
    sleep 1

    log_debug "PjM pane setup complete"
}

#
# eng1ペインの作成
#
create_eng1_pane() {
    local session_name="$1"
    local task_id="$2"
    local eng1_workdir
    eng1_workdir=$(get_pane_workdir "eng1")

    log_debug "Creating eng1 pane..."

    # 右側70%で垂直分割
    tmux split-window -h -t "$session_name" -p 70

    # eng1ワークツリーディレクトリの確認・作成
    if [[ ! -d "$eng1_workdir" ]]; then
        log_info "Creating eng1 worktree..."
        mkdir -p "$eng1_workdir"
        # TODO: git worktree addの実装（Phase 2以降）
    fi

    # 作業ディレクトリへ移動
    tmux send-keys -t "${session_name}.1" "cd ${eng1_workdir}" C-m

    # 環境変数設定
    tmux send-keys -t "${session_name}.1" "export TASK_ID=${task_id}" C-m
    tmux send-keys -t "${session_name}.1" "export ENGINEER_ROLE=eng1" C-m
    tmux send-keys -t "${session_name}.1" "export WORK_DIR=${eng1_workdir}" C-m
    tmux send-keys -t "${session_name}.1" "export PANE_ID=1" C-m

    # Claudeを自動実行モードで起動
    log_debug "Starting Claude in eng1 pane (auto-execution mode)..."
    tmux send-keys -t "${session_name}.1" "claude --dangerously-skip-permissions" C-m

    log_debug "eng1 pane created"
}

#
# タスクセッションの削除
#
kill_task_session() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    log_info "Killing task session: ${session_name}"

    if ! tmux_session_exists "$session_name"; then
        log_warn "Task session does not exist: ${session_name}"
        return 0
    fi

    # セッション削除
    tmux kill-session -t "$session_name"

    log_success "Task session killed: ${session_name}"
}

#
# タスクセッション一覧
#
list_task_sessions() {
    log_info "=== Task Sessions ==="

    local session_pattern="${TMUX_SESSION_PREFIX}-task-"
    local found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^${session_pattern} ]]; then
            found=true
            local session_name="${line%%:*}"
            local task_id="${session_name#${TMUX_SESSION_PREFIX}-task-}"

            # セッション情報表示
            printf "%-20s %s\n" "$task_id" "$session_name"
        fi
    done < <(tmux list-sessions 2>/dev/null || true)

    if [[ "$found" == "false" ]]; then
        log_info "No task sessions found"
    fi
}

#
# タスクセッションにアタッチ
#
attach_task_session() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        log_info "Available sessions:"
        list_task_sessions
        return 1
    fi

    log_info "Attaching to task session: ${session_name}"
    tmux attach-session -t "$session_name"
}

#
# タスクセッションの存在確認
#
task_session_exists() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    tmux_session_exists "$session_name"
}

#
# タスクセッションのステータス表示
#
task_session_status() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_info "=== Task Session Status: ${task_id} ==="
    echo ""
    echo "Session: ${session_name}"
    echo ""

    # ペイン情報を表示
    log_info "Panes:"
    tmux list-panes -t "$session_name" \
        -F "  Pane #{pane_index}: #{pane_width}x#{pane_height} - #{pane_current_command}"
}

#
# 全タスクセッションの削除
#
kill_all_task_sessions() {
    log_info "Killing all task sessions..."

    local session_pattern="${TMUX_SESSION_PREFIX}-task-"
    local count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^${session_pattern} ]]; then
            local session_name="${line%%:*}"
            log_info "Killing: ${session_name}"
            tmux kill-session -t "$session_name" 2>/dev/null || true
            count=$((count + 1))
        fi
    done < <(tmux list-sessions 2>/dev/null || true)

    if [[ $count -eq 0 ]]; then
        log_info "No task sessions to kill"
    else
        log_success "Killed ${count} task session(s)"
    fi
}

#
# メイン処理
#
main() {
    init_common
    init_logger

    local command="${1:-}"

    case "$command" in
        create)
            local task_id="${2:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 create <task-id>"
                exit 1
            fi
            create_task_session "$task_id"
            ;;
        kill)
            local task_id="${2:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 kill <task-id>"
                exit 1
            fi
            kill_task_session "$task_id"
            ;;
        list)
            list_task_sessions
            ;;
        attach)
            local task_id="${2:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 attach <task-id>"
                exit 1
            fi
            attach_task_session "$task_id"
            ;;
        status)
            local task_id="${2:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 status <task-id>"
                exit 1
            fi
            task_session_status "$task_id"
            ;;
        exists)
            local task_id="${2:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                exit 1
            fi
            if task_session_exists "$task_id"; then
                echo "exists"
                exit 0
            else
                echo "not_exists"
                exit 1
            fi
            ;;
        kill-all)
            kill_all_task_sessions
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args]

Commands:
  create <task-id>
      タスクセッションを作成
      - PjMペイン + eng1ペインを作成
      - 各ペインでClaudeを起動

  kill <task-id>
      タスクセッションを削除

  list
      全タスクセッションを一覧表示

  attach <task-id>
      タスクセッションにアタッチ

  status <task-id>
      タスクセッションのステータスを表示

  exists <task-id>
      タスクセッションの存在確認

  kill-all
      全タスクセッションを削除

Examples:
  # タスクセッション作成
  $0 create task-001

  # タスクセッションにアタッチ
  $0 attach task-001

  # タスクセッション削除
  $0 kill task-001

  # 全セッション一覧
  $0 list
EOF
            exit 0
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
