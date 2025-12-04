/*
  ESP32 Quad Motor Control + BLE Text Control

  概要:
  - @quad_motor_control.ino と同様に L9110S で4つのモーターを制御
  - @ble_led_ble_test.ino と同様に BLE ペリフェラルとして動作し、
    Webアプリ(React + Web Bluetooth)からのテキストメッセージを受信
  - 受信したテキストに応じて:
    - "BLINK"       : 内蔵LEDを点滅
    - 上記以外の任意テキスト : 内蔵LEDを一定時間点灯
    - "0","45",...,"315" の 8方向数値 : controlMotor() を用いてその方向に推力を出す
      → 一定時間動作させたあと自動で停止

  Webアプリ側:
  - 既に作成済みの BLE Text Sender (SERVICE_UUID / CHARACTERISTIC_UUID は下記と一致)
  - ブラウザ側から任意のテキストを送信すると、このスケッチが受信して動作
*/

#include <Arduino.h>
#include <math.h>

// BLE ライブラリ
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --------------------------------------------------------
// モーター制御（@quad_motor_control.ino と同等）
// --------------------------------------------------------

// モーターA（右）のピン定義
const int INRIGHT_A = 16; // ESP32 GPIO 16
const int INRIGHT_B = 17; // ESP32 GPIO 17

// モーターB（前）のピン定義
const int INFRONT_A = 18; // ESP32 GPIO 18
const int INFRONT_B = 19; // ESP32 GPIO 19

// モーターC（左）のピン定義
const int INLEFT_A = 22; // ESP32 GPIO 22
const int INLEFT_B = 21; // ESP32 GPIO 21

// モーターD（後）のピン定義
const int INBACK_A = 25; // ESP32 GPIO 25
const int INBACK_B = 26; // ESP32 GPIO 26

// --------------------------------------------------------
// LED & BLE 設定（@ble_led_ble_test.ino と同様）
// --------------------------------------------------------

// 内蔵LED (多くの ESP32 DevKit では GPIO2)
const int LED_PIN = 2;

// Webアプリと合わせる BLE UUID
static const char *SERVICE_UUID        = "12345678-1234-1234-1234-1234567890ab";
static const char *CHARACTERISTIC_UUID = "abcd1234-5678-90ab-cdef-1234567890ab";

// 特定のテキストデータ (この文字列を受信したら LED を点滅)
const char *SPECIAL_TEXT = "BLINK";

// 通常点灯させる時間 (ミリ秒)
const unsigned long LED_ON_DURATION_MS = 500;

// 点滅パターン
const int BLINK_COUNT       = 5;   // 点滅回数
const int BLINK_INTERVAL_MS = 200; // ON/OFF の間隔

// モーターの動作時間 (ms)
const unsigned long MOTOR_RUN_DURATION_MS = 3000;

// LED 点滅用の非同期制御フラグ
bool ledBlinkActive = false;
int  ledBlinkRemainingToggles = 0;      // 残りトグル回数 (ON/OFFで2カウント)
unsigned long ledBlinkInterval = 0;     // ON/OFF 間隔
unsigned long ledBlinkLastMillis = 0;   // 最後にトグルした時刻

// --------------------------------------------------------
// グローバル変数
// --------------------------------------------------------

BLEServer         *pServer         = nullptr;
BLECharacteristic *pCharacteristic = nullptr;

bool deviceConnected = false;

// --------------------------------------------------------
// ヘルパー関数: LED
// --------------------------------------------------------

void ledOnForDuration(unsigned long durationMs) {
  digitalWrite(LED_PIN, HIGH);
  delay(durationMs);
  digitalWrite(LED_PIN, LOW);
}

// 非同期点滅を開始する（count 回の点滅 = ON/OFF トグル 2*count 回）
void ledBlinkPattern(int count, int intervalMs) {
  if (count <= 0 || intervalMs <= 0) {
    return;
  }

  // 既存の点滅があればリセット
  ledBlinkActive = true;
  ledBlinkRemainingToggles = count * 2;
  ledBlinkInterval = static_cast<unsigned long>(intervalMs);
  ledBlinkLastMillis = millis();

  // 開始時は必ず OFF からスタート
  digitalWrite(LED_PIN, LOW);
}

// 非同期点滅の更新処理（loop() から定期的に呼び出す）
void updateLedBlink() {
  if (!ledBlinkActive) {
    return;
  }

  unsigned long now = millis();
  if (now - ledBlinkLastMillis >= ledBlinkInterval) {
    ledBlinkLastMillis = now;

    // 現在状態をトグル
    int current = digitalRead(LED_PIN);
    digitalWrite(LED_PIN, current == LOW ? HIGH : LOW);

    ledBlinkRemainingToggles--;
    if (ledBlinkRemainingToggles <= 0) {
      ledBlinkActive = false;
      digitalWrite(LED_PIN, LOW);  // 終了時は必ず消灯
    }
  }
}

// --------------------------------------------------------
// ヘルパー関数: モーター制御
// (@quad_motor_control.ino より抜粋)
// --------------------------------------------------------

void controlMotorSingle(int inaPin, int inbPin, float thrust) {
  if (thrust > 0.0) {
    // 正転
    digitalWrite(inaPin, HIGH);
    digitalWrite(inbPin, LOW);
  } else if (thrust < 0.0) {
    // 逆転
    digitalWrite(inaPin, LOW);
    digitalWrite(inbPin, HIGH);
  } else {
    // 停止
    digitalWrite(inaPin, LOW);
    digitalWrite(inbPin, LOW);
  }
}

