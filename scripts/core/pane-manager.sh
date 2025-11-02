#!/usr/bin/env bash
#
# pane-manager.sh - ペイン管理
# タスクセッション内のペイン操作と通信管理
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

# task-session.shの関数を使用
# shellcheck source=./task-session.sh
source "${SCRIPT_DIR}/task-session.sh"

#
# ペインにメッセージを送信
#
send_to_pane() {
    local task_id="$1"
    local pane_id="$2"
    local message="$3"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_debug "Sending message to pane ${pane_id}: ${message}"

    # メッセージをClaude Codeのプロンプトに入力
    tmux send-keys -t "${session_name}.${pane_id}" "$message"

    # 少し待機してからEnterキーを送信
    sleep 0.5
    tmux send-keys -t "${session_name}.${pane_id}" C-m

    log_success "Message sent to pane ${pane_id}"
}

#
# ペインの出力をキャプチャ
#
capture_pane() {
    local task_id="$1"
    local pane_id="$2"
    local lines="${3:-100}"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_debug "Capturing ${lines} lines from pane ${pane_id}..."

    # ペイン出力のキャプチャ
    tmux capture-pane -t "${session_name}.${pane_id}" -p -S -"$lines"
}

#
# ペイン追加（Phase 2以降用）
#
add_pane() {
    local task_id="$1"
    local role="$2"  # eng2, reviewer, docs
    local pane_id="$3"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_info "Adding ${role} pane..."

    # 作業ディレクトリ取得
    local workdir
    workdir=$(get_pane_workdir "$role")

    # ワークツリーディレクトリの確認・作成
    if [[ ! -d "$workdir" ]]; then
        log_info "Creating ${role} worktree..."
        mkdir -p "$workdir"
        # TODO: git worktree addの実装（Phase 2以降）
    fi

    # ペイン追加（水平分割）
    tmux split-window -v -t "${session_name}.1"

    # 作業ディレクトリへ移動
    tmux send-keys -t "${session_name}.${pane_id}" "cd ${workdir}" C-m

    # 環境変数設定
    tmux send-keys -t "${session_name}.${pane_id}" "export TASK_ID=${task_id}" C-m
    tmux send-keys -t "${session_name}.${pane_id}" "export ENGINEER_ROLE=${role}" C-m
    tmux send-keys -t "${session_name}.${pane_id}" "export WORK_DIR=${workdir}" C-m
    tmux send-keys -t "${session_name}.${pane_id}" "export PANE_ID=${pane_id}" C-m

    # Claudeを自動実行モードで起動
    log_debug "Starting Claude in ${role} pane (auto-execution mode)..."
    tmux send-keys -t "${session_name}.${pane_id}" "claude --dangerously-skip-permissions" C-m

    log_success "${role} pane added"
}

#
# ペインリスト表示
#
list_panes() {
    local task_id="$1"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_info "=== Panes in ${session_name} ==="

    tmux list-panes -t "$session_name" \
        -F "Pane #{pane_index}: #{pane_width}x#{pane_height} - #{pane_current_command}"
}

#
# ペインのクリア
#
clear_pane() {
    local task_id="$1"
    local pane_id="$2"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_info "Clearing pane ${pane_id}..."

    tmux send-keys -t "${session_name}.${pane_id}" "clear" C-m

    log_success "Pane ${pane_id} cleared"
}

#
# ペインの選択（フォーカス）
#
select_pane() {
    local task_id="$1"
    local pane_id="$2"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_debug "Selecting pane ${pane_id}..."

    tmux select-pane -t "${session_name}.${pane_id}"
}

#
# ペインのサイズ変更
#
resize_pane() {
    local task_id="$1"
    local pane_id="$2"
    local direction="$3"  # U, D, L, R
    local amount="${4:-5}"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_debug "Resizing pane ${pane_id} ${direction} by ${amount}..."

    tmux resize-pane -t "${session_name}.${pane_id}" -"$direction" "$amount"
}

#
# PjMペインから全ペインへブロードキャスト
#
broadcast_from_pjm() {
    local task_id="$1"
    local message="$2"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    log_info "Broadcasting message from PjM to all panes..."

    # 全ペインを取得
    local pane_count
    pane_count=$(tmux list-panes -t "$session_name" | wc -l | tr -d ' ')

    # ペイン0（PjM）以外の全ペインに送信
    for ((i=1; i<pane_count; i++)); do
        log_debug "Sending to pane ${i}..."
        tmux send-keys -t "${session_name}.${i}" "$message" C-m
    done

    log_success "Broadcast complete to $((pane_count - 1)) pane(s)"
}

