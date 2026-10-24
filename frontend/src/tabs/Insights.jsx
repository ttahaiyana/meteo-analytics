import React, { useState } from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, Table, useAsync, asArray, fmt } from '../ui.jsx'

const KINDS = {
  risk: ['Риск для работ на открытом воздухе', 'Reds'],
  tourism: ['Комфорт для туризма', 'Greens'],
  construction: ['Пригодность для строительства', 'Blues'],
  wind_power_index: ['Индекс ветрового потенциала', 'Purples'],
}

export default function Insights() {
  const [kind, setKind] = useState('risk')
  const st = useAsync(() => analysis('insights'), [])
  return (
    <Async state={st}>
      {(d) => {
        const rows = d.locations
        const [title, scale] = KINDS[kind]
        return (
          <>
            <div className="toolbar">
              <label>Показатель:&nbsp;
                <select value={kind} onChange={(e) => setKind(e.target.value)}>
                  {Object.entries(KINDS).map(([k, [l]]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </label>
            </div>
            <Card title={`${title}: точки × месяцы`} note={kind === 'wind_power_index' ? d.definitions.wind : `${kind === 'risk' ? d.definitions.risk : d.definitions[kind]}. Климатическая норма ${d.base}.`}>
              <Plot data={[{ z: rows.map((r) => r[kind]), x: d.months, y: rows.map((r) => r.name), type: 'heatmap', colorscale: scale,
                colorbar: { title: kind === 'wind_power_index' ? 'м³/с³' : '%' } }]}
                layout={{ yaxis: { autorange: 'reversed' }, margin: { l: 110, r: 20, t: 20, b: 40 } }} height={Math.max(300, 40 * rows.length + 90)} />
            </Card>
            <Card title="Сводка по точкам" note="Три лучших/худших месяца по каждому показателю.">
              <Table rows={rows} cols={[
                { key: 'name', label: 'Точка' },
                { key: 'riskiest', label: 'Наибольший риск', render: (v) => asArray(v).join(', ') },
                { key: 'best_tourism', label: 'Лучше для туризма', render: (v) => asArray(v).join(', ') },
                { key: 'best_construction', label: 'Лучше для стройки', render: (v) => asArray(v).join(', ') },
                { key: 'wind_potential', label: 'Ветровой индекс', render: (v) => fmt(v, 0) },
              ]} />
            </Card>
          </>
        )
      }}
    </Async>
  )
}
