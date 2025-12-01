
module "db" {
  #checkov:skip=CKV_AWS_293:demo only, no deletion protection is needed
  #checkov:skip=CKV2_AWS_60:demo only, no backup is needed
  #checkov:skip=CKV_AWS_338:demo only, log retention is not required
  #checkov:skip=CKV_AWS_304:demo only, secret rotation is not required

  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-rds?ref=0a4405c039d0149fe05bfe8f19a1bbbba17ceb0d"

  identifier = "petclinic-database"

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16" # DB parameter group
  major_engine_version = "16"         # DB option group
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = "postgres"
  manage_master_user_password = false
  username = "djangouser"
  password = "asdfqwer"
  port     = 5432

  # setting manage_master_user_password_rotation to false after it
  # has been set to true previously disables automatic rotation
  manage_master_user_password_rotation              = false
  # master_user_password_rotate_immediately           = false
  # master_user_password_rotation_schedule_expression = "rate(15 days)"

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "monitoring-role"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Description for monitoring role"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }

  depends_on = [ module.vpc ]
}

resource "aws_dynamodb_table" "billing_table" {
  #checkov:skip=CKV2_AWS_16:demo only, autoscaling is not needed
  #checkov:skip=CKV_AWS_119:demo only, no encryption is needed

  name           = "BillingInfo"
  billing_mode   = "PROVISIONED"
  read_capacity  = 2
  write_capacity = 2
  hash_key       = "ownerId"
  range_key      = "timestamp"

  point_in_time_recovery {
   enabled = true
  }

  # server_side_encryption {
  #   enabled     = true
  # }

  attribute {
    name = "ownerId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

}

resource "aws_dynamodb_table" "apm_test_table" {
  #checkov:skip=CKV2_AWS_16:demo only, autoscaling is not needed
  #checkov:skip=CKV_AWS_119:demo only, no encryption is needed

  name           = "apm_test"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  point_in_time_recovery {
   enabled = true
  }

  # server_side_encryption {
  #   enabled     = true
  # }

  attribute {
    name = "id"
    type = "S"
  }

}

resource "aws_dynamodb_table" "payment_table" {
  #checkov:skip=CKV2_AWS_16:demo only, autoscaling is not needed
  #checkov:skip=CKV_AWS_119:demo only, no encryption is needed

  name           = "PetClinicPayment"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  point_in_time_recovery {
   enabled = true
  }

  # server_side_encryption {
  #   enabled     = true
  # }

  attribute {
    name = "id"
    type = "S"
  }

}

resource "aws_dynamodb_table" "tickets_table" {
  #checkov:skip=CKV_AWS_119:demo only, no encryption is needed

  name           = "Tickets"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ticketId"

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "ticketId"
    type = "S"
  }
}

resource "aws_appautoscaling_target" "tickets_write_target" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.tickets_table.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "tickets_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.tickets_write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.tickets_write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.tickets_write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.tickets_write_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_target" "tickets_read_target" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.tickets_table.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "tickets_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.tickets_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.tickets_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.tickets_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.tickets_read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70.0
  }
}
