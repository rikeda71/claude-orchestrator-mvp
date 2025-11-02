#!/usr/bin/env bash
#
# task-manager.sh - タスク管理システム
# タスクのCRUD操作、ステータス管理、依存関係管理を提供
#

set -euo pipefail

# 共通ユーティリティの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../utils/common.sh
source "${SCRIPT_DIR}/../utils/common.sh"
# shellcheck source=../utils/logger.sh
source "${SCRIPT_DIR}/../utils/logger.sh"

# タスクステータスの定義
STATUS_PENDING="pending"
STATUS_IN_PROGRESS="in-progress"
STATUS_REVIEW="review"
STATUS_COMPLETED="completed"

# タスクタイプの定義
TYPE_FEATURE="feature"
TYPE_BUG="bug"
TYPE_REVIEW="review"
TYPE_DOCS="docs"

#
# タスクファイルのパスを取得
#
get_task_file_path() {
    local task_id="$1"
    local status="${2:-}"

    if [[ -z "$status" ]]; then
        # ステータスが指定されていない場合、全ディレクトリを検索
        for dir in queue in-progress review completed; do
            local file_path="${TASK_DIR}/${dir}/${task_id}.json"
            if [[ -f "$file_path" ]]; then
                echo "$file_path"
                return 0
            fi
        done
        return 1
    else
        # ステータスが指定されている場合
        local dir
        case "$status" in
            pending) dir="queue" ;;
            in-progress) dir="in-progress" ;;
            review) dir="reviews" ;;
            completed) dir="completed" ;;
            *) die "Invalid status: ${status}" ;;
        esac
        echo "${TASK_DIR}/${dir}/${task_id}.json"
    fi
}

#
# タスクの作成
#
create_task() {
    local type="$1"
    local description="$2"
    local assigned_to="${3:-}"
    local created_by="${4:-pjm}"

    # タスクタイプの検証
    case "$type" in
        feature|bug|review|docs) ;;
        *) die "Invalid task type: ${type}. Use: feature, bug, review, docs" ;;
    esac

    # タスクIDの生成
    local task_id
    task_id=$(generate_task_id "task")

    # タスクファイルのパス
    local task_file
    task_file=$(get_task_file_path "$task_id" "pending")

    # タスクJSONの作成
    cat > "$task_file" <<EOF
{
  "id": "${task_id}",
  "type": "${type}",
  "assigned_to": "${assigned_to}",
  "status": "${STATUS_PENDING}",
  "description": "${description}",
  "created_by": "${created_by}",
  "created_at": "$(timestamp)",
  "updated_at": "$(timestamp)",
  "dependencies": [],
  "worktree": "",
  "files": [],
  "review_notes": [],
  "history": []
}
EOF

    log_info "Task created: ${task_id}"
    log_task "$task_id" "INFO" "Task created: ${description}"

    echo "$task_id"
}

#
# タスクの表示
#
show_task() {
    local task_id="$1"

    local task_file
    task_file=$(get_task_file_path "$task_id")

    if [[ ! -f "$task_file" ]]; then
        die "Task not found: ${task_id}"
    fi

    cat "$task_file" | jq .
}

