#!/usr/bin/env bash
#
# common.sh - 共通関数とユーティリティ
# すべてのスクリプトから読み込まれる基本機能を提供
#

set -euo pipefail

# スクリプトのルートディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 設定ファイルのパス
ORCHESTRATOR_CONF="${ORCHESTRATOR_ROOT}/config/orchestrator.conf"
TARGET_PROJECT_CONF="${ORCHESTRATOR_ROOT}/config/target-project.conf"

# デフォルト設定
DEFAULT_TMUX_SESSION_PREFIX="claude"
DEFAULT_PIPE_DIR="${ORCHESTRATOR_ROOT}/communication/pipes"
DEFAULT_LOG_DIR="${ORCHESTRATOR_ROOT}/communication/logs"
DEFAULT_TASK_DIR="${ORCHESTRATOR_ROOT}/tasks"
DEFAULT_WORKTREE_BASE="${ORCHESTRATOR_ROOT}/worktrees"

# 色定義（ログ出力用）
COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_MAGENTA="\033[35m"
COLOR_CYAN="\033[36m"

# ログレベル
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# 現在のログレベル（環境変数で上書き可能）
CURRENT_LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

#
# 設定ファイルの読み込み
#
load_config() {
    if [[ -f "${ORCHESTRATOR_CONF}" ]]; then
        # shellcheck source=/dev/null
        source "${ORCHESTRATOR_CONF}"
    fi

    if [[ -f "${TARGET_PROJECT_CONF}" ]]; then
        # shellcheck source=/dev/null
        source "${TARGET_PROJECT_CONF}"
    fi

    # 設定がない場合はデフォルト値を使用
    TMUX_SESSION_PREFIX="${TMUX_SESSION_PREFIX:-$DEFAULT_TMUX_SESSION_PREFIX}"
    PIPE_DIR="${PIPE_DIR:-$DEFAULT_PIPE_DIR}"
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
    TASK_DIR="${TASK_DIR:-$DEFAULT_TASK_DIR}"
    WORKTREE_BASE="${WORKTREE_BASE:-$DEFAULT_WORKTREE_BASE}"
}

#
# ログ出力関数
#
log_debug() {
    [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]] || return 0
    echo -e "${COLOR_MAGENTA}[DEBUG]${COLOR_RESET} $*" >&2
}

log_info() {
    [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]] || return 0
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2
}

log_success() {
    [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]] || return 0
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*" >&2
}

log_warn() {
    [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARN ]] || return 0
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    [[ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ]] || return 0
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

#
# エラーハンドリング
#
die() {
    log_error "$@"
    exit 1
}

#
# 必須コマンドのチェック
#
check_required_commands() {
    local missing_commands=()

    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        die "Required commands not found: ${missing_commands[*]}"
    fi
}

#
# ファイルロック（flock使用）
#
acquire_lock() {
    local lockfile="$1"
    local timeout="${2:-10}"
    local fd="${3:-200}"

    eval "exec ${fd}>\"${lockfile}\""

    if ! flock -w "$timeout" "$fd"; then
        die "Failed to acquire lock: ${lockfile}"
    fi

    log_debug "Lock acquired: ${lockfile}"
}

release_lock() {
    local fd="${1:-200}"
    eval "exec ${fd}>&-"
    log_debug "Lock released"
}

#
# JSON操作（jq使用）
#
json_get() {
    local file="$1"
    local query="$2"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: ${file}"
        return 1
    fi

    jq -r "$query" "$file"
}

json_set() {
    local file="$1"
    local query="$2"
    local value="$3"
    local tmp_file="${file}.tmp"

    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: ${file}"
        return 1
    fi

    jq "$query = $value" "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
    log_debug "JSON updated: ${file}"
}

#
# タイムスタンプ生成（ISO 8601形式）
#
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#
# UUID生成（簡易版）
#
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # macOSの場合、uuidgenが利用可能
        # Linuxの場合、/proc/sys/kernel/random/uuidを使用
        if [[ -f /proc/sys/kernel/random/uuid ]]; then
            cat /proc/sys/kernel/random/uuid
        else
            # フォールバック: date + ランダム文字列
            echo "$(date +%s)-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9')"
        fi
    fi
}

#
# タスクIDの生成
#
generate_task_id() {
    local prefix="${1:-task}"
    local timestamp_part=$(date +%Y%m%d%H%M%S)
    local random_part=$(head -c 4 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)
    echo "${prefix}-${timestamp_part}-${random_part}"
}

#
# ディレクトリの存在確認と作成
#
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_debug "Directory created: ${dir}"
    fi
}

#
# tmuxセッションの存在確認
#
tmux_session_exists() {
    local session_name="$1"
    tmux has-session -t "$session_name" 2>/dev/null
}

#
# 名前付きパイプの作成
#
create_pipe() {
    local pipe_path="$1"

    if [[ -p "$pipe_path" ]]; then
        log_debug "Pipe already exists: ${pipe_path}"
        return 0
    fi

    mkfifo "$pipe_path"
    chmod 600 "$pipe_path"
    log_info "Pipe created: ${pipe_path}"
}

#
# 名前付きパイプの削除
#
remove_pipe() {
    local pipe_path="$1"

    if [[ -p "$pipe_path" ]]; then
        rm -f "$pipe_path"
        log_debug "Pipe removed: ${pipe_path}"
    fi
}

#
# 設定値の表示（デバッグ用）
#
show_config() {
    log_info "=== Orchestrator Configuration ==="
    log_info "ORCHESTRATOR_ROOT: ${ORCHESTRATOR_ROOT}"
    log_info "TMUX_SESSION_PREFIX: ${TMUX_SESSION_PREFIX}"
    log_info "PIPE_DIR: ${PIPE_DIR}"
    log_info "LOG_DIR: ${LOG_DIR}"
    log_info "TASK_DIR: ${TASK_DIR}"
    log_info "WORKTREE_BASE: ${WORKTREE_BASE}"

    if [[ -n "${TARGET_PROJECT_PATH:-}" ]]; then
        log_info "TARGET_PROJECT_PATH: ${TARGET_PROJECT_PATH}"
        log_info "TARGET_PROJECT_MAIN_BRANCH: ${TARGET_PROJECT_MAIN_BRANCH:-main}"
    else
        log_warn "TARGET_PROJECT_PATH not configured"
    fi
}

#
# 初期化処理
#
init_common() {
    # 必須コマンドのチェック
    check_required_commands tmux git jq

    # 設定ファイルの読み込み
    load_config

    # 必要なディレクトリの作成
    ensure_dir "$PIPE_DIR"
    ensure_dir "$LOG_DIR"
    ensure_dir "$TASK_DIR"
}

# スクリプトが直接実行された場合の処理
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_common
    show_config
fi
