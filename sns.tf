# SysOpsTeamPager: 全アラームの通知先トピック。
# メール購読は確認リンク直クリックの自動解除事故を避けるため CLI で行う（README参照）。
resource "aws_sns_topic" "sysops_team_pager" {
  name = "SysOpsTeamPager"
}
