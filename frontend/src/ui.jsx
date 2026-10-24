import React, { useEffect, useState } from 'react'

// Загрузка данных вкладки: показывает состояние загрузки и ошибку.
export function useAsync(fn, deps) {
  const [state, setState] = useState({ loading: true, data: null, error: null })
  useEffect(() => {
    let alive = true
    setState((s) => ({ ...s, loading: true, error: null }))
    fn().then(
      (data) => alive && setState({ loading: false, data, error: null }),
      (error) => alive && setState({ loading: false, data: null, error: error.message }),
    )
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)
  return state
}

export function Async({ state, children }) {
  if (state.error) return <div className="error">Ошибка: {state.error}</div>
  if (state.loading && !state.data) return <div className="muted">Расчёт…</div>
  if (!state.data) return null
  return <div className={state.loading ? 'stale' : ''}>{children(state.data)}</div>
}

export const Card = ({ title, note, children }) => (
  <section className="card">
    {title && <h3>{title}</h3>}
    {children}
    {note && <p className="note">{note}</p>}
  </section>
)

export const fmt = (v, d = 2) => (v == null ? '—' : Number(v).toFixed(d))
export const fmtP = (p) => (p == null ? '—' : p < 0.001 ? '<0.001' : p.toFixed(3))
export const asArray = (x) => (Array.isArray(x) ? x : x == null ? [] : [x])

// Таблица-массив объектов (R сериализует data.frame как массив записей).
export function Table({ rows, cols }) {
  return (
    <div className="tablewrap">
      <table>
        <thead><tr>{cols.map((c) => <th key={c.key}>{c.label}</th>)}</tr></thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i}>{cols.map((c) => <td key={c.key}>{c.render ? c.render(r[c.key], r) : r[c.key]}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
