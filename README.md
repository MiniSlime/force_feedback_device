# Force Feedback Device

ESP32とWeb Bluetooth APIを使用した力覚フィードバックデバイスの性能評価実験システムです。

## プロジェクト概要

このプロジェクトは、ESP32とWeb Bluetooth APIを使用した力覚フィードバックデバイスの性能評価実験システムです。ESP32がBLEペリフェラルとして動作し、React Webアプリケーションから制御を受け、4つのモーター（L9110Sドライバ）で8方向の推力提示を行います。

また、DJI Telloドローンを使用した方向提示デバイスとしての機能も提供しています。`vertical_force`手法を選択した場合、Telloドローンが8方向に移動して方向提示を行います。

## 技術スタック

### Webアプリケーション
- **フレームワーク**: React 19.2.0 + TypeScript
- **ビルドツール**: Vite 7.2.4
- **ルーティング**: react-router-dom 7.10.0
- **BLE通信**: Web Bluetooth API（Chrome系ブラウザのみ対応）

### ESP32
- **開発環境**: Arduino IDE
- **BLEライブラリ**: ESP32 BLE Arduino
- **モータードライバ**: L9110S（4チャンネル）

### Tello制御（vertical_force手法）
- **ドローン**: DJI Tello
- **ライブラリ**: tellopy (Python)
- **通信**: tellopy経由（バックエンドサーバー経由）
- **バックエンド**: Python + Flask

## セットアップ

### Webアプリケーション

```bash
cd ble_experiment
npm install
npm run dev      # 開発サーバー起動（localhost:5173）
npm run build    # 本番ビルド
```

### ESP32

1. Arduino IDEで`quad_motor_control_ble.ino`を開く
2. ESP32ボードを選択
3. 必要なライブラリをインストール（ESP32 BLE Arduino）
4. アップロード

### Telloサーバー（vertical_force手法を使用する場合）

```bash
cd tello-server
pip install -r requirements.txt
python server.py      # サーバー起動（localhost:3001）
```

**注意**: Telloサーバーを起動する前に、以下を確認してください：
- Python 3.7以上がインストールされていること
- TelloがWi-Fiに接続されていること
- PC/MacがTelloと同じWi-Fiネットワークに接続されていること
- tellopyパッケージがインストールされていること（`pip install tellopy`）

## 使用方法

### horizontal_force手法（ESP32使用）

1. ESP32にスケッチをアップロード
2. Webアプリケーションを起動
3. ホーム画面でBLEデバイスに接続
4. 参加者番号を入力し、手法で「horizontal_force」を選択
5. 実験開始ボタンをクリック
6. 実験完了後、CSVファイルをダウンロード

### vertical_force手法（Tello使用）

1. Telloサーバーを起動（`cd tello-server && python server.py`）
2. TelloをWi-Fiに接続
3. Webアプリケーションを起動
4. ホーム画面でTelloに接続
5. 参加者番号を入力し、手法で「vertical_force」を選択
6. 実験開始ボタンをクリック（自動的に離陸）
7. 実験完了後、CSVファイルをダウンロード（自動的に着陸）

## GitHub Pagesでの公開

このプロジェクトのWebアプリケーションはGitHub Pagesで自動デプロイされます。

### 初回設定

1. GitHubリポジトリの「Settings」→「Pages」に移動
2. 「Source」で「GitHub Actions」を選択
3. `main`ブランチにプッシュすると自動的にデプロイが開始されます

### デプロイ後のアクセス

デプロイが完了すると、以下のURLでアクセスできます：
```
https://YOUR_USERNAME.github.io/force_feedback_device/
```

**注意**: GitHub PagesはHTTPSで提供されるため、Web Bluetooth APIを使用できます。

## ディレクトリ構造

```
force_feedback_device/
├── ble_experiment/              # React Webアプリケーション
│   ├── src/
│   │   ├── App.tsx             # メインアプリケーション
│   │   ├── bleConnection.ts     # BLE接続状態管理
│   │   ├── telloConnection.ts   # Tello接続状態管理
│   │   └── ...
│   └── package.json
├── tello-server/                # Tello制御用バックエンドサーバー
│   ├── server.py                # tellopyを使用したPythonサーバー
│   ├── server.js                # 旧Node.jsサーバー（参考用）
│   ├── requirements.txt         # Python依存パッケージ
│   └── package.json            # 旧Node.js設定（参考用）
├── quad_motor_control_ble.ino  # メインESP32スケッチ
├── ble_led_ble_test.ino        # テスト用ESP32スケッチ
├── quad_motor_control.ino      # モーター制御のみのベーススケッチ
├── AGENTS.md                     # 詳細ドキュメント
└── README.md                     # このファイル
```

## BLE通信仕様

- **Service UUID**: `12345678-1234-1234-1234-1234567890ab`
- **Characteristic UUID**: `abcd1234-5678-90ab-cdef-1234567890ab`
- **プロパティ**: WRITE / WRITE_NR

## ライセンス

このプロジェクトのライセンス情報は含まれていません。

## 詳細ドキュメント

詳細な技術仕様や開発者向けドキュメントは`AGENTS.md`を参照してください。

