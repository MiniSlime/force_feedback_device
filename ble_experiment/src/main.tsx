import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './index.css'
import App from './App.tsx'

// GitHub Pagesではサブディレクトリにデプロイされるため、basenameを設定
// 開発環境（localhost）では空文字列、本番環境では'/force_feedback_device'
const basename = import.meta.env.PROD ? '/force_feedback_device' : ''

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter basename={basename}>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
