
# Salesforce + Slack Notification Integration (Portfolio)

> **完成版**：このリポジトリは転職用ポートフォリオとして整理した完成版です。学習途中の履歴は別リポジトリに残しています。

![Salesforce](https://img.shields.io/badge/Salesforce-Apex-blue)
![Slack](https://img.shields.io/badge/Slack-Incoming%20Webhook-4A154B)
![CI](https://img.shields.io/badge/Tests-passing-brightgreen)

---

## 概要

Salesforce の **商談（Opportunity）** 更新をトリガーに、**Slack の指定チャンネルへ通知**します。  
標準連携では難しい「通知条件・メッセージの細かい制御」を **Apex + Webhook** で柔軟に実現します。

- 非同期処理（Queueable/AllowsCallouts）で **バルク安全**・ガバナ制限に配慮
- 閾値や対象ステージは **Custom Metadata Type (CMDT)** でノーコード管理
- Webhook URL は **Named Credential** に外出しして **シークレットをコードに持たない**

---

## デモ（イメージ）

> スクリーンショット差し替え想定：`docs/screenshot-slack.png` を後日追加

```text
[商談更新] ACME - 新規導入案件
フェーズ: Negotiation/Review (確度 50%)
金額: ¥3,000,000
担当: Taro Sales
備考: 9/15 見積再提示
```

---

## アーキテクチャ

```mermaid
flowchart LR
    A[Opportunity Update] --> B[Apex Trigger]
    B --> C[SlackNotificationHandler<br/>(Queueable + AllowsCallouts)]
    C --> D[Named Credential: Slack_Webhook]
    D --> E[Slack Incoming Webhook]
    E --> F[Slack Channel]
```

### 主要コンポーネント
- **OpportunityTrigger.trigger**  
  フェーズ／金額変化を検知して通知対象を抽出。関連情報をバルク SOQL で取得し、1トランザクションにつき1ジョブだけ enqueue。
- **SlackNotificationHandler.cls**  
  `Queueable, Database.AllowsCallouts` で非同期 POST。Slack Block Kit の `blocks` を組み立て、複数商談を1リクエストで送信。
- **SlackConfigProvider.cls**  
  CMDT `Slack_Config__mdt` を読み込み、`Enabled__c` / `MinAmount__c` / `TargetStages__c` を提供。未設定時も安全デフォルトで動作。

---

## セットアップ

### 0) 前提
- Salesforce 組織（Sandbox / Dev Org）
- Slack ワークスペース（アプリ「Incoming Webhooks」を有効化）
- Salesforce CLI（新 CLI）：`sf` コマンドが使えること

### 1) Slack Webhook URL を発行
1. Slack で **Incoming Webhooks** を有効化  
2. 通知先チャンネルを選択して **Webhook URL** を取得

### 2) Salesforce 側の準備
1. **Named Credential** を作成  
   - 設定 → **名前付き資格情報** → 新規  
   - ラベル: `Slack Webhook` / 名前: `Slack_Webhook`  
   - URL: 取得した Webhook URL  
   - 認証: なし（匿名 POST）  
   - 利用ユーザへ権限セット割り当てを忘れずに
2. **Custom Metadata Type (CMDT)** を作成  
   - 設定 → **カスタムメタデータ型** → 新規  
   - ラベル: `Slack Config` / API 名: `Slack_Config`  
   - 項目:
     - `Enabled__c` (Checkbox)
     - `MinAmount__c` (Number/Decimal)
     - `TargetStages__c` (Text, カンマ区切り: 例 `Prospecting, Negotiation/Review, Closed Won`)
   - レコード `Default` を作成して上記項目を設定

### 3) デプロイ & テスト
```bash
# 接続
sf org login web --alias MyOrg
sf config set target-org=MyOrg

# デプロイ
sf project deploy start --source-dir force-app --ignore-conflicts

# 単体テスト（必要に応じてクラス名を調整）
sf apex run test --tests SlackNotificationHandlerTest --result-format human
```

---

## 使い方

- 商談の **フェーズ** または **金額** が変化したとき、トリガで抽出 → ハンドラが Slack へ送信します。
- 送信されるメッセージは **Block Kit** 構造で、読みやすいカード風のレイアウトになります。

### 送信 JSON（例）
```json
{
  "blocks": [
    { "type": "header", "text": { "type": "plain_text", "text": "商談更新" } },
    { "type": "section", "fields": [
      { "type": "mrkdwn", "text": "*商談名*\nACME - 新規導入案件" },
      { "type": "mrkdwn", "text": "*フェーズ*\nNegotiation/Review (50%)" },
      { "type": "mrkdwn", "text": "*金額*\n¥3,000,000" },
      { "type": "mrkdwn", "text": "*担当*\nTaro Sales" }
    ]},
    { "type": "section", "text": { "type": "mrkdwn", "text": "*備考*\n9/15 見積再提示" } },
    { "type": "divider" }
  ]
}
```

---

## カスタマイズ

- **通知しきい値**：`MinAmount__c` に金額下限をセット（未設定なら無効）  
- **対象ステージ**：`TargetStages__c` にカンマ区切りで列挙（空なら無効）  
- **ON/OFF**：`Enabled__c` で一時停止が可能  
- **拡張**：Teams/Discord/Google Chat などの Webhook にも容易に派生可能

---

## セキュリティ

- Webhook URL は **Named Credential** に格納（コードやリポジトリに含めない）  
- GitHub では **Push Protection / Secret Scanning** を有効化  
- テストやログでシークレットを出力しない（`System.debug` の取り扱いに注意）

---

## 運用ガイド

- **ログ監視**：失敗時は `System.debug(ERROR, ...)` が出力されます（本番は監査用カスタムオブジェクト／PE へ移行可）  
- **負荷対策**：1トランザクション=1ジョブ運用。大量更新は Platform Events などへ拡張余地あり  
- **変更管理**：閾値・ステージ変更は CMDT で即時反映（デプロイ不要）

---
---

## 複数レコード処理（バルク対応）

本実装は **1トランザクションにつき1回だけ enqueue** し、Queueable Apex 内で **複数レコードをまとめて Slack に通知** する方式を採用しています。  

### 設計ポイント

- **Trigger 側**  
  - 商談のフェーズ／金額が変化したものだけを抽出  
  - 変更 ID を `Set<Id>` で一括管理し、重複排除  
  - `System.enqueueJob(new SlackNotificationHandler(ids))` を **1回のみ呼び出し**

- **Queueable 側**  
  - 渡された ID を SOQL でまとめて取得  
  - CMDT の条件（Enabled, MinAmount, TargetStages）でフィルタ  
  - Slack Block Kit の **50 blocks 制限**に対応するため、**チャンク分割（最大15件/メッセージ）**して複数 POST

### コード抜粋（チャンク処理部）

```apex
Integer baseBlocks = 2;   // 先頭 section + divider
Integer perRecord  = 3;   // 1件あたり section + actions + divider
Integer maxBlocks  = 50;
Integer maxPerMessage = (maxBlocks - baseBlocks) / perRecord; // 16件まで
Integer CHUNK = Math.min(15, maxPerMessage); // 安全に15件まで

for (Integer i=0; i<filtered.size(); i+=CHUNK) {
    List<Opportunity> chunk = filtered.subList(i, Math.min(i+CHUNK, filtered.size()));
    List<Object> blocks = new List<Object>();
    blocks.add(sectionText('*商談更新* :bell:（まとめ通知 ' + (i/CHUNK+1) + '/' +
                   (Integer)Math.ceil((Decimal)filtered.size()/CHUNK) + '）'));
    blocks.add(divider());
    // ... 各商談を section/actions で追加 ...
    doPost(JSON.serialize(new Map<String,Object>{ 'blocks' => blocks }));
}


## トラブルシュート

- **ApexClass XML エラー（`cvc-elt.1.a`）**  
  - メタ XML が SFDX 形式になっているか確認（`<ApexClass xmlns=...>` / `<ApexTrigger xmlns=...>`）
- **`Invalid type: SlackConfigProvider.Conf`**  
  - 依存順に注意。`SlackConfigProvider` のデプロイが先行しているかチェック
- **Slack が 401/403**  
  - Webhook URL が無効／権限不足。Named Credential を再確認
- **Git の push で non-fast-forward**  
  - 初期 README がリモートにあるだけなら `git push --force-with-lease` で上書き

---

## ライセンス

このポートフォリオは学習・採用選考の評価目的で公開しています。商用利用や再配布はご相談ください。

---

## 著者

- @pi-cpu — Salesforce エンジニア（Apex／API 連携／テスト自動化）
- 目的：**「標準を尊重しつつ、必要なところだけコードで拡張」** を実務レベルで示すこと
