import os
import json
import psycopg2

def handler(event, context):
    print("--- Lambda function starting DB operation ---")
    
    # 環境変数からDB接続情報を取得
    DB_HOST = os.environ.get("DB_HOST", "postgres") # LocalStackでのデフォルトホスト名
    DB_NAME = os.environ.get("DB_NAME", "localdb")
    DB_USER = os.environ.get("DB_USER", "localuser")
    DB_PASS = os.environ.get("DB_PASS", "localpassword")
    
    conn = None
    try:
        # PostgreSQLに接続
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS
        )
        cur = conn.cursor()
        
        # --- Records をループで回す ---
        # SQSは一度に複数のメッセージ(Batch)を渡すことがあるため、全て処理する必要があります
        for record in event['Records']:
            try:
                # SQSメッセージボディを取得
                message_body_str = record['body']
                print(f"Processing message: {message_body_str}")

                # JSON変換
                message_data = json.loads(message_body_str)

                # S3キー取得
                s3_key = message_data.get('key')
                
                # DB登録
                sql = "INSERT INTO items (name, quantity) VALUES (%s, %s);"
                cur.execute(sql, (s3_key, 1))
                
            except Exception as e:
                # バッチ内の一つのメッセージで失敗しても、他の処理は止めないようにログを出して継続
                print(f"Error processing a record: {e}")
                # 本番ではここ失敗したメッセージだけDLQに送るなどの制御が必要ですが、
                # 簡易的にはここでエラーログを出してスキップします
                continue
        # ----------------------------------------
        
        # 変更をコミット
        conn.commit()
        cur.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps('Batch processed successfully.')
        }

    except Exception as e:
        print(f"Critical DB Error: {e}")
        # DB接続自体が失敗した場合はLambda全体をエラーにしてリトライさせる
        raise e
    finally:
        if conn:
            conn.close()