(function () {
  const STORAGE_KEY = "notchflow-theme";

  function getSystemTheme() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function getStoredTheme() {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "light" || stored === "dark") return stored;
    return null;
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    const toggle = document.querySelector(".theme-toggle");
    if (toggle) {
      const label = theme === "dark" ? "Switch to light mode" : "Switch to dark mode";
      toggle.setAttribute("aria-label", label);
    }
  }

  function initTheme() {
    const stored = getStoredTheme();
    applyTheme(stored ?? getSystemTheme());
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute("data-theme") || getSystemTheme();
    const next = current === "dark" ? "light" : "dark";
    localStorage.setItem(STORAGE_KEY, next);
    applyTheme(next);
  }

  function initNav() {
    const toggle = document.querySelector(".nav-toggle");
    const nav = document.querySelector(".nav-links");
    if (!toggle || !nav) return;

    toggle.addEventListener("click", () => {
      const open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", String(open));
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        nav.classList.remove("is-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  function initScreenshots() {
    document.querySelectorAll("[data-screenshot-showcase]").forEach((showcase) => {
      const tabs = showcase.querySelectorAll(".screenshot-tab");
      const panels = showcase.querySelectorAll(".screenshot-panel");
      if (!tabs.length || !panels.length) return;

      tabs.forEach((tab) => {
        const activate = () => {
          const targetId = tab.getAttribute("data-shot");
          if (!targetId) return;

          tabs.forEach((t) => {
            const active = t === tab;
            t.classList.toggle("is-active", active);
            t.setAttribute("aria-selected", String(active));
            t.tabIndex = active ? 0 : -1;
          });

          panels.forEach((panel) => {
            const active = panel.id === targetId;
            panel.classList.toggle("is-active", active);
            panel.hidden = !active;
          });
        };

        tab.addEventListener("click", activate);
        tab.addEventListener("keydown", (event) => {
          const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
          if (!keys.includes(event.key)) return;
          event.preventDefault();
          const list = Array.from(tabs);
          const index = list.indexOf(tab);
          const delta = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
          const next = list[(index + delta + list.length) % list.length];
          next.focus();
          next.click();
        });
      });
    });
  }

  document.querySelector(".theme-toggle")?.addEventListener("click", toggleTheme);

  initTheme();
  initNav();
  initScreenshots();
})();
