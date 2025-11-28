-- localdb に接続した状態で実行されます

-- DDL (テーブル作成)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    quantity INTEGER
);

-- ユーザーが作成したDBオブジェクトの権限をユーザーに付与
GRANT ALL PRIVILEGES ON TABLE items TO localuser;
GRANT ALL PRIVILEGES ON SEQUENCE items_id_seq TO localuser;

-- DML (初期データ投入)
--------------------------------------------------------------------------------
INSERT INTO items (name, quantity) VALUES
('コーヒー豆', 50),
('牛乳', 20),
('パン', 10),
('卵', 30);

-- 挿入したデータの権限も付与
GRANT ALL PRIVILEGES ON TABLE items TO localuser;

-- シーケンスをリセット（DDLをテストした後の再実行時などに備えて）
SELECT setval('items_id_seq', (SELECT MAX(id) FROM items));