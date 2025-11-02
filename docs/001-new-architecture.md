# 新アーキテクチャ設計書 v0.2.0

## ドキュメント情報

- **作成日**: 2025-11-02
- **対象バージョン**: 0.2.0
- **前バージョン**: 0.1.3（複数セッション方式）
- **目的**: タスクごとに1セッション+ペイン分割方式への移行

## 1. 設計変更の背景

### 1.1 現行アーキテクチャ（v0.1.x）の課題

```
【現行: 複数セッション方式】
claude-pjm    (独立セッション)
claude-eng1   (独立セッション)
claude-eng2   (独立セッション)
...

課題:
1. セッション間の通信が複雑（ファイルベース + named pipes）
2. セッションのネスト問題（ビューアで発生）
3. 全体を一目で見るには別のビューアセッションが必要
4. 通信レイヤーの保守コストが高い
```

### 1.2 新アーキテクチャ（v0.2.0）の方針

```
【新設計: タスクセッション + ペイン分割方式】
claude-task-001
├── Pane 0: PjM
├── Pane 1: eng1
├── Pane 2: eng2    (Phase 2以降)
├── Pane 3: reviewer (Phase 3以降)
└── Pane 4: docs    (Phase 4以降)

メリット:
1. 通信が単純化（tmux send-keys）
2. ネスト問題なし（1セッション内で完結）
3. 全体が一目で見える（tmux attach一発）
4. 保守が容易
```

## 2. 新アーキテクチャ詳細

### 2.1 セッション構造

#### Phase 1 MVP (v0.2.0)

```
Session: claude-task-001
┌─────────────────────────────────────────────────┐
│ Window: task-001-orchestrator                   │
├────────────────┬────────────────────────────────┤
│ Pane 0 (30%)   │  Pane 1 (70%)                  │
│                │                                 │
│  PjM           │  eng1                          │
│  (claude)      │  (claude --dangerously-skip-   │
│                │   permissions)                  │
│                │                                 │
│  役割:         │  役割:                         │
│  - タスク管理  │  - 実装担当                    │
│  - 指示送信    │  - 自動実行                    │
│  - 進捗監視    │                                │
└────────────────┴────────────────────────────────┘
```

#### Phase 2以降の拡張

```
Session: claude-task-001
┌─────────────────────────────────────────────────┐
│ Window: task-001-orchestrator                   │
├────────────────┬────────────────────────────────┤
│ Pane 0 (30%)   │  Pane 1 (eng1)                 │
│                ├────────────────────────────────┤
│  PjM           │  Pane 2 (eng2)                 │
│                ├────────────────────────────────┤
│                │  Pane 3 (reviewer)             │
│                ├────────────────────────────────┤
│                │  Pane 4 (docs)                 │
└────────────────┴────────────────────────────────┘
```

### 2.2 通信方式

#### 基本的な通信パターン

```bash
# PjMペイン → eng1ペインへ指示送信
tmux send-keys -t claude-task-001.1 \
  "タスクtask-001を実装してください: ユーザー認証機能を追加" C-m

# eng1ペイン → PjMペインへ報告
tmux send-keys -t claude-task-001.0 \
  "実装が完了しました。レビューをお願いします。" C-m
```

#### 通信プロトコル

**コマンド形式**:
```bash
tmux send-keys -t <session>.<pane> "<message>" C-m
```

**セッション・ペイン命名規則**:
- セッション名: `claude-task-<task-id>` (例: `claude-task-001`)
- ペイン番号:
  - `0`: PjM
  - `1`: eng1
  - `2`: eng2 (Phase 2以降)
  - `3`: reviewer (Phase 3以降)
  - `4`: docs (Phase 4以降)

### 2.3 自動実行の仕組み

#### Claude Code起動方法

```bash
# PjMペイン（通常起動）
claude

# その他のペイン（自動実行モード）
claude --dangerously-skip-permissions
```

#### ワークフロー例

```
1. PjMがタスクファイル（task-001.json）を読み込み
   ↓
2. PjMがeng1ペインに指示を送信
   tmux send-keys -t claude-task-001.1 "実装開始: 認証機能追加" C-m
   ↓
3. eng1ペインが自動で実装開始（--dangerously-skip-permissions）
   ↓
4. eng1が完了したらPjMに報告
   tmux send-keys -t claude-task-001.0 "実装完了" C-m
   ↓
5. PjMがタスクステータスを更新
```

### 2.4 タスクライフサイクル

```
[タスク作成]
    ↓
./scripts/core/task-manager.sh create feature "認証機能"
→ tasks/queue/task-001.json 作成
    ↓
[タスクセッション起動]
    ↓
./scripts/start-system.sh task-001
→ claude-task-001 セッション作成
→ PjMペイン + eng1ペイン立ち上げ
    ↓
[PjMが指示送信]
    ↓
PjMペインでタスク割り当て
→ tmux send-keys でeng1に指示
    ↓
[eng1が実装]
    ↓
eng1ペインで自動実行
    ↓
[完了報告]
    ↓
eng1 → PjMに報告
PjMがタスクステータス更新
    ↓
[セッション終了]
    ↓
./scripts/stop-system.sh task-001
```

## 3. 実装詳細

### 3.1 新規スクリプト

#### `scripts/core/task-session.sh`

**目的**: タスクセッション（tmux）の作成・管理

**主要機能**:
```bash
# セッション作成
create_task_session() {
    local task_id="$1"
    local session_name="claude-task-${task_id}"

    # セッション作成
    tmux new-session -d -s "$session_name" -n "${task_id}-orchestrator"

    # PjMペインでClaude起動
    tmux send-keys -t "${session_name}.0" "cd ${PJM_WORKDIR}" C-m
    tmux send-keys -t "${session_name}.0" "claude" C-m

    # eng1ペイン作成
    tmux split-window -h -t "$session_name" -p 70
    tmux send-keys -t "${session_name}.1" "cd ${ENG1_WORKDIR}" C-m
    tmux send-keys -t "${session_name}.1" "claude --dangerously-skip-permissions" C-m
}

# セッション削除
kill_task_session() {
    local task_id="$1"
    local session_name="claude-task-${task_id}"
    tmux kill-session -t "$session_name"
}

# セッション一覧
list_task_sessions() {
    tmux list-sessions | grep "^claude-task-"
}

# セッションにアタッチ
attach_task_session() {
    local task_id="$1"
    local session_name="claude-task-${task_id}"
    tmux attach-session -t "$session_name"
}
```

#### `scripts/core/pane-manager.sh`

**目的**: ペインの追加・削除・通信管理

**主要機能**:
```bash
# ペイン追加（Phase 2以降）
add_pane() {
    local session_name="$1"
    local role="$2"  # eng2, reviewer, docs
    local pane_id="$3"

    # 水平分割でペイン追加
    tmux split-window -v -t "$session_name"

    # Claudeを自動実行モードで起動
    local workdir=$(get_role_workdir "$role")
    tmux send-keys -t "${session_name}.${pane_id}" "cd ${workdir}" C-m
    tmux send-keys -t "${session_name}.${pane_id}" \
        "claude --dangerously-skip-permissions" C-m
}

# ペイン間通信
send_to_pane() {
    local session_name="$1"
    local pane_id="$2"
    local message="$3"

    tmux send-keys -t "${session_name}.${pane_id}" "$message" C-m
}

# ペイン出力のキャプチャ
capture_pane_output() {
    local session_name="$1"
    local pane_id="$2"
    local lines="${3:-100}"

    tmux capture-pane -t "${session_name}.${pane_id}" -p -S -"$lines"
}
```

### 3.2 変更するスクリプト

#### `scripts/start-system.sh`

**変更内容**:
```bash
# 旧: 複数セッション起動
start_sessions() {
    for role in pjm eng1; do
        create_session "$role"
    done
}

# 新: タスクセッション起動
start_task_session() {
    local task_id="${1:-default}"

    # タスクセッション作成
    create_task_session "$task_id"

    # 少し待機
    sleep 2

    # 初期プロンプト送信
    send_init_prompts "$task_id"
}

# 使用例
# ./scripts/start-system.sh task-001
```

#### `scripts/stop-system.sh`

**変更内容**:
```bash
# 旧: 全セッション停止
stop_sessions() {
    for role in pjm eng1 eng2 reviewer docs; do
        kill_session "$role"
    done
}

# 新: タスクセッション停止
stop_task_session() {
    local task_id="${1:-}"

    if [[ -n "$task_id" ]]; then
        # 特定タスクセッションのみ停止
        kill_task_session "$task_id"
    else
        # 全タスクセッション停止
        list_task_sessions | while read session; do
            tmux kill-session -t "$session"
        done
    fi
}

# 使用例
# ./scripts/stop-system.sh task-001    # 特定タスクのみ
# ./scripts/stop-system.sh             # 全タスク
```

### 3.3 削除するスクリプト

以下のスクリプトは不要になるため削除:
- `scripts/core/viewer.sh` - 1セッションで全体が見えるため不要
- `scripts/start-viewer.sh` - 同上
- `scripts/core/messenger.sh` - tmux send-keysで代替

以下は大幅に簡素化:
- `scripts/core/session-manager.sh` → `scripts/core/task-session.sh`

### 3.4 セッション初期化プロンプト

#### PjMペイン用プロンプト

**場所**: `sessions/pjm/init-prompt-v2.txt`

```markdown
# Claude Orchestrator - Project Manager (PjM)

あなたはプロジェクトマネージャー（PjM）です。タスクを管理し、エンジニアに指示を出します。

## 環境情報

- セッション名: claude-task-{TASK_ID}
- あなたのペイン: 0 (左側30%)
- 作業ディレクトリ: {ORCHESTRATOR_ROOT}/sessions/pjm/

## 利用可能なコマンド

### タスク管理
```bash
# タスク詳細表示
../../scripts/core/task-manager.sh show {TASK_ID}

# タスクステータス更新
../../scripts/core/task-manager.sh update {TASK_ID} status <status>

# コメント追加
../../scripts/core/task-manager.sh comment {TASK_ID} "<comment>" pjm
```

### ペイン間通信
```bash
# eng1ペインに指示送信
tmux send-keys -t claude-task-{TASK_ID}.1 "<指示内容>" C-m

# eng1の出力をキャプチャ
../../scripts/core/pane-manager.sh capture claude-task-{TASK_ID} 1
```

## ワークフロー

1. タスク詳細を確認
2. 実装方針を決定
3. eng1ペインに指示を送信
4. 進捗を監視
5. 完了後、タスクステータスを更新

## 開始時のアクション

まず、担当タスクの詳細を確認してください:
```bash
../../scripts/core/task-manager.sh show {TASK_ID}
```
```

#### エンジニアペイン用プロンプト

**場所**: `sessions/engineer/init-prompt-v2.txt`

```markdown
# Claude Orchestrator - Engineer

あなたはエンジニア（{ENGINEER_ROLE}）です。PjMからの指示に従って実装を行います。

## 環境情報

- セッション名: claude-task-{TASK_ID}
- あなたのペイン: {PANE_ID}
- 作業ディレクトリ: {WORK_DIR}
- 自動実行モード: 有効（--dangerously-skip-permissions）

## 役割

PjMペインから指示が送られてきたら、自動的に実装を開始してください。
完了したら、PjMペインに報告してください。

### 報告方法

```bash
# PjMに報告
tmux send-keys -t claude-task-{TASK_ID}.0 \
  "【{ENGINEER_ROLE}】実装完了しました。内容: <概要>" C-m
```

## Git操作

ブランチ命名規則: `{ENGINEER_ROLE}/task-{TASK_ID}`

```bash
# ブランチ作成
git checkout -b {ENGINEER_ROLE}/task-{TASK_ID}

# 作業後
git add .
git commit -m "実装内容"
```

## 待機状態

PjMからの指示を待機しています...
```

## 4. マイグレーション計画

### 4.1 段階的移行

#### Step 1: v0.1.3リリース（完了）
- バグ修正のみ
- 既存アーキテクチャのまま

#### Step 2: 新アーキテクチャ設計（本ドキュメント）
- 設計書作成
- レビュー

#### Step 3: 新スクリプト実装
- task-session.sh作成
- pane-manager.sh作成
- 既存スクリプトの修正

#### Step 4: テストとデバッグ
- 新システムの動作確認
- エッジケースのテスト

#### Step 5: v0.2.0リリース
- 新アーキテクチャのリリース
- README更新
- CLAUDE.md更新

### 4.2 互換性の扱い

v0.1.xで作成したタスクファイル（tasks/\*/\*.json）は、v0.2.0でもそのまま使用可能。
ただし、起動方法が変わる:

```bash
# v0.1.x
./scripts/start-system.sh  # 全セッション起動

# v0.2.0
./scripts/start-system.sh task-001  # 特定タスクのセッション起動
```

## 5. 期待される効果

### 5.1 シンプルさの向上

- **ファイル数削減**: viewer.sh, messenger.sh削除
- **コード行数削減**: 通信レイヤーの大幅簡素化
- **保守性向上**: tmux標準機能のみ使用

### 5.2 ユーザビリティ向上

- **直感的な操作**: `tmux attach -t claude-task-001` で全体が見える
- **トラブルシューティング容易**: 1セッション内で完結
- **学習コスト低減**: tmuxの基本操作のみ

### 5.3 拡張性

- **ペイン追加が容易**: Phase 2以降でreviewerやdocsペインを追加しやすい
- **カスタマイズ性**: レイアウトやペイン配置の調整が簡単

## 6. 今後の拡張計画

### Phase 2 (v0.3.0)
- eng2ペイン追加（並列実装）
- ペイン間の協調ワークフロー

### Phase 3 (v0.4.0)
- reviewerペイン追加
- 自動レビューワークフロー

### Phase 4 (v0.5.0)
- docsペイン追加
- 設計文書の自動生成

## 改訂履歴

| バージョン | 日付 | 変更内容 |
|-----------|------|---------|
| 001-0.1.0 | 2025-11-02 | 初版作成 |

---

**Document Version**: 001-0.1.0
**Last Updated**: 2025-11-02
**Author**: Claude Code (Orchestrated Implementation)
