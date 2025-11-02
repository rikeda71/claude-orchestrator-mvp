# 006: Advanced PM-Engineer Improvements

## 目的

PjMとエンジニアのコミュニケーションをさらに改善：

1. **エンジニアの細かい進捗報告**: キリの良いタイミングでPjMに通知
2. **PjMのフィードバックループ**: 進捗を受けて優先順位調整・指示
3. **PjMのパワハラ度向上**: より厳しく、結果重視のスタイル
4. **Principal Engineerスタイル**: 自律的で技術的に優れた判断

## 背景

### 現在の課題

**1. 進捗報告が粗い**
- 現在: タスク完了時のみ通知
- 問題点:
  - PjMが途中経過を把握できない
  - エンジニア間の依存関係に気づけない
  - ブロッカーの早期発見ができない

**2. PjMのパワハラ度が不足**
- 現在: やや優しすぎる
- 改善点:
  - より厳しい言葉選び
  - 容赦ない指摘
  - プレッシャーをかける表現

**3. エンジニアがJunior感**
- 現在: 指示待ち的な振る舞い
- 改善点:
  - 技術的判断を自ら行う
  - 設計レビューの実施
  - ベストプラクティスの適用

## 解決方針

### 1. エンジニアの細かい進捗報告

**報告タイミング:**

| タイミング | 通知内容 | 例 |
|-----------|---------|-----|
| Design Doc作成完了 | `PROGRESS: Design doc created` | 実装前の設計完了 |
| 主要機能実装完了 | `PROGRESS: Core feature implemented` | JWT生成機能完了 |
| テスト作成完了 | `PROGRESS: Tests written` | ユニットテスト完了 |
| ブロッカー発生 | `BLOCKED: [reason]` | 依存ライブラリの問題 |
| 完了 | `COMPLETED: [summary]` | 全タスク完了 |

**実装方法:**
```bash
# エンジニアが重要な進捗時にPjMへ通知
pane-manager.sh send ${TASK_ID} 0 "PROGRESS: Design doc created for JWT module"

# PjMはescを送信してエンジニアの入力を中断
pane-manager.sh send ${TASK_ID} 1 $'\x1b'

# その後、フィードバックを送信
pane-manager.sh send ${TASK_ID} 1 "Good. Now focus on token validation first. Other engineers need it."
```

**進捗報告フォーマット:**
```
[Pane X | roleY] PROGRESS: <簡潔な進捗内容>
[Pane X | roleY] BLOCKED: <ブロッカーの理由>
[Pane X | roleY] COMPLETED: <完了サマリー>
```

**フォーマット説明:**
- `[Pane X | roleY]`: どのペイン（X）のどのロール（Y）からの通知かを明示
- 例: `[Pane 1 | eng1] PROGRESS: Design doc created`
- 例: `[Pane 2 | eng2] BLOCKED: Need user model from eng1`
- レビュワーも同様: `[Pane 3 | reviewer] REVIEW_NEEDED: Code review for PR #123`

### 2. PjMのフィードバックループ

**メッセージフォーマット:**
- すべてのPjMからのメッセージに `[Pane 0 | pjm]` プレフィックスをつける
- メッセージ本文はユーザー命令と同じ言語を使用
- プレフィックス部分は常に英語（`[Pane 0 | pjm]`）

**フィードバック戦略:**

1. **進捗を受けて優先順位調整**
   - eng1がJWT生成完了 → eng2に「[Pane 0 | pjm] JWT生成完了。統合テスト優先でやれ。」
   - eng2がブロック中 → eng1に「[Pane 0 | pjm] eng2ブロック中。そっちのタスク優先しろ。」

2. **定期的な進捗確認**
   - 15分経過しても連絡なし → 進捗確認を送信
   - 30分経過しても連絡なし → 厳しく催促

