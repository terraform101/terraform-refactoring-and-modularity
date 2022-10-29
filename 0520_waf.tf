# WAF web ACL 생성

# lb 용 waf (ingress로 alb만든 후 적용 필요 여부 확인)
resource "aws_wafv2_web_acl" "waf_lb" {
  name  = "waf-${var.env}-${var.pjt}-lb"
  scope = "REGIONAL" # scope 은 CLoudFront일 때만 "CLOURFRONT", 그 외에 ALB, API GW에서 사용하는 ACL은 "REGIONAL"로 설정함
  default_action {
    allow {}
  } # default_action은 rule에 포함되지 않은 요청이 인입될 경우 디폴트 동작. 보안 가이드에 따라야 함 (block or allow)

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-${var.env}-${var.pjt}-lb"
    sampled_requests_enabled   = true # AWS WAF가 규칙과 일치하는 웹 요청의 샘플링을 저장해야하는지 여부를 나타내는 부울

  }

  tags = {
    Name    = "waf-${var.env}-${var.pjt}-lb",
    Service = "lb"
  }
}
