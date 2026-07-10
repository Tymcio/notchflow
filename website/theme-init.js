(function () {
  const stored = localStorage.getItem("notchflow-theme");
  if (stored === "light" || stored === "dark") {
    document.documentElement.setAttribute("data-theme", stored);
  }
})();
