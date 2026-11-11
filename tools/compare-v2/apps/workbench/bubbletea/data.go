package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// The data is the same as the DABT and Textual apps use: tasks are generated like gen.py's make_tasks(), logs and notes are the static
// files in ../data (override with WB_DATA).

type task struct{ id, title, owner, status string }

func makeTasks() []task {
	owners := []string{"ada", "bob", "cy", "dee", "eli", "fay"}
	states := []string{"open", "done", "blocked"}
	verbs := []string{"Fix", "Review", "Ship", "Plan", "Test", "Draft"}
	things := []string{"parser", "cache", "login", "theme", "report", "build"}
	out := make([]task, 0, 200)
	for i := 1; i <= 200; i++ {
		out = append(out, task{fmt.Sprintf("T-%04d", i), fmt.Sprintf("%s %s %d", verbs[i%6], things[i/6%6], i), owners[i%6], states[i%3]})
	}
	return out
}

func dataDir() string {
	if d := os.Getenv("WB_DATA"); d != "" {
		return d
	}
	exe, err := os.Executable()
	if err != nil {
		return "../data"
	}
	return filepath.Join(filepath.Dir(exe), "..", "data")
}

func readData(name string) string {
	b, err := os.ReadFile(filepath.Join(dataDir(), name))
	if err != nil {
		fmt.Fprintln(os.Stderr, "workbench: cannot read data file:", err, "(set WB_DATA to apps/workbench/data)")
		os.Exit(1)
	}
	return string(b)
}

func readLogs() []string { return strings.Split(strings.TrimRight(readData("logs.txt"), "\n"), "\n") }

func (t task) searchable() string {
	return strings.ToLower(t.id + "|" + t.title + "|" + t.owner + "|" + t.status)
}
