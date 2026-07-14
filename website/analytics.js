(function () {
  const CONSENT_KEY = "notchflow-cookie-consent";
  const MEASUREMENT_ID_PATTERN = /^G-[A-Z0-9]+$/;

  const COPY = {
    en: {
      title: "Cookies & privacy",
      body: "We use Google Analytics to measure anonymous visit statistics — only if you accept. Rejecting analytics does not limit access to the site.",
      accept: "Accept analytics",
      reject: "Reject",
      privacy: "Privacy policy",
      manage: "Cookie settings",
    },
    pl: {
      title: "Ciasteczka i prywatność",
      body: "Używamy Google Analytics do anonimowych statystyk odwiedzin — tylko po Twojej zgodzie. Odrzucenie analityki nie ogranicza dostępu do strony.",
      accept: "Akceptuj analitykę",
      reject: "Odrzuć",
      privacy: "Polityka prywatności",
      manage: "Ustawienia cookies",
    },
  };

  let trackingActive = false;

  function getLang() {
    const lang = (document.documentElement.lang || "en").toLowerCase();
    return lang.startsWith("pl") ? "pl" : "en";
  }

  function getSiteContext() {
    return {
      site_language: getLang(),
      page_location: window.location.pathname,
    };
  }

  function getCopy() {
    return COPY[getLang()];
  }

  function getMeasurementId() {
    const id = window.NOTCHFLOW_ANALYTICS?.measurementId;
    if (!id || id === "G-XXXXXXXXXX" || !MEASUREMENT_ID_PATTERN.test(id)) return null;
    return id;
  }

  function getStoredConsent() {
    const value = localStorage.getItem(CONSENT_KEY);
    if (value === "accepted" || value === "rejected") return value;
    return null;
  }

  function setStoredConsent(value) {
    localStorage.setItem(CONSENT_KEY, value);
  }

  function privacyHref() {
    return getLang() === "pl" ? "/pl/privacy.html" : "/privacy.html";
  }

  function updateConsent(granted) {
    window.gtag("consent", "update", {
      analytics_storage: granted ? "granted" : "denied",
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
    });
    trackingActive = granted;
  }

  function track(eventName, params) {
    if (!trackingActive || typeof window.gtag !== "function") return;
    window.gtag("event", eventName, {
      ...getSiteContext(),
      ...params,
    });
  }

  function loadGoogleAnalytics(measurementId) {
    if (window.__notchflowGaLoaded) return;
    window.__notchflowGaLoaded = true;

    const script = document.createElement("script");
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
    document.head.appendChild(script);

    window.gtag("js", new Date());
    window.gtag("config", measurementId, {
      anonymize_ip: true,
      allow_google_signals: false,
      allow_ad_personalization_signals: false,
      send_page_view: true,
      site_language: getLang(),
      content_group: getLang() === "pl" ? "Polish site" : "English site",
    });
  }

  function hideBanner(banner) {
    banner.hidden = true;
    banner.classList.remove("is-visible");
    document.body.classList.remove("cookie-banner-open");
  }

  function showBanner(banner) {
    banner.hidden = false;
    requestAnimationFrame(() => {
      banner.classList.add("is-visible");
      document.body.classList.add("cookie-banner-open");
    });
  }

  function linkLabel(element) {
    const text = (element.textContent || "").replace(/\s+/g, " ").trim();
    if (text) return text.slice(0, 100);
    return element.getAttribute("aria-label") || element.getAttribute("href") || "unknown";
  }

  function initClickTracking() {
    document.addEventListener("click", (event) => {
      if (!trackingActive) return;

      const checkout = event.target.closest("[data-polar-checkout]");
      if (checkout) {
        track("begin_checkout", {
          product: checkout.getAttribute("data-polar-checkout"),
          link_text: linkLabel(checkout),
          page_location: window.location.pathname,
        });
        return;
      }

      const screenshotTab = event.target.closest(".screenshot-tab");
      if (screenshotTab) {
        track("select_content", {
          content_type: "screenshot_tab",
          item_id: screenshotTab.getAttribute("data-shot") || screenshotTab.textContent?.trim(),
        });
        return;
      }

      const langLink = event.target.closest(".lang-switch a[href]");
      if (langLink) {
        const target = (langLink.textContent || "").trim().toLowerCase();
        track("language_switch", {
          from_language: getLang(),
          to_language: target === "pl" ? "pl" : target === "en" ? "en" : target,
        });
        return;
      }

      const anchor = event.target.closest("a[href]");
      if (!anchor || anchor.closest(".cookie-banner")) return;

      const href = anchor.getAttribute("href") || "";
      const label = linkLabel(anchor);

      if (href.includes("github.com/Tymcio/notchflow/releases")) {
        track("download_click", {
          link_url: href,
          link_text: label,
          page_location: window.location.pathname,
        });
        return;
      }

      if (href === "#download" || anchor.classList.contains("header-cta")) {
        track("cta_click", {
          cta_type: "download",
          link_text: label,
          page_location: window.location.pathname,
        });
        return;
      }

      if (href.startsWith("http") && !href.includes(window.location.hostname)) {
        track("outbound_click", {
          link_url: href,
          link_text: label,
          page_location: window.location.pathname,
        });
        return;
      }

      if (anchor.classList.contains("btn-primary") || anchor.classList.contains("btn-lg")) {
        track("cta_click", {
          cta_type: "primary",
          link_url: href,
          link_text: label,
          page_location: window.location.pathname,
        });
      }
    });

    document.querySelector(".theme-toggle")?.addEventListener("click", () => {
      track("theme_toggle", {
        theme: document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark",
      });
    });
  }

  function initScrollTracking() {
    const thresholds = [25, 50, 75, 90];
    const fired = new Set();

    function onScroll() {
      if (!trackingActive) return;

      const doc = document.documentElement;
      const scrollable = doc.scrollHeight - window.innerHeight;
      if (scrollable <= 0) return;

      const percent = Math.round((window.scrollY / scrollable) * 100);
      thresholds.forEach((threshold) => {
        if (percent >= threshold && !fired.has(threshold)) {
          fired.add(threshold);
          track("scroll_depth", {
            percent_scrolled: threshold,
            page_location: window.location.pathname,
          });
        }
      });
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  function createBanner(measurementId) {
    const copy = getCopy();
    const banner = document.createElement("section");
    banner.className = "cookie-banner";
    banner.setAttribute("role", "dialog");
    banner.setAttribute("aria-live", "polite");
    banner.setAttribute("aria-label", copy.title);
    banner.hidden = true;

    banner.innerHTML = `
      <div class="cookie-banner-inner container">
        <div class="cookie-banner-copy">
          <h2 class="cookie-banner-title">${copy.title}</h2>
          <p class="cookie-banner-text">${copy.body}</p>
          <a class="cookie-banner-link" href="${privacyHref()}">${copy.privacy}</a>
        </div>
        <div class="cookie-banner-actions">
          <button type="button" class="btn cookie-banner-reject">${copy.reject}</button>
          <button type="button" class="btn btn-primary cookie-banner-accept">${copy.accept}</button>
        </div>
      </div>
    `;

    banner.querySelector(".cookie-banner-accept")?.addEventListener("click", () => {
      setStoredConsent("accepted");
      updateConsent(true);
      loadGoogleAnalytics(measurementId);
      track("consent_update", { consent_status: "accepted" });
      hideBanner(banner);
    });

    banner.querySelector(".cookie-banner-reject")?.addEventListener("click", () => {
      setStoredConsent("rejected");
      updateConsent(false);
      hideBanner(banner);
    });

    document.body.appendChild(banner);
    return banner;
  }

  function initManageLinks(banner) {
    document.querySelectorAll("[data-cookie-settings]").forEach((link) => {
      link.addEventListener("click", (event) => {
        event.preventDefault();
        showBanner(banner);
      });
    });
  }

  function init() {
    const measurementId = getMeasurementId();
    if (!measurementId) return;

    initClickTracking();
    initScrollTracking();

    const banner = createBanner(measurementId);
    initManageLinks(banner);

    const consent = getStoredConsent();
    if (consent === "accepted") {
      updateConsent(true);
      loadGoogleAnalytics(measurementId);
      return;
    }

    if (consent === "rejected") {
      updateConsent(false);
    } else {
      showBanner(banner);
    }
  }

  window.notchflowAnalytics = {
    track,
    isEnabled: () => trackingActive,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
