# Force Feedback Device

ESP32とWeb Bluetooth APIを使用した力覚フィードバックデバイスの性能評価実験システムです。

## プロジェクト概要

このプロジェクトは、ESP32とWeb Bluetooth APIを使用した力覚フィードバックデバイスの性能評価実験システムです。ESP32がBLEペリフェラルとして動作し、React Webアプリケーションから制御を受け、4つのモーター（L9110Sドライバ）で8方向の推力提示を行います。

現在は`wrist-worn`と`hand-grip`の2つの手法をサポートしており、両方ともBLE接続を使用します。実験フローは同じで、CSV保存時の手法名のみが異なります。

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

### Tello制御（現在未使用）
- **ドローン**: DJI Tello
- **ライブラリ**: tellopy (Python)
- **通信**: tellopy経由（バックエンドサーバー経由）
- **バックエンド**: Python + Flask
- **注意**: 現在の実装では使用されていません。コードは残していますが、実験フローでは使用されません。

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

### Telloサーバー（現在未使用）

**注意**: 現在の実装ではTelloサーバーは使用されていません。以下の情報は参考用です。

```bash
cd tello-server
pip install -r requirements.txt
python server.py      # サーバー起動（localhost:3001）
```

以前の実装では、Telloサーバーを起動する前に以下を確認する必要がありました：
- Python 3.7以上がインストールされていること
- TelloがWi-Fiに接続されていること
- PC/MacがTelloと同じWi-Fiネットワークに接続されていること
- tellopyパッケージがインストールされていること（`pip install tellopy`）

## 使用方法

### wrist-worn / hand-grip手法（両方ともESP32使用）

両方の手法とも同じ手順で使用します。実験フローも同じで、CSV保存時の手法名のみが異なります。

1. ESP32にスケッチをアップロード
2. Webアプリケーションを起動
3. ホーム画面でBLEデバイスに接続
4. 参加者番号を入力し、手法で「Wrist-worn」または「Hand-grip」を選択
5. 実験開始ボタンをクリック
6. 実験完了後、CSVファイルをダウンロード

**実験フロー**:
- 3秒待機 → BLEで方向送信 → 3秒間モーター動作
- 円形回答エリアで方向をクリック（1°刻み）
- 8方向×2セット（計16試行）をランダム順で提示

**CSV出力**:
実験完了後、以下のデータを含むCSVファイルをダウンロードできます：
- 参加者番号、手法、試行番号、正解方向、回答角度、回答時間
- 誤差（正解方向と回答角度の絶対誤差、度単位）
- 正答フラグ（誤差≤30度なら1、>30度なら0、スキップ時は-1）

詳細なCSV形式は`AGENTS.md`を参照してください。

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

