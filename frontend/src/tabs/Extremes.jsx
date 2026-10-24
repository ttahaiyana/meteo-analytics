import React, { useState } from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, Table, useAsync, fmt, fmtP } from '../ui.jsx'

const IND = {
  hot_days: 'Жаркие дни (Tmax > P95)', heatwaves: 'Волны жары (≥3 дня подряд)', frost_days: 'Дни с заморозком (Tmin < 0)',
  heavy_rain_days: 'Дни с сильными осадками', max_dry_spell: 'Макс. сухой период (дни)',
}

export default function Extremes({ loc }) {
  const [ind, setInd] = useState('hot_days')
  const st = useAsync(() => analysis('extremes', { loc }), [loc])
  return (
    <Async state={st}>
      {(d) => {
        const y = d.yearly
        const tr = d.trends.find((t) => t.indicator === ind)
        return (
          <>
            <div className="kpis">
              {d.records.map((r) => (
                <div className="kpi" key={r.label}><span>{r.label} ({r.date})</span><b>{fmt(r.value, 1)} {r.unit}</b></div>
              ))}
              <div className="kpi"><span>Порог жары (P95 Tmax, {d.thresholds.base})</span><b>{fmt(d.thresholds.hot_p95_tmax, 1)} °C</b></div>
              <div className="kpi"><span>Порог ливня (P95 дождливых дней)</span><b>{fmt(d.thresholds.heavy_rain_mm, 1)} мм</b></div>
            </div>
            <div className="toolbar">
              <label>Индикатор:&nbsp;
                <select value={ind} onChange={(e) => setInd(e.target.value)}>
                  {Object.entries(IND).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </label>
              {tr && <span className="note">Тренд: {fmt(tr.sen, 2)} за десятилетие (95% ДИ {fmt(tr.sen_lo, 2)}…{fmt(tr.sen_hi, 2)}), p = {fmtP(tr.mk_p)} — {tr.direction}</span>}
            </div>
            <div className="grid">
              <Card title={IND[ind]} note="Число эпизодов по годам и тренд Тейла–Сена.">
                <Plot data={[
                  { x: y.map((r) => r.year), y: y.map((r) => r[ind]), type: 'bar', marker: { color: COLORS[3] }, name: 'Год' },
                  ...(tr && tr.sen != null ? [{
                    x: [y[0].year, y[y.length - 1].year], mode: 'lines', type: 'scatter', name: 'Тренд', line: { color: COLORS[1], width: 3 },
                    y: (() => {
                      const ys = y.map((r) => r[ind]); const m = ys.reduce((a, b) => a + b, 0) / ys.length
                      const xm = (y[0].year + y[y.length - 1].year) / 2
                      return [m + (tr.sen / 10) * (y[0].year - xm), m + (tr.sen / 10) * (y[y.length - 1].year - xm)]
                    })(),
                  }] : []),
                ]} />
              </Card>
              <Card title="Максимумы по годам: осадки за сутки и ветер">
                <Plot data={[
                  { x: y.map((r) => r.year), y: y.map((r) => r.max_precip), name: 'Осадки, мм', type: 'scatter', mode: 'lines', line: { color: COLORS[0] } },
                  { x: y.map((r) => r.year), y: y.map((r) => r.max_wind), name: 'Ветер, м/с', yaxis: 'y2', type: 'scatter', mode: 'lines', line: { color: COLORS[5] } },
                ]} layout={{ yaxis: { title: 'мм' }, yaxis2: { title: 'м/с', overlaying: 'y', side: 'right' } }} />
              </Card>
            </div>
            <Card title="Тренды индикаторов экстремальности">
              <Table rows={d.trends} cols={[
                { key: 'indicator', label: 'Индикатор', render: (v) => IND[v] }, { key: 'sen', label: 'Тейл–Сен /дек.', render: (v) => fmt(v, 2) },
                { key: 'sen_lo', label: 'ДИ от', render: (v) => fmt(v, 2) }, { key: 'sen_hi', label: 'ДИ до', render: (v) => fmt(v, 2) },
                { key: 'mk_p', label: 'p (МК)', render: fmtP }, { key: 'direction', label: 'Вывод' },
              ]} />
            </Card>
          </>
        )
      }}
    </Async>
  )
}
