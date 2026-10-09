#!/usr/bin/env bash
# Deploys the baby-names sync backend: DynamoDB table + Lambda + public Function URL.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-louis}" AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 AWS_PAGER=""
NAME=baby-names
cd "$(dirname "$0")"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

if ! aws dynamodb describe-table --table-name $NAME >/dev/null 2>&1; then
  aws dynamodb create-table --table-name $NAME --billing-mode PAY_PER_REQUEST \
    --attribute-definitions AttributeName=room,AttributeType=S AttributeName=slot,AttributeType=S \
    --key-schema AttributeName=room,KeyType=HASH AttributeName=slot,KeyType=RANGE >/dev/null
  aws dynamodb wait table-exists --table-name $NAME
  aws dynamodb update-time-to-live --table-name $NAME --time-to-live-specification Enabled=true,AttributeName=ttl >/dev/null
fi

ROLE=$NAME-lambda
if ! aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
  aws iam create-role --role-name $ROLE --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam put-role-policy --role-name $ROLE --policy-name table-access --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"dynamodb:Query\",\"dynamodb:PutItem\"],\"Resource\":\"arn:aws:dynamodb:us-east-2:$ACCOUNT:table/$NAME\"}]}"
  sleep 12
fi

rm -f /tmp/$NAME.zip && (cd lambda && zip -q /tmp/$NAME.zip index.mjs)
if aws lambda get-function --function-name $NAME >/dev/null 2>&1; then
  aws lambda update-function-code --function-name $NAME --zip-file fileb:///tmp/$NAME.zip >/dev/null
else
  aws lambda create-function --function-name $NAME --runtime nodejs22.x --handler index.handler \
    --role arn:aws:iam::$ACCOUNT:role/$ROLE --zip-file fileb:///tmp/$NAME.zip --timeout 10 --memory-size 128 \
    --environment "Variables={TABLE=$NAME}" >/dev/null
  aws lambda wait function-active-v2 --function-name $NAME
  aws lambda create-function-url-config --function-name $NAME --auth-type NONE \
    --cors '{"AllowOrigins":["*"],"AllowMethods":["POST"],"AllowHeaders":["content-type"],"MaxAge":86400}' >/dev/null
  aws lambda add-permission --function-name $NAME --statement-id url-public --action lambda:InvokeFunctionUrl \
    --principal '*' --function-url-auth-type NONE >/dev/null
  aws lambda add-permission --function-name $NAME --statement-id url-invoke --action lambda:InvokeFunction \
    --principal '*' --invoked-via-function-url >/dev/null  # needs AWS CLI >= 2.3x (brew upgrade awscli)
fi
aws lambda get-function-url-config --function-name $NAME --query FunctionUrl --output text
