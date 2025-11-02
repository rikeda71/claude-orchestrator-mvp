#!/usr/bin/env bash
#
# messenger.sh - セッション間通信システム
# 名前付きパイプとファイルベースのメッセージング機能を提供
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

# メッセージディレクトリ
MESSAGE_DIR="${ORCHESTRATOR_ROOT}/communication/buffers"

#
# パイプのパスを取得
#
get_pipe_path() {
    local from="$1"
    local to="$2"
    echo "${PIPE_DIR}/${from}-to-${to}"
}

#
# すべてのパイプを作成
#
create_all_pipes() {
    log_info "Creating communication pipes..."

    ensure_dir "$PIPE_DIR"

    # Phase 1: PjM <-> eng1 のみ
    create_pipe "$(get_pipe_path pjm eng1)"
    create_pipe "$(get_pipe_path eng1 pjm)"

    log_success "Communication pipes created"
}

#
# すべてのパイプを削除
#
remove_all_pipes() {
    log_info "Removing communication pipes..."

    for pipe in "${PIPE_DIR}"/*; do
        if [[ -p "$pipe" ]]; then
            rm -f "$pipe"
            log_debug "Removed pipe: ${pipe}"
        fi
    done

    log_success "Communication pipes removed"
}

#
# メッセージファイルのパスを取得
#
get_message_file() {
    local to="$1"
    local timestamp="$2"
    echo "${MESSAGE_DIR}/${to}-${timestamp}.msg"
}

#
# メッセージの送信（ファイルベース）
#
send_message_file() {
    local from="$1"
    local to="$2"
    local message="$3"

    ensure_dir "$MESSAGE_DIR"

    local timestamp
    timestamp=$(date +%s)
    local message_file
    message_file=$(get_message_file "$to" "$timestamp")

    # メッセージファイルの作成（JSON形式）
    cat > "$message_file" <<EOF
{
  "from": "${from}",
  "to": "${to}",
  "timestamp": "$(timestamp)",
  "message": "${message}"
}
EOF

    log_info "Message sent: ${from} -> ${to}"
    log_session "$from" "INFO" "Sent message to ${to}: ${message}"
    log_session "$to" "INFO" "Received message from ${from}: ${message}"

    echo "$message_file"
}

#
# メッセージの読み取り（ファイルベース）
#
read_messages() {
    local recipient="$1"
    local mark_read="${2:-true}"

    if [[ ! -d "$MESSAGE_DIR" ]]; then
        log_warn "Message directory not found"
        return 1
    fi

    local found=0

    # 受信者宛のメッセージファイルを検索
    for message_file in "${MESSAGE_DIR}/${recipient}"-*.msg; do
        [[ -f "$message_file" ]] || continue
        found=1

        # メッセージの表示
        local from
        from=$(json_get "$message_file" '.from')
        local message
        message=$(json_get "$message_file" '.message')
        local msg_timestamp
        msg_timestamp=$(json_get "$message_file" '.timestamp')

        echo "[$msg_timestamp] From: $from"
        echo "  Message: $message"
        echo ""

        # 既読にする場合はファイルを削除
        if [[ "$mark_read" == "true" ]]; then
            rm -f "$message_file"
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_info "No messages for ${recipient}"
    fi

    return 0
}

#
# メッセージをセッションに送信
#
send_to_session() {
    local from="$1"
    local to="$2"
    local message="$3"

    # セッションの存在確認
    local to_session
    to_session=$(get_session_name "$to")

    if ! tmux_session_exists "$to_session"; then
        log_error "Target session does not exist: ${to_session}"
        return 1
    fi

    # ファイルベースのメッセージ送信
    send_message_file "$from" "$to" "$message"

    return 0
}

#
# ブロードキャストメッセージ（全セッションに送信）
#
broadcast_message() {
    local from="$1"
    local message="$2"

    log_info "Broadcasting message from ${from}..."

    for role in pjm eng1 eng2 reviewer docs; do
        # 自分自身には送信しない
        if [[ "$role" == "$from" ]]; then
            continue
        fi

        # セッションが存在する場合のみ送信
        local session_name
        session_name=$(get_session_name "$role")
        if tmux_session_exists "$session_name"; then
            send_message_file "$from" "$role" "$message"
        fi
    done

    log_success "Broadcast complete"
}

#
# メッセージキューのクリーンアップ
#
cleanup_messages() {
    local older_than_minutes="${1:-60}"

    log_info "Cleaning up messages older than ${older_than_minutes} minutes..."

    if [[ ! -d "$MESSAGE_DIR" ]]; then
        return 0
    fi

    local count=0
    # 指定時間より古いメッセージファイルを削除
    find "$MESSAGE_DIR" -name "*.msg" -type f -mmin "+${older_than_minutes}" | while read -r file; do
        rm -f "$file"
        count=$((count + 1))
    done

    log_success "Cleaned up old messages"
}

#
# メッセージ統計
#
message_stats() {
    log_info "=== Message Statistics ==="

    if [[ ! -d "$MESSAGE_DIR" ]]; then
        log_info "No messages"
        return 0
    fi

    for role in pjm eng1 eng2 reviewer docs; do
        local count
        count=$(find "$MESSAGE_DIR" -name "${role}-*.msg" -type f 2>/dev/null | wc -l | tr -d ' ')

        if [[ $count -gt 0 ]]; then
            printf "%-15s %d unread message(s)\n" "$role" "$count"
        fi
    done
}

#
# メイン処理
#
main() {
    init_common
    init_logger

    local command="${1:-}"

    case "$command" in
        init-pipes)
            create_all_pipes
            ;;
        cleanup-pipes)
            remove_all_pipes
            ;;
        send)
            shift
            if [[ $# -lt 3 ]]; then
                die "Usage: send <from> <to> <message>"
            fi
            send_to_session "$@"
            ;;
        read)
            shift
            if [[ $# -lt 1 ]]; then
                die "Usage: read <recipient> [mark_read]"
            fi
            read_messages "$@"
            ;;
        broadcast)
            shift
            if [[ $# -lt 2 ]]; then
                die "Usage: broadcast <from> <message>"
            fi
            broadcast_message "$@"
            ;;
        cleanup)
            shift
            cleanup_messages "${1:-60}"
            ;;
        stats)
            message_stats
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  init-pipes
      Create all communication pipes

  cleanup-pipes
      Remove all communication pipes

  send <from> <to> <message>
      Send a message from one session to another

  read <recipient> [mark_read]
      Read messages for recipient (mark_read: true/false, default: true)

  broadcast <from> <message>
      Broadcast message to all sessions

  cleanup [minutes]
      Clean up messages older than N minutes (default: 60)

  stats
      Show message statistics

Examples:
  $0 init-pipes
  $0 send pjm eng1 "Start working on task-001"
  $0 read eng1
  $0 broadcast pjm "System maintenance in 5 minutes"
  $0 stats
EOF
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
