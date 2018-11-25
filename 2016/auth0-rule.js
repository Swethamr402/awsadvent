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
