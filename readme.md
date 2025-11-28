# 起動コマンド
docker compose up -d --build

# CLIコンテナへの接続
docker compose exec cli bash

# コンテナの停止と削除
docker compose down

# 再起動
docker compose up -d

# S3バケットの作成コマンド
awslocal s3 mb s3://my-local-s3-bucket

# S3バケットにPutイベント通知を設定するコマンド
awslocal s3api put-bucket-notification-configuration \
    --bucket my-local-s3-bucket \
    --notification-configuration '{"LambdaFunctionConfigurations": [
        {
            "Id": "S3EventTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:my-local-lambda",
            "Events": ["s3:ObjectCreated:*"]
        }
    ]}'

# 初期設定
# 1. Lambdaコードの更新（ZIPファイルの再作成が必要です）
# /appは ./python/src にマウントされています。
rm -f /app/function.zip
zip -r /app/function.zip . -x "function.zip" -x "output.log"

# 2. Lambda関数の更新と環境変数の設定
QUEUE_URL="http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/my-local-queue"

awslocal lambda update-function-code \
    --function-name my-local-lambda \
    --zip-file fileb:///app/function.zip

awslocal lambda update-function-configuration \
    --function-name my-local-lambda \
    --handler s3_handler.handler \
    --environment "Variables={SQS_QUEUE_URL=$QUEUE_URL,DB_HOST=postgres,DB_NAME=localdb,DB_USER=localuser,DB_PASS=localpassword}"

# 3. SQSにメッセージを送信し、DB挿入をトリガー
awslocal sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "PostgreSQLへの最終確認テスト"

# 4. psqlでデータ確認 (成功すれば、itemsテーブルに新しい行が追加されます)
psql -h postgres -p 5432 -U localuser -d localdb
# localdb=# SELECT * FROM items; # 5行になっているか確認
# 初期設定ここまで


# LocalStack Learning Project: Serverless Async Architecture

LocalStack を使用して、AWS サーバーレスアーキテクチャ（S3, Lambda, SQS）と PostgreSQL の連携をローカル環境でシミュレーションする学習用プロジェクトです。

## 🏗️ アーキテクチャ

**フロー:** `S3 (PutObject)` -> `Lambda (Producer)` -> `SQS` -> `Lambda (Consumer)` -> `PostgreSQL`

1.  **S3**: ファイルアップロードを検知。
2.  **Lambda 1 (`s3_handler.py`)**: S3 イベントをトリガーに起動し、ファイル情報を SQS に送信。
3.  **SQS**: メッセージをキューイングし、非同期処理を実現。
4.  **Lambda 2 (`lambda_function.py`)**: SQS メッセージをポーリングして起動し、データを PostgreSQL に保存。
5.  **PostgreSQL**: データの永続化。

## 📂 ディレクトリ構成

```text
.
├── docker-compose.yml   # 構成定義 (LocalStack, Postgres, Python CLI)
├── Dockerfile           # CLIコンテナ用のビルド定義
├── initdb/              # DB初期化用SQL (テーブル作成, データ投入)
├── python/src/          # Lambda関数ソースコード
│   ├── lambda_function.py # Consumer (SQS -> DB)
│   └── s3_handler.py      # Producer (S3 -> SQS)
└── postgres_data/       # DBデータ永続化ディレクトリ (Git対象外)