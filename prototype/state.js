(() => {
  const P = (window.LuntProto = window.LuntProto || {});
  const DATA = window.LUNT_DATA;
  const ICONS = DATA.icons;

  const clone = value => JSON.parse(JSON.stringify(value));

  const state = {
    surface: "popover",
    scene: "live",
    oauthStep: "idle",
    mainTab: "inbox",
    inboxScope: "all",
    workScope: "all",
    workType: "all",
    watchScope: "all",
    quickFilterOpen: false,
    quickFilterMode: "all",
    activeRowIndex: 0,
    syncing: false,
    lastSyncedLabel: "Synced 12s ago",
    workspaceMode: "monitors",
    selectedMonitorId: "m-sglang",
    selectedSearchId: "s-review",
    drawerMode: null,
    drawerPreset: "valid-repo",
    searchDrawerPreset: "valid-swift",
    drawerError: null,
    confirmingDeleteId: null,
    settingsTab: "general",
    refreshInterval: "1m",
    launchAtLogin: true,
    showMenuBarCount: true,
    systemNotifications: true,
    visibleTabs: {
      inbox: true,
      work: true,
      watch: true
    },
    sparkleState: "idle",
    spacingOpen: false,
    spacingArea: "all",
    selectedMetricId: "G01",
    banner: null,
    popoverNotice: null,
    workspaceNotice: null,
    settingsNotice: null,
    eventSeq: 1,
    notifications: clone(DATA.notifications),
    activities: clone(DATA.activities),
    savedSearches: clone(DATA.savedSearches),
    monitors: clone(DATA.monitors),
    rules: clone(DATA.rules)
  };

  let bannerTimer = null;
  let popoverNoticeTimer = null;
  let workspaceNoticeTimer = null;
  let settingsNoticeTimer = null;

  function clearBannerTimer() {
    clearTimeout(bannerTimer);
    bannerTimer = null;
  }

  function showSystemBanner(title, detail) {
    state.banner = { title, detail };
    clearBannerTimer();
    P.renderBanner();
    bannerTimer = setTimeout(() => {
      state.banner = null;
      P.renderBanner();
    }, 3600);
  }

  function showPopoverStatus(message) {
    state.popoverNotice = message;
    clearTimeout(popoverNoticeTimer);
    P.renderPopover();
    popoverNoticeTimer = setTimeout(() => {
      state.popoverNotice = null;
      P.renderPopover();
    }, 2600);
  }

  function showWindowStatus(target, message) {
    if (target === "workspace") {
      state.workspaceNotice = message;
      clearTimeout(workspaceNoticeTimer);
      renderWindowStatus();
      workspaceNoticeTimer = setTimeout(() => {
        state.workspaceNotice = null;
        renderWindowStatus();
      }, 2800);
      return;
    }
    state.settingsNotice = message;
    clearTimeout(settingsNoticeTimer);
    renderWindowStatus();
    settingsNoticeTimer = setTimeout(() => {
      state.settingsNotice = null;
      renderWindowStatus();
    }, 2800);
  }

  function renderWindowStatus() {
    const wsEl = document.getElementById("workspace-status");
    if (wsEl) {
      wsEl.hidden = !state.workspaceNotice;
      wsEl.textContent = state.workspaceNotice || "";
    }
    const setEl = document.getElementById("settings-status");
    if (setEl) {
      setEl.hidden = !state.settingsNotice;
      setEl.textContent = state.settingsNotice || "";
    }
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function stateGlyphFor(item) {
    if (item.kind === "pr") {
      if (item.state === "merged") return { cls: "state-merged", svg: ICONS.prMerged };
      if (item.state === "closed") return { cls: "state-closed", svg: ICONS.prClosed };
      if (item.state === "draft") return { cls: "state-draft", svg: ICONS.prDraft };
      return { cls: "state-open", svg: ICONS.prOpen };
    }
    if (item.kind === "issue") {
      if (item.state === "closed" || item.state === "done") return { cls: "state-merged", svg: ICONS.issueDone };
      return { cls: "state-open", svg: ICONS.issueOpen };
    }
    if (item.kind === "release") return { cls: "state-info", svg: ICONS.release };
    return { cls: "state-open", svg: ICONS.commit };
  }

  function ciMarkHtml(ci) {
    if (ci === "pass") return '<span class="ci-mark state-open" title="Checks pass">✓ CI</span>';
    if (ci === "fail") return '<span class="ci-mark state-closed" title="Checks fail">✕ CI</span>';
    if (ci === "pending") return '<span class="ci-mark state-pending" title="Checks run">● CI</span>';
    return "";
  }

  function unreadNotificationsCount() {
    if (state.scene === "empty" || state.scene === "oauth") return 0;
    return state.notifications.filter(item => item.unread).length;
  }

  function unreadWatchCount() {
    if (state.scene === "empty" || state.scene === "oauth") return 0;
    let total = 0;
    for (const m of state.monitors) {
      if (!m.enabled) continue;
      for (const ev of m.events) {
        if (ev.unread && m.toggles[ev.kind] !== false) total++;
      }
    }
    for (const s of state.savedSearches) {
      if (!s.enabled || !s.watchAlerts) continue;
      for (const ev of s.alertEvents) {
        if (ev.unread) total++;
      }
    }
    return total;
  }

  function enabledMainTabs() {
    const order = ["inbox", "work", "watch"];
    const list = order.filter(key => state.visibleTabs[key]);
    return list.length ? list : ["inbox"];
  }

  function ensureValidMainTab() {
    const allowed = enabledMainTabs();
    if (!allowed.includes(state.mainTab)) {
      state.mainTab = allowed[0];
    }
  }

  function ensureValidWorkScope() {
    if (!state.workScope.startsWith("search:")) return;
    const targetId = state.workScope.slice(7);
    const active = state.savedSearches.some(s => s.id === targetId && s.enabled && s.pinned);
    if (!active) state.workScope = "all";
  }

  function ensureValidWatchScope() {
    if (state.watchScope.startsWith("mon:")) {
      const targetId = state.watchScope.slice(4);
      if (!state.monitors.some(m => m.id === targetId && m.enabled)) {
        state.watchScope = "all";
      }
    } else if (state.watchScope.startsWith("query:")) {
      const targetId = state.watchScope.slice(6);
      if (!state.savedSearches.some(s => s.id === targetId && s.enabled && s.watchAlerts)) {
        state.watchScope = "all";
      }
    }
  }

  function filterByWorkType(items) {
    if (state.workType === "prs") return items.filter(item => item.kind === "pr");
    if (state.workType === "issues") return items.filter(item => item.kind === "issue");
    return items;
  }

  function mapWatchEventToRow(ev, sourceId) {
    return {
      id: ev.id,
      kind: ev.kind,
      state: ev.state,
      repo: ev.repo,
      number: ev.number || null,
      reason: ev.actor,
      ci: null,
      time: ev.time,
      unread: ev.unread,
      url: ev.url,
      title: ev.title,
      fresh: ev.fresh,
      sourceId
    };
  }

  function currentPopoverRows() {
    if (state.scene !== "live") return [];
    let rows = [];
    if (state.mainTab === "inbox") {
      rows = state.notifications.filter(item => {
        if (state.inboxScope === "prs") return item.kind === "pr";
        if (state.inboxScope === "issues") return item.kind === "issue";
        return true;
      });
    } else if (state.mainTab === "work") {
      ensureValidWorkScope();
      if (state.workScope.startsWith("search:")) {
        const searchId = state.workScope.slice(7);
        const match = state.savedSearches.find(s => s.id === searchId && s.enabled);
        rows = match ? filterByWorkType(match.results.slice()) : [];
      } else {
        const roleFiltered = state.activities.filter(
          item => state.workScope === "all" || item.role === state.workScope
        );
        rows = filterByWorkType(roleFiltered);
      }
    } else if (state.mainTab === "watch") {
      ensureValidWatchScope();
      for (const m of state.monitors) {
        if (!m.enabled) continue;
        if (state.watchScope !== "all" && state.watchScope !== "mon:" + m.id) continue;
        for (const ev of m.events) {
          if (m.toggles[ev.kind] === false) continue;
          rows.push(mapWatchEventToRow(ev, m.id));
        }
      }
      for (const s of state.savedSearches) {
        if (!s.enabled || !s.watchAlerts) continue;
        if (state.watchScope !== "all" && state.watchScope !== "query:" + s.id) continue;
        for (const ev of s.alertEvents) {
          rows.push(mapWatchEventToRow(ev, s.id));
        }
      }
    }

    if (state.quickFilterOpen) {
      if (state.quickFilterMode === "unread") {
        rows = rows.filter(r => r.unread);
      } else if (state.quickFilterMode === "prs") {
        rows = rows.filter(r => r.kind === "pr");
      } else if (state.quickFilterMode === "ci-fail") {
        rows = rows.filter(r => r.ci === "fail" || r.ci === "pending");
      }
    }
    return rows;
  }

  function itemLabelForId(rowId) {
    const n = state.notifications.find(x => x.id === rowId);
    if (n) return n.repo + (n.number ? "#" + n.number : "");
    const a = state.activities.find(x => x.id === rowId);
    if (a) return a.repo + (a.number ? "#" + a.number : "");
    for (const s of state.savedSearches) {
      const r = s.results.find(x => x.id === rowId) || s.alertEvents.find(x => x.id === rowId);
      if (r) return r.repo + (r.number ? "#" + r.number : "");
    }
    for (const m of state.monitors) {
      const ev = m.events.find(x => x.id === rowId);
      if (ev) return ev.repo + (ev.number ? "#" + ev.number : "");
    }
    return "GitHub";
  }

  function markRowRead(rowId) {
    const notif = state.notifications.find(n => n.id === rowId);
    if (notif) {
      notif.unread = !notif.unread;
      notif.fresh = false;
      P.renderAll();
      return;
    }
    for (const m of state.monitors) {
      const ev = m.events.find(e => e.id === rowId);
      if (ev) {
        ev.unread = !ev.unread;
        ev.fresh = false;
        P.renderAll();
        return;
      }
    }
    for (const s of state.savedSearches) {
      const ev = s.alertEvents.find(e => e.id === rowId);
      if (ev) {
        ev.unread = !ev.unread;
        ev.fresh = false;
        P.renderAll();
        return;
      }
    }
    showPopoverStatus("Work items reflect live GitHub state");
  }

  function markCurrentTabRead() {
    if (state.mainTab === "inbox") {
      for (const n of state.notifications) {
        if (state.inboxScope === "prs" && n.kind !== "pr") continue;
        if (state.inboxScope === "issues" && n.kind !== "issue") continue;
        n.unread = false;
        n.fresh = false;
      }
      showPopoverStatus("Inbox marked as read");
    } else if (state.mainTab === "watch") {
      for (const m of state.monitors) {
        if (state.watchScope !== "all" && state.watchScope !== "mon:" + m.id) continue;
        for (const ev of m.events) {
          ev.unread = false;
          ev.fresh = false;
        }
      }
      for (const s of state.savedSearches) {
        if (!s.watchAlerts) continue;
        if (state.watchScope !== "all" && state.watchScope !== "query:" + s.id) continue;
        for (const ev of s.alertEvents) {
          ev.unread = false;
          ev.fresh = false;
        }
      }
      showPopoverStatus("Watch stream cleared");
    }
    P.renderAll();
  }

  function triggerSync() {
    if (state.syncing) return;
    state.syncing = true;
    P.renderAll();
    setTimeout(() => {
      state.syncing = false;
      if (state.scene === "error") {
        state.scene = "live";
      }
      state.lastSyncedLabel = "Synced just now";
      for (const m of state.monitors) {
        if (m.enabled) m.lastSynced = "just now";
      }
      for (const s of state.savedSearches) {
        if (s.enabled) s.lastSynced = "just now";
      }
      P.renderAll();
    }, 420);
  }

  function simulateIncomingEvent() {
    state.scene = "live";
    const idx = state.eventSeq++;
    const samples = [
      {
        repo: "samzong/lunt",
        number: 43 + idx,
        kind: "pr",
        state: "open",
        reason: "review requested",
        ci: "pass",
        title: "feat(menubar): align trailing hover actions without title reflow"
      },
      {
        repo: "samzong/spale",
        number: 40 + idx,
        kind: "issue",
        state: "open",
        reason: "mention",
        ci: null,
        title: "Preserve manual scroll offset when switching window bar tabs"
      },
      {
        repo: "sgl-project/sglang",
        number: 13090 + idx,
        kind: "pr",
        state: "open",
        reason: "review requested",
        ci: "pending",
        title: "perf(attention): fuse FP8 kv-cache quantize into decode epilogue"
      }
    ];
    const pick = samples[(idx - 1) % samples.length];
    state.notifications.unshift({
      id: "sim-n-" + idx,
      kind: pick.kind,
      state: pick.state,
      repo: pick.repo,
      number: pick.number,
      threads: 1,
      reason: pick.reason,
      ci: pick.ci,
      time: "now",
      unread: true,
      fresh: true,
      url: "https://github.com/" + pick.repo + "/pull/" + pick.number,
      title: pick.title
    });
    const alertSearch = state.savedSearches.find(s => s.enabled && s.watchAlerts);
    if (idx % 2 === 0 && alertSearch) {
      alertSearch.alertEvents.unshift({
        id: "sim-q-" + idx,
        kind: pick.kind,
        state: pick.state,
        repo: pick.repo,
        number: pick.number,
        actor: "query: " + alertSearch.name,
        time: "now",
        unread: true,
        fresh: true,
        url: "https://github.com/" + pick.repo + "/pull/" + pick.number,
        title: pick.title
      });
    } else if (state.monitors[0]) {
      state.monitors[0].events.unshift({
        id: "sim-m-" + idx,
        kind: "pr",
        state: "open",
        repo: pick.repo,
        actor: "@samzong",
        time: "now",
        unread: true,
        fresh: true,
        url: "https://github.com/" + pick.repo,
        title: pick.title
      });
    }
    state.lastSyncedLabel = "Updated just now";
    if (state.systemNotifications) {
      showSystemBanner(pick.repo + " #" + pick.number, pick.title);
    } else {
      showPopoverStatus("New event in " + pick.repo);
    }
    P.renderAll();
  }


  function renderRowHtml(row, index, allowReadToggle) {
    const glyph = stateGlyphFor(row);
    const isUnread = row.unread === true;
    const isReadAttr = row.unread === false ? ' data-read="true"' : "";
    const freshCls = row.fresh ? " fresh" : "";
    const activeAttr = index === state.activeRowIndex ? ' data-active="true"' : "";
    const shortcutNum = index < 9 ? String(index + 1) : "";
    const shortcutAttr = shortcutNum ? ' data-shortcut="' + shortcutNum + '"' : "";
    const numberPart = row.number ? '<span class="meta-num">#' + row.number + "</span>" : "";
    const threadsPart =
      row.threads && row.threads > 1
        ? '<span class="meta-tag">×' + row.threads + "</span>"
        : "";
    const reasonPart = row.reason
      ? '<span class="meta-tag">' + escapeHtml(row.reason) + "</span>"
      : "";
    const ciPart = ciMarkHtml(row.ci);
    const dotPart = isUnread ? '<span class="status-dot" aria-hidden="true"></span>' : "";

    const toggleBtn = allowReadToggle
      ? '<button type="button" class="row-icon-btn" data-action="toggle-read" data-id="' +
        escapeHtml(row.id) +
        '" title="' +
        (isUnread ? "Mark as read (E)" : "Mark as unread (E)") +
        '" aria-label="' +
        (isUnread ? "Mark as read: " : "Mark as unread: ") +
        escapeHtml(row.title) +
        '">' +
        ICONS.check +
        "</button>"
      : "";

    return (
      '<div class="item-row' +
      freshCls +
      '"' +
      isReadAttr +
      activeAttr +
      shortcutAttr +
      ' data-row-index="' +
      index +
      '">' +
      '<div class="state-glyph ' +
      glyph.cls +
      '">' +
      glyph.svg +
      "</div>" +
      '<div class="item-main">' +
      '<button type="button" class="item-primary-btn" data-action="open-row" data-id="' +
      escapeHtml(row.id) +
      '" data-url="' +
      escapeHtml(row.url || "https://github.com") +
      '" data-title="' +
      escapeHtml(row.title) +
      '">' +
      '<span class="meta-line"><span class="meta-repo">' +
      escapeHtml(row.repo) +
      "</span>" +
      numberPart +
      threadsPart +
      reasonPart +
      ciPart +
      "</span>" +
      '<span class="item-title">' +
      escapeHtml(row.title) +
      "</span>" +
      "</button>" +
      "</div>" +
      '<div class="item-trailing">' +
      '<span class="trailing-rest"><span>' +
      escapeHtml(row.time) +
      "</span>" +
      dotPart +
      "</span>" +
      '<span class="trailing-actions">' +
      toggleBtn +
      '<button type="button" class="row-icon-btn" data-action="open-row" data-id="' +
      escapeHtml(row.id) +
      '" data-url="' +
      escapeHtml(row.url || "https://github.com") +
      '" data-title="' +
      escapeHtml(row.title) +
      '" title="Open on GitHub" aria-label="Open on GitHub: ' +
      escapeHtml(row.title) +
      '">' +
      ICONS.ext +
      "</button>" +
      "</span>" +
      (shortcutNum
        ? '<span class="trailing-shortcut" aria-hidden="true"><span class="shortcut-cap">' +
          shortcutNum +
          "</span></span>"
        : "") +
      "</div>" +
      "</div>"
    );
  }

  Object.assign(P, {
    DATA,
    ICONS,
    state,
    clearBannerTimer,
    showSystemBanner,
    showPopoverStatus,
    showWindowStatus,
    renderWindowStatus,
    escapeHtml,
    stateGlyphFor,
    ciMarkHtml,
    unreadNotificationsCount,
    unreadWatchCount,
    enabledMainTabs,
    ensureValidMainTab,
    ensureValidWorkScope,
    ensureValidWatchScope,
    filterByWorkType,
    mapWatchEventToRow,
    currentPopoverRows,
    itemLabelForId,
    markRowRead,
    markCurrentTabRead,
    triggerSync,
    simulateIncomingEvent,
    renderRowHtml
  });
})();
