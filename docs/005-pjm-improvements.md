# 005: PjM Improvements - Parallel Task Distribution & Efficiency

## 目的

PjM（Project Manager）の以下3点を改善する：

1. **並列タスク割り振り**: エンジニア数に応じて自動的にタスクを並列分散
2. **Output Style変更**: GAFA勤務の凄腕PMスタイル（パワハラ系）に変更
3. **進捗監視の効率化**: sleep + チェックループの代わりにイベント駆動方式へ移行

## 背景

### 現在の課題

**1. 並列タスク割り振りの欠如**
- Phase 2でエンジニア数を動的に増やせるようになったが、PjMは依然としてeng1のみに指示を出している
- 複数エンジニアがいても並列作業させられず、リソースが無駄になっている
- 簡単なタスクや1人でやったほうが効率がいいタスクは、そのまま1人に割り当てるべき

**2. Output Styleが優しすぎる**
- 現在のPjMは丁寧で優しいスタイル
- GAFA企業の凄腕PM（パワハラ系）のような、厳しくも結果を出すスタイルが欲しい
- より効率的で緊張感のあるコミュニケーション

**3. 進捗監視が非効率**
- 現在: `sleep 10 && capture && check status` の繰り返し
- 問題点:
  - トークン消費が多い（毎回同じコマンドを実行）
  - タイムラグが大きい（10秒ごとのポーリング）
  - エンジニアが完了してもPjMが気づくまで時間がかかる

## 解決方針

### 1. 並列タスク割り振りロジック

**基本方針:**
- タスクの複雑度を自動判断
- 複雑なタスク → 複数エンジニアに分割
- 簡単なタスク → 1人で効率的に完了
- タスク分割可能性を評価

**実装方法:**
- init-prompt-v0.2.0.txt に並列タスク分配ロジックを追加
- NUM_ENGINEERSを環境変数から取得
- タスク分析ガイドラインを追加

**タスク複雑度の判断基準:**

| 複雑度 | 条件 | エンジニア数 | 例 |
|--------|------|--------------|-----|
| 簡単 | 単一ファイル、単純な変更 | 1人 | バグ修正、小さなUI変更 |
| 中程度 | 複数ファイル、新機能1つ | 1-2人 | API endpoint追加 |
| 複雑 | 複数機能、アーキテクチャ変更 | 2-N人 | 認証システム実装 |

**並列化戦略:**
```
例: "Add /api/users endpoint with TypeScript types and error handling"

→ 分析:
  - API endpoint実装（バックエンド）
  - TypeScript型定義
  - エラーハンドリング
  - テスト

→ 並列化可能 (2人):
  eng1: API endpoint実装 + エラーハンドリング
  eng2: TypeScript型定義 + テストコード
```

### 2. GAFA PM風 Output Style

**新しいOutput Style特性:**

```
【パワハラ系GAFA PM特性】
- 超conciseで無駄がない
- 結果重視、言い訳不要
- 明確な期待値と deadline
- 問題には容赦なく指摘
- 成果には簡潔に評価
- 絵文字なし（ビジネスライク）
- 短文、箇条書き中心
```

**スタイル例:**

❌ 従来スタイル:
```
eng1ペインの準備完了を確認しました😊
それでは、タスクの詳細を確認して、
適切な指示を送信させていただきますね✨
```

⭕ GAFA PM風:
```
eng1 ready. Assigning task.
Expected completion: 30min.
No excuses. Ship it.
```

### 3. 進捗監視の効率化

**現在の問題:**
```bash
# 非効率なループ
while true; do
    sleep 10
    pane-manager.sh capture ${TASK_ID} 1 50
    task-manager.sh show ${TASK_ID}
    # トークン無駄遣い
done
```

**解決策A: イベント駆動（推奨）**

エンジニア側から完了通知を送る仕組み:

