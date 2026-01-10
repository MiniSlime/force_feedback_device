import { useCallback, useEffect, useRef, useState } from 'react'
import { Routes, Route, useNavigate, useSearchParams } from 'react-router-dom'
import './App.css'
import { getBleCharacteristic, setBleCharacteristic } from './bleConnection'

const BASE_DIRECTIONS = [0, 45, 90, 135, 180, 225, 270, 315]

type BleState = 'disconnected' | 'connecting' | 'connected'

// ESP32 側のスケッチ (ble_led_ble_test.ino / quad_motor_control_ble.ino) で定義している UUID と合わせる
const SERVICE_UUID = '12345678-1234-1234-1234-1234567890ab'
const CHARACTERISTIC_UUID = 'abcd1234-5678-90ab-cdef-1234567890ab'

function Home() {
  const navigate = useNavigate()
  const [bleState, setBleState] = useState<BleState>('disconnected')
  const [deviceName, setDeviceName] = useState<string | null>(null)
  const [server, setServer] = useState<BluetoothRemoteGATTServer | null>(null)
  const [characteristic, setCharacteristic] =
    useState<BluetoothRemoteGATTCharacteristic | null>(null)
  const [log, setLog] = useState<string[]>([])
  const [textToSend, setTextToSend] = useState('')

  // 実験ステータス用
  const [participantId, setParticipantId] = useState('')
  const [method, setMethod] = useState<'wrist-worn' | 'hand-grip'>(
    'wrist-worn',
  )

  const appendLog = useCallback((message: string) => {
    setLog((prev) => [...prev, `[${new Date().toLocaleTimeString()}] ${message}`])
  }, [])

  const handleConnect = useCallback(async () => {
    if (!navigator.bluetooth) {
      appendLog('このブラウザは Web Bluetooth API をサポートしていません。')
      return
    }

    try {
      setBleState('connecting')
      appendLog('デバイスの選択ダイアログを表示します...')

      // ESP32 がアドバタイズしている Service UUID を指定してフィルタ
      const device = await navigator.bluetooth.requestDevice({
        filters: [{ services: [SERVICE_UUID] }],
        optionalServices: [SERVICE_UUID],
      })

      setDeviceName(device.name ?? 'Unknown device')
      appendLog(`選択されたデバイス: ${device.name ?? '名称なし'} (${device.id})`)

      device.addEventListener('gattserverdisconnected', () => {
        appendLog('デバイスが切断されました。')
        setBleState('disconnected')
        setServer(null)
        setCharacteristic(null)
      })

      const gattServer = await device.gatt?.connect()
      if (!gattServer) {
        appendLog('GATTサーバーに接続できませんでした。')
        setBleState('disconnected')
        return
      }

      setServer(gattServer)
      appendLog('GATTサーバーに接続しました。')

      // ESP32 側で定義した Service / Characteristic をピンポイントで取得
      const service = await gattServer.getPrimaryService(SERVICE_UUID)
      const writableChar = await service.getCharacteristic(CHARACTERISTIC_UUID)

      appendLog(
        `書き込み先Characteristicを取得しました: service=${service.uuid}, char=${writableChar.uuid}`,
      )

      setCharacteristic(writableChar)
      setBleCharacteristic(writableChar)
      setBleState('connected')
      appendLog('書き込み先Characteristicの準備ができました。')
    } catch (error) {
      console.error(error)
      appendLog(`接続中にエラーが発生しました: ${(error as Error).message}`)
      setBleState('disconnected')
    }
  }, [appendLog])

  const handleDisconnect = useCallback(async () => {
    try {
      if (server?.connected) {
        server.disconnect()
        appendLog('手動で切断しました。')
      }
    } catch (error) {
      console.error(error)
      appendLog(`切断中にエラーが発生しました: ${(error as Error).message}`)
    } finally {
      setBleState('disconnected')
      setServer(null)
      setCharacteristic(null)
      setBleCharacteristic(null)
    }
  }, [appendLog, server])

  const handleSend = useCallback(async () => {
    if (!characteristic) {
      appendLog('書き込み先Characteristicが準備されていません。')
      return
    }
    if (!textToSend) {
      appendLog('送信するテキストを入力してください。')
      return
    }

    try {
      const encoder = new TextEncoder()
      const data = encoder.encode(textToSend)
      await characteristic.writeValue(data)
      appendLog(`送信しました: "${textToSend}" (${data.byteLength} bytes)`)
      // 必要であれば送信後にテキストをクリア
      // setTextToSend('')
    } catch (error) {
      console.error(error)
      appendLog(`送信中にエラーが発生しました: ${(error as Error).message}`)
    }
  }, [appendLog, characteristic, textToSend])

  const isConnecting = bleState === 'connecting'
  const isConnected = bleState === 'connected'

  // 実験開始ボタンの有効化条件（参加者番号のみ必要、BLE接続は任意）
  const canStartExperiment = !!participantId

  return (
    <div className="app-root">
      <main className="app-main">
        <section className="card status-card">
          <h2>実験ステータス</h2>
          <div className="field-group">
            <label className="field-label" htmlFor="participantId">
              参加者番号
            </label>
            <input
              id="participantId"
              className="text-input single-line"
              type="text"
              placeholder="例: P01"
              value={participantId}
              onChange={(e) => setParticipantId(e.target.value)}
            />
          </div>

          <div className="field-group">
            <span className="field-label">手法</span>
            <select
              className="select-input"
              value={method}
              onChange={(e) =>
                setMethod(e.target.value as 'wrist-worn' | 'hand-grip')
              }
            >
              <option value="wrist-worn">Wrist-worn</option>
              <option value="hand-grip">Hand-grip</option>
            </select>
          </div>

          <div className="button-row end">
            <button
              className="secondary-button"
              onClick={() => {
                const params = new URLSearchParams({
                  participantId,
                  method,
                  practice: 'true',
                })
                navigate(`/experiment?${params.toString()}`)
              }}
              disabled={!canStartExperiment}
            >
              練習タスク
            </button>
            <button
              className="primary-button"
              onClick={() => {
                const params = new URLSearchParams({
                  participantId,
                  method,
                })
                navigate(`/experiment?${params.toString()}`)
              }}
              disabled={!canStartExperiment}
            >
              実験開始
            </button>
          </div>
        </section>

        {/* 両方の手法ともBLE接続を使用 */}
        <section className="card">
          <h2>デバイス接続（BLE）</h2>
          <p className="status-text">
            状態: <span className={`status-pill status-${bleState}`}>{bleState}</span>
          </p>
          <p className="device-name">
            デバイス: {deviceName ?? '未接続'}
          </p>
          <div className="button-row">
            <button
              className="primary-button"
              onClick={handleConnect}
              disabled={isConnecting || isConnected}
            >
              {isConnecting ? '接続中...' : 'BLEデバイスに接続'}
            </button>
            <button
              className="secondary-button"
              onClick={handleDisconnect}
              disabled={!isConnected}
            >
              切断
            </button>
          </div>
          <p className="helper-text">
            接続時にブラウザがデバイス選択ダイアログを表示します。
          </p>
        </section>

        {/* テキスト送信テスト（両方の手法で使用可能） */}
        <section className="card">
          <h2>テキスト送信テスト</h2>
          <label className="field-label" htmlFor="textToSend">
            送信するテキスト
          </label>
          <textarea
            id="textToSend"
            className="text-input"
            rows={4}
            placeholder="ここに任意のテキストを入力して、接続したBLEデバイスへ送信します。"
            value={textToSend}
            onChange={(e) => setTextToSend(e.target.value)}
          />
          <div className="button-row end">
            <button
              className="primary-button"
              onClick={handleSend}
              disabled={!isConnected}
            >
              送信
            </button>
          </div>
          {!isConnected && (
            <p className="helper-text warning">
              テキスト送信には、先にBLEデバイスへ接続する必要があります。
            </p>
          )}
        </section>

        <section className="card log-card">
          <h2>ログ</h2>
          <div className="log-container">
            {log.length === 0 ? (
              <p className="log-empty">まだログはありません。</p>
            ) : (
              <ul>
                {log.map((line, index) => (
                  <li key={index}>{line}</li>
                ))}
              </ul>
            )}
          </div>
        </section>
      </main>

      <footer className="app-footer">
        <p>
          対応ブラウザ: Chrome系ブラウザ (HTTPS 環境または localhost が必要です)
        </p>
      </footer>
    </div>
  )
}