/**
 * @brief 指定した方向に推力を発生させる関数
 * @param direction 推力の方向（0-360度）
 *                  0度: 右方向
 *                  90度: 前方向
 *                  180度: 左方向
 *                  270度: 後方向
 *                  45/135/225/315度: 斜め方向
 * @param enabled モーターのオン/オフ制御（true: 動作、false: 停止）
 */
void controlMotor(int direction, bool enabled) {
  if (!enabled) {
    // すべてのモーターを停止
    digitalWrite(INRIGHT_A, LOW);
    digitalWrite(INRIGHT_B, LOW);
    digitalWrite(INFRONT_A, LOW);
    digitalWrite(INFRONT_B, LOW);
    digitalWrite(INLEFT_A, LOW);
    digitalWrite(INLEFT_B, LOW);
    digitalWrite(INBACK_A, LOW);
    digitalWrite(INBACK_B, LOW);
    Serial.println("Motors stopped.");
    return;
  }

  // 動作確認用にLEDを点滅させる
  ledBlinkPattern(BLINK_COUNT, BLINK_INTERVAL_MS);

  // 角度を0-360度の範囲に正規化
  direction = direction % 360;
  if (direction < 0) {
    direction += 360;
  }

  float thrustA = 0;
  float thrustB = 0;
  float thrustC = 0;
  float thrustD = 0;

  switch (direction) {
    case 0:   // 右
      thrustA = 1; thrustB = 0; thrustC = -1; thrustD = 0;
      break;
    case 45:  // 右前
      thrustA = 1; thrustB = 1; thrustC = -1; thrustD = -1;
      break;
    case 90:  // 前
      thrustA = 0; thrustB = 1; thrustC = 0; thrustD = -1;
      break;
    case 135: // 左前
      thrustA = -1; thrustB = 1; thrustC = 1; thrustD = -1;
      break;
    case 180: // 左
      thrustA = -1; thrustB = 0; thrustC = 1; thrustD = 0;
      break;
    case 225: // 左後
      thrustA = -1; thrustB = -1; thrustC = 1; thrustD = 1;
      break;
    case 270: // 後
      thrustA = 0; thrustB = -1; thrustC = 0; thrustD = 1;
      break;
    case 315: // 右後
      thrustA = 1; thrustB = -1; thrustC = -1; thrustD = 1;
      break;
    default:  // 未定義の方向は停止
      thrustA = 0; thrustB = 0; thrustC = 0; thrustD = 0;
      break;
  }

  controlMotorSingle(INRIGHT_A, INRIGHT_B, thrustA);
  controlMotorSingle(INFRONT_A, INFRONT_B, thrustB);
  controlMotorSingle(INLEFT_A, INLEFT_B, thrustC);
  controlMotorSingle(INBACK_A, INBACK_B, thrustD);

  Serial.print("Direction: ");
  Serial.print(direction);
  Serial.print(" deg, Thrusts - A:");
  Serial.print(thrustA, 0);
  Serial.print(" B:");
  Serial.print(thrustB, 0);
  Serial.print(" C:");
  Serial.print(thrustC, 0);
  Serial.print(" D:");
  Serial.print(thrustD, 0);
  Serial.println();
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
    pServer->getAdvertising()->start();
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String value = pCharacteristic->getValue();

    if (value.length() == 0) {
      return;
    }

    // 末尾の \r\n を除去
    while (value.length() > 0 &&
           (value.endsWith("\n") || value.endsWith("\r"))) {
      value.remove(value.length() - 1);
    }

    Serial.print("[BLE] Received: ");
    Serial.println(value);

    // 1. 特定テキスト "BLINK" → LED点滅
    if (value == SPECIAL_TEXT) {
      ledBlinkPattern(BLINK_COUNT, BLINK_INTERVAL_MS);
      return;
    }

    // 2. 8方向の数値ならモーター制御 ("0","45",...,"315")
    if (value == "0"   || value == "45"  || value == "90"  ||
        value == "135" || value == "180" || value == "225" ||
        value == "270" || value == "315") {

      int direction = value.toInt();
      Serial.print("[MOTOR] Run direction ");
      Serial.print(direction);
      Serial.println(" deg");

      controlMotor(direction, true);
      delay(MOTOR_RUN_DURATION_MS);
      controlMotor(0, false); // 停止

      return;
    }

    // 3. その他の任意テキスト → LEDを一定時間点灯
    ledOnForDuration(LED_ON_DURATION_MS);
  }
};

// --------------------------------------------------------
// Arduino 標準関数
// --------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println();
  Serial.println("ESP32 Quad Motor + BLE Text Control starting...");

  // LED 初期化
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // モーター用ピンの初期化
  pinMode(INRIGHT_A, OUTPUT);
  pinMode(INRIGHT_B, OUTPUT);
  pinMode(INFRONT_A, OUTPUT);
  pinMode(INFRONT_B, OUTPUT);
  pinMode(INLEFT_A, OUTPUT);
  pinMode(INLEFT_B, OUTPUT);
  pinMode(INBACK_A, OUTPUT);
  pinMode(INBACK_B, OUTPUT);

  // 初期状態は全モーター停止
  controlMotor(0, false);

  // BLE 初期化
  BLEDevice::init("ESP32-QUAD-MOTOR");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Write 専用の Characteristic
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_WRITE_NR
                    );

  pCharacteristic->setCallbacks(new MyCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  // アドバタイズ開始
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started.");
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
  Serial.print("Characteristic UUID: ");
  Serial.println(CHARACTERISTIC_UUID);
}

void loop() {
  // すべてコールバック駆動だが、LED の非同期点滅制御を更新する
  updateLedBlink();

  // ループ周期を短くしすぎないための軽いウェイト
  delay(100);
}


