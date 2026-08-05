// Aeterna site — progressive enhancement and latest release metadata.
(function () {
  "use strict";

  var root = document.documentElement;
  var nav = document.getElementById("site-nav");
  var toggle = document.getElementById("nav-toggle");
  var navLinks = document.getElementById("primary-navigation");
  var releaseApi = document.querySelector("meta[name=\"release-api\"]");
  var releaseRepository = "https://github.com/ziyi127/Aeterna";
  var consentBanner = document.getElementById("consent-banner");
  var consentKey = "aeterna_ad_preference";

  function readCookie(name) {
    var match = document.cookie.match(new RegExp("(?:^|;\\s*)" + name + "=([^;]*)"));
    return match ? decodeURIComponent(match[1]) : null;
  }

  function saveAdPreference(value) {
    document.cookie = consentKey + "=" + encodeURIComponent(value) + "; max-age=31536000; path=/; SameSite=Lax";
  }

  function disableAds() {
    saveAdPreference("declined");
    if (consentBanner) consentBanner.hidden = true;
  }

  function acceptAds() {
    saveAdPreference("accepted");
    if (consentBanner) consentBanner.hidden = true;
  }

  function loadLatestRelease() {
    var localMetadata = document.querySelector('link[rel="release-data"]');
    var url = localMetadata ? localMetadata.href : releaseApi && releaseApi.content;
    if (!url) return;

    fetch(url, { headers: { Accept: "application/json" } })
      .then(function (response) {
        if (!response.ok) throw new Error("release request failed");
        return response.json();
      })
      .then(function (release) {
        if (!release.tag_name || !Array.isArray(release.assets)) return;
        var version = release.tag_name.replace(/^v/, "");
        document.querySelectorAll("[data-release-version]").forEach(function (element) {
          element.textContent = "v" + version;
        });
        document.querySelectorAll("[data-release-link]").forEach(function (element) {
          element.href = release.html_url || releaseRepository + "/releases";
        });

        var structuredData = document.querySelector('script[type="application/ld+json"]');
        if (structuredData) {
          try {
            var data = JSON.parse(structuredData.textContent);
            data.softwareVersion = version;
            data.downloadUrl = release.html_url || releaseRepository + "/releases";
            structuredData.textContent = JSON.stringify(data);
          } catch (error) { /* Structured data is optional enhancement. */ }
        }

        var assets = {
          windows: "aeterna.exe",
          macos: "aeterna-arm64-macos",
          linux: "aeterna-x86_64-linux"
        };
        Object.keys(assets).forEach(function (platform) {
          var asset = release.assets.find(function (item) { return item.name === assets[platform]; });
          var link = document.querySelector("[data-release-asset=\"" + platform + "\"]");
          if (asset && link) link.href = asset.browser_download_url;
        });
      })
      .catch(function () { /* Static release links remain usable on failure. */ });
  }

  function closeNav() {
    if (!nav || !toggle) return;
    nav.classList.remove("open");
    toggle.setAttribute("aria-expanded", "false");
  }

  root.classList.add("js");
  loadLatestRelease();

  if (consentBanner && !readCookie(consentKey)) consentBanner.hidden = false;
  document.querySelectorAll("[data-ad-preference]").forEach(function (button) {
    button.addEventListener("click", function () {
      if (button.getAttribute("data-ad-preference") === "declined") disableAds();
      else acceptAds();
    });
  });

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
