package openmeteo

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func okBody() string {
	cols := []string{`"time":["2020-01-01","2020-01-02"]`}
	for _, v := range Variables {
		cols = append(cols, `"`+v+`":[1.5,null]`)
	}
	return `{"daily":{` + strings.Join(cols, ",") + `}}`
}

func TestParse(t *testing.T) {
	s, err := Parse([]byte(okBody()))
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Dates) != 2 || s.Columns["precipitation_sum"][1] != nil || *s.Columns["precipitation_sum"][0] != 1.5 {
		t.Fatalf("неверный разбор: %+v", s)
	}
}

func TestParseErrors(t *testing.T) {
	for name, body := range map[string]string{
		"не json":        `x`,
		"нет time":       `{"daily":{}}`,
		"нет параметра":  `{"daily":{"time":["2020-01-01"]}}`,
		"ошибка сервиса": `{"error":true,"reason":"boom"}`,
		"длина":          strings.Replace(okBody(), `[1.5,null]`, `[1.5]`, 1),
	} {
		if _, err := Parse([]byte(body)); err == nil {
			t.Errorf("%s: ожидалась ошибка", name)
		}
	}
}

func TestFetchRetry(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.Write([]byte(okBody()))
	}))
	defer srv.Close()
	c := NewClient()
	c.BaseURL = srv.URL
	if _, err := c.Fetch(context.Background(), 10, 10, "2020-01-01", "2020-01-02"); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("ожидался 1 повтор, вызовов: %d", calls)
	}
}

func TestFetchBadCoords(t *testing.T) {
	if _, err := NewClient().Fetch(context.Background(), 100, 0, "2020-01-01", "2020-01-02"); err == nil {
		t.Fatal("ожидалась ошибка координат")
	}
}
