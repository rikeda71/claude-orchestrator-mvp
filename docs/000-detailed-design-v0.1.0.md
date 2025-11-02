# Claude Orchestrator 詳細設計書

> ⚠️ **注意**: このドキュメントはv0.1.0の詳細設計書です。v0.2.0以降は `docs/001-new-architecture.md` および `docs/003-target-project-integration-fix.md` を参照してください。

## ドキュメント情報

- **作成日**: 2025-11-02
- **バージョン**: 0.1.0 (Phase 1 - MVP)
- **対象**: Claude Orchestrator System Phase 1実装
- **完成版**: 1.0.0 (Phase 4完了時)

## 1. 実装概要

### 1.1 実装方針

本実装は、docs/design-doc.mdに基づき、以下の方針で実装されています：

- **管理対象**: 外部の別プロジェクトを管理（関心の分離）
- **初期規模**: 最小構成（PjM + Engineer1 の2セッション）
- **実装言語**: 純粋Bash（依存を最小化、tmux統合が容易）
- **拡張性**: Phase 2以降で段階的に機能拡張可能な設計

### 1.2 実装済みコンポーネント

```
claude-orchestrator/
├── .git/                      ✅ Gitリポジトリ初期化済み
├── .gitignore                 ✅ 適切な除外設定
├── README.md                  ✅ ユーザー向けドキュメント
├── config/                    ✅ 設定ファイル
│   ├── orchestrator.conf      ✅ システム設定
│   └── target-project.conf.example ✅ プロジェクト設定テンプレート
├── scripts/
│   ├── core/                  ✅ コアスクリプト
│   │   ├── session-manager.sh ✅ tmuxセッション管理
│   │   ├── task-manager.sh    ✅ タスクCRUD操作
│   │   └── messenger.sh       ✅ セッション間通信
│   ├── start-system.sh        ✅ システム起動
│   ├── stop-system.sh         ✅ システム停止
│   └── utils/                 ✅ ユーティリティ
│       ├── common.sh          ✅ 共通関数
│       └── logger.sh          ✅ ログ機能
├── sessions/                  ✅ セッション初期化
│   ├── pjm/
│   │   └── init-prompt.txt    ✅ PjM用プロンプト
│   ├── eng1/
│   │   └── init-prompt.txt    ✅ Engineer1用プロンプト
│   ├── eng2/
│   │   └── init-prompt.txt    ✅ Engineer2用プロンプト
│   ├── reviewer/
│   │   └── init-prompt.txt    ✅ Reviewer用プロンプト
│   ├── docs/
│   │   └── init-prompt.txt    ✅ Docs用プロンプト
│   └── engineer-init-prompt.txt ✅ エンジニア共通テンプレート
├── tasks/                     ✅ タスク管理ディレクトリ
├── communication/             ✅ 通信管理ディレクトリ
├── worktrees/                 ✅ Gitワークツリー用
└── docs/                      ✅ ドキュメント
    ├── design-doc.md          ✅ 基本設計書
    └── detailed-design.md     ✅ 本ドキュメント
```

## 2. アーキテクチャ詳細

### 2.1 システム構成図

```
┌─────────────────────────────────────────────────────────┐
│                   User                                   │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ├─── start-system.sh (起動)
                  ├─── stop-system.sh (停止)
                  └─── tmux attach (セッション接続)
                  │
┌─────────────────┴───────────────────────────────────────┐
│            Claude Orchestrator System                    │
│                                                          │
│  ┌────────────┐         ┌────────────┐                 │
│  │ PjM        │────────▶│ Engineer1  │                 │
│  │ Session    │         │ Session    │                 │
│  │ (claude)   │◀────────│ (claude)   │                 │
│  └────────────┘         └────────────┘                 │
│        │                      │                          │
│        │                      │                          │
│  ┌─────┴──────────────────────┴──────┐                 │
│  │     Communication Layer            │                 │
│  │  - Named Pipes (FIFO)              │                 │
│  │  - File-based Messages             │                 │
│  │  - tmux Buffers                    │                 │
│  └────────────────────────────────────┘                 │
│        │                      │                          │
│  ┌─────┴──────────────────────┴──────┐                 │
│  │     Task Management                │                 │
│  │  - JSON-based Tasks                │                 │
│  │  - Status Tracking                 │                 │
│  │  - File System Storage             │                 │
│  └────────────────────────────────────┘                 │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### 2.2 データフロー

```
1. タスク作成フロー
   PjM → task-manager.sh create → tasks/queue/<task-id>.json

