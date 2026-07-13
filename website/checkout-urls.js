// Polar checkout URLs — replace after creating Checkout Links in Polar dashboard.
// See docs/polar-setup.md
var NOTCHFLOW_CHECKOUT = {
  lifetime: "https://buy.polar.sh/polar_cl_IFSZArybpJcU5Jx11XnZYRA5fGFcQgUdrU2Gv0bL3zW",
  annual: "https://buy.polar.sh/polar_cl_IFSZArybpJcU5Jx11XnZYRA5fGFcQgUdrU2Gv0bL3zW",
};

(function () {
  var PLACEHOLDER_PATH = /\/notchflow\/(lifetime|annual)$/;

  document.querySelectorAll("[data-polar-checkout]").forEach(function (el) {
    var key = el.getAttribute("data-polar-checkout");
    var url = NOTCHFLOW_CHECKOUT[key];
    if (!url) return;

    el.href = url;
    el.setAttribute("rel", "noopener noreferrer");

    if (PLACEHOLDER_PATH.test(url) && typeof console !== "undefined") {
      console.warn(
        "[NotchFlow] Polar checkout URL for \"" + key + "\" is still a placeholder. Update website/checkout-urls.js."
      );
    }
  });

  var params = new URLSearchParams(window.location.search);
  var purchased = params.get("purchased");
  if (purchased !== "lifetime" && purchased !== "annual") return;

  var isPL =
    document.documentElement.lang === "pl" ||
    window.location.pathname.indexOf("/pl/") !== -1;

  var messages = {
    en: {
      lifetime: {
        title: "Thank you for your purchase!",
        body:
          "Check your email for your license key (NOTCHFLOW_…). Open NotchFlow → Settings → License, paste the key, and click Activate.",
      },
      annual: {
        title: "Thank you for your subscription!",
        body:
          "Check your email for your license key. Open NotchFlow → Settings → License, paste the key, and click Activate. Your plan renews yearly until you cancel in the Polar customer portal.",
      },
    },
    pl: {
      lifetime: {
        title: "Dziękujemy za zakup!",
        body:
          "Sprawdź e-mail z kluczem licencyjnym (NOTCHFLOW_…). Otwórz NotchFlow → Ustawienia → Licencja, wklej klucz i kliknij Aktywuj.",
      },
      annual: {
        title: "Dziękujemy za subskrypcję!",
        body:
          "Sprawdź e-mail z kluczem licencyjnym. Otwórz NotchFlow → Ustawienia → Licencja, wklej klucz i kliknij Aktywuj. Plan odnawia się co rok — anulujesz w portalu klienta Polar.",
      },
    },
  };

  var msg = (isPL ? messages.pl : messages.en)[purchased];
  if (!msg) return;

  var main = document.querySelector("main .container");
  if (!main) return;

  var banner = document.createElement("aside");
  banner.className = "purchase-success-banner";
  banner.setAttribute("role", "status");
  banner.innerHTML =
    '<p class="purchase-success-title">' +
    msg.title +
    '</p><p class="purchase-success-text">' +
    msg.body +
    "</p>";
  main.insertBefore(banner, main.firstChild);

  params.delete("purchased");
  var query = params.toString();
  var clean =
    window.location.pathname + (query ? "?" + query : "") + window.location.hash;
  window.history.replaceState({}, "", clean);
})();
