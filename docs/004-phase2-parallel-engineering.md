# Phase 2: 並列エンジニアリング 詳細設計書

## ドキュメント情報

- **作成日**: 2025-11-02
- **対象バージョン**: 0.3.0 (Phase 2)
- **前バージョン**: 0.2.0 (Phase 1 MVP完了)
- **目的**: 動的なエンジニア数指定による並列開発の実現

## 改訂履歴

- **2025-11-02**: 初版作成
- **2025-11-02**: eng2固定→動的エンジニア数指定方式に設計変更
- **2025-11-02**: タスク分配アルゴリズムの詳細追加（PjM主導型 + 自動割り当て補助）
- **2025-11-02**: タスク通知機能（notify_engineer）の実装詳細追加

---

## 1. Phase 2 の目的

### 1.1 背景

Phase 1 (v0.2.0)では、PjMとeng1による2ペイン構成を実装し、基本的なタスク管理とgit worktreeを用いた開発環境を確立しました。

Phase 2では、**エンジニア数を動的に指定できる仕組み**を導入し、複数のエンジニアが**並列に異なるタスクを実装**できる環境を構築します。これにより、プロジェクト規模に応じた柔軟な開発体制が可能になります。

### 1.2 Phase 2 の目標

- ✅ エンジニア数を起動オプションで指定可能（`--engineers N`）
- ✅ 指定された数のエンジニアペイン自動作成
- ✅ 各エンジニア用のgit worktree自動作成
- ✅ タスク分配ロジックの実装（複数エンジニアへの適切な割り当て）
- ✅ 並列作業時のコンフリクト検出・警告機能
- ✅ 全エンジニアの進捗状況を並行監視
- ✅ マージ時のコンフリクト解決サポート

### 1.3 設計思想: スケーラブルなアーキテクチャ

**コンセプト**: 「eng2固定」ではなく「eng{1..N}の動的生成」

```bash
# 起動時にエンジニア数を指定
./scripts/start-system.sh --engineers 2   # eng1, eng2
./scripts/start-system.sh --engineers 3   # eng1, eng2, eng3
./scripts/start-system.sh --engineers 5   # eng1, eng2, ..., eng5
```

**メリット**:
- プロジェクトの規模に応じて柔軟にスケール可能
- 将来的な拡張（eng10以上）にも対応
- コードの重複を排除（ループ処理で一般化）

## 2. アーキテクチャ変更

### 2.1 セッション構造（動的ペイン生成）

```
claude-task-{session-id}
├── Pane 0: PjM              (タスク作成・進捗管理)
├── Pane 1: eng1             (エンジニア1 実装)
├── Pane 2: eng2             (エンジニア2 実装)
├── Pane 3: eng3             (エンジニア3 実装)  ← 動的に追加
└── ...                      (--engineers オプションに応じて拡張)
```

**変更点**:
- **エンジニア数は起動時に決定**（デフォルト: 1）
- 各ペインは独立したClaude Codeインスタンス
- PjMがすべてのエンジニアの作業状況を監視
- ペイン番号: `0 (PjM)`, `1..(N) (eng1..engN)`

### 2.2 Git Worktree構造（動的生成）

```
worktrees/
├── eng1/                    # eng1専用worktree
│   └── (TARGET_PROJECT)
├── eng2/                    # eng2専用worktree
│   └── (TARGET_PROJECT)
├── eng3/                    # eng3専用worktree (--engineers 3以上の場合)
│   └── (TARGET_PROJECT)
└── ...
```

**ブランチ命名規則**:
- eng{N}: `eng{N}/feature/*`, `eng{N}/bug/*`, etc.
- 例: `eng1/feature/auth`, `eng2/bug/fix-login`, `eng3/feature/api`

各エンジニアは独立したworktreeで作業し、git worktreeによりファイルシステムレベルで隔離されます。

### 2.3 設定ファイル構造

**ファイル**: `config/orchestrator.conf`

新規追加パラメータ:

```bash
# デフォルトのエンジニア数（Phase 1との互換性のため1）
DEFAULT_ENGINEERS=1

# 最大エンジニア数（システムリソースの上限）
MAX_ENGINEERS=10
```

**ファイル**: `config/target-project.conf`

既存パラメータの一般化:

```bash
# Engineer branch prefix pattern
# {N} はエンジニア番号に置換される
ENGINEER_BRANCH_PREFIX="eng{N}"

# 例:
# eng1 → eng1/feature/xxx
# eng2 → eng2/feature/xxx
# eng3 → eng3/feature/xxx
```

### 2.4 タスクフロー（N人のエンジニア）

```mermaid
graph TD
    A[PjM: 要件分析] --> B[PjM: タスク分割]
    B --> C[PjM: 負荷状況確認]
    C --> D{PjM: 担当者決定}

    D -->|手動割り当て| E1[PjM: タスク作成+担当者指定]
    D -->|自動割り当て| E2[PjM: タスク作成→auto-assign]

    E1 --> F[自動通知: eng{N}ペインへ]
    E2 --> F

    F --> G1[eng1: 実装開始]
    F --> G2[eng2: 実装開始]
    F --> G3[eng3: 実装開始]
    F --> G4[engN: 実装開始]

    G1 --> H1[eng1: コミット]
    G2 --> H2[eng2: コミット]
    G3 --> H3[eng3: コミット]
    G4 --> H4[engN: コミット]

    H1 --> I{PjM: マージ可否判定}
    H2 --> I
    H3 --> I
    H4 --> I

    I -->|コンフリクトなし| J[PjM: masterへマージ]
    I -->|コンフリクトあり| K[PjM: コンフリクト通知]
    K --> L[担当eng: コンフリクト解決]
    L --> I
```

