import os
import json
import boto3

# SQSのキューURLは環境変数から取得
SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')

def handler(event, context):
    """
    S3イベントを受け取り、その情報をSQSに送信する
    """
    if not SQS_QUEUE_URL:
        print("Error: SQS_QUEUE_URL environment variable is not set.")
        return {'statusCode': 500}

    print(f"Received S3 event batch with {len(event['Records'])} records.")
    
    sqs = boto3.client('sqs', endpoint_url='http://localstack:4566')
    
    # S3イベントのレコードをループ処理
    for record in event['Records']:
        
        # S3イベントからバケット名とキー（ファイルパス）を取得
        bucket_name = record['s3']['bucket']['name']
        object_key = record['s3']['object']['key']
        
        # SQSに渡すメッセージを作成
        message_body = {
            'bucket': bucket_name,
            'key': object_key,
            'event_time': record['eventTime']
        }
        
        try:
            # SQSキューにメッセージを送信
            sqs.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(message_body)
            )
            print(f"Sent message to SQS for s3://{bucket_name}/{object_key}")
            
        except Exception as e:
            print(f"Error sending message to SQS: {e}")
            # エラー発生時はログを残して処理を継続（またはエラーとして返す）
            continue
            
    return {'statusCode': 200, 'body': f"Processed {len(event['Records'])} S3 records."}