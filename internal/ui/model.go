package ui

import (
	"k8secret/internal/kubectl"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type Screen int

const (
	ScreenNamespaces Screen = iota
	ScreenSecrets
	ScreenDetail
)

type Model struct {
	screen    Screen
	width     int
	height    int
	context   string
	namespace string
	secret    string
	err       error

	namespaces NamespaceModel
	secrets    SecretsModel
	detail     DetailModel
}

// Messages
type contextMsg string
type errMsg error

func fetchContext() tea.Msg {
	ctx, err := kubectl.CurrentContext()
	if err != nil {
		return errMsg(err)
	}
	return contextMsg(ctx)
}

func New() Model {
	return Model{
		screen:     ScreenNamespaces,
		namespaces: NewNamespaceModel(),
		secrets:    NewSecretsModel(),
		detail:     NewDetailModel(),
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(fetchContext, m.namespaces.Init())
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case contextMsg:
		m.context = string(msg)
	case tea.KeyMsg:
		// Global quit
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
	}

	var cmd tea.Cmd
	switch m.screen {
	case ScreenNamespaces:
		m.namespaces, cmd = m.namespaces.Update(msg)
		if m.namespaces.chosen != "" {
			m.namespace = m.namespaces.chosen
			m.namespaces.chosen = ""
			m.screen = ScreenSecrets
			m.secrets = NewSecretsModel()
			return m, m.secrets.FetchSecrets(m.namespace)
		}
	case ScreenSecrets:
		m.secrets, cmd = m.secrets.Update(msg)
		if m.secrets.chosen != "" {
			m.secret = m.secrets.chosen
			m.secrets.chosen = ""
			m.screen = ScreenDetail
			m.detail = NewDetailModel()
			m.detail.namespace = m.namespace
			m.detail.secret = m.secret
			return m, m.detail.FetchDetail(m.namespace, m.secret)
		}
		if m.secrets.goBack {
			m.secrets.goBack = false
			m.screen = ScreenNamespaces
			return m, nil
		}
	case ScreenDetail:
		m.detail, cmd = m.detail.Update(msg)
		if m.detail.goBack {
			m.detail.goBack = false
			m.screen = ScreenSecrets
			m.secrets = NewSecretsModel()
			return m, m.secrets.FetchSecrets(m.namespace)
		}
	}

	return m, cmd
}

func (m Model) View() string {
	if m.width == 0 {
		return "Loading..."
	}

	header := m.renderHeader()
	footer := m.renderFooter()

	headerH := lipgloss.Height(header)
	footerH := lipgloss.Height(footer)
	bodyH := m.height - headerH - footerH - 1

	var body string
	switch m.screen {
	case ScreenNamespaces:
		body = m.namespaces.View(m.width, bodyH)
	case ScreenSecrets:
		body = m.secrets.View(m.width, bodyH)
	case ScreenDetail:
		body = m.detail.View(m.width, bodyH)
	}

	return header + "\n" + body + "\n" + footer
}

func (m Model) renderHeader() string {
	ctx := m.context
	if ctx == "" {
		ctx = "..."
	}

	parts := []string{HeaderStyle.Render(ctx)}

	if m.namespace != "" {
		parts = append(parts, HeaderStyle.Render(m.namespace))
	}
	if m.secret != "" {
		parts = append(parts, HeaderStyle.Render(m.secret))
	}

	sep := BreadcrumbSep.String()
	breadcrumb := strings.Join(parts, sep)

	return lipgloss.NewStyle().Width(m.width).Render(breadcrumb)
}

func (m Model) renderFooter() string {
	var hints []string

	switch m.screen {
	case ScreenNamespaces:
		hints = m.namespaces.KeyHints()
	case ScreenSecrets:
		hints = m.secrets.KeyHints()
	case ScreenDetail:
		hints = m.detail.KeyHints()
	}

	var parts []string
	for _, h := range hints {
		kv := strings.SplitN(h, ":", 2)
		if len(kv) == 2 {
			parts = append(parts, FooterKeyStyle.Render(kv[0])+FooterStyle.Render(kv[1]))
		}
	}

	return FooterStyle.Width(m.width).Render(strings.Join(parts, "  "))
}
