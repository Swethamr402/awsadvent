set -e

SAM_DEPLOYMENT_BUCKET='its-my-bucket-and-ill-deploy-if-i-want-to'
STACK_NAME='hello-sam'

function ensureBucket()
{
  echo "Checking for deployment bucket $1..."
  local bucketCheck=`aws s3api list-buckets --query "contains(Buckets[].[Name][], '$1')"`  
  if [ $bucketCheck = "false" ] ; then
    echo " -> Bucket not found, creating..."
    if [ $2 = 'us-east-1' ] ; then
      aws s3api create-bucket --bucket $1 \
        --region $2
    else
      aws s3api create-bucket --bucket $1 \
        --create-bucket-configuration LocationConstraint=$2 \
        --region $2
    fi
    
    aws s3api put-bucket-encryption --bucket $1 --region $2 \
      --server-side-encryption-configuration '{
        "Rules":[{
          "ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}
        }]}'
    echo " -> Success!"
  else
    echo " -> Bucket already exists, continuing..."
  fi
}

function packageRegion()
{
  echo "Packaging and uploading for $1"
  sam package --template-file template.yaml \
    --s3-bucket $SAM_DEPLOYMENT_BUCKET-$1 \
    --output-template-file deploy-template-$1.yaml \
    --region $1
}

function deployRegion()
{
  sam deploy --template-file deploy-template-$1.yaml \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides DomainName=$DOMAIN_NAME HostedZoneId=$HOSTED_ZONE_ID \
    --no-fail-on-empty-changeset \
    --region $1
}

function ensureGlobalTable()
{
  echo "Checking global table status"
  hasGlobalTable=`aws dynamodb list-global-tables --region us-east-1 \
    --query "contains(GlobalTables[*].[GlobalTableName][],'$1')"`

  if [ $hasGlobalTable = "false" ] ; then
    echo " -> Global Table does not exist, creating..."
    aws dynamodb create-global-table --global-table-name $1 \
      --replication-group RegionName=us-east-1 RegionName=eu-west-1 RegionName=ap-southeast-1 \
      --region us-east-1
    echo " -> Success!"
  else
    echo " -> Global table already exists, continuing..."
  fi
}

# Deploy the CFN stack to each region
for region in 'us-east-1' 'eu-west-1' 'ap-southeast-1'; do
  ensureBucket "$SAM_DEPLOYMENT_BUCKET-$region" $region
  packageRegion $region
  deployRegion $region
done

# Ensure the DynamoDb Global Table is hooked up
ensureGlobalTable "HitsTable"