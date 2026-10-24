import React, { useState } from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, Table, useAsync, fmt, fmtP } from '../ui.jsx'

const VARS = { tmean: 'Средняя температура', tmax: 'Максимальная температура', tmin: 'Минимальная температура', precip: 'Годовая сумма осадков', wind: 'Скорость ветра (макс.)' }

const slopeCell = (v, r) => <span className={r.significant ? (v > 0 ? 'pos' : 'neg') : 'dim'}>{fmt(v, 3)}</span>

export default function Trends({ loc, locs }) {
  const [v, setV] = useState('tmean')
  const one = useAsync(() => analysis('trends', { loc, var: v }), [loc, v])
  const rank = useAsync(() => analysis('trends', { var: v }), [v, locs.length])
  return (
    <>
      <div className="toolbar">
        <label>Параметр:&nbsp;
          <select value={v} onChange={(e) => setV(e.target.value)}>
            {Object.entries(VARS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </label>
        <span className="note">Скорости — в единицах за десятилетие. Значимость — тест Манна–Кендалла, p&lt;0.05.</span>
      </div>
      <Async state={one}>
        {(d) => {
          const s = d.stats
          return (
            <>
              <div className="kpis">
                <div className="kpi"><span>Тренд (Тейл–Сен)</span><b>{fmt(s.sen, 3)} {d.unit}/дек.</b></div>
                <div className="kpi"><span>95% ДИ</span><b>{fmt(s.sen_lo, 2)} … {fmt(s.sen_hi, 2)}</b></div>
                <div className="kpi"><span>Регрессия (OLS)</span><b>{fmt(s.ols, 3)} {d.unit}/дек.</b></div>
                <div className="kpi"><span>Манн–Кендалл: p / τ</span><b>{fmtP(s.mk_p)} / {fmt(s.mk_tau, 2)}</b></div>
                <div className="kpi"><span>Вывод</span><b>{s.direction}</b></div>
              </div>
              <div className="grid">
                <Card title={`${VARS[v]} по годам: ${d.location.name}`} note="Линия — тренд Тейла–Сена.">
                  <Plot data={[
                    { x: d.years, y: d.values, type: 'scatter', mode: 'lines+markers', name: 'Год', line: { color: COLORS[0] }, marker: { size: 4 } },
                    { x: d.sen_line.x, y: d.sen_line.y, type: 'scatter', mode: 'lines', name: 'Тренд', line: { color: COLORS[1], width: 3 } },
                  ]} layout={{ yaxis: { title: d.unit } }} />
                </Card>
                <Card title="Сезонные тренды" note="Зима — декабрь предыдущего года и январь–февраль. Закрашенные столбцы — значимые тренды.">
                  <Plot data={[{ x: d.seasons.map((r) => r.label), y: d.seasons.map((r) => r.sen), type: 'bar',
                    error_y: { type: 'data', symmetric: false, array: d.seasons.map((r) => r.sen_hi - r.sen), arrayminus: d.seasons.map((r) => r.sen - r.sen_lo) },
                    marker: { color: d.seasons.map((r) => (r.significant ? COLORS[1] : '#cbd5e1')) } }]}
                    layout={{ yaxis: { title: `${d.unit}/декаду` } }} />
                </Card>
              </div>
              <Card title="Сезонные тренды: детали">
                <Table rows={d.seasons} cols={[
                  { key: 'label', label: 'Сезон' }, { key: 'sen', label: 'Тейл–Сен', render: slopeCell },
                  { key: 'sen_lo', label: 'ДИ от', render: (x) => fmt(x, 3) }, { key: 'sen_hi', label: 'ДИ до', render: (x) => fmt(x, 3) },
                  { key: 'ols', label: 'OLS', render: (x) => fmt(x, 3) }, { key: 'mk_p', label: 'p (МК)', render: fmtP }, { key: 'direction', label: 'Вывод' },
                ]} />
              </Card>
            </>
          )
        }}
      </Async>
      <Async state={rank}>
        {(d) => (
          <div className="grid">
            <Card title="Где тренд быстрее: сравнение точек" note="Сначала тренд по каждой территории, затем сопоставление. Серые столбцы — незначимые тренды.">
              <Plot data={[{ y: d.ranking.map((r) => r.name).reverse(), x: d.ranking.map((r) => r.sen).reverse(), type: 'bar', orientation: 'h',
                error_x: { type: 'data', symmetric: false, array: d.ranking.map((r) => r.sen_hi - r.sen).reverse(), arrayminus: d.ranking.map((r) => r.sen - r.sen_lo).reverse() },
                marker: { color: d.ranking.map((r) => (r.significant ? COLORS[1] : '#cbd5e1')).reverse() } }]}
                layout={{ xaxis: { title: `${d.unit}/декаду` }, margin: { l: 110, r: 20, t: 20, b: 45 } }} />
            </Card>
            <Card title="Рейтинг">
              <Table rows={d.ranking} cols={[
                { key: 'name', label: 'Точка' }, { key: 'zone', label: 'Зона' }, { key: 'sen', label: `Тренд, ${d.unit}/дек.`, render: slopeCell },
                { key: 'mk_p', label: 'p (МК)', render: fmtP }, { key: 'direction', label: 'Вывод' },
              ]} />
            </Card>
          </div>
        )}
      </Async>
    </>
  )
}
