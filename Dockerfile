# 1. ベースイメージ: 以前使用した Python スリムイメージを使用
FROM python:3.11-slim-bookworm

# 2. 環境変数: DB接続情報と、awslocalのデフォルト設定を定義
ENV AWS_DEFAULT_REGION=us-east-1
ENV AWS_ACCESS_KEY_ID=test
ENV AWS_SECRET_ACCESS_KEY=test
ENV DB_HOST=localhost
ENV DB_NAME=localdb
ENV DB_USER=localuser
ENV DB_PASS=localpassword
ENV AWS_ENDPOINT_URL=http://localstack:4566

# 3. ビルドツールとクライアントツールのインストール
# PostgreSQLドライバ(psycopg2)のビルドに必要なツールと、zip, curl, unzipをインストール
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        curl \
        unzip \
        groff \
        less \
        zip \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# 4. AWS CLIのインストール
# awslocalの依存関係としてAWS CLI本体をインストール
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# エントリポイントスクリプトをコピー
COPY entrypoint.sh /usr/local/bin/
# 実行権限を付与 (Windows環境で作ったファイル用)
RUN chmod +x /usr/local/bin/entrypoint.sh
# 改行コードの自動修正 (Windowsで作成した場合のトラブル防止)
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

# 5. Python依存関係（awslocalとpsycopg2）のインストール
# /appを作業ディレクトリに設定
WORKDIR /app

# エントリポイントを設定
ENTRYPOINT ["entrypoint.sh"]

# psycopg2-binaryとawscli-localをインストールし、/appに配置
RUN pip install --no-cache-dir \
    psycopg2-binary \
    awscli-local

# 6. LambdaコードのコピーとZIP化の準備
# ホストOS側で LambdaコードとZIPファイルを作成するため、コピーや最終ZIP化は手動で行う
# CMD ["bash"] を残しておき、ユーザーがシェルに入れるようにする
CMD ["bash"]

