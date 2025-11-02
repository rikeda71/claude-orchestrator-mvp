# 003: Target Project Integration Fix

## 問題

現在のv0.2.0実装では、エンジニアが orchestrator 内の `worktrees/` ディレクトリで作業しているため、外部プロジェクト（target project）の管理ができていない。

### 現状の動作

1. `WORKTREE_BASE` のデフォルト値: `${ORCHESTRATOR_ROOT}/worktrees`
2. エンジニアの作業ディレクトリ: `${WORKTREE_BASE}/eng1/` = `orchestrator/worktrees/eng1/`
3. Git worktree が作成されていない（TODO コメントのみ）
4. TARGET_PROJECT_PATH が設定されていても使われていない

### 期待される動作

1. `TARGET_PROJECT_PATH` が設定されている場合、そのプロジェクトで作業する
2. エンジニアは target project の git worktree で作業する
3. Target project のコードを読み書きできる
4. Target project にコミット・ブランチ作成ができる

## 解決方針

### 1. ワークツリーベースの決定ロジック変更

`common.sh` の `load_config()` で、TARGET_PROJECT_PATH が設定されている場合の処理を追加：

```bash
load_config() {
    # ... 既存の設定読み込み ...

    # TARGET_PROJECT_PATHが設定されている場合、WORKTREE_BASEを調整
    if [[ -n "${TARGET_PROJECT_PATH:-}" ]] && [[ -d "${TARGET_PROJECT_PATH}" ]]; then
        # Target projectが存在する場合、そのプロジェクト内にworktreeを作成
        if [[ -z "${WORKTREE_BASE:-}" ]]; then
            WORKTREE_BASE="${TARGET_PROJECT_PATH}/.orchestrator-worktrees"
        fi
    else
        # Target projectがない場合、orchestrator内のworktreeを使用
        WORKTREE_BASE="${WORKTREE_BASE:-$DEFAULT_WORKTREE_BASE}"
    fi
}
```

### 2. Git Worktree 自動作成

`task-session.sh` の `create_eng1_pane()` で、git worktree を自動作成する：

```bash
create_eng1_pane() {
    local session_name="$1"
    local task_id="$2"
    local eng1_workdir
    eng1_workdir=$(get_pane_workdir "eng1")

    log_debug "Creating eng1 pane..."

    # 右側70%で垂直分割
    tmux split-window -h -t "$session_name" -p 70

    # eng1ワークツリーの確認・作成
    if [[ ! -d "$eng1_workdir" ]]; then
        log_info "Creating eng1 worktree for task: ${task_id}..."

        if [[ -n "${TARGET_PROJECT_PATH:-}" ]] && [[ -d "${TARGET_PROJECT_PATH}" ]]; then
            # Target projectのgit worktreeを作成
            create_git_worktree "eng1" "$task_id" "$eng1_workdir"
        else
            # Standalone mode: 単純なディレクトリ作成
            mkdir -p "$eng1_workdir"
            log_warn "No target project configured, working in standalone mode"
        fi
    fi

    # ... 残りの処理 ...
}
```

### 3. Git Worktree 作成関数

新しいヘルパー関数を `task-session.sh` に追加：

```bash
#
# Git worktreeの作成
#
create_git_worktree() {
    local role="$1"
    local task_id="$2"
    local worktree_path="$3"

    # Target projectのメインブランチを確認
    local main_branch="${TARGET_PROJECT_MAIN_BRANCH:-main}"

    # ブランチ名を生成
    local branch_prefix
    case "$role" in
        eng1)
            branch_prefix="${ENG1_BRANCH_PREFIX:-eng1/feature}"
            ;;
        eng2)
            branch_prefix="${ENG2_BRANCH_PREFIX:-eng2/feature}"
            ;;
        *)
            log_error "Unknown role: ${role}"
            return 1
            ;;
    esac

    local branch_name="${branch_prefix}/${task_id}"

    log_info "Creating git worktree: ${worktree_path}"
    log_debug "Branch: ${branch_name}"
    log_debug "Base: ${main_branch}"

    # Target projectディレクトリに移動
    cd "${TARGET_PROJECT_PATH}"

    # Worktreeを作成（ブランチも同時に作成）
    if git worktree add -b "$branch_name" "$worktree_path" "$main_branch" 2>/dev/null; then
        log_success "Git worktree created: ${worktree_path}"
    else
        # ブランチが既に存在する場合
        log_warn "Branch ${branch_name} already exists, using existing branch"
        git worktree add "$worktree_path" "$branch_name" 2>/dev/null || {
            log_error "Failed to create worktree"
            return 1
        }
    fi

    # オーケストレータルートに戻る
    cd "${ORCHESTRATOR_ROOT}"
}
```

