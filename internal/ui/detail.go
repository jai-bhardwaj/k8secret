package ui

import (
	"fmt"
	"k8secret/internal/kubectl"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/atotto/clipboard"
	tea "github.com/charmbracelet/bubbletea"
)

// Change tracking
type ChangeKind int

const (
	ChangeNone ChangeKind = iota
	ChangeModified
	ChangeAdded
	ChangeDeleted
)

type Row struct {
	Key      string
	Original string // value from cluster ("" for added keys)
	Current  string // working value
	Kind     ChangeKind
}

// Messages
type detailMsg []kubectl.KeyValue
type saveResultMsg struct {
	err     error
	applied int
}
type clearFeedbackMsg struct{}

type DetailModel struct {
	rows      []Row
	cursor    int
	loading   bool
	err       error
	goBack    bool
	namespace string
	secret    string

	// Editing state
	editing    bool
	editIdx    int
	editValue  string
	editCursor int

	// Add key state
	adding    bool
	addStep   int // 0 = key, 1 = value
	addKey    string
	addValue  string
	addCursor int

	// Filter state
	filter    string
	filtering bool

	// Save/discard confirmation
	confirmSave    bool
	confirmDiscard bool

	// Feedback
	feedback    string
	feedbackErr bool
}

func NewDetailModel() DetailModel {
	return DetailModel{loading: true}
}

func (m DetailModel) FetchDetail(namespace, secret string) tea.Cmd {
	return func() tea.Msg {
		kvs, err := kubectl.GetSecretData(namespace, secret)
		if err != nil {
			return errMsg(err)
		}
		return detailMsg(kvs)
	}
}

func (m DetailModel) stagedCount() int {
	n := 0
	for _, r := range m.rows {
		if r.Kind != ChangeNone {
			n++
		}
	}
	return n
}

// visibleIndices returns the indices into m.rows that match the current filter.
// Staged rows (any Kind != ChangeNone) are always shown so pending changes are never hidden.
func (m DetailModel) visibleIndices() []int {
	var out []int
	lower := strings.ToLower(m.filter)
	for i, r := range m.rows {
		if r.Kind != ChangeNone || m.filter == "" ||
			strings.Contains(strings.ToLower(r.Key), lower) ||
			strings.Contains(strings.ToLower(r.Current), lower) ||
			strings.Contains(strings.ToLower(r.Original), lower) {
			out = append(out, i)
		}
	}
	return out
}

func (m DetailModel) Update(msg tea.Msg) (DetailModel, tea.Cmd) {
	switch msg := msg.(type) {
	case detailMsg:
		m.rows = make([]Row, len(msg))
		for i, kv := range msg {
			m.rows[i] = Row{Key: kv.Key, Original: kv.Value, Current: kv.Value, Kind: ChangeNone}
		}
		sort.Slice(m.rows, func(i, j int) bool { return m.rows[i].Key < m.rows[j].Key })
		m.loading = false
	case errMsg:
		m.err = msg
		m.loading = false
	case saveResultMsg:
		if msg.err != nil {
			m.feedback = fmt.Sprintf("Error after %d changes: %s", msg.applied, msg.err.Error())
			m.feedbackErr = true
		} else {
			m.feedback = fmt.Sprintf("Applied %d changes successfully", msg.applied)
			m.feedbackErr = false
		}
		m.confirmSave = false
		// Re-fetch to get fresh state
		return m, tea.Batch(
			clearFeedbackAfter(3*time.Second),
			m.FetchDetail(m.namespace, m.secret),
		)
	case clearFeedbackMsg:
		m.feedback = ""
	case tea.KeyMsg:
		if m.confirmSave {
			return m.updateConfirmSave(msg)
		}
		if m.confirmDiscard {
			return m.updateConfirmDiscard(msg)
		}
		if m.adding {
			return m.updateAdding(msg)
		}
		if m.editing {
			return m.updateEditing(msg)
		}
		if m.filtering {
			return m.updateFiltering(msg)
		}
		return m.updateNormal(msg)
	}
	return m, nil
}

// insertAtCursor splices text into s at position cur and returns the new string and cursor.
func insertAtCursor(s string, cur int, text string) (string, int) {
	// Strip control characters / newlines so pasted multi-line values collapse to one line.
	text = strings.Map(func(r rune) rune {
		if r == '\n' || r == '\r' {
			return ' '
		}
		if r < 0x20 {
			return -1
		}
		return r
	}, text)
	out := s[:cur] + text + s[cur:]
	return out, cur + len(text)
}

