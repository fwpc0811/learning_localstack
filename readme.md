# LocalStack Learning Project

LocalStack を使用して、AWS サーバーレスアーキテクチャ（S3, Lambda, SQS）と PostgreSQL の連携をローカル環境で行う学習用プロジェクト

## アーキテクチャ

**データフロー:**
`S3 (PutObject)` -\> `Lambda (Producer)` -\> `SQS` -\> `Lambda (Consumer)` -\> `PostgreSQL`
(エラー時: `SQS` -\> `SQS_DL (Dead Letter Queue)`)

1.  **S3**: ファイルアップロードを検知。
2.  **Lambda 1 (`s3_handler.py`)**: S3 イベントを受け取り、ファイル情報を SQS に送信。
3.  **SQS**: メッセージをキューイングし、非同期処理と疎結合を実現。
4.  **Lambda 2 (`lambda_function.py`)**: SQS メッセージをポーリングして起動し、データを PostgreSQL に保存。
5.  **PostgreSQL**: データの永続化。
6.  **SQS\_DL (DLQ)**: 処理に失敗したメッセージを退避（3回リトライ後に移動）。

## ディレクトリ構成

```text
.
├── docker-compose.yml   # 構成定義 (LocalStack, Postgres, Python CLI, Adminer)
├── Dockerfile           # CLIコンテナ用のビルド定義
├── initdb/              # DB初期化用SQL (テーブル作成, データ投入)
├── python/src/          # Lambda関数ソースコード
│   ├── lambda_function.py # Consumer (SQS -> DB)
│   └── s3_handler.py      # Producer (S3 -> SQS)
└── postgres_data/       # DBデータ永続化ディレクトリ (Git対象外)
```

## 前提条件

  * **Docker Desktop**: 起動中であること (Running)。
  * **Git**: インストール済みであること。

-----

## 環境構築 (Setup)

### 1\. プロジェクトの起動

Docker Compose を使用して、LocalStack, PostgreSQL, CLI環境を一括で起動します。

```bash
docker compose up -d --build
```

### 2\. CLIコンテナへの接続

以降の操作（デプロイ、テスト）はすべて、ツールがインストール済みの `cli` コンテナ内で行います。

```powershell
docker compose exec cli bash
```

-----

## リソースのデプロイ (Deployment)

CLIコンテナ内 (`root@...:/app#`) で以下の手順を順に実行し、LocalStack 上にリソースを作成します。
**※ 初回起動時や `docker compose down` 後に必ず実行してください。**

### Step 1: 環境変数の設定

```bash
export AWS_ENDPOINT_URL=http://localstack:4566
awslocal configure set endpoint_url http://localstack:4566
```

### Step 2: SQSキューとS3バケットの作成

```bash
awslocal sqs create-queue --queue-name my-local-queue
awslocal s3 mb s3://my-local-s3-bucket
```

### Step 3: 依存関係のセットアップとZIP化

PostgreSQLドライバ (`psycopg2`) を Lambda 環境に合わせて準備し、ZIP化します。

```bash
# 既存の依存関係をクリアして再インストール (Lambda互換ライブラリ aws-psycopg2)
rm -rf /app/psycopg2*
pip install aws-psycopg2 -t /app

# デプロイ用ZIPの作成 (不要なファイルを除外)
rm -f /app/function.zip
zip -r /app/function.zip . \
    -x "function.zip" \
    -x "*.txt" \
    -x "*.json" \
    -x "psycopg2_binary-*.dist-info"
```

### Step 4: Lambda関数のデプロイ

**Lambda 1: Producer (S3 Handler)**

```bash
awslocal lambda create-function \
    --function-name my-local-lambda \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/irrelevant \
    --handler s3_handler.handler \
    --zip-file fileb:///app/function.zip \
    --environment "Variables={SQS_QUEUE_URL=http://localstack:4566/000000000000/my-local-queue}"
```

**Lambda 2: Consumer (DB Handler)**

```bash
awslocal lambda create-function \
    --function-name my-local-lambda-consumer \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/irrelevant \
    --handler lambda_function.handler \
    --zip-file fileb:///app/function.zip \
    --environment "Variables={DB_HOST=postgres,DB_NAME=localdb,DB_USER=localuser,DB_PASS=localpassword}"
```

### Step 5: イベント連携の設定

**SQS -\> Lambda 2**

```bash
awslocal lambda create-event-source-mapping \
    --function-name my-local-lambda-consumer \
    --event-source-arn arn:aws:sqs:us-east-1:000000000000:my-local-queue \
    --batch-size 10
```

**S3 -\> Lambda 1**

```bash
awslocal s3api put-bucket-notification-configuration \
    --bucket my-local-s3-bucket \
    --notification-configuration '{"LambdaFunctionConfigurations": [{"Id": "S3EventTrigger", "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:my-local-lambda", "Events": ["s3:ObjectCreated:*"]}]}'
```

### Step 6: デッドレターキュー (DLQ) の設定

処理に失敗したメッセージを退避させるためのキューを作成し、メインキューに紐付けます（3回失敗で移動）。

```bash
# 1. DLQ作成
awslocal sqs create-queue --queue-name my-local-queue-dlq

# 2. ARN取得とRedrive Policy設定
DLQ_ARN=$(awslocal sqs get-queue-attributes \
    --queue-url http://localstack:4566/000000000000/my-local-queue-dlq \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)

awslocal sqs set-queue-attributes \
    --queue-url http://localstack:4566/000000000000/my-local-queue \
    --attributes "{\"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"
```

-----

## 動作確認

### 1\. テストデータのアップロード

S3 にファイルをアップロードして、フローをトリガーします。

```bash
# テストファイルの作成
echo "GIT README TEST" > readme-test.txt

# S3へアップロード (ファイル名をユニークにする)
awslocal s3 cp readme-test.txt s3://my-local-s3-bucket/data/test-$(date +%s).txt
```

### 2\. 結果の確認 (DB)

PostgreSQL にデータが格納されているか確認します。

```bash
PGPASSWORD=localpassword psql -h postgres -p 5432 -U localuser -d localdb -c "SELECT * FROM items;"
```

*成功していれば、新しい行が追加されています。*

-----

## データ確認

ブラウザからリソースやデータを確認できます。

| ツール | URL | 用途 |
| :--- | :--- | :--- |
| **LocalStack Dashboard** | [https://app.localstack.cloud](https://app.localstack.cloud) | S3, Lambda, SQS, Logs の確認 |
| **Adminer** | [http://localhost:8081](https://www.google.com/search?q=http://localhost:8081) | PostgreSQL データの閲覧・編集 |

  * **Adminer ログイン情報**:
      * システム: `PostgreSQL`
      * サーバ: `postgres`
      * ユーザ名: `localuser`
      * パスワード: `localpassword`
      * データベース: `localdb`

-----

## 🛑 終了とクリーンアップ

コンテナを停止し、リソースを削除します。

```bash
# CLIコンテナから抜ける
exit

# コンテナの停止と削除
docker compose down
```