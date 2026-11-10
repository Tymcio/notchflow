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
      const custom = toggle.getAttribute(theme === "dark" ? "data-label-light" : "data-label-dark");
      toggle.setAttribute("aria-label", custom || label);
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

    const polish = document.documentElement.lang === "pl";
    const openLabel = toggle.getAttribute("data-label-open") || toggle.getAttribute("aria-label") || (polish ? "Otwórz menu" : "Open menu");
    const closeLabel = toggle.getAttribute("data-label-close") || (polish ? "Zamknij menu" : "Close menu");

    function setOpen(open) {
      nav.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? closeLabel : openLabel);
    }

    toggle.addEventListener("click", () => {
      setOpen(!nav.classList.contains("is-open"));
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => setOpen(false));
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && nav.classList.contains("is-open")) setOpen(false);
    });

    document.addEventListener("pointerdown", (event) => {
      if (!nav.classList.contains("is-open")) return;
      if (nav.contains(event.target) || toggle.contains(event.target)) return;
      setOpen(false);
    });
  }

  function initReveal() {
    const nodes = document.querySelectorAll("[data-reveal]");
    if (!nodes.length) return;

    const reveal = (node) => node.classList.add("is-visible");
    if (!("IntersectionObserver" in window) || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      nodes.forEach(reveal);
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          reveal(entry.target);
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 }
    );
    nodes.forEach((node) => observer.observe(node));
  }

  function initSectionSpy() {
    const links = [...document.querySelectorAll(".nav-links a[href^='#']")];
    if (!links.length || !("IntersectionObserver" in window)) return;

    const map = new Map();
    links.forEach((link) => {
      const id = link.getAttribute("href").slice(1);
      const section = document.getElementById(id);
      if (section) map.set(section, link);
    });
    if (!map.size) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        links.forEach((link) => link.classList.remove("is-active"));
        map.get(visible.target)?.classList.add("is-active");
      },
      { rootMargin: "-40% 0px -45% 0px", threshold: [0.15, 0.4] }
    );
    map.forEach((_, section) => observer.observe(section));
  }

  function initShowcase() {
    const root = document.querySelector("[data-showcase]");
    if (!root) return;

    const shots = [...root.querySelectorAll("[data-shot]")];
    const front = root.querySelector("[data-showcase-front]");
    const back = root.querySelector("[data-showcase-back]");
    if (!shots.length || !front || !back) return;

    const desktop = window.matchMedia("(min-width: 960px)");
    let active = "";
    let showingFront = true;
    let token = 0;

    function photo(id) {
      return root.querySelector('[data-shot="' + id + '"] img');
    }

    function show(id) {
      if (!id || id === active || !desktop.matches) return;
      const source = photo(id);
      if (!source) return;
      const nextSrc = source.currentSrc || source.getAttribute("src");
      if (!nextSrc) return;
      active = id;
      shots.forEach((shot) => shot.classList.toggle("is-current", shot.getAttribute("data-shot") === id));

      const incoming = showingFront ? back : front;
      const outgoing = showingFront ? front : back;
      const request = ++token;

      const commit = () => {
        if (request !== token) return;
        incoming.alt = source.alt;
        incoming.classList.add("is-visible");
        outgoing.classList.remove("is-visible");
        showingFront = !showingFront;
      };

      if (incoming.getAttribute("src") === nextSrc && incoming.complete && incoming.naturalWidth) {
        commit();
        return;
      }
      incoming.onload = commit;
      incoming.alt = source.alt;
      incoming.src = nextSrc;
    }

    function sync() {
      if (!desktop.matches) return;
      const current = shots.find((shot) => shot.classList.contains("is-current")) || shots[0];
      const id = current.getAttribute("data-shot");
      if (!active) {
        const source = photo(id);
        if (source && !front.getAttribute("src")) {
          front.src = source.currentSrc || source.getAttribute("src");
          front.alt = source.alt;
        }
        front.classList.add("is-visible");
        active = id;
        shots.forEach((shot) => shot.classList.toggle("is-current", shot.getAttribute("data-shot") === id));
        return;
      }
      show(id);
    }

    if ("IntersectionObserver" in window) {
      const observer = new IntersectionObserver(
        (entries) => {
          if (!desktop.matches) return;
          const visible = entries
            .filter((entry) => entry.isIntersecting)
            .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
          if (visible) show(visible.target.getAttribute("data-shot"));
        },
        { rootMargin: "-30% 0px -40% 0px", threshold: [0.2, 0.55] }
      );
      shots.forEach((shot) => observer.observe(shot));
    }

    desktop.addEventListener("change", sync);
    sync();
  }

  document.querySelector(".theme-toggle")?.addEventListener("click", toggleTheme);
  initTheme();
  /* Hero recording: no autoplay with reduced motion (the poster stays), and pause it
     while it is off screen so it costs nothing below the fold. */
  function initHeroVideo() {
    var video = document.querySelector(".hero-video");
    if (!video) return;
    var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");
    function play() {
      var attempt = video.play();
      if (attempt && attempt.catch) attempt.catch(function () {});
    }
    if (reduce && reduce.matches) {
      video.removeAttribute("autoplay");
      video.pause();
      return;
    }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) play(); else video.pause();
        });
      }, { threshold: 0.15 }).observe(video);
    }
  }

  initNav();
  initReveal();
  initSectionSpy();
  initShowcase();
  initHeroVideo();
})();