func clearFeedbackAfter(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(time.Time) tea.Msg {
		return clearFeedbackMsg{}
	})
}

func (m DetailModel) updateNormal(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	vis := m.visibleIndices()

	switch msg.String() {
	case "q":
		if m.stagedCount() > 0 {
			m.feedback = "Unsaved changes! Press s to save or ctrl+z to discard"
			m.feedbackErr = true
			return m, clearFeedbackAfter(3 * time.Second)
		}
		return m, tea.Quit
	case "esc":
		if m.filter != "" {
			m.filter = ""
			m.filtering = false
			m.clampCursor()
			return m, nil
		}
		if m.stagedCount() > 0 {
			m.feedback = "Unsaved changes! Press s to save or ctrl+z to discard"
			m.feedbackErr = true
			return m, clearFeedbackAfter(3 * time.Second)
		}
		m.goBack = true
	case "j", "down":
		if m.cursor < len(vis)-1 {
			m.cursor++
		}
	case "k", "up":
		if m.cursor > 0 {
			m.cursor--
		}
	case "G":
		if len(vis) > 0 {
			m.cursor = len(vis) - 1
		}
	case "g":
		m.cursor = 0
	case "/":
		m.filtering = true
	case "e":
		if len(vis) > 0 {
			ri := vis[m.cursor]
			if m.rows[ri].Kind != ChangeDeleted {
				m.editing = true
				m.editIdx = ri
				m.editValue = m.rows[ri].Current
				m.editCursor = len(m.editValue)
			}
		}
	case "a":
		m.adding = true
		m.addStep = 0
		m.addKey = ""
		m.addValue = ""
		m.addCursor = 0
	case "d":
		if len(vis) > 0 {
			ri := vis[m.cursor]
			r := &m.rows[ri]
			if r.Kind == ChangeAdded {
				m.rows = append(m.rows[:ri], m.rows[ri+1:]...)
				m.clampCursor()
			} else if r.Kind != ChangeDeleted {
				r.Kind = ChangeDeleted
			}
		}
	case "u":
		if len(vis) > 0 {
			ri := vis[m.cursor]
			r := &m.rows[ri]
			switch r.Kind {
			case ChangeModified:
				r.Current = r.Original
				r.Kind = ChangeNone
			case ChangeDeleted:
				r.Kind = ChangeNone
			case ChangeAdded:
				m.rows = append(m.rows[:ri], m.rows[ri+1:]...)
				m.clampCursor()
			}
		}
	case "s":
		if m.stagedCount() == 0 {
			m.feedback = "No changes to save"
			m.feedbackErr = false
			return m, clearFeedbackAfter(2 * time.Second)
		}
		m.confirmSave = true
	case "ctrl+z":
		if m.stagedCount() == 0 {
			m.feedback = "No changes to discard"
			m.feedbackErr = false
			return m, clearFeedbackAfter(2 * time.Second)
		}
		m.confirmDiscard = true
	}
	return m, nil
}

func (m *DetailModel) clampCursor() {
	vis := m.visibleIndices()
	if m.cursor >= len(vis) && m.cursor > 0 {
		m.cursor = len(vis) - 1
	}
	if len(vis) == 0 {
		m.cursor = 0
	}
}

func (m DetailModel) updateFiltering(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.filtering = false
		m.filter = ""
		m.clampCursor()
	case "enter":
		m.filtering = false
		m.clampCursor()
	case "backspace":
		if len(m.filter) > 0 {
			m.filter = m.filter[:len(m.filter)-1]
			m.clampCursor()
		}
	default:
		s := msg.String()
		if len(s) == 1 || s == " " {
			m.filter += s
			m.clampCursor()
		}
	}
	return m, nil
}

