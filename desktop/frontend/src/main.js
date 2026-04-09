// State
let state = {
  context: '',
  namespaces: [],
  selectedNs: null,
  secrets: [],
  selectedSecret: null,
  kvData: [],      // original from cluster
  kvChanges: {},   // key -> { action: 'modify'|'delete'|'add', value: string }
  newKeys: [],     // [{ key, value }]
};

// DOM refs
const $ = (id) => document.getElementById(id);
const breadcrumb = $('breadcrumb');
const contextEl = $('context-name');
const nsList = $('ns-list');
const nsSearch = $('ns-search');
const secretsView = $('secrets-view');
const detailView = $('detail-view');
const secretsTitle = $('secrets-title');
const secretsBody = $('secrets-body');
const secretSearch = $('secret-search');
const detailTitle = $('detail-title');
const kvList = $('kv-list');
const btnBack = $('btn-back');
const btnAddKey = $('btn-add-key');
const btnSave = $('btn-save');
const btnDiscard = $('btn-discard');
const toast = $('toast');
const modalOverlay = $('modal-overlay');
const modalTitle = $('modal-title');
const modalKeyLabel = $('modal-key-label');
const modalKeyInput = $('modal-key-input');
const modalValueInput = $('modal-value-input');
const modalCancel = $('modal-cancel');
const modalConfirm = $('modal-confirm');

// Modal state
let modalCallback = null;

// ------- Wails backend calls -------
async function callBackend(method, ...args) {
  try {
    return await window.go.desktop.App[method](...args);
  } catch (err) {
    showToast(String(err), true);
    throw err;
  }
}

// ------- Init -------
async function init() {
  setupEvents();

  try {
    const ctx = await callBackend('GetCurrentContext');
    state.context = ctx;
    contextEl.textContent = ctx;
  } catch {
    contextEl.textContent = 'no context';
    showDisconnected('No kubectl context set. Run "kubectl config use-context &lt;name&gt;" to connect to a cluster.');
    return;
  }

  loadNamespaces();
}

function showDisconnected(message) {
  nsList.innerHTML = '';
  const content = document.querySelector('.content');
  secretsView.innerHTML = `
    <div class="disconnected">
      <div class="disconnected-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
          <line x1="12" y1="9" x2="12" y2="13"/>
          <line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
      </div>
      <h2 class="disconnected-title">Not Connected</h2>
      <p class="disconnected-msg">${message}</p>
      <button class="btn btn-primary" id="btn-retry">Retry Connection</button>
    </div>
  `;
  document.getElementById('btn-retry').addEventListener('click', () => {
    secretsView.innerHTML = `
      <div class="panel-header">
        <h2 id="secrets-title">Select a namespace</h2>
        <input type="text" id="secret-search" placeholder="Filter..." autocomplete="off" />
      </div>
      <div class="table-wrap">
        <table id="secrets-table">
          <thead><tr><th>Name</th><th>Type</th><th>Age</th></tr></thead>
          <tbody id="secrets-body"></tbody>
        </table>
      </div>
    `;
    // Re-bind refs that were replaced
    init();
  });
}

// ------- Namespaces -------
async function loadNamespaces() {
  nsList.innerHTML = '<div class="loading"><div class="spinner"></div>Loading namespaces...</div>';
  try {
    state.namespaces = await callBackend('GetNamespaces');
    renderNamespaces();
  } catch (err) {
    const msg = String(err);
    if (msg.includes('connection refused') || msg.includes('connect:') || msg.includes('Unable to connect')) {
      showDisconnected('Cannot reach the cluster. Is it running and is your kubeconfig correct?');
    } else if (msg.includes('unauthorized') || msg.includes('Unauthorized')) {
      showDisconnected('Cluster credentials expired or invalid. Re-authenticate and try again.');
    } else {
      nsList.innerHTML = `
        <div class="empty-state" style="padding:20px;">
          <div class="disconnected-icon" style="font-size:24px;opacity:0.4;">!</div>
          <span style="color:var(--red);font-size:12px;text-align:center;padding:0 12px;">${escapeHtml(msg)}</span>
          <button class="btn btn-ghost" style="margin-top:12px;" onclick="loadNamespaces()">Retry</button>
        </div>
      `;
    }
  }
}

