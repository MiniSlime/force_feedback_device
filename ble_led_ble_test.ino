/*
  ESP32 BLE LED Test (Webアプリ用)

  このスケッチは、作成した React Web アプリ
  （Web Bluetooth API を用いて任意テキストを送信するアプリ）
  からの接続とテキスト送信に対応した ESP32 ペリフェラル実装です。

  要件:
  - ESP32 を BLE ペリフェラルとして動作させる
  - 任意の BLE セントラル(Webブラウザ/スマホなど)からUTF-8テキストデータを受信
  - 何らかのテキストを受信したら内蔵LED(GPIO2)を一定時間点灯
  - 特定のテキスト(例: "BLINK")を受信したら LED を点滅

  Webアプリ側のポイント:
  - Webアプリは「書き込み可能な Characteristic」を自動探索する実装
  - 本スケッチでは、WRITE / WRITE_NR を持つ Characteristic を1つだけ用意
    → Webアプリからは自動的にここが選ばれます
  - 送信データは TextEncoder により UTF-8 バイト列となりますが、
    ESP32 側では Arduino String として受信して扱っています

  使い方(例):
  - Reactで作成した Web アプリ（BLE Text Sender）をブラウザで開く
  - 「BLEデバイスに接続」を押し、"ESP32-BLE-LED" を選択して接続
  - テキストを入力して「送信」を押す
    - "BLINK" を送ると点滅
    - それ以外の文字列は一定時間点灯
*/

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --------------------------------------------------------
// 設定値
// --------------------------------------------------------

// 内蔵LED (多くの ESP32 DevKit では GPIO2)
const int LED_PIN = 2;

// 任意の UUID (他の機器と被りにくいようランダム生成したものを想定)
// 必要に応じて変更してください。
// Webアプリ側で特定のサービス/キャラUUIDを指定したい場合は、
// ここで定義している値と揃えるようにしてください。
static const char *SERVICE_UUID        = "12345678-1234-1234-1234-1234567890ab";
static const char *CHARACTERISTIC_UUID = "abcd1234-5678-90ab-cdef-1234567890ab";

// 特定のテキストデータ (この文字列を受信したら LED を点滅)
const char *SPECIAL_TEXT = "BLINK";

// 通常点灯させる時間 (ミリ秒)
const unsigned long LED_ON_DURATION_MS = 500;

// 点滅パターン
const int BLINK_COUNT      = 5;    // 点滅回数
const int BLINK_INTERVAL_MS = 200; // ON/OFF の間隔

// --------------------------------------------------------
// グローバル変数
// --------------------------------------------------------

BLEServer        *pServer        = nullptr;
BLECharacteristic *pCharacteristic = nullptr;

bool deviceConnected = false;

// --------------------------------------------------------
// LED 制御用のヘルパー関数
// --------------------------------------------------------

void ledOnForDuration(unsigned long durationMs) {
  digitalWrite(LED_PIN, HIGH);
  delay(durationMs);
  digitalWrite(LED_PIN, LOW);
}

void ledBlinkPattern(int count, int intervalMs) {
  for (int i = 0; i < count; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(intervalMs);
    digitalWrite(LED_PIN, LOW);
    delay(intervalMs);
  }
}

// --------------------------------------------------------
// BLE コールバック
// --------------------------------------------------------

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    Serial.println("[BLE] Central connected.");
  }

  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println("[BLE] Central disconnected. Start advertising again.");
    // 切断されたら再アドバタイズ
    pServer->getAdvertising()->start();
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    // 環境によって getValue() の戻り値型が異なるため、Arduino String を使用
    String value = pCharacteristic->getValue();

    if (value.length() == 0) {
      return;
    }

    // Web側からのテキストに改行が含まれる可能性もあるため、末尾の \r\n を軽く除去
    while (value.length() > 0 &&
           (value.endsWith("\n") || value.endsWith("\r"))) {
      value.remove(value.length() - 1);
    }

    // 受信データをシリアルモニタへ出力
    Serial.print("[BLE] Received: ");
    Serial.println(value);

    // 特定のテキストの場合: 点滅
    if (value == SPECIAL_TEXT) {
      ledBlinkPattern(BLINK_COUNT, BLINK_INTERVAL_MS);
    } else {
      // それ以外は一定時間点灯
      ledOnForDuration(LED_ON_DURATION_MS);
    }
  }
};

// --------------------------------------------------------
// Arduino 標準関数
// --------------------------------------------------------

void setup() {
  // シリアル初期化
  Serial.begin(115200);
  delay(1000);
  Serial.println();
  Serial.println("ESP32 BLE LED Test starting...");

  // LED 初期化
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // BLE 初期化
  BLEDevice::init("ESP32-BLE-LED");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Write 専用の Characteristic を作成
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_WRITE_NR
                    );

  pCharacteristic->setCallbacks(new MyCallbacks());

  // 必要であれば CCCD を付与 (通知は使っていないが、汎用性のため)
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  // アドバタイズ開始
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // オプション設定
  pAdvertising->setMinPreferred(0x12);  // オプション設定

  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started.");
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
  Serial.print("Characteristic UUID: ");
  Serial.println(CHARACTERISTIC_UUID);
}

void loop() {
  // 今回はコールバック駆動のため、loop では特に処理をしない
  delay(100);
}


