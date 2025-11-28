import os
import json
import psycopg2

def handler(event, context):
    print("--- Lambda function starting DB operation ---")
    
    # 環境変数からDB接続情報を取得
    DB_HOST = os.environ.get("DB_HOST", "localhost")
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
        
        # SQSから渡されたメッセージボディを取得
        # SQSイベントはRecordsリストで渡されるため、最初のレコードを使用
        message_body_str = event['Records'][0]['body']

        # SQSメッセージボディ（JSON文字列）をPythonオブジェクトに変換
        message_data = json.loads(message_body_str)

        # DBに登録したいデータ（S3のキー）を取得
        s3_key = message_data.get('key')
        
        # データベース操作（テーブルにS3のキーを挿入）
        sql = "INSERT INTO items (name, quantity) VALUES (%s, %s);"
        cur.execute(sql, (s3_key, 1)) # nameにs3_keyを、quantityに1を挿入
        
        # 変更をコミット
        conn.commit()
        print(f"Successfully inserted message: {message_body_str}")
        
        cur.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data inserted successfully.')
        }

    except Exception as e:
        print(f"Error connecting to or operating database: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'DB Error: {e}')
        }
    finally:
        if conn:
            conn.close()