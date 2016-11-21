## Disregard IAM users, acquire STS keys

One of the best, most compelling features of AWS is all of the tools and APIs available for automation of your infrastructure. Engineers and administrators can take an empty account and have it ready to run scalable production workloads in mere minutes thanks to these tools.

But there's a dark side as well. Everyone has seen the stories of [the bots continuously scouring GitHub for IAM access keys](http://www.programmableweb.com/news/why-exposed-api-keys-and-sensitive-data-are-growing-cause-concern/analysis/2015/01/05), leading to stolen data, public embarrassment, and [thousands of dollars in bills](https://wptavern.com/ryan-hellyers-aws-nightmare-leaked-access-keys-result-in-a-6000-bill-overnight). AWS themselves offer advice on [dealing with exposed keys](https://aws.amazon.com/blogs/security/what-to-do-if-you-inadvertently-expose-an-aws-access-key/).

"Don't show your keys during presentations" and "don't commit your credentials to source control" are pieces of advice that sound easy to follow, but all it takes is one small mistake to compromise your account. Wouldn't it be great if long-lived IAM access keys could be done away with completely?

### The Security Token Service
Most AWS power-users are familiar with IAM roles. For those unfamiliar, these allow you to attach specific IAM policies to your [EC2 instances](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html), [Lambda functions](http://docs.aws.amazon.com/lambda/latest/dg/intro-permission-model.html), and [ECS tasks](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html). Instead of needing to provide long-lived access keys to these resources, they are simply available in the environment and rotated automatically and regularly.

Most of these technologies use the [Security Token Service](http://docs.aws.amazon.com/STS/latest/APIReference/Welcome.html) under the hood. STS provides several APIs for generating temporary access keys for a specific IAM role.

You may also be familiar with STS if you've ever created or used a cross-account role. Many SaaS vendors use [cross-account roles](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user.html) in order to manage customer accounts without needing to store long-lived IAM access keys.

### Federated Login
Providing each person with an IAM user and a set of access keys works great for some organizations. But other organizations may be managing hundreds of users and several AWS accounts. Organizations with such a footprint generally also already have centralized user management with Active Directory, Google GSuite, or some other directory service. At that point, managing AWS users and access control from that same centralized point becomes very attractive. Otherwise, role trusts can become a rat's nest - not to mention a security nightmare waiting to happen - and users may find the process of constantly exchanging credentials and switching between accounts confusing and frustrating.

Luckily, AWS offers [several strategies for federated login](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers.html) through SAML or OpenID Connect identity providers like [Microsoft ADFS](https://aws.amazon.com/blogs/security/enabling-federation-to-aws-using-windows-active-directory-adfs-and-saml-2-0/) and [Google GSuite](https://aws.amazon.com/blogs/security/how-to-set-up-federated-single-sign-on-to-aws-using-google-apps/). There is a more-complete list of SAML providers [in the AWS docs](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml_3rd-party.html).

Federated login allows users of the identity provider to log in to the AWS Management console within a specific IAM role. That means administrators don't need to manage IAM users for people just needing to use the AWS console. Which is cool, but doesn't solve our problem of eliminating IAM access keys - API/SDK users still need keys to use.

### Using Federated Login for STS keys
Like all of the other IAM magic we discussed above, federated login *also* uses STS under the hood - it just uses SAML or OIDC to generate a temporary sign-in URL for getting the user to the console. That means it can also be used to generate raw STS keys using the [`assume-role-with-saml`](http://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithSAML.html) API.

Of course, the hard part of using assume-role-with-saml from the command-line is that you need a SAML assertion generated from authenticating with your identity provider. AWS provides example scripts in some blog posts on how to do this for [ADFS](https://aws.amazon.com/blogs/security/how-to-implement-federated-api-and-cli-access-using-saml-2-0-and-ad-fs/) and [certain other identity providers](https://aws.amazon.com/blogs/security/how-to-implement-a-general-solution-for-federated-apicli-access-using-saml-2-0/), but they are pretty specific to the individual identity provider.

By and large, though, the scripts automate the HTML login form for the identity provider to generate the SAML response, then they send that to AWS to assume the requested role.

Providing users with a script like this means that they can generate STS keys with the same credentials they already use for other systems. And those keys will automatically expire after a short time to limit risk if they ever do get compromised.

In this way, careful account administrators can do away with IAM users entirely and limit their attack surface.

### Putting it all together
Where I work, we have dozens of accounts, hundreds of users, and a few different identity providers. Our situation and our needs are possibly atypical but probably not unique. After a few different attempts, this is the solution that we ended up with.

Due to having several different identity providers that could potentially be attached to any given account, we opted to use [Auth0](https://auth0.com) as our identity provider. It was already in use in a few places throughout the company and allowed us to use it as an identity provider interface and aggregator, abstracting away the differences and allowing us to easily mix and match which are attached to any given account.

Our scripting hooks up the identity provider the same way in every account regardless of if it will use ADFS or Google under the hood, then the identity connections for ADFS etc are enabled based on which types of users will be logging in.

We create a client for each AWS account as described in the [Auth0 documentation](https://auth0.com/docs/integrations/aws#obtain-aws-tokens-to-securely-call-aws-apis-and-resources) and attach account-specific client metadata to the client to enable the login. Then we create an IAM Identity Provider in the AWS account as per [the AWS documentation](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_saml.html).

`auth0-client.json`:
```json
{
  "addons": {
    "samlp": {
      "audience": "https://signin.aws.amazon.com/saml",
      "mappings": {
        "email": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
      },
      "createUpnClaim": false,
      "passthroughClaimsWithNoMapping": false,
      "mapUnknownClaimsAsIs": false,
      "mapIdentities": false,
      "nameIdentifierFormat": "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
      "nameIdentifierProbes": [
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
      ]
    }
  },
  "callbacks": [
    "https://signin.aws.amazon.com/saml"
  ],
  "jwt_configuration": {
    "alg": "HS256",
    "lifetime_in_seconds": 36000,
    "secret_encoded": true
  },
  "token_endpoint_auth_method": "client_secret_post",
  "app_type": "non_interactive"
}
```

`create-client.rb`:
```ruby
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
```

This creates an Auth0 client that will be used for SAML authentication. The client metadata is used by the Auth0 rule to identify which account to place the user into and determine if the user is authorized to assume that role.

The Auth0 rule runs for every authentication and pulls information from the client metadata set above. It then ensures the user is a member of the `aws_default_group` in directory services. If the user is a member, it logs the user into a role named for that group, otherwise it errors out.

A simplified version of the rule is below:
```javascript
function awsAuthorization (user, context, callback) {
  // Pull relevant things out of client metadata
  var aws_account_number = context.clientMetadata.aws_account_number,
    default_group = context.clientMetadata.aws_default_group,
    identity_provider = 'arn:aws:iam::' + aws_account_number + ':saml-provider/Auth0',
    requested_aws_role;

  // See if user is a member of the default group
  requested_aws_role = context.connection + '/' + default_group.replace(/\\/g,'/').replace(/ /g,'+');

  if (user.groups.indexOf(default_group) >= 0) {
    user.awsRole = 'arn:aws:iam::' + aws_account_number + ':role/' + requested_aws_role;
  }

  if (!user.awsRole) {
    return callback("You aren't authorized to login to AWS account " + aws_account_number + "!");
  }

  // 'delegation' protocol means we are just generating STS keys
  if(context.protocol === 'delegation') {
    // Since we're delegating an existing session, the user
    // already has a role assigned.
    var aws_role = user.awsRole.split(',')[0];

    context.addonConfiguration.aws.principal = identity_provider;
    context.addonConfiguration.aws.role = aws_role;
    context.addonConfiguration.aws.mappings = {
      'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier': 'name',
      'https://aws.amazon.com/SAML/Attributes/Role':                          'awsRole',
      'https://aws.amazon.com/SAML/Attributes/RoleSessionName':               'nickname',
      'https://aws.amazon.com/SAML/Attributes/SessionDuration':               'sessionDuration'
    };

  // If we aren't delegating, we are logging in to the console
  } else {

    // SAML federation requires the role to be "$roleName,$IdPName"
    // so let's join them.
    user.awsRole = [user.awsRole, identity_provider].join(',');
    user.sessionDuration = '43200';

    // Used by AWS to map our session to a role
    context.samlConfiguration.mappings = {
      'https://aws.amazon.com/SAML/Attributes/Role': 'awsRole',
      'https://aws.amazon.com/SAML/Attributes/RoleSessionName': 'nickname',
      'https://aws.amazon.com/SAML/Attributes/SessionDuration': 'sessionDuration'
    };
  }

  callback(null, user, context);
}
```

With all of this in place in Auth0 and the AWS account, users simply navigate to `https://[organization].auth0.com/samlp/[client_id]` to log in to the AWS console for the account. We've created a simple redirector service to put friendly names in front of those URLs, but that is out of scope of this article.

That allows us to control logging in to the AWS management console for multiple accounts from a single location, but what about STS keys?

The [Auth0 delegation endpoint](https://auth0.com/docs/integrations/aws#obtain-aws-tokens-to-securely-call-aws-apis-and-resources) for these clients can be used to generate STS keys from anywhere you can make HTTP requests.

`sts.rb`:
```ruby
require 'net/http'
require 'json'
require 'io/console'
require 'pp'

puts 'Username:'
user = STDIN.gets.chomp
puts 'Password:'
pw = STDIN.noecho(&:gets).chomp
puts 'Auth0 Organization:'
organization = STDIN.gets.chomp
puts 'Auth0 Client:'
client = STDIN.gets.chomp

# Authenticate to the client with username/password
uri = URI("https://#{organization}.auth0.com/oauth/ro")
req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
req.body = {
  client_id: client, username: user, password: pw,
  connection: 'adfs', grant_type: 'password', scope: 'openid'
}.to_json
res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(req)
end

# Use the returned JWT to fetch STS keys
uri = URI("https://#{organization}.auth0.com/delegation")
req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
req.body = {
  client_id: client,
  grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
  id_token: JSON.parse(res.body)['id_token'],
  scope: 'openid', api_type: 'aws'
}.to_json

res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(req)
end

pp JSON.parse(res.body)['Credentials']
```

Running that script with valid values will output STS keys that are good for one hour. The script can easily be extended to write these keys to an AWS credentials file or inject them into the environment for use by the AWS CLI or other tooling.

### Conclusion

Using STS through Auth0 for users along with Instance Profiles (etc) for systems, we have been able to ensure that there are no IAM users or long-lived IAM access keys in any of our accounts, simplifying management and increasing security of our accounts.

Users gain and lose access to accounts automatically as they join and leave the company or are added and removed to relevant security groups in our directory services. This means account administrators don't need to spend any extra time or effort managing access to their accounts and users don't need to worry about accidentally exposing their keys or regularly/manually rotating them.
