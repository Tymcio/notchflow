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

  function getLang() {
    const lang = (document.documentElement.lang || "en").toLowerCase();
    return lang.startsWith("pl") ? "pl" : "en";
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
      return;
    }

    showBanner(banner);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