function renderNamespaces() {
  const filter = nsSearch.value.toLowerCase();
  const filtered = state.namespaces.filter(ns =>
    ns.name.toLowerCase().includes(filter)
  );

  if (filtered.length === 0) {
    nsList.innerHTML = '<div class="empty-state"><span>No namespaces found</span></div>';
    return;
  }

  nsList.innerHTML = filtered.map(ns => `
    <div class="list-item ${state.selectedNs === ns.name ? 'active' : ''}"
         data-ns="${ns.name}">
      <span class="name">${ns.name}</span>
      <span class="badge ${ns.status === 'Active' ? 'active-status' : ''}">${ns.status}</span>
    </div>
  `).join('');

  nsList.querySelectorAll('.list-item').forEach(el => {
    el.addEventListener('click', () => selectNamespace(el.dataset.ns));
  });
}

async function selectNamespace(name) {
  state.selectedNs = name;
  state.selectedSecret = null;
  clearChanges();
  renderNamespaces();
  updateBreadcrumb();
  showSecretsView();
  await loadSecrets(name);
}

// ------- Secrets -------
async function loadSecrets(namespace) {
  secretsTitle.textContent = `Secrets`;
  secretsBody.innerHTML = '<tr><td colspan="3"><div class="loading"><div class="spinner"></div>Loading...</div></td></tr>';

  try {
    state.secrets = await callBackend('GetSecrets', namespace);
    renderSecrets();
  } catch {
    secretsBody.innerHTML = '<tr><td colspan="3">Failed to load secrets</td></tr>';
  }
}

function renderSecrets() {
  const filter = secretSearch.value.toLowerCase();
  const filtered = state.secrets.filter(s =>
    s.name.toLowerCase().includes(filter) ||
    s.type.toLowerCase().includes(filter)
  );

  secretsTitle.innerHTML = `Secrets <span class="count">(${filtered.length})</span>`;

  if (filtered.length === 0) {
    secretsBody.innerHTML = '<tr><td colspan="3" style="color:var(--text-muted);padding:20px;">No secrets found</td></tr>';
    return;
  }

  secretsBody.innerHTML = filtered.map(s => `
    <tr data-secret="${s.name}">
      <td>${s.name}</td>
      <td>${s.type}</td>
      <td>${s.age}</td>
    </tr>
  `).join('');

  secretsBody.querySelectorAll('tr').forEach(el => {
    el.addEventListener('click', () => selectSecret(el.dataset.secret));
  });
}

async function selectSecret(name) {
  state.selectedSecret = name;
  clearChanges();
  updateBreadcrumb();
  showDetailView();
  await loadSecretData(name);
}

// ------- Detail -------
async function loadSecretData(name) {
  detailTitle.textContent = name;
  kvList.innerHTML = '<div class="loading"><div class="spinner"></div>Loading secret data...</div>';

  try {
    state.kvData = await callBackend('GetSecretData', state.selectedNs, name);
    state.kvData.sort((a, b) => a.key.localeCompare(b.key));
    renderKvList();
  } catch {
    kvList.innerHTML = '<div class="loading">Failed to load</div>';
  }
}

