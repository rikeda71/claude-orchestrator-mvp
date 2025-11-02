# 002: Phase 2 - Parallel Engineering (v0.3.0)

## ドキュメント情報

- **Phase**: 2
- **Version**: v0.3.0
- **Status**: Design
- **Created**: 2025-11-02
- **Author**: Claude Code

## 概要

Phase 2では、エンジニアペインを動的に追加して複数のエンジニアが並列で作業できるようにします。
エンジニアの数は起動時に指定可能で、1〜N人まで柔軟に対応します。

## 目標

1. **動的エンジニアペイン**: 起動時に`--engineers N`でエンジニア数を指定
2. **並列タスク管理**: 複数タスクの同時実行をサポート
3. **協調ワークフロー**: PjMが複数エンジニアを調整

## アーキテクチャ

### セッション構造（動的）

#### 1人のエンジニア（Phase 1）
```
Session: claude-task-{task-id}
┌─────────────────────────────────────────────────┐
│ Window: {task-id}-orchestrator                  │
├────────────────┬────────────────────────────────┤
│ Pane 0 (30%)   │  Pane 1 (eng1) - 70%          │
│                │                                │
│  PjM           │  (自動実行モード)              │
└────────────────┴────────────────────────────────┘
```

#### 2人のエンジニア
```
Session: claude-task-{task-id}
┌─────────────────────────────────────────────────┐
│ Window: {task-id}-orchestrator                  │
├────────────────┬────────────────────────────────┤
│ Pane 0 (30%)   │  Pane 1 (eng1) - 35%          │
│                ├────────────────────────────────┤
│  PjM           │  Pane 2 (eng2) - 35%          │
│  (通常モード)   │                                │
│                │  (両方とも自動実行モード)       │
└────────────────┴────────────────────────────────┘
```

#### 3人のエンジニア
```
Session: claude-task-{task-id}
┌─────────────────────────────────────────────────┐
│ Window: {task-id}-orchestrator                  │
├────────────────┬────────────────────────────────┤
│ Pane 0 (30%)   │  Pane 1 (eng1) - 23%          │
│                ├────────────────────────────────┤
│  PjM           │  Pane 2 (eng2) - 23%          │
│  (通常モード)   ├────────────────────────────────┤
│                │  Pane 3 (eng3) - 24%          │
│                │                                │
│                │  (全て自動実行モード)           │
└────────────────┴────────────────────────────────┘
```

### ペイン配置の計算

```bash
# エンジニア数からペインの高さを計算
calculate_engineer_pane_height() {
    local num_engineers="$1"
    # 右側70%を均等分割
    echo $((100 / num_engineers))
}
```

## 実装計画

### 1. task-session.sh の拡張

動的にエンジニアペインを追加する機能を実装：

```bash
#
# エンジニアペインを動的に追加
#
create_engineer_panes() {
    local session_name="$1"
    local task_id="$2"
    local num_engineers="${3:-1}"  # デフォルトは1人

    # eng1は既に create_task_session() で作成済み
    # eng2以降を追加

    for ((i=2; i<=num_engineers; i++)); do
        local role="eng${i}"
        local pane_id="$i"

        log_info "Creating ${role} pane..."

        # Pane 1を垂直分割
        tmux split-window -v -t "${session_name}.1"

        # 作業ディレクトリ
        local workdir="${WORKTREE_BASE}/${role}"

        # ディレクトリ作成
        if [[ ! -d "$workdir" ]]; then
            log_info "Creating ${role} worktree..."
            mkdir -p "$workdir"
        fi

        # 作業ディレクトリへ移動
        tmux send-keys -t "${session_name}.${pane_id}" "cd ${workdir}" C-m

        # 環境変数設定
        tmux send-keys -t "${session_name}.${pane_id}" "export TASK_ID=${task_id}" C-m
        tmux send-keys -t "${session_name}.${pane_id}" "export ENGINEER_ROLE=${role}" C-m
        tmux send-keys -t "${session_name}.${pane_id}" "export WORK_DIR=${workdir}" C-m
        tmux send-keys -t "${session_name}.${pane_id}" "export PANE_ID=${pane_id}" C-m

        # Claude自動実行モードで起動
        log_debug "Starting Claude in ${role} pane (auto-execution mode)..."
        tmux send-keys -t "${session_name}.${pane_id}" "claude --dangerously-skip-permissions" C-m

        log_success "${role} pane created"
    done

    # ペインレイアウトを調整（均等分割）
    if [[ $num_engineers -gt 1 ]]; then
        tmux select-layout -t "$session_name" main-vertical
    fi
}
```

