(() => {
  const P = window.LuntProto;
  const { DATA, state, showSystemBanner, showWindowStatus, escapeHtml, ensureValidMainTab } = P;

  function renderSettings() {
    const win = document.getElementById("surface-settings");
    if (!win) return;
    win.hidden = state.surface !== "settings";
    if (state.surface !== "settings") return;

    const tabs = [
      { id: "general", label: "General" },
      { id: "account", label: "Account" },
      { id: "rules", label: "Rules" },
      { id: "about", label: "About" }
    ];
    const sideEl = document.getElementById("settings-sidebar");
    const detailEl = document.getElementById("settings-detail");

    sideEl.innerHTML = tabs
      .map(
        t =>
          '<button type="button" class="side-row" data-settings-tab="' +
          t.id +
          '" aria-current="' +
          String(state.settingsTab === t.id) +
          '"><span>' +
          t.label +
          "</span></button>"
      )
      .join("");

    if (state.settingsTab === "general") {
      const intervals = ["1m", "2m", "5m", "10m"];
      const tabNames = [
        { id: "inbox", label: "Inbox" },
        { id: "work", label: "Work" },
        { id: "watch", label: "Watch" }
      ];
      detailEl.innerHTML =
        "<h2>General</h2>" +
        '<div class="settings-group">' +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Background refresh</span>' +
        '<span class="settings-hint">Polling cadence for REST notifications and GraphQL queries</span></div>' +
        '<div class="pill-track" role="group" aria-label="Refresh interval">' +
        intervals
          .map(
            iv =>
              '<button type="button" class="pill-seg" data-refresh-iv="' +
              iv +
              '" aria-pressed="' +
              String(state.refreshInterval === iv) +
              '">' +
              iv +
              "</button>"
          )
          .join("") +
        "</div></div>" +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Show unread count in menu bar</span>' +
        '<span class="settings-hint">Updates the menu bar item at the top of this stage immediately</span></div>' +
        '<button type="button" class="switch-btn" id="btn-toggle-menubar-count" aria-pressed="' +
        String(state.showMenuBarCount) +
        '">' +
        (state.showMenuBarCount ? "On" : "Off") +
        "</button></div>" +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Launch at login</span>' +
        '<span class="settings-hint">Managed through SMAppService.mainApp</span></div>' +
        '<button type="button" class="switch-btn" id="btn-toggle-login" aria-pressed="' +
        String(state.launchAtLogin) +
        '">' +
        (state.launchAtLogin ? "On" : "Off") +
        "</button></div>" +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">System notifications</span>' +
        '<span class="settings-hint">Deliver macOS banners during background refresh</span></div>' +
        '<div class="detail-controls">' +
        '<button type="button" class="compact-action" id="btn-test-banner">Send test banner</button>' +
        '<button type="button" class="switch-btn" id="btn-toggle-sys-notif" aria-pressed="' +
        String(state.systemNotifications) +
        '">' +
        (state.systemNotifications ? "On" : "Off") +
        "</button></div></div>" +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Visible popover sections</span>' +
        '<span class="settings-hint">Applies immediately without app restart while one section stays active</span></div>' +
        '<div class="filter-chip-row" role="group" aria-label="Visible popover sections">' +
        tabNames
          .map(
            t =>
              '<button type="button" class="scope-pill" data-toggle-vis-tab="' +
              t.id +
              '" aria-pressed="' +
              String(state.visibleTabs[t.id]) +
              '">' +
              t.label +
              "</button>"
          )
          .join("") +
        "</div></div>" +
        "</div>";
    } else if (state.settingsTab === "account") {
      detailEl.innerHTML =
        "<h2>Account</h2>" +
        '<div class="settings-group">' +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">@samzong</span>' +
        '<span class="settings-hint">Signed in through GitHub OAuth · token stored in macOS Keychain</span></div>' +
        '<div class="detail-controls">' +
        '<button type="button" class="compact-action" id="btn-preview-oauth">Preview Device OAuth</button>' +
        "</div></div>" +
        "</div>";
    } else if (state.settingsTab === "rules") {
      detailEl.innerHTML =
        '<div class="detail-header">' +
        '<div class="detail-title-group"><h2>Notification rules</h2>' +
        '<span class="settings-hint">Evaluated automatically during background notification sync</span></div>' +
        '<button type="button" class="action-secondary" id="btn-run-rules">Run active rules</button>' +
        "</div>" +
        '<div class="settings-group">' +
        state.rules
          .map(
            r =>
              '<div class="settings-row">' +
              '<div class="settings-label-block"><span class="settings-label">' +
              escapeHtml(r.name) +
              '</span><span class="settings-hint"><code>' +
              escapeHtml(r.condition) +
              "</code> → " +
              escapeHtml(r.action) +
              "</span></div>" +
              '<button type="button" class="switch-btn" data-toggle-rule="' +
              escapeHtml(r.id) +
              '" aria-pressed="' +
              String(r.enabled) +
              '">' +
              (r.enabled ? "Enabled" : "Muted") +
              "</button></div>"
          )
          .join("") +
        "</div>";
    } else {
      detailEl.innerHTML =
        "<h2>About Lunt</h2>" +
        '<div class="settings-group">' +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Lunt 0.6.0 (build 89)</span>' +
        '<span class="settings-hint">Apple Silicon (arm64) · macOS 15+ · Swift 6 · Sparkle EdDSA</span></div>' +
        '<button type="button" class="action-secondary" id="btn-check-updates">' +
        (state.sparkleState === "done" ? "Up to date (0.6.0)" : "Check for Updates") +
        "</button></div>" +
        '<div class="settings-row">' +
        '<div class="settings-label-block"><span class="settings-label">Repository</span>' +
        '<span class="settings-hint">github.com/samzong/lunt · MIT License</span></div>' +
        '<span class="meta-tag">LSUIElement</span></div>' +
        "</div>";
    }
  }

  function clearGeometryHighlights() {
    document.querySelectorAll(".geom-highlight").forEach(el => {
      el.classList.remove("geom-highlight");
    });
  }

  function measureSelector(selector) {
    const el = document.querySelector(selector);
    if (!el) return "hidden in current view";
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return "hidden in current view";
    const radius = getComputedStyle(el).borderRadius || "0px";
    return Math.round(rect.width) + " × " + Math.round(rect.height) + " px · r=" + radius;
  }

  function renderSpacingInspector() {
    const bar = document.getElementById("spacing-toolbar");
    const panel = document.getElementById("spacing-inspector");
    clearGeometryHighlights();
    if (!bar || !panel) return;

    bar.hidden = !state.spacingOpen;
    panel.hidden = !state.spacingOpen;
    if (!state.spacingOpen) return;

    document.querySelectorAll("[data-spacing-area]").forEach(btn => {
      btn.setAttribute("aria-pressed", String(btn.dataset.spacingArea === state.spacingArea));
    });

    const filtered = DATA.geometry.filter(
      g => state.spacingArea === "all" || g.area === state.spacingArea
    );
    const active = filtered.find(g => g.id === state.selectedMetricId) || filtered[0];
    if (active) {
      state.selectedMetricId = active.id;
      const targetEl = document.querySelector(active.selector);
      if (targetEl && targetEl.getClientRects().length > 0) {
        targetEl.classList.add("geom-highlight");
      }
      const readout = document.getElementById("spacing-readout");
      if (readout) {
        readout.textContent =
          active.id + " · " + active.relation + " → " + measureSelector(active.selector);
      }
    }

    const tbody = document.getElementById("spacing-tbody");
    if (tbody) {
      tbody.innerHTML = filtered
        .map(
          g =>
            '<tr data-selected="' +
            String(g.id === state.selectedMetricId) +
            '">' +
            '<td><button type="button" class="metric-id-btn" data-metric-id="' +
            g.id +
            '">' +
            g.id +
            "</button></td>" +
            "<td>" +
            escapeHtml(g.relation) +
            "</td>" +
            "<td>" +
            escapeHtml(g.current) +
            "</td>" +
            "<td>" +
            escapeHtml(measureSelector(g.selector)) +
            "</td>" +
            "<td>" +
            escapeHtml(g.target) +
            "</td>" +
            "</tr>"
        )
        .join("");
    }
  }


  function handleSettingsAndInspectorClick(event) {
    if (event.target.closest("#btn-toggle-spacing")) {
      state.spacingOpen = !state.spacingOpen;
      P.renderAll();
      return true;
    }

    const areaBtn = event.target.closest("[data-spacing-area]");
    if (areaBtn) {
      state.spacingArea = areaBtn.dataset.spacingArea;
      renderSpacingInspector();
      return true;
    }

    const metricBtn = event.target.closest("[data-metric-id]");
    if (metricBtn) {
      const id = metricBtn.dataset.metricId;
      state.selectedMetricId = id;
      const spec = DATA.geometry.find(g => g.id === id);
      if (spec) {
        if (spec.id === "G07") state.surface = "workspace";
        else if (spec.id === "G08") state.surface = "settings";
        else state.surface = "popover";
      }
      P.renderAll();
      return true;
    }

    const setTabBtn = event.target.closest("[data-settings-tab]");
    if (setTabBtn) {
      state.settingsTab = setTabBtn.dataset.settingsTab;
      renderSettings();
      return true;
    }

    const refreshBtn = event.target.closest("[data-refresh-iv]");
    if (refreshBtn) {
      state.refreshInterval = refreshBtn.dataset.refreshIv;
      renderSettings();
      return true;
    }

    if (event.target.closest("#btn-toggle-menubar-count")) {
      state.showMenuBarCount = !state.showMenuBarCount;
      P.renderAll();
      return true;
    }

    if (event.target.closest("#btn-toggle-login")) {
      state.launchAtLogin = !state.launchAtLogin;
      renderSettings();
      return true;
    }

    if (event.target.closest("#btn-toggle-sys-notif")) {
      state.systemNotifications = !state.systemNotifications;
      renderSettings();
      return true;
    }

    if (event.target.closest("#btn-test-banner")) {
      showSystemBanner("Lunt test notification", "Background delivery uses UNUserNotificationCenter.");
      return true;
    }

    const visTabBtn = event.target.closest("[data-toggle-vis-tab]");
    if (visTabBtn) {
      const key = visTabBtn.dataset.toggleVisTab;
      const activeCount = Object.values(state.visibleTabs).filter(Boolean).length;
      if (state.visibleTabs[key] && activeCount <= 1) {
        showWindowStatus("settings", "At least one section stays visible");
        return;
      }
      state.visibleTabs[key] = !state.visibleTabs[key];
      ensureValidMainTab();
      P.renderAll();
      return true;
    }

    if (event.target.closest("#btn-preview-oauth")) {
      state.surface = "popover";
      state.scene = "oauth";
      state.oauthStep = "idle";
      P.renderAll();
      return true;
    }

    const ruleBtn = event.target.closest("[data-toggle-rule]");
    if (ruleBtn) {
      const rule = state.rules.find(r => r.id === ruleBtn.dataset.toggleRule);
      if (rule) {
        rule.enabled = !rule.enabled;
        renderSettings();
      }
      return true;
    }

    if (event.target.closest("#btn-run-rules")) {
      let affected = 0;
      if (state.rules[0]?.enabled) {
        for (const n of state.notifications) {
          if (n.repo.includes("homebrew-tap") && n.unread) {
            n.unread = false;
            affected++;
          }
        }
      }
      showWindowStatus(
        "settings",
        affected > 0
          ? affected + " notification marked read"
          : "All matching items already read"
      );
      P.renderAll();
      return true;
    }

    if (event.target.closest("#btn-check-updates")) {
      state.sparkleState = "done";
      showWindowStatus("settings", "Lunt 0.6.0 (arm64) is up to date");
      renderSettings();
      return true;
    }

    return false;
  }

  Object.assign(P, { renderSettings, renderSpacingInspector, handleSettingsAndInspectorClick });
})();