### 2.5 タスク分配アルゴリズムの詳細

#### 2.5.1 基本フロー（PjM主導型）⭐ 推奨

**Step 1: タスク分割**
- PjMが大きな機能要件を分析
- 実装可能な単位にサブタスクを分割
- 各サブタスクの依存関係を整理

**Step 2: 負荷状況確認**
```bash
../../scripts/core/task-manager.sh list-engineers
```

出力例:
```
Engineer   | Pending    | In Progress
----------------------------------------
eng1       | 1          | 1
eng2       | 0          | 1
eng3       | 2          | 0
```

**Step 3: 担当者決定**

PjMが以下を考慮して担当者を決定:
- ✅ エンジニアの現在の負荷状況
- ✅ タスクの優先度・緊急度
- ✅ タスク間の依存関係
- 🔜 エンジニアのスキルセット（Phase 3以降）

**Step 4: タスク作成と自動通知**
```bash
# 担当者を指定してタスク作成
../../scripts/core/task-manager.sh create feature "Add user auth" eng2 pjm

# → 自動的に eng2 ペインに通知が送信される
```

**Step 5: エンジニアが実装開始**
- 割り当てられたタスクの通知を受け取る
- タスク詳細を確認して実装開始

**メリット**:
- ✅ PjMがコンテキストを持って判断できる
- ✅ タスクの依存関係を考慮した割り当て可能
- ✅ プロジェクト全体の最適化が可能

#### 2.5.2 補助的フロー（自動割り当て）

単純な負荷分散が必要な場合や、大量の独立したタスクを一括割り当てする場合:

```bash
# タスク作成（担当者未指定）
../../scripts/core/task-manager.sh create feature "Task description" "" pjm

# 自動割り当て（最も負荷の少ないエンジニアへ）
../../scripts/core/task-manager.sh auto-assign <task-id>
```

**自動割り当てアルゴリズム（Phase 2）**:
1. 全エンジニアの現在のタスク数を取得（pending + in-progress）
2. 最もタスク数が少ないエンジニアを選択
3. 同数の場合は番号が若いエンジニアを優先（eng1 > eng2 > ...）

**一括自動割り当ての例**:
```bash
# 大量のタスクを一括作成
for i in {1..10}; do
    ../../scripts/core/task-manager.sh create feature "Task ${i}" "" pjm
done

# 一括自動割り当て
for task_id in $(../../scripts/core/task-manager.sh list pending | awk '{print $1}'); do
    ../../scripts/core/task-manager.sh auto-assign "$task_id"
done
```

**メリット**:
- ✅ 簡単・高速
- ✅ 負荷が均等に分散される
- ✅ 大量タスクの一括処理に便利

**将来の拡張（Phase 3以降）**:
- 🔜 タスク規模（ストーリーポイント）を考慮
- 🔜 エンジニアのスキルセットとのマッチング
- 🔜 タスクの優先度を考慮した割り当て

#### 2.5.3 タスク通知機能

タスクが割り当てられると、自動的に該当エンジニアペインに通知が送信されます。

**通知内容**:
```
📋 New task assigned: task-20251102-abc123
Task Type: feature
Description: Add user authentication
Priority: high
Dependencies: []

Run the following to see details:
../../scripts/core/task-manager.sh show task-20251102-abc123
```

**実装方法**:
- `assign_task()` 関数内で `notify_engineer()` を呼び出し
- tmux send-keys でメッセージを該当ペインに送信

## 3. 実装計画

### 3.1 影響を受けるファイル

#### 3.1.1 スクリプトファイル

1. **`scripts/start-system.sh`** ⭐ 重要
   - **新規オプション**: `--engineers N` の追加
   - エンジニア数のバリデーション（1 ≤ N ≤ MAX_ENGINEERS）
   - エンジニア数を環境変数 `NUM_ENGINEERS` に設定
   - 動的なセッションディレクトリ作成（ループ処理）

2. **`scripts/core/task-session.sh`** ⭐ 重要
   - **動的ペイン生成**: `NUM_ENGINEERS` に基づいてループでeng{1..N}を作成
   - **動的worktree生成**: 各エンジニア用のworktreeをループで作成
   - **init-prompt動的ロード**: 各エンジニアに初期プロンプトを送信
   - **レイアウト最適化**: ペイン数に応じた自動レイアウト調整

3. **`scripts/core/pane-manager.sh`**
   - `add_pane()` 関数の実装（汎用化）
   - `get_engineer_count()` 関数の追加（現在のエンジニア数取得）
   - `optimize_layout()` 関数の拡張（N+1ペインに対応）

4. **`scripts/core/task-manager.sh`** ⭐ 重要
   - **タスク分配アルゴリズム**: N人のエンジニアに対する負荷分散
   - **`auto-assign` コマンド**: 最も負荷の少ないエンジニアへ自動割り当て
   - **`list-engineers` コマンド**: 現在のエンジニア一覧と負荷状況表示
   - **`notify_engineer()` 関数**: タスク割り当て時にエンジニアペインへ自動通知
   - **コンフリクト検出**: 全エンジニアの進行中タスクを横断チェック

5. **`scripts/stop-system.sh`**
   - **動的worktree削除**: すべてのeng{1..N} worktreeを削除
   - **動的セッション停止**: すべてのエンジニアペインを停止

#### 3.1.2 設定ファイル

6. **`config/orchestrator.conf`**
   - `DEFAULT_ENGINEERS=1`
   - `MAX_ENGINEERS=10`

7. **`config/target-project.conf`**
   - `ENGINEER_BRANCH_PREFIX="eng{N}"` （パターン化）

#### 3.1.3 セッション初期化ファイル

8. **`sessions/engineer/init.sh`**
   - 既存のまま（ROLE環境変数で切り分け）
   - `ROLE=eng1`, `ROLE=eng2`, ..., `ROLE=engN`

9. **`sessions/engineer/init-prompt-v0.2.0.txt`**
   - 既存のまま（汎用的なプロンプト）
   - エンジニア番号に依存しない記述

#### 3.1.4 ドキュメント

10. **`CLAUDE.md`**
    - `--engineers` オプションの説明追加
    - 動的エンジニア数に対応したコマンド例

11. **`README.md`**
    - Phase 2の動的エンジニア数機能の説明
    - 使用例の追加

### 3.2 実装ステップ

#### Step 1: 設定ファイルの拡張

**ファイル**: `config/orchestrator.conf`

```bash
# Phase 2: 並列エンジニアリング設定
DEFAULT_ENGINEERS=1      # デフォルトのエンジニア数
MAX_ENGINEERS=10         # 最大エンジニア数
```

**ファイル**: `config/target-project.conf`

```bash
# Engineer branch prefix pattern
# {N} はエンジニア番号に置換される (例: eng1, eng2, eng3)
ENGINEER_BRANCH_PREFIX="eng{N}"
```

---

#### Step 2: start-system.sh に `--engineers` オプション追加

**ファイル**: `scripts/start-system.sh`

**主な変更点**:

1. **オプション解析**:

```bash
# デフォルト値
NUM_ENGINEERS="${DEFAULT_ENGINEERS:-1}"
OPEN_TERMINAL=true

# オプション解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --engineers)
            NUM_ENGINEERS="$2"
            shift 2
            ;;
        --no-open)
            OPEN_TERMINAL=false
            shift
            ;;
        --with-samples)
            CREATE_SAMPLES=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--engineers N] [--no-open] [--with-samples]"
            exit 1
            ;;
    esac
done
```

2. **バリデーション**:

```bash
# エンジニア数のバリデーション
if ! [[ "$NUM_ENGINEERS" =~ ^[0-9]+$ ]]; then
    die "Invalid engineer count: $NUM_ENGINEERS (must be a number)"
fi

if [[ $NUM_ENGINEERS -lt 1 ]]; then
    die "Engineer count must be at least 1"
fi

if [[ $NUM_ENGINEERS -gt ${MAX_ENGINEERS:-10} ]]; then
    die "Engineer count exceeds maximum (${MAX_ENGINEERS})"
fi

log_info "Starting system with ${NUM_ENGINEERS} engineer(s)..."
export NUM_ENGINEERS
```

3. **動的ディレクトリ作成**:

```bash
setup_directories() {
    log_info "Setting up directory structure..."

    # ... 既存のディレクトリ作成 ...

    # エンジニア用セッションディレクトリ（動的）
    for ((i=1; i<=NUM_ENGINEERS; i++)); do
        ensure_dir "${ORCHESTRATOR_ROOT}/sessions/eng${i}"
    done

    # Note: eng{N}ディレクトリはgit worktree addで自動作成されるため、ここでは作成しない

    log_success "Directory structure initialized (${NUM_ENGINEERS} engineers)"
}
```

---

#### Step 3: task-session.sh での動的ペイン・worktree生成

**ファイル**: `scripts/core/task-session.sh`

**主な変更点**:

1. **動的worktree作成**:

```bash
create_engineer_worktrees() {
    local num_engineers="${NUM_ENGINEERS:-1}"

    log_info "Creating worktrees for ${num_engineers} engineer(s)..."

    for ((i=1; i<=num_engineers; i++)); do
        local role="eng${i}"
        local worktree_path="${WORKTREE_BASE}/${role}"

        # worktreeが既に存在する場合はスキップ
        if [[ -d "$worktree_path" ]]; then
            log_warn "Worktree already exists: $worktree_path (skipping)"
            continue
        fi

        # ブランチ名生成 (eng{N}/session-{SESSION_ID})
        local branch_prefix="${ENGINEER_BRANCH_PREFIX/\{N\}/${i}}"
        local branch_name="${branch_prefix}/session-${SESSION_ID}"

        # メインブランチから新しいブランチを作成してworktree追加
        log_info "Creating worktree for ${role}: ${worktree_path}"
        cd "$TARGET_PROJECT_PATH" || die "Failed to cd to target project"

        git worktree add -b "$branch_name" "$worktree_path" "$TARGET_PROJECT_MAIN_BRANCH" \
            || die "Failed to create worktree for ${role}"

        log_success "Worktree created: ${worktree_path} (branch: ${branch_name})"
    done
}
```

