import React, { useState } from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, Table, useAsync, fmt } from '../ui.jsx'

const FEAT = {
  tmean: 'Tср, °C', amplitude: 'Амплитуда, °C', precip_year: 'Осадки, мм/год', wind: 'Ветер, м/с',
  hum: 'Влажность, %', hot_days: 'Дни ≥30 °C', frost_days: 'Дни с Tmin<0', heavy_rain_days: 'Дни ≥20 мм',
}

export default function Compare({ locs }) {
  const [k, setK] = useState(4)
  const [feat, setFeat] = useState('amplitude')
  const st = useAsync(() => analysis('compare', { k }), [k, locs.length])
  const kmax = Math.max(2, Math.min(8, locs.length - 1))
  return (
    <>
      <div className="toolbar">
        <label>Число кластеров:&nbsp;
          <select value={k} onChange={(e) => setK(+e.target.value)}>
            {Array.from({ length: kmax - 1 }, (_, i) => i + 2).map((n) => <option key={n}>{n}</option>)}
          </select>
        </label>
        <label>Показатель:&nbsp;
          <select value={feat} onChange={(e) => setFeat(e.target.value)}>
            {Object.entries(FEAT).map(([key, l]) => <option key={key} value={key}>{l}</option>)}
          </select>
        </label>
      </div>
      <Async state={st}>
        {(d) => {
          const t = d.table
          const sorted = [...t].sort((a, b) => b[feat] - a[feat])
          return (
            <>
              <div className="grid">
                <Card title={`Сравнение: ${FEAT[feat]}`} note={`Норма ${d.base}.`}>
                  <Plot data={[{ x: sorted.map((r) => r.name), y: sorted.map((r) => r[feat]), type: 'bar',
                    marker: { color: sorted.map((r) => COLORS[(r.cluster - 1) % COLORS.length]) } }]} />
                </Card>
                <Card title="Карта точек и кластеры" note="Цвет — кластер k-means по стандартизованным показателям.">
                  <Plot data={[{ type: 'scattergeo', mode: 'markers+text', lat: t.map((r) => r.lat), lon: t.map((r) => r.lon),
                    text: t.map((r) => r.name), textposition: 'top center',
                    marker: { size: 12, color: t.map((r) => COLORS[(r.cluster - 1) % COLORS.length]) } }]}
                    layout={{ geo: { projection: { type: 'natural earth' }, showland: true, landcolor: '#eef2f7', showcountries: true, countrycolor: '#cbd5e1' }, margin: { l: 0, r: 0, t: 10, b: 0 } }} height={360} />
                </Card>
                <Card title="Проекция на главные компоненты (PCA)" note="Близкие точки — похожий погодный режим.">
                  <Plot data={[{ x: t.map((r) => r.pc1), y: t.map((r) => r.pc2), text: t.map((r) => r.name), mode: 'markers+text',
                    textposition: 'top center', type: 'scatter', marker: { size: 12, color: t.map((r) => COLORS[(r.cluster - 1) % COLORS.length]) } }]}
                    layout={{ xaxis: { title: 'PC1' }, yaxis: { title: 'PC2' } }} />
                </Card>
                <Card title="Годовой ход температуры по точкам">
                  <Plot data={d.profiles.map((p, i) => ({ x: d.months, y: p.tmean, name: t.find((r) => r.id === p.id)?.name,
                    type: 'scatter', mode: 'lines', line: { color: COLORS[i % COLORS.length] } }))} layout={{ yaxis: { title: '°C' } }} />
                </Card>
                <Card title="Годовой ход осадков по точкам">
                  <Plot data={d.profiles.map((p, i) => ({ x: d.months, y: p.precip, name: t.find((r) => r.id === p.id)?.name,
                    type: 'scatter', mode: 'lines', line: { color: COLORS[i % COLORS.length] } }))} layout={{ yaxis: { title: 'мм' } }} />
                </Card>
              </div>
              <Card title="Сводная таблица показателей">
                <Table rows={t} cols={[
                  { key: 'name', label: 'Точка' }, { key: 'zone', label: 'Зона' }, { key: 'cluster', label: 'Кластер' },
                  ...Object.entries(FEAT).map(([key, label]) => ({ key, label, render: (v) => fmt(v, 1) })),
                  { key: 'tmax_abs', label: 'Tmax абс.', render: (v) => fmt(v, 1) }, { key: 'tmin_abs', label: 'Tmin абс.', render: (v) => fmt(v, 1) },
                ]} />
              </Card>
            </>
          )
        }}
      </Async>
    </>
  )
}
