# SOA03-4DAY — Monitoring Applications and Infrastructure を Terraform で実測検証する

AWS Skill Builder「Lab - Monitoring Applications and Infrastructure (SPL-TF-300-SYMON3)」を題材に、
CloudWatch エージェント（Parameter Store 配布）・アラーム・`set-alarm-state`・Lambda Canary を
Terraform で再現し、ラボが省略している運用上の想定 4 本を実機検証するリポジトリ。

## 構成

- **EC2 AppServer**: デフォルト VPC / AL2023 / t3.micro / Session Manager 接続（SSH鍵・ingress なし）/ IMDSv2 必須 / `shutdown -h +1440`（24h 自動 stop の課金セーフティネット）
- **CloudWatch Agent**: 設定 JSON を SSM Parameter Store（`AmazonCloudWatch-AgentConfigFile`）に置き、user_data の `amazon-cloudwatch-agent-ctl -a fetch-config -c ssm:...` で配布（ラボのタスク1〜2相当）
- **myDashboard**: mem_used_percent / NetworkIn・Out / canary 健全性の 3 ウィジェット（タスク3相当）
- **SNS**: `SysOpsTeamPager` トピック。全アラームが `alarm_actions` と `ok_actions`（復旧通知）で接続
- **Lambda Canary**: `rate(1 minute)` の EventBridge ルールで URL を監視（タスク7相当）
- **アラーム 6 本**: 下表参照

| アラーム | 対象 | 役割 |
|---|---|---|
| `AppServerSystemsCheckAlarm` | StatusCheckFailed_System >= 1 | ラボ再現（通知のみ）。set-alarm-state テスト＋自動OK復帰の実測 |
| `AppServerInstanceRebootAlarm` | StatusCheckFailed_Instance >= 1 | **仮説G**: reboot アクション付き。set-alarm-state がアクションも発火させることを実証 |
| `AppServerMemHighAlarm` | CWAgent mem_used_percent > 80 | **仮説H**: 標準メトリクスで見えないメモリ枯渇の検知 |
| `lambda-canary-errors-60s` | Lambda Errors >= 1 (period 60s) | **仮説J**: 検知遅延の period 依存を実測 |
| `lambda-canary-errors-300s` | Lambda Errors >= 1 (period 300s) | **仮説J**: ラボのメール例と同じ period |
| `lambda-canary-alive` | Lambda Invocations < 1 (3/3, breaching) | **仮説I**: canary 自体の停止を検知する「監視の監視」 |

## 使い方

WSL（mise 管理の terraform/aws）のログインシェルで実行する。

```bash
cd ~/projects/SOA03-4DAY
terraform init
terraform plan
terraform apply
```

apply 後、CloudWatch エージェントのメトリクス（CWAgent 名前空間）が出るまで 5〜10 分待つ。

### SNS メール購読（CLI 推奨）

確認メールのリンク直クリックは「確認と同時に自動解除」事故があるため、CLI で確定する:

```bash
TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint you@example.com
# 確認メールの URL を右クリックでコピーし、Token= 以降を抽出して:
aws sns confirm-subscription --topic-arn "$TOPIC_ARN" --token <TOKEN> --authenticate-on-unsubscribe true
# SubscriptionArn が実 ARN（PendingConfirmation でない）なら確認済:
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN"
```

## 検証 Runbook

### 仮説G: set-alarm-state は「状態」だけでなく「アクション」も発火させる

```bash
IID=$(terraform output -raw instance_id)
# 事前の起動時刻を記録
aws ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].LaunchTime'
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids "$IID" --parameters 'commands=["uptime -s"]'

# テストのつもりで ALARM にする → reboot アクションが本当に走る
aws cloudwatch set-alarm-state --alarm-name AppServerInstanceRebootAlarm \
  --state-value ALARM --state-reason "testing purposes"

# 観測: uptime -s が更新される（再起動）＋実メトリクス正常により自動で OK 復帰
aws cloudwatch describe-alarm-history --alarm-name AppServerInstanceRebootAlarm \
  --history-item-type StateUpdate --max-records 5
```