2. **動的ペイン作成**:

```bash
create_engineer_panes() {
    local num_engineers="${NUM_ENGINEERS:-1}"

    log_info "Creating ${num_engineers} engineer pane(s)..."

    for ((i=1; i<=num_engineers; i++)); do
        local role="eng${i}"

        log_info "Adding pane for ${role}..."
        add_pane "$role" "$SESSION_NAME" || die "Failed to add pane for ${role}"
    done

    # レイアウト最適化（PjM + N engineers）
    local total_panes=$((num_engineers + 1))
    optimize_layout "$SESSION_NAME" "$total_panes"
}
```

3. **start_task_session() の更新**:

```bash
start_task_session() {
    # ... 既存の初期化処理 ...

    # PjMペイン作成
    create_pjm_pane

    # エンジニア用worktree作成（動的）
    create_engineer_worktrees

    # エンジニアペイン作成（動的）
    create_engineer_panes

    # ... 以降の処理 ...
}
```

---

#### Step 4: pane-manager.sh の汎用化

**ファイル**: `scripts/core/pane-manager.sh`

**主な変更点**:

1. **`add_pane()` 関数の実装**:

```bash
add_pane() {
    local role="${1:-}"
    local session_name="${2:-}"

    if [[ -z "$role" || -z "$session_name" ]]; then
        log_error "Usage: add_pane <role> <session_name>"
        return 1
    fi

    # 作業ディレクトリ取得
    local workdir
    workdir=$(get_pane_workdir "$role")

    # ワークツリーディレクトリの確認
    if [[ ! -d "$workdir" ]]; then
        log_error "Worktree directory not found: $workdir"
        return 1
    fi

    # 初期化スクリプトパス
    local init_script
    if [[ "$role" =~ ^eng[0-9]+$ ]]; then
        # エンジニアロール（eng1, eng2, ..., engN）
        init_script="${ORCHESTRATOR_ROOT}/sessions/engineer/init.sh"
    else
        # その他のロール（pjm, reviewer, docs）
        init_script="${ORCHESTRATOR_ROOT}/sessions/${role}/init.sh"
    fi

    # 現在のペイン数を取得
    local current_panes
    current_panes=$(tmux list-panes -t "$session_name" | wc -l)

    # ペイン追加（水平分割）
    tmux split-window -v -t "${session_name}.${current_panes}" -c "$workdir"

    # 新ペイン番号を取得（最新のペイン）
    local new_pane
    new_pane=$(tmux list-panes -t "$session_name" -F "#{pane_index}" | tail -1)

    # 初期化スクリプトを実行
    if [[ -f "$init_script" ]]; then
        log_info "Initializing ${role} pane with ${init_script}..."
        tmux send-keys -t "${session_name}.${new_pane}" "ROLE=${role} bash ${init_script}" C-m
    else
        log_warn "Init script not found: ${init_script}"
    fi

    log_success "Added ${role} pane (Pane ${new_pane}) to session ${session_name}"
}
```

2. **`optimize_layout()` 関数の拡張**:

```bash
optimize_layout() {
    local session_name="${1:-}"
    local num_panes="${2:-2}"

    if [[ -z "$session_name" ]]; then
        log_error "Usage: optimize_layout <session_name> [num_panes]"
        return 1
    fi

    log_info "Optimizing layout for ${num_panes} pane(s)..."

    case "$num_panes" in
        2)
            # PjM + eng1: 横2分割
            tmux select-layout -t "$session_name" even-horizontal
            ;;
        3)
            # PjM + eng1 + eng2: PjM左、eng1/eng2右2段
            tmux select-layout -t "$session_name" main-vertical
            tmux resize-pane -t "${session_name}.0" -x 30%
            ;;
        4|5)
            # PjM + eng1-3(or 4): タイル状
            tmux select-layout -t "$session_name" tiled
            ;;
        *)
            # 6ペイン以上: even-verticalで縦分割
            tmux select-layout -t "$session_name" even-vertical
            ;;
    esac

    log_success "Layout optimized for ${num_panes} panes"
}
```

3. **`get_pane_workdir()` の拡張**:

```bash
get_pane_workdir() {
    local role="${1:-}"

    case "$role" in
        pjm|reviewer|docs)
            # Orchestrator context
            echo "${ORCHESTRATOR_ROOT}/sessions/${role}"
            ;;
        eng*)
            # Engineer context (eng1, eng2, ..., engN)
            echo "${WORKTREE_BASE}/${role}"
            ;;
        *)
            log_error "Unknown role: $role"
            return 1
            ;;
    esac
}
```

---

#### Step 5: task-manager.sh でのN人対応タスク分配

**ファイル**: `scripts/core/task-manager.sh`

**主な変更点**:

1. **全エンジニア一覧取得**:

```bash
get_all_engineers() {
    local num_engineers="${NUM_ENGINEERS:-1}"
    for ((i=1; i<=num_engineers; i++)); do
        echo "eng${i}"
    done
}
```