type TrialStatus = 'idle' | 'stimulating' | 'finished'

type TrialResult = {
  index: number
  trueDirection: number
  responseAngle: number
  responseTimeMs: number
}

function ExperimentPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()

  const participantId = searchParams.get('participantId') ?? ''
  const method = searchParams.get('method') ?? ''
  const isPractice = searchParams.get('practice') === 'true'

  const [status, setStatus] = useState<TrialStatus>('idle')
  const [trialDirections, setTrialDirections] = useState<number[]>([])
  const [currentIndex, setCurrentIndex] = useState(0)
  const [responseAngle, setResponseAngle] = useState<number | null>(null)
  const [responseStartTime, setResponseStartTime] = useState<number | null>(null)
  const [results, setResults] = useState<TrialResult[]>([])
  const [isStimActive, setIsStimActive] = useState<boolean | null>(null)
  const [elapsedTimeMs, setElapsedTimeMs] = useState<number>(0)
  const [isBleConnected, setIsBleConnected] = useState<boolean>(false)

  const stimTimeoutRef = useRef<number | null>(null)
  const elapsedTimeIntervalRef = useRef<number | null>(null)

  const shuffle = useCallback((arr: number[]) => {
    const copy = [...arr]
    for (let i = copy.length - 1; i > 0; i -= 1) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[copy[i], copy[j]] = [copy[j], copy[i]]
    }
    return copy
  }, [])

  const startTrial = useCallback(
    async (index: number, directions: number[]) => {
      const direction = directions[index]

      // 前のタスクのタイマーをクリア
      if (stimTimeoutRef.current !== null) {
        window.clearTimeout(stimTimeoutRef.current)
        stimTimeoutRef.current = null
      }

      // 3秒待ってから刺激開始
      setStatus('stimulating')
      setIsStimActive(null) // 3秒待機中
      setResponseAngle(null)
      setResponseStartTime(null)

      await new Promise((resolve) => {
        window.setTimeout(resolve, 3000)
      })

      // モーター動作と同時に「力覚提示中」表示とタイマーを開始（BLE送信の完了を待たない）
      setIsStimActive(true)
      setResponseStartTime(performance.now())

      // 3秒後に「力覚提示中」状態だけオフにする
      if (stimTimeoutRef.current !== null) {
        window.clearTimeout(stimTimeoutRef.current)
      }
      stimTimeoutRef.current = window.setTimeout(() => {
        setIsStimActive(false)
      }, 3000)

      // BLE接続がある場合のみESP32に送信（非ブロッキング）
      try {
        const characteristic = getBleCharacteristic()
        if (characteristic) {
          const encoder = new TextEncoder()
          // writeValue()は非同期で実行（完了を待たない）
          characteristic.writeValue(encoder.encode(String(direction))).catch((error) => {
            console.error('BLE送信エラー:', error)
            // エラーが発生しても実験は続行
          })
        }
        // BLE接続がない場合は送信をスキップして実験を続行
      } catch (error) {
        console.error('BLE送信準備エラー:', error)
        // エラーが発生しても実験は続行
      }
    },
    [method],
  )

  const handleStart = useCallback(async () => {
    if (status !== 'idle' && status !== 'finished') return

    // BLE接続は任意（接続がない場合は警告表示のみ）
    // 1セット目と2セット目をそれぞれシャッフルしてから結合
    // 各セット内では同じ方向は1度しか提示されない
    const set1 = shuffle([...BASE_DIRECTIONS])
    const set2 = shuffle([...BASE_DIRECTIONS])
    const directions = [...set1, ...set2]
    setTrialDirections(directions)
    setResults([])
    setCurrentIndex(0)
    await startTrial(0, directions)
  }, [shuffle, startTrial, status, method])

  const handleResponseClick = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      // 力覚提示が開始される前（1秒待機中）は回答を受け付けない
      if (status !== 'stimulating' || isStimActive === null) return

      const rect = event.currentTarget.getBoundingClientRect()
      const centerX = rect.left + rect.width / 2
      const centerY = rect.top + rect.height / 2

      const clickX = event.clientX
      const clickY = event.clientY

      const dx = clickX - centerX
      const dy = centerY - clickY // 画面座標は下が正なので反転

      const rad = Math.atan2(dy, dx)
      let deg = (rad * 180) / Math.PI
      if (deg < 0) deg += 360

      setResponseAngle(deg)
    },
    [status, isStimActive],
  )

  const handleSkip = useCallback(async () => {
    if (status !== 'stimulating' || !trialDirections.length || isStimActive === null) {
      return
    }

    // スキップ時は回答角度を-1として記録
    const trueDirection = trialDirections[currentIndex]
    const startTime = responseStartTime ?? performance.now()
    const responseTimeMs = performance.now() - startTime

    setResults((prev) => [
      ...prev,
      {
        index: currentIndex,
        trueDirection,
        responseAngle: -1,
        responseTimeMs,
      },
    ])

    // 次のタスクに進む
    const nextIndex = currentIndex + 1
    if (nextIndex >= trialDirections.length) {
      setStatus('finished')
    } else {
      setCurrentIndex(nextIndex)
      await startTrial(nextIndex, trialDirections)
    }
  }, [
    status,
    trialDirections,
    currentIndex,
    responseStartTime,
    isStimActive,
    startTrial,
  ])

  const handleNextTask = useCallback(async () => {
    if (status !== 'stimulating' || responseAngle == null || !trialDirections.length) {
      return
    }

    const trueDirection = trialDirections[currentIndex]
    const startTime = responseStartTime ?? performance.now()
    const responseTimeMs = performance.now() - startTime

    setResults((prev) => [
      ...prev,
      {
        index: currentIndex,
        trueDirection,
        responseAngle,
        responseTimeMs,
      },
    ])

    const nextIndex = currentIndex + 1
    if (nextIndex >= trialDirections.length) {
      setStatus('finished')
    } else {
      setCurrentIndex(nextIndex)
      await startTrial(nextIndex, trialDirections)
    }
  }, [currentIndex, responseAngle, responseStartTime, startTrial, status, trialDirections])

  const handleDownloadCsv = useCallback(() => {
    if (!results.length) return

    // 角度の差を計算する関数（循環を考慮、0-180度の範囲で返す）
    const calculateAngleError = (trueDir: number, responseDir: number): number => {
      let diff = Math.abs(trueDir - responseDir)
      // 360度の循環を考慮（例: 0度と350度の差は10度）
      if (diff > 180) {
        diff = 360 - diff
      }
      return diff
    }

    const header = [
      'participantId',
      'method',
      'trialIndex',
      'trueDirection',
      'responseAngle',
      'responseTimeMs',
      'error',
      'isCorrect',
    ]
    const lines = results.map((r) => {
      // スキップ時（responseAngle === -1）の処理
      if (r.responseAngle === -1) {
        return [
          participantId,
          method,
          r.index,
          r.trueDirection,
          '-1',
          Math.round(r.responseTimeMs),
          '', // 誤差は計算しない
          '-1', // 正答フラグは-1（スキップ）
        ].join(',')
      }

      // 通常の回答時の処理
      const error = calculateAngleError(r.trueDirection, r.responseAngle)
      const isCorrect = error <= 30 ? 1 : 0 // 30度以内なら正答

      return [
        participantId,
        method,
        r.index,
        r.trueDirection,
        r.responseAngle.toFixed(2),
        Math.round(r.responseTimeMs),
        error.toFixed(2),
        isCorrect,
      ].join(',')
    })

    const csvContent = [header.join(','), ...lines].join('\n')
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)

    const link = document.createElement('a')
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
    link.href = url
    link.setAttribute(
      'download',
      `experiment_${participantId || 'unknown'}_${method || 'unknown'}_${timestamp}.csv`,
    )
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  }, [method, participantId, results])

  // 回答時間のリアルタイム更新
  useEffect(() => {
    if (responseStartTime === null) {
      // タイマーが開始されていない場合は経過時間をリセット
      setElapsedTimeMs(0)
      if (elapsedTimeIntervalRef.current !== null) {
        window.clearInterval(elapsedTimeIntervalRef.current)
        elapsedTimeIntervalRef.current = null
      }
      return
    }

    // タイマー開始: 100msごとに経過時間を更新
    elapsedTimeIntervalRef.current = window.setInterval(() => {
      const now = performance.now()
      const elapsed = now - responseStartTime
      setElapsedTimeMs(elapsed)
    }, 100)

    return () => {
      if (elapsedTimeIntervalRef.current !== null) {
        window.clearInterval(elapsedTimeIntervalRef.current)
        elapsedTimeIntervalRef.current = null
      }
    }
  }, [responseStartTime])

  // BLE接続状態を定期的にチェック
  useEffect(() => {
    const checkBleConnection = () => {
      const characteristic = getBleCharacteristic()
      setIsBleConnected(!!characteristic)
    }

    // 初回チェック
    checkBleConnection()

    // 定期的にチェック（500ms間隔）
    const interval = setInterval(checkBleConnection, 500)

    return () => clearInterval(interval)
  }, [])

  // コンポーネントのクリーンアップ
  useEffect(
    () => () => {
      if (stimTimeoutRef.current !== null) {
        window.clearTimeout(stimTimeoutRef.current)
      }
      if (elapsedTimeIntervalRef.current !== null) {
        window.clearInterval(elapsedTimeIntervalRef.current)
      }
    },
    [],
  )

  return (
    <div className="app-root experiment-page">
      <main className="app-main experiment-main">
        <section className="card experiment-task-card">
          {status === 'idle' && (
            <>
              <p className="helper-text">
                「開始」を押すと最初のタスクが始まります。
              </p>
              <div className="button-row">
                <button className="primary-button" onClick={handleStart}>
                  開始
                </button>
                <button
                  className="secondary-button"
                  onClick={() => navigate('/')}
                >
                  ホーム画面へ
                </button>
              </div>
            </>
          )}

          {status === 'stimulating' && (
            <>
              <p className="helper-text">
                3 秒後に力覚が 3 秒間提示されます。「力覚提示中」と表示されている間も含め、
                感じた方向を円の中をクリックして回答してください。
              </p>
              {isStimActive === null ? (
                <p className="helper-text">次の力覚が 3 秒後に提示されます...</p>
              ) : isStimActive ? (
                <p className="helper-text warning">力覚提示中（約 3 秒間）</p>
              ) : (
                <p className="helper-text">力覚提示は終了しました。回答を完了してください。</p>
              )}

              <div className="response-area" onClick={handleResponseClick}>
                <div className="response-circle">
                  <div className="response-center-dot" />
                  {responseAngle != null && (
                    <div
                      className="response-marker"
                      style={{
                        // CSS の rotate() は時計回りが正方向のため、計算済みの反時計回りの角度をマイナスして適用する
                        transform: `translate(-50%, -50%) rotate(${-responseAngle}deg) translate(90px, 0)`,
                      }}
                    />
                  )}
                  {/* 角度ラベル */}
                  {BASE_DIRECTIONS.map((angle) => {
                    // 角度をラジアンに変換
                    // 右を0°として反時計回りに進む角度（handleResponseClickと同じ座標系）
                    const rad = (angle * Math.PI) / 180
                    const labelRadius = 150 // ラベルの位置（円の外側）
                    const labelX = Math.cos(rad) * labelRadius
                    const labelY = -Math.sin(rad) * labelRadius // y軸を反転（画面座標は下が正）

                    return (
                      <div
                        key={angle}
                        className="response-angle-label"
                        style={{
                          position: 'absolute',
                          left: '50%',
                          top: '50%',
                          transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
                          color: 'rgba(148, 163, 184, 0.95)',
                          fontSize: '13px',
                          fontWeight: '500',
                          pointerEvents: 'none',
                          userSelect: 'none',
                          textShadow: '0 1px 2px rgba(0, 0, 0, 0.5)',
                        }}
                      >
                        {angle}°
                      </div>
                    )
                  })}
                </div>
              </div>
              <p className="response-hint">
                回答角度:{' '}
                {responseAngle === -1
                  ? 'スキップ'
                  : responseAngle != null
                    ? `${responseAngle.toFixed(1)}°`
                    : '未回答'}
              </p>
              {isPractice && (
                <p className="response-hint">
                  正解方向:{' '}
                  {trialDirections[currentIndex] != null
                    ? `${trialDirections[currentIndex]}°`
                    : '未設定'}
                </p>
              )}
              {isPractice && (
                <p className="response-hint">
                  回答時間:{' '}
                  {responseStartTime != null
                    ? `${(elapsedTimeMs / 1000).toFixed(2)}秒`
                    : '計測開始前'}
                </p>
              )}

              <div className="button-row end">
                <button
                  className="secondary-button"
                  onClick={() => navigate('/')}
                >
                  ホーム画面へ
                </button>
                <button
                  className="secondary-button"
                  onClick={handleSkip}
                  disabled={responseAngle === -1 || isStimActive === null}
                >
                  スキップ
                </button>
                <button
                  className="primary-button"
                  onClick={handleNextTask}
                  disabled={responseAngle == null}
                >
                  次のタスク
                </button>
              </div>
            </>
          )}

          {status === 'finished' && (
            <>
              <p className="helper-text warning">
                全てのタスクが完了しました。「結果CSVをダウンロード」で結果を保存できます。
              </p>
              <div className="button-row">
                <button
                  className="primary-button"
                  onClick={handleDownloadCsv}
                  disabled={!results.length}
                >
                  結果CSVをダウンロード
                </button>
                <button
                  className="secondary-button"
                  onClick={() => navigate('/')}
                >
                  ホーム画面へ
                </button>
              </div>
            </>
          )}
        </section>
      </main>
      {!isBleConnected && (
        <div className="ble-warning-banner">
          <span className="ble-warning-icon">⚠️</span>
          <span className="ble-warning-text">
            BLEデバイスに接続されていません。力覚提示は行われませんが、実験は続行できます。
          </span>
        </div>
      )}
    </div>
  )
}

function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/experiment" element={<ExperimentPage />} />
    </Routes>
  )
}

export default App