3. **escキーでエンジニアの入力を中断**
   ```bash
   # エンジニアペインにescを送信（入力中断）
   pane-manager.sh send ${TASK_ID} 1 $'\x1b'

   # すぐにフィードバックを送信（日本語命令の場合）
   pane-manager.sh send ${TASK_ID} 1 "[Pane 0 | pjm] 停止。優先順位変更。Xを先にやれ。"

   # 英語命令の場合
   pane-manager.sh send ${TASK_ID} 1 "[Pane 0 | pjm] Stop. Change priority. Do X first."
   ```

### 3. よりパワハラチックなPjM

**パワハラ度向上の具体例:**

| レベル | 従来 | 改善後（パワハラ） |
|--------|------|------------------|
| タスク割り当て | "Implement JWT. Expected: 30min." | "JWT implementation. 30min deadline. Don't be late." |
| 進捗確認 | "How's progress?" | "Status update. Now." |
| 遅延指摘 | "Taking longer than expected." | "You're behind schedule. Speed up or explain why." |
| ブロッカー対応 | "What's blocking you?" | "What's the holdup? Fix it or escalate immediately." |
| 完了確認 | "Good work." | "Done. Next." |
| 厳しい催促 | "Please update soon." | "No update in 20min. Report status NOW or I'll assume failure." |

**パワハラトーン特性:**
- 短い命令形
- "please" を使わない
- 期限を明確に強調
- 遅延に容赦なし
- "なぜ遅れているのか説明しろ" 的な追及

### 4. Principal Engineer風のエンジニア

**Principal Engineerの特性:**

1. **自律的な技術判断**
   - 実装前に設計レビューを自ら実施
   - ベストプラクティスを適用
   - セキュリティ・パフォーマンスを考慮

2. **Design-First Approach**
   - 必ず実装前にDesign Docを作成
   - トレードオフを明記
   - PjMに設計レビューを依頼

3. **プロアクティブな問題解決**
   - 潜在的な問題を事前に指摘
   - 他エンジニアの実装も考慮
   - システム全体の整合性を保つ

4. **技術的リーダーシップ**
   - コードレビューの視点を持つ
   - アーキテクチャの一貫性を保つ
   - ベストプラクティスを提案

**具体例:**

❌ Junior Engineer:
```
PjMからの指示: "Implement JWT"
→ すぐに実装開始
→ とりあえず動くコードを書く
→ 完了報告
```

✅ Principal Engineer:
```
PjMからの指示: "Implement JWT"
→ まず要件を分析
→ Design Doc作成（セキュリティ考慮、token expiry戦略、refresh token設計）
→ PjMに設計レビュー依頼: "[Pane 1 | eng1] PROGRESS: Design doc created. Review needed before implementation."
→ **承認待ち状態に入る（重要：承認なしで実装を進めてはいけない）**
→ PjMからの承認を受信: "Design approved. Proceed with implementation. Focus on token validation first. Ship it."
→ **承認受信後、実装を開始**
→ ベストプラクティスに従って実装
→ セキュリティテスト実施
→ 完了報告: "[Pane 1 | eng1] COMPLETED: JWT module with generation, validation, refresh. All tests passing."
```

## 実装計画

### Phase 1: エンジニアプロンプト改善

**追加内容:**

1. **進捗報告ガイドライン**
   - 報告タイミングの明記
   - フォーマットの統一
   - PjMへの通知方法

2. **Principal Engineerマインドセット**
   - Design-First Approach
   - セキュリティ・パフォーマンス考慮
   - 技術的判断の自律性

3. **ワークフロー例の更新**
   ```
   1. タスク受領
   2. 要件分析
   3. Design Doc作成
   4. → PROGRESS通知: "[Pane 1 | eng1] PROGRESS: Design doc created"
   5. PjMからの設計承認受信: "Design approved. Proceed with implementation. Ship it."
   6. 実装開始
   7. 主要機能完了時 → PROGRESS通知: "[Pane 1 | eng1] PROGRESS: Core feature implemented"
   8. テスト完了時 → PROGRESS通知: "[Pane 1 | eng1] PROGRESS: Tests written and passing"
   9. 全体完了 → COMPLETED通知: "[Pane 1 | eng1] COMPLETED: Feature X with tests. All passing."
   ```

### Phase 2: PjMプロンプト改善

**追加内容:**