### 2. start-system.sh の拡張

`--engineers N`オプションを追加：

```bash
main() {
    local task_id=""
    local auto_attach="true"
    local num_engineers=1  # デフォルトは1人

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --engineers|-e)
                num_engineers="$2"
                if [[ ! "$num_engineers" =~ ^[0-9]+$ ]] || [[ $num_engineers -lt 1 ]]; then
                    log_error "Invalid number of engineers: ${num_engineers}"
                    exit 1
                fi
                shift 2
                ;;
            --no-attach)
                auto_attach="false"
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: $0 [task-id] [options]

Arguments:
  task-id           タスクID（オプション）
                    指定しない場合はデフォルトタスクを作成

Options:
  --engineers, -e N エンジニア数を指定（デフォルト: 1）
  --no-attach       セッションに自動アタッチしない
  --help, -h        このヘルプメッセージを表示

Examples:
  # 1人のエンジニアで起動（デフォルト）
  $0 task-001

  # 2人のエンジニアで起動
  $0 task-001 --engineers 2

  # 3人のエンジニアで起動
  $0 task-001 -e 3
EOF
                exit 0
                ;;
            # ... 他のオプション
        esac
    done

    # ... 初期化処理 ...

    # タスクセッション起動
    start_task_session "$task_id" "$num_engineers"

    # ... 残りの処理 ...
}

#
# タスクセッションの起動（エンジニア数を指定）
#
start_task_session() {
    local task_id="$1"
    local num_engineers="${2:-1}"

    log_info "Starting task session for: ${task_id} with ${num_engineers} engineer(s)"

    # タスクセッションが既に存在する場合はエラー
    if "$TASK_SESSION" exists "$task_id" 2>/dev/null; then
        log_error "Task session already running: ${task_id}"
        log_info "Attach to existing session with:"
        echo "  tmux attach -t ${TMUX_SESSION_PREFIX}-task-${task_id}"
        return 1
    fi

    # タスクセッション作成（エンジニア数を渡す）
    "$TASK_SESSION" create "$task_id" "$num_engineers"

    log_success "Task session started: ${task_id} with ${num_engineers} engineer(s)"
}
```

### 3. pane-manager.sh の拡張

エンジニア全体への一斉送信機能：

```bash
#
# 全エンジニアペインに送信
#
send_to_all_engineers() {
    local task_id="$1"
    local message="$2"
    local session_name
    session_name=$(get_task_session_name "$task_id")

    if ! tmux_session_exists "$session_name"; then
        log_error "Task session does not exist: ${session_name}"
        return 1
    fi

    # ペイン数を取得
    local pane_count
    pane_count=$(tmux list-panes -t "$session_name" 2>/dev/null | wc -l | tr -d ' ')

    # Pane 0（PjM）以外の全ペインに送信
    log_info "Sending message to all engineers..."
    for ((i=1; i<pane_count; i++)); do
        log_debug "Sending to pane ${i}..."
        tmux send-keys -t "${session_name}.${i}" "$message" C-m
    done

    log_success "Message sent to $((pane_count - 1)) engineer(s)"
}

#
# 特定のエンジニアに送信（役割名で指定）
#
send_to_engineer() {
    local task_id="$1"
    local role="$2"      # eng1, eng2, eng3, ...
    local message="$3"

    # 役割名からペインIDを計算
    local pane_id="${role#eng}"  # "eng1" -> "1"

    send_to_pane "$task_id" "$pane_id" "$message"
}
```

