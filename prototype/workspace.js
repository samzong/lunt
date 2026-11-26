(() => {
  const P = window.LuntProto;
  const { ICONS, state, escapeHtml, renderRowHtml } = P;

  function renderWorkspace() {
    const win = document.getElementById("surface-workspace");
    if (!win) return;
    win.hidden = state.surface !== "workspace";
    if (state.surface !== "workspace") return;

    document.querySelectorAll("[data-workspace-mode]").forEach(btn => {
      btn.setAttribute("aria-selected", String(btn.dataset.workspaceMode === state.workspaceMode));
    });

    const newBtn = document.getElementById("btn-workspace-new");
    const newLabel = document.getElementById("workspace-new-label");
    if (newBtn && newLabel) {
      const text = state.workspaceMode === "monitors" ? "New target" : "New query";
      newLabel.textContent = text;
      newBtn.setAttribute("aria-label", text);
    }

    const sideEl = document.getElementById("workspace-sidebar");
    const detailEl = document.getElementById("workspace-detail");

    if (state.workspaceMode === "monitors") {
      sideEl.innerHTML =
        '<div class="sidebar-label">Watched targets (' +
        state.monitors.length +
        ")</div>" +
        state.monitors
          .map(m => {
            const hasUnread = m.enabled && m.events.some(e => e.unread && m.toggles[e.kind] !== false);
            const dotCls = !m.enabled ? "side-dot" : hasUnread ? "side-dot attention" : "side-dot live";
            return (
              '<button type="button" class="side-row" data-select-monitor="' +
              escapeHtml(m.id) +
              '" aria-current="' +
              String(state.selectedMonitorId === m.id) +
              '">' +
              '<span class="side-row-left"><span class="' +
              dotCls +
              '" aria-hidden="true"></span><span class="side-row-title">' +
              escapeHtml(m.name) +
              "</span></span>" +
              '<span class="scope-count">' +
              m.events.length +
              "</span>" +
              "</button>"
            );
          })
          .join("");

      const current = state.monitors.find(m => m.id === state.selectedMonitorId) || state.monitors[0];
      if (!current) {
        detailEl.innerHTML =
          (state.drawerMode === "new-monitor" ? renderMonitorDrawerHtml() : "") +
          '<div class="calm-state"><p class="calm-title">No watched targets yet</p>' +
          '<p class="calm-sub">Add a repository or account target to track new changes.</p>' +
          '<button type="button" class="action-primary" id="btn-ws-empty-new">Add target</button></div>';
        document.getElementById("btn-ws-empty-new")?.addEventListener("click", () => {
          state.drawerMode = "new-monitor";
          state.drawerError = null;
          renderWorkspace();
        });
        return;
      }
      state.selectedMonitorId = current.id;

      const drawerHtml =
        state.drawerMode === "new-monitor"
          ? renderMonitorDrawerHtml()
          : "";

      const deleteConfirmHtml =
        state.confirmingDeleteId === current.id
          ? '<div class="error-banner"><span>Delete "' +
            escapeHtml(current.name) +
            '" and clear its local event history?</span>' +
            '<span class="detail-controls">' +
            '<button type="button" class="compact-action" id="btn-cancel-delete">Cancel</button>' +
            '<button type="button" class="action-primary" id="btn-confirm-delete">Confirm delete</button>' +
            "</span></div>"
          : "";

      const toggleDefs = [
        { key: "commit", label: "Commits" },
        { key: "pr", label: "Pull requests" },
        { key: "issue", label: "Issues" },
        { key: "release", label: "Releases" },
        { key: "comment", label: "Comments" }
      ];

      const matchedRows = current.events
        .filter(ev => current.toggles[ev.kind] !== false)
        .map((ev, i) =>
          renderRowHtml(
            {
              id: ev.id,
              kind: ev.kind,
              state: ev.state,
              repo: ev.repo,
              number: null,
              reason: ev.actor,
              ci: null,
              time: ev.time,
              unread: ev.unread,
              url: ev.url,
              title: ev.title
            },
            i,
            true
          )
        )
        .join("");

      detailEl.innerHTML =
        drawerHtml +
        deleteConfirmHtml +
        '<div class="detail-header">' +
        '<div class="detail-title-group">' +
        "<h2>" +
        escapeHtml(current.name) +
        "</h2>" +
        '<div class="detail-meta"><code>' +
        escapeHtml(current.type + ":" + current.target) +
        "</code><span>Last synced " +
        escapeHtml(current.lastSynced) +
        "</span></div>" +
        "</div>" +
        '<div class="detail-controls">' +
        '<button type="button" class="switch-btn" id="btn-toggle-mon-enabled" aria-pressed="' +
        String(current.enabled) +
        '">' +
        (current.enabled ? "Active" : "Paused") +
        "</button>" +
        '<button type="button" class="compact-action" id="btn-sync-single-mon">' +
        ICONS.sync +
        "<span>Sync now</span></button>" +
        '<button type="button" class="icon-btn" id="btn-ask-delete-mon" title="Delete target" aria-label="Delete target">' +
        ICONS.trash +
        "</button>" +
        "</div>" +
        "</div>" +
        '<div class="filter-chip-row" role="group" aria-label="Event notification filters">' +
        toggleDefs
          .map(
            t =>
              '<button type="button" class="scope-pill" data-mon-kind="' +
              t.key +
              '" aria-pressed="' +
              String(current.toggles[t.key] !== false) +
              '">' +
              t.label +
              "</button>"
          )
          .join("") +
        "</div>" +
        "<h3>Recent matched events</h3>" +
        '<div class="list-viewport">' +
        (matchedRows ||
          '<div class="calm-state"><p class="calm-sub">No events match the active event filters.</p></div>') +
        "</div>";
    } else {
      sideEl.innerHTML =
        '<div class="sidebar-label">Saved queries (' +
        state.savedSearches.length +
        ")</div>" +
        state.savedSearches
          .map(s => {
            const tags = [];
            if (s.pinned) tags.push("Work");
            if (s.watchAlerts) tags.push("Watch");
            const suffix = tags.length ? tags.join(" · ") + " · " + s.results.length : String(s.results.length);
            const dotCls = !s.enabled ? "side-dot" : s.watchAlerts ? "side-dot attention" : "side-dot live";
            return (
              '<button type="button" class="side-row" data-select-search="' +
              escapeHtml(s.id) +
              '" aria-current="' +
              String(state.selectedSearchId === s.id) +
              '">' +
              '<span class="side-row-left"><span class="' +
              dotCls +
              '" aria-hidden="true"></span><span class="side-row-title">' +
              escapeHtml(s.name) +
              "</span></span>" +
              '<span class="scope-count">' +
              escapeHtml(suffix) +
              "</span>" +
              "</button>"
            );
          })
          .join("");

      const current =
        state.savedSearches.find(s => s.id === state.selectedSearchId) || state.savedSearches[0];
      if (!current) {
        detailEl.innerHTML =
          (state.drawerMode === "new-search" ? renderSearchDrawerHtml() : "") +
          '<div class="calm-state"><p class="calm-title">No saved queries yet</p>' +
          '<p class="calm-sub">Create an Issue or Pull Request query to pin in Work or watch for changes.</p>' +
          '<button type="button" class="action-primary" id="btn-ws-empty-search">Add query</button></div>';
        document.getElementById("btn-ws-empty-search")?.addEventListener("click", () => {
          state.drawerMode = "new-search";
          state.drawerError = null;
          renderWorkspace();
        });
        return;
      }
      state.selectedSearchId = current.id;

      const drawerHtml =
        state.drawerMode === "new-search"
          ? renderSearchDrawerHtml()
          : "";

      const deleteConfirmHtml =
        state.confirmingDeleteId === current.id
          ? '<div class="error-banner"><span>Delete query "' +
            escapeHtml(current.name) +
            '" and remove its Work and Watch entries?</span>' +
            '<span class="detail-controls">' +
            '<button type="button" class="compact-action" id="btn-cancel-delete">Cancel</button>' +
            '<button type="button" class="action-primary" id="btn-confirm-delete-search">Confirm delete</button>' +
            "</span></div>"
          : "";

      const previewHtml = current.results
        .map((r, idx) => renderRowHtml(r, idx, false))
        .join("");

      detailEl.innerHTML =
        drawerHtml +
        deleteConfirmHtml +
        '<div class="detail-header">' +
        '<div class="detail-title-group">' +
        "<h2>" +
        escapeHtml(current.name) +
        "</h2>" +
        '<div class="detail-meta"><code>' +
        escapeHtml(current.query) +
        "</code><span>Last synced " +
        escapeHtml(current.lastSynced) +
        "</span></div>" +
        "</div>" +
        '<div class="detail-controls">' +
        '<button type="button" class="switch-btn" id="btn-toggle-search-pin" aria-pressed="' +
        String(current.pinned) +
        '">' +
        (current.pinned ? "Pinned in Work" : "Pin to Work") +
        "</button>" +
        '<button type="button" class="switch-btn" id="btn-toggle-search-watch" aria-pressed="' +
        String(current.watchAlerts) +
        '">' +
        (current.watchAlerts ? "Watch alerts: On" : "Watch alerts: Off") +
        "</button>" +
        '<button type="button" class="switch-btn" id="btn-toggle-search-enabled" aria-pressed="' +
        String(current.enabled) +
        '">' +
        (current.enabled ? "Enabled" : "Paused") +
        "</button>" +
        '<button type="button" class="icon-btn" id="btn-ask-delete-search" title="Delete query" aria-label="Delete query">' +
        ICONS.trash +
        "</button>" +
        "</div>" +
        "</div>" +
        (current.watchAlerts
          ? '<p class="note-sub">New matches since last sync appear in Watch and macOS banners.</p>'
          : '<p class="note-sub">Turn on Watch alerts to send new query matches to Watch without copying the query.</p>') +
        "<h3>Current query matches (" +
        current.results.length +
        ")</h3>" +
        '<div class="list-viewport">' +
        (previewHtml ||
          '<div class="calm-state"><p class="calm-sub">No current matches for this query.</p></div>') +
        "</div>";
    }
  }

  function renderMonitorDrawerHtml() {
    const presets = [
      { id: "valid-repo", label: "Repo: rust-lang/cargo", target: "rust-lang/cargo", type: "repository" },
      { id: "valid-user", label: "Account: @yyx990803", target: "yyx990803", type: "account" },
      { id: "invalid-repo", label: "Invalid: samzong/missing-404", target: "samzong/missing-404", type: "repository" }
    ];
    return (
      '<div class="inline-sheet" role="region" aria-label="Add watched target">' +
      '<div class="sheet-row"><strong>Add GitHub target</strong>' +
      '<div class="filter-chip-row">' +
      presets
        .map(
          p =>
            '<button type="button" class="scope-pill" data-drawer-preset="' +
            p.id +
            '" aria-pressed="' +
            String(state.drawerPreset === p.id) +
            '">' +
            p.label +
            "</button>"
        )
        .join("") +
      "</div></div>" +
      (state.drawerError
        ? '<div class="error-banner"><span>' + escapeHtml(state.drawerError) + "</span></div>"
        : "") +
      '<div class="sheet-row"><span class="note-sub">Lunt makes sure that the GitHub repository or account exists before saving.</span>' +
      '<span class="detail-controls">' +
      '<button type="button" class="compact-action" id="btn-drawer-cancel">Cancel</button>' +
      '<button type="button" class="action-primary" id="btn-drawer-save">Save target</button>' +
      "</span></div>" +
      "</div>"
    );
  }

  function renderSearchDrawerHtml() {
    const presets = [
      { id: "valid-swift", label: "Swift 6 PRs" },
      { id: "valid-bugs", label: "Assigned Bugs" },
      { id: "invalid-query", label: "Invalid: empty query" }
    ];
    return (
      '<div class="inline-sheet" role="region" aria-label="Add saved query">' +
      '<div class="sheet-row"><strong>Add saved query</strong>' +
      '<div class="filter-chip-row">' +
      presets
        .map(
          p =>
            '<button type="button" class="scope-pill" data-search-drawer-preset="' +
            p.id +
            '" aria-pressed="' +
            String(state.searchDrawerPreset === p.id) +
            '">' +
            p.label +
            "</button>"
        )
        .join("") +
      "</div></div>" +
      (state.drawerError
        ? '<div class="error-banner"><span>' + escapeHtml(state.drawerError) + "</span></div>"
        : "") +
      '<div class="sheet-row"><span class="note-sub">Saved queries filter Issues and Pull Requests in Work and optionally alert in Watch.</span>' +
      '<span class="detail-controls">' +
      '<button type="button" class="compact-action" id="btn-drawer-cancel">Cancel</button>' +
      '<button type="button" class="action-primary" id="btn-search-drawer-save">Save query</button>' +
      "</span></div>" +
      "</div>"
    );
  }


  P.renderWorkspace = renderWorkspace;
})();