2. **`auto-assign` コマンド（N人対応）**:

```bash
auto_assign_task() {
    local task_id="${1:-}"

    if [[ -z "$task_id" ]]; then
        log_error "Usage: auto-assign <task-id>"
        return 1
    fi

    # 全エンジニアのタスク数を取得
    local min_load=999999
    local best_engineer=""

    for engineer in $(get_all_engineers); do
        local task_count
        task_count=$(find "$QUEUE_DIR" "$INPROGRESS_DIR" -name "*.json" \
            -exec jq -r "select(.assignee == \"$engineer\") | .id" {} \; 2>/dev/null | wc -l)

        log_debug "${engineer}: ${task_count} tasks"

        if [[ $task_count -lt $min_load ]]; then
            min_load=$task_count
            best_engineer="$engineer"
        fi
    done

    if [[ -z "$best_engineer" ]]; then
        log_error "No available engineers found"
        return 1
    fi

    # タスク割り当て
    assign_task "$task_id" "$best_engineer"
    log_success "Task ${task_id} auto-assigned to ${best_engineer} (current load: ${min_load})"
}
```

3. **`list-engineers` コマンド**:

```bash
list_engineers() {
    log_info "Engineer workload status:"
    echo ""
    printf "%-10s | %-10s | %-15s\n" "Engineer" "Pending" "In Progress"
    echo "----------------------------------------"

    for engineer in $(get_all_engineers); do
        local pending_count
        local inprogress_count

        pending_count=$(find "$QUEUE_DIR" -name "*.json" \
            -exec jq -r "select(.assignee == \"$engineer\") | .id" {} \; 2>/dev/null | wc -l)

        inprogress_count=$(find "$INPROGRESS_DIR" -name "*.json" \
            -exec jq -r "select(.assignee == \"$engineer\") | .id" {} \; 2>/dev/null | wc -l)

        printf "%-10s | %-10s | %-15s\n" "$engineer" "$pending_count" "$inprogress_count"
    done
}
```

4. **コンフリクト検出（全エンジニア横断）**:

```bash
check_potential_conflicts() {
    local task_id="${1:-}"
    local assignee="${2:-}"

    # タスクの変更ファイルリストを取得
    local task_file
    task_file=$(find_task_file "$task_id")

    local changed_files
    changed_files=$(jq -r '.files[]?' "$task_file" 2>/dev/null)

    if [[ -z "$changed_files" ]]; then
        log_debug "No files specified for task ${task_id}, skipping conflict check"
        return 0
    fi

    # 全エンジニアの進行中タスクと比較
    local has_conflict=false

    for engineer in $(get_all_engineers); do
        # 自分自身はスキップ
        if [[ "$engineer" == "$assignee" ]]; then
            continue
        fi

        # このエンジニアの進行中タスクを取得
        local other_tasks
        other_tasks=$(find "$INPROGRESS_DIR" -name "*.json" \
            -exec jq -r "select(.assignee == \"$engineer\") | .id" {} \; 2>/dev/null)

        for other_task in $other_tasks; do
            local other_files
            other_files=$(jq -r '.files[]?' "${INPROGRESS_DIR}/${other_task}.json" 2>/dev/null)

            # ファイルの重複チェック
            for file in $changed_files; do
                if echo "$other_files" | grep -q "^${file}$"; then
                    log_warn "⚠️  Potential conflict detected!"
                    log_warn "    File: $file"
                    log_warn "    Task ${task_id} (${assignee}) ⚔️  Task ${other_task} (${engineer})"
                    has_conflict=true
                fi
            done
        done
    done

    if [[ "$has_conflict" == "true" ]]; then
        return 1
    fi

    log_success "No conflicts detected for task ${task_id}"
    return 0
}
```

5. **タスク通知機能（`notify_engineer()`）**:

```bash
notify_engineer() {
    local assignee="${1:-}"
    local task_id="${2:-}"

    if [[ -z "$assignee" || -z "$task_id" ]]; then
        log_debug "notify_engineer: missing arguments"
        return 1
    fi

    # エンジニアロールでない場合はスキップ
    if [[ ! "$assignee" =~ ^eng[0-9]+$ ]]; then
        log_debug "Assignee is not an engineer role: ${assignee}"
        return 0
    fi

    # エンジニア番号を抽出（eng1 → 1, eng2 → 2, ...）
    local eng_number="${assignee#eng}"

    # タスクセッションを検索
    local session_name
    session_name=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "claude-task-" | head -1)

    if [[ -z "$session_name" ]]; then
        log_debug "No task session found, skipping notification"
        return 0
    fi

    # ペイン番号（PjMがPane 0、eng1がPane 1、eng2がPane 2、...）
    local pane_index="$eng_number"

    # ペインが存在するか確認
    if ! tmux list-panes -t "$session_name" -F "#{pane_index}" 2>/dev/null | grep -q "^${pane_index}$"; then
        log_debug "Pane ${pane_index} not found in session ${session_name}"
        return 0
    fi

    # タスク詳細を取得
    local task_file
    task_file=$(find_task_file "$task_id")

    local task_type task_desc
    task_type=$(jq -r '.type // "unknown"' "$task_file" 2>/dev/null)
    task_desc=$(jq -r '.description // ""' "$task_file" 2>/dev/null)

    # 通知メッセージを送信
    tmux send-keys -t "${session_name}.${pane_index}" "" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo ''" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo '📋 New task assigned: ${task_id}'" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo 'Type: ${task_type}'" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo 'Description: ${task_desc}'" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo ''" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo 'Run the following to see details:'" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo '  ../../scripts/core/task-manager.sh show ${task_id}'" C-m
    tmux send-keys -t "${session_name}.${pane_index}" "echo ''" C-m

    log_success "Notified ${assignee} about task ${task_id}"
}
```

