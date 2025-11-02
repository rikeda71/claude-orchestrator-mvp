#!/usr/bin/env bash
#
# viewer.sh - 統合ビューア管理
# 複数のClaude Codeセッションを1つのtmuxウィンドウで統合表示
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

# ビューアセッション名
VIEWER_SESSION="${TMUX_SESSION_PREFIX}-viewer"

#
# ビューアセッションの作成
#
create_viewer_session() {
    log_info "統合ビューアセッションを作成中..."

    # 既存セッションのチェック
    if tmux_session_exists "$VIEWER_SESSION"; then
        log_warn "ビューアセッションは既に存在します: ${VIEWER_SESSION}"
        return 0
    fi

    # ビューアセッションの作成
    tmux new-session -d -s "$VIEWER_SESSION" -n "orchestrator-view"

    log_success "ビューアセッション作成完了: ${VIEWER_SESSION}"
}

#
# レイアウトの設定
#
setup_viewer_layout() {
    local roles=("$@")

    log_info "ビューアレイアウトを設定中..."

    if ! tmux_session_exists "$VIEWER_SESSION"; then
        die "ビューアセッションが存在しません"
    fi

    # ウィンドウの参照
    local window="${VIEWER_SESSION}:orchestrator-view"

    # 最初のペイン（左側: PjM用）
    log_debug "PjMペインを設定中..."

    # 右側を垂直分割して他のロール用のペインを作成
    local pane_count=${#roles[@]}

    if [[ $pane_count -eq 0 ]]; then
        log_warn "表示するロールが指定されていません"
        return 1
    fi

    # 左側30%をPjM、右側70%をその他に分割
    tmux split-window -h -t "$window" -p 70

    # 右側のペインを水平分割（役割の数に応じて）
    if [[ $pane_count -gt 1 ]]; then
        for ((i=1; i<pane_count; i++)); do
            # 残りのスペースを均等に分割
            local percentage=$((100 / (pane_count - i + 1)))
            tmux split-window -v -t "${window}.1" -p "$percentage"
        done
    fi

    log_success "レイアウト設定完了"
}

#
# セッションをペインに接続
#
attach_sessions_to_panes() {
    log_info "各ペインにセッションを接続中..."

    if ! tmux_session_exists "$VIEWER_SESSION"; then
        die "ビューアセッションが存在しません"
    fi

    local window="${VIEWER_SESSION}:orchestrator-view"

    # 左ペイン（0番）: PjM
    local pjm_session="${TMUX_SESSION_PREFIX}-pjm"
    if tmux_session_exists "$pjm_session"; then
        log_debug "PjMセッションを接続: ペイン0"
        tmux send-keys -t "${window}.0" "tmux attach-session -t ${pjm_session}" C-m
    else
        log_warn "PjMセッションが存在しません"
        tmux send-keys -t "${window}.0" "echo 'PjMセッションが起動していません'" C-m
    fi

    # 右側のペイン: その他のロール
    local pane_index=1
    for role in eng1 eng2 reviewer docs; do
        local role_session="${TMUX_SESSION_PREFIX}-${role}"

        if tmux_session_exists "$role_session"; then
            log_debug "${role}セッションを接続: ペイン${pane_index}"
            # ペインが存在するか確認
            if tmux list-panes -t "$window" | grep -q "^${pane_index}:"; then
                tmux send-keys -t "${window}.${pane_index}" "tmux attach-session -t ${role_session}" C-m
                pane_index=$((pane_index + 1))
            fi
        fi
    done

    log_success "セッション接続完了"
}

#
# ビューアの完全セットアップ
#
setup_viewer() {
    log_info "統合ビューアをセットアップ中..."

    # アクティブなロールを検出
    local active_roles=()
    for role in eng1 eng2 reviewer docs; do
        local session_name="${TMUX_SESSION_PREFIX}-${role}"
        if tmux_session_exists "$session_name"; then
            active_roles+=("$role")
        fi
    done

    if [[ ${#active_roles[@]} -eq 0 ]]; then
        log_warn "アクティブなエンジニア/レビュワー/Docsセッションがありません"
        log_info "PjMセッションのみ表示します"
    fi

    # ビューアセッション作成
    create_viewer_session

    # レイアウト設定
    setup_viewer_layout "${active_roles[@]}"

    # セッション接続
    attach_sessions_to_panes

    log_success "統合ビューアのセットアップ完了"
}

#
# ビューアセッションにアタッチ
#
attach_viewer() {
    if ! tmux_session_exists "$VIEWER_SESSION"; then
        log_error "ビューアセッションが存在しません"
        log_info "先に setup を実行してください"
        return 1
    fi

    log_info "ビューアセッションにアタッチします..."
    tmux attach-session -t "$VIEWER_SESSION"
}

#
# ビューアセッションの削除
#
kill_viewer() {
    if ! tmux_session_exists "$VIEWER_SESSION"; then
        log_warn "ビューアセッションは存在しません"
        return 0
    fi

    log_info "ビューアセッションを終了中..."
    tmux kill-session -t "$VIEWER_SESSION"
    log_success "ビューアセッション終了完了"
}

#
# ビューアのステータス表示
#
viewer_status() {
    log_info "=== ビューアセッションステータス ==="

    if tmux_session_exists "$VIEWER_SESSION"; then
        log_success "ビューアセッション: 実行中"

        # ペイン情報を表示
        log_info "ペイン構成:"
        tmux list-panes -t "$VIEWER_SESSION" -F "  ペイン#{pane_index}: #{pane_width}x#{pane_height}"
    else
        log_info "ビューアセッション: 停止中"
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
        setup)
            setup_viewer
            ;;
        attach)
            attach_viewer
            ;;
        kill)
            kill_viewer
            ;;
        status)
            viewer_status
            ;;
        *)
            cat <<EOF
Usage: $0 <command>

Commands:
  setup
      統合ビューアセッションをセットアップ
      - ビューアセッション作成
      - レイアウト設定（左: PjM、右: その他）
      - 各セッションを接続

  attach
      ビューアセッションにアタッチ
      統合ビューを表示

  kill
      ビューアセッションを終了

  status
      ビューアセッションのステータス表示

Examples:
  # ビューアのセットアップ
  $0 setup

  # ビューアを表示
  $0 attach

  # ビューアを終了
  $0 kill

Layout:
  ┌─────────────────────────────────────────┐
  │ claude-viewer                           │
  ├──────────────┬──────────────────────────┤
  │              │  eng1                    │
  │   PjM        ├──────────────────────────┤
  │   (30%)      │  eng2                    │
  │              ├──────────────────────────┤
  │              │  reviewer                │
  │              ├──────────────────────────┤
  │              │  docs                    │
  └──────────────┴──────────────────────────┘
         左                  右(70%)
EOF
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