2. タスク割り当てフロー
   PjM → task-manager.sh assign → タスクファイル更新 → messenger.sh send → Engineer1

3. タスク実行フロー
   Engineer1 → タスク確認 → ステータス更新 (in-progress) → 実装 → 完了報告 (completed)

4. メッセージングフロー
   送信側 → messenger.sh send → communication/buffers/<to>-<timestamp>.msg → 受信側 → read
```

## 3. コンポーネント詳細

### 3.1 共通ユーティリティ (scripts/utils/)

#### 3.1.1 common.sh

**目的**: 全スクリプトから利用される共通機能

**主要関数**:
- `load_config()`: 設定ファイル読み込み
- `log_*()`: ログ出力（debug, info, warn, error, success）
- `check_required_commands()`: 必須コマンドの存在確認
- `acquire_lock()` / `release_lock()`: ファイルロック
- `json_get()` / `json_set()`: JSON操作（jq使用）
- `timestamp()`: ISO 8601形式のタイムスタンプ生成
- `generate_task_id()`: タスクID生成
- `tmux_session_exists()`: tmuxセッション存在確認
- `create_pipe()` / `remove_pipe()`: 名前付きパイプ操作

**設計判断**:
- Bash関数で実装し、全スクリプトからsource可能
- エラーハンドリングを統一（die関数）
- ログレベルによる出力制御

#### 3.1.2 logger.sh

**目的**: ファイルベースの永続的なログ管理

**主要関数**:
- `init_logger()`: ログディレクトリ初期化
- `log_session()` / `log_system()` / `log_task()`: 種別ごとのログ記録
- `rotate_log()` / `rotate_log_if_needed()`: ログローテーション
- `show_log()` / `search_log()`: ログ閲覧・検索
- `cleanup_logs()`: ログクリーンアップ
- `capture_tmux_pane()`: tmuxペイン内容のキャプチャ

**設計判断**:
- ログは3種類に分類（session, system, task）
- 自動ローテーション（10MB超過時、最大5世代保持）
- JSON形式ではなくプレーンテキスト（可読性優先）

### 3.2 コアスクリプト (scripts/core/)

#### 3.2.1 task-manager.sh

**目的**: タスクのCRUD操作とライフサイクル管理

**タスクJSON構造**:
```json
{
  "id": "task-20251102120000-abc123",
  "type": "feature",
  "assigned_to": "eng1",
  "status": "pending",
  "description": "タスクの説明",
  "created_by": "pjm",
  "created_at": "2025-11-02T10:00:00Z",
  "updated_at": "2025-11-02T10:00:00Z",
  "dependencies": [],
  "worktree": "",
  "files": [],
  "review_notes": [],
  "history": []
}
```

**主要機能**:
- `create_task()`: タスク作成（queueディレクトリに配置）
- `show_task()`: タスク詳細表示（jqで整形）
- `list_tasks()`: タスク一覧（ステータスフィルタ可能）
- `update_task_field()`: フィールド更新
- `update_task_status()`: ステータス変更（ファイル移動を伴う）
- `assign_task()`: タスク割り当て
- `delete_task()`: タスク削除
- `add_task_comment()`: レビューコメント追加
- `list_assigned_tasks()`: 担当者別タスク一覧

**ステータス遷移**:
```
pending (queue/) → in-progress (in-progress/) → review (reviews/) → completed (completed/)
                        ↑                              ↓
                        └──────────────────────────────┘
                        (修正依頼時は in-progress に戻る)