func (m DetailModel) updateEditing(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	// Terminal-native paste (cmd+v on macOS, bracketed paste on Linux)
	if msg.Paste {
		m.editValue, m.editCursor = insertAtCursor(m.editValue, m.editCursor, string(msg.Runes))
		return m, nil
	}
	switch msg.String() {
	case "esc":
		m.editing = false
	case "enter":
		r := &m.rows[m.editIdx]
		r.Current = m.editValue
		if r.Kind != ChangeAdded {
			if r.Current == r.Original {
				r.Kind = ChangeNone
			} else {
				r.Kind = ChangeModified
			}
		}
		m.editing = false
	case "backspace":
		if m.editCursor > 0 {
			m.editValue = m.editValue[:m.editCursor-1] + m.editValue[m.editCursor:]
			m.editCursor--
		}
	case "left":
		if m.editCursor > 0 {
			m.editCursor--
		}
	case "right":
		if m.editCursor < len(m.editValue) {
			m.editCursor++
		}
	case "ctrl+a":
		m.editCursor = 0
	case "ctrl+e":
		m.editCursor = len(m.editValue)
	case "ctrl+k":
		m.editValue = m.editValue[:m.editCursor]
	case "ctrl+u":
		m.editValue = m.editValue[m.editCursor:]
		m.editCursor = 0
	case "ctrl+v":
		if text, err := clipboard.ReadAll(); err == nil {
			m.editValue, m.editCursor = insertAtCursor(m.editValue, m.editCursor, text)
		}
	default:
		s := msg.String()
		if len(s) == 1 || s == " " {
			m.editValue = m.editValue[:m.editCursor] + s + m.editValue[m.editCursor:]
			m.editCursor++
		}
	}
	return m, nil
}

func (m DetailModel) updateAdding(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	// Terminal-native paste (cmd+v on macOS, bracketed paste on Linux)
	if msg.Paste {
		text := string(msg.Runes)
		if m.addStep == 0 {
			m.addKey, m.addCursor = insertAtCursor(m.addKey, m.addCursor, text)
		} else {
			m.addValue, m.addCursor = insertAtCursor(m.addValue, m.addCursor, text)
		}
		return m, nil
	}
	switch msg.String() {
	case "esc":
		m.adding = false
	case "enter":
		if m.addStep == 0 {
			if m.addKey == "" {
				return m, nil
			}
			m.addStep = 1
			m.addCursor = 0
		} else {
			// Stage the new key
			newRowIdx := len(m.rows)
			m.rows = append(m.rows, Row{
				Key:     m.addKey,
				Current: m.addValue,
				Kind:    ChangeAdded,
			})
			// cursor indexes into visibleIndices(), not m.rows directly —
			// find where the new row landed in the visible list
			m.cursor = 0
			for vi, ri := range m.visibleIndices() {
				if ri == newRowIdx {
					m.cursor = vi
					break
				}
			}
			m.adding = false
		}
	case "backspace":
		if m.addStep == 0 {
			if m.addCursor > 0 {
				m.addKey = m.addKey[:m.addCursor-1] + m.addKey[m.addCursor:]
				m.addCursor--
			}
		} else {
			if m.addCursor > 0 {
				m.addValue = m.addValue[:m.addCursor-1] + m.addValue[m.addCursor:]
				m.addCursor--
			}
		}
	case "left":
		if m.addCursor > 0 {
			m.addCursor--
		}
	case "right":
		limit := len(m.addKey)
		if m.addStep == 1 {
			limit = len(m.addValue)
		}
		if m.addCursor < limit {
			m.addCursor++
		}
	case "ctrl+v":
		if text, err := clipboard.ReadAll(); err == nil {
			if m.addStep == 0 {
				m.addKey, m.addCursor = insertAtCursor(m.addKey, m.addCursor, text)
			} else {
				m.addValue, m.addCursor = insertAtCursor(m.addValue, m.addCursor, text)
			}
		}
	default:
		s := msg.String()
		if len(s) == 1 || s == " " {
			if m.addStep == 0 {
				m.addKey = m.addKey[:m.addCursor] + s + m.addKey[m.addCursor:]
			} else {
				m.addValue = m.addValue[:m.addCursor] + s + m.addValue[m.addCursor:]
			}
			m.addCursor++
		}
	}
	return m, nil
}

func (m DetailModel) updateConfirmSave(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	switch msg.String() {
	case "y":
		m.confirmSave = false
		ns := m.namespace
		sec := m.secret
		rows := make([]Row, len(m.rows))
		copy(rows, m.rows)
		return m, func() tea.Msg {
			applied := 0
			for _, r := range rows {
				var err error
				switch r.Kind {
				case ChangeDeleted:
					err = kubectl.DeleteSecretKey(ns, sec, r.Key)
				case ChangeModified:
					err = kubectl.PatchSecret(ns, sec, r.Key, r.Current)
				case ChangeAdded:
					err = kubectl.PatchSecret(ns, sec, r.Key, r.Current)
				default:
					continue
				}
				if err != nil {
					return saveResultMsg{err: fmt.Errorf("key %q: %w", r.Key, err), applied: applied}
				}
				applied++
			}
			return saveResultMsg{applied: applied}
		}
	case "n", "esc":
		m.confirmSave = false
	}
	return m, nil
}

func (m DetailModel) updateConfirmDiscard(msg tea.KeyMsg) (DetailModel, tea.Cmd) {
	switch msg.String() {
	case "y":
		m.confirmDiscard = false
		// Reset all changes
		var kept []Row
		for _, r := range m.rows {
			switch r.Kind {
			case ChangeAdded:
				continue // remove added rows
			default:
				r.Kind = ChangeNone
				r.Current = r.Original
				kept = append(kept, r)
			}
		}
		m.rows = kept
		if m.cursor >= len(m.rows) && m.cursor > 0 {
			m.cursor = len(m.rows) - 1
		}
		m.feedback = "All changes discarded"
		m.feedbackErr = false
		return m, clearFeedbackAfter(2 * time.Second)
	case "n", "esc":
		m.confirmDiscard = false
	}
	return m, nil
}

func (m DetailModel) View(width, height int) string {
	if m.loading {
		return DimStyle.Render("  Loading secret data...")
	}
	if m.err != nil {
		return ErrorStyle.Render("  Error: " + m.err.Error())
	}

	var b strings.Builder

	// Title line
	vis := m.visibleIndices()

	var added, modified, deleted int
	for _, r := range m.rows {
		switch r.Kind {
		case ChangeAdded:
			added++
		case ChangeModified:
			modified++
		case ChangeDeleted:
			deleted++
		}
	}

	title := fmt.Sprintf("  Secret Data (%d keys", len(m.rows))
	if m.filter != "" {
		title += fmt.Sprintf(", %d matching", len(vis))
	}
	title += ")"
	b.WriteString(DimStyle.Render(title))

	// Diff counts as separate styled badges after the title
	if added > 0 || modified > 0 || deleted > 0 {
		b.WriteString("  ")
		if added > 0 {
			b.WriteString(DiffAddStyle.Render(fmt.Sprintf("+%d added", added)))
			b.WriteString("  ")
		}
		if modified > 0 {
			b.WriteString(DiffModStyle.Render(fmt.Sprintf("~%d modified", modified)))
			b.WriteString("  ")
		}
		if deleted > 0 {
			b.WriteString(DiffDelStyle.Render(fmt.Sprintf("-%d deleted", deleted)))
		}
	}
	b.WriteString("\n")

	// Filter bar
	if m.filtering {
		b.WriteString(FilterStyle.Render(fmt.Sprintf("  / %s_", m.filter)) + "\n")
	} else if m.filter != "" {
		b.WriteString(FilterStyle.Render(fmt.Sprintf("  filter: %s", m.filter)) + "\n")
	} else {
		b.WriteString("\n")
	}

	// Calculate visible area
	extraLines := 0
	if m.adding {
		extraLines += 3
	}
	if m.confirmSave || m.confirmDiscard {
		extraLines += 2
	}
	if m.feedback != "" {
		extraLines += 2
	}
	listHeight := height - 4 - extraLines
	if listHeight < 1 {
		listHeight = 1
	}

	// Scroll window over visible (filtered) rows
	visStart := 0
	if m.cursor >= visStart+listHeight {
		visStart = m.cursor - listHeight + 1
	}

	for vi := visStart; vi < len(vis) && vi < visStart+listHeight; vi++ {
		ri := vis[vi]
		r := m.rows[ri]
		isCursor := vi == m.cursor

		if m.editing && ri == m.editIdx {
			b.WriteString(m.renderEditRow(r, isCursor))
		} else {
			b.WriteString(m.renderRow(r, isCursor, width))
		}
		b.WriteString("\n")
	}

	if len(vis) == 0 && !m.adding {
		if m.filter != "" {
			b.WriteString(DimStyle.Render("  No keys match filter"))
		} else {
			b.WriteString(DimStyle.Render("  No data in this secret"))
		}
	}

	// Add form
	if m.adding {
		b.WriteString("\n")
		if m.addStep == 0 {
			before := m.addKey[:m.addCursor]
			after := m.addKey[m.addCursor:]
			b.WriteString(EditingStyle.Render("  Key:   ") + EditingStyle.Render(before) + EditingStyle.Render("_") + EditingStyle.Render(after))
		} else {
			b.WriteString(DimStyle.Render("  Key:   ") + NormalStyle.Render(m.addKey) + "\n")
			before := m.addValue[:m.addCursor]
			after := m.addValue[m.addCursor:]
			b.WriteString(EditingStyle.Render("  Value: ") + EditingStyle.Render(before) + EditingStyle.Render("_") + EditingStyle.Render(after))
		}
		b.WriteString("\n")
	}

	// Confirmations
	total := added + modified + deleted
	if m.confirmSave {
		b.WriteString("\n")
		b.WriteString(DiffModStyle.Render(fmt.Sprintf("  Apply %d changes? (y/n)", total)))
		b.WriteString("\n")
	}
	if m.confirmDiscard {
		b.WriteString("\n")
		b.WriteString(ErrorStyle.Render(fmt.Sprintf("  Discard %d changes? (y/n)", total)))
		b.WriteString("\n")
	}

	// Feedback
	if m.feedback != "" {
		b.WriteString("\n")
		if m.feedbackErr {
			b.WriteString(ErrorStyle.Render("  " + m.feedback))
		} else {
			b.WriteString(SuccessStyle.Render("  " + m.feedback))
		}
	}

	return b.String()
}

