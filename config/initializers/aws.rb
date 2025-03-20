aws_config = { region: ENV["AWS_REGION"] || "us-west-2" }

if (local_dynamo = ENV["DYNAMODB_ENDPOINT"]).present?
  aws_config[:endpoint] = local_dynamo
end

if (aws_key_id = ENV["AWS_ACCESS_KEY_ID"]).present?
  aws_config[:credentials] = Aws::Credentials.new(aws_key_id, ENV["AWS_SECRET_ACCESS_KEY"])
end

Aws.config.update(aws_config)
