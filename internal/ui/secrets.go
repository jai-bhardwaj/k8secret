package ui

import (
	"fmt"
	"k8secret/internal/kubectl"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

type secretsMsg []kubectl.Secret

type SecretsModel struct {
	items     []kubectl.Secret
	filtered  []kubectl.Secret
	cursor    int
	filter    string
	filtering bool
	loading   bool
	err       error
	chosen    string
	goBack    bool
}

func NewSecretsModel() SecretsModel {
	return SecretsModel{loading: true}
}

func (m SecretsModel) FetchSecrets(namespace string) tea.Cmd {
	return func() tea.Msg {
		secrets, err := kubectl.ListSecrets(namespace)
		if err != nil {
			return errMsg(err)
		}
		return secretsMsg(secrets)
	}
}

func (m SecretsModel) Update(msg tea.Msg) (SecretsModel, tea.Cmd) {
	switch msg := msg.(type) {
	case secretsMsg:
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

func (m SecretsModel) updateNormal(msg tea.KeyMsg) (SecretsModel, tea.Cmd) {
	switch msg.String() {
	case "q":
		return m, tea.Quit
	case "esc":
		m.goBack = true
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

func (m SecretsModel) updateFilter(msg tea.KeyMsg) (SecretsModel, tea.Cmd) {
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

func (m *SecretsModel) applyFilter() {
	if m.filter == "" {
		m.filtered = m.items
	} else {
		m.filtered = nil
		lower := strings.ToLower(m.filter)
		for _, s := range m.items {
			if strings.Contains(strings.ToLower(s.Name), lower) ||
				strings.Contains(strings.ToLower(s.Type), lower) {
				m.filtered = append(m.filtered, s)
			}
		}
	}
	if m.cursor >= len(m.filtered) {
		m.cursor = max(0, len(m.filtered)-1)
	}
}

func (m SecretsModel) View(width, height int) string {
	if m.loading {
		return DimStyle.Render("  Loading secrets...")
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

	title := fmt.Sprintf("  Secrets (%d)", len(m.filtered))
	b.WriteString(DimStyle.Render(title) + "\n")

	// Column header
	hdr := fmt.Sprintf("  %-35s %-30s %s", "NAME", "TYPE", "AGE")
	b.WriteString(DimStyle.Render(hdr) + "\n")

	listHeight := height - 4
	if m.filtering || m.filter != "" {
		listHeight--
	}
	if listHeight < 1 {
		listHeight = 1
	}

	visibleStart := 0
	if m.cursor >= visibleStart+listHeight {
		visibleStart = m.cursor - listHeight + 1
	}
	if visibleStart > 0 && m.cursor < visibleStart {
		visibleStart = m.cursor
	}

	for i := visibleStart; i < len(m.filtered) && i < visibleStart+listHeight; i++ {
		s := m.filtered[i]
		line := fmt.Sprintf("%-35s %-30s %s", s.Name, s.Type, s.Age())
		if i == m.cursor {
			b.WriteString(SelectedStyle.Render("  > " + line))
		} else {
			b.WriteString(NormalStyle.Render("    " + line))
		}
		b.WriteString("\n")
	}

	if len(m.filtered) == 0 {
		b.WriteString(DimStyle.Render("  No secrets found"))
	}

	return b.String()
}

func (m SecretsModel) KeyHints() []string {
	if m.filtering {
		return []string{"esc: cancel", "enter: apply"}
	}
	return []string{"j/k: navigate", "enter: select", "/: filter", "esc: back", "q: quit"}
}