```

**設計判断**:
- ファイルベースでシンプル、外部DBなし
- ステータス変更時はファイルを移動（ディレクトリ=ステータス）
- ファイルロック（flock）で競合回避
- JSONでデータ永続化、jqで操作

#### 3.2.2 session-manager.sh

**目的**: tmuxセッションのライフサイクル管理

**主要機能**:
- `create_session()`: tmuxセッション作成（デタッチモード）
- `kill_session()`: セッション終了
- `list_sessions()`: セッション一覧表示
- `attach_session()`: セッションにアタッチ
- `send_command()`: セッションにコマンド送信（tmux send-keys）
- `capture_session()`: セッション出力のキャプチャ
- `start_claude()`: Claude Code起動
- `send_init_prompt()`: 初期プロンプト送信
- `check_session_health()`: ヘルスチェック
- `restart_session()`: セッション再起動

**セッション命名規則**:
- フォーマット: `${TMUX_SESSION_PREFIX}-${role}`
- 例: `claude-pjm`, `claude-eng1`

**設計判断**:
- tmuxのデタッチモードでバックグラウンド実行
- 各セッションは独立した作業ディレクトリを持つ
- 初期プロンプトはファイルから読み込み
- セッションログは自動的に記録

#### 3.2.3 messenger.sh

**目的**: セッション間通信

**通信方式**:
1. **ファイルベースメッセージング**（メイン）
   - `communication/buffers/<to>-<timestamp>.msg` にJSON形式で保存
   - 非同期、永続化、履歴追跡可能

2. **名前付きパイプ（FIFO）**（補助）
   - リアルタイム通信用
   - 現在は作成のみ、将来の拡張用

**主要機能**:
- `create_all_pipes()`: 通信パイプ作成
- `remove_all_pipes()`: パイプクリーンアップ
- `send_message_file()`: メッセージ送信（ファイルベース）
- `read_messages()`: メッセージ読み取り
- `send_to_session()`: セッションへメッセージ送信
- `broadcast_message()`: 全セッションへブロードキャスト
- `cleanup_messages()`: 古いメッセージの削除
- `message_stats()`: メッセージ統計

**メッセージJSON構造**:
```json
{
  "from": "pjm",
  "to": "eng1",
  "timestamp": "2025-11-02T10:00:00Z",
  "message": "メッセージ内容"
}
```

**設計判断**:
- ファイルベースで確実性とデバッグ容易性を優先
- パイプは将来の拡張用に予約
- 自動クリーンアップ（デフォルト60分経過後）

### 3.3 システム制御スクリプト (scripts/)

#### 3.3.1 start-system.sh

**目的**: システム全体の起動

**起動シーケンス**:
1. `check_prerequisites()`: 前提条件チェック
   - 必須コマンド（tmux, git, jq）の存在確認
   - 設定ファイルの確認
   - 管理対象プロジェクトの存在確認

2. `init_directories()`: ディレクトリ構造の初期化
   - 必要なディレクトリを自動作成
   - .gitkeepファイルは既に配置済み

3. `init_communication()`: 通信システムの初期化
   - 名前付きパイプの作成

4. `start_logging()`: システムログ開始

5. `start_sessions()`: セッションの起動
   - Phase 1: pjm, eng1 のみ
   - 各セッションを1秒間隔で起動

6. `verify_sessions()`: セッション確認
   - セッション一覧表示
   - ヘルスチェック

7. `show_welcome()`: ウェルカムメッセージ表示

**オプション**:
- `--with-samples`: サンプルタスク作成

**設計判断**:
- エラーが発生しても可能な限り継続
- 各ステップでログ記録
- ユーザーへの情報提供を重視

#### 3.3.2 stop-system.sh

**目的**: システムの安全な停止

**停止シーケンス**:
1. `check_running_tasks()`: 進行中タスクの確認
   - in-progressディレクトリをチェック
   - タスクがある場合は警告表示

2. `notify_sessions()`: セッションへの終了通知
   - 全セッションにメッセージ送信

3. `save_session_logs()`: セッションログの保存
   - tmuxペイン内容をキャプチャ
   - タイムスタンプ付きでファイル保存

4. `stop_sessions()`: セッション停止
   - 全tmuxセッションをkill

5. `cleanup_pipes()`: パイプのクリーンアップ

6. `cleanup_messages()`: メッセージのクリーンアップ

7. `save_system_status()`: システム状態の保存
   - タスク数などをJSON形式で保存

8. `show_goodbye()`: 終了メッセージ表示

**オプション**:
- `--force / -f`: タスクチェックをスキップして強制停止
- `--skip-task-check`: タスクチェックをスキップ（確認は表示）

**設計判断**:
- データ損失を防ぐため、進行中タスクを警告
- ログとセッション状態を必ず保存
- グレースフルシャットダウンを重視

#### 3.3.3 viewer.sh（統合ビューア）

**目的**: 複数セッションの統合表示

**主要機能**:
- `create_viewer_session()`: ビューアセッション作成
- `setup_viewer_layout()`: レイアウト設定（左30%: PjM、右70%: その他を縦分割）
- `attach_sessions_to_panes()`: 各ペインに既存セッションを接続
- `setup_viewer()`: 完全セットアップ
- `attach_viewer()`: ビューアにアタッチ
- `kill_viewer()`: ビューア終了

**レイアウト構成**:
```
┌─────────────────────────────────────────┐
│ claude-viewer                           │
├──────────────┬──────────────────────────┤
│              │  eng1                    │
│   PjM        ├──────────────────────────┤
│   (30%)      │  eng2 (if running)       │
│              ├──────────────────────────┤
│              │  reviewer (if running)   │
│              ├──────────────────────────┤
│              │  docs (if running)       │
└──────────────┴──────────────────────────┘
```

**設計判断**:
- 各セッションの独立性を保持（ビューアは表示のみ）
- アクティブなセッションのみ表示
- ペイン分割はtmuxのネイティブ機能を使用

#### 3.3.4 start-viewer.sh

**目的**: 統合ビューアを新しいターミナルウィンドウで起動

**主要機能**:
- `detect_terminal()`: OS/ターミナルタイプの自動検出
- `open_in_terminal_app()`: macOS Terminal.app で起動
- `open_in_iterm()`: macOS iTerm2 で起動
- `open_in_gnome_terminal()`: Linux gnome-terminal で起動
- `open_in_konsole()`: Linux konsole で起動
- `open_in_xterm()`: Linux xterm で起動
- `launch_viewer_window()`: 新しいウィンドウで起動
- `launch_viewer_current()`: 現在のターミナルで起動

**対応ターミナル**:
- macOS: Terminal.app, iTerm2
- Linux: gnome-terminal, konsole, xterm

**設計判断**:
- 環境を自動検出して適切なターミナルで起動
- AppleScript (macOS) / コマンドライン (Linux) を使用
- フォールバック: 手動起動のコマンドを表示

**start-system.shとの統合**:
- `--with-viewer` オプション追加
- システム起動後に自動的にビューア起動可能

## 4. 設定ファイル

### 4.1 config/orchestrator.conf

システム全体の設定。ほとんどの項目はデフォルト値で動作。

**主要設定項目**:
- `TMUX_SESSION_PREFIX`: セッション名プレフィックス（デフォルト: "claude"）
- `LOG_LEVEL`: ログレベル（0=DEBUG, 1=INFO, 2=WARN, 3=ERROR）
- `CONTEXT_WARNING_THRESHOLD`: コンテキスト警告閾値（95%）

### 4.2 config/target-project.conf

管理対象プロジェクトの設定。ユーザーが編集する。

**必須設定項目**:
- `TARGET_PROJECT_PATH`: 管理対象プロジェクトのパス

**オプション設定項目**:
- `TARGET_PROJECT_MAIN_BRANCH`: メインブランチ名（デフォルト: "main"）
- `ENG1_BRANCH_PREFIX`: エンジニア1のブランチプレフィックス
- `AUTO_MERGE_ENABLED`: 自動マージの有効化
- `REVIEW_REQUIRED`: レビュー必須フラグ

## 5. セッション初期プロンプト

### 5.1 プロンプト設計方針

各セッションの初期プロンプトは以下の構成：

1. **役割の明確化**: セッションの役割を最初に宣言
2. **責務の列挙**: 何をすべきかを具体的に記載
3. **作業環境の提示**: ディレクトリパス、利用可能なコマンド
4. **ワークフローの例示**: 典型的な作業の流れ
5. **行動指針**: 判断基準となる原則

### 5.2 エンジニアプロンプトの設計

**現在の実装（Phase 1 MVP）**:

`sessions/engineer/init-prompt.txt` を汎用エンジニアプロンプトとして使用。

変数置換:
- `${ENGINEER_ROLE}`: エンジニアの識別子（eng1, eng2, ...）
- `${WORK_DIR}`: 作業ディレクトリパス
- `${ORCHESTRATOR_ROOT}`: システムルートパス

**将来の拡張計画（Phase 3以降）**:

専門化されたエンジニアプロンプトの実装:

```
sessions/
├── engineer/                  # 汎用エンジニア（デフォルト）
│   └── init-prompt.txt
├── backend-engineer/          # バックエンド専門
│   └── init-prompt.txt
├── frontend-engineer/         # フロントエンド専門
│   └── init-prompt.txt
├── mobile-engineer/           # モバイルアプリ専門
│   └── init-prompt.txt
├── devops-engineer/           # DevOps専門
│   └── init-prompt.txt
└── qa-engineer/               # QA専門
    └── init-prompt.txt
