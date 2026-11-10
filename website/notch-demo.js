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
  const AUTOPLAY_CYCLE = ["agents", "media", "shelf", "focus", "calendar", "notes"];
  const IDLE_MS = 1400;
  const MODULE_MS = 3400;
  // Agents step timings (autoplay only)
  const AGENT_NEEDS_YOU_MS = 1500; // idle notch shows "needs you"
  const AGENT_APPROVE_MS = 1500; // expanded, before the simulated Allow
  const AGENT_PRESS_MS = 260; // Allow button pressed highlight
  const AGENT_RUN_MS = 2500; // Claude row: running -> done
  const AGENT_DONE_MS = 1300; // keep "Done" on screen before moving on

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
      if (expandedEl) {
        expandedEl.setAttribute("aria-hidden", String(!expanded));
        if (expanded) expandedEl.removeAttribute("inert");
        else expandedEl.setAttribute("inert", "");
      }
      if (idleEl) {
        idleEl.setAttribute("aria-hidden", String(expanded));
        idleEl.tabIndex = expanded ? -1 : 0;
      }
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

      syncIdleAlert();
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
      if (!inView || document.hidden) {
        focusRaf = 0;
        lastFocusTick = 0;
        return;
      }

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

    function ensureFocusLoop() {
      if (prefersReducedMotion() || focusRaf || !inView || document.hidden) return;
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

      ruler.addEventListener("keydown", (event) => {
        const step = event.shiftKey ? 5 : 1;
        let minutes = remainingSeconds / 60;
        if (event.key === "ArrowRight" || event.key === "ArrowUp") minutes += step;
        else if (event.key === "ArrowLeft" || event.key === "ArrowDown") minutes -= step;
        else if (event.key === "Home") minutes = 1;
        else if (event.key === "End") minutes = 90;
        else return;
        event.preventDefault();
        event.stopPropagation();
        stopAutoplay();
        remainingSeconds = Math.min(90, Math.max(1, Math.round(minutes))) * 60;
        syncFocusCountdown();
        expandTo("focus", true);
        setFocusMode("countdown", true);
      });
    }

    root.querySelectorAll("[data-focus-ruler]").forEach(bindRulerDrag);
    syncFocusCountdown();

    // --- Claude Allow / Deny + usage meters ---
    const COPY = {
      en: {
        claude: {
          pending: { phase: "Needs approval", pre: "Run ", post: "?" },
          running: { phase: "Running", pre: "Running ", post: "…" },
          done: { phase: "Done ✓", pre: "", post: " passed" },
          denied: { phase: "Denied", pre: "", post: " blocked" },
        },
        live: {
          waiting: "Claude Code is waiting for approval",
          approved: "Approved",
          done: "Done",
          denied: "Denied",
        },
        idleAlert: "Claude Code needs approval. Expand NotchFlow",
      },
      pl: {
        claude: {
          pending: { phase: "Wymaga zgody", pre: "Uruchom ", post: "?" },
          running: { phase: "Pracuje", pre: "Uruchamiam ", post: "…" },
          done: { phase: "Gotowe ✓", pre: "", post: " zaliczony" },
          denied: { phase: "Odrzucono", pre: "", post: " zablokowany" },
        },
        live: {
          waiting: "Claude Code czeka na zgodę",
          approved: "Zatwierdzono",
          done: "Gotowe",
          denied: "Odrzucono",
        },
        idleAlert: "Claude Code wymaga zgody. Rozwiń NotchFlow",
      },
    };
    const copy = COPY[isPolish ? "pl" : "en"];

    const CLAUDE_DONE_HOLD_MS = 3200; // done -> back to pending
    const CLAUDE_DENIED_HOLD_MS = 2800; // denied -> back to pending
    const USAGE_CLAUDE_5H = 62;
    const USAGE_COST = 3;

    const claudeRow = root.querySelector("[data-agent-claude]");
    const liveEl = root.querySelector("[data-agent-live]");
    const idleBaseLabel = idleEl ? idleEl.getAttribute("aria-label") || "" : "";
    let claudeState = "pending";
    let claudeTimers = [];
    let liveTimer = 0;

    function clearClaudeTimers() {
      claudeTimers.forEach((id) => clearTimeout(id));
      claudeTimers = [];
    }

    function announce(message) {
      if (!liveEl || !message) return;
      clearTimeout(liveTimer);
      liveEl.textContent = "";
      // Re-set after a tick so repeated messages are announced again.
      liveTimer = window.setTimeout(() => {
        liveEl.textContent = message;
      }, 60);
    }

    function setUsage(key, percent) {
      root.querySelectorAll(`[data-usage-fill="${key}"]`).forEach((fill) => {
        fill.style.setProperty("--usage", `${percent}%`);
      });
      root.querySelectorAll(`[data-usage-value="${key}"]`).forEach((value) => {
        value.textContent = String(percent);
      });
    }

    function syncIdleAlert() {
      const alert = current === "agents" && claudeState === "pending" && Boolean(claudeRow);
      root.classList.toggle("is-agent-alert", alert);
      if (idleEl) {
        idleEl.setAttribute("aria-label", alert ? copy.idleAlert : idleBaseLabel);
      }
    }

    function setClaudeState(state) {
      claudeState = copy.claude[state] ? state : "pending";
      root.querySelectorAll(".agent-actions .is-pressed").forEach((btn) => {
        btn.classList.remove("is-pressed");
      });
      if (claudeRow) {
        const text = copy.claude[claudeState];
        claudeRow.setAttribute("data-agent-state", claudeState);
        const phase = claudeRow.querySelector(".agent-phase");
        const pre = claudeRow.querySelector(".agent-body-pre");
        const post = claudeRow.querySelector(".agent-body-post");
        if (phase) phase.textContent = text.phase;
        if (pre) pre.textContent = text.pre;
        if (post) post.textContent = text.post;
        // Buttons stay in the layout (hidden via CSS) so the row keeps its height.
        claudeRow.querySelectorAll("[data-agent-decide]").forEach((btn) => {
          btn.disabled = claudeState !== "pending";
        });
      }
      if (claudeState === "pending") setUsage("claude-5h", USAGE_CLAUDE_5H);
      if (claudeState === "done") setUsage("claude-5h", USAGE_CLAUDE_5H - USAGE_COST);
      syncIdleAlert();
    }

    function resetClaude() {
      clearClaudeTimers();
      if (claudeState !== "pending") setClaudeState("pending");
    }

    // Runs the Allow / Deny sequence. `speak` controls the live region so the
    // looping autoplay never floods screen readers.
    function runClaude(decision, speak) {
      if (!claudeRow) return;
      clearClaudeTimers();
      const focusWasOnActions = claudeRow.contains(document.activeElement);
      if (decision === "allow") {
        setClaudeState("running");
        if (speak) announce(copy.live.approved);
        claudeTimers.push(
          window.setTimeout(() => {
            setClaudeState("done");
            if (speak) announce(copy.live.done);
          }, AGENT_RUN_MS)
        );
        claudeTimers.push(
          window.setTimeout(() => {
            setClaudeState("pending");
            if (speak) announce(copy.live.waiting);
          }, AGENT_RUN_MS + CLAUDE_DONE_HOLD_MS)
        );
      } else {
        setClaudeState("denied");
        if (speak) announce(copy.live.denied);
        claudeTimers.push(
          window.setTimeout(() => {
            setClaudeState("pending");
            if (speak) announce(copy.live.waiting);
          }, CLAUDE_DENIED_HOLD_MS)
        );
      }
      // The buttons hide while the row is busy; keep keyboard focus in place.
      if (focusWasOnActions) claudeRow.focus({ preventScroll: true });
    }

    function decideClaude(decision) {
      if (!claudeRow || claudeState !== "pending") return;
      stopAutoplay();
      expandTo("agents", true);
      runClaude(decision === "allow" ? "allow" : "deny", true);
    }

    // --- MacBook / Mac without a notch ---
    function setDevice(device) {
      const menubar = device === "menubar";
      root.classList.toggle("is-menubar", menubar);
      root.setAttribute("data-device", menubar ? "menubar" : "notch");
      root.querySelectorAll("[data-device-choice]").forEach((btn) => {
        btn.setAttribute(
          "aria-pressed",
          String(btn.getAttribute("data-device-choice") === (menubar ? "menubar" : "notch"))
        );
      });
    }

    function expandTo(moduleId, fromUser) {
      const wasShowing = expanded && current === moduleId;
      setModule(moduleId, fromUser);
      setExpanded(true);
      if (moduleId === "focus") syncFocusCountdown();
      if (fromUser && moduleId === "agents" && !wasShowing && claudeState === "pending") {
        announce(copy.live.waiting);
      }
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

    function autoplayBlocked() {
      return userLocked || !inView || document.hidden || prefersReducedMotion();
    }

    function userIsOnIsland() {
      return island.matches(":hover") || island.contains(document.activeElement);
    }

    // Agents scenario: idle "needs you" -> expand -> cursor-less Allow ->
    // running -> done -> continue the cycle.
    function playAgentsScenario() {
      autoplayIndex = 0;
      resetClaude();
      setModule("agents", false);
      schedule(() => {
        if (autoplayBlocked()) return;
        expandTo("agents", false);
        schedule(() => {
          if (autoplayBlocked()) return;
          if (claudeState !== "pending" || userIsOnIsland()) {
            // Never approve on the visitor's behalf while they are on the island.
            schedule(runAutoplayStep, MODULE_MS);
            return;
          }
          const allowBtn = claudeRow && claudeRow.querySelector('[data-agent-decide="allow"]');
          if (allowBtn) allowBtn.classList.add("is-pressed");
          schedule(() => {
            if (allowBtn) allowBtn.classList.remove("is-pressed");
            if (autoplayBlocked() || claudeState !== "pending") return;
            runClaude("allow", false);
            schedule(runAutoplayStep, AGENT_RUN_MS + AGENT_DONE_MS);
          }, AGENT_PRESS_MS);
        }, AGENT_APPROVE_MS);
      }, AGENT_NEEDS_YOU_MS);
    }

    function runAutoplayStep() {
      if (autoplayBlocked()) return;

      if (!expanded) {
        if (AUTOPLAY_CYCLE[0] === "agents" && claudeRow) {
          playAgentsScenario();
          return;
        }
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
      // Collapsed on the agents scenario: go straight into "needs you".
      const delay = !expanded && current === "agents" ? 0 : IDLE_MS;
      schedule(runAutoplayStep, delay);
    }

    // Initial state
    setModule(current, false);
    setFocusMode(
      root.querySelector("[data-focus-mode].is-active")?.getAttribute("data-focus-mode") ||
        "countdown",
      false
    );
    setExpanded(expanded);
    setDevice(root.getAttribute("data-device") === "menubar" ? "menubar" : "notch");
    setClaudeState("pending");

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

      const deviceBtn = event.target.closest("[data-device-choice]");
      if (deviceBtn && root.contains(deviceBtn)) {
        event.preventDefault();
        setDevice(deviceBtn.getAttribute("data-device-choice"));
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
        if (focusRaf) {
          cancelAnimationFrame(focusRaf);
          focusRaf = 0;
        }
      } else if (inView) {
        ensureFocusLoop();
        if (isAutoplay && !userLocked) startAutoplay();
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
            const wasInView = inView;
            inView = entry.isIntersecting && entry.intersectionRatio > 0.2;
            root.classList.toggle("is-in-view", inView);
            // Only (re)start on entering view so threshold changes don't cut a step short.
            if (inView && !wasInView && isAutoplay && !userLocked) {
              startAutoplay();
            } else if (!inView) {
              clearTimers();
            }
            if (inView) ensureFocusLoop();
            else if (focusRaf) {
              cancelAnimationFrame(focusRaf);
              focusRaf = 0;
            }
          });
        },
        { threshold: [0, 0.2, 0.5] }
      );
      io.observe(root);
    } else {
      inView = true;
      ensureFocusLoop();
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
