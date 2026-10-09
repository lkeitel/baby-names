#!/usr/bin/env bash
# Removes everything deploy.sh created.
export AWS_PROFILE="${AWS_PROFILE:-louis}" AWS_REGION=us-east-2 AWS_PAGER=""
NAME=baby-names
aws lambda delete-function-url-config --function-name $NAME
aws lambda delete-function --function-name $NAME
aws iam delete-role-policy --role-name $NAME-lambda --policy-name table-access
aws iam detach-role-policy --role-name $NAME-lambda --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name $NAME-lambda
aws dynamodb delete-table --table-name $NAME
