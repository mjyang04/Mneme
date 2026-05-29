const state = {
  mode: "search",
  status: null,
  activity: null,
  desktop: window.mnemeDesktop ?? null
};

const elements = {
  tabs: [...document.querySelectorAll(".tab")],
  views: [...document.querySelectorAll(".view")],
  segments: [...document.querySelectorAll(".segment")],
  commandInput: document.querySelector("#commandInput"),
  askButton: document.querySelector("#askButton"),
  results: document.querySelector("#results"),
  answerPanel: document.querySelector("#answerPanel"),
  sourceKind: document.querySelector("#sourceKind"),
  sourcePath: document.querySelector("#sourcePath"),
  browseSource: document.querySelector("#browseSource"),
  addSource: document.querySelector("#addSource"),
  sourceList: document.querySelector("#sourceList"),
  rebuildIndex: document.querySelector("#rebuildIndex"),
  indexState: document.querySelector("#indexState"),
  sourceCount: document.querySelector("#sourceCount"),
  chunkCount: document.querySelector("#chunkCount"),
  transcriptTitle: document.querySelector("#transcriptTitle"),
  transcriptText: document.querySelector("#transcriptText"),
  importTranscript: document.querySelector("#importTranscript"),
  transcriptList: document.querySelector("#transcriptList"),
  refreshActivity: document.querySelector("#refreshActivity"),
  activityList: document.querySelector("#activityList"),
  hotkeyInput: document.querySelector("#hotkeyInput"),
  askTopK: document.querySelector("#askTopK"),
  dataDir: document.querySelector("#dataDir"),
  saveSettings: document.querySelector("#saveSettings"),
  capabilities: document.querySelector("#capabilities"),
  toast: document.querySelector("#toast")
};

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options.headers ?? {})
    }
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || `Request failed: ${response.status}`);
  }
  return payload;
}

function activateView(name) {
  for (const tab of elements.tabs) {
    tab.classList.toggle("active", tab.dataset.view === name);
  }
  for (const view of elements.views) {
    view.classList.toggle("active", view.id === `view-${name}`);
  }
}

function setMode(mode) {
  state.mode = mode;
  for (const segment of elements.segments) {
    segment.classList.toggle("active", segment.dataset.mode === mode);
  }
  if (mode === "ask") {
    elements.askButton.textContent = "Ask";
  } else {
    elements.askButton.textContent = "Search";
  }
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.add("visible");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => {
    elements.toast.classList.remove("visible");
  }, 2600);
}

async function refreshStatus() {
  state.status = await api("/api/status");
  const { sources, transcripts, index, settings, capabilities, dataDir } = state.status;
  elements.indexState.textContent = index.builtAt
    ? `Index ${new Date(index.builtAt).toLocaleTimeString()}`
    : "Index not built";
  elements.sourceCount.textContent = `${sources.length} source${sources.length === 1 ? "" : "s"}`;
  elements.chunkCount.textContent = `${index.chunks} chunk${index.chunks === 1 ? "" : "s"}`;
  elements.hotkeyInput.value = settings.quickSearchHotkey;
  elements.askTopK.value = settings.askTopK;
  elements.dataDir.value = dataDir;
  renderSources(sources);
  renderTranscripts(transcripts);
  elements.capabilities.innerHTML = capabilities
    .map((capability) => `<span class="capability">${escapeHtml(capability)}</span>`)
    .join("");
}

function renderSources(sources) {
  if (!sources.length) {
    elements.sourceList.innerHTML = emptyRow("No sources registered.");
    return;
  }
  elements.sourceList.innerHTML = sources.map((source) => `
    <div class="table-row">
      <div>
        <div class="row-title">${escapeHtml(source.path)}</div>
        <div class="row-meta">${escapeHtml(source.kind)} · added ${formatDate(source.addedAt)}</div>
      </div>
      <div class="row-actions">
        <button class="link-button" data-open-path="${escapeHtml(source.path)}">Open</button>
        <button class="danger-button" data-delete-source="${escapeHtml(source.id)}">Remove</button>
      </div>
    </div>
  `).join("");
}