func (m DetailModel) renderRow(r Row, isCursor bool, width int) string {
	maxValWidth := width - 40
	if maxValWidth < 10 {
		maxValWidth = 10
	}

	truncate := func(s string) string {
		if len(s) > maxValWidth {
			return s[:maxValWidth-3] + "..."
		}
		return s
	}

	pointer := "    "
	if isCursor {
		pointer = "  > "
	}

	switch r.Kind {
	case ChangeAdded:
		line := fmt.Sprintf("+ %-28s %s", r.Key, truncate(r.Current))
		if isCursor {
			return DiffAddStyle.Bold(true).Render(pointer+line)
		}
		return DiffAddStyle.Render(pointer + line)

	case ChangeDeleted:
		line := fmt.Sprintf("- %-28s %s", r.Key, truncate(r.Original))
		if isCursor {
			return DiffDelStyle.Bold(true).Render(pointer+line)
		}
		return DiffDelStyle.Render(pointer + line)

	case ChangeModified:
		line := fmt.Sprintf("~ %-28s %s → %s", r.Key, truncate(r.Original), truncate(r.Current))
		if isCursor {
			return DiffModStyle.Bold(true).Render(pointer+line)
		}
		return DiffModStyle.Render(pointer + line)

	default:
		key := LabelStyle.Render(r.Key)
		val := truncate(r.Current)
		if isCursor {
			return SelectedStyle.Render(pointer) + key + " " + NormalStyle.Render(val)
		}
		return pointer + key + " " + DimStyle.Render(val)
	}
}

func (m DetailModel) renderEditRow(r Row, isCursor bool) string {
	pointer := "    "
	if isCursor {
		pointer = "  > "
	}

	before := m.editValue[:m.editCursor]
	after := m.editValue[m.editCursor:]
	cursor := EditingStyle.Render("_")
	val := EditingStyle.Render(before) + cursor + EditingStyle.Render(after)

	key := LabelStyle.Render(r.Key)
	return SelectedStyle.Render(pointer) + key + " " + val
}

func pasteHint() string {
	if runtime.GOOS == "darwin" {
		return "cmd+v: paste"
	}
	return "ctrl+v: paste"
}

func (m DetailModel) KeyHints() []string {
	if m.editing {
		return []string{"enter: stage edit", "esc: cancel", pasteHint(), "ctrl+a/e: home/end", "ctrl+k: kill line"}
	}
	if m.adding {
		if m.addStep == 0 {
			return []string{"enter: next", "esc: cancel", pasteHint()}
		}
		return []string{"enter: stage add", "esc: cancel", pasteHint()}
	}
	if m.filtering {
		return []string{"enter: confirm", "esc: clear filter"}
	}
	if m.confirmSave {
		return []string{"y: apply", "n: cancel"}
	}
	if m.confirmDiscard {
		return []string{"y: discard all", "n: cancel"}
	}

	hints := []string{"j/k: navigate", "/: search", "e: edit", "a: add", "d: delete"}
	if m.stagedCount() > 0 {
		hints = append(hints, "u: undo", "s: save", "ctrl+z: discard all")
	}
	if m.filter != "" {
		hints = append(hints, "esc: clear filter")
	} else {
		hints = append(hints, "esc: back")
	}
	hints = append(hints, "q: quit")
	return hints
}
