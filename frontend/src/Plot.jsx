import React, { useEffect, useRef } from 'react'
import Plotly from 'plotly.js-dist-min'

const FONT = { family: 'Inter, system-ui, sans-serif', size: 12, color: '#1f2937' }

// Обёртка над Plotly: перерисовка при смене данных, адаптивный размер.
export default function Plot({ data, layout = {}, height = 360 }) {
  const ref = useRef(null)
  useEffect(() => {
    const el = ref.current
    Plotly.react(
      el,
      data,
      {
        font: FONT, height, margin: { l: 55, r: 20, t: 36, b: 45 },
        paper_bgcolor: 'rgba(0,0,0,0)', plot_bgcolor: 'rgba(0,0,0,0)',
        legend: { orientation: 'h', y: -0.2 }, ...layout,
      },
      { responsive: true, displaylogo: false },
    )
  }, [data, layout, height])
  useEffect(() => {
    const el = ref.current
    return () => Plotly.purge(el)
  }, [])
  return <div ref={ref} style={{ width: '100%' }} />
}

export const COLORS = ['#2563eb', '#dc2626', '#16a34a', '#d97706', '#7c3aed', '#0891b2', '#db2777', '#4b5563']
