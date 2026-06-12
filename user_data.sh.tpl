#!/bin/bash
# install -> configure の順序を保証。各ステップは非致命にしてコアを止めない。
dnf install -y amazon-cloudwatch-agent || echo "WARN: cloudwatch agent install failed"
dnf install -y stress-ng || echo "WARN: stress-ng install failed"

# Parameter Store の設定で CloudWatch Agent を起動（ラボの ssm:AgentConfigFile 相当）
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c ssm:${cw_agent_param} || echo "WARN: cloudwatch agent configure failed"

# destroy 忘れの課金セーフティネット: 24時間後に自動 stop（terminate ではない）
shutdown -h +1440