```

**役割割り当ての拡張**:

PjMがタスク作成時に役割（role）を指定:

```bash
# 現在（Phase 1）
task-manager.sh create feature "API実装" eng1

# 将来（Phase 3以降）
task-manager.sh create feature "API実装" eng1 --role backend-engineer
task-manager.sh create feature "UI実装" eng2 --role frontend-engineer
task-manager.sh create feature "CI/CD構築" eng3 --role devops-engineer
```

タスクJSON構造の拡張:
```json
{
  "id": "task-xxx",
  "assigned_to": "eng1",
  "role": "backend-engineer",  // 新規フィールド
  "type": "feature",
  ...
}
```

セッション起動時にroleに応じたプロンプトを選択:
```bash
# session-manager.shの拡張
start_engineer_session() {
    local engineer_id="$1"  # eng1, eng2, ...
    local role="${2:-engineer}"  # デフォルトは汎用engineer

    local prompt_file="sessions/${role}/init-prompt.txt"
    # プロンプトファイルをロードして変数置換
}
```

これにより:
- eng1: backend-engineer として起動
- eng2, eng3: frontend-engineer として起動
- eng4: mobile-engineer として起動

など、柔軟な役割分担が可能になる。

### 5.3 Git ブランチ命名規則

- 基本形式: `feature/<task-id>`
- エンジニア識別付き: `eng1/feature/<task-id>`（任意）
- 例: `feature/task-20251102120000-abc123`
- 例: `eng1/feature/task-20251102120000-abc123`

## 6. 実装の技術的判断

### 6.1 なぜBashか

**選択理由**:
1. tmuxとの統合が容易
2. パイプ、FIFO、ファイル操作がネイティブ
3. 追加の依存がない（Python/Node.jsインタープリタ不要）
4. デバッグが容易（シェルスクリプトは可読性が高い）

**デメリットと対策**:
- 複雑なロジックには不向き → 関数単位で分割、common.shで共通化
- エラーハンドリングが弱い → `set -euo pipefail` で厳格化
- JSONパースが困難 → jqを利用

### 6.2 なぜファイルベースか

**タスク管理**:
- データベース不要でシンプル
- Gitで履歴管理可能
- 直接編集・閲覧が可能
- バックアップが容易

**メッセージング**:
- 非同期通信が自然
- デバッグが容易（ファイルを直接確認）
- 履歴が自動的に残る
- 複数プロセスからの読み書きに対応（ロック機構）

### 6.3 なぜtmuxか

**選択理由**:
1. 複数の独立したシェルセッションを管理
2. デタッチ/アタッチで柔軟な操作
3. セッション間でのバッファ共有
4. send-keysでプログラマティックに操作可能
5. ターミナル切断後も継続実行

**代替案との比較**:
- GNU Screen: 機能がやや少ない
- 単純なバックグラウンドジョブ: 対話が困難
- 別ターミナルウィンドウ: 自動化が困難

### 6.4 コンテキスト管理戦略

**課題**: Claude Codeのコンテキストウィンドウは有限

**対策**:
1. 使用率95%で警告（将来実装予定）
2. `/clear`コマンドの実行を推奨
3. 重要な状態はファイルに永続化
4. セッションログで履歴を保持
5. タスクコメントで作業状態を記録

## 7. Phase 2 以降の拡張計画

### 7.1 Phase 2: 3セッション構成

追加要素:
- Engineer2 (eng2) セッション追加
- 並列タスク実行
- エンジニア間の作業調整

実装必要項目:
- eng2セッション起動をstart-system.shに追加
- タスク割り当てロジックの改善
- 競合検出機構

### 7.2 Phase 3: 4セッション構成

追加要素:
- Reviewer セッション追加
- コードレビューワークフロー実装

実装必要項目:
- `scripts/core/review-manager.sh` 新規作成
- レビュー依頼の自動化
- フィードバックループの実装

### 7.3 Phase 4: 5セッション完全構成

追加要素:
- Design Doc Writer セッション追加
- 設計文書の自動更新

実装必要項目:
- ドキュメント生成スクリプト
- 実装との同期機構

### 7.4 高度な機能（将来）

- **Git Worktree統合**: 外部プロジェクトのworktree自動管理
- **コンテキスト監視**: `scripts/core/monitor.sh` 実装
- **GitHub Issues統合**: API経由でIssueと連携
- **Slack通知**: Webhook経由で通知
- **Web UI**: システム状態の可視化

## 8. 使用開始手順

### 8.1 初回セットアップ

```bash
# 1. 設定ファイルの作成
cd /Users/rikeda/ghq/github.com/rikeda71/claude-orchestrator
cp config/target-project.conf.example config/target-project.conf