#
# タスク一覧の表示
#
list_tasks() {
    local status_filter="${1:-}"

    local dirs=()
    if [[ -z "$status_filter" ]]; then
        dirs=("queue" "in-progress" "reviews" "completed")
    else
        case "$status_filter" in
            pending) dirs=("queue") ;;
            in-progress) dirs=("in-progress") ;;
            review) dirs=("reviews") ;;
            completed) dirs=("completed") ;;
            *) die "Invalid status filter: ${status_filter}" ;;
        esac
    fi

    log_info "=== Task List ==="

    local found=0
    for dir in "${dirs[@]}"; do
        local dir_path="${TASK_DIR}/${dir}"

        if [[ -d "$dir_path" ]]; then
            for task_file in "${dir_path}"/*.json; do
                [[ -f "$task_file" ]] || continue
                found=1

                local task_id
                task_id=$(json_get "$task_file" '.id')
                local type
                type=$(json_get "$task_file" '.type')
                local assigned_to
                assigned_to=$(json_get "$task_file" '.assigned_to')
                local status
                status=$(json_get "$task_file" '.status')
                local description
                description=$(json_get "$task_file" '.description')

                printf "%-25s %-10s %-10s %-15s %s\n" \
                    "$task_id" "$type" "$assigned_to" "$status" "$description"
            done
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_info "No tasks found"
    fi
}

#
# タスクのフィールド更新
#
update_task_field() {
    local task_id="$1"
    local field="$2"
    local value="$3"

    local task_file
    task_file=$(get_task_file_path "$task_id")

    if [[ ! -f "$task_file" ]]; then
        die "Task not found: ${task_id}"
    fi

    # フィールドの更新
    local tmp_file="${task_file}.tmp"
    jq --arg val "$value" ".${field} = \$val | .updated_at = \"$(timestamp)\"" "$task_file" > "$tmp_file"
    mv "$tmp_file" "$task_file"

    log_info "Task updated: ${task_id} (${field} = ${value})"
    log_task "$task_id" "INFO" "Field updated: ${field} = ${value}"
}

#
# タスクのステータス変更（ファイル移動を伴う）
#
update_task_status() {
    local task_id="$1"
    local new_status="$2"

    # ステータスの検証
    case "$new_status" in
        pending|in-progress|review|completed) ;;
        *) die "Invalid status: ${new_status}" ;;
    esac

    # 現在のタスクファイルを検索
    local current_file
    current_file=$(get_task_file_path "$task_id")

    if [[ ! -f "$current_file" ]]; then
        die "Task not found: ${task_id}"
    fi

    # 現在のステータスを取得
    local current_status
    current_status=$(json_get "$current_file" '.status')

    if [[ "$current_status" == "$new_status" ]]; then
        log_warn "Task already in status: ${new_status}"
        return 0
    fi

    # 新しいファイルパスを決定
    local new_file
    new_file=$(get_task_file_path "$task_id" "$new_status")

    # ステータスの更新
    local tmp_file="${current_file}.tmp"
    jq --arg status "$new_status" '.status = $status | .updated_at = "'"$(timestamp)"'"' "$current_file" > "$tmp_file"

    # ファイルの移動
    mv "$tmp_file" "$new_file"
    rm -f "$current_file"

    log_success "Task status updated: ${task_id} (${current_status} -> ${new_status})"
    log_task "$task_id" "INFO" "Status changed: ${current_status} -> ${new_status}"

    echo "$new_file"
}

#
# タスクの割り当て
#
assign_task() {
    local task_id="$1"
    local assignee="$2"

    # 割り当て先の検証
    case "$assignee" in
        eng1|eng2|reviewer|docs|pjm) ;;
        *) die "Invalid assignee: ${assignee}. Use: eng1, eng2, reviewer, docs, pjm" ;;
    esac

    update_task_field "$task_id" "assigned_to" "$assignee"
    log_info "Task assigned: ${task_id} -> ${assignee}"
}

#
# タスクの削除
#
delete_task() {
    local task_id="$1"

    local task_file
    task_file=$(get_task_file_path "$task_id")

    if [[ ! -f "$task_file" ]]; then
        die "Task not found: ${task_id}"
    fi

    # ファイルの削除
    rm -f "$task_file"

    log_info "Task deleted: ${task_id}"
    log_task "$task_id" "INFO" "Task deleted"
}

#
# タスクにコメント追加
#
add_task_comment() {
    local task_id="$1"
    local comment="$2"
    local author="${3:-system}"

    local task_file
    task_file=$(get_task_file_path "$task_id")

    if [[ ! -f "$task_file" ]]; then
        die "Task not found: ${task_id}"
    fi

    # コメントの追加
    local tmp_file="${task_file}.tmp"
    local comment_entry=$(jq -n \
        --arg author "$author" \
        --arg comment "$comment" \
        --arg timestamp "$(timestamp)" \
        '{author: $author, comment: $comment, timestamp: $timestamp}')

    jq ".review_notes += [$comment_entry] | .updated_at = \"$(timestamp)\"" "$task_file" > "$tmp_file"
    mv "$tmp_file" "$task_file"

    log_info "Comment added to task: ${task_id}"
    log_task "$task_id" "INFO" "Comment added by ${author}: ${comment}"
}

#
# 担当者のタスク一覧
#
list_assigned_tasks() {
    local assignee="$1"

    log_info "=== Tasks assigned to ${assignee} ==="

    local found=0
    for dir in queue in-progress reviews; do
        local dir_path="${TASK_DIR}/${dir}"

        if [[ -d "$dir_path" ]]; then
            for task_file in "${dir_path}"/*.json; do
                [[ -f "$task_file" ]] || continue

                local assigned_to
                assigned_to=$(json_get "$task_file" '.assigned_to')

                if [[ "$assigned_to" == "$assignee" ]]; then
                    found=1
                    local task_id
                    task_id=$(json_get "$task_file" '.id')
                    local type
                    type=$(json_get "$task_file" '.type')
                    local status
                    status=$(json_get "$task_file" '.status')
                    local description
                    description=$(json_get "$task_file" '.description')

                    printf "%-25s %-10s %-15s %s\n" \
                        "$task_id" "$type" "$status" "$description"
                fi
            done
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_info "No tasks found for ${assignee}"
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
            shift
            create_task "$@"
            ;;
        show)
            shift
            show_task "$@"
            ;;
        list)
            shift
            list_tasks "$@"
            ;;
        update)
            shift
            local task_id="$1"
            local field="$2"
            local value="$3"

            if [[ "$field" == "status" ]]; then
                update_task_status "$task_id" "$value"
            else
                update_task_field "$task_id" "$field" "$value"
            fi
            ;;
        assign)
            shift
            assign_task "$@"
            ;;
        delete)
            shift
            delete_task "$@"
            ;;
        comment)
            shift
            add_task_comment "$@"
            ;;
        my-tasks)
            shift
            list_assigned_tasks "$@"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  create <type> <description> [assignee] [created_by]
      Create a new task
      Types: feature, bug, review, docs

  show <task-id>
      Show task details

  list [status]
      List all tasks or filter by status
      Status: pending, in-progress, review, completed

  update <task-id> <field> <value>
      Update a task field
      Special handling for 'status' field (moves file)

  assign <task-id> <assignee>
      Assign task to someone
      Assignees: eng1, eng2, reviewer, docs, pjm

  delete <task-id>
      Delete a task

  comment <task-id> <comment> [author]
      Add a comment to task

  my-tasks <assignee>
      List tasks assigned to specific person

Examples:
  $0 create feature "Implement user authentication" eng1 pjm
  $0 list pending
  $0 show task-20251102120000-abc123
  $0 update task-20251102120000-abc123 status in-progress
  $0 assign task-20251102120000-abc123 eng2
  $0 my-tasks eng1
EOF
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
