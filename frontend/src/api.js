// Тонкая обёртка над REST API Go-бэкенда.
async function request(url, opts) {
  const res = await fetch(url, opts)
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`)
  return body
}

export const getLocations = () => request('/api/locations')
export const getStatus = () => request('/api/status')
export const startFetch = (ids) =>
  request('/api/fetch', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ids }) })
export const analysis = (method, params = {}) => {
  const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null && v !== ''))
  return request(`/api/analysis/${method}?${q}`)
}