function renderTranscripts(transcripts) {
  if (!transcripts.length) {
    elements.transcriptList.innerHTML = emptyRow("No transcripts imported.");
    return;
  }
  elements.transcriptList.innerHTML = transcripts.map((transcript) => `
    <div class="table-row">
      <div>
        <div class="row-title">${escapeHtml(transcript.title)}</div>
        <div class="row-meta">${formatDate(transcript.createdAt)} · ${wordCount(transcript.text)} words</div>
      </div>
      <span class="kind-chip">Text</span>
    </div>
  `).join("");
}

function renderResults(hits) {
  elements.answerPanel.classList.add("hidden");
  if (!hits.length) {
    elements.results.innerHTML = emptyRow("No local matches.");
    return;
  }
  elements.results.innerHTML = hits.map((hit) => `
    <article class="result-item">
      <div class="result-header">
        <div>
          <div class="result-title">${escapeHtml(hit.title)}</div>
          <div class="result-meta">${escapeHtml(hit.path || "")}${hit.locator ? ` · ${escapeHtml(hit.locator)}` : ""}</div>
        </div>
        <div>
          <span class="kind-chip">${escapeHtml(hit.kind)}</span>
          <span class="score-chip">${hit.score}</span>
        </div>
      </div>
      <p class="snippet">${escapeHtml(hit.snippet)}</p>
      ${hit.path ? `<div class="row-actions"><button class="link-button" data-open-path="${escapeHtml(hit.path)}">Open source</button><button class="link-button" data-show-path="${escapeHtml(hit.path)}">Show in folder</button></div>` : ""}
    </article>
  `).join("");
}

function renderAnswer(answer) {
  elements.answerPanel.classList.remove("hidden");
  elements.answerPanel.innerHTML = `
    <div class="result-title">Answer</div>
    <p class="snippet">${escapeHtml(answer.answer)}</p>
    <div class="result-meta">
      ${answer.citations.map((citation) => `[${citation.number}] ${escapeHtml(citation.title)} · ${escapeHtml(citation.path || "")}`).join("<br>")}
    </div>
  `;
}

function renderActivity(activity) {
  if (!activity.projects.length) {
    elements.activityList.innerHTML = emptyRow("No source activity available.");
    return;
  }
  elements.activityList.innerHTML = activity.projects.map((project) => `
    <section class="activity-project">
      <h2>${escapeHtml(project.name)}</h2>
      <div class="row-meta">${escapeHtml(project.root)}</div>
      <div class="activity-grid">
        <div>
          <strong>Recent files</strong>
          <ul>
            ${project.recentFiles.slice(0, 8).map((file) => `<li>${escapeHtml(file.relativePath)} · ${formatDate(file.modifiedAt)}</li>`).join("")}
          </ul>
        </div>
        <div>
          <strong>Git commits</strong>
          <ul>
            ${project.commits.slice(0, 5).map((commit) => `<li>${escapeHtml(commit.hash)} ${escapeHtml(commit.message)}</li>`).join("") || "<li>No git commits found.</li>"}
          </ul>
        </div>
      </div>
    </section>
  `).join("");
}

async function performSearch() {
  const query = elements.commandInput.value.trim();
  if (!query) {
    elements.results.innerHTML = emptyRow("Enter a local search query.");
    return;
  }
  if (state.mode === "ask") {
    const answer = await api(`/api/answer?q=${encodeURIComponent(query)}`);
    renderAnswer(answer);
    const results = await api(`/api/search?q=${encodeURIComponent(query)}`);
    renderResults(results.hits);
    renderAnswer(answer);
  } else {
    const results = await api(`/api/search?q=${encodeURIComponent(query)}`);
    renderResults(results.hits);
  }
}

async function addSource() {
  const path = elements.sourcePath.value.trim();
  if (!path) {
    showToast("Enter a source folder path.");
    return;
  }
  await api("/api/sources", {
    method: "POST",
    body: JSON.stringify({
      kind: elements.sourceKind.value,
      path
    })
  });
  elements.sourcePath.value = "";
  await refreshStatus();
  showToast("Source added.");
}

async function browseSource() {
  if (!state.desktop?.selectSourceFolder) {
    showToast("Folder picker is available in the Windows desktop app.");
    return;
  }
  const selectedPath = await state.desktop.selectSourceFolder();
  if (selectedPath) {
    elements.sourcePath.value = selectedPath;
  }
}

