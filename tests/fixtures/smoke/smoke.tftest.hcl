mock_provider "aws" {
  # aws_iam_policy_document produces JSON strings that must be valid policy JSON.
  # The generic mock behavior generates arbitrary strings for computed attributes,
  # which breaks resources that validate JSON (like aws_iam_role.assume_role_policy).
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "plan_smoke" {
  command = plan

  # This output is derived from naming locals/inputs and should be deterministic even with mocking.
  assert {
    condition     = module.sut.ecs_service_name == "gh-runner-example-service"
    error_message = "Expected ECS service name to match derived naming convention."
  }
}

