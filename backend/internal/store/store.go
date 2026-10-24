// Package store хранит сырые загрузки в CSV отдельно от результатов расчётов.
package store

import (
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"meteo/internal/openmeteo"
)

type Store struct{ Dir string }

func (s *Store) path(id string) string { return filepath.Join(s.Dir, id+".csv") }

// Save записывает ряд атомарно (через временный файл).
func (s *Store) Save(id string, ser *openmeteo.Series) error {
	if err := os.MkdirAll(s.Dir, 0o755); err != nil {
		return err
	}
	tmp := s.path(id) + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	header := append([]string{"date"}, openmeteo.Variables...)
	if err := w.Write(header); err != nil {
		f.Close()
		return err
	}
	for i, d := range ser.Dates {
		row := make([]string, 0, len(header))
		row = append(row, d)
		for _, v := range openmeteo.Variables {
			if p := ser.Columns[v][i]; p != nil {
				row = append(row, strconv.FormatFloat(*p, 'f', -1, 64))
			} else {
				row = append(row, "")
			}
		}
		if err := w.Write(row); err != nil {
			f.Close()
			return err
		}
	}
	w.Flush()
	if err := w.Error(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, s.path(id))
}

// Info — сведения о загруженном ряде.
type Info struct {
	Rows     int     `json:"rows"`
	From     string  `json:"from"`
	To       string  `json:"to"`
	Missing  int     `json:"missing"`  // число пустых значений
	Complete float64 `json:"complete"` // доля заполненных значений, %
	ModTime  int64   `json:"modTime"`
}

// Stat возвращает сведения о ряде или nil, если он не загружен.
func (s *Store) Stat(id string) (*Info, error) {
	fi, err := os.Stat(s.path(id))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	f, err := os.Open(s.path(id))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	recs, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", id, err)
	}
	if len(recs) < 2 {
		return nil, fmt.Errorf("%s: пустой файл", id)
	}
	info := &Info{Rows: len(recs) - 1, From: recs[1][0], To: recs[len(recs)-1][0], ModTime: fi.ModTime().Unix()}
	cells := 0
	for _, r := range recs[1:] {
		for _, c := range r[1:] {
			cells++
			if c == "" {
				info.Missing++
			}
		}
	}
	if cells > 0 {
		info.Complete = 100 * float64(cells-info.Missing) / float64(cells)
	}
	return info, nil
}
