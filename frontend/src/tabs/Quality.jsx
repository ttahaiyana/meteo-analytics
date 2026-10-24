import React from 'react'
import { analysis } from '../api.js'
import { Async, Card, Table, useAsync, fmt } from '../ui.jsx'

export default function Quality() {
  const st = useAsync(() => analysis('quality'), [])
  return (
    <Async state={st}>
      {(d) => {
        const sum = (o) => Object.values(o).reduce((a, b) => a + b, 0)
        const rows = d.locations.map((l) => ({ ...l, out: sum(l.outliers), fill: sum(l.filled), miss: Math.max(...Object.values(l.missing_pct)), left: Math.max(...Object.values(l.left_pct)) }))
        return (
          <>
            <Card title="Правила предобработки" note="Недопустимые значения заменяются пропуском; короткие пропуски линейно интерполируются; осадки не интерполируются.">
              <ul>
                <li>Физические диапазоны: {Object.entries(d.rules.limits).map(([k, v]) => `${k}: ${v[0]}…${v[1]}`).join('; ')}.</li>
                <li>Интерполяция пропусков не длиннее {d.rules.max_gap_days} суток (кроме: {d.rules.no_interpolation}).</li>
                <li>Единицы: °C, мм, м/с, %, гПа; время — GMT.</li>
              </ul>
            </Card>
            <Card title="Качество рядов по точкам">
              <Table rows={rows} cols={[
                { key: 'name', label: 'Точка' }, { key: 'from', label: 'С' }, { key: 'to', label: 'По' }, { key: 'rows', label: 'Суток' },
                { key: 'miss', label: 'Макс. доля пропусков, %', render: (v) => fmt(v, 3) },
                { key: 'out', label: 'Выбросов удалено' }, { key: 'fill', label: 'Пропусков заполнено' },
                { key: 'left', label: 'Пропусков осталось (макс.), %', render: (v) => fmt(v, 3) },
              ]} />
            </Card>
          </>
        )
      }}
    </Async>
  )
}