function renderKvList() {
  const allRows = [];

  // Original keys
  for (const kv of state.kvData) {
    const change = state.kvChanges[kv.key];
    if (change && change.action === 'delete') {
      allRows.push({ key: kv.key, value: kv.value, status: 'deleted' });
    } else if (change && change.action === 'modify') {
      allRows.push({ key: kv.key, value: change.value, originalValue: kv.value, status: 'modified' });
    } else {
      allRows.push({ key: kv.key, value: kv.value, status: 'none' });
    }
  }

  // New keys
  for (const nk of state.newKeys) {
    allRows.push({ key: nk.key, value: nk.value, status: 'added', isNew: true });
  }

  if (allRows.length === 0) {
    kvList.innerHTML = '<div class="empty-state"><div class="icon">~</div><span>No data in this secret</span></div>';
    updateSaveButtons();
    return;
  }

  kvList.innerHTML = allRows.map((row, idx) => {
    const statusClass = row.status !== 'none' ? row.status : '';
    let badge = '';
    if (row.status === 'modified') badge = '<span class="change-badge modified">modified</span>';
    if (row.status === 'added') badge = '<span class="change-badge added">new</span>';
    if (row.status === 'deleted') badge = '<span class="change-badge deleted">deleted</span>';

    const displayValue = row.status === 'deleted' ? row.value : row.value;

    return `
      <div class="kv-row ${statusClass}" data-key="${row.key}" data-idx="${idx}" data-new="${row.isNew || false}">
        <div class="kv-key">${escapeHtml(row.key)}${badge}</div>
        <div class="kv-value">${escapeHtml(displayValue)}</div>
        <div class="kv-actions">
          ${row.status === 'deleted' ? `
            <button class="btn-edit" data-action="undo" data-key="${escapeAttr(row.key)}">undo</button>
          ` : `
            <button class="btn-edit" data-action="edit" data-key="${escapeAttr(row.key)}" data-new="${row.isNew || false}">edit</button>
            <button class="btn-danger" data-action="delete" data-key="${escapeAttr(row.key)}" data-new="${row.isNew || false}">delete</button>
          `}
        </div>
      </div>
    `;
  }).join('');

  // Wire up action buttons
  kvList.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const action = btn.dataset.action;
      const key = btn.dataset.key;
      const isNew = btn.dataset.new === 'true';

      if (action === 'edit') {
        openEditModal(key, isNew);
      } else if (action === 'delete') {
        handleDelete(key, isNew);
      } else if (action === 'undo') {
        handleUndo(key);
      }
    });
  });

  updateSaveButtons();
}

// ------- Change tracking -------
function hasChanges() {
  return Object.keys(state.kvChanges).length > 0 || state.newKeys.length > 0;
}

function clearChanges() {
  state.kvChanges = {};
  state.newKeys = [];
  updateSaveButtons();
}

function updateSaveButtons() {
  const changed = hasChanges();
  btnSave.classList.toggle('hidden', !changed);
  btnDiscard.classList.toggle('hidden', !changed);
}

function handleDelete(key, isNew) {
  if (isNew) {
    state.newKeys = state.newKeys.filter(nk => nk.key !== key);
  } else {
    state.kvChanges[key] = { action: 'delete' };
  }
  renderKvList();
}

function handleUndo(key) {
  delete state.kvChanges[key];
  renderKvList();
}

// ------- Modal -------
function openEditModal(key, isNew) {
  let currentValue = '';
  if (isNew) {
    const nk = state.newKeys.find(n => n.key === key);
    currentValue = nk ? nk.value : '';
  } else {
    const change = state.kvChanges[key];
    if (change && change.action === 'modify') {
      currentValue = change.value;
    } else {
      const kv = state.kvData.find(k => k.key === key);
      currentValue = kv ? kv.value : '';
    }
  }

  modalTitle.textContent = `Edit: ${key}`;
  modalKeyLabel.classList.add('hidden');
  modalKeyInput.classList.add('hidden');
  modalValueInput.value = currentValue;
  modalOverlay.classList.remove('hidden');
  modalValueInput.focus();

  modalCallback = (value) => {
    if (isNew) {
      const nk = state.newKeys.find(n => n.key === key);
      if (nk) nk.value = value;
    } else {
      const original = state.kvData.find(k => k.key === key);
      if (original && original.value === value) {
        delete state.kvChanges[key];
      } else {
        state.kvChanges[key] = { action: 'modify', value };
      }
    }
    renderKvList();
  };
}

function openAddModal() {
  modalTitle.textContent = 'Add Key';
  modalKeyLabel.classList.remove('hidden');
  modalKeyInput.classList.remove('hidden');
  modalKeyInput.value = '';
  modalValueInput.value = '';
  modalOverlay.classList.remove('hidden');
  modalKeyInput.focus();

  modalCallback = (value) => {
    const key = modalKeyInput.value.trim();
    if (!key) return;

    // Check for duplicate
    const exists = state.kvData.some(kv => kv.key === key) ||
                   state.newKeys.some(nk => nk.key === key);
    if (exists) {
      showToast(`Key "${key}" already exists`, true);
      return;
    }

    state.newKeys.push({ key, value });
    renderKvList();
  };
}

