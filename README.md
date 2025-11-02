# Claude Orchestrator

マルチClaude ワークフローシステム - 複数のClaude Codeインスタンスを協調させて動作するオーケストレーションシステム

## 概要

このシステムは、Anthropicのエンジニアリングベストプラクティス「Claude Code Best Practices」の第6章「Uplevel with multi-Claude workflows」に基づき、複数のClaude Codeインスタンスを協調させて並列開発を実現します。

### 主な特徴

- **並列処理**: 複数のタスクを同時実行
- **役割分離**: PjM、エンジニア、レビュワー、ドキュメントライターなど専門性に基づく作業分担
- **自動化ワークフロー**: タスク管理からレビューまでの自動化
- **コンテキスト管理**: 効率的なコンテキストウィンドウ管理

## システム構成

### Phase 1: MVP（最小構成 - 2セッション）

- **プロジェクトマネージャー（PjM）**: タスクの作成・割り当て・進捗管理
- **エンジニア1（eng1）**: 実装担当

### Phase 2以降: 拡張構成

- **エンジニアN（eng2,3, ...）**: 並列実装
- **レビュワー（reviewer）**: コードレビュー
- **Design Docライター（docs）**: 設計文書管理
- QA (qa) : 実装のテスト

## 必要な環境

- **OS**: macOS、Linux（tmux対応環境）
- **tmux**: v3.0以上
- **git**: v2.0以上
- **jq**: v1.6以上（JSON処理用）
- **Claude Code**: v2.0以上
- **bash**: v4.0以上

## インストール

```bash
# 1. リポジトリのクローン
git clone <repository-url>
cd claude-orchestrator

# 2. 必要なディレクトリの初期化
./scripts/init.sh

# 3. 設定ファイルの編集
cp config/target-project.conf.example config/target-project.conf
vim config/target-project.conf
# TARGET_PROJECT_PATH を管理したいプロジェクトのパスに設定
```

## 使い方

### 1. システムの起動

```bash
./scripts/start-system.sh
```

これにより以下が実行されます：
- tmuxセッションの作成（PjM、eng1）
- Claude Codeの起動
- Git worktreeの作成（エンジニア用）
- 初期プロンプトの送信
- タスクセッションの起動（新しいターミナルウィンドウで自動起動、`--no-open` で無効化可能）

### 2. タスクの作成

PjMペイン（またはタスクセッション）で以下を実行：

```bash
# タスク作成（タイプ、説明、担当者、作成者）
../../scripts/core/task-manager.sh create feature "ユーザー認証機能の実装" eng1 pjm

# タスク一覧表示
../../scripts/core/task-manager.sh list

# タスクをエンジニアに割り当て
../../scripts/core/task-manager.sh assign <task-id> eng1
```

### 3. タスクの実装

eng1セッションで自動的にタスクが通知されます。エンジニアは以下を実行：

```bash
# 割り当てられたタスクの確認
task show task-001

# タスクのステータス更新
task update task-001 status in-progress

# 実装作業...

# 完了報告
task update task-001 status completed
```

### 4. システムの停止

```bash
./scripts/stop-system.sh
```

## ディレクトリ構成

```
claude-orchestrator/
├── config/              # 設定ファイル
├── scripts/             # 実行スクリプト
│   ├── core/           # コアスクリプト
│   └── utils/          # ユーティリティ
├── sessions/            # セッション初期化
├── tasks/               # タスク管理
│   ├── queue/          # 待機中
│   ├── in-progress/    # 進行中
│   ├── completed/      # 完了
│   └── reviews/        # レビュー待ち
├── communication/       # セッション間通信
│   ├── pipes/          # 名前付きパイプ
│   ├── buffers/        # 共有バッファ
│   └── logs/           # ログ
├── worktrees/          # Gitワークツリー
└── docs/               # ドキュメント
```

## コマンドリファレンス

### タスク管理コマンド

```bash
# タスク作成
task create <type> <description> [assignee]

# タスク一覧
task list [status]

# タスク詳細
task show <task-id>

# タスク更新
task update <task-id> <field> <value>

# タスク割り当て
task assign <task-id> <assignee>

# タスク削除
task delete <task-id>
```

### セッション管理コマンド

```bash
# セッション作成
session create <name> <role>

# セッション一覧
session list

# セッション接続
session attach <name>

# セッション削除
session kill <name>
```

### メッセージング

```bash
# メッセージ送信
msg <target-session> <message>

# メッセージ受信確認
msg read
```

## トラブルシューティング

### セッションが応答しない

```bash
# セッション状態確認
tmux list-sessions | grep claude

# セッション再起動
./scripts/stop-system.sh
./scripts/start-system.sh
```

### タスクファイルの破損

```bash
# タスクの整合性チェック
./scripts/utils/task-validator.sh

# バックアップからの復元
cp tasks/.backup/task-001.json tasks/queue/
```

### 通信パイプの問題

```bash
# パイプの再作成
./scripts/utils/recreate-pipes.sh
```

## 開発ガイドライン

### スクリプト開発

- 全てのスクリプトはbashで記述
- 共通機能は`scripts/utils/common.sh`を使用
- エラーハンドリングを徹底
- ログは`scripts/utils/logger.sh`を使用

### タスクJSON形式

```json
{
  "id": "task-001",
  "type": "feature|bug|review|docs",
  "assigned_to": "eng1|eng2|reviewer|docs",
  "status": "pending|in-progress|review|completed",
  "description": "タスクの説明",
  "created_by": "pjm",
  "created_at": "2025-11-02T10:00:00Z",
  "dependencies": [],
  "worktree": "eng1-feature",
  "files": []
}
```

## ロードマップ

### Phase 1: MVP ✓（完了）
- [x] Git初期化
- [x] 基本スクリプト実装
- [x] 2セッション構成（PjM + eng1）
- [x] タスク管理機能
- [x] v0.2.0: 1セッション内統合、タスクセッション、git worktree対応

### Phase 2: 並列開発（計画中）
- [ ] エンジニア2追加（並列開発）
- [ ] タスク分配アルゴリズム
- [ ] コンフリクト検出・解決

### Phase 3: レビューワークフロー
- [ ] レビュワー追加
- [ ] コードレビューワークフロー

### Phase 4: 完全構成
- [ ] Design Docライター追加（5セッション）
- [ ] コンテキスト監視機能
- [ ] 自動テスト統合

### Phase 5: 外部統合
- [ ] GitHub Issues統合
- [ ] ClickUp API連携
- [ ] Slack通知
- [ ] ML-based タスク割り当て

## ライセンス

MIT License

## 貢献

Issue、Pull Requestを歓迎します。

## 参考文献

- [Claude Code Best Practices - Multi-Claude Workflows](https://docs.anthropic.com)
- [tmux Documentation](https://github.com/tmux/tmux/wiki)
- [Git Worktree](https://git-scm.com/docs/git-worktree)

## サポート

質問や問題がある場合は、Issueを作成してください。
