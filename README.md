# Claude Orchestrator

マルチClaude ワークフローシステム - 複数のClaude Codeインスタンスを協調させて動作するオーケストレーションシステム

## 概要

このシステムは、Anthropicのエンジニアリングベストプラクティス「Claude Code Best Practices」の第6章「Uplevel with multi-Claude workflows」に基づき、複数のClaude Codeインスタンスを協調させて並列開発を実現します。

### 主な特徴

- **並列処理**: 複数のタスクを同時実行
- **役割分離**: PjM、エンジニア、レビュワー、ドキュメントライターなど専門性に基づく作業分担
- **自動化ワークフロー**: タスク管理からレビュー、ドキュメント生成までの自動化
- **コンテキスト管理**: 効率的なコンテキストウィンドウ管理
- **品質保証**: コードレビューと技術文書生成の自動化

## システム構成

### Phase 1: MVP（✅ 完了 - 2セッション）

- **プロジェクトマネージャー（PjM）**: タスクの作成・割り当て・進捗管理
- **エンジニア1（eng1）**: 実装担当

### Phase 2: 並列開発（✅ 完了）

- **複数エンジニア（eng1, eng2, engN）**: 並列実装
- **動的スケーリング**: タスクの複雑度に応じてエンジニア数を調整
- **Design Doc承認フロー**: 実装前の設計レビュー

### Phase 3: レビューワークフロー（✅ 完了）

- **レビュワー（reviewer）**: コードレビューと品質保証
- **自動レビュープロセス**: 実装完了後の自動レビュー
- **マージ承認フロー**: レビュー承認後の自動マージ

### Phase 4: ドキュメント生成（✅ 完了）

- **ドキュメントライター（docs）**: 技術文書の自動生成
- **API仕様書生成**: OpenAPI仕様、エンドポイント文書
- **アーキテクチャ文書**: システム構成図、フロー図（Mermaid）
- **自動タスク作成**: 実装完了を検知して文書化タスクを自動生成

### Phase 5以降: 今後の拡張

- **QA（qa）**: 実装のテスト自動化
- **外部統合**: GitHub、ClickUp、Slack連携

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

#### 基本的な起動（Phase 1構成）

```bash
./scripts/start-system.sh
```

#### Phase 2+3+4: 完全構成での起動

```bash
# 複数エンジニア + レビュワー + ドキュメントライター
./scripts/start-system.sh --engineers 3 --with-reviewer --with-docs \
  --instruction "ユーザー認証機能を実装してください"
```

#### オプション

- `--engineers N`: エンジニアの数を指定（デフォルト: 1）
- `--with-reviewer`: レビュワーセッションを起動
- `--with-docs`: ドキュメントライターセッションを起動
- `--instruction "タスク内容"`: 初期タスクの指示を指定
- `--no-open`: タスクセッションの自動起動を無効化

これにより以下が実行されます：
- tmuxセッションの作成（PjM、eng1〜engN、reviewer、docs）
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
│   ├── orchestrator.conf       # システム全体の設定
│   └── target-project.conf     # ターゲットプロジェクトの設定
├── scripts/             # 実行スクリプト
│   ├── core/           # コアスクリプト
│   │   ├── task-manager.sh     # タスク管理
│   │   ├── task-session.sh     # タスクセッション作成
│   │   └── pane-manager.sh     # tmuxペイン管理
│   └── utils/          # ユーティリティ
│       ├── common.sh           # 共通関数
│       └── logger.sh           # ロギング
├── sessions/            # セッション初期化
│   ├── pjm/            # プロジェクトマネージャー
│   ├── engineer/       # エンジニア
│   ├── reviewer/       # レビュワー (Phase 3)
│   └── docs/           # ドキュメントライター (Phase 4)
├── tasks/               # タスク管理
│   ├── queue/          # 待機中
│   ├── in-progress/    # 進行中
│   ├── reviews/        # レビュー待ち (Phase 3)
│   └── completed/      # 完了
├── communication/       # セッション間通信
│   └── logs/           # セッションログ
└── docs/               # 設計ドキュメント
    ├── 000-design-doc.md
    ├── 008-phase3-reviewer-integration.md
    └── 009-phase4-docs-writer-integration.md
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

### Phase 1: MVP ✅（完了）
- [x] Git初期化
- [x] 基本スクリプト実装
- [x] 2セッション構成（PjM + eng1）
- [x] タスク管理機能
- [x] v0.2.0: 1セッション内統合、タスクセッション、git worktree対応

### Phase 2: 並列開発 ✅（完了）
- [x] 複数エンジニア対応（動的スケーリング）
- [x] タスク分配アルゴリズム
- [x] Design Doc承認ワークフロー
- [x] 並列実装とworktree分離
- [x] 進捗レポート機能

### Phase 3: レビューワークフロー ✅（完了）
- [x] レビュワーセッション追加
- [x] コードレビューワークフロー
- [x] セキュリティ・品質チェック
- [x] 承認後の自動マージ

### Phase 4: ドキュメント生成 ✅（完了）
- [x] ドキュメントライターセッション追加
- [x] 完了タスクトリガーによる自動ドキュメント生成
- [x] API仕様書生成（OpenAPI）
- [x] アーキテクチャ図生成（Mermaid）
- [x] PjM軽量レビューワークフロー

### Phase 5: QAエンジニア（計画中）
- [ ] QAエンジニアセッション追加
- [ ] テストケース自動生成
- [ ] テスト実行とレポート
- [ ] 品質メトリクス集計

### Phase 6: 外部統合（計画中）
- [ ] GitHub Issues統合
- [ ] ClickUp API連携
- [ ] Slack通知
- [ ] Webhook対応

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
