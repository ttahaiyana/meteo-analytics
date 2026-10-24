import React from 'react'
import Plot, { COLORS } from '../Plot.jsx'
import { analysis } from '../api.js'
import { Async, Card, useAsync, fmt } from '../ui.jsx'

export default function Seasonality({ loc }) {
  const st = useAsync(() => analysis('seasonality', { loc }), [loc])
  return (
    <Async state={st}>
      {(d) => (
        <>
          <div className="kpis">
            <div className="kpi"><span>Самый холодный месяц</span><b>{d.coldest}</b></div>
            <div className="kpi"><span>Самый тёплый месяц</span><b>{d.warmest}</b></div>
            <div className="kpi"><span>Норма температуры ({d.base})</span><b>{fmt(d.norm_tmean, 1)} °C</b></div>
            <div className="kpi"><span>Норма осадков ({d.base})</span><b>{fmt(d.norm_precip, 0)} мм/год</b></div>
            <div className="kpi"><span>Суточный размах: зима / лето</span><b>{fmt(d.dtr_coldest, 1)} / {fmt(d.dtr_warmest, 1)} °C</b></div>
          </div>
          <div className="grid">
            <Card title="Годовой ход температуры" note={`Среднее по дням месяца, норма ${d.base}. Линии — Tmax, Tmean, Tmin.`}>
              <Plot data={[
                { x: d.months, y: d.tmax, name: 'Tmax', type: 'scatter', mode: 'lines+markers', line: { color: COLORS[1] } },
                { x: d.months, y: d.tmean, name: 'Tmean', type: 'scatter', mode: 'lines+markers', line: { color: COLORS[3] } },
                { x: d.months, y: d.tmin, name: 'Tmin', type: 'scatter', mode: 'lines+markers', line: { color: COLORS[0] } },
              ]} layout={{ yaxis: { title: '°C' } }} />
            </Card>
            <Card title="Осадки по месяцам" note="Средняя месячная сумма за базовый период.">
              <Plot data={[{ x: d.months, y: d.precip, type: 'bar', marker: { color: COLORS[0] }, name: 'Осадки' }]}
                layout={{ yaxis: { title: 'мм' } }} />
            </Card>
            <Card title="Суточная амплитуда температуры (Tmax − Tmin)" note="Показывает суточный ход: зимой и летом разница между днём и ночью различается.">
              <Plot data={[{ x: d.months, y: d.dtr, type: 'bar', marker: { color: COLORS[3] }, name: 'Амплитуда' }]}
                layout={{ yaxis: { title: '°C' } }} />
            </Card>
            <Card title="Ветер и влажность">
              <Plot data={[
                { x: d.months, y: d.wind, name: 'Ветер, м/с', type: 'scatter', mode: 'lines+markers', line: { color: COLORS[5] } },
                { x: d.months, y: d.hum, name: 'Влажность, %', yaxis: 'y2', type: 'scatter', mode: 'lines+markers', line: { color: COLORS[4] } },
              ]} layout={{ yaxis: { title: 'м/с' }, yaxis2: { title: '%', overlaying: 'y', side: 'right' } }} />
            </Card>
            <Card title="Годовые аномалии температуры" note={`Отклонение среднегодовой температуры от нормы ${d.base}.`}>
              <Plot data={[{ x: d.years, y: d.tmean_anom, type: 'bar', name: 'Аномалия',
                marker: { color: d.tmean_anom.map((v) => (v >= 0 ? COLORS[1] : COLORS[0])) } }]}
                layout={{ yaxis: { title: '°C' } }} />
            </Card>
            <Card title="Годовые аномалии осадков" note="Отклонение годовой суммы от нормы, %. Пропущенные годы (недостаточно данных) не показываются.">
              <Plot data={[{ x: d.years, y: d.precip_anom_pct, type: 'bar', name: 'Аномалия',
                marker: { color: d.precip_anom_pct.map((v) => (v >= 0 ? COLORS[0] : COLORS[3])) } }]}
                layout={{ yaxis: { title: '%' } }} />
            </Card>
          </div>
        </>
      )}
    </Async>
  )
}
