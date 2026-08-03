// Aeterna site — progressive enhancement, navigation and ad consent.
(function () {
  "use strict";

  var root = document.documentElement;
  var nav = document.getElementById("site-nav");
  var toggle = document.getElementById("nav-toggle");
  var navLinks = document.getElementById("primary-navigation");
  var consentBanner = document.getElementById("consent-banner");
  var consentKey = "aeterna-ad-consent-v1";
  var adSlot = document.getElementById("adsense-slot");
  var releaseApi = document.querySelector("meta[name=\"release-api\"]");
  var releaseRepository = "https://github.com/ziyi127/Aeterna";

  function loadLatestRelease() {
    var localMetadata = document.querySelector('link[rel="release-data"]');
    var url = localMetadata ? localMetadata.href : releaseApi && releaseApi.content;
    if (!url) return;
    fetch(url, { headers: { Accept: "application/json" } })
      .then(function (response) { if (!response.ok) throw new Error("release request failed"); return response.json(); })
      .then(function (release) {
        if (!release.tag_name || !Array.isArray(release.assets)) return;
        var version = release.tag_name.replace(/^v/, "");
        document.querySelectorAll("[data-release-version]").forEach(function (element) { element.textContent = "v" + version; });
        document.querySelectorAll("[data-release-link]").forEach(function (element) { element.href = release.html_url || releaseRepository + "/releases"; });
        var structuredData = document.querySelector('script[type="application/ld+json"]');
        if (structuredData) {
          try {
            var data = JSON.parse(structuredData.textContent);
            data.softwareVersion = version;
            data.downloadUrl = release.html_url || releaseRepository + "/releases";
            structuredData.textContent = JSON.stringify(data);
          } catch (error) { /* Structured data is optional enhancement. */ }
        }
        var assets = { windows: "aeterna.exe", macos: "aeterna-arm64-macos", linux: "aeterna-x86_64-linux" };
        Object.keys(assets).forEach(function (platform) {
          var asset = release.assets.find(function (item) { return item.name === assets[platform]; });
          var link = document.querySelector("[data-release-asset=\"" + platform + "\"]");
          if (asset && link) link.href = asset.browser_download_url;
        });
      })
      .catch(function () { /* The static release links remain usable offline. */ });
  }

  loadLatestRelease();

  root.classList.add("js");

  function closeNav() {
    if (!nav || !toggle) return;
    nav.classList.remove("open");
    toggle.setAttribute("aria-expanded", "false");
  }

  if (nav && toggle && navLinks) {
    toggle.addEventListener("click", function () {
      var isOpen = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", String(isOpen));
    });

    navLinks.addEventListener("click", function (event) {
      if (event.target.closest("a")) closeNav();
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") closeNav();
    });
  }

  function loadAdsense() {
    if (!adSlot || document.getElementById("adsense-loader")) return;
    var script = document.createElement("script");
    script.id = "adsense-loader";
    script.async = true;
    script.crossOrigin = "anonymous";
    script.src = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-8719096658134755";
    document.head.appendChild(script);
    adSlot.hidden = false;
  }

  function setConsent(value) {
    try { localStorage.setItem(consentKey, value); } catch (error) { /* Storage is optional. */ }
    if (consentBanner) consentBanner.hidden = true;
    if (value === "accepted") loadAdsense();
  }

  function readConsent() {
    try { return localStorage.getItem(consentKey); } catch (error) { return null; }
  }

  var storedConsent = readConsent();
  if (storedConsent === "accepted") {
    loadAdsense();
  } else if (storedConsent !== "declined" && consentBanner) {
    consentBanner.hidden = false;
  }

  document.querySelectorAll("[data-consent]").forEach(function (button) {
    button.addEventListener("click", function () { setConsent(button.getAttribute("data-consent")); });
  });

  document.querySelectorAll("[data-open-consent]").forEach(function (button) {
    button.addEventListener("click", function () {
      if (consentBanner) consentBanner.hidden = false;
    });
  });

  var reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (!reducedMotion && "IntersectionObserver" in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll(".reveal").forEach(function (element) { observer.observe(element); });
  } else {
    document.querySelectorAll(".reveal").forEach(function (element) { element.classList.add("in"); });
  }
})();
