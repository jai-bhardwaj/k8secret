package ui

import "github.com/charmbracelet/lipgloss"

var (
	HeaderStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("62")).
			Foreground(lipgloss.Color("230")).
			Bold(true).
			Padding(0, 1)

	BreadcrumbSep = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			SetString(" > ")

	FooterStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241")).
			Padding(0, 1)

	FooterKeyStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("228")).
			Bold(true)

	SelectedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("229")).
			Bold(true)

	NormalStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("252"))

	DimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))

	ErrorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true)

	SuccessStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("82")).
			Bold(true)

	FilterStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("214"))

	EditingStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("117"))

	LabelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("110")).
			Bold(true).
			Width(30)

	DiffAddStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("82"))

	DiffDelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196"))

	DiffModStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("214"))
)
