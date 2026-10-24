// Package openmeteo загружает суточные данные реанализа ERA5 через Open-Meteo Archive API.
package openmeteo

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Variables — суточные параметры, запрашиваемые у API (порядок = порядок колонок CSV).
var Variables = []string{
	"temperature_2m_max",
	"temperature_2m_min",
	"temperature_2m_mean",
	"precipitation_sum",
	"wind_speed_10m_max",
	"relative_humidity_2m_mean",
	"pressure_msl_mean",
	"cloud_cover_mean",
}

// Series — ответ API в удобном виде: даты и колонки значений (nil = пропуск).
type Series struct {
	Dates   []string
	Columns map[string][]*float64
}

type Client struct {
	BaseURL string
	HTTP    *http.Client
	Retries int
}

func NewClient() *Client {
	return &Client{
		BaseURL: "https://archive-api.open-meteo.com/v1/archive",
		HTTP:    &http.Client{Timeout: 90 * time.Second},
		Retries: 4,
	}
}

type response struct {
	Daily map[string]json.RawMessage `json:"daily"`
	Error bool                       `json:"error"`
	Msg   string                     `json:"reason"`
}

// Fetch загружает ряд по координатам за период [start, end] (YYYY-MM-DD).
func (c *Client) Fetch(ctx context.Context, lat, lon float64, start, end string) (*Series, error) {
	if lat < -90 || lat > 90 || lon < -180 || lon > 180 {
		return nil, fmt.Errorf("некорректные координаты: %v, %v", lat, lon)
	}
	q := url.Values{}
	q.Set("latitude", fmt.Sprintf("%.4f", lat))
	q.Set("longitude", fmt.Sprintf("%.4f", lon))
	q.Set("start_date", start)
	q.Set("end_date", end)
	q.Set("daily", strings.Join(Variables, ","))
	q.Set("wind_speed_unit", "ms")
	q.Set("timezone", "GMT")
	u := c.BaseURL + "?" + q.Encode()

	var lastErr error
	for attempt := 0; attempt <= c.Retries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(attempt*attempt) * 5 * time.Second):
			}
		}
		s, retry, err := c.do(ctx, u)
		if err == nil {
			return s, nil
		}
		lastErr = err
		if !retry {
			break
		}
	}
	return nil, lastErr
}

func (c *Client) do(ctx context.Context, u string) (*Series, bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, false, err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, true, err // сетевой сбой — повторяем
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, true, err
	}
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		return nil, true, fmt.Errorf("open-meteo: HTTP %d", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, false, fmt.Errorf("open-meteo: HTTP %d: %s", resp.StatusCode, truncate(string(body), 200))
	}
	s, err := Parse(body)
	return s, false, err
}

// Parse разбирает JSON-ответ и проверяет его целостность:
// наличие поля time, всех запрошенных параметров и одинаковую длину массивов.
func Parse(body []byte) (*Series, error) {
	var r response
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("open-meteo: некорректный JSON: %w", err)
	}
	if r.Error {
		return nil, fmt.Errorf("open-meteo: %s", r.Msg)
	}
	rawTime, ok := r.Daily["time"]
	if !ok {
		return nil, fmt.Errorf("open-meteo: в ответе нет поля daily.time")
	}
	var dates []string
	if err := json.Unmarshal(rawTime, &dates); err != nil {
		return nil, fmt.Errorf("open-meteo: поле time: %w", err)
	}
	if len(dates) == 0 {
		return nil, fmt.Errorf("open-meteo: пустой ряд")
	}
	s := &Series{Dates: dates, Columns: map[string][]*float64{}}
	for _, v := range Variables {
		raw, ok := r.Daily[v]
		if !ok {
			return nil, fmt.Errorf("open-meteo: в ответе нет параметра %s", v)
		}
		var col []*float64
		if err := json.Unmarshal(raw, &col); err != nil {
			return nil, fmt.Errorf("open-meteo: параметр %s: %w", v, err)
		}
		if len(col) != len(dates) {
			return nil, fmt.Errorf("open-meteo: параметр %s: %d значений вместо %d", v, len(col), len(dates))
		}
		s.Columns[v] = col
	}
	return s, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
