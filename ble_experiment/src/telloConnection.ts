// Tello SDK 2.0 接続管理
// バックエンドサーバー経由でUDP通信でTelloを制御

// 開発環境ではViteのプロキシを使用、本番環境では環境変数から取得
const API_BASE_URL = import.meta.env.VITE_TELLO_API_URL || ''

export type TelloState = 'disconnected' | 'connecting' | 'connected'

let telloState: TelloState = 'disconnected'
let isConnected = false

// 方向（度）をTelloコマンドに変換
// 8方向: 0, 45, 90, 135, 180, 225, 270, 315度
// Telloの移動距離（cm）: デフォルト50cm
const MOVE_DISTANCE = 50

export function directionToTelloCommand(direction: number): string[] {
  // 方向を正規化（0-360度）
  const normalizedDir = ((direction % 360) + 360) % 360

  const commands: string[] = []

  // 8方向にマッピング
  if (normalizedDir >= 337.5 || normalizedDir < 22.5) {
    // 0度（右）
    commands.push(`right ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 22.5 && normalizedDir < 67.5) {
    // 45度（右上）
    commands.push(`forward ${MOVE_DISTANCE}`)
    commands.push(`right ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 67.5 && normalizedDir < 112.5) {
    // 90度（上）
    commands.push(`forward ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 112.5 && normalizedDir < 157.5) {
    // 135度（左上）
    commands.push(`forward ${MOVE_DISTANCE}`)
    commands.push(`left ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 157.5 && normalizedDir < 202.5) {
    // 180度（左）
    commands.push(`left ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 202.5 && normalizedDir < 247.5) {
    // 225度（左下）
    commands.push(`back ${MOVE_DISTANCE}`)
    commands.push(`left ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 247.5 && normalizedDir < 292.5) {
    // 270度（下）
    commands.push(`back ${MOVE_DISTANCE}`)
  } else if (normalizedDir >= 292.5 && normalizedDir < 337.5) {
    // 315度（右下）
    commands.push(`back ${MOVE_DISTANCE}`)
    commands.push(`right ${MOVE_DISTANCE}`)
  }

  return commands
}

// Tello接続（tellopy経由）
export async function connectTello(): Promise<void> {
  if (isConnected) {
    return
  }

  telloState = 'connecting'

  try {
    const response = await fetch(`${API_BASE_URL}/api/tello/connect`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}))
      throw new Error(errorData.error || `HTTP error! status: ${response.status}`)
    }

    const data = await response.json()
    if (data.success) {
      isConnected = true
      telloState = 'connected'
    } else {
      throw new Error(data.error || 'Failed to connect to Tello')
    }
  } catch (error) {
    telloState = 'disconnected'
    isConnected = false
    throw error
  }
}

// Tello切断
export async function disconnectTello(): Promise<void> {
  if (!isConnected) {
    return
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/tello/disconnect`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}))
      throw new Error(errorData.error || `HTTP error! status: ${response.status}`)
    }
  } catch (error) {
    console.error('Error during disconnect:', error)
  } finally {
    isConnected = false
    telloState = 'disconnected'
  }
}

// Tello離陸
export async function takeoffTello(): Promise<void> {
  if (!isConnected) {
    throw new Error('Tello is not connected')
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/tello/takeoff`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    const data = await response.json()

    if (!response.ok || !data.success) {
      const errorMessage = data.error || `HTTP error! status: ${response.status}`
      throw new Error(errorMessage)
    }
  } catch (error) {
    console.error('Tello takeoff error:', error)
    throw error
  }
}

// Tello着陸
export async function landTello(): Promise<void> {
  if (!isConnected) {
    return
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/tello/land`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    const data = await response.json()

    if (!response.ok || !data.success) {
      const errorMessage = data.error || `HTTP error! status: ${response.status}`
      throw new Error(errorMessage)
    }
  } catch (error) {
    console.error('Land error:', error)
    throw error
  }
}

// 方向を送信してTelloを移動（tellopyの方向エンドポイントを使用）
export async function sendDirection(direction: number): Promise<void> {
  if (!isConnected) {
    throw new Error('Tello is not connected')
  }

  try {
    const response = await fetch(`${API_BASE_URL}/api/tello/direction`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ direction }),
    })

    const data = await response.json()

    if (!response.ok || !data.success) {
      const errorMessage = data.error || `HTTP error! status: ${response.status}`
      throw new Error(errorMessage)
    }
  } catch (error) {
    console.error('Tello direction error:', error)
    throw error
  }
}

// 接続状態を取得
export function getTelloState(): TelloState {
  return telloState
}

// 接続状態をチェック
export function isTelloConnected(): boolean {
  return isConnected
}