6. **`assign_task()` での通知呼び出し**:

既存の `assign_task()` 関数を拡張し、割り当て後に通知を送信:

```bash
assign_task() {
    local task_id="${1:-}"
    local assignee="${2:-}"

    # ... 既存の割り当て処理 ...

    # タスク割り当て成功後、エンジニアへ通知
    notify_engineer "$assignee" "$task_id"

    log_success "Task ${task_id} assigned to ${assignee}"
}
```

7. **コマンド追加**:

```bash
main() {
    # ... 既存のコード ...

    local command="${1:-}"
    case "$command" in
        # ... 既存のコマンド ...
        auto-assign)
            auto_assign_task "$2"
            ;;
        list-engineers)
            list_engineers
            ;;
        # ...
    esac
}
```

---

#### Step 6: stop-system.sh での動的worktree削除

**ファイル**: `scripts/stop-system.sh`

**主な変更点**:

```bash
cleanup_worktrees() {
    log_info "Cleaning up git worktrees..."

    # NUM_ENGINEERSが未設定の場合、既存worktreeを検出
    if [[ -z "${NUM_ENGINEERS:-}" ]]; then
        NUM_ENGINEERS=$(find "$WORKTREE_BASE" -maxdepth 1 -type d -name "eng*" | wc -l)
        log_debug "Detected ${NUM_ENGINEERS} worktree(s)"
    fi

    for ((i=1; i<=NUM_ENGINEERS; i++)); do
        local role="eng${i}"
        local worktree_path="${WORKTREE_BASE}/${role}"

        if [[ -d "$worktree_path" ]]; then
            log_info "Removing worktree: ${worktree_path}"
            cd "$TARGET_PROJECT_PATH" || continue
            git worktree remove "$worktree_path" --force || log_warn "Failed to remove worktree: $worktree_path"
            log_success "Removed worktree: ${role}"
        fi
    done
}
```

---

#### Step 7: ドキュメント更新

**ファイル**: `CLAUDE.md`

```markdown
## Development Commands

### System Management

```bash
# Start the orchestrator system (default: 1 engineer)
./scripts/start-system.sh

# Start with 2 engineers
./scripts/start-system.sh --engineers 2

# Start with 3 engineers
./scripts/start-system.sh --engineers 3

# Start with sample tasks
./scripts/start-system.sh --engineers 2 --with-samples

# Stop the system gracefully
./scripts/stop-system.sh
```

### Task Management

```bash
# Auto-assign task to least busy engineer
./scripts/core/task-manager.sh auto-assign <task-id>

# List all engineers and their workload
./scripts/core/task-manager.sh list-engineers
```
```

**ファイル**: `README.md`

```markdown
### Phase 2: 並列開発（現在のバージョン）
- [x] エンジニア数を動的に指定可能（`--engineers N`）
- [x] タスク自動割り当て機能
- [x] コンフリクト検出・解決

#### 使用例

```bash
# 2人のエンジニアで起動
./scripts/start-system.sh --engineers 2

# 3人のエンジニアで起動
./scripts/start-system.sh --engineers 3
```
```

---

### 3.3 テスト計画

#### 3.3.1 単体テスト

1. **エンジニア数バリデーションテスト**
   ```bash
   # エラーケース
   ./scripts/start-system.sh --engineers 0
   # 期待: エラーメッセージ "Engineer count must be at least 1"

   ./scripts/start-system.sh --engineers 11
   # 期待: エラーメッセージ "Engineer count exceeds maximum (10)"

   ./scripts/start-system.sh --engineers abc
   # 期待: エラーメッセージ "Invalid engineer count"
   ```

2. **動的ペイン生成テスト**
   ```bash
   # 1エンジニア（デフォルト）
   ./scripts/start-system.sh
   tmux list-panes -t claude-task-* | wc -l
   # 期待: 2（PjM + eng1）

   # 2エンジニア
   ./scripts/start-system.sh --engineers 2
   tmux list-panes -t claude-task-* | wc -l
   # 期待: 3（PjM + eng1 + eng2）

   # 5エンジニア
   ./scripts/start-system.sh --engineers 5
   tmux list-panes -t claude-task-* | wc -l
   # 期待: 6（PjM + eng1-5）
   ```

3. **動的worktree生成テスト**
   ```bash
   # 3エンジニアで起動
   ./scripts/start-system.sh --engineers 3

   # worktreeが3つ作成されていることを確認
   ls -la worktrees/ | grep eng
   # 期待: eng1, eng2, eng3

   # 各worktreeでブランチを確認
   for i in {1..3}; do
       cd worktrees/eng${i}/[TARGET_PROJECT]
       git branch | grep eng${i}/session-
   done
   # 期待: それぞれのブランチが存在
   ```