### 4. Worktree クリーンアップ

`stop-system.sh` に worktree 削除機能を追加：

```bash
cleanup_worktrees() {
    local task_id="$1"

    if [[ -z "${TARGET_PROJECT_PATH:-}" ]]; then
        return 0
    fi

    log_info "Cleaning up worktrees for task: ${task_id}..."

    for role in eng1 eng2; do
        local worktree_path="${WORKTREE_BASE}/${role}"

        if [[ -d "$worktree_path" ]]; then
            log_info "Removing worktree: ${worktree_path}"

            cd "${TARGET_PROJECT_PATH}"
            git worktree remove "$worktree_path" --force 2>/dev/null || {
                log_warn "Failed to remove worktree: ${worktree_path}"
                log_info "You may need to manually remove it"
            }
            cd "${ORCHESTRATOR_ROOT}"
        fi
    done
}
```

### 5. .gitignore 設定

Target project 側の `.gitignore` に worktree ディレクトリを追加する必要がある：

```gitignore
# Claude Orchestrator worktrees
.orchestrator-worktrees/
```

## 実装の流れ

### Phase 1: 設定とディレクトリ管理

1. `config/target-project.conf` を設定
   - `TARGET_PROJECT_PATH` を nextjs-dashboard に設定
   - `TARGET_PROJECT_MAIN_BRANCH` を確認

2. `common.sh` の `load_config()` を修正
   - TARGET_PROJECT_PATH ベースの WORKTREE_BASE 決定ロジック追加

3. `start-system.sh` の `init_directories()` を修正
   - Target project 配下の worktree ディレクトリ作成

### Phase 2: Git Worktree 管理

1. `task-session.sh` に `create_git_worktree()` 関数追加

2. `create_eng1_pane()` を修正
   - git worktree 自動作成を実装
   - standalone mode のフォールバック処理

3. `stop-system.sh` に `cleanup_worktrees()` 追加
   - タスク完了時の worktree 削除

### Phase 3: テスト

1. nextjs-dashboard で設定
2. タスク作成 → セッション起動
3. eng1 ペインが nextjs-dashboard の worktree で起動することを確認
4. ファイル読み書きのテスト
5. Git 操作のテスト（branch, commit）
6. セッション停止 → worktree 削除の確認

## 制約事項

### Target Project 要件

- Git リポジトリである必要がある
- メインブランチ（main/master）が存在する
- Worktree 作成用の十分なディスク容量がある

### Standalone Mode

TARGET_PROJECT_PATH が設定されていない場合：
- `orchestrator/worktrees/` で作業（現行動作）
- Git worktree は作成されない
- シンプルなディレクトリとして動作

### Phase 2 との関係

Phase 2（動的エンジニア数）実装時：
- `create_git_worktree()` は eng2, eng3... にも対応
- Worktree クリーンアップは全エンジニアに対応
- ブランチ名プレフィックスは動的に設定可能にする

## セキュリティ考慮事項

1. **Target project の検証**
   - TARGET_PROJECT_PATH のパス検証
   - Git リポジトリであることの確認
   - 書き込み権限の確認

2. **Worktree の隔離**
   - 各エンジニアは独立した worktree で作業
   - ブランチの命名規則で衝突を防止
   - タスク完了時の確実なクリーンアップ

3. **.gitignore 必須**
   - Target project に `.orchestrator-worktrees/` を追加
   - 誤コミットを防止

## 成功基準

- [x] TARGET_PROJECT_PATH 設定が反映される
- [x] エンジニアペインが target project の worktree で起動する
- [x] Target project のファイル読み書きができる
- [x] Git ブランチが自動作成される
- [ ] コミット・プッシュができる（手動テスト必要）
- [x] セッション停止時に worktree が削除される
- [x] nextjs-dashboard でのテストが成功する

## 参考

- Git worktree documentation: https://git-scm.com/docs/git-worktree
- Phase 2 design: docs/002-phase2-parallel-engineering.md
- CLAUDE.md: Document-driven development workflow
