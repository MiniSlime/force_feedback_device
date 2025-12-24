#!/usr/bin/env python3
"""
Tello制御用Pythonバックエンドサーバー
tellopyを使用してTelloを制御する
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import tellopy
import time
import threading

app = Flask(__name__)
CORS(app)

# Telloインスタンス
drone = None
is_connected = False
move_speed = 30  # 移動速度（0-100）
move_duration = 3.0  # 移動時間（秒）

def init_drone():
    """Telloドローンの初期化"""
    global drone
    if drone is None:
        drone = tellopy.Tello()
    return drone

@app.route('/api/tello/connect', methods=['POST'])
def connect():
    """Telloに接続（tellopy経由）"""
    global is_connected, drone
    
    try:
        if is_connected:
            return jsonify({
                'success': True,
                'message': 'Already connected'
            })
        
        drone = init_drone()
        drone.connect()
        is_connected = True
        
        return jsonify({
            'success': True,
            'message': 'Connected to Tello',
            'response': 'ok'
        })
    except Exception as e:
        print(f'Connection error: {e}')
        is_connected = False
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/tello/disconnect', methods=['POST'])
def disconnect():
    """Telloから切断"""
    global is_connected, drone
    
    try:
        if not is_connected or drone is None:
            return jsonify({
                'success': True,
                'message': 'Not connected'
            })
        
        # 着陸を試みる
        try:
            drone.land()
            time.sleep(1)
        except Exception as e:
            print(f'Land error: {e}')
        
        # 切断
        try:
            drone.quit()
        except Exception as e:
            print(f'Quit error: {e}')
        
        is_connected = False
        drone = None
        
        return jsonify({
            'success': True,
            'message': 'Disconnected from Tello'
        })
    except Exception as e:
        print(f'Disconnect error: {e}')
        is_connected = False
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/tello/command', methods=['POST'])
def command():
    """Telloコマンドを実行（SDKコマンド文字列をtellopyメソッドに変換）"""
    global is_connected, drone
    
    try:
        if not is_connected or drone is None:
            return jsonify({
                'success': False,
                'error': 'Tello is not connected'
            }), 400
        
        data = request.get_json()
        command_str = data.get('command', '')
        
        if not command_str:
            return jsonify({
                'success': False,
                'error': 'Command is required'
            }), 400
        
        # SDKコマンドをtellopyメソッドに変換
        response = execute_command(command_str)
        
        return jsonify({
            'success': True,
            'response': response
        })
    except Exception as e:
        print(f'Command error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def execute_command(command_str):
    """SDKコマンド文字列をtellopyメソッドに変換して実行"""
    global drone
    
    cmd_parts = command_str.strip().lower().split()
    cmd = cmd_parts[0] if cmd_parts else ''
    
    try:
        if cmd == 'command':
            # SDKモードに入る（tellopyでは自動的にSDKモード）
            return 'ok'
        
        elif cmd == 'takeoff':
            drone.takeoff()
            time.sleep(2)  # 離陸完了を待つ
            return 'ok'
        
        elif cmd == 'land':
            drone.land()
            time.sleep(1)
            return 'ok'
        
        elif cmd == 'forward':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            # tellopyは速度ベースなので、一定時間移動
            drone.forward(move_speed)
            time.sleep(move_duration)
            drone.forward(0)  # 停止
            return 'ok'
        
        elif cmd == 'back':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            drone.backward(move_speed)
            time.sleep(move_duration)
            drone.backward(0)
            return 'ok'
        
        elif cmd == 'left':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            drone.left(move_speed)
            time.sleep(move_duration)
            drone.left(0)
            return 'ok'
        
        elif cmd == 'right':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            drone.right(move_speed)
            time.sleep(move_duration)
            drone.right(0)
            return 'ok'
        
        elif cmd == 'up':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            drone.up(move_speed)
            time.sleep(move_duration)
            drone.up(0)
            return 'ok'
        
        elif cmd == 'down':
            distance = int(cmd_parts[1]) if len(cmd_parts) > 1 else 50
            drone.down(move_speed)
            time.sleep(move_duration)
            drone.down(0)
            return 'ok'
        
        elif cmd == 'cw':
            # 時計回り回転
            degrees = int(cmd_parts[1]) if len(cmd_parts) > 1 else 90
            drone.clockwise(move_speed)
            time.sleep(degrees / 90.0 * 1.0)  # 90度で約1秒
            drone.clockwise(0)
            return 'ok'
        
        elif cmd == 'ccw':
            # 反時計回り回転
            degrees = int(cmd_parts[1]) if len(cmd_parts) > 1 else 90
            drone.counter_clockwise(move_speed)
            time.sleep(degrees / 90.0 * 1.0)
            drone.counter_clockwise(0)
            return 'ok'
        
        else:
            return f'error Unknown command: {cmd}'
    
    except Exception as e:
        return f'error {str(e)}'

@app.route('/api/tello/status', methods=['GET'])
def status():
    """接続状態を確認"""
    return jsonify({
        'connected': is_connected
    })

@app.route('/api/tello/takeoff', methods=['POST'])
def takeoff():
    """Telloを離陸"""
    global is_connected, drone
    
    try:
        if not is_connected or drone is None:
            return jsonify({
                'success': False,
                'error': 'Tello is not connected'
            }), 400
        
        drone.takeoff()
        time.sleep(2)  # 離陸完了を待つ
        
        return jsonify({
            'success': True,
            'response': 'ok'
        })
    except Exception as e:
        print(f'Takeoff error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/tello/land', methods=['POST'])
def land():
    """Telloを着陸"""
    global is_connected, drone
    
    try:
        if not is_connected or drone is None:
            return jsonify({
                'success': False,
                'error': 'Tello is not connected'
            }), 400
        
        drone.land()
        time.sleep(1)
        
        return jsonify({
            'success': True,
            'response': 'ok'
        })
    except Exception as e:
        print(f'Land error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/tello/direction', methods=['POST'])
def direction():
    """方向（度）を指定してTelloを移動（tellopyのメソッドを直接使用）"""
    global is_connected, drone
    
    try:
        if not is_connected or drone is None:
            return jsonify({
                'success': False,
                'error': 'Tello is not connected'
            }), 400
        
        data = request.get_json()
        direction_deg = data.get('direction', 0)
        
        # 方向を正規化（0-360度）
        normalized_dir = ((direction_deg % 360) + 360) % 360
        
        # 8方向にマッピングして移動
        move_drone_by_direction(normalized_dir)
        
        return jsonify({
            'success': True,
            'response': 'ok'
        })
    except Exception as e:
        print(f'Direction error: {e}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def move_drone_by_direction(direction_deg):
    global drone
    
    # 角度をラジアンに変換して計算（8方位をベクトルで処理）
    import math
    rad = math.radians(direction_deg)
    
    # move_speedを各成分に分解 (0-100の範囲)
    # Telloの座標系: pitch(前後), roll(左右)
    # 0度=右(roll>0), 90度=前(pitch>0)
    roll = int(move_speed * math.cos(rad))
    pitch = int(move_speed * math.sin(rad))

    print(f"Moving: pitch={pitch}, roll={roll}")

    # --- 重要：離陸判定をバイパスするための試行 ---
    # 通常のtakeoff()の代わりに、低速回転を指示
    # (注意: 環境により、やはりtakeoffなしでは動かない場合があります)
    
    # 1. 瞬間的にスロットルを上げ下げして「やる気」を出す（機種による）
    drone.set_throttle(10) 
    time.sleep(0.1)
    
    # 2. 目的の方向に力をかける
    drone.set_roll(roll)
    drone.set_pitch(pitch)
    
    # 3. 指定時間維持
    time.sleep(move_duration)
    
    # 4. 停止
    drone.set_roll(0)
    drone.set_pitch(0)
    drone.set_throttle(0)

if __name__ == '__main__':
    print('Tello server running on http://localhost:3001')
    print('Make sure Tello is connected to Wi-Fi')
    app.run(host='0.0.0.0', port=3001, debug=True)

