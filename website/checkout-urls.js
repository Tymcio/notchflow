// Polar checkout URLs — replace after creating products in Polar dashboard.
// See docs/polar-setup.md
var NOTCHFLOW_CHECKOUT = {
  lifetime: "https://buy.polar.sh/notchflow/lifetime",
  annual: "https://buy.polar.sh/notchflow/annual",
};

(function () {
  document.querySelectorAll("[data-polar-checkout]").forEach(function (el) {
    var key = el.getAttribute("data-polar-checkout");
    if (NOTCHFLOW_CHECKOUT[key]) {
      el.href = NOTCHFLOW_CHECKOUT[key];
    }
  });
})();