function closeModal() {
  modalOverlay.classList.add('hidden');
  modalCallback = null;
}

// ------- Save -------
async function saveChanges() {
  const ops = [];

  for (const [key, change] of Object.entries(state.kvChanges)) {
    if (change.action === 'delete') {
      ops.push({ type: 'delete', key });
    } else if (change.action === 'modify') {
      ops.push({ type: 'update', key, value: change.value });
    }
  }

  for (const nk of state.newKeys) {
    ops.push({ type: 'update', key: nk.key, value: nk.value });
  }

  if (ops.length === 0) return;

  let applied = 0;
  for (const op of ops) {
    try {
      if (op.type === 'delete') {
        await callBackend('DeleteSecretKey', state.selectedNs, state.selectedSecret, op.key);
      } else {
        await callBackend('UpdateSecretKey', state.selectedNs, state.selectedSecret, op.key, op.value);
      }
      applied++;
    } catch (err) {
      showToast(`Failed after ${applied} changes: ${err}`, true);
      clearChanges();
      await loadSecretData(state.selectedSecret);
      return;
    }
  }

  showToast(`Applied ${applied} change${applied !== 1 ? 's' : ''} successfully`);
  clearChanges();
  await loadSecretData(state.selectedSecret);
}

function discardChanges() {
  clearChanges();
  renderKvList();
  showToast('Changes discarded');
}

// ------- Views -------
function showSecretsView() {
  secretsView.classList.remove('hidden');
  detailView.classList.add('hidden');
}

function showDetailView() {
  secretsView.classList.add('hidden');
  detailView.classList.remove('hidden');
}

function goBack() {
  if (hasChanges()) {
    if (!confirm('You have unsaved changes. Discard?')) return;
  }
  state.selectedSecret = null;
  clearChanges();
  updateBreadcrumb();
  showSecretsView();
}

// ------- Breadcrumb -------
function updateBreadcrumb() {
  const parts = [];
  if (state.selectedNs) {
    parts.push(`<span class="crumb">${state.selectedNs}</span>`);
  }
  if (state.selectedSecret) {
    parts.push(`<span class="crumb">${state.selectedSecret}</span>`);
  }

  if (parts.length === 0) {
    breadcrumb.innerHTML = '<span class="crumb">k8secret</span>';
  } else {
    breadcrumb.innerHTML = '<span class="crumb">k8secret</span>' +
      parts.map(p => `<span class="sep">/</span>${p}`).join('');
  }
}

// ------- Toast -------
let toastTimer = null;
function showToast(message, isError = false) {
  toast.textContent = message;
  toast.className = `toast ${isError ? 'error' : 'success'}`;
  toast.classList.remove('hidden');

  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.add('hidden');
  }, 3000);
}

// ------- Helpers -------
function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function escapeAttr(str) {
  return str.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

// ------- Events -------
function setupEvents() {
  nsSearch.addEventListener('input', renderNamespaces);
  secretSearch.addEventListener('input', renderSecrets);
  btnBack.addEventListener('click', goBack);
  btnAddKey.addEventListener('click', openAddModal);
  btnSave.addEventListener('click', saveChanges);
  btnDiscard.addEventListener('click', discardChanges);

  modalCancel.addEventListener('click', closeModal);
  modalConfirm.addEventListener('click', () => {
    if (modalCallback) {
      modalCallback(modalValueInput.value);
    }
    closeModal();
  });

  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) closeModal();
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (!modalOverlay.classList.contains('hidden')) {
        closeModal();
      }
    }
  });
}

// ------- Boot -------
updateBreadcrumb();

if (window.go) {
  init();
} else {
  // Wait for Wails runtime
  document.addEventListener('DOMContentLoaded', () => {
    if (window.go) {
      init();
    } else {
      // Wails v2 fires wails:loaded
      window.addEventListener('wails:loaded', init);
      // Fallback: poll briefly
      let tries = 0;
      const poll = setInterval(() => {
        if (window.go || tries > 50) {
          clearInterval(poll);
          if (window.go) init();
        }
        tries++;
      }, 100);
    }
  });
}
