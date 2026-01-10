# Force Feedback Device - AI開発者向けドキュメント

## プロジェクト概要

このプロジェクトは、ESP32とWeb Bluetooth APIを使用した力覚フィードバックデバイスの性能評価実験システムです。ESP32がBLEペリフェラルとして動作し、React Webアプリケーションから制御を受け、4つのモーター（L9110Sドライバ）で8方向の推力提示を行います。

**注意**: 以前はTelloドローンを使用した`vertical_force`手法も提供していましたが、現在は`wrist-worn`と`hand-grip`の2つの手法のみをサポートしており、両方ともBLE接続を使用します。Tello関連のコードは残していますが、現在は使用されていません。

## ディレクトリ構造

```
force_feedback_device/
├── ble_experiment/              # React Webアプリケーション
│   ├── src/
│   │   ├── App.tsx             # メインアプリケーション（ホーム画面・実験画面）
│   │   ├── App.css             # アプリケーションスタイル
│   │   ├── main.tsx            # エントリーポイント
│   │   ├── bleConnection.ts     # BLE接続状態管理（グローバル）
│   │   ├── telloConnection.ts   # Tello接続状態管理
│   │   ├── bluetooth.d.ts      # Web Bluetooth API型定義
│   │   └── index.css           # グローバルスタイル
│   ├── package.json
│   └── vite.config.ts
├── tello-server/                # Tello制御用バックエンドサーバー
│   ├── server.py                # tellopyを使用したPythonサーバー
│   ├── requirements.txt         # Python依存パッケージ
│   └── package.json            # 旧Node.js設定（参考用）
├── quad_motor_control_ble.ino  # メインESP32スケッチ（モーター制御+BLE）
├── ble_led_ble_test.ino        # テスト用ESP32スケッチ（LED制御のみ）
├── quad_motor_control.ino      # モーター制御のみのベーススケッチ
├── AGENTS.md                     # 実験フロー要件
└── issue_list.txt              # 既知の問題・改善点リスト
```

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

### Tello制御（非推奨・現在未使用）
- **ドローン**: DJI Tello
- **ライブラリ**: tellopy (Python)
- **通信**: tellopy経由（バックエンドサーバー経由）
- **バックエンド**: Python + Flask
- **特徴**: Tello SDK 2.0の自動安全機能を回避し、腕に装着した状態でも制御可能
- **注意**: 現在の実装では使用されていません。コードは残していますが、実験フローでは使用されません。

## 主要機能

### 1. ホーム画面 (`/`)
- **BLEデバイス接続管理**（両方の手法で使用）
  - デバイス選択・接続・切断
  - 接続状態の表示
  - 接続ログの表示
  - テキスト送信機能（デバッグ用）
- **実験設定**
  - 参加者番号入力
  - 手法選択（`wrist-worn` / `hand-grip`）
  - 実験開始ボタン（BLE接続必須）

### 2. 実験画面 (`/experiment`)
- **実験フロー**（両方の手法とも同じフロー）
  1. 開始ボタンで実験開始
  2. 8方向×2セット（計16試行）をランダム順で提示
  3. 各タスク:
     - 3秒待機 → BLEで方向送信 → 3秒間モーター動作
     - 円形回答エリアで方向をクリック（1°刻み）
     - 「次のタスク」または「スキップ」で次へ
  4. 全試行完了後、CSVダウンロード
- **回答記録**
  - 正解方向（0, 45, 90, 135, 180, 225, 270, 315度）
  - 参加者の回答角度（0-360度、または-1=スキップ）
  - 回答時間（ミリ秒、力覚提示開始から回答完了まで）
  - 誤差（正解方向と回答角度の絶対誤差、度単位、360度の循環を考慮）
  - 正答フラグ（誤差≤30度なら1、>30度なら0、スキップ時は-1）
  - **手法名**: CSVには`wrist-worn`または`hand-grip`が記録される（実験フローは同じ）

## BLE通信仕様

### UUID
- **Service UUID**: `12345678-1234-1234-1234-1234567890ab`
- **Characteristic UUID**: `abcd1234-5678-90ab-cdef-1234567890ab`
- **プロパティ**: WRITE / WRITE_NR

### 通信プロトコル
- **送信形式**: UTF-8テキスト（`TextEncoder`でエンコード）
- **受信形式**: Arduino `String`として受信
- **コマンド**:
  - `"0"`, `"45"`, `"90"`, `"135"`, `"180"`, `"225"`, `"270"`, `"315"`: モーターを指定方向に3秒間動作（デューティー比100%）
  - `"0 50"`, `"90 75"` などの形式: 角度とデューティー比（0-100%）を指定してモーターを3秒間動作
    - 例: `"0 50"` = 角度0°、デューティー比50%で動作
    - 例: `"90 75"` = 角度90°、デューティー比75%で動作
  - `"BLINK"`: LED点滅
  - その他: LED一定時間点灯

