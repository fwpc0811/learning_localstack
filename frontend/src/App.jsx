import { useState } from 'react';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

// LocalStackの設定
const s3Client = new S3Client({
  region: "us-east-1",
  endpoint: "http://localhost:4566", // ブラウザから見たLocalStackのアドレス
  credentials: {
    accessKeyId: "test",
    secretAccessKey: "test"
  },
  forcePathStyle: true // LocalStackでは必須
});

function App() {
  const [file, setFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState('');

  const handleFileChange = (e) => {
    if (e.target.files) {
      setFile(e.target.files[0]);
    }
  };

  const handleUpload = async () => {
    if (!file) return;
    setUploading(true);
    setMessage('');

    try {
      // ファイルを ArrayBuffer に変換して読み込む
      const fileBody = await file.arrayBuffer();

      const command = new PutObjectCommand({
        Bucket: "my-local-s3-bucket",
        Key: `data/${file.name}`,
        Body: fileBody,
      });

      await s3Client.send(command);
      setMessage(`Upload successful: ${file.name}`);
    } catch (error) {
      console.error(error);
      // ★修正: スタックトレースを含める
      setMessage(`Error: ${error.message}\n\nStack Trace:\n${error.stack}`);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'sans-serif' }}>
      <h1>LocalStack S3 Uploader</h1>
      <input type="file" onChange={handleFileChange} />
      <button onClick={handleUpload} disabled={!file || uploading} style={{ marginLeft: '10px' }}>
        {uploading ? 'Uploading...' : 'Upload'}
      </button>
      
      {/* ★修正: <pre>タグを使い、改行やログを見やすく表示するスタイルを適用 */}
      {message && (
        <pre style={{ 
          marginTop: '20px', 
          padding: '15px', 
          backgroundColor: '#f5f5f5', 
          borderRadius: '5px',
          border: '1px solid #ccc',
          textAlign: 'left',
          whiteSpace: 'pre-wrap',       // 改行をそのまま表示
          overflowWrap: 'break-word',   // 長い行を折り返す
          color: message.startsWith('Error') ? '#d32f2f' : '#2e7d32', // エラーなら赤、成功なら緑
          fontSize: '14px',
          fontFamily: 'monospace'
        }}>
          {message}
        </pre>
      )}
    </div>
  );
}

export default App;