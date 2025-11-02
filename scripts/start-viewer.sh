#!/usr/bin/env bash
#
# start-viewer.sh - 統合ビューア起動スクリプト
# 新しいターミナルウィンドウで統合ビューアを起動
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
VIEWER_SCRIPT="${SCRIPT_DIR}/core/viewer.sh"

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
    local viewer_cmd="$1"

    log_info "Terminal.appで新しいウィンドウを開きます..."

    # AppleScriptを使用して新しいウィンドウで実行
    osascript <<EOF
tell application "Terminal"
    do script "cd ${SCRIPT_DIR}/.. && ${viewer_cmd}"
    activate
end tell
EOF

    log_success "ビューアウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（macOS iTerm2）
#
open_in_iterm() {
    local viewer_cmd="$1"

    log_info "iTerm2で新しいウィンドウを開きます..."

    # AppleScriptを使用
    osascript <<EOF
tell application "iTerm"
    create window with default profile
    tell current session of current window
        write text "cd ${SCRIPT_DIR}/.."
        write text "${viewer_cmd}"
    end tell
    activate
end tell
EOF

    log_success "ビューアウィンドウを開きました（iTerm2）"
}

#
# 新しいターミナルウィンドウで起動（Linux gnome-terminal）
#
open_in_gnome_terminal() {
    local viewer_cmd="$1"

    log_info "gnome-terminalで新しいウィンドウを開きます..."

    gnome-terminal -- bash -c "cd ${SCRIPT_DIR}/.. && ${viewer_cmd}"

    log_success "ビューアウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（Linux konsole）
#
open_in_konsole() {
    local viewer_cmd="$1"

    log_info "konsoleで新しいウィンドウを開きます..."

    konsole --workdir "${SCRIPT_DIR}/.." -e bash -c "${viewer_cmd}"

    log_success "ビューアウィンドウを開きました"
}

#
# 新しいターミナルウィンドウで起動（Linux xterm）
#
open_in_xterm() {
    local viewer_cmd="$1"

    log_info "xtermで新しいウィンドウを開きます..."

    xterm -e "cd ${SCRIPT_DIR}/.. && ${viewer_cmd}" &

    log_success "ビューアウィンドウを開きました"
}

#
# ビューアを新しいウィンドウで起動
#
launch_viewer_window() {
    local auto="${1:-false}"

    # ビューアコマンド
    local viewer_cmd="${VIEWER_SCRIPT} setup && ${VIEWER_SCRIPT} attach"

    # ターミナルタイプの検出
    local terminal_type
    terminal_type=$(detect_terminal)

    log_info "検出されたターミナル: ${terminal_type}"

    case "$terminal_type" in
        terminal)
            open_in_terminal_app "$viewer_cmd"
            ;;
        iterm)
            open_in_iterm "$viewer_cmd"
            ;;
        gnome-terminal)
            open_in_gnome_terminal "$viewer_cmd"
            ;;
        konsole)
            open_in_konsole "$viewer_cmd"
            ;;
        xterm)
            open_in_xterm "$viewer_cmd"
            ;;
        unknown)
            log_error "サポートされているターミナルが見つかりません"
            log_info "手動で以下のコマンドを実行してください:"
            echo ""
            echo "  ${VIEWER_SCRIPT} setup"
            echo "  ${VIEWER_SCRIPT} attach"
            return 1
            ;;
    esac
}

#
# 現在のターミナルで起動
#
launch_viewer_current() {
    log_info "現在のターミナルでビューアを起動します..."

    # セットアップ
    "$VIEWER_SCRIPT" setup

    # アタッチ
    "$VIEWER_SCRIPT" attach
}

#
# メイン処理
#
main() {
    local new_window="true"

    # オプション解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --current)
                new_window="false"
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [options]

Options:
  --current         現在のターミナルで起動（新しいウィンドウを開かない）
  --help, -h        このヘルプメッセージを表示

Description:
  統合ビューアを起動します。デフォルトでは新しいターミナルウィンドウで開きます。

  ビューアは以下のレイアウトで各セッションを表示します:
  - 左側 (30%): PjMセッション
  - 右側 (70%): その他のセッション（eng1, eng2, reviewer, docs）を縦分割

Supported Terminals:
  macOS:
    - Terminal.app
    - iTerm2

  Linux:
    - gnome-terminal
    - konsole
    - xterm

Examples:
  # 新しいウィンドウで起動（デフォルト）
  $0

  # 現在のターミナルで起動
  $0 --current

Note:
  ビューアを起動する前に、システムが起動している必要があります。
  ./scripts/start-system.sh を先に実行してください。
EOF
                exit 0
                ;;
            *)
                log_error "不明なオプション: $1"
                exit 1
                ;;
        esac
    done

    # 初期化
    init_common
    init_logger

    log_info "=== 統合ビューア起動 ==="

    # システムが起動しているか確認
    local pjm_session="${TMUX_SESSION_PREFIX}-pjm"
    if ! tmux_session_exists "$pjm_session"; then
        log_error "システムが起動していません"
        log_info "先に ./scripts/start-system.sh を実行してください"
        exit 1
    fi

    # ビューア起動
    if [[ "$new_window" == "true" ]]; then
        launch_viewer_window
    else
        launch_viewer_current
    fi
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