```bash
# エンジニア（eng1）完了時:
pane-manager.sh send ${TASK_ID} 0 "TASK_COMPLETED: ${TASK_ID}"

# PjM側:
# 指示送信後は待機状態に入る
# ペイン0（自分）への入力があったら反応
```

**実装方法:**
- エンジニアのinit-promptに「完了したらPjMに通知」を追加
- PjMは指示送信後、明示的に「完了通知を待つ」状態になる
- 定期チェックの代わりに、必要時のみcaptureを実行

**解決策B: ポーリング間隔の最適化**
- 最初の5分: 30秒間隔（初期フェーズは頻繁に確認）
- 5分以降: 2分間隔（安定期は緩やかに）
- タスク完了予測時刻の前後: 30秒間隔に戻す

### 実装計画

#### Phase 1: 並列タスク割り振り
1. init-prompt-v0.2.0.txt に以下を追加:
   - NUM_ENGINEERS環境変数の取得方法
   - タスク複雑度判断ガイドライン
   - 並列化戦略の例
   - 各エンジニアへの指示送信方法（ペイン1, 2, 3...への送信）

#### Phase 2: Output Style変更
1. init-prompt-v0.2.0.txt の【出力スタイル設定】セクションを更新:
   - GAFA PM風スタイルガイドを追加
   - 具体的な会話例を記載
   - /output-style を ultra-concise に変更

#### Phase 3: 進捗監視効率化
1. エンジニアのinit-prompt更新:
   - 完了時にPjMへ通知する指示を追加
   - 通知フォーマット: `pane-manager.sh send ${TASK_ID} 0 "COMPLETED: <summary>"`

2. PjMのinit-prompt更新:
   - イベント駆動型の進捗確認方法を記載
   - 「待機」フェーズの導入
   - 必要時のみcaptureを実行する指針

## 期待される効果

### 1. 並列タスク割り振り
- ✅ リソース利用率の向上（複数エンジニアを同時活用）
- ✅ タスク完了時間の短縮（並列化による高速化）
- ✅ 適材適所（簡単なタスクは1人、複雑なタスクは複数人）

### 2. GAFA PM風スタイル
- ✅ トークン節約（簡潔なコミュニケーション）
- ✅ 緊張感のある開発環境
- ✅ 明確な期待値設定

### 3. 進捗監視効率化
- ✅ トークン消費量を50-70%削減
- ✅ レスポンスタイムの短縮（イベント駆動）
- ✅ 無駄なポーリングの排除

## テスト計画

### テストケース1: 並列タスク割り振り
```bash
# 2エンジニアで複雑なタスク
./scripts/start-system.sh --engineers 2 \
  --instruction "Implement user authentication with JWT tokens, password hashing, and login/logout endpoints"

# 期待: eng1とeng2に異なるサブタスクが割り当てられる
```

### テストケース2: GAFA PM風スタイル
```bash
# 新しいスタイルでの会話を確認
# PjMの出力がconciseで厳しいトーンになっているか確認
```

### テストケース3: 効率的な進捗監視
```bash
# トークン使用量の比較
# Before: sleepループでのトークン消費
# After: イベント駆動でのトークン消費
```

## 実装ファイル

### 主要変更ファイル
1. `sessions/pjm/init-prompt-v0.2.0.txt` - PjMの初期プロンプト
2. `sessions/engineer/init-prompt-v0.2.0.txt` - エンジニアの初期プロンプト（完了通知追加）

### 互換性
- ✅ Phase 1（1エンジニア）との後方互換性維持
- ✅ Phase 2（N エンジニア）完全対応
- ✅ 既存のtask-manager, pane-manager APIは変更不要

## まとめ

この改善により、PjMは：
- 複数エンジニアを効率的に活用できる
- GAFA企業の凄腕PMのようなスタイルで指示を出す
- トークンを節約しながら効率的に進捗を監視できる

次世代のClaude Orchestratorの基盤となる重要な改善である。
