def construct_client_config(account_name, account_number, default_group, mfa_type)
  client = JSON.parse(File.read(File.expand_path('./auth0-client.json', __FILE__)))
  client["name"] = account_name
  client["client_metadata"] = {
    "aws_default_group" => default_group,
    "aws_account_number" => account_number
  }

  client
end

my_client = construct_client_config("aws-myaccount", "123456789012", "domain\\aws_admins")
auth0.create_client("aws-myaccount", my_client)
