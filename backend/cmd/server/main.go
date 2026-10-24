package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"meteo/internal/api"
	"meteo/internal/openmeteo"
	"meteo/internal/rrunner"
	"meteo/internal/store"
)

func main() {
	var (
		addr   = flag.String("addr", ":8080", "адрес HTTP-сервера")
		root   = flag.String("root", "..", "корень приложения (analysis/, data/, frontend/)")
		rscr   = flag.String("rscript", "Rscript", "путь к Rscript")
		start  = flag.String("start", "1950-01-01", "начало периода")
		end    = flag.String("end", "2024-12-31", "конец периода")
		static = flag.String("static", "", "каталог собранного фронтенда (по умолчанию <root>/frontend/dist)")
	)
	flag.Parse()

	locs, err := api.LoadLocations(filepath.Join(*root, "data", "locations.json"))
	if err != nil {
		log.Fatal(err)
	}
	if *static == "" {
		*static = filepath.Join(*root, "frontend", "dist")
	}
	if _, err := os.Stat(*static); err != nil {
		log.Printf("фронтенд не собран (%s), раздаются только /api", *static)
		*static = ""
	}
	var env []string
	if lib := os.Getenv("R_LIBS_USER"); lib != "" {
		env = append(env, "R_LIBS_USER="+lib)
	}
	s := &api.Server{
		Locations: locs,
		Store:     &store.Store{Dir: filepath.Join(*root, "data", "raw")},
		Client:    openmeteo.NewClient(),
		R:         rrunner.New(*rscr, filepath.Join(*root, "analysis", "run.R"), env),
		Start:     *start,
		End:       *end,
		StaticDir: *static,
	}
	srv := &http.Server{Addr: *addr, Handler: s.Handler(), ReadHeaderTimeout: 10 * time.Second}
	log.Printf("слушаю %s", *addr)
	log.Fatal(srv.ListenAndServe())
}
