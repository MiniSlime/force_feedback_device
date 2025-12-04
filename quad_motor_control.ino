// L9110Sモータードライバで4つのモーターを制御するプログラム
// モーター配置:
// - モーターA: 右方向
// - モーターB: 前方向
// - モーターC: 左方向
// - モーターD: 後方向

#include <Arduino.h>
#include <math.h>

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

void setup() {
  Serial.begin(115200);
  Serial.println("ESP32 Quad Motor Control with L9110S");

  // --- 各モーターのピンをデジタル出力に設定 ---
  pinMode(INRIGHT_A, OUTPUT);
  pinMode(INRIGHT_B, OUTPUT);
  pinMode(INFRONT_A, OUTPUT);
  pinMode(INFRONT_B, OUTPUT);
  pinMode(INLEFT_A, OUTPUT);
  pinMode(INLEFT_B, OUTPUT);
  pinMode(INBACK_A, OUTPUT);
  pinMode(INBACK_B, OUTPUT);

  // モーターを初期状態で停止させる（両方のピンをLow）
  digitalWrite(INRIGHT_A, LOW);
  digitalWrite(INRIGHT_B, LOW);
  digitalWrite(INFRONT_A, LOW);
  digitalWrite(INFRONT_B, LOW);
  digitalWrite(INLEFT_A, LOW);
  digitalWrite(INLEFT_B, LOW);
  digitalWrite(INBACK_A, LOW);
  digitalWrite(INBACK_B, LOW);

  Serial.println("Initialization complete. All motors stopped.");
}

void loop() {
  // // 5秒間、前方向に推力を発生させる
  // controlMotor(90, true);
  // delay(5000);
  // controlMotor(0, false);

  // // 5秒間、後方向に推力を発生させる
  // controlMotor(270, true);
  // delay(5000);
  // controlMotor(0, false);

  //それぞれのモーターを3秒ずつ個別に正転させる
  digitalWrite(INRIGHT_A, HIGH);
  digitalWrite(INRIGHT_B, LOW);
  delay(3000);
  digitalWrite(INRIGHT_A, LOW);
  digitalWrite(INRIGHT_B, LOW);
  digitalWrite(INFRONT_A, HIGH);
  digitalWrite(INFRONT_B, LOW);
  delay(3000);
  digitalWrite(INFRONT_A, LOW);
  digitalWrite(INFRONT_B, LOW);
  digitalWrite(INLEFT_A, HIGH);
  digitalWrite(INLEFT_B, LOW);
  delay(3000);
  digitalWrite(INLEFT_A, LOW);
  digitalWrite(INLEFT_B, LOW);
  digitalWrite(INBACK_A, HIGH);
  digitalWrite(INBACK_B, LOW);
  delay(3000);
  digitalWrite(INBACK_A, LOW);
  digitalWrite(INBACK_B, LOW);

  // モーターを永久に停止し、ループを繰り返さないようにする
  controlMotor(0, false);
  while (true) {
    delay(1000);
  } 
}

/**
 * @brief 指定した方向に推力を発生させる関数
 * @param direction 推力の方向（0-360度）
 *                  0度: 右方向（モーターAが回転、モーターCが逆回転、前後は停止）
 *                  90度: 前方向（モーターBが回転、モーターDが逆回転、左右は停止）
 *                  180度: 左方向（モーターCが回転、モーターAが逆回転、前後は停止）
 *                  270度: 後方向（モーターDが回転、モーターBが逆回転、左右は停止）
 *                  斜め方向: 各モーターの推力を合成して方向を表現
 * @param enabled モーターのオン/オフ制御（true: 動作、false: 停止）
 */
void controlMotor(int direction, bool enabled) {
  // モーターが無効な場合は、すべてのモーターを停止
  if (!enabled) {
    // すべてのモーターを停止（両方のピンをオフ）
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

  // 角度を0-360度の範囲に正規化
  direction = direction % 360;
  if (direction < 0) {
    direction += 360;
  }

  // 8方向（0, 45, 90, 135, 180, 225, 270, 315度）への場合分けによる制御
  // directionの値で直接分岐
  float thrustA = 0;
  float thrustB = 0;
  float thrustC = 0;
  float thrustD = 0;

  switch (direction) {
    case 0:   // 0度（右）
      thrustA = 1; thrustB = 0; thrustC = -1; thrustD = 0;
      break;
    case 45:  // 45度（右前）
      thrustA = 1; thrustB = 1; thrustC = -1; thrustD = -1;
      break;
    case 90:  // 90度（前）
      thrustA = 0; thrustB = 1; thrustC = 0; thrustD = -1;
      break;
    case 135: // 135度（左前）
      thrustA = -1; thrustB = 1; thrustC = 1; thrustD = -1;
      break;
    case 180: // 180度（左）
      thrustA = -1; thrustB = 0; thrustC = 1; thrustD = 0;
      break;
    case 225: // 225度（左後）
      thrustA = -1; thrustB = -1; thrustC = 1; thrustD = 1;
      break;
    case 270: // 270度（後）
      thrustA = 0; thrustB = -1; thrustC = 0; thrustD = 1;
      break;
    case 315: // 315度（右後）
      thrustA = 1; thrustB = -1; thrustC = -1; thrustD = 1;
      break;
    default:  // 未定義の方向は停止
      thrustA = 0; thrustB = 0; thrustC = 0; thrustD = 0;
      break;
  }

  // 各モーターを制御（正の値は正転、負の値は逆回転、0は停止）
  controlMotorSingle(INRIGHT_A, INRIGHT_B, thrustA);
  controlMotorSingle(INFRONT_A, INFRONT_B, thrustB);
  controlMotorSingle(INLEFT_A, INLEFT_B, thrustC);
  controlMotorSingle(INBACK_A, INBACK_B, thrustD);

  // デバッグ用シリアル出力
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

/**
 * @brief 単一のモーターを制御する補助関数
 * @param inaPin INAピン番号
 * @param inbPin INBピン番号
 * @param thrust 推力値 (-1.0 から 1.0) ※デジタル制御のため符号のみ使用
 *               正の値: 正転、負の値: 逆回転、0: 停止
 */
void controlMotorSingle(int inaPin, int inbPin, float thrust) {
  if (thrust > 0.0) {
    // 正転（プロペラを回転させて推力発生）
    // INAをHigh、INBをLow
    digitalWrite(inaPin, HIGH);
    digitalWrite(inbPin, LOW);
  } else if (thrust < 0.0) {
    // 逆回転（プロペラを逆回転させて推力発生）
    // INAをLow、INBをHigh
    digitalWrite(inaPin, LOW);
    digitalWrite(inbPin, HIGH);
  } else {
    // 停止（INAとINBをオフ）
    digitalWrite(inaPin, LOW);
    digitalWrite(inbPin, LOW);
  }
}

