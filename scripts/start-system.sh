#!/usr/bin/env bash
#
# start-system.sh - システム起動スクリプト (v0.2.0)
# タスクセッションを起動
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
    ensure_dir "$LOG_DIR"
    ensure_dir "${LOG_DIR}/sessions"
    ensure_dir "${LOG_DIR}/system"
    ensure_dir "${LOG_DIR}/tasks"
    ensure_dir "$TASK_DIR/queue"
    ensure_dir "$TASK_DIR/in-progress"
    ensure_dir "$TASK_DIR/completed"
    ensure_dir "$TASK_DIR/reviews"
    ensure_dir "$WORKTREE_BASE"

    # セッションディレクトリの作成
    for role in pjm eng1 eng2 reviewer docs; do
        ensure_dir "${ORCHESTRATOR_ROOT}/sessions/${role}"
    done

    # エンジニア用ワークツリーディレクトリ
    # Note: eng1/eng2ディレクトリはgit worktree addで自動作成されるため、ここでは作成しない
    # ensure_dir "${WORKTREE_BASE}/eng1"
    # ensure_dir "${WORKTREE_BASE}/eng2"

    log_success "Directory structure initialized"
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
# タスクの存在確認とタスクIDの取得
#
get_or_create_task() {
    local task_id="${1:-}"

    if [[ -n "$task_id" ]]; then
        # タスクIDが指定された場合、存在確認
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
            log_error "Task not found: ${task_id}"
            log_info "Available tasks:"
            "$TASK_MANAGER" list
            return 1
        fi

        echo "$task_id"
    else
        # タスクIDが指定されない場合、デフォルトタスクを作成
        log_info "No task ID specified, creating default task..."

        local new_task_id
        new_task_id=$("$TASK_MANAGER" create feature "Default orchestrator task" eng1 system | grep -o 'task-[^[:space:]]*')

        log_success "Created default task: ${new_task_id}"
        echo "$new_task_id"
    fi
}

#
# タスクセッションの起動
#
start_task_session() {
    local task_id="$1"
    local user_instruction="$2"

    log_info "Starting task session for: ${task_id}"

    # タスクセッションが既に存在する場合はエラー
    if "$TASK_SESSION" exists "$task_id" 2>/dev/null; then
        log_error "Task session already running: ${task_id}"
        log_info "Attach to existing session with:"
        echo "  tmux attach -t ${TMUX_SESSION_PREFIX}-task-${task_id}"
        echo "Or:"
        echo "  ${TASK_SESSION} attach ${task_id}"
        return 1
    fi

    # タスクセッション作成（指示を渡す）
    "$TASK_SESSION" create "$task_id" "$user_instruction"

    log_success "Task session started: ${task_id}"
}

#
# OSとターミナルの検出
#
detect_terminal() {
    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Darwin)
            # macOS
            if [[ -n "${ITERM_SESSION_ID:-}" ]]; then
                echo "iterm"
            elif [[ -n "${TERM_PROGRAM:-}" ]] && [[ "${TERM_PROGRAM}" == "Apple_Terminal" ]]; then
                echo "terminal"
            else
                # デフォルトはTerminal.app
                echo "terminal"
            fi
            ;;
        Linux)
            # Linuxの場合、利用可能なターミナルを検索
            if command -v gnome-terminal &> /dev/null; then
                echo "gnome-terminal"
            elif command -v konsole &> /dev/null; then
                echo "konsole"
            elif command -v xterm &> /dev/null; then
                echo "xterm"
            else
                echo "unknown"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

#
# 新しいターミナルウィンドウで起動（macOS Terminal.app）
#
open_in_terminal_app() {
    local session_name="$1"

    log_info "Terminal.appで新しいウィンドウを開きます..."

    # AppleScriptを使用して新しいウィンドウで最大サイズで実行
    osascript <<EOF
tell application "Terminal"
    set newWindow to do script "tmux attach-session -t ${session_name}"
    activate

    -- 画面の境界を取得
    tell application "Finder"
        set screenBounds to bounds of window of desktop
    end tell

    -- ウィンドウを最大サイズに設定（少し余白を残す）
    set bounds of window 1 to {0, 22, item 3 of screenBounds, item 4 of screenBounds}
end tell
EOF

    log_success "タスクセッションウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（macOS iTerm2）
#
open_in_iterm() {
    local session_name="$1"

    log_info "iTerm2で新しいウィンドウを開きます..."

    # AppleScriptを使用して最大サイズで開く
    osascript <<EOF
tell application "iTerm"
    create window with default profile
    tell current session of current window
        write text "tmux attach-session -t ${session_name}"
    end tell
    activate

    -- 画面の境界を取得
    tell application "Finder"
        set screenBounds to bounds of window of desktop
    end tell

    -- ウィンドウを最大サイズに設定（少し余白を残す）
    set bounds of current window to {0, 22, item 3 of screenBounds, item 4 of screenBounds}
end tell
EOF

    log_success "タスクセッションウィンドウを開きました（iTerm2）"
}

#
# 新しいターミナルウィンドウで起動（Linux gnome-terminal）
#
open_in_gnome_terminal() {
    local session_name="$1"

    log_info "gnome-terminalで新しいウィンドウを開きます..."

    gnome-terminal -- bash -c "tmux attach-session -t ${session_name}"

    log_success "タスクセッションウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（Linux konsole）
#
open_in_konsole() {
    local session_name="$1"

    log_info "konsoleで新しいウィンドウを開きます..."

    konsole -e bash -c "tmux attach-session -t ${session_name}"

    log_success "タスクセッションウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（Linux xterm）
#
open_in_xterm() {
    local session_name="$1"

    log_info "xtermで新しいウィンドウを開きます..."

    xterm -e "tmux attach-session -t ${session_name}" &

    log_success "タスクセッションウィンドウを開きました"
}

#
# ウェルカムメッセージの表示
#
show_welcome() {
    local task_id="$1"

    cat <<'EOF'

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          Claude Orchestrator v0.2.0 Started                  ║
║                                                               ║
║  Task-Based Session Architecture                             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    log_info "System is ready!"
    echo ""
    log_info "Task Session: ${task_id}"
    echo ""
    log_info "Available Commands:"
    echo "  - Attach to session:    tmux attach -t ${TMUX_SESSION_PREFIX}-task-${task_id}"
    echo "  - Or use shortcut:      ${TASK_SESSION} attach ${task_id}"
    echo "  - View task details:    ${TASK_MANAGER} show ${task_id}"
    echo "  - List panes:           ${SCRIPT_DIR}/core/pane-manager.sh list ${task_id}"
    echo "  - Stop session:         ${SCRIPT_DIR}/stop-system.sh ${task_id}"
    echo ""
    log_info "Pane Layout:"
    echo "  - Pane 0 (left 30%):  PjM (Project Manager)"
    echo "  - Pane 1 (right 70%): eng1 (Engineer 1)"
    echo ""
    log_info "System logs: ${LOG_DIR}"
    echo ""
}

#
# メイン処理
#
main() {
    local task_id=""
    local auto_attach="true"
    local user_instruction=""

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-attach)
                auto_attach="false"
                shift
                ;;
            --instruction|-i)
                user_instruction="$2"
                shift 2
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [task-id] [options]

Arguments:
  task-id           タスクID（オプション）
                    指定しない場合はデフォルトタスクを作成

Options:
  --no-attach           セッションに自動アタッチしない
  --instruction, -i     PjMへの初期指示（必須）
  --help, -h            このヘルプメッセージを表示

Description:
  タスクごとに1つのtmuxセッションを起動します。
  セッション内でペインを分割し、各ロールを配置：
  - Pane 0: PjM (プロジェクトマネージャー)
  - Pane 1: eng1 (エンジニア1、自動実行モード)

  PjMペインからeng1ペインに指示を送ることで、
  自動的にタスクが進行します。

Examples:
  # デフォルトタスクで起動
  $0 --instruction "Implement user authentication"

  # 既存のタスクで起動
  $0 task-001 --instruction "Fix login bug"

  # タスク作成後、そのタスクで起動
  ./scripts/core/task-manager.sh create feature "ユーザー認証実装"
  $0 task-001 -i "Implement JWT-based authentication"

Workflow:
  1. タスクを作成（または既存タスクを指定）
  2. start-system.shでタスクセッション起動（自動的にアタッチ）
  3. PjMペインでタスクを確認
  4. PjMからeng1に指示を送信
  5. eng1が自動実行
  6. 完了後、Ctrl+B → D でデタッチ
  7. stop-system.shでセッション終了
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

    log_info "=== Claude Orchestrator v0.2.0 System Startup ==="
    log_system "orchestrator" "INFO" "Starting system (v0.2.0 architecture)..."

    # 起動シーケンス
    check_prerequisites
    init_directories
    start_logging

    # タスクIDの取得または作成
    task_id=$(get_or_create_task "$task_id")

    if [[ -z "$task_id" ]]; then
        log_error "Failed to get or create task"
        exit 1
    fi

    # 指示が必須
    if [[ -z "$user_instruction" ]]; then
        log_error "Initial instruction is required"
        log_info "Usage: $0 [task-id] --instruction \"Your instruction here\""
        exit 1
    fi

    # タスクセッション起動
    start_task_session "$task_id" "$user_instruction"

    # ウェルカムメッセージ
    show_welcome "$task_id"

    log_system "orchestrator" "INFO" "System startup complete (task: ${task_id})"
    log_success "=== System startup complete ==="

    # 自動アタッチ（新しいターミナルウィンドウで）
    if [[ "$auto_attach" == "true" ]]; then
        local session_name="${TMUX_SESSION_PREFIX}-task-${task_id}"

        # ターミナルタイプの検出
        local terminal_type
        terminal_type=$(detect_terminal)

        log_info "検出されたターミナル: ${terminal_type}"
        echo ""

        case "$terminal_type" in
            terminal)
                open_in_terminal_app "$session_name" &
                ;;
            iterm)
                open_in_iterm "$session_name" &
                ;;
            gnome-terminal)
                open_in_gnome_terminal "$session_name" &
                ;;
            konsole)
                open_in_konsole "$session_name" &
                ;;
            xterm)
                open_in_xterm "$session_name"
                ;;
            unknown)
                log_warn "サポートされているターミナルが見つかりません"
                log_info "手動で以下のコマンドを実行してください:"
                echo ""
                echo "  tmux attach -t ${session_name}"
                echo ""
                ;;
        esac

    else
        echo ""
        log_info "To attach manually: tmux attach -t ${TMUX_SESSION_PREFIX}-task-${task_id}"
        echo ""
    fi
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
