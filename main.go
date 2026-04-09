//go:build !desktop

package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"k8secret/internal/ui"
)

func main() {
	p := tea.NewProgram(ui.New(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