## ESP32スケッチ仕様

### `quad_motor_control_ble.ino`（メイン）
- **機能**:
  - BLEペリフェラルとして動作
  - 4つのモーター（右・前・左・後）を8方向制御
  - LED制御（点滅・点灯）
- **モーター制御**:
  - `controlMotor(direction, enabled, dutyCyclePercent)`: 指定方向（0-360度）に推力発生
    - `dutyCyclePercent`: デューティー比（0-100%、デフォルト100%）
  - `controlMotorSingle(inaPin, inbPin, thrust, dutyCyclePercent)`: 単一モーター制御
    - `dutyCyclePercent`: デューティー比（0-100%、デフォルト100%）
  - 8方向: 0, 45, 90, 135, 180, 225, 270, 315度
  - デューティー比: 0-100%の範囲で指定可能（PWM制御）
- **非同期LED点滅**: `ledBlinkPattern()`は非ブロッキング実装

### `ble_led_ble_test.ino`（テスト用）
- BLE + LED制御のみ（モーター制御なし）
- デバッグ・テスト用途

## 実験フロー詳細

### タスク進行
1. **待機状態** (`idle`)
   - 「開始」ボタンのみ表示
   - BLE接続チェック

2. **刺激提示中** (`stimulating`)
   - 3秒待機（`isStimActive === null`）
   - BLE送信 → モーター動作開始（同時に`isStimActive = true`）
   - 3秒間「力覚提示中」表示
   - 回答時間タイマー開始（`responseStartTime`）
   - 3秒後、`isStimActive = false`（回答可能）

3. **完了** (`finished`)
   - 全16試行完了
   - CSVダウンロード可能

### データ記録
CSV形式:
```csv
participantId,method,trialIndex,trueDirection,responseAngle,responseTimeMs,error,isCorrect
P001,wrist-worn,0,90,87.5,2340,2.5,1
P002,hand-grip,0,45,42.3,1890,2.7,1
P003,wrist-worn,1,180,220.0,3120,40.0,0
P004,hand-grip,2,270,-1,5000,,,
...
```

**CSVカラム説明**:
- `participantId`: 参加者番号
- `method`: 使用手法（`wrist-worn`または`hand-grip`）
- `trialIndex`: 試行番号（0から開始）
- `trueDirection`: 正解方向（0, 45, 90, 135, 180, 225, 270, 315度）
- `responseAngle`: 参加者の回答角度（0-360度、スキップ時は-1）
- `responseTimeMs`: 回答時間（力覚提示開始から回答完了までの時間、ミリ秒）
- `error`: 誤差（正解方向と回答角度の絶対誤差、度単位）。360度の循環を考慮して計算（例: 0度と350度の差は10度）。スキップ時は空文字
- `isCorrect`: 正答フラグ（誤差≤30度なら1、>30度なら0、スキップ時は-1）

**手法名の違い**: `wrist-worn`と`hand-grip`の2つの手法がありますが、実験フローは全く同じです。CSVに記録される手法名のみが異なります。

## 重要な実装詳細

### BLE接続管理
- **グローバル状態**: `bleConnection.ts`で`BluetoothRemoteGATTCharacteristic`を保持
- **ホーム画面**: 接続確立後、`setBleCharacteristic()`で保存
- **実験画面**: `getBleCharacteristic()`で取得して使用
- **制約**: 実験画面遷移にはBLE接続必須（ボタン無効化で制御）

### タイマー管理
- **`stimTimeoutRef`**: 力覚提示中の3秒タイマー
- **`elapsedTimeIntervalRef`**: 回答時間のリアルタイム更新（100ms間隔）
- **クリーンアップ**: 各タスク開始時に前のタスクのタイマーをクリア

### 状態管理
- **`status`**: `'idle' | 'stimulating' | 'finished'`
- **`isStimActive`**: `null`（待機中）| `true`（提示中）| `false`（提示終了）
- **`responseAngle`**: `null`（未回答）| `number`（0-360度）| `-1`（スキップ）

### UI/UX
- **画面中央配置**: `position: fixed`で全画面対応
- **メッセージ表示統一**: 実験画面の`helper-text`は全て同じスタイル（背景・ボーダー・パディング）
- **回答エリア**: 画面中心を起点とした円形クリック領域（反時計回り0-360度）

## 開発時の注意点

### BLE接続
- **ブラウザ制限**: Chrome/Edge等のChromium系のみ対応
- **HTTPS必須**: 本番環境ではHTTPSが必要（localhostは例外）
- **接続タイムアウト**: デバイスが見つからない場合はエラーハンドリング必須

### ESP32
- **モーター動作時間**: 3秒固定（`MOTOR_RUN_DURATION_MS`）
- **デューティー比制御**: コマンドで0-100%の範囲で指定可能（PWM制御）
- **モーター起動**: 起動時は100%で起動し、一定時間後に指定デューティー比に切り替え
- **LED非同期処理**: `loop()`で`updateLedBlink()`を呼び出し
- **シリアル出力**: デバッグ情報は115200bpsで出力

### 実験フロー
- **ランダム化**: 1セット（8方向）をシャッフル → 2セット目をシャッフル → 結合
- **スキップ処理**: `responseAngle = -1`として記録、自動で次タスクへ
- **タイマー競合**: 前タスクのタイマーを必ずクリア
- **手法の違い**: `wrist-worn`と`hand-grip`の実験フローは全く同じ。CSV保存時の手法名のみが異なる

## 既知の問題・改善点

- `issue_list.txt`を参照

## ビルド・実行方法

### Webアプリケーション
```bash
cd ble_experiment
npm install
npm run dev      # 開発サーバー起動（localhost:5173）
npm run build    # 本番ビルド
```

### ESP32
- Arduino IDEで`quad_motor_control_ble.ino`を開く
- ESP32ボードを選択
- 必要なライブラリをインストール（ESP32 BLE Arduino）
- アップロード

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

## ファイル変更時の影響範囲

### `App.tsx`変更時
- ホーム画面・実験画面の両方に影響
- BLE接続ロジック・実験フロー・UI表示

### `App.css`変更時
- 全画面のスタイルに影響
- 実験画面専用スタイル（`.experiment-task-card`等）に注意

### ESP32スケッチ変更時
- UUID変更時は`App.tsx`の`SERVICE_UUID`/`CHARACTERISTIC_UUID`も同期
- モーター動作時間変更時はWeb側の表示も調整が必要

## デバッグ情報

### Webアプリ
- ブラウザの開発者ツール（F12）でコンソールログ確認
- BLE接続エラーは`appendLog()`で表示
- 回答時間はリアルタイム表示（デバッグ用）

### ESP32
- シリアルモニタ（115200bps）で動作確認
- `[BLE] Received: ...`で受信データ確認
- `[MOTOR] Run direction ... deg`でモーター動作確認

## Tello制御の詳細（現在未使用）

**注意**: 以下の情報は参考用です。現在の実装ではTelloは使用されていません。

### tellopyの特徴
- **自動安全機能の回避**: Tello SDK 2.0の自動安全機能を回避し、腕に装着した状態でも制御可能
- **速度ベース制御**: `drone.forward(speed)`, `drone.left(speed)`などの速度ベースの制御
- **8方向移動**: 方向（度）を指定して直接移動

### APIエンドポイント（参考用）
- `POST /api/tello/connect`: Telloに接続（tellopy経由）
- `POST /api/tello/disconnect`: Telloから切断
- `POST /api/tello/takeoff`: 離陸
- `POST /api/tello/land`: 着陸
- `POST /api/tello/direction`: 方向（度）を指定して移動
- `POST /api/tello/command`: SDKコマンド文字列を実行（互換性のため）
- `GET /api/tello/status`: 接続状態確認

### ホーム画面の簡易制御（参考用）
以前の実装では、Tello接続後、簡易制御セクションが表示されていました：
- 離陸・着陸ボタンでTelloの離着陸を制御
- 8方向のボタンをクリックしてTelloを移動
- 操作ログが表示される

## 現在の実装状況（2024年更新）

### 手法の変更
- **以前**: `horizontal_force`（BLE接続）と`vertical_force`（Tello接続）の2手法
- **現在**: `wrist-worn`と`hand-grip`の2手法（両方ともBLE接続を使用）
- **実験フロー**: 両方の手法とも全く同じフロー（3秒待機 → BLE送信 → 3秒間モーター動作）
- **CSV保存**: 手法名のみが異なる（`wrist-worn`または`hand-grip`）

### Tello関連コード
- Tello関連のコード（`telloConnection.ts`、`tello-server/`など）は残していますが、現在は使用されていません
- 実験フローからはTello関連の処理を削除しました

## 今後の拡張可能性

- 実験パラメータの動的変更（待機時間・動作時間等）
- リアルタイムデータ可視化（グラフ表示）
- 複数参加者の結果比較機能
- 実験設定の保存・読み込み機能