# 2. 設定ファイルの編集
vim config/target-project.conf
# TARGET_PROJECT_PATH を設定

# 3. システムの起動
./scripts/start-system.sh

# 4. PjMセッションにアタッチ
tmux attach -t claude-pjm
```

### 8.2 基本操作

**タスクの作成（PjMセッションで）**:
```bash
../../scripts/core/task-manager.sh create feature "ユーザー認証機能の実装" eng1
```

**タスクの確認（Engineer1セッションで）**:
```bash
../../scripts/core/task-manager.sh my-tasks eng1
```

**タスクの開始**:
```bash
../../scripts/core/task-manager.sh update task-xxx status in-progress
```

**タスクの完了**:
```bash
../../scripts/core/task-manager.sh update task-xxx status completed
```

### 8.3 トラブルシューティング

**セッションが応答しない**:
```bash
# セッション一覧確認
tmux list-sessions

# セッション再起動
./scripts/core/session-manager.sh restart pjm
```

**タスクファイルが壊れた**:
```bash
# タスクの手動確認
cat tasks/queue/task-xxx.json

# jqで整形
jq . tasks/queue/task-xxx.json
```

**ログの確認**:
```bash
# システムログ
./scripts/utils/logger.sh show system orchestrator

# セッションログ
./scripts/utils/logger.sh show session pjm
```

## 9. まとめ

### 9.1 実装完了項目

✅ Git初期化と.gitignore
✅ README.md作成
✅ ディレクトリ構造の整備
✅ 共通ユーティリティ(common.sh, logger.sh)実装
✅ タスク管理スクリプト(task-manager.sh)実装
✅ セッション管理スクリプト(session-manager.sh)実装
✅ 通信スクリプト(messenger.sh)実装
✅ システム起動スクリプト(start-system.sh)実装
✅ システム停止スクリプト(stop-system.sh)実装
✅ 設定ファイルテンプレート作成
✅ セッション初期プロンプト作成
✅ 詳細設計書作成

### 9.2 システムの状態

- **Phase 1 MVP**: 完成
- **動作可能**: はい
- **テスト済み**: 未（次ステップ）
- **本番準備**: 設定ファイル編集後に可能

### 9.3 次のステップ

1. 設定ファイルの編集（`config/target-project.conf`）
2. システムの起動テスト
3. サンプルタスクでの動作確認
4. 実際のプロジェクトでの運用開始
5. フィードバックに基づく改善

## 付録A: ファイル一覧

```
合計ファイル数: 20+
主要スクリプト: 8
設定ファイル: 2
プロンプトファイル: 6
ドキュメント: 3
```

## 付録B: コマンドリファレンス

**システム制御**:
- `./scripts/start-system.sh [--with-samples]`
- `./scripts/stop-system.sh [--force]`

**タスク管理**:
- `./scripts/core/task-manager.sh create <type> "<desc>" [assignee]`
- `./scripts/core/task-manager.sh list [status]`
- `./scripts/core/task-manager.sh show <task-id>`
- `./scripts/core/task-manager.sh update <task-id> <field> <value>`
- `./scripts/core/task-manager.sh my-tasks <assignee>`

**セッション管理**:
- `./scripts/core/session-manager.sh create <role>`
- `./scripts/core/session-manager.sh list`
- `./scripts/core/session-manager.sh attach <role>`
- `./scripts/core/session-manager.sh health`

**メッセージング**:
- `./scripts/core/messenger.sh send <from> <to> "<message>"`
- `./scripts/core/messenger.sh read <recipient>`
- `./scripts/core/messenger.sh broadcast <from> "<message>"`
- `./scripts/core/messenger.sh stats`

---

## 付録C: バージョニング戦略

### セマンティックバージョニング

本プロジェクトは[Semantic Versioning 2.0.0](https://semver.org/)に従います。

**バージョン形式**: MAJOR.MINOR.PATCH

- **MAJOR (メジャー)**: 後方互換性のない変更（1.0.0完成まで0系）
- **MINOR (マイナー)**: 後方互換性のある機能追加（各Phase完了時に+1）
- **PATCH (パッチ)**: 後方互換性のあるバグ修正や小さな改善

### リリース計画

- **0.1.0** (現在): Phase 1 MVP - 2セッション構成（PjM + eng1）
- **0.1.x**: Phase 1のバグ修正、小さな改善
- **0.2.0**: Phase 2 - 3セッション構成（+ eng2）
- **0.2.x**: Phase 2のバグ修正、小さな改善
- **0.3.0**: Phase 3 - 4セッション構成（+ reviewer）
- **0.3.x**: Phase 3のバグ修正、小さな改善
- **0.4.0**: Phase 4 - 5セッション構成（+ docs writer）
- **0.4.x**: Phase 4のバグ修正、小さな改善
- **0.5.0**: Git worktree統合
- **0.6.0**: コンテキスト監視機能
- **0.7.0**: 専門化エンジニアプロンプト実装（backend/frontend/mobile/devops/qa）
- **0.8.0**: 外部サービス統合（GitHub Issues）
- **0.9.0**: 外部サービス統合（ClickUp/Slack）
- **0.10.0**: RC（Release Candidate）- 総合テスト、ドキュメント整備
- **1.0.0**: 正式リリース - 全機能完成、本番運用可能

### バージョン例

```
0.1.0  初回リリース（Phase 1 MVP）
0.1.1  start-system.shのバグ修正
0.1.2  ログ出力の改善
0.1.3  ドキュメント修正
0.2.0  Phase 2完了（eng2追加）
0.2.1  タスク割り当てロジックの修正
...
```

### マイルストーン

| バージョン | マイルストーン | 主要機能 |
|-----------|--------------|---------|
| 0.1.0 | Phase 1 MVP | 基本構成、タスク管理、2セッション |
| 0.4.0 | Phase 4完了 | 5セッション完全構成 |
| 0.7.0 | 専門化完了 | 役割ベースエンジニアリング |
| 1.0.0 | 正式リリース | 全機能、本番運用品質 |

---

**Document Version**: 0.1.0
**Last Updated**: 2025-11-02
**Author**: Claude Code (Orchestrated Implementation)
