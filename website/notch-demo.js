(function () {
  const MODULES = [
    "media",
    "calendar",
    "shelf",
    "focus",
    "notes",
    "clipboard",
    "agents",
    "mirror",
  ];
  const AUTOPLAY_CYCLE = ["media", "shelf", "focus", "agents", "calendar", "notes"];
  const IDLE_MS = 1400;
  const MODULE_MS = 3400;

  function prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  function isCoarsePointer() {
    return window.matchMedia("(hover: none)").matches;
  }

  function initDemo(root) {
    const island = root.querySelector(".notch-island");
    const stage = root.querySelector(".notch-demo-stage");
    if (!island || !stage) return;

    const mode = root.getAttribute("data-notch-mode") || "manual";
    const isAutoplay = mode === "autoplay" && !prefersReducedMotion();
    const staysExpanded = mode === "expanded";
    const expandedEl = island.querySelector(".notch-expanded");
    const idleEl = island.querySelector(".notch-idle");

    // hover / manual / autoplay all start idle unless marked expanded
    let expanded = root.classList.contains("is-expanded") || staysExpanded;
    let current = root.getAttribute("data-active-module") || "media";
    let userLocked = false;
    let inView = false;
    let timers = [];
    let autoplayIndex = 0;

    function clearTimers() {
      timers.forEach((id) => clearTimeout(id));
      timers = [];
    }

    function schedule(fn, ms) {
      timers.push(setTimeout(fn, ms));
    }

    function setExpanded(next) {
      expanded = Boolean(next);
      root.classList.toggle("is-expanded", expanded);
      island.setAttribute("data-state", expanded ? "expanded" : "idle");
      root.setAttribute("aria-expanded", String(expanded));
      if (expandedEl) expandedEl.setAttribute("aria-hidden", String(!expanded));
      if (idleEl) idleEl.setAttribute("aria-hidden", String(expanded));
    }

    function setModule(id, fromUser) {
      if (!MODULES.includes(id)) return;
      current = id;
      root.setAttribute("data-active-module", id);
      root.setAttribute("data-module", id);

      root.querySelectorAll("[data-module-tab]").forEach((tab) => {
        const active = tab.getAttribute("data-module-tab") === id;
        tab.classList.toggle("is-active", active);
        tab.setAttribute("aria-selected", String(active));
        tab.tabIndex = active ? 0 : -1;
      });

      root.querySelectorAll("[data-module-chip]").forEach((chip) => {
        const active = chip.getAttribute("data-module-chip") === id;
        chip.classList.toggle("is-active", active);
        chip.setAttribute("aria-selected", String(active));
      });

      root.querySelectorAll("[data-module-panel]").forEach((panel) => {
        const active = panel.getAttribute("data-module-panel") === id;
        panel.classList.toggle("is-active", active);
        if (active) {
          panel.removeAttribute("hidden");
          panel.setAttribute("aria-hidden", "false");
        } else {
          panel.setAttribute("hidden", "");
          panel.setAttribute("aria-hidden", "true");
        }
      });

      if (id === "focus") {
        requestAnimationFrame(syncFocusCountdown);
      }

      if (fromUser) userLocked = true;
    }

    function setFocusMode(modeId, fromUser) {
      if (!modeId) return;
      root.querySelectorAll("[data-focus-mode]").forEach((btn) => {
        const active = btn.getAttribute("data-focus-mode") === modeId;
        btn.classList.toggle("is-active", active);
        btn.setAttribute("aria-selected", String(active));
      });
      root.querySelectorAll("[data-focus-view]").forEach((view) => {
        const active = view.getAttribute("data-focus-view") === modeId;
        view.classList.toggle("is-active", active);
        if (active) {
          view.removeAttribute("hidden");
        } else {
          view.setAttribute("hidden", "");
        }
      });
      if (modeId === "countdown") {
        syncFocusCountdown();
      }
      if (fromUser) userLocked = true;
    }

    // --- Focus time ruler (animated remaining minutes) ---
    const POINT_SPACING = 6;
    const isPolish =
      document.documentElement.lang === "pl" ||
      /\/pl(\/|$)/.test(location.pathname);
    let remainingSeconds = 24 * 60 + 59;
    let rulerDragging = false;
    let dragStartX = 0;
    let dragStartMinute = 0;
    let focusRaf = 0;
    let lastFocusTick = 0;

    function formatCountdown(sec) {
      const s = Math.max(0, Math.floor(sec));
      const m = Math.floor(s / 60);
      const r = s % 60;
      return `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
    }

    function ensureRulerTicks(ruler) {
      const ticks = ruler.querySelector("[data-focus-ruler-ticks]");
      if (!ticks || ticks.dataset.ready === "1") return ticks;
      ticks.replaceChildren();
      for (let m = 0; m <= 90; m += 1) {
        const el = document.createElement("span");
        el.className = "focus-ruler-tick" + (m % 5 === 0 ? " is-major" : "");
        el.style.left = `${m * POINT_SPACING}px`;
        if (m % 5 === 0) {
          const lab = document.createElement("i");
          lab.textContent = String(m);
          el.appendChild(lab);
        }
        ticks.appendChild(el);
      }
      ticks.style.width = `${90 * POINT_SPACING}px`;
      ticks.dataset.ready = "1";
      return ticks;
    }

    function setRulerCenter(ruler, minutes) {
      const ticks = ensureRulerTicks(ruler);
      const win = ruler.querySelector(".focus-ruler-window");
      if (!ticks || !win) return;
      const mid = win.clientWidth / 2 || ruler.clientWidth / 2;
      const clamped = Math.min(90, Math.max(0, minutes));
      ticks.style.transform = `translateX(${mid - clamped * POINT_SPACING}px)`;
      ruler.setAttribute("aria-valuenow", String(Math.round(clamped)));
    }

    function syncFocusCountdown() {
      root.querySelectorAll('[data-focus-view="countdown"]').forEach((view) => {
        const timeEl = view.querySelector(".focus-time");
        const ruler = view.querySelector("[data-focus-ruler]");
        if (timeEl) timeEl.textContent = formatCountdown(remainingSeconds);
        if (ruler) setRulerCenter(ruler, remainingSeconds / 60);
      });
    }

    function tickFocus(now) {
      const focusActive =
        expanded &&
        current === "focus" &&
        root.querySelector("[data-focus-mode].is-active")?.getAttribute("data-focus-mode") ===
          "countdown";

      if (focusActive && !rulerDragging && !prefersReducedMotion()) {
        if (!lastFocusTick) lastFocusTick = now;
        if (now - lastFocusTick >= 70) {
          remainingSeconds = Math.max(0, remainingSeconds - 2.2);
          if (remainingSeconds <= 8) remainingSeconds = 25 * 60;
          lastFocusTick = now;
          syncFocusCountdown();
        }
      } else {
        lastFocusTick = 0;
      }
      focusRaf = requestAnimationFrame(tickFocus);
    }

    function bindRulerDrag(ruler) {
      ensureRulerTicks(ruler);
      setRulerCenter(ruler, remainingSeconds / 60);

      ruler.addEventListener("pointerdown", (event) => {
        if (event.button != null && event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
        stopAutoplay();
        rulerDragging = true;
        dragStartX = event.clientX;
        dragStartMinute = remainingSeconds / 60;
        ruler.setPointerCapture?.(event.pointerId);
        expandTo("focus", true);
        setFocusMode("countdown", true);
      });

      ruler.addEventListener("pointermove", (event) => {
        if (!rulerDragging) return;
        const live = dragStartMinute - (event.clientX - dragStartX) / POINT_SPACING;
        const clamped = Math.min(90, Math.max(1, live));
        remainingSeconds = clamped * 60;
        syncFocusCountdown();
      });

      const endDrag = (event) => {
        if (!rulerDragging) return;
        rulerDragging = false;
        remainingSeconds = Math.round(Math.min(90, Math.max(1, remainingSeconds / 60))) * 60;
        syncFocusCountdown();
        try {
          ruler.releasePointerCapture?.(event.pointerId);
        } catch (_) {
          /* ignore */
        }
      };
      ruler.addEventListener("pointerup", endDrag);
      ruler.addEventListener("pointercancel", endDrag);
    }

    root.querySelectorAll("[data-focus-ruler]").forEach(bindRulerDrag);
    syncFocusCountdown();
    if (!prefersReducedMotion()) {
      focusRaf = requestAnimationFrame(tickFocus);
    }

    // --- Claude Allow / Deny ---
    const claudeCopy = isPolish
      ? {
          pending: {
            phase: "Wymaga zatwierdzenia",
            body: "Zapis do Package.swift?",
          },
          allowed: {
            phase: "Uruchomione",
            body: "Zapisuję Package.swift…",
          },
          denied: {
            phase: "Odrzucono",
            body: "Zapis zablokowany",
          },
        }
      : {
          pending: {
            phase: "Needs approval",
            body: "Write to Package.swift?",
          },
          allowed: {
            phase: "Running",
            body: "Writing Package.swift…",
          },
          denied: {
            phase: "Denied",
            body: "Write blocked",
          },
        };

    let claudeResetTimer = 0;

    function setClaudeState(row, state) {
      if (!row) return;
      row.setAttribute("data-agent-state", state);
      const copy = claudeCopy[state] || claudeCopy.pending;
      const phase = row.querySelector(".agent-phase");
      const body = row.querySelector(".agent-body");
      if (phase) phase.textContent = copy.phase;
      if (body) body.textContent = copy.body;
      row.classList.toggle("agent-cursor", false);
    }

    function decideClaude(decision) {
      const row = root.querySelector("[data-agent-claude]");
      if (!row) return;
      stopAutoplay();
      expandTo("agents", true);
      clearTimeout(claudeResetTimer);
      setClaudeState(row, decision === "allow" ? "allowed" : "denied");
      claudeResetTimer = window.setTimeout(() => {
        setClaudeState(row, "pending");
      }, 2800);
    }

    function expandTo(moduleId, fromUser) {
      setModule(moduleId, fromUser);
      setExpanded(true);
      if (moduleId === "focus") syncFocusCountdown();
    }

    function collapse(fromUser) {
      if (staysExpanded && !fromUser) return;
      setExpanded(false);
      if (fromUser) userLocked = true;
    }

    function stopAutoplay() {
      clearTimers();
      userLocked = true;
    }

    function runAutoplayStep() {
      if (userLocked || !inView || document.hidden || prefersReducedMotion()) return;

      if (!expanded) {
        expandTo(AUTOPLAY_CYCLE[0], false);
        autoplayIndex = 0;
        schedule(runAutoplayStep, MODULE_MS);
        return;
      }

      autoplayIndex = (autoplayIndex + 1) % AUTOPLAY_CYCLE.length;
      if (autoplayIndex === 0) {
        collapse(false);
        schedule(runAutoplayStep, IDLE_MS);
        return;
      }

      setModule(AUTOPLAY_CYCLE[autoplayIndex], false);
      schedule(runAutoplayStep, MODULE_MS);
    }

    function startAutoplay() {
      if (!isAutoplay || userLocked) return;
      clearTimers();
      schedule(runAutoplayStep, IDLE_MS);
    }

    // Initial state
    setModule(current, false);
    setFocusMode(
      root.querySelector("[data-focus-mode].is-active")?.getAttribute("data-focus-mode") ||
        "countdown",
      false
    );
    setExpanded(expanded);

    // Event delegation — reliable for icon tabs, chips, and focus picker
    root.addEventListener("click", (event) => {
      const tab = event.target.closest("[data-module-tab]");
      if (tab && root.contains(tab)) {
        event.preventDefault();
        event.stopPropagation();
        stopAutoplay();
        expandTo(tab.getAttribute("data-module-tab"), true);
        return;
      }

      const chip = event.target.closest("[data-module-chip]");
      if (chip && root.contains(chip)) {
        event.preventDefault();
        event.stopPropagation();
        stopAutoplay();
        expandTo(chip.getAttribute("data-module-chip"), true);
        return;
      }

      const focusBtn = event.target.closest("[data-focus-mode]");
      if (focusBtn && root.contains(focusBtn)) {
        event.preventDefault();
        event.stopPropagation();
        stopAutoplay();
        setFocusMode(focusBtn.getAttribute("data-focus-mode"), true);
        return;
      }

      const decideBtn = event.target.closest("[data-agent-decide]");
      if (decideBtn && root.contains(decideBtn)) {
        event.preventDefault();
        event.stopPropagation();
        decideClaude(decideBtn.getAttribute("data-agent-decide"));
        return;
      }

      // Tap collapsed island to expand
      if (!expanded && island.contains(event.target)) {
        event.preventDefault();
        stopAutoplay();
        expandTo(current, true);
      }
    });

    root.addEventListener("keydown", (event) => {
      const tab = event.target.closest("[data-module-tab]");
      if (!tab || !root.contains(tab)) return;
      const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
      if (!keys.includes(event.key)) return;
      event.preventDefault();
      const list = Array.from(root.querySelectorAll("[data-module-tab]"));
      const index = list.indexOf(tab);
      const delta = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
      const next = list[(index + delta + list.length) % list.length];
      next.focus();
      stopAutoplay();
      expandTo(next.getAttribute("data-module-tab"), true);
    });

    if (!isCoarsePointer()) {
      // Expand only when hovering the notch/island — not the whole stage
      island.addEventListener("pointerenter", () => {
        if (staysExpanded) return;
        if (!expanded) expandTo(current, false);
        if (isAutoplay && !userLocked) clearTimers();
      });
      island.addEventListener("pointerleave", (event) => {
        if (staysExpanded || userLocked) return;
        const next = event.relatedTarget;
        // Keep open when moving to chips / hint under the same demo
        if (next && root.contains(next) && !island.contains(next)) return;
        if (isAutoplay && inView) {
          startAutoplay();
          return;
        }
        collapse(false);
      });
      root.addEventListener("pointerleave", () => {
        if (staysExpanded || userLocked) return;
        if (isAutoplay && inView) {
          startAutoplay();
          return;
        }
        collapse(false);
      });
    }

    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      if (staysExpanded) return;
      if (!expanded) return;
      if (!root.contains(document.activeElement) && !root.matches(":hover")) return;
      stopAutoplay();
      collapse(true);
    });

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        clearTimers();
      } else if (isAutoplay && inView && !userLocked) {
        startAutoplay();
      }
    });

    if (isCoarsePointer()) {
      document.addEventListener("pointerdown", (event) => {
        if (!expanded || staysExpanded) return;
        if (root.contains(event.target)) return;
        if (!userLocked && isAutoplay) return;
        collapse(true);
      });
    }

    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            inView = entry.isIntersecting && entry.intersectionRatio > 0.2;
            root.classList.toggle("is-in-view", inView);
            if (inView && isAutoplay && !userLocked) {
              startAutoplay();
            } else if (!inView) {
              clearTimers();
            }
          });
        },
        { threshold: [0, 0.2, 0.5] }
      );
      io.observe(root);
    } else {
      inView = true;
      if (isAutoplay) startAutoplay();
    }
  }

  function initAll() {
    document.querySelectorAll("[data-notch-demo]").forEach(initDemo);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initAll);
  } else {
    initAll();
  }
})();
