import os
import json
import psycopg2

def handler(event, context):
    print("--- Lambda function starting DB operation ---")
    
    DB_HOST = os.environ.get("DB_HOST", "postgres") # デフォルトをpostgresに変更
    DB_NAME = os.environ.get("DB_NAME", "localdb")
    DB_USER = os.environ.get("DB_USER", "localuser")
    DB_PASS = os.environ.get("DB_PASS", "localpassword")
    
    conn = None
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS
        )
        cur = conn.cursor()
        
        # --- 修正: バッチ処理対応 (ループ処理) ---
        for record in event['Records']:
            try:
                message_body_str = record['body']
                message_data = json.loads(message_body_str)
                s3_key = message_data.get('key')
                
                print(f"Processing S3 Key: {s3_key}")

                sql = "INSERT INTO items (name, quantity) VALUES (%s, %s);"
                cur.execute(sql, (s3_key, 1))
            except Exception as e:
                print(f"Error processing record: {e}")
                # 個別のレコードエラーはログに出して、他のレコードの処理を継続
                continue
        # ----------------------------------------
        
        conn.commit()
        cur.close()
        
        return {'statusCode': 200, 'body': json.dumps('Batch processed successfully.')}

    except Exception as e:
        print(f"Critical DB Error: {e}")
        # DB接続エラーなどは致命的なのでraiseする
        raise e
    finally:
        if conn:
            conn.close()