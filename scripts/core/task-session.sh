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
        eng*)
            # エンジニアはworktreeで作業 (eng1, eng2, eng3, ...)
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
# タスクセッションの作成（Phase 2: 動的エンジニア数対応）
#
create_task_session() {
    local task_id="$1"
    local user_instruction="$2"
    local session_name
    session_name=$(get_task_session_name "$task_id")
    local window_name
    window_name=$(get_task_window_name "$task_id")
    local num_engineers="${NUM_ENGINEERS:-1}"

    log_info "Creating task session: ${session_name} (${num_engineers} engineers)"

    # セッションが既に存在する場合はエラー
    if tmux_session_exists "$session_name"; then
        log_error "Task session already exists: ${session_name}"
        return 1
    fi

    # セッション作成
    tmux new-session -d -s "$session_name" -n "$window_name"
    log_success "Task session created: ${session_name}"

    # PjMペイン（ペイン0）の設定
    setup_pjm_pane "$session_name" "$task_id" "$user_instruction"

    # エンジニア用worktreeの作成（動的）
    create_engineer_worktrees "$task_id"

    # エンジニアペインの作成（動的）
    create_engineer_panes "$session_name" "$task_id"

    log_success "Task session setup complete: ${session_name} (PjM + ${num_engineers} engineers)"
}

#
# PjMペインのセットアップ
#
setup_pjm_pane() {
    local session_name="$1"
    local task_id="$2"
    local user_instruction="$3"

    log_debug "Setting up PjM pane..."

    # 初期化スクリプトのパス
    local init_script="${ORCHESTRATOR_ROOT}/sessions/pjm/init.sh"

    # 初期化スクリプトを実行（1回の実行で環境設定とClaude起動を完了）
    log_debug "Starting Claude in PjM pane (auto-execution mode) with init script..."
    tmux send-keys -t "${session_name}.0" "${init_script} '${task_id}' '${ORCHESTRATOR_ROOT}' '${user_instruction}'" C-m

    log_debug "PjM pane setup complete"
}

#
# Git worktreeの作成
#
create_git_worktree() {
    local role="$1"
    local task_id="$2"
    local worktree_path="$3"

    # Target projectのメインブランチを確認
    local main_branch="${TARGET_PROJECT_MAIN_BRANCH:-main}"

    # ブランチ名を生成（Phase 2: 動的対応）
    local branch_prefix
    if [[ "$role" =~ ^eng[0-9]+$ ]]; then
        # エンジニアロール（eng1, eng2, eng3, ...）
        local eng_number="${role#eng}"
        local pattern="${ENGINEER_BRANCH_PREFIX:-eng__N__}"
        # __N__をエンジニア番号に置換
        branch_prefix="${pattern//__N__/${eng_number}}"
    else
        log_error "Unknown role: ${role}"
        return 1
    fi

    local branch_name="${branch_prefix}/${task_id}"

    log_info "Creating git worktree: ${worktree_path}"
    log_debug "Branch: ${branch_name}"
    log_debug "Base: ${main_branch}"

    # Target projectディレクトリに移動
    local original_dir
    original_dir=$(pwd)
    cd "${TARGET_PROJECT_PATH}"

    # Worktreeを作成（ブランチも同時に作成）
    if git worktree add -b "$branch_name" "$worktree_path" "$main_branch" 2>/dev/null; then
        log_success "Git worktree created: ${worktree_path}"
    else
        # ブランチが既に存在する場合
        log_warn "Branch ${branch_name} already exists, using existing branch"
        if git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            log_success "Git worktree created with existing branch: ${worktree_path}"
        else
            log_error "Failed to create worktree"
            cd "$original_dir"
            return 1
        fi
    fi

    # 元のディレクトリに戻る
    cd "$original_dir"
}

#
# エンジニア用worktreeの一括作成（Phase 2: 動的対応）
#
create_engineer_worktrees() {
    local task_id="$1"
    local num_engineers="${NUM_ENGINEERS:-1}"

    log_info "Creating worktrees for ${num_engineers} engineer(s)..."

    for ((i=1; i<=num_engineers; i++)); do
        local role="eng${i}"
        local worktree_path="${WORKTREE_BASE}/${role}"

        # worktreeが既に存在する場合はスキップ
        if [[ -d "$worktree_path" ]]; then
            log_warn "Worktree already exists: ${worktree_path} (skipping)"
            continue
        fi

        log_info "Creating worktree for ${role}: ${worktree_path}"

        if [[ -n "${TARGET_PROJECT_PATH:-}" ]] && [[ -d "${TARGET_PROJECT_PATH}" ]]; then
            # Target projectのgit worktreeを作成
            if ! create_git_worktree "$role" "$task_id" "$worktree_path"; then
                log_error "Failed to create git worktree for ${role}, aborting"
                return 1
            fi
        else
            # Standalone mode: 単純なディレクトリ作成
            mkdir -p "$worktree_path"
            log_warn "No target project configured, working in standalone mode"
        fi

        log_success "Worktree created: ${worktree_path}"
    done

    log_success "All worktrees created (${num_engineers} engineers)"
}

#
# エンジニアペインの一括作成（Phase 2: 動的対応）
#
create_engineer_panes() {
    local session_name="$1"
    local task_id="$2"
    local num_engineers="${NUM_ENGINEERS:-1}"

    log_info "Creating ${num_engineers} engineer pane(s)..."

    for ((i=1; i<=num_engineers; i++)); do
        local role="eng${i}"
        local workdir
        workdir=$(get_pane_workdir "$role")

        log_debug "Creating ${role} pane..."

        # 最初のエンジニアは右70%で水平分割、それ以降は垂直分割
        if [[ $i -eq 1 ]]; then
            tmux split-window -h -t "$session_name" -p 70
        else
            # 最後のペインを垂直分割
            local last_pane=$((i - 1))
            tmux split-window -v -t "${session_name}.${last_pane}"
        fi

        # 初期化スクリプトのパス
        local init_script="${ORCHESTRATOR_ROOT}/sessions/engineer/init.sh"

        # 初期化スクリプトを実行
        log_debug "Starting Claude in ${role} pane (auto-execution mode)..."
        tmux send-keys -t "${session_name}.${i}" "${init_script} '${task_id}' '${role}' '${workdir}' '${i}' '${ORCHESTRATOR_ROOT}'" C-m

        log_debug "${role} pane created"
    done

    log_success "All engineer panes created (${num_engineers} engineers)"
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
            local user_instruction="${3:-}"
            if [[ -z "$task_id" ]]; then
                log_error "Task ID is required"
                echo "Usage: $0 create <task-id> [instruction]"
                exit 1
            fi
            create_task_session "$task_id" "$user_instruction"
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