4. **タスク自動割り当てテスト**
   ```bash
   # 3エンジニアで起動
   ./scripts/start-system.sh --engineers 3

   # タスクを6つ作成
   for i in {1..6}; do
       ../../scripts/core/task-manager.sh create feature "Task ${i}" "" pjm
   done

   # 自動割り当て
   for task_id in $(../../scripts/core/task-manager.sh list pending | awk '{print $1}'); do
       ../../scripts/core/task-manager.sh auto-assign "$task_id"
   done

   # 負荷状況確認
   ../../scripts/core/task-manager.sh list-engineers
   # 期待: 各エンジニアに2つずつ割り当てられる
   ```

#### 3.3.2 統合テスト

1. **並列実装テスト（3エンジニア）**
   ```bash
   # 3エンジニアで起動
   ./scripts/start-system.sh --engineers 3

   # 異なるタスクを各エンジニアに割り当て
   ../../scripts/core/task-manager.sh create feature "Add auth" eng1 pjm
   ../../scripts/core/task-manager.sh create feature "Add logging" eng2 pjm
   ../../scripts/core/task-manager.sh create feature "Add API" eng3 pjm

   # 各エンジニアペインで同時に実装
   # - eng1: sessions/engineer/配下で作業
   # - eng2: sessions/engineer/配下で作業
   # - eng3: sessions/engineer/配下で作業

   # すべてのタスクが独立して進行することを確認
   ```

2. **コンフリクト検出テスト（全エンジニア横断）**
   ```bash
   # 3エンジニアで起動
   ./scripts/start-system.sh --engineers 3

   # 同じファイルを変更するタスクを作成
   ../../scripts/core/task-manager.sh create feature "Update config (eng1)" eng1 pjm
   ../../scripts/core/task-manager.sh create feature "Update config (eng2)" eng2 pjm

   # タスク実行後、コンフリクト警告が表示されることを確認
   # 期待: "⚠️ Potential conflict detected! File: config.js"
   ```

3. **スケーラビリティテスト**
   ```bash
   # 最大エンジニア数（10人）で起動
   ./scripts/start-system.sh --engineers 10

   # ペイン数確認
   tmux list-panes -t claude-task-* | wc -l
   # 期待: 11（PjM + eng1-10）

   # worktree確認
   ls -la worktrees/ | grep eng | wc -l
   # 期待: 10

   # レイアウトが適切に調整されていることを確認
   tmux list-panes -t claude-task-* -F "#{pane_width}x#{pane_height}"
   ```

---

## 4. リスクと対策

### 4.1 想定されるリスク

| リスク | 影響度 | 対策 |
|--------|--------|------|
| **ファイルコンフリクト** | 高 | 全エンジニア横断のコンフリクト検出機能 |
| **git worktree管理の複雑化** | 中 | 動的worktree削除の自動化 |
| **タスク分配の偏り** | 中 | 負荷ベースの自動割り当てアルゴリズム |
| **ペインレイアウトの見づらさ** | 中 | ペイン数に応じた自動レイアウト最適化 |
| **システムリソース消費** | 中 | MAX_ENGINEERS=10で上限設定 |
| **初期化処理の遅延** | 低 | タイムアウト設定、並列初期化の検討 |

### 4.2 対策の詳細

#### 4.2.1 ファイルコンフリクト対策

- **事前検出**: タスク作成時にPjMが変更対象ファイルを明示
- **実行時警告**: `check_potential_conflicts()` による全エンジニア横断チェック
- **マージ時確認**: masterへのマージ前に `git merge --no-ff --no-commit` で事前確認

#### 4.2.2 git worktree管理

- **自動削除**: セッション終了時に全worktreeを `git worktree remove`
- **定期クリーンアップ**: 週次でorphaned worktreeをクリーンアップ
- **ロックファイル管理**: `.git/worktrees/*/locked` の適切な管理

#### 4.2.3 タスク分配アルゴリズム

- **負荷均等化**: 各エンジニアの現在のタスク数をカウントし、最も少ないエンジニアへ割り当て
- **優先度対応**: 将来的には優先度の高いタスクを経験豊富なエンジニアへ優先割り当て
- **スキルマッチング**: タスクタイプとエンジニアのスキルセットのマッチング（Phase 3以降）

#### 4.2.4 システムリソース対策

- **上限設定**: `MAX_ENGINEERS=10` で上限を設定
- **メモリ監視**: 将来的にはシステムメモリ使用量を監視
- **段階的起動**: エンジニアペインを順次起動（並列起動オプションも検討）

---

## 5. Phase 2完了の定義

以下の条件をすべて満たした時点でPhase 2完了とします:

- [ ] `--engineers N` オプションが動作する
- [ ] エンジニア数のバリデーションが機能する（1 ≤ N ≤ 10）
- [ ] 指定された数のエンジニアペインが自動作成される
- [ ] 各エンジニア用のgit worktreeが自動作成される
- [ ] 複数エンジニアが同時に異なるタスクを実装できる
- [ ] タスク割り当て時にエンジニアペインへ自動通知が送信される
- [ ] タスク自動割り当て機能が動作する（負荷分散）
- [ ] `list-engineers` コマンドで負荷状況を確認できる
- [ ] コンフリクト検出機能が全エンジニア横断で動作する
- [ ] 全エンジニアの変更をmasterへマージできる
- [ ] 動的worktree削除が正常に動作する
- [ ] ドキュメント（CLAUDE.md、README.md）が更新されている
- [ ] 統合テストがすべてパスする（1, 2, 3, 5, 10エンジニア）

---

## 6. Phase 3への準備

Phase 2完了後、Phase 3（レビューワークフロー）に向けて以下を検討:

- **reviewer ペインの追加**
- **タスクステータス `review` の活用**
- **コードレビューワークフロー**（engN → reviewer → master）
- **自動テスト統合**（レビュー前にテスト実行）

---

## 7. 参考情報

### 7.1 関連ドキュメント

- `docs/001-new-architecture.md` - v0.2.0アーキテクチャ設計
- `docs/003-target-project-integration-fix.md` - git worktree統合
- `CLAUDE.md` - 開発ガイドライン

### 7.2 実装スケジュール（目安）

- **Step 1**: 設定ファイル拡張（30分）
- **Step 2**: start-system.sh オプション追加（1時間）
- **Step 3**: task-session.sh 動的生成（2-3時間）
- **Step 4**: pane-manager.sh 汎用化（1-2時間）
- **Step 5**: task-manager.sh N人対応（2-3時間）
- **Step 6**: stop-system.sh 動的削除（30分）
- **Step 7**: ドキュメント・テスト（1-2時間）
- **合計**: 8-12時間程度

---

## 8. 実装例: コマンドフロー

### 8.1 基本的な使用例（PjM主導型）⭐ 推奨

```bash
# 1. システム起動（2エンジニア）
./scripts/start-system.sh --engineers 2

# 2. PjMペインで負荷状況確認
../../scripts/core/task-manager.sh list-engineers
# 出力例:
# Engineer   | Pending    | In Progress
# ----------------------------------------
# eng1       | 0          | 0
# eng2       | 0          | 0

# 3. PjMがタスク分割・割り当て（担当者を指定）
../../scripts/core/task-manager.sh create feature "Add user auth" eng1 pjm
# → eng1ペインに自動通知:
#    📋 New task assigned: task-20251102-abc123
#    Type: feature
#    Description: Add user auth

../../scripts/core/task-manager.sh create feature "Add logging system" eng2 pjm
# → eng2ペインに自動通知

../../scripts/core/task-manager.sh create bug "Fix login bug" eng1 pjm
# → eng1ペインに自動通知

# 4. 各エンジニアが通知を受け取り、実装開始
# eng1ペイン: タスク詳細確認
../../scripts/core/task-manager.sh show task-20251102-abc123
# → 実装開始

# eng2ペイン: タスク詳細確認
../../scripts/core/task-manager.sh show task-20251102-def456
# → 実装開始

# 5. PjMが進捗監視
../../scripts/core/task-manager.sh list-engineers
# 出力例:
# Engineer   | Pending    | In Progress
# ----------------------------------------
# eng1       | 1          | 1
# eng2       | 0          | 1

# 6. システム停止（worktree自動削除）
./scripts/stop-system.sh
```

### 8.2 自動割り当ての使用例

```bash
# 1. システム起動（2エンジニア）
./scripts/start-system.sh --engineers 2

# 2. タスク作成（担当者未指定）
../../scripts/core/task-manager.sh create feature "User auth" "" pjm
../../scripts/core/task-manager.sh create feature "Logging system" "" pjm
../../scripts/core/task-manager.sh create bug "Fix login bug" "" pjm

# 3. タスク自動割り当て
../../scripts/core/task-manager.sh auto-assign task-xxx-001
# → 最も負荷が少ないeng1に割り当て＆通知

../../scripts/core/task-manager.sh auto-assign task-xxx-002
# → eng2に割り当て＆通知

../../scripts/core/task-manager.sh auto-assign task-xxx-003
# → eng1に割り当て＆通知

# 4. エンジニア負荷状況確認
../../scripts/core/task-manager.sh list-engineers
# 出力例:
# Engineer   | Pending    | In Progress
# ----------------------------------------
# eng1       | 2          | 0
# eng2       | 1          | 0

# 5. 各エンジニアが実装開始
# (各ペインで自動的にタスクが通知済み)

# 6. システム停止（worktree自動削除）
./scripts/stop-system.sh
```

### 8.3 大規模プロジェクト例（5エンジニア）

```bash
# 5エンジニアで起動
./scripts/start-system.sh --engineers 5

# タスク大量作成
for i in {1..15}; do
    ../../scripts/core/task-manager.sh create feature "Feature ${i}" "" pjm
done

# 一括自動割り当て
for task_id in $(../../scripts/core/task-manager.sh list pending | awk '{print $1}'); do
    ../../scripts/core/task-manager.sh auto-assign "$task_id"
done

# 負荷状況確認
../../scripts/core/task-manager.sh list-engineers
# 期待: 各エンジニアに3つずつ均等に割り当てられる
```

---

**以上、Phase 2: 並列エンジニアリング詳細設計書でした！** 🎉
