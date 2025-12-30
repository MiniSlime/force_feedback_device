/*
  ESP32 Quad Motor Control + BLE Text Control

  概要:
  - @quad_motor_control.ino と同様に L9110S で4つのモーターを制御
  - モーター制御はPWM制御を使用（デューティー比70%）
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

// モーター起動間隔 (ms)
const unsigned long MOTOR_START_INTERVAL_MS = 100;

// PWM制御設定
const int PWM_FREQUENCY = 20000;       // PWM周波数 (Hz)
const int PWM_RESOLUTION = 8;         // PWM解像度 (ビット)
const int PWM_DUTY_CYCLE = 255;       // デューティー比100% (255 * 1.0 = 255)
const int PWM_DUTY_CYCLE_FULL = 255;  // デューティー比100% (起動時用)
const unsigned long MOTOR_START_BOOST_MS = 100; // 起動時の100%回転時間 (ms)

// 注意: 新しいESP32 Arduinoコアでは、ledcAttachがチャンネルを自動で割り当てるため、
// チャンネル番号の定義は不要になりました。ledcWrite(pin, duty)を使用します。

// LED 点滅用の非同期制御フラグ
bool ledBlinkActive = false;
int  ledBlinkRemainingToggles = 0;      // 残りトグル回数 (ON/OFFで2カウント)
unsigned long ledBlinkInterval = 0;     // ON/OFF 間隔
unsigned long ledBlinkLastMillis = 0;   // 最後にトグルした時刻

// モーター起動用の非同期制御フラグ
bool motorStartPending = false;         // モーター起動待ちがあるか
float pendingThrustA = 0;               // 起動待ちの推力A
float pendingThrustB = 0;               // 起動待ちの推力B
float pendingThrustC = 0;               // 起動待ちの推力C
float pendingThrustD = 0;               // 起動待ちの推力D
int pendingMotorIndex = 0;              // 次に起動するモーターのインデックス (0=A, 1=B, 2=C, 3=D)
unsigned long motorStartLastMillis = 0;  // 最後にモーターを起動した時刻

// モーター起動時刻記録（100%→70%切り替え用）
unsigned long motorAStartTime = 0;      // モーターAの起動時刻（0=未起動）
unsigned long motorBStartTime = 0;      // モーターBの起動時刻（0=未起動）
unsigned long motorCStartTime = 0;      // モーターCの起動時刻（0=未起動）
unsigned long motorDStartTime = 0;      // モーターDの起動時刻（0=未起動）
float motorAThrust = 0;                 // モーターAの推力方向（-1, 0, 1）
float motorBThrust = 0;                 // モーターBの推力方向（-1, 0, 1）
float motorCThrust = 0;                 // モーターCの推力方向（-1, 0, 1）
float motorDThrust = 0;                 // モーターDの推力方向（-1, 0, 1）

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
// ヘルパー関数: モーター制御（PWM制御）
// --------------------------------------------------------

void controlMotorSingle(int inaPin, int inbPin, float thrust, bool useFullDuty = false) {
  int dutyCycle = useFullDuty ? PWM_DUTY_CYCLE_FULL : PWM_DUTY_CYCLE;
  
  if (thrust > 0.0) {
    // 正転
    ledcWrite(inaPin, dutyCycle);
    ledcWrite(inbPin, 0);
  } else if (thrust < 0.0) {
    // 逆転
    ledcWrite(inaPin, 0);
    ledcWrite(inbPin, dutyCycle);
  } else {
    // 停止
    ledcWrite(inaPin, 0);
    ledcWrite(inbPin, 0);
  }
}

// 非同期モーター起動の更新処理（loop() から定期的に呼び出す）
void updateMotorStart() {
  if (!motorStartPending) {
    return;
  }

  unsigned long now = millis();
  if (now - motorStartLastMillis >= MOTOR_START_INTERVAL_MS) {
    motorStartLastMillis = now;

    // 次のモーターを順番に起動（pendingMotorIndexは次のモーターのインデックス）
    // 0=A, 1=B, 2=C, 3=D, 4=完了
    // pendingMotorIndex以降のモーターを順番にチェックして起動（1回の呼び出しで1つだけ）
    if (pendingMotorIndex == 0) {
      if (pendingThrustA != 0.0) {
        controlMotorSingle(INRIGHT_A, INRIGHT_B, pendingThrustA, true); // 100%で起動
        motorAStartTime = millis();
        motorAThrust = pendingThrustA;
        pendingMotorIndex = 1;
      } else {
        pendingMotorIndex = 1; // このモーターは起動不要なので次へ
      }
    } else if (pendingMotorIndex == 1) {
      if (pendingThrustB != 0.0) {
        controlMotorSingle(INFRONT_A, INFRONT_B, pendingThrustB, true); // 100%で起動
        motorBStartTime = millis();
        motorBThrust = pendingThrustB;
        pendingMotorIndex = 2;
      } else {
        pendingMotorIndex = 2; // このモーターは起動不要なので次へ
      }
    } else if (pendingMotorIndex == 2) {
      if (pendingThrustC != 0.0) {
        controlMotorSingle(INLEFT_A, INLEFT_B, pendingThrustC, true); // 100%で起動
        motorCStartTime = millis();
        motorCThrust = pendingThrustC;
        pendingMotorIndex = 3;
      } else {
        pendingMotorIndex = 3; // このモーターは起動不要なので次へ
      }
    } else if (pendingMotorIndex == 3) {
      if (pendingThrustD != 0.0) {
        controlMotorSingle(INBACK_A, INBACK_B, pendingThrustD, true); // 100%で起動
        motorDStartTime = millis();
        motorDThrust = pendingThrustD;
      }
      pendingMotorIndex = 4;
      motorStartPending = false; // すべて起動完了
    } else {
      // 完了
      motorStartPending = false;
    }
  }
}

// モーターのデューティ比を100%から70%に切り替える処理（loop() から定期的に呼び出す）
void updateMotorDutyCycle() {
  unsigned long now = millis();
  
  // モーターA: 起動から一定時間経過したら70%に切り替え
  if (motorAStartTime > 0 && (now - motorAStartTime >= MOTOR_START_BOOST_MS)) {
    controlMotorSingle(INRIGHT_A, INRIGHT_B, motorAThrust, false); // 70%に切り替え
    motorAStartTime = 0; // 処理済みフラグ
  }
  
  // モーターB: 起動から一定時間経過したら70%に切り替え
  if (motorBStartTime > 0 && (now - motorBStartTime >= MOTOR_START_BOOST_MS)) {
    controlMotorSingle(INFRONT_A, INFRONT_B, motorBThrust, false); // 70%に切り替え
    motorBStartTime = 0; // 処理済みフラグ
  }
  
  // モーターC: 起動から一定時間経過したら70%に切り替え
  if (motorCStartTime > 0 && (now - motorCStartTime >= MOTOR_START_BOOST_MS)) {
    controlMotorSingle(INLEFT_A, INLEFT_B, motorCThrust, false); // 70%に切り替え
    motorCStartTime = 0; // 処理済みフラグ
  }
  
  // モーターD: 起動から一定時間経過したら70%に切り替え
  if (motorDStartTime > 0 && (now - motorDStartTime >= MOTOR_START_BOOST_MS)) {
    controlMotorSingle(INBACK_A, INBACK_B, motorDThrust, false); // 70%に切り替え
    motorDStartTime = 0; // 処理済みフラグ
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
    // モーター起動待ちをキャンセル
    motorStartPending = false;
    pendingThrustA = 0;
    pendingThrustB = 0;
    pendingThrustC = 0;
    pendingThrustD = 0;
    
    // 起動時刻記録をリセット
    motorAStartTime = 0;
    motorBStartTime = 0;
    motorCStartTime = 0;
    motorDStartTime = 0;
    
    // すべてのモーターを停止（PWMで0に設定）
    ledcWrite(INRIGHT_A, 0);
    ledcWrite(INRIGHT_B, 0);
    ledcWrite(INFRONT_A, 0);
    ledcWrite(INFRONT_B, 0);
    ledcWrite(INLEFT_A, 0);
    ledcWrite(INLEFT_B, 0);
    ledcWrite(INBACK_A, 0);
    ledcWrite(INBACK_B, 0);
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

  // 動作するモーターを100ms間隔で順番に起動（非同期）
  // 起動予約を設定
  pendingThrustA = thrustA;
  pendingThrustB = thrustB;
  pendingThrustC = thrustC;
  pendingThrustD = thrustD;
  pendingMotorIndex = 0;
  motorStartPending = true;
  motorStartLastMillis = millis();
  
  // 起動時刻記録をリセット
  motorAStartTime = 0;
  motorBStartTime = 0;
  motorCStartTime = 0;
  motorDStartTime = 0;
  
  // 最初のモーターを即座に起動（thrustが0でない最初のモーター、100%で起動）
  if (thrustA != 0.0) {
    controlMotorSingle(INRIGHT_A, INRIGHT_B, thrustA, true); // 100%で起動
    motorAStartTime = millis();
    motorAThrust = thrustA;
    pendingMotorIndex = 1;
    motorStartLastMillis = millis();
  } else if (thrustB != 0.0) {
    controlMotorSingle(INFRONT_A, INFRONT_B, thrustB, true); // 100%で起動
    motorBStartTime = millis();
    motorBThrust = thrustB;
    pendingMotorIndex = 2;
    motorStartLastMillis = millis();
  } else if (thrustC != 0.0) {
    controlMotorSingle(INLEFT_A, INLEFT_B, thrustC, true); // 100%で起動
    motorCStartTime = millis();
    motorCThrust = thrustC;
    pendingMotorIndex = 3;
    motorStartLastMillis = millis();
  } else if (thrustD != 0.0) {
    controlMotorSingle(INBACK_A, INBACK_B, thrustD, true); // 100%で起動
    motorDStartTime = millis();
    motorDThrust = thrustD;
    pendingMotorIndex = 4; // すべて起動済み
    motorStartPending = false;
  } else {
    // すべてのモーターが停止状態
    pendingMotorIndex = 4;
    motorStartPending = false;
  }

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

    // 2. "test" → 全てのモーターを順番に1秒ずつ正転
    if (value == "test") {
      Serial.println("[MOTOR] Test mode: Running all motors sequentially for 1 second each");
      
      // モーターA（右）を1秒正転
      Serial.println("[MOTOR] Motor A (Right) - Forward 1 second");
      controlMotorSingle(INRIGHT_A, INRIGHT_B, 1.0);
      delay(1000);
      controlMotorSingle(INRIGHT_A, INRIGHT_B, 0.0);
      
      // モーターB（前）を1秒正転
      Serial.println("[MOTOR] Motor B (Front) - Forward 1 second");
      controlMotorSingle(INFRONT_A, INFRONT_B, 1.0);
      delay(1000);
      controlMotorSingle(INFRONT_A, INFRONT_B, 0.0);
      
      // モーターC（左）を1秒正転
      Serial.println("[MOTOR] Motor C (Left) - Forward 1 second");
      controlMotorSingle(INLEFT_A, INLEFT_B, 1.0);
      delay(1000);
      controlMotorSingle(INLEFT_A, INLEFT_B, 0.0);
      
      // モーターD（後）を1秒正転
      Serial.println("[MOTOR] Motor D (Back) - Forward 1 second");
      controlMotorSingle(INBACK_A, INBACK_B, 1.0);
      delay(1000);
      controlMotorSingle(INBACK_A, INBACK_B, 0.0);
      
      Serial.println("[MOTOR] Test mode completed");
      return;
    }

    // 3. 8方向の数値ならモーター制御 ("0","45",...,"315")
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

    // 4. その他の任意テキスト → LEDを一定時間点灯
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

  // モーター用ピンの初期化とPWMチャンネルの設定（チャンネルは自動で割り当てられる）
  // モーターA（右）
  ledcAttach(INRIGHT_A, PWM_FREQUENCY, PWM_RESOLUTION);
  ledcAttach(INRIGHT_B, PWM_FREQUENCY, PWM_RESOLUTION);
  
  // モーターB（前）
  ledcAttach(INFRONT_A, PWM_FREQUENCY, PWM_RESOLUTION);
  ledcAttach(INFRONT_B, PWM_FREQUENCY, PWM_RESOLUTION);
  
  // モーターC（左）
  ledcAttach(INLEFT_A, PWM_FREQUENCY, PWM_RESOLUTION);
  ledcAttach(INLEFT_B, PWM_FREQUENCY, PWM_RESOLUTION);
  
  // モーターD（後）
  ledcAttach(INBACK_A, PWM_FREQUENCY, PWM_RESOLUTION);
  ledcAttach(INBACK_B, PWM_FREQUENCY, PWM_RESOLUTION);

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
  
  // モーターの非同期起動制御を更新する
  updateMotorStart();
  
  // モーターのデューティ比を100%から70%に切り替える処理
  updateMotorDutyCycle();

  // ループ周期を短くしすぎないための軽いウェイト
  delay(100);
}