コマンドラインインターフェースを更新：

```bash
main() {
    local command="${1:-}"

    case "$command" in
        send-all-engineers)
            local task_id="${2:-}"
            local message="${3:-}"

            if [[ -z "$task_id" ]] || [[ -z "$message" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 send-all-engineers <task-id> <message>"
                exit 1
            fi

            send_to_all_engineers "$task_id" "$message"
            ;;
        send-engineer)
            local task_id="${2:-}"
            local role="${3:-}"
            local message="${4:-}"

            if [[ -z "$task_id" ]] || [[ -z "$role" ]] || [[ -z "$message" ]]; then
                log_error "Missing arguments"
                echo "Usage: $0 send-engineer <task-id> <role> <message>"
                exit 1
            fi

            send_to_engineer "$task_id" "$role" "$message"
            ;;
        # ... 既存のコマンド ...
    esac
}
```

### 4. 新しいプロンプト

`sessions/pjm/init-prompt-v0.3.0.txt`:
```
あなたはプロジェクトマネージャー（PjM）です。

【v0.3.0 アーキテクチャ】
このセッションは複数エンジニアをサポートします。
- エンジニア数: ${NUM_ENGINEERS}人（環境変数で確認可能）
- ペイン0: PjM（あなた）
- ペイン1〜N: eng1〜engN（自動実行モード）

【エンジニアへの指示方法】

# 特定のエンジニアに指示
../../scripts/core/pane-manager.sh send-engineer ${TASK_ID} eng1 "認証機能を実装してください"
../../scripts/core/pane-manager.sh send-engineer ${TASK_ID} eng2 "プロフィールページを実装してください"

# 全エンジニアに一斉指示
../../scripts/core/pane-manager.sh send-all-engineers ${TASK_ID} "コーディング規約を確認してください"

# 個別ペイン指定（ペインIDで）
../../scripts/core/pane-manager.sh send ${TASK_ID} 1 "Task Aを実装"
../../scripts/core/pane-manager.sh send ${TASK_ID} 2 "Task Bを実装"
```

## ワークフロー

### 基本的な流れ

1. **タスク作成**
```bash
./scripts/core/task-manager.sh create feature "User authentication" eng1 pjm
./scripts/core/task-manager.sh create feature "User profile page" eng2 pjm
```

2. **システム起動（エンジニア数指定）**
```bash
# 2人のエンジニアで起動
./scripts/start-system.sh task-001 --engineers 2

# 3人のエンジニアで起動
./scripts/start-system.sh task-001 -e 3
```

3. **PjMから指示**
```bash
# eng1への指示
./scripts/core/pane-manager.sh send-engineer task-001 eng1 "ユーザー認証機能を実装してください"

# eng2への指示
./scripts/core/pane-manager.sh send-engineer task-001 eng2 "ユーザープロフィールページを実装してください"

# 全員に一斉通知
./scripts/core/pane-manager.sh send-all-engineers task-001 "ランチ休憩を取りましょう"
```

4. **進捗確認**
```bash
# eng1の出力確認
./scripts/core/pane-manager.sh capture task-001 1 50

# eng2の出力確認
./scripts/core/pane-manager.sh capture task-001 2 50

# 全ペイン一覧
./scripts/core/pane-manager.sh list task-001
```

## Git Worktree管理

### 動的Worktree構造

```
worktrees/
├── eng1/          # eng1用のworktree
├── eng2/          # eng2用のworktree
├── eng3/          # eng3用のworktree（必要に応じて）
└── ...
```

各エンジニア用のworktreeディレクトリは起動時に自動作成されます。

### ブランチ戦略

```bash
# 各エンジニアのブランチ
eng1/feature/task-001
eng2/feature/task-002
eng3/feature/task-003

# またはタスクベース
feature/task-001  # eng1担当
feature/task-002  # eng2担当
feature/task-003  # eng3担当
```

## タスク管理の拡張

### 動的なタスク割り当て

```bash
# エンジニアの数に応じて割り当て
for i in {1..3}; do
    ./scripts/core/task-manager.sh create feature "Task ${i}" "eng${i}" pjm
done
```

## PjMの役割

複数エンジニア管理でのPjMの責務：

1. **タスクの割り当て**
   - N人のエンジニアに効率的に分配
   - 依存関係とスキルを考慮

2. **リソース配分**
   - 負荷の均等化
   - ボトルネックの解消

3. **調整とサポート**
   - エンジニア間のコンフリクト調整
   - 質問への回答

4. **品質管理**
   - 各エンジニアの成果物確認
   - 統合テストの実施

## スケーラビリティ

### 推奨エンジニア数

- **1人**: シンプルなタスク、学習目的
- **2人**: 標準的な並列開発
- **3人**: 複雑なプロジェクト
- **4人以上**: 大規模プロジェクト（画面サイズに注意）

### 制約事項

- **画面サイズ**: エンジニア数が多いとペインが小さくなる
- **tmux制限**: ペイン数の物理的制限
- **Claude API**: 同時実行数の制限

## テスト計画

### 1. 動的ペイン追加のテスト

```bash
# 1人で起動
./scripts/start-system.sh task-001
./scripts/core/pane-manager.sh list task-001
# 期待: Pane 0, 1

# 3人で起動
./scripts/start-system.sh task-002 --engineers 3
./scripts/core/pane-manager.sh list task-002
# 期待: Pane 0, 1, 2, 3
```

### 2. 一斉送信のテスト

```bash
# 3人で起動
./scripts/start-system.sh task-001 -e 3

# 全員に送信
./scripts/core/pane-manager.sh send-all-engineers task-001 "echo 'Hello from PjM'"

# 各ペインの出力確認
for i in {1..3}; do
    ./scripts/core/pane-manager.sh capture task-001 $i 5
done
```

### 3. 役割名指定のテスト

```bash
# 役割名で指定
./scripts/core/pane-manager.sh send-engineer task-001 eng1 "Task A"
./scripts/core/pane-manager.sh send-engineer task-001 eng2 "Task B"
./scripts/core/pane-manager.sh send-engineer task-001 eng3 "Task C"
```

## マイルストーン

### M1: 動的ペイン追加
- [ ] task-session.shにcreate_engineer_panes()実装
- [ ] start-system.shに--engineers オプション追加
- [ ] 動的ペイン追加のテスト

### M2: ペイン通信の拡張
- [ ] pane-manager.shにsend-all-engineers実装
- [ ] pane-manager.shにsend-engineer実装
- [ ] 役割名指定のテスト

### M3: プロンプト更新
- [ ] sessions/pjm/init-prompt-v0.3.0.txt作成
- [ ] sessions/engineer/init-prompt-v0.3.0.txt更新
- [ ] プロンプトのテスト

### M4: ドキュメントと例
- [ ] README更新（Phase 2の説明）
- [ ] サンプルワークフローの追加
- [ ] スケーラビリティガイド

## 実装の優先順位

1. **High**: 動的ペイン追加（M1）
2. **High**: 一斉送信機能（M2）
3. **Medium**: 役割名指定（M2）
4. **Low**: プロンプト更新（M3）

## 次のフェーズへの準備

Phase 3 (v0.4.0) では：
- reviewerペインの追加
- 自動レビューワークフロー
- N人のエンジニア → 1人のreviewer → PjM承認

## 改訂履歴

| バージョン | 日付 | 変更内容 |
|-----------|------|---------|
| 002-0.1.0 | 2025-11-02 | Phase 2設計書初版（動的エンジニア数対応） |

---

**Document Version**: 002-0.1.0
**Last Updated**: 2025-11-02
**Author**: Claude Code (Phase 2 Planning)
