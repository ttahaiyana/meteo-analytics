// Package rrunner запускает R-скрипты анализа как подпроцесс Rscript:
// JSON-запрос приходит в stdin, JSON-ответ читается из stdout.
package rrunner

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"
)

type Runner struct {
	Rscript string // путь к Rscript
	Script  string // путь к analysis/run.R
	Timeout time.Duration
	Env     []string // дополнительные переменные окружения (например, R_LIBS_USER)

	mu    sync.Mutex
	cache map[string]json.RawMessage
}

func New(rscript, script string, env []string) *Runner {
	return &Runner{Rscript: rscript, Script: script, Timeout: 120 * time.Second, Env: env, cache: map[string]json.RawMessage{}}
}

// Run вызывает метод анализа. version входит в ключ кэша: при смене данных результат пересчитывается.
func (r *Runner) Run(ctx context.Context, method string, request any, version string) (json.RawMessage, error) {
	in, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	key := method + "|" + version + "|" + string(in)
	r.mu.Lock()
	if v, ok := r.cache[key]; ok {
		r.mu.Unlock()
		return v, nil
	}
	r.mu.Unlock()

	ctx, cancel := context.WithTimeout(ctx, r.Timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, r.Rscript, "--vanilla", r.Script, method)
	cmd.Stdin = bytes.NewReader(in)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Env = append(cmd.Environ(), r.Env...)
	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("R: превышено время выполнения метода %s", method)
		}
		return nil, fmt.Errorf("R: метод %s: %w: %s", method, err, strings.TrimSpace(lastLines(stderr.String(), 5)))
	}
	out := bytes.TrimSpace(stdout.Bytes())
	if !json.Valid(out) {
		return nil, fmt.Errorf("R: метод %s вернул некорректный JSON", method)
	}
	res := json.RawMessage(append([]byte(nil), out...))
	r.mu.Lock()
	r.cache[key] = res
	r.mu.Unlock()
	return res, nil
}

func lastLines(s string, n int) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}