async function rebuildIndex() {
  elements.indexState.textContent = "Indexing...";
  const stats = await api("/api/index/rebuild", { method: "POST", body: "{}" });
  await refreshStatus();
  showToast(`Indexed ${stats.documents} documents, skipped ${stats.skipped}.`);
}

async function importTranscript() {
  const title = elements.transcriptTitle.value.trim();
  const text = elements.transcriptText.value.trim();
  if (!text) {
    showToast("Paste transcript text first.");
    return;
  }
  await api("/api/transcripts/import-text", {
    method: "POST",
    body: JSON.stringify({ title, text })
  });
  elements.transcriptTitle.value = "";
  elements.transcriptText.value = "";
  await refreshStatus();
  showToast("Transcript imported.");
}

async function refreshActivity() {
  state.activity = await api("/api/activity");
  renderActivity(state.activity);
}

async function saveSettings() {
  await api("/api/settings", {
    method: "POST",
    body: JSON.stringify({
      quickSearchHotkey: elements.hotkeyInput.value,
      askTopK: Number(elements.askTopK.value)
    })
  });
  await refreshStatus();
  showToast("Settings saved.");
}

async function openNativePath(targetPath) {
  if (!state.desktop?.openPath) {
    showToast("Opening files is available in the Windows desktop app.");
    return;
  }
  const result = await state.desktop.openPath(targetPath);
  if (!result?.ok) {
    showToast(result?.error || "Could not open path.");
  }
}

async function showNativePath(targetPath) {
  if (!state.desktop?.showItemInFolder) {
    showToast("Showing files is available in the Windows desktop app.");
    return;
  }
  const result = await state.desktop.showItemInFolder(targetPath);
  if (!result?.ok) {
    showToast(result?.error || "Could not show path.");
  }
}

elements.tabs.forEach((tab) => {
  tab.addEventListener("click", () => activateView(tab.dataset.view));
});

elements.segments.forEach((segment) => {
  segment.addEventListener("click", () => setMode(segment.dataset.mode));
});

elements.askButton.addEventListener("click", () => {
  performSearch().catch((error) => showToast(error.message));
});

elements.commandInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    performSearch().catch((error) => showToast(error.message));
  }
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    elements.commandInput.select();
  }
});

window.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    elements.commandInput.focus();
    elements.commandInput.select();
  }
});

elements.addSource.addEventListener("click", () => {
  addSource().catch((error) => showToast(error.message));
});

elements.browseSource.addEventListener("click", () => {
  browseSource().catch((error) => showToast(error.message));
});

elements.sourceList.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-delete-source]");
  const openButton = event.target.closest("[data-open-path]");
  if (button) {
    await api(`/api/sources/${encodeURIComponent(button.dataset.deleteSource)}`, { method: "DELETE" });
    await refreshStatus();
    showToast("Source removed.");
  } else if (openButton) {
    await openNativePath(openButton.dataset.openPath);
  }
});

elements.results.addEventListener("click", async (event) => {
  const openButton = event.target.closest("[data-open-path]");
  const showButton = event.target.closest("[data-show-path]");
  if (openButton) {
    await openNativePath(openButton.dataset.openPath);
  } else if (showButton) {
    await showNativePath(showButton.dataset.showPath);
  }
});

elements.rebuildIndex.addEventListener("click", () => {
  rebuildIndex().catch((error) => showToast(error.message));
});

elements.importTranscript.addEventListener("click", () => {
  importTranscript().catch((error) => showToast(error.message));
});

elements.refreshActivity.addEventListener("click", () => {
  refreshActivity().catch((error) => showToast(error.message));
});

elements.saveSettings.addEventListener("click", () => {
  saveSettings().catch((error) => showToast(error.message));
});

if (state.desktop?.onTriggerRebuild) {
  state.desktop.onTriggerRebuild(() => {
    rebuildIndex().catch((error) => showToast(error.message));
  });
}

function emptyRow(message) {
  return `<div class="table-row"><div class="muted">${escapeHtml(message)}</div></div>`;
}

function wordCount(text) {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function formatDate(value) {
  if (!value) return "";
  return new Date(value).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

setMode("search");
refreshStatus()
  .then(() => refreshActivity())
  .catch((error) => showToast(error.message));
