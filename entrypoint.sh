#!/bin/bash
set -e

# エンドポイントの設定
export AWS_ENDPOINT_URL=http://localstack:4566

# --- 初回実行チェック ---
# マーカーファイルが存在しない場合のみ実行
if [ ! -f /app/.initialized ]; then
    echo "初回セットアップを開始します..."

    # LocalStackが起動して応答するまで待機するループ
    echo "⏳ LocalStackの起動を待機中..."
    # s3 ls が成功するまで5秒おきにリトライ
    until awslocal s3 ls > /dev/null 2>&1; do
        echo -n "."
        sleep 5
    done
    echo "LocalStack is ready!"

    # --- 以下、README.md の手順を自動化 ---
    echo "リソースを作成中..."

    # 1. 基本設定
    awslocal configure set endpoint_url http://localstack:4566

    # 2. SQSキューとS3バケット
    awslocal sqs create-queue --queue-name my-local-queue
    awslocal s3 mb s3://my-local-s3-bucket

    # 3. 依存関係のセットアップとZIP化
    echo "ZIPファイルの作成..."
    rm -rf /app/psycopg2*
    pip install aws-psycopg2 -t /app
    
    # /app に移動してZIP化
    cd /app
    rm -f function.zip
    zip -r function.zip . -x "function.zip" -x "*.txt" -x "*.json" -x "*.dist-info" -x ".initialized"

    # 4. Lambda関数のデプロイ
    echo "deploying Lambda 1..."
    awslocal lambda create-function \
        --function-name my-local-lambda \
        --runtime python3.9 \
        --role arn:aws:iam::000000000000:role/irrelevant \
        --handler s3_handler.handler \
        --zip-file fileb:///app/function.zip \
        --environment "Variables={SQS_QUEUE_URL=http://localstack:4566/000000000000/my-local-queue}"

    echo "deploying Lambda 2..."
    awslocal lambda create-function \
        --function-name my-local-lambda-consumer \
        --runtime python3.9 \
        --role arn:aws:iam::000000000000:role/irrelevant \
        --handler lambda_function.handler \
        --zip-file fileb:///app/function.zip \
        --environment "Variables={DB_HOST=postgres,DB_NAME=localdb,DB_USER=localuser,DB_PASS=localpassword}"

    # 5. イベント連携
    echo "Setting up triggers..."
    awslocal lambda create-event-source-mapping \
        --function-name my-local-lambda-consumer \
        --event-source-arn arn:aws:sqs:us-east-1:000000000000:my-local-queue \
        --batch-size 10

    awslocal s3api put-bucket-notification-configuration \
        --bucket my-local-s3-bucket \
        --notification-configuration '{"LambdaFunctionConfigurations": [{"Id": "S3EventTrigger", "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:my-local-lambda", "Events": ["s3:ObjectCreated:*"]}]}'

    # CORS設定 (ブラウザからのアクセス許可) 
    echo "Setting up CORS..."
    echo '{"CORSRules": [{"AllowedHeaders": ["*"], "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"], "AllowedOrigins": ["*"], "ExposeHeaders": ["ETag"]}]}' > /tmp/cors.json
    awslocal s3api put-bucket-cors --bucket my-local-s3-bucket --cors-configuration file:///tmp/cors.json
    
    # 6. DLQ (オプション)
    awslocal sqs create-queue --queue-name my-local-queue-dlq
    DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url http://localstack:4566/000000000000/my-local-queue-dlq --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
    awslocal sqs set-queue-attributes --queue-url http://localstack:4566/000000000000/my-local-queue --attributes "{\"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"

    # --- 完了処理 ---
    # マーカーファイルを作成 (ホストの python/src/.initialized に保存されます)
    touch /app/.initialized
    echo "初回セットアップが完了"
else
    echo "既に初回セットアップ済み"
fi

# 本来のコマンド（CMD ["bash"]）を実行してシェルに入れるようにする
exec "$@"