#!/usr/bin/env bash
#
# session-manager.sh - tmuxセッション管理システム
# Claude Codeセッションの作成、制御、監視を提供
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

# セッションロール定義
ROLE_PJM="pjm"
ROLE_ENG1="eng1"
ROLE_ENG2="eng2"
ROLE_REVIEWER="reviewer"
ROLE_DOCS="docs"

#
# セッション名の生成
#
get_session_name() {
    local role="$1"
    echo "${TMUX_SESSION_PREFIX}-${role}"
}

#
# セッションの作業ディレクトリを取得
#
get_session_workdir() {
    local role="$1"

    case "$role" in
        pjm|reviewer|docs)
            echo "${ORCHESTRATOR_ROOT}/sessions/${role}"
            ;;
        eng1|eng2)
            echo "${WORKTREE_BASE}/${role}"
            ;;
        *)
            die "Invalid role: ${role}"
            ;;
    esac
}

#
# セッション初期プロンプトファイルのパスを取得
#
get_init_prompt_file() {
    local role="$1"
    echo "${ORCHESTRATOR_ROOT}/sessions/${role}/init-prompt.txt"
}

#
# セッションの作成
#
create_session() {
    local role="$1"

    # ロールの検証
    case "$role" in
        pjm|eng1|eng2|reviewer|docs) ;;
        *) die "Invalid role: ${role}. Use: pjm, eng1, eng2, reviewer, docs" ;;
    esac

    local session_name
    session_name=$(get_session_name "$role")

    # 既存セッションのチェック
    if tmux_session_exists "$session_name"; then
        log_warn "Session already exists: ${session_name}"
        return 0
    fi

    # 作業ディレクトリの取得と作成
    local workdir
    workdir=$(get_session_workdir "$role")
    ensure_dir "$workdir"

    # セッションの作成
    log_info "Creating session: ${session_name} (${role})"

    # tmuxセッションの作成（デタッチモード）
    tmux new-session -d -s "$session_name" -c "$workdir"

    # セッションのペイン設定
    tmux send-keys -t "$session_name" "cd ${workdir}" C-m

    # セッションロギングの開始
    log_session "$role" "INFO" "Session created: ${session_name}"

    log_success "Session created: ${session_name}"

    echo "$session_name"
}

#
# セッションの削除
#
kill_session() {
    local role="$1"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        log_warn "Session does not exist: ${session_name}"
        return 0
    fi

    log_info "Killing session: ${session_name}"

    # セッションの終了
    tmux kill-session -t "$session_name"

    log_session "$role" "INFO" "Session killed: ${session_name}"
    log_success "Session killed: ${session_name}"
}

#
# セッション一覧の表示
#
list_sessions() {
    log_info "=== Claude Orchestrator Sessions ==="

    local found=0
    for role in pjm eng1 eng2 reviewer docs; do
        local session_name
        session_name=$(get_session_name "$role")

        if tmux_session_exists "$session_name"; then
            found=1
            local attached="No"
            if tmux list-sessions | grep -q "^${session_name}:.*attached"; then
                attached="Yes"
            fi

            printf "%-15s %-20s %-10s\n" "$role" "$session_name" "Attached: $attached"
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_info "No sessions found"
    fi
}

#
# セッションにアタッチ
#
attach_session() {
    local role="$1"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        die "Session does not exist: ${session_name}"
    fi

    log_info "Attaching to session: ${session_name}"

    # セッションにアタッチ（インタラクティブ）
    tmux attach-session -t "$session_name"
}

#
# セッションにコマンドを送信
#
send_command() {
    local role="$1"
    shift
    local command="$*"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        die "Session does not exist: ${session_name}"
    fi

    log_info "Sending command to ${session_name}: ${command}"

    # コマンドの送信
    tmux send-keys -t "$session_name" "$command" C-m

    log_session "$role" "INFO" "Command sent: ${command}"
}

#
# セッションからの出力キャプチャ
#
capture_session() {
    local role="$1"
    local lines="${2:-100}"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        die "Session does not exist: ${session_name}"
    fi

    # ペインの内容をキャプチャ
    tmux capture-pane -t "$session_name" -p -S "-${lines}"
}

#
# Claude Codeの起動
#
start_claude() {
    local role="$1"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        die "Session does not exist: ${session_name}"
    fi

    log_info "Starting Claude Code in session: ${session_name}"

    # Claude Codeの起動
    send_command "$role" "claude"

    # 少し待機
    sleep 2

    log_session "$role" "INFO" "Claude Code started"
}

#
# 初期プロンプトの送信
#
send_init_prompt() {
    local role="$1"

    local prompt_file
    prompt_file=$(get_init_prompt_file "$role")

    if [[ ! -f "$prompt_file" ]]; then
        log_warn "Init prompt file not found: ${prompt_file}"
        return 1
    fi

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        die "Session does not exist: ${session_name}"
    fi

    log_info "Sending init prompt to session: ${session_name}"

    # プロンプトファイルの内容を読み込み
    local prompt_content
    prompt_content=$(<"$prompt_file")

    # プロンプトの送信（複数行対応）
    # tmuxのsend-keysは改行を含む長いテキストの送信が難しいため、
    # ファイルから1行ずつ送信する
    while IFS= read -r line; do
        tmux send-keys -t "$session_name" -l "$line"
        tmux send-keys -t "$session_name" C-m
        sleep 0.1
    done < "$prompt_file"

    log_session "$role" "INFO" "Init prompt sent"
}

#
# セッションのヘルスチェック
#
check_session_health() {
    local role="$1"

    local session_name
    session_name=$(get_session_name "$role")

    if ! tmux_session_exists "$session_name"; then
        echo "NOT_RUNNING"
        return 1
    fi

    # セッションが応答しているか確認
    # ここでは単にセッションが存在するかをチェック
    # より詳細なヘルスチェックは今後実装

    echo "HEALTHY"
    return 0
}

#
# すべてのセッションのヘルスチェック
#
check_all_sessions() {
    log_info "=== Session Health Check ==="

    for role in pjm eng1; do
        local session_name
        session_name=$(get_session_name "$role")

        local status
        status=$(check_session_health "$role")

        printf "%-15s %-20s %-10s\n" "$role" "$session_name" "$status"
    done
}

#
# セッションの再起動
#
restart_session() {
    local role="$1"

    log_info "Restarting session: ${role}"

    # 既存セッションを終了
    kill_session "$role" 2>/dev/null || true

    # 少し待機
    sleep 1

    # 新しいセッションを作成
    create_session "$role"
}

#
# セッションのログ表示
#
show_session_log() {
    local role="$1"
    local lines="${2:-50}"

    show_log "session" "$role" "$lines"
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
            shift
            create_session "$@"
            ;;
        kill)
            shift
            kill_session "$@"
            ;;
        list)
            list_sessions
            ;;
        attach)
            shift
            attach_session "$@"
            ;;
        send)
            shift
            send_command "$@"
            ;;
        capture)
            shift
            capture_session "$@"
            ;;
        start-claude)
            shift
            start_claude "$@"
            ;;
        init-prompt)
            shift
            send_init_prompt "$@"
            ;;
        health)
            shift
            if [[ $# -eq 0 ]]; then
                check_all_sessions
            else
                check_session_health "$@"
            fi
            ;;
        restart)
            shift
            restart_session "$@"
            ;;
        log)
            shift
            show_session_log "$@"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  create <role>
      Create a new tmux session for the specified role
      Roles: pjm, eng1, eng2, reviewer, docs

  kill <role>
      Kill the specified session

  list
      List all orchestrator sessions

  attach <role>
      Attach to the specified session

  send <role> <command>
      Send a command to the specified session

  capture <role> [lines]
      Capture output from session (default: 100 lines)

  start-claude <role>
      Start Claude Code in the specified session

  init-prompt <role>
      Send initial prompt to the specified session

  health [role]
      Check health of session(s)

  restart <role>
      Restart the specified session

  log <role> [lines]
      Show session log (default: 50 lines)

Examples:
  $0 create pjm
  $0 list
  $0 send pjm "task list"
  $0 attach pjm
  $0 health
  $0 restart eng1
EOF
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