1. **よりパワハラチックなスタイル**
   - 命令形の使用
   - "please" 排除
   - 厳しい催促の例文

2. **フィードバックループの実装**
   - PROGRESS受信時の対応（特にDesign Doc作成完了時）
   - **重要**: Design Doc作成完了時は**必ず承認メッセージを送信**してエンジニアを待機状態から解放
   - 優先順位調整の判断基準
   - escキー送信 + フィードバック

3. **定期的な進捗確認**
   ```bash
   # 15分経過チェック
   last_update=$(check_last_progress_time)
   if [ $last_update -gt 900 ]; then  # 15分 = 900秒
       pane-manager.sh send ${TASK_ID} ${PANE_ID} "Status update. Now."
   fi

   # 30分経過で厳しく催促
   if [ $last_update -gt 1800 ]; then  # 30分 = 1800秒
       pane-manager.sh send ${TASK_ID} ${PANE_ID} "No update in 30min. Report immediately or explain delay."
   fi
   ```

4. **エンジニア入力中断 + FB**
   ```bash
   # PROGRESS受信時
   # 1. エンジニアの入力を中断
   pane-manager.sh send ${TASK_ID} ${ENG_PANE} $'\x1b'

   # 2. フィードバック送信
   pane-manager.sh send ${TASK_ID} ${ENG_PANE} "Good. Now prioritize X because eng2 needs it."
   ```

## 期待される効果

### 1. エンジニアの細かい進捗報告
- ✅ PjMがリアルタイムで状況把握
- ✅ エンジニア間の依存関係を早期発見
- ✅ ブロッカーの即座対応
- ✅ 優先順位の動的調整

### 2. パワハラチックなPjM
- ✅ より緊張感のある開発環境
- ✅ 明確なプレッシャー
- ✅ 遅延への即座対応
- ✅ 結果重視の文化

### 3. Principal Engineerスタイル
- ✅ 高品質な設計
- ✅ セキュリティ・パフォーマンス考慮
- ✅ システム全体の整合性
- ✅ プロアクティブな問題解決

## テスト計画

### テストケース1: 進捗報告とフィードバック
```bash
# 2エンジニアで認証システム実装
./scripts/start-system.sh --engineers 2 \
  --instruction "Implement authentication: JWT + password hashing"

# 期待される動き:
# 1. eng1: Design doc作成 → PROGRESS通知
# 2. PjM: escキー送信 + "Good. Proceed with implementation."
# 3. eng1: JWT生成実装完了 → PROGRESS通知
# 4. PjM: eng2に優先順位変更指示
# 5. eng2: パスワードハッシング完了 → PROGRESS通知
# 6. 両者完了 → COMPLETED通知
```

### テストケース2: 進捗確認タイムアウト
```bash
# エンジニアが15分間連絡なし
# → PjM: "Status update. Now." を送信

# さらに15分（計30分）連絡なし
# → PjM: "No update in 30min. Report immediately or explain delay."
```

### テストケース3: Principal Engineer的設計レビュー
```bash
# エンジニアが実装前にDesign Doc作成
# → "PROGRESS: Design doc created. Review needed."
# → PjMが設計をレビュー
# → PjM: "Approved. Proceed." または "Revise: [feedback]"
```

## 実装ファイル

### 主要変更ファイル
1. `sessions/engineer/init-prompt-v0.2.0.txt`
   - 進捗報告ガイドライン追加
   - Principal Engineerマインドセット追加
   - ワークフロー例更新

2. `sessions/pjm/init-prompt-v0.2.0.txt`
   - よりパワハラチックなスタイルガイド追加
   - フィードバックループの実装方法追加
   - 進捗確認タイムアウトロジック追加
   - escキー送信 + FB方法の明記

## まとめ

この改善により：

- **エンジニア**: より細かく進捗報告し、Principal Engineerとして自律的に動く
- **PjM**: より厳しく管理し、進捗に応じて動的に優先順位を調整
- **コミュニケーション**: リアルタイムなフィードバックループで効率最大化

次世代のハイパフォーマンス開発チームを実現する🔥
