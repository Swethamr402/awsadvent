const {DynamoDB} = require('aws-sdk'),
  dynamo = new DynamoDB();

if(process.env.AWS_SAM_LOCAL) {
  console.log("RUNNING LOCALLY")
  process.env.HITS_TABLE_NAME='HitsTableLocal';
}

exports.health = async () => {
  return {
    statusCode: 200
  };
}

exports.hello = async (event) => {
  const sourceIp = event.requestContext.identity.sourceIp;

  let resp = await dynamo.updateItem({
    TableName: process.env.HITS_TABLE_NAME,
    Key: {
      ipAddress: { S: sourceIp}
    },
    UpdateExpression: 'ADD hits :h',
    ExpressionAttributeValues: {
      ':h': { N: '1' }
    },
    ReturnValues: 'ALL_NEW'
  }).promise();

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: `hello from ${process.env.AWS_REGION}, ${sourceIp}`,
      visits: resp.Attributes.hits.N
    })
  };
};