通知のみの `AppServerSystemsCheckAlarm` でも同じテストを行い、ALARM→自動OK復帰までの秒数を比較する。

### 仮説H: メモリ枯渇は CloudWatch Agent でしか見えない

```bash
# 10分間メモリの85%を確保し続ける
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids "$IID" \
  --parameters 'commands=["nohup stress-ng --vm 1 --vm-bytes 85% --vm-hang 0 -t 600 >/tmp/stress.log 2>&1 &"]'

# 観測: mem_used_percent の定常値→ピーク、ALARM 発火時刻、同時刻の CPUUtilization
```

### 仮説I: カナリアの死は誰が見るのか

```bash
# スケジューラ障害（誤操作）を再現
aws events disable-rule --name CheckWebsiteScheduledEvent

# 観測: lambda-canary-errors-* は沈黙のまま（Errors は欠落するだけ）。
#       lambda-canary-alive (Invocations<1, 3/3, breaching) が ALARM になるまでの分数。

# 復旧
aws events enable-rule --name CheckWebsiteScheduledEvent
```

### 仮説J: period 60s vs 300s の検知遅延差

```bash
# ラボと同じ「expected を 404 に書き換えて意図的に失敗させる」
aws lambda update-function-configuration --function-name lambda-canary \
  --environment 'Variables={site=https://docs.aws.amazon.com/lambda/latest/dg/welcome.html,expected=404}'

# 観測: lambda-canary-errors-60s と lambda-canary-errors-300s の
#       ALARM Timestamp 差・SNS メール 2 通の時刻差

# 復旧（terraform apply で環境変数を元に戻すのが確実）
terraform apply
```

## クリーンアップ

```bash
terraform destroy
# 残骸ゼロ確認
aws ec2 describe-instances --filters "Name=tag:Project,Values=SOA03-4DAY" \
  "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].InstanceId'
aws cloudwatch describe-alarms --alarm-name-prefix AppServer --query 'MetricAlarms[].AlarmName'
aws cloudwatch describe-alarms --alarm-name-prefix lambda-canary --query 'MetricAlarms[].AlarmName'
aws lambda get-function --function-name lambda-canary 2>&1 | grep -c NotFound
aws events describe-rule --name CheckWebsiteScheduledEvent 2>&1 | grep -c NotFound
aws sns list-topics --query "Topics[?contains(TopicArn,'SysOpsTeamPager')]"
aws ssm get-parameter --name AmazonCloudWatch-AgentConfigFile 2>&1 | grep -c NotFound
```

## ハマりどころ（実機で踏んだもの・先回り）

- **SSM パラメータ名は `AmazonCloudWatch-` で始める**: マネージドポリシー CloudWatchAgentServerPolicy の `ssm:GetParameter` は `parameter/AmazonCloudWatch-*` にしか許可されていない。ラボの `AgentConfigFile` という名前をそのまま使うと fetch-config が AccessDenied になる（ラボは専用ロールで回避している）。
- **`aws sns subscribe` のメール指定は `--notification-endpoint`**。`--endpoint` はグローバルの `--endpoint-url` に誤解釈され `scheme is missing` で失敗する。
- **SNS 確認リンクの直クリックは自動解除されることがある** → 上記 CLI フローで Token 確定。
- **set-alarm-state はアクションを抑制しない**。修復アクション（reboot/recover 等）付きアラームに使うと本物の修復が走る（仮説Gで実証）。通知テストは通知専用アラームか `aws sns publish` で行う。
- **ロググループは `retention_in_days` を必ず明示**（Lambda が自動作成する既定は無期限）。
- **EC2 アクション付きアラームが `Failed to execute action` になる場合**: アカウントに CloudWatch の EC2 アクション用サービスリンクロールが無い。コンソールで一度 EC2 アクション付きアラームを作るか、`aws iam create-service-linked-role --aws-service-name events.amazonaws.com` 相当の SLR 作成で解消。
