import React, { useState } from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, useAsync } from '../ui.jsx'

export default function Correlations({ loc }) {
  const [method, setMethod] = useState('spearman')
  const [x, setX] = useState('tmean')
  const [y, setY] = useState('hum')
  const st = useAsync(() => analysis('correlations', { loc }), [loc])
  return (
    <Async state={st}>
      {(d) => {
        const z = d[method]
        const lab = Object.fromEntries(d.vars.map((v, i) => [v, d.labels[i]]))
        return (
          <>
            <div className="toolbar">
              <label>Коэффициент:&nbsp;
                <select value={method} onChange={(e) => setMethod(e.target.value)}>
                  <option value="spearman">Спирмен (ранговый)</option>
                  <option value="pearson">Пирсон</option>
                </select>
              </label>
              <label>Ось X:&nbsp;<select value={x} onChange={(e) => setX(e.target.value)}>{d.vars.map((v) => <option key={v} value={v}>{lab[v]}</option>)}</select></label>
              <label>Ось Y:&nbsp;<select value={y} onChange={(e) => setY(e.target.value)}>{d.vars.map((v) => <option key={v} value={v}>{lab[v]}</option>)}</select></label>
            </div>
            <div className="grid">
              <Card title="Матрица корреляций (суточные значения)" note="Корреляция показывает связь, но не причинность; на суточных рядах сезонность усиливает связи с температурой.">
                <Plot data={[{ z, x: d.labels, y: d.labels, type: 'heatmap', zmin: -1, zmax: 1, colorscale: 'RdBu', reversescale: true,
                  text: z.map((r) => r.map((v) => v.toFixed(2))), texttemplate: '%{text}' }]}
                  layout={{ yaxis: { autorange: 'reversed' } }} height={420} />
              </Card>
              <Card title={`${lab[x]} — ${lab[y]}`} note="Случайная выборка 900 суток.">
                <Plot data={[{ x: d.sample[x], y: d.sample[y], mode: 'markers', type: 'scatter', marker: { color: COLORS[0], opacity: 0.45, size: 5 } }]}
                  layout={{ xaxis: { title: lab[x] }, yaxis: { title: lab[y] } }} height={420} />
              </Card>
            </div>
          </>
        )
      }}
    </Async>
  )
}
