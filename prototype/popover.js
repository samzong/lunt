(() => {
  const P = window.LuntProto;
  const {
    ICONS,
    state,
    clearBannerTimer,
    showPopoverStatus,
    escapeHtml,
    unreadNotificationsCount,
    unreadWatchCount,
    ensureValidMainTab,
    ensureValidWorkScope,
    ensureValidWatchScope,
    filterByWorkType,
    currentPopoverRows,
    triggerSync,
    renderRowHtml
  } = P;

  function renderTopControls() {
    document.querySelectorAll("[data-surface]").forEach(btn => {
      btn.setAttribute("aria-pressed", String(btn.dataset.surface === state.surface));
    });
    document.querySelectorAll("[data-scene]").forEach(btn => {
      btn.setAttribute("aria-pressed", String(btn.dataset.scene === state.scene));
    });
    const spacingBtn = document.getElementById("btn-toggle-spacing");
    if (spacingBtn) {
      spacingBtn.setAttribute("aria-pressed", String(state.spacingOpen));
    }
  }

  function renderMenuBar() {
    const appTitle = document.getElementById("menubar-app-name");
    if (appTitle) {
      appTitle.textContent = state.surface === "popover" ? "Xcode" : "Lunt";
    }
    const statusBtn = document.getElementById("status-item");
    if (!statusBtn) return;
    const totalUnread = unreadNotificationsCount();
    statusBtn.setAttribute("aria-expanded", String(state.surface === "popover"));
    statusBtn.setAttribute(
      "aria-label",
      totalUnread > 0
        ? "Lunt menu bar, " + totalUnread + " unread notifications"
        : "Lunt menu bar, no unread notifications"
    );
    const dotHtml = totalUnread > 0 ? '<span class="status-dot" aria-hidden="true"></span>' : "";
    const countHtml =
      totalUnread > 0 && state.showMenuBarCount
        ? "<span>" + totalUnread + "</span>"
        : "";
    statusBtn.innerHTML = ICONS.github + countHtml + dotHtml;
  }

  function renderBanner() {
    const box = document.getElementById("stage-banner");
    if (!box) return;
    if (!state.banner) {
      box.hidden = true;
      box.innerHTML = "";
      return;
    }
    box.hidden = false;
    box.innerHTML =
      '<div class="banner-app-icon" aria-hidden="true">' +
      ICONS.github +
      '</div><div class="banner-copy"><strong>' +
      escapeHtml(state.banner.title) +
      "</strong><span>" +
      escapeHtml(state.banner.detail) +
      '</span></div><button type="button" class="row-icon-btn" id="btn-dismiss-banner" aria-label="Dismiss notification">' +
      ICONS.close +
      "</button>";
    const dismiss = document.getElementById("btn-dismiss-banner");
    if (dismiss) {
      dismiss.addEventListener("click", () => {
        state.banner = null;
        clearBannerTimer();
        renderBanner();
      });
    }
  }

  function renderPopover() {
    const wrap = document.getElementById("popover-wrap");
    if (!wrap) return;
    wrap.hidden = state.surface !== "popover";
    if (state.surface !== "popover") return;

    ensureValidMainTab();
    const tabsEl = document.getElementById("main-tabs");
    const tabDefs = [
      { id: "inbox", label: "Inbox", dot: unreadNotificationsCount() > 0 },
      { id: "work", label: "Work", dot: false },
      { id: "watch", label: "Watch", dot: unreadWatchCount() > 0 }
    ].filter(t => state.visibleTabs[t.id]);

    tabsEl.innerHTML = tabDefs
      .map(
        t =>
          '<button type="button" role="tab" class="nav-seg" data-main-tab="' +
          t.id +
          '" aria-selected="' +
          String(state.mainTab === t.id) +
          '">' +
          '<span class="nav-label">' +
          t.label +
          "</span>" +
          (t.dot ? '<span class="status-dot" aria-hidden="true"></span>' : "") +
          "</button>"
      )
      .join("");

    const syncBtn = document.getElementById("btn-sync");
    if (syncBtn) {
      syncBtn.classList.toggle("spinning", state.syncing);
    }

    const filterBtn = document.getElementById("btn-quick-filter");
    if (filterBtn) {
      filterBtn.setAttribute("aria-pressed", String(state.quickFilterOpen));
    }

    const scopeBar = document.getElementById("scope-bar");
    const filterDrawer = document.getElementById("filter-drawer");
    const listEl = document.getElementById("popover-list");
    const calmEl = document.getElementById("popover-calm");
    const statusDot = document.getElementById("popover-status-dot");
    const statusText = document.getElementById("popover-status-text");

    if (statusDot) {
      statusDot.classList.toggle("notice", Boolean(state.popoverNotice));
    }

    if (state.scene === "oauth") {
      scopeBar.hidden = true;
      filterDrawer.hidden = true;
      listEl.hidden = true;
      calmEl.hidden = false;
      if (state.oauthStep === "code") {
        calmEl.innerHTML =
          '<div class="calm-glyph">' +
          ICONS.github +
          "</div>" +
          '<p class="calm-title">Authorize Lunt on GitHub</p>' +
          '<p class="calm-sub">Lunt copied the code to the clipboard. Confirm in your browser to store the session in Keychain.</p>' +
          '<div class="device-code-box">WDJB-491K</div>' +
          '<div class="calm-actions">' +
          '<button type="button" class="action-primary" id="btn-oauth-complete">Complete authorization</button>' +
          '<button type="button" class="action-secondary" id="btn-oauth-cancel">Cancel</button>' +
          "</div>";
      } else {
        calmEl.innerHTML =
          '<div class="calm-glyph">' +
          ICONS.github +
          "</div>" +
          '<p class="calm-title">Connect your GitHub account</p>' +
          '<p class="calm-sub">Device OAuth stores credentials in macOS Keychain without personal tokens.</p>' +
          '<div class="calm-actions">' +
          '<button type="button" class="action-primary" id="btn-oauth-start">Sign in with GitHub</button>' +
          "</div>";
      }
      statusText.textContent = state.popoverNotice || "Not signed in · OAuth device flow";
      bindCalmActions();
      return;
    }

    scopeBar.hidden = false;
    filterDrawer.hidden = !state.quickFilterOpen;
    renderScopeBar();
    renderFilterDrawer();

    if (state.scene === "error") {
      listEl.hidden = true;
      calmEl.hidden = false;
      calmEl.innerHTML =
        '<div class="calm-glyph state-closed">' +
        ICONS.prClosed +
        "</div>" +
        '<p class="calm-title">GitHub GraphQL request timed out</p>' +
        '<p class="calm-sub">Cached state stays visible. Make sure that network access works or sync again.</p>' +
        '<div class="calm-actions">' +
        '<button type="button" class="action-primary" id="btn-error-retry">Sync again</button>' +
        '<button type="button" class="action-secondary" id="btn-error-settings">Account settings</button>' +
        "</div>";
      statusText.textContent = state.popoverNotice || "Sync failed · cached snapshot retained";
      bindCalmActions();
      return;
    }

    const rows = currentPopoverRows();
    if (state.activeRowIndex >= rows.length) {
      state.activeRowIndex = Math.max(0, rows.length - 1);
    }

    if (rows.length === 0) {
      listEl.hidden = true;
      calmEl.hidden = false;
      const isWatch = state.mainTab === "watch";
      calmEl.innerHTML =
        '<div class="calm-glyph">' +
        (isWatch ? ICONS.watch : ICONS.check) +
        "</div>" +
        '<p class="calm-title">' +
        (isWatch ? "No unread watch events" : "No matching items") +
        "</p>" +
        '<p class="calm-sub">' +
        (isWatch
          ? "Watched repositories, accounts, and queries have no new events right now."
          : "No items match the selected filter.") +
        "</p>" +
        '<div class="calm-actions">' +
        (state.scene === "empty"
          ? '<button type="button" class="action-secondary" id="btn-restore-live">Load sample stream</button>'
          : "") +
        (isWatch
          ? '<button type="button" class="action-primary" id="btn-empty-manage">Manage watch targets</button>'
          : "") +
        "</div>";
      statusText.textContent =
        (state.popoverNotice ? state.popoverNotice : state.lastSyncedLabel) + " · 0 unread";
      bindCalmActions();
      return;
    }

    calmEl.hidden = true;
    listEl.hidden = false;
    const allowReadToggle = state.mainTab === "inbox" || state.mainTab === "watch";
    listEl.innerHTML = rows.map((row, idx) => renderRowHtml(row, idx, allowReadToggle)).join("");

    const unread = unreadNotificationsCount();
    statusText.textContent =
      (state.popoverNotice
        ? state.popoverNotice
        : state.syncing
          ? "Syncing GitHub…"
          : state.lastSyncedLabel) +
      " · " +
      unread +
      " unread";
  }

  function renderScopeBar() {
    const pillsEl = document.getElementById("scope-pills");
    const actionsEl = document.getElementById("scope-actions");
    if (!pillsEl || !actionsEl) return;

    if (state.mainTab === "inbox") {
      const allCount = state.scene === "empty" ? 0 : state.notifications.length;
      const prCount = state.scene === "empty" ? 0 : state.notifications.filter(n => n.kind === "pr").length;
      const issueCount = state.scene === "empty" ? 0 : state.notifications.filter(n => n.kind === "issue").length;
      const defs = [
        { id: "all", label: "All", count: allCount },
        { id: "prs", label: "PRs", count: prCount },
        { id: "issues", label: "Issues", count: issueCount }
      ];
      pillsEl.innerHTML = defs
        .map(
          d =>
            '<button type="button" class="scope-pill" data-inbox-scope="' +
            d.id +
            '" aria-pressed="' +
            String(state.inboxScope === d.id) +
            '"><span>' +
            d.label +
            '</span><span class="scope-count">' +
            d.count +
            "</span></button>"
        )
        .join("");
      actionsEl.innerHTML =
        unreadNotificationsCount() > 0
          ? '<button type="button" class="compact-action" id="btn-mark-tab-read" title="Mark visible as read">' +
            ICONS.check +
            "<span>Read</span></button>"
          : "";
    } else if (state.mainTab === "work") {
      ensureValidWorkScope();
      const roles = [
        { id: "all", label: "All" },
        { id: "review", label: "Review" },
        { id: "assigned", label: "Assigned" },
        { id: "created", label: "Created" },
        { id: "mentioned", label: "Mentioned" }
      ];
      const baseItems = filterByWorkType(state.activities);
      let html = roles
        .map(r => {
          const count =
            state.scene === "empty"
              ? 0
              : baseItems.filter(a => r.id === "all" || a.role === r.id).length;
          return (
            '<button type="button" class="scope-pill" data-work-scope="' +
            r.id +
            '" aria-pressed="' +
            String(state.workScope === r.id) +
            '"><span>' +
            r.label +
            '</span><span class="scope-count">' +
            count +
            "</span></button>"
          );
        })
        .join("");

      const pinned = state.savedSearches.filter(s => s.enabled && s.pinned);
      if (pinned.length > 0) {
        html += '<span class="scope-sep" aria-hidden="true"></span>';
        html += pinned
          .map(s => {
            const count = state.scene === "empty" ? 0 : filterByWorkType(s.results).length;
            return (
              '<button type="button" class="scope-pill" data-work-scope="search:' +
              escapeHtml(s.id) +
              '" aria-pressed="' +
              String(state.workScope === "search:" + s.id) +
              '"><span>' +
              escapeHtml(s.name) +
              '</span><span class="scope-count">' +
              count +
              "</span></button>"
            );
          })
          .join("");
      }
      pillsEl.innerHTML = html;

      const nextLabel =
        state.workType === "all"
          ? "All ▾"
          : state.workType === "prs"
            ? "PRs ▾"
            : "Issues ▾";
      actionsEl.innerHTML =
        '<button type="button" class="compact-action" id="btn-cycle-work-type" aria-label="Filter work item type">' +
        nextLabel +
        "</button>" +
        '<button type="button" class="compact-action" id="btn-manage-searches" title="Manage saved queries">' +
        ICONS.sliders +
        "<span>Manage</span></button>";
    } else if (state.mainTab === "watch") {
      ensureValidWatchScope();
      const activeMons = state.monitors.filter(m => m.enabled);
      const alertQueries = state.savedSearches.filter(s => s.enabled && s.watchAlerts);
      let html =
        '<button type="button" class="scope-pill" data-watch-scope="all" aria-pressed="' +
        String(state.watchScope === "all") +
        '"><span>All</span><span class="scope-count">' +
        unreadWatchCount() +
        "</span></button>";
      html += activeMons
        .map(
          m =>
            '<button type="button" class="scope-pill" data-watch-scope="mon:' +
            escapeHtml(m.id) +
            '" aria-pressed="' +
            String(state.watchScope === "mon:" + m.id) +
            '"><span>' +
            escapeHtml(m.name) +
            "</span></button>"
        )
        .join("");
      html += alertQueries
        .map(
          s =>
            '<button type="button" class="scope-pill" data-watch-scope="query:' +
            escapeHtml(s.id) +
            '" aria-pressed="' +
            String(state.watchScope === "query:" + s.id) +
            '"><span>' +
            escapeHtml(s.name) +
            "</span></button>"
        )
        .join("");
      pillsEl.innerHTML = html;
      actionsEl.innerHTML =
        (unreadWatchCount() > 0
          ? '<button type="button" class="compact-action" id="btn-mark-tab-read">' +
            ICONS.check +
            "<span>Read</span></button>"
          : "") +
        '<button type="button" class="compact-action" id="btn-manage-monitors">' +
        ICONS.sliders +
        "<span>Manage</span></button>";
    }
  }

  function renderFilterDrawer() {
    const drawer = document.getElementById("filter-drawer");
    if (!drawer || drawer.hidden) return;
    const modes = [
      { id: "all", label: "All items" },
      { id: "unread", label: "Unread only" },
      { id: "prs", label: "Pull requests" },
      { id: "ci-fail", label: "CI attention" }
    ];
    drawer.innerHTML =
      '<div class="filter-presets" role="group" aria-label="Quick filter">' +
      modes
        .map(
          m =>
            '<button type="button" class="scope-pill" data-quick-filter="' +
            m.id +
            '" aria-pressed="' +
            String(state.quickFilterMode === m.id) +
            '">' +
            m.label +
            "</button>"
        )
        .join("") +
      "</div>" +
      '<button type="button" class="icon-btn" id="btn-close-filter" aria-label="Close quick filter">' +
      ICONS.close +
      "</button>";
  }

  function bindCalmActions() {
    document.getElementById("btn-oauth-start")?.addEventListener("click", () => {
      state.oauthStep = "code";
      showPopoverStatus("Code WDJB-491K copied to pasteboard");
      P.renderAll();
    });
    document.getElementById("btn-oauth-complete")?.addEventListener("click", () => {
      state.oauthStep = "idle";
      state.scene = "live";
      showPopoverStatus("Signed in as @samzong");
      P.renderAll();
    });
    document.getElementById("btn-oauth-cancel")?.addEventListener("click", () => {
      state.oauthStep = "idle";
      P.renderAll();
    });
    document.getElementById("btn-error-retry")?.addEventListener("click", () => {
      triggerSync();
    });
    document.getElementById("btn-error-settings")?.addEventListener("click", () => {
      state.surface = "settings";
      state.settingsTab = "account";
      P.renderAll();
    });
    document.getElementById("btn-restore-live")?.addEventListener("click", () => {
      state.scene = "live";
      P.renderAll();
    });
    document.getElementById("btn-empty-manage")?.addEventListener("click", () => {
      state.surface = "workspace";
      state.workspaceMode = "monitors";
      P.renderAll();
    });
  }


  Object.assign(P, { renderTopControls, renderMenuBar, renderBanner, renderPopover });
})();