#
# メイン処理
#
main() {
    init_common
    init_logger

    local command="${1:-}"

    case "$command" in
        send)
            local task_id="${2:-}"
            local pane_id="${3:-}"
            local message="${4:-}"

            if [[ -z "$task_id" ]] || [[ -z "$pane_id" ]] || [[ -z "$message" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 send <task-id> <pane-id> <message>"
                exit 1
            fi

            send_to_pane "$task_id" "$pane_id" "$message"
            ;;
        capture)
            local task_id="${2:-}"
            local pane_id="${3:-}"
            local lines="${4:-100}"

            if [[ -z "$task_id" ]] || [[ -z "$pane_id" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 capture <task-id> <pane-id> [lines]"
                exit 1
            fi

            capture_pane "$task_id" "$pane_id" "$lines"
            ;;
        add)
            local task_id="${2:-}"
            local role="${3:-}"
            local pane_id="${4:-}"

            if [[ -z "$task_id" ]] || [[ -z "$role" ]] || [[ -z "$pane_id" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 add <task-id> <role> <pane-id>"
                exit 1
            fi

            add_pane "$task_id" "$role" "$pane_id"
            ;;
        list)
            local task_id="${2:-}"

            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 list <task-id>"
                exit 1
            fi

            list_panes "$task_id"
            ;;
        clear)
            local task_id="${2:-}"
            local pane_id="${3:-}"

            if [[ -z "$task_id" ]] || [[ -z "$pane_id" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 clear <task-id> <pane-id>"
                exit 1
            fi

            clear_pane "$task_id" "$pane_id"
            ;;
        select)
            local task_id="${2:-}"
            local pane_id="${3:-}"

            if [[ -z "$task_id" ]] || [[ -z "$pane_id" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 select <task-id> <pane-id>"
                exit 1
            fi

            select_pane "$task_id" "$pane_id"
            ;;
        resize)
            local task_id="${2:-}"
            local pane_id="${3:-}"
            local direction="${4:-}"
            local amount="${5:-5}"

            if [[ -z "$task_id" ]] || [[ -z "$pane_id" ]] || [[ -z "$direction" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 resize <task-id> <pane-id> <U|D|L|R> [amount]"
                exit 1
            fi

            resize_pane "$task_id" "$pane_id" "$direction" "$amount"
            ;;
        broadcast)
            local task_id="${2:-}"
            local message="${3:-}"

            if [[ -z "$task_id" ]] || [[ -z "$message" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 broadcast <task-id> <message>"
                exit 1
            fi

            broadcast_from_pjm "$task_id" "$message"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args]

Commands:
  send <task-id> <pane-id> <message>
      ペインにメッセージを送信
      例: $0 send task-001 1 "実装を開始してください"

  capture <task-id> <pane-id> [lines]
      ペインの出力をキャプチャ（デフォルト100行）
      例: $0 capture task-001 1 200

  add <task-id> <role> <pane-id>
      新しいペインを追加（Phase 2以降）
      例: $0 add task-001 eng2 2

  list <task-id>
      全ペインをリスト表示
      例: $0 list task-001

  clear <task-id> <pane-id>
      ペインをクリア
      例: $0 clear task-001 1

  select <task-id> <pane-id>
      ペインを選択（フォーカス）
      例: $0 select task-001 1

  resize <task-id> <pane-id> <U|D|L|R> [amount]
      ペインのサイズ変更
      例: $0 resize task-001 0 R 10

  broadcast <task-id> <message>
      PjM以外の全ペインにブロードキャスト
      例: $0 broadcast task-001 "作業を一時停止してください"

Pane IDs:
  0: PjM
  1: eng1
  2: eng2 (Phase 2以降)
  3: reviewer (Phase 3以降)
  4: docs (Phase 4以降)

Examples:
  # PjMからeng1に指示送信
  $0 send task-001 1 "ユーザー認証機能を実装してください"

  # eng1の出力をキャプチャ
  $0 capture task-001 1 50

  # eng2ペインを追加（Phase 2）
  $0 add task-001 eng2 2

  # 全ペインに一斉通知
  $0 broadcast task-001 "ミーティングのため15分中断します"
EOF
            exit 0
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
