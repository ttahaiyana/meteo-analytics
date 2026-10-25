import React, { useCallback, useEffect, useState } from 'react'
import { getLocations, getStatus, startFetch } from './api.js'
import Seasonality from './tabs/Seasonality.jsx'
import Compare from './tabs/Compare.jsx'
import Trends from './tabs/Trends.jsx'
import Extremes from './tabs/Extremes.jsx'
import Correlations from './tabs/Correlations.jsx'
import Insights from './tabs/Insights.jsx'
import Quality from './tabs/Quality.jsx'

const TABS = [
  ['season', 'Режим и сезонность', Seasonality, true],
  ['compare', 'Сравнение регионов', Compare, false],
  ['trends', 'Тренды', Trends, true],
  ['extremes', 'Экстремумы', Extremes, true],
  ['corr', 'Связи параметров', Correlations, true],
  ['insights', 'Прикладные выводы', Insights, false],
  ['quality', 'Качество данных', Quality, false],
]

export default function App() {
  const [locs, setLocs] = useState([])
  const [loc, setLoc] = useState('')
  const [tab, setTab] = useState('season')
  const [job, setJob] = useState(null)
  const [error, setError] = useState(null)

  const refresh = useCallback(async () => {
    try {
      const l = await getLocations()
      setLocs(l)
      setLoc((cur) => (cur && l.find((x) => x.id === cur && x.data) ? cur : l.find((x) => x.data)?.id || ''))
    } catch (e) { setError(e.message) }
  }, [])

  useEffect(() => { refresh(); getStatus().then(setJob).catch(() => {}) }, [refresh])

  // пока идёт загрузка — опрашиваем статус и обновляем список точек
  useEffect(() => {
    if (!job?.running) return
    const t = setInterval(async () => {
      try {
        const s = await getStatus()
        setJob(s)
        refresh()
      } catch (e) { setError(e.message) }
    }, 3000)
    return () => clearInterval(t)
  }, [job?.running, refresh])

  const loaded = locs.filter((l) => l.data)
  const load = async () => {
    setError(null)
    try {
      await startFetch(locs.filter((l) => !l.data).map((l) => l.id))
      setJob(await getStatus())
    } catch (e) { setError(e.message) }
  }
  const Active = TABS.find((t) => t[0] === tab)
  const View = Active[2]
  const errs = job?.errors ? Object.entries(job.errors) : []

  return (
    <>
      <header>
        <h1>Аналитика погоды · Open-Meteo (ERA5)</h1>
        <span className="spacer" />
        {job?.running && (
          <>
            <div className="progress"><i style={{ width: `${(100 * job.done) / Math.max(job.total, 1)}%` }} /></div>
            <span className="sub">загрузка {job.done}/{job.total}</span>
          </>
        )}
        {loaded.length === 0 && (
          <button className="btn" onClick={load} disabled={job?.running}>Загрузить данные</button>
        )}
      </header>
      <nav>
        {TABS.map(([id, label]) => (
          <button key={id} className={id === tab ? 'active' : ''} onClick={() => setTab(id)}>{label}</button>
        ))}
      </nav>
      <main>
        {error && <div className="error" style={{ marginBottom: 12 }}>{error}</div>}
        {errs.length > 0 && (
          <div className="error" style={{ marginBottom: 12 }}>
            Не загружено: {errs.map(([id, m]) => `${locs.find((l) => l.id === id)?.name || id} (${m})`).join('; ')}.
            Бесплатный API ограничивает число запросов — повторите позже командой make fetch-missing.
          </div>
        )}
        {loaded.length === 0 ? (
          <div className="card empty">
            <h3>Данных пока нет</h3>
            <p className="muted">Нажмите «Загрузить данные»: приложение скачает суточные ряды 1950–2024 для {locs.length} точек из разных климатических зон.
              Загрузка занимает несколько минут из-за лимитов API.</p>
          </div>
        ) : (
          <>
            {Active[3] && (
              <div className="toolbar">
                <label>Точка:&nbsp;
                  <select value={loc} onChange={(e) => setLoc(e.target.value)}>
                    {loaded.map((l) => <option key={l.id} value={l.id}>{l.name} — {l.zone}</option>)}
                  </select>
                </label>
              </div>
            )}
            <View loc={loc} locs={loaded} />
          </>
        )}
      </main>
    </>
  )
}
