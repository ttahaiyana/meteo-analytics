// Package api — HTTP-обработчики: данные, загрузка, вызовы R-анализа, раздача фронтенда.
package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"meteo/internal/openmeteo"
	"meteo/internal/rrunner"
	"meteo/internal/store"
)

type Location struct {
	ID   string  `json:"id"`
	Name string  `json:"name"`
	Zone string  `json:"zone"`
	Lat  float64 `json:"lat"`
	Lon  float64 `json:"lon"`
}

type Server struct {
	Locations []Location
	Store     *store.Store
	Client    *openmeteo.Client
	R         *rrunner.Runner
	Start     string // начало загружаемого периода
	End       string
	StaticDir string // каталог собранного фронтенда ("" — не раздавать)

	mu  sync.Mutex
	job jobState
}

type jobState struct {
	Running bool              `json:"running"`
	Done    int               `json:"done"`
	Total   int               `json:"total"`
	Errors  map[string]string `json:"errors"`
}

// methods — разрешённые методы анализа и допустимые параметры запроса.
var methods = map[string][]string{
	"seasonality":  {"loc"},
	"compare":      {"k"},
	"trends":       {"loc", "var"},
	"extremes":     {"loc"},
	"correlations": {"loc"},
	"insights":     {},
	"quality":      {},
}

func LoadLocations(path string) ([]Location, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var l []Location
	if err := json.Unmarshal(b, &l); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return l, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/locations", s.locations)
	mux.HandleFunc("POST /api/fetch", s.fetch)
	mux.HandleFunc("GET /api/status", s.status)
	mux.HandleFunc("GET /api/analysis/{method}", s.analysis)
	if s.StaticDir != "" {
		mux.Handle("/", spa(s.StaticDir))
	}
	return logRequests(mux)
}

func (s *Server) find(id string) *Location {
	for i := range s.Locations {
		if s.Locations[i].ID == id {
			return &s.Locations[i]
		}
	}
	return nil
}

type locationView struct {
	Location
	Data *store.Info `json:"data"`
}

func (s *Server) locations(w http.ResponseWriter, r *http.Request) {
	out := make([]locationView, 0, len(s.Locations))
	for _, l := range s.Locations {
		info, err := s.Store.Stat(l.ID)
		if err != nil {
			log.Printf("stat %s: %v", l.ID, err)
		}
		out = append(out, locationView{l, info})
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	writeJSON(w, http.StatusOK, s.job)
}

// fetch запускает фоновую загрузку выбранных (или всех) точек.
func (s *Server) fetch(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IDs []string `json:"ids"`
	}
	if r.ContentLength != 0 {
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&req); err != nil {
			httpError(w, http.StatusBadRequest, "некорректное тело запроса")
			return
		}
	}
	var targets []Location
	if len(req.IDs) == 0 {
		targets = s.Locations
	}
	for _, id := range req.IDs {
		l := s.find(id)
		if l == nil {
			httpError(w, http.StatusBadRequest, "неизвестная точка: "+id)
			return
		}
		targets = append(targets, *l)
	}
	s.mu.Lock()
	if s.job.Running {
		s.mu.Unlock()
		httpError(w, http.StatusConflict, "загрузка уже выполняется")
		return
	}
	s.job = jobState{Running: true, Total: len(targets), Errors: map[string]string{}}
	s.mu.Unlock()

	go s.runFetch(targets)
	writeJSON(w, http.StatusAccepted, map[string]int{"total": len(targets)})
}

func (s *Server) runFetch(targets []Location) {
	ctx := context.Background()
	for i, l := range targets {
		if i > 0 {
			time.Sleep(2 * time.Second) // бережём лимиты бесплатного API
		}
		err := s.fetchOne(ctx, l)
		s.mu.Lock()
		s.job.Done++
		if err != nil {
			log.Printf("fetch %s: %v", l.ID, err)
			s.job.Errors[l.ID] = err.Error()
		}
		s.mu.Unlock()
	}
	s.mu.Lock()
	s.job.Running = false
	s.mu.Unlock()
}

func (s *Server) fetchOne(ctx context.Context, l Location) error {
	ser, err := s.Client.Fetch(ctx, l.Lat, l.Lon, s.Start, s.End)
	if err != nil {
		return err
	}
	return s.Store.Save(l.ID, ser)
}

// loaded возвращает точки, для которых данные уже загружены, и «версию» набора для кэша.
func (s *Server) loaded() ([]Location, string) {
	var out []Location
	var ver []string
	for _, l := range s.Locations {
		if info, _ := s.Store.Stat(l.ID); info != nil {
			out = append(out, l)
			ver = append(ver, l.ID+":"+strconv.FormatInt(info.ModTime, 10))
		}
	}
	sort.Strings(ver)
	return out, strings.Join(ver, ",")
}

func (s *Server) analysis(w http.ResponseWriter, r *http.Request) {
	method := r.PathValue("method")
	allowed, ok := methods[method]
	if !ok {
		httpError(w, http.StatusNotFound, "неизвестный метод анализа")
		return
	}
	loaded, version := s.loaded()
	if len(loaded) == 0 {
		httpError(w, http.StatusPreconditionFailed, "данные не загружены: выполните загрузку (POST /api/fetch)")
		return
	}
	params := map[string]string{}
	for _, p := range allowed {
		if v := r.URL.Query().Get(p); v != "" {
			params[p] = v
		}
	}
	if id := params["loc"]; id != "" {
		l := s.find(id)
		if l == nil {
			httpError(w, http.StatusBadRequest, "неизвестная точка: "+id)
			return
		}
		if info, _ := s.Store.Stat(id); info == nil {
			httpError(w, http.StatusPreconditionFailed, "для точки "+id+" данные не загружены")
			return
		}
	}
	if v, ok := params["var"]; ok && !validVar(v) {
		httpError(w, http.StatusBadRequest, "неизвестный параметр var")
		return
	}
	if v, ok := params["k"]; ok {
		if n, err := strconv.Atoi(v); err != nil || n < 2 || n > 8 {
			httpError(w, http.StatusBadRequest, "k должно быть числом от 2 до 8")
			return
		}
	}
	req := map[string]any{"data_dir": s.Store.Dir, "locations": loaded, "params": params}
	res, err := s.R.Run(r.Context(), method, req, version)
	if err != nil {
		log.Printf("analysis %s: %v", method, err)
		httpError(w, http.StatusInternalServerError, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(res)
}

func validVar(v string) bool {
	switch v {
	case "tmean", "tmax", "tmin", "precip", "wind":
		return true
	}
	return false
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func httpError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %v", r.Method, r.URL.RequestURI(), time.Since(t).Round(time.Millisecond))
	})
}

// spa раздаёт статику фронтенда, неизвестные пути отдаёт как index.html.
func spa(dir string) http.Handler {
	fs := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := filepath.Join(dir, filepath.Clean("/"+r.URL.Path))
		if _, err := os.Stat(p); err != nil {
			http.ServeFile(w, r, filepath.Join(dir, "index.html"))
			return
		}
		fs.ServeHTTP(w, r)
	})
}
