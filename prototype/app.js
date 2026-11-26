(() => {
  const P = window.LuntProto;
  const {
    state,
    clearBannerTimer,
    showPopoverStatus,
    showWindowStatus,
    renderWindowStatus,
    itemLabelForId,
    currentPopoverRows,
    markRowRead,
    markCurrentTabRead,
    triggerSync,
    simulateIncomingEvent
  } = P;

  function renderAll() {
    const stageRoot = document.getElementById("desktop-stage");
    if (stageRoot) stageRoot.dataset.stageSurface = state.surface;
    P.renderTopControls();
    P.renderMenuBar();
    P.renderBanner();
    renderWindowStatus();
    P.renderPopover();
    P.renderWorkspace();
    P.renderSettings();
    P.renderSpacingInspector();
  }

  P.renderAll = renderAll;

  document.querySelectorAll("[data-theme-mode]").forEach(button => {
    button.addEventListener("click", () => {
      const mode = button.dataset.themeMode;
      document.querySelectorAll("[data-theme-mode]").forEach(item => {
        item.setAttribute("aria-pressed", String(item === button));
      });
      if (mode === "light" || mode === "dark") {
        document.documentElement.dataset.theme = mode;
      } else {
        delete document.documentElement.dataset.theme;
      }
    });
  });

  document.addEventListener("click", event => {
    const surfaceBtn = event.target.closest("[data-surface]");
    if (surfaceBtn) {
      state.surface = surfaceBtn.dataset.surface;
      renderAll();
      return;
    }

    const sceneBtn = event.target.closest("[data-scene]");
    if (sceneBtn) {
      state.scene = sceneBtn.dataset.scene;
      state.oauthStep = "idle";
      renderAll();
      return;
    }

    if (event.target.closest("#btn-sim-event")) {
      simulateIncomingEvent();
      return;
    }


    if (P.handleSettingsAndInspectorClick(event)) {
      return;
    }

    if (event.target.closest("#status-item")) {
      state.surface = "popover";
      renderAll();
      return;
    }

    const mainTabBtn = event.target.closest("[data-main-tab]");
    if (mainTabBtn) {
      state.mainTab = mainTabBtn.dataset.mainTab;
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-sync")) {
      triggerSync();
      return;
    }

    if (event.target.closest("#btn-quick-filter")) {
      state.quickFilterOpen = !state.quickFilterOpen;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-close-filter")) {
      state.quickFilterOpen = false;
      state.quickFilterMode = "all";
      renderAll();
      return;
    }

    const qfBtn = event.target.closest("[data-quick-filter]");
    if (qfBtn) {
      state.quickFilterMode = qfBtn.dataset.quickFilter;
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-open-settings")) {
      state.surface = "settings";
      renderAll();
      return;
    }

    const inboxScopeBtn = event.target.closest("[data-inbox-scope]");
    if (inboxScopeBtn) {
      state.inboxScope = inboxScopeBtn.dataset.inboxScope;
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    const workScopeBtn = event.target.closest("[data-work-scope]");
    if (workScopeBtn) {
      state.workScope = workScopeBtn.dataset.workScope;
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-cycle-work-type")) {
      const order = ["all", "prs", "issues"];
      state.workType = order[(order.indexOf(state.workType) + 1) % order.length];
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    const watchScopeBtn = event.target.closest("[data-watch-scope]");
    if (watchScopeBtn) {
      state.watchScope = watchScopeBtn.dataset.watchScope;
      state.activeRowIndex = 0;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-mark-tab-read")) {
      markCurrentTabRead();
      return;
    }

    if (event.target.closest("#btn-manage-searches")) {
      state.surface = "workspace";
      state.workspaceMode = "searches";
      renderAll();
      return;
    }

    if (event.target.closest("#btn-manage-monitors")) {
      state.surface = "workspace";
      state.workspaceMode = "monitors";
      renderAll();
      return;
    }

    const toggleReadBtn = event.target.closest('[data-action="toggle-read"]');
    if (toggleReadBtn) {
      markRowRead(toggleReadBtn.dataset.id);
      return;
    }

    const openRowBtn = event.target.closest('[data-action="open-row"]');
    if (openRowBtn) {
      const rowId = openRowBtn.dataset.id;
      const notif = state.notifications.find(n => n.id === rowId);
      if (notif && notif.unread) {
        notif.unread = false;
        notif.fresh = false;
      }
      for (const m of state.monitors) {
        const ev = m.events.find(e => e.id === rowId);
        if (ev && ev.unread) {
          ev.unread = false;
          ev.fresh = false;
        }
      }
      for (const s of state.savedSearches) {
        const ev = s.alertEvents.find(e => e.id === rowId);
        if (ev && ev.unread) {
          ev.unread = false;
          ev.fresh = false;
        }
      }
      showPopoverStatus("Opened " + itemLabelForId(rowId));
      renderAll();
      return;
    }

    const wsModeBtn = event.target.closest("[data-workspace-mode]");
    if (wsModeBtn) {
      state.workspaceMode = wsModeBtn.dataset.workspaceMode;
      state.drawerMode = null;
      state.drawerError = null;
      state.confirmingDeleteId = null;
      P.renderWorkspace();
      P.renderSpacingInspector();
      return;
    }

    if (event.target.closest("#btn-workspace-new")) {
      if (state.workspaceMode === "monitors") {
        state.drawerMode = state.drawerMode === "new-monitor" ? null : "new-monitor";
      } else {
        state.drawerMode = state.drawerMode === "new-search" ? null : "new-search";
      }
      state.drawerError = null;
      P.renderWorkspace();
      return;
    }

    const monSelect = event.target.closest("[data-select-monitor]");
    if (monSelect) {
      state.selectedMonitorId = monSelect.dataset.selectMonitor;
      state.confirmingDeleteId = null;
      P.renderWorkspace();
      return;
    }

    const searchSelect = event.target.closest("[data-select-search]");
    if (searchSelect) {
      state.selectedSearchId = searchSelect.dataset.selectSearch;
      state.confirmingDeleteId = null;
      P.renderWorkspace();
      return;
    }

    const presetBtn = event.target.closest("[data-drawer-preset]");
    if (presetBtn) {
      state.drawerPreset = presetBtn.dataset.drawerPreset;
      state.drawerError = null;
      P.renderWorkspace();
      return;
    }

    const searchPresetBtn = event.target.closest("[data-search-drawer-preset]");
    if (searchPresetBtn) {
      state.searchDrawerPreset = searchPresetBtn.dataset.searchDrawerPreset;
      state.drawerError = null;
      P.renderWorkspace();
      return;
    }

    if (event.target.closest("#btn-drawer-cancel")) {
      state.drawerMode = null;
      state.drawerError = null;
      P.renderWorkspace();
      return;
    }

    if (event.target.closest("#btn-drawer-save")) {
      if (state.drawerPreset === "invalid-repo") {
        state.drawerError = 'GitHub repository "samzong/missing-404" returned HTTP 404. Choose a valid target.';
        P.renderWorkspace();
        return;
      }
      const isUser = state.drawerPreset === "valid-user";
      const newId = isUser ? "m-yyx" : "m-cargo";
      if (!state.monitors.some(m => m.id === newId)) {
        state.monitors.unshift({
          id: newId,
          name: isUser ? "@yyx990803" : "cargo",
          type: isUser ? "account" : "repository",
          target: isUser ? "yyx990803" : "rust-lang/cargo",
          enabled: true,
          lastSynced: "just now",
          toggles: { commit: true, pr: true, issue: true, release: true, comment: false },
          events: [
            {
              id: "me-added-" + state.eventSeq++,
              kind: "release",
              state: "info",
              repo: isUser ? "vuejs/core" : "rust-lang/cargo",
              actor: isUser ? "@yyx990803" : "@ehuss",
              time: "6m",
              unread: true,
              url: isUser ? "https://github.com/vuejs/core" : "https://github.com/rust-lang/cargo",
              title: isUser
                ? "Release v3.5.14: vapor compiler hydration schedule pass"
                : "Merged #14892: stabilize resolver sparse index cache headers"
            }
          ]
        });
      }
      state.selectedMonitorId = newId;
      state.drawerMode = null;
      state.drawerError = null;
      showWindowStatus("workspace", "Target saved · initial sync complete");
      renderAll();
      return;
    }

    if (event.target.closest("#btn-search-drawer-save")) {
      if (state.searchDrawerPreset === "invalid-query") {
        state.drawerError = "Query syntax is empty. Enter an Issue or Pull Request query before saving.";
        P.renderWorkspace();
        return;
      }
      const isBugs = state.searchDrawerPreset === "valid-bugs";
      const newId = isBugs ? "s-bugs" : "s-swift";
      if (!state.savedSearches.some(s => s.id === newId)) {
        const resultItem = isBugs
          ? {
              id: "sr-bugs-" + state.eventSeq++,
              kind: "issue",
              state: "open",
              repo: "samzong/lunt",
              number: 28,
              reason: "assigned",
              ci: null,
              time: "15m",
              url: "https://github.com/samzong/lunt/issues/28",
              title: "Improve GitHub request status and rate-limit readout"
            }
          : {
              id: "sr-swift-" + state.eventSeq++,
              kind: "pr",
              state: "open",
              repo: "samzong/lunt",
              number: 42,
              reason: "Swift 6",
              ci: "pass",
              time: "5m",
              url: "https://github.com/samzong/lunt/pull/42",
              title: "refactor(ui): unify MenuBarExtra header platter and single-row scope strip"
            };
        state.savedSearches.push({
          id: newId,
          name: isBugs ? "Assigned Bugs" : "Open Swift 6 PRs",
          type: isBugs ? "issue" : "pr",
          pinned: true,
          watchAlerts: isBugs,
          enabled: true,
          lastSynced: "just now",
          query: isBugs ? "assignee:@me is:open is:issue label:bug" : "user:samzong is:open is:pr language:swift",
          results: [resultItem],
          alertEvents: isBugs
            ? [
                {
                  id: "se-new-" + state.eventSeq++,
                  kind: resultItem.kind,
                  state: resultItem.state,
                  repo: resultItem.repo,
                  number: resultItem.number,
                  actor: "query: Assigned Bugs",
                  time: resultItem.time,
                  unread: true,
                  url: resultItem.url,
                  title: resultItem.title
                }
              ]
            : []
        });
      }
      state.selectedSearchId = newId;
      state.drawerMode = null;
      state.drawerError = null;
      showWindowStatus("workspace", "Query saved · pinned in Work");
      renderAll();
      return;
    }

    if (event.target.closest("#btn-toggle-mon-enabled")) {
      const m = state.monitors.find(x => x.id === state.selectedMonitorId);
      if (m) {
        m.enabled = !m.enabled;
        renderAll();
      }
      return;
    }

    if (event.target.closest("#btn-sync-single-mon")) {
      const m = state.monitors.find(x => x.id === state.selectedMonitorId);
      if (m) {
        m.lastSynced = "just now";
        showWindowStatus("workspace", m.name + " synced just now");
        P.renderWorkspace();
      }
      return;
    }

    if (event.target.closest("#btn-ask-delete-mon")) {
      state.confirmingDeleteId = state.selectedMonitorId;
      P.renderWorkspace();
      return;
    }

    if (event.target.closest("#btn-ask-delete-search")) {
      state.confirmingDeleteId = state.selectedSearchId;
      P.renderWorkspace();
      return;
    }

    if (event.target.closest("#btn-cancel-delete")) {
      state.confirmingDeleteId = null;
      P.renderWorkspace();
      return;
    }

    if (event.target.closest("#btn-confirm-delete")) {
      state.monitors = state.monitors.filter(m => m.id !== state.confirmingDeleteId);
      state.confirmingDeleteId = null;
      state.selectedMonitorId = state.monitors[0]?.id || null;
      renderAll();
      return;
    }

    if (event.target.closest("#btn-confirm-delete-search")) {
      state.savedSearches = state.savedSearches.filter(s => s.id !== state.confirmingDeleteId);
      state.confirmingDeleteId = null;
      state.selectedSearchId = state.savedSearches[0]?.id || null;
      renderAll();
      return;
    }

    const monKindBtn = event.target.closest("[data-mon-kind]");
    if (monKindBtn) {
      const m = state.monitors.find(x => x.id === state.selectedMonitorId);
      if (m) {
        const k = monKindBtn.dataset.monKind;
        m.toggles[k] = !(m.toggles[k] !== false);
        renderAll();
      }
      return;
    }

    if (event.target.closest("#btn-toggle-search-pin")) {
      const s = state.savedSearches.find(x => x.id === state.selectedSearchId);
      if (s) {
        s.pinned = !s.pinned;
        renderAll();
      }
      return;
    }

    if (event.target.closest("#btn-toggle-search-watch")) {
      const s = state.savedSearches.find(x => x.id === state.selectedSearchId);
      if (s) {
        s.watchAlerts = !s.watchAlerts;
        if (s.watchAlerts && s.alertEvents.length === 0 && s.results.length > 0) {
          const seed = s.results[0];
          s.alertEvents.push({
            id: "se-seed-" + s.id + "-" + state.eventSeq++,
            kind: seed.kind,
            state: seed.state,
            repo: seed.repo,
            number: seed.number,
            actor: "query: " + s.name,
            time: seed.time,
            unread: true,
            url: seed.url,
            title: seed.title
          });
        }
        renderAll();
      }
      return;
    }

    if (event.target.closest("#btn-toggle-search-enabled")) {
      const s = state.savedSearches.find(x => x.id === state.selectedSearchId);
      if (s) {
        s.enabled = !s.enabled;
        renderAll();
      }
      return;
    }

  });

  const stageEl = document.getElementById("desktop-stage");

  document.addEventListener("keydown", event => {
    if (stageEl) stageEl.classList.toggle("command-held", event.metaKey);

    if (event.key === "Escape") {
      if (state.banner) {
        state.banner = null;
        clearBannerTimer();
        P.renderBanner();
        return;
      }
      if (state.quickFilterOpen) {
        state.quickFilterOpen = false;
        state.quickFilterMode = "all";
        renderAll();
        return;
      }
      if (state.drawerMode || state.confirmingDeleteId) {
        state.drawerMode = null;
        state.confirmingDeleteId = null;
        renderAll();
        return;
      }
    }

    if (state.surface !== "popover") return;

    if (event.metaKey && !event.shiftKey && !event.altKey && /^[1-9]$/.test(event.key)) {
      const rows = currentPopoverRows();
      const idx = Number(event.key) - 1;
      if (rows[idx]) {
        event.preventDefault();
        state.activeRowIndex = idx;
        showPopoverStatus(
          "Opened " + (rows[idx].repo ? rows[idx].repo + (rows[idx].number ? "#" + rows[idx].number : "") : "GitHub")
        );
        if (rows[idx].unread) markRowRead(rows[idx].id);
        else renderAll();
      }
      return;
    }

    if (event.metaKey && event.key.toLowerCase() === "r") {
      event.preventDefault();
      triggerSync();
      return;
    }

    if (event.key === "/" && !event.metaKey && !event.ctrlKey) {
      event.preventDefault();
      state.quickFilterOpen = !state.quickFilterOpen;
      renderAll();
      return;
    }

    const rows = currentPopoverRows();
    if (!rows.length) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      state.activeRowIndex = Math.min(rows.length - 1, state.activeRowIndex + 1);
      P.renderPopover();
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      state.activeRowIndex = Math.max(0, state.activeRowIndex - 1);
      P.renderPopover();
    } else if (event.key.toLowerCase() === "e" && !event.metaKey && !event.ctrlKey) {
      const target = rows[state.activeRowIndex];
      if (target) {
        event.preventDefault();
        markRowRead(target.id);
      }
    }
  });

  document.addEventListener("keyup", event => {
    if (stageEl) stageEl.classList.toggle("command-held", event.metaKey);
  });

  window.addEventListener("blur", () => {
    if (stageEl) stageEl.classList.remove("command-held");
  });

  window.addEventListener("resize", () => {
    if (state.spacingOpen) P.renderSpacingInspector();
  });

  renderAll();

})();
