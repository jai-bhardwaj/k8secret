package ui

import (
	"fmt"
	"k8secret/internal/kubectl"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

type namespacesMsg []kubectl.Namespace

type NamespaceModel struct {
	items    []kubectl.Namespace
	filtered []kubectl.Namespace
	cursor   int
	filter   string
	filtering bool
	loading  bool
	err      error
	chosen   string
}

func NewNamespaceModel() NamespaceModel {
	return NamespaceModel{loading: true}
}

func (m NamespaceModel) Init() tea.Cmd {
	return func() tea.Msg {
		nss, err := kubectl.ListNamespaces()
		if err != nil {
			return errMsg(err)
		}
		return namespacesMsg(nss)
	}
}

func (m NamespaceModel) Update(msg tea.Msg) (NamespaceModel, tea.Cmd) {
	switch msg := msg.(type) {
	case namespacesMsg:
		m.items = msg
		m.loading = false
		m.applyFilter()
	case errMsg:
		m.err = msg
		m.loading = false
	case tea.KeyMsg:
		if m.filtering {
			return m.updateFilter(msg)
		}
		return m.updateNormal(msg)
	}
	return m, nil
}

func (m NamespaceModel) updateNormal(msg tea.KeyMsg) (NamespaceModel, tea.Cmd) {
	switch msg.String() {
	case "q":
		return m, tea.Quit
	case "j", "down":
		if m.cursor < len(m.filtered)-1 {
			m.cursor++
		}
	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
		}
	case "enter":
		if len(m.filtered) > 0 {
			m.chosen = m.filtered[m.cursor].Name
		}
	case "/":
		m.filtering = true
	case "G":
		if len(m.filtered) > 0 {
			m.cursor = len(m.filtered) - 1
		}
	case "g":
		m.cursor = 0
	}
	return m, nil
}

func (m NamespaceModel) updateFilter(msg tea.KeyMsg) (NamespaceModel, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.filtering = false
		m.filter = ""
		m.applyFilter()
	case "enter":
		m.filtering = false
	case "backspace":
		if len(m.filter) > 0 {
			m.filter = m.filter[:len(m.filter)-1]
			m.applyFilter()
		}
	default:
		if len(msg.String()) == 1 {
			m.filter += msg.String()
			m.applyFilter()
		}
	}
	return m, nil
}

func (m *NamespaceModel) applyFilter() {
	if m.filter == "" {
		m.filtered = m.items
	} else {
		m.filtered = nil
		lower := strings.ToLower(m.filter)
		for _, ns := range m.items {
			if strings.Contains(strings.ToLower(ns.Name), lower) {
				m.filtered = append(m.filtered, ns)
			}
		}
	}
	if m.cursor >= len(m.filtered) {
		m.cursor = max(0, len(m.filtered)-1)
	}
}

func (m NamespaceModel) View(width, height int) string {
	if m.loading {
		return DimStyle.Render("  Loading namespaces...")
	}
	if m.err != nil {
		return ErrorStyle.Render("  Error: " + m.err.Error())
	}

	var b strings.Builder

	if m.filtering {
		b.WriteString(FilterStyle.Render(fmt.Sprintf("  / %s_", m.filter)))
		b.WriteString("\n")
	} else if m.filter != "" {
		b.WriteString(FilterStyle.Render(fmt.Sprintf("  filter: %s", m.filter)))
		b.WriteString("\n")
	}

	title := fmt.Sprintf("  Namespaces (%d)", len(m.filtered))
	b.WriteString(DimStyle.Render(title) + "\n\n")

	// Calculate visible window
	visibleStart := 0
	listHeight := height - 4
	if m.filtering || m.filter != "" {
		listHeight--
	}
	if listHeight < 1 {
		listHeight = 1
	}
	if m.cursor >= visibleStart+listHeight {
		visibleStart = m.cursor - listHeight + 1
	}
	if visibleStart > 0 && m.cursor < visibleStart {
		visibleStart = m.cursor
	}

	for i := visibleStart; i < len(m.filtered) && i < visibleStart+listHeight; i++ {
		ns := m.filtered[i]
		status := DimStyle.Render(fmt.Sprintf("(%s)", ns.Status))
		if i == m.cursor {
			b.WriteString(SelectedStyle.Render(fmt.Sprintf("  > %-40s %s", ns.Name, status)))
		} else {
			b.WriteString(NormalStyle.Render(fmt.Sprintf("    %-40s %s", ns.Name, status)))
		}
		b.WriteString("\n")
	}

	if len(m.filtered) == 0 {
		b.WriteString(DimStyle.Render("  No namespaces found"))
	}

	return b.String()
}

func (m NamespaceModel) KeyHints() []string {
	if m.filtering {
		return []string{"esc: cancel", "enter: apply"}
	}
	return []string{"j/k: navigate", "enter: select", "/: filter", "q: quit"}
}
