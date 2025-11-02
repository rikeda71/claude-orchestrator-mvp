#!/usr/bin/env bash
#
# logger.sh - ログ管理システム
# ファイルベースのロギング機能を提供
#

set -euo pipefail

# Note: logger.shは必ずcommon.shの後にsourceされることを前提とする
# common.shが既に読み込まれていることが必要（ORCHESTRATOR_ROOTなどの変数が定義済み）

# ログファイルのパスは init_logger() で設定される
SESSION_LOG_DIR=""
SYSTEM_LOG_DIR=""
TASK_LOG_DIR=""

# ログローテーション設定
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=5

#
# ログディレクトリの初期化
#
init_logger() {
    # ログディレクトリパスを設定（init_common()の後に呼ばれる前提）
    SESSION_LOG_DIR="${LOG_DIR}/sessions"
    SYSTEM_LOG_DIR="${LOG_DIR}/system"
    TASK_LOG_DIR="${LOG_DIR}/tasks"

    ensure_dir "$SESSION_LOG_DIR"
    ensure_dir "$SYSTEM_LOG_DIR"
    ensure_dir "$TASK_LOG_DIR"
}

#
# ログファイルのパスを取得
#
get_log_path() {
    local log_type="$1"  # session, system, task
    local log_name="$2"

    case "$log_type" in
        session)
            echo "${SESSION_LOG_DIR}/${log_name}.log"
            ;;
        system)
            echo "${SYSTEM_LOG_DIR}/${log_name}.log"
            ;;
        task)
            echo "${TASK_LOG_DIR}/${log_name}.log"
            ;;
        *)
            die "Invalid log type: ${log_type}"
            ;;
    esac
}

#
# ログへの書き込み
#
write_log() {
    local log_type="$1"
    local log_name="$2"
    local level="$3"
    shift 3
    local message="$*"

    local log_file
    log_file=$(get_log_path "$log_type" "$log_name")

    local timestamp
    timestamp=$(timestamp)

    # ログエントリの作成
    local log_entry="[${timestamp}] [${level}] ${message}"

    # ファイルに追記
    echo "$log_entry" >> "$log_file"

    # ログローテーションの確認
    rotate_log_if_needed "$log_file"
}

#
# セッションログの書き込み
#
log_session() {
    local session_name="$1"
    local level="$2"
    shift 2
    local message="$*"

    write_log "session" "$session_name" "$level" "$message"
}

#
# システムログの書き込み
#
log_system() {
    local component="$1"
    local level="$2"
    shift 2
    local message="$*"

    write_log "system" "$component" "$level" "$message"
}

#
# タスクログの書き込み
#
log_task() {
    local task_id="$1"
    local level="$2"
    shift 2
    local message="$*"

    write_log "task" "$task_id" "$level" "$message"
}

#
# ログファイルのサイズ取得（MB）
#
get_log_size_mb() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        echo "0"
        return
    fi

    # ファイルサイズをMB単位で取得
    local size_bytes
    size_bytes=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
    echo $((size_bytes / 1024 / 1024))
}

#
# ログローテーション
#
rotate_log() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        return
    fi

    log_debug "Rotating log: ${log_file}"

    # 既存のローテーションファイルをシフト
    for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
        local old_file="${log_file}.${i}"
        local new_file="${log_file}.$((i + 1))"

        if [[ -f "$old_file" ]]; then
            if [[ $i -eq $((MAX_LOG_FILES - 1)) ]]; then
                # 最古のファイルを削除
                rm -f "$old_file"
            else
                mv "$old_file" "$new_file"
            fi
        fi
    done

    # 現在のログファイルを.1に移動
    mv "$log_file" "${log_file}.1"

    # 新しいログファイルを作成
    touch "$log_file"
}

#
# 必要に応じてログローテーション
#
rotate_log_if_needed() {
    local log_file="$1"
    local size_mb
    size_mb=$(get_log_size_mb "$log_file")

    if [[ $size_mb -ge $MAX_LOG_SIZE_MB ]]; then
        rotate_log "$log_file"
    fi
}

#
# ログファイルの表示
#
show_log() {
    local log_type="$1"
    local log_name="$2"
    local lines="${3:-50}"  # デフォルトは最新50行

    local log_file
    log_file=$(get_log_path "$log_type" "$log_name")

    if [[ ! -f "$log_file" ]]; then
        log_warn "Log file not found: ${log_file}"
        return 1
    fi

    tail -n "$lines" "$log_file"
}

#
# ログファイルの検索
#
search_log() {
    local log_type="$1"
    local log_name="$2"
    local pattern="$3"

    local log_file
    log_file=$(get_log_path "$log_type" "$log_name")

    if [[ ! -f "$log_file" ]]; then
        log_warn "Log file not found: ${log_file}"
        return 1
    fi

    grep "$pattern" "$log_file"
}

#
# すべてのログファイルをクリーンアップ
#
cleanup_logs() {
    local keep_current="${1:-true}"

    log_info "Cleaning up log files..."

    if [[ "$keep_current" == "true" ]]; then
        # ローテーションファイルのみ削除
        find "$LOG_DIR" -type f -name "*.log.*" -delete
        log_info "Rotated log files removed"
    else
        # すべてのログファイルを削除
        find "$LOG_DIR" -type f -name "*.log*" -delete
        log_info "All log files removed"
    fi
}

#
# ログの統計情報
#
log_stats() {
    log_info "=== Log Statistics ==="

    for log_type in session system task; do
        local log_dir
        case "$log_type" in
            session) log_dir="$SESSION_LOG_DIR" ;;
            system) log_dir="$SYSTEM_LOG_DIR" ;;
            task) log_dir="$TASK_LOG_DIR" ;;
        esac

        local file_count
        file_count=$(find "$log_dir" -type f -name "*.log" 2>/dev/null | wc -l | tr -d ' ')

        local total_size
        total_size=$(du -sh "$log_dir" 2>/dev/null | cut -f1 || echo "0")

        log_info "${log_type}: ${file_count} files, ${total_size}"
    done
}

#
# tmuxペインからのログキャプチャ
#
capture_tmux_pane() {
    local session_name="$1"
    local pane_index="${2:-0}"
    local output_file="$3"

    if ! tmux_session_exists "$session_name"; then
        log_error "Session not found: ${session_name}"
        return 1
    fi

    # tmuxペインの内容をキャプチャ
    tmux capture-pane -t "${session_name}:${pane_index}" -p > "$output_file"

    log_debug "Captured pane content: ${session_name} -> ${output_file}"
}

#
# セッションログのアーカイブ
#
archive_session_log() {
    local session_name="$1"
    local archive_dir="${LOG_DIR}/archives"

    ensure_dir "$archive_dir"

    local log_file
    log_file=$(get_log_path "session" "$session_name")

    if [[ ! -f "$log_file" ]]; then
        log_warn "No log file to archive: ${log_file}"
        return 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_name="${session_name}_${timestamp}.log.gz"
    local archive_path="${archive_dir}/${archive_name}"

    gzip -c "$log_file" > "$archive_path"

    log_info "Session log archived: ${archive_path}"
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_common
    init_logger

    case "${1:-}" in
        stats)
            log_stats
            ;;
        cleanup)
            cleanup_logs "${2:-true}"
            ;;
        show)
            show_log "${2:-session}" "${3:-pjm}" "${4:-50}"
            ;;
        *)
            echo "Usage: $0 {stats|cleanup|show}"
            echo "  stats           - Show log statistics"
            echo "  cleanup [keep]  - Clean up logs (keep=true/false)"
            echo "  show <type> <name> [lines] - Show log file"
            exit 1
            ;;
    esac
fi
