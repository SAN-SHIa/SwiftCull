"use strict";

const translations = window.SWIFTCULL_TRANSLATIONS;
const root = document.documentElement;
let language = "en";
let theme = "light";
let selectedFeature = "browse";
let selectedPhoto = 0;
const ratings = [0, 0, 0, 0];

function readPreference(key, fallback) {
  try { return localStorage.getItem(key) || fallback; } catch { return fallback; }
}
function savePreference(key, value) {
  try { localStorage.setItem(key, value); } catch { /* Storage is optional. */ }
}
function t(key, values = {}) {
  let text = translations[language][key] ?? translations.en[key] ?? key;
  Object.entries(values).forEach(([name, value]) => { text = text.replaceAll(`{${name}}`, String(value)); });
  return text;
}

const themeToggle = document.querySelector(".theme-toggle");
const themeChoices = [...document.querySelectorAll("[data-theme-choice]")];
const languageToggle = document.querySelector(".language-toggle");
const heroScreenshot = document.querySelector("#hero-screenshot");
const heroZoom = heroScreenshot.closest("[data-zoom]");
const menuToggle = document.querySelector(".menu-toggle");
const mobileNav = document.querySelector("#mobile-nav");
const featureTabs = [...document.querySelectorAll("[data-feature]")];
const featureTrack = document.querySelector("#feature-track");
const featureSlides = [...document.querySelectorAll("[data-slide]")];
const featureSequence = document.querySelector(".feature-sequence");
const featureGallery = document.querySelector(".feature-gallery");
const featureDescriptions = [...document.querySelectorAll(".feature-description")];
const featureScroll = { enabled: false, start: 0, distance: 0, top: 0 };
let featureLayoutFrame = 0;
let featureScrollFrame = 0;
let pendingFeatureProgress = null;
const previousFeature = document.querySelector(".feature-previous");
const nextFeature = document.querySelector(".feature-next");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const demo = document.querySelector("#rating-demo");
const demoPhotos = [...document.querySelectorAll("[data-photo]")];
const ratingButtons = [...document.querySelectorAll("[data-rating]")];
const dialog = document.querySelector(".image-dialog");

function setTheme(value, persist = true) {
  theme = value === "dark" ? "dark" : "light";
  root.dataset.theme = theme;
  const source = `./assets/${theme}.webp`;
  if (heroScreenshot.getAttribute("src") !== source) heroScreenshot.src = source;
  heroScreenshot.alt = t(theme === "dark" ? "preview.altDark" : "preview.altLight");
  heroScreenshot.srcset = `./assets/${theme}.webp 1600w, ./assets/${theme}@2x.webp 2926w`;
  heroZoom.dataset.zoom = `./assets/${theme}@2x.webp`;
  heroZoom.dataset.zoomAlt = heroScreenshot.alt;
  themeToggle.setAttribute("aria-label", t(theme === "dark" ? "theme.toLight" : "theme.toDark"));
  themeToggle.querySelector("use").setAttribute("href", theme === "dark" ? "#i-sun" : "#i-moon");
  document.querySelector('meta[name="theme-color"]').content = theme === "dark" ? "#09090b" : "#ffffff";
  themeChoices.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.themeChoice === theme)));
  if (persist) savePreference("swiftcull-site-theme", theme);
}

const features = {
  browse: { image: "dark", keys: ["E", "1–5"] },
  filter: { image: "filter", keys: ["⌘ A", "Q"] },
  info: { image: "photo-info", keys: ["Space", "⌘ ⇧ B"] },
  frame: { image: "watermark", keys: ["15", "6"] },
  live: { image: "video-live", keys: ["V", "P"] },
};
function updateFeatureNavigation() {
  const index = featureSlides.findIndex((slide) => slide.dataset.slide === selectedFeature);
  featureTabs.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.feature === selectedFeature)));
  const activeButton = featureTabs[index];
  const navigation = activeButton.parentElement;
  const activeBounds = activeButton.getBoundingClientRect();
  const navigationBounds = navigation.getBoundingClientRect();
  if (activeBounds.left < navigationBounds.left || activeBounds.right > navigationBounds.right) {
    navigation.scrollTo({ left: activeButton.offsetLeft - navigation.offsetLeft - (navigation.clientWidth - activeButton.clientWidth) / 2, behavior: "instant" });
  }
  previousFeature.disabled = index === 0;
  nextFeature.disabled = index === featureSlides.length - 1;
  const count = document.querySelector(".feature-count");
  count.textContent = `${index + 1} / ${featureSlides.length}`;
  count.setAttribute("aria-label", t("features.position", { current: index + 1, total: featureSlides.length }));
  const distance = featureTrack.scrollWidth - featureTrack.clientWidth;
  const progress = distance > 0 ? featureTrack.scrollLeft / distance : 0;
  document.querySelector(".feature-progress > span").style.setProperty("--gallery-progress", String(progress));
}

function renderFeature() {
  featureSlides.forEach((slide) => {
    const key = slide.dataset.slide;
    const shortcuts = slide.querySelector(".feature-shortcut");
    shortcuts.replaceChildren();
    features[key].keys.forEach((label, index) => {
      const value = document.createElement(key === "frame" ? "span" : "kbd");
      if (key === "frame") value.className = "feature-fact";
      value.textContent = label;
      shortcuts.append(value, document.createTextNode(t(`feature.${key}.key${index + 1}`)));
    });
    slide.querySelector("[data-zoom]").dataset.zoomAlt = t(`feature.${key}.alt`);
  });
  updateFeatureNavigation();
}

function moveToFeature(key, behavior = reducedMotion.matches ? "instant" : "smooth") {
  selectedFeature = key;
  const slide = featureSlides.find((item) => item.dataset.slide === key);
  const padding = parseFloat(getComputedStyle(featureTrack).paddingLeft);
  const left = Math.max(0, Math.min(featureTrack.scrollWidth - featureTrack.clientWidth, slide.offsetLeft - padding));
  if (featureScroll.enabled) {
    window.scrollTo({ top: featureScroll.start + left, behavior });
  } else {
    featureTrack.scrollTo({ left, behavior });
  }
  updateFeatureNavigation();
}

function selectFeature(button, focus = false) {
  moveToFeature(button.dataset.feature);
  if (focus) {
    button.focus({ preventScroll: true });
    const nav = button.parentElement;
    nav.scrollTo({ left: button.offsetLeft - nav.offsetLeft - (nav.clientWidth - button.clientWidth) / 2, behavior: "instant" });
  }
}

let galleryFrame = 0;
featureTrack.addEventListener("scroll", () => {
  if (galleryFrame) return;
  galleryFrame = requestAnimationFrame(() => {
    galleryFrame = 0;
    const padding = parseFloat(getComputedStyle(featureTrack).paddingLeft);
    const nearest = featureSlides.reduce((best, slide) =>
      Math.abs(slide.offsetLeft - padding - featureTrack.scrollLeft) < Math.abs(best.offsetLeft - padding - featureTrack.scrollLeft) ? slide : best);
    selectedFeature = nearest.dataset.slide;
    updateFeatureNavigation();
  });
}, { passive: true });

previousFeature.addEventListener("click", () => {
  const index = featureSlides.findIndex((slide) => slide.dataset.slide === selectedFeature);
  moveToFeature(featureSlides[Math.max(0, index - 1)].dataset.slide);
});
nextFeature.addEventListener("click", () => {
  const index = featureSlides.findIndex((slide) => slide.dataset.slide === selectedFeature);
  moveToFeature(featureSlides[Math.min(featureSlides.length - 1, index + 1)].dataset.slide);
});

featureTrack.addEventListener("keydown", (event) => {
  if (event.target !== featureTrack || event.altKey || event.ctrlKey || event.metaKey) return;
  const current = featureSlides.findIndex((slide) => slide.dataset.slide === selectedFeature);
  let next;
  if (event.key === "ArrowRight") next = Math.min(current + 1, featureSlides.length - 1);
  if (event.key === "ArrowLeft") next = Math.max(current - 1, 0);
  if (event.key === "Home") next = 0;
  if (event.key === "End") next = featureSlides.length - 1;
  if (next !== undefined) { event.preventDefault(); moveToFeature(featureSlides[next].dataset.slide); }
});

// The sticky scene reserves one vertical pixel per horizontal pixel of travel.
// Wheel, touch, Page Down, and reverse scrolling all use the browser's normal
// document scroll; no wheel cancellation or body lock is involved.
function configureFeatureScroll() {
  featureLayoutFrame = 0;
  const previous = { ...featureScroll };
  const wasInside = pendingFeatureProgress !== null || (previous.enabled && Math.abs(featureGallery.getBoundingClientRect().top - previous.top) < 2);
  const previousProgress = pendingFeatureProgress ?? (previous.enabled ? featureTrack.scrollLeft / previous.distance : 0);
  pendingFeatureProgress = null;
  featureSequence.classList.remove("is-pinned");
  featureSequence.style.removeProperty("--sequence-height");
  featureGallery.style.removeProperty("--slide-width");
  featureDescriptions.forEach((description) => { description.style.minHeight = ""; });
  featureScroll.enabled = false;

  const headerHeight = document.querySelector(".header-inner").offsetHeight + 1;
  const pinTop = headerHeight + 16;
  const availableHeight = innerHeight - pinTop - 24;
  const baseWidth = featureSlides[0].offsetWidth;
  const minimumWidth = Math.min(baseWidth, 360);
  let canPin = !reducedMotion.matches && CSS.supports("position", "sticky");

  // Keep all images on a shared baseline, then shrink the gallery just enough
  // to fit below the header. A short landscape viewport uses the native rail.
  if (canPin) {
    for (let pass = 0; pass < 4; pass += 1) {
      featureDescriptions.forEach((description) => { description.style.minHeight = ""; });
      const descriptionHeight = Math.max(...featureDescriptions.map((description) => description.offsetHeight));
      featureDescriptions.forEach((description) => { description.style.minHeight = `${descriptionHeight}px`; });
      const imageHeight = featureSlides[0].querySelector(".feature-media").offsetHeight;
      const chromeHeight = featureGallery.offsetHeight - imageHeight + 16;
      const width = Math.min(baseWidth, Math.floor((availableHeight - chromeHeight) * 1280 / 779));
      if (width < minimumWidth) { canPin = false; break; }
      featureGallery.style.setProperty("--slide-width", `${width}px`);
    }
    canPin = canPin && featureGallery.offsetHeight + 16 <= availableHeight + 2;
  }

  if (canPin) {
    featureSequence.classList.add("is-pinned");
    featureSequence.style.setProperty("--pin-top", `${pinTop}px`);
    featureScroll.distance = featureTrack.scrollWidth - featureTrack.clientWidth;
    featureSequence.style.setProperty("--sequence-height", `${featureGallery.offsetHeight + featureScroll.distance}px`);
    featureScroll.start = featureSequence.getBoundingClientRect().top + scrollY - pinTop;
    featureScroll.top = pinTop;
    featureScroll.enabled = featureScroll.distance > 0;
    if (wasInside && featureScroll.enabled) {
      window.scrollTo({ top: featureScroll.start + previousProgress * featureScroll.distance, behavior: "instant" });
    }
    syncFeatureScroll();
  } else {
    featureGallery.style.removeProperty("--slide-width");
    featureDescriptions.forEach((description) => { description.style.minHeight = ""; });
    const slide = featureSlides.find((item) => item.dataset.slide === selectedFeature);
    featureTrack.scrollTo({ left: slide.offsetLeft - parseFloat(getComputedStyle(featureTrack).paddingLeft), behavior: "instant" });
  }
  const hint = document.querySelector(".feature-scroll-cue [data-i18n]");
  hint.dataset.i18n = featureScroll.enabled ? "features.hint" : "features.swipeHint";
  hint.textContent = t(hint.dataset.i18n);
  featureSlides.forEach((slide) => { slide.querySelector("img").sizes = `${slide.offsetWidth}px`; });
  updateFeatureNavigation();
}

function queueFeatureLayout(progress) {
  if (typeof progress === "number") pendingFeatureProgress = progress;
  if (!featureLayoutFrame) featureLayoutFrame = requestAnimationFrame(configureFeatureScroll);
}

function syncFeatureScroll() {
  featureScrollFrame = 0;
  if (!featureScroll.enabled) return;
  const left = Math.max(0, Math.min(featureScroll.distance, scrollY - featureScroll.start));
  if (Math.abs(featureTrack.scrollLeft - left) > 0.5) featureTrack.scrollLeft = left;
}
window.addEventListener("scroll", () => {
  if (!featureScrollFrame) featureScrollFrame = requestAnimationFrame(syncFeatureScroll);
}, { passive: true });
window.addEventListener("resize", queueFeatureLayout, { passive: true });
window.addEventListener("load", queueFeatureLayout, { once: true });
reducedMotion.addEventListener("change", queueFeatureLayout);
featureTrack.addEventListener("focusin", (event) => {
  const slide = event.target.closest("[data-slide]");
  if (featureScroll.enabled && slide && slide.dataset.slide !== selectedFeature) {
    moveToFeature(slide.dataset.slide, "instant");
  }
});

function renderRatings() {
  demoPhotos.forEach((photo, index) => {
    photo.setAttribute("aria-pressed", String(selectedPhoto === index));
    photo.setAttribute("aria-label", t("demo.select", { name: t(`photo.${index}.name`) }));
    const stars = photo.querySelector(".photo-stars");
    stars.replaceChildren();
    stars.setAttribute("aria-label", ratings[index] ? t("demo.stars", { rating: ratings[index] }) : t("demo.unrated"));
    for (let n = 0; n < ratings[index]; n += 1) {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.classList.add("icon");
      svg.setAttribute("aria-hidden", "true");
      const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
      use.setAttribute("href", "#i-star");
      svg.append(use);
      stars.append(svg);
    }
  });
  ratingButtons.forEach((button) => {
    const rating = Number(button.dataset.rating);
    button.classList.toggle("is-filled", rating <= ratings[selectedPhoto]);
    button.setAttribute("aria-pressed", String(rating === ratings[selectedPhoto]));
    button.setAttribute("aria-label", t("demo.rate", { rating }));
  });
  document.querySelector("#rating-status").textContent = t("demo.status", {
    name: t(`photo.${selectedPhoto}.name`),
    rating: ratings[selectedPhoto] ? t("demo.stars", { rating: ratings[selectedPhoto] }) : t("demo.unrated"),
  });
}

function setLanguage(value, persist = true) {
  const preserveProgress = featureScroll.enabled && Math.abs(featureGallery.getBoundingClientRect().top - featureScroll.top) < 2
    ? Math.max(0, Math.min(1, (scrollY - featureScroll.start) / featureScroll.distance)) : undefined;
  language = value === "zh" ? "zh" : "en";
  root.lang = language === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    // HTML comes exclusively from the authored local translation dictionary.
    element.innerHTML = t(element.dataset.i18n);
  });
  ["aria-label", "alt"].forEach((attribute) => {
    document.querySelectorAll(`[data-i18n-${attribute}]`).forEach((element) => {
      element.setAttribute(attribute, t(element.getAttribute(`data-i18n-${attribute}`)));
    });
  });
  document.title = t("page.title");
  document.querySelector('meta[name="description"]').content = t("page.description");
  document.querySelector('meta[property="og:title"]').content = t("page.ogTitle");
  document.querySelector('meta[property="og:description"]').content = t("page.ogDescription");
  document.querySelector('meta[property="og:locale"]').content = language === "zh" ? "zh_CN" : "en_US";
  languageToggle.textContent = t("language.name");
  languageToggle.setAttribute("aria-label", t("language.switch"));
  languageToggle.lang = language === "en" ? "zh-CN" : "en";
  menuToggle.setAttribute("aria-label", t(mobileNav.hidden ? "menu.open" : "menu.close"));
  document.querySelector("#dialog-caption").textContent = t("zoom.default");
  setTheme(theme, false);
  renderFeature();
  renderRatings();
  queueFeatureLayout(preserveProgress);
  if (persist) savePreference("swiftcull-site-language", language);
}

languageToggle.addEventListener("click", () => setLanguage(language === "en" ? "zh" : "en"));
themeToggle.addEventListener("click", () => setTheme(theme === "dark" ? "light" : "dark"));
themeChoices.forEach((button) => button.addEventListener("click", () => setTheme(button.dataset.themeChoice)));

function closeMenu() {
  mobileNav.hidden = true;
  menuToggle.setAttribute("aria-expanded", "false");
  menuToggle.setAttribute("aria-label", t("menu.open"));
  menuToggle.querySelector("use").setAttribute("href", "#i-menu");
}
menuToggle.addEventListener("click", () => {
  const opening = mobileNav.hidden;
  mobileNav.hidden = !opening;
  menuToggle.setAttribute("aria-expanded", String(opening));
  menuToggle.setAttribute("aria-label", t(opening ? "menu.close" : "menu.open"));
  menuToggle.querySelector("use").setAttribute("href", opening ? "#i-close" : "#i-menu");
});
mobileNav.querySelectorAll("a").forEach((link) => link.addEventListener("click", closeMenu));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !mobileNav.hidden) { closeMenu(); menuToggle.focus(); }
});
window.matchMedia("(min-width: 601px)").addEventListener("change", (event) => { if (event.matches) closeMenu(); });

featureTabs.forEach((button, index) => {
  button.addEventListener("click", () => selectFeature(button));
  button.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % featureTabs.length;
    if (event.key === "ArrowLeft") next = (index + featureTabs.length - 1) % featureTabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = featureTabs.length - 1;
    if (next !== undefined) { event.preventDefault(); selectFeature(featureTabs[next], true); }
  });
});

demoPhotos.forEach((photo, index) => photo.addEventListener("click", () => { selectedPhoto = index; renderRatings(); }));
ratingButtons.forEach((button) => button.addEventListener("click", () => { ratings[selectedPhoto] = Number(button.dataset.rating); renderRatings(); }));
document.querySelector(".clear-rating").addEventListener("click", () => { ratings[selectedPhoto] = 0; renderRatings(); });
demo.addEventListener("keydown", (event) => {
  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
  if (/^[0-5]$/.test(event.key)) {
    event.preventDefault(); ratings[selectedPhoto] = Number(event.key); renderRatings();
  } else if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
    event.preventDefault();
    selectedPhoto = (selectedPhoto + (event.key === "ArrowRight" ? 1 : -1) + demoPhotos.length) % demoPhotos.length;
    renderRatings(); demoPhotos[selectedPhoto].focus({ preventScroll: true });
  }
});

document.querySelectorAll("[data-zoom]").forEach((button) => button.addEventListener("click", () => {
  const image = dialog.querySelector(".dialog-image");
  image.src = button.dataset.zoom;
  image.alt = button.dataset.zoomAlt;
  document.querySelector("#dialog-caption").textContent = button.dataset.zoomAlt;
  dialog.showModal();
}));
document.querySelector(".dialog-close").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target !== dialog) return;
  const bounds = dialog.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
});

// English is the first-visit default, regardless of browser locale.
setTheme(readPreference("swiftcull-site-theme", "light"), false);
setLanguage(readPreference("swiftcull-site-language", "en"), false);

// Reveal complete content groups once, as they enter the viewport. Content remains
// visible when JavaScript or IntersectionObserver is unavailable.
const revealItems = [...document.querySelectorAll("[data-reveal]")];
let revealObserver;
function configureReveals() {
  revealObserver?.disconnect();
  if (reducedMotion.matches || !("IntersectionObserver" in window)) {
    root.classList.remove("reveal-ready");
    revealItems.forEach((element) => element.classList.add("is-visible"));
    return;
  }
  revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      revealObserver.unobserve(entry.target);
    });
  }, { threshold: 0.08, rootMargin: "0px 0px -32px 0px" });
  root.classList.add("reveal-ready");
  revealItems.forEach((element) => {
    const bounds = element.getBoundingClientRect();
    if (bounds.top < innerHeight && bounds.bottom > 0) element.classList.add("is-visible");
    if (!element.classList.contains("is-visible")) revealObserver.observe(element);
  });
}
configureReveals();
reducedMotion.addEventListener("change", configureReveals);
// Keyboard navigation must never leave focus in a visually hidden content group.
document.addEventListener("focusin", (event) => event.target.closest("[data-reveal]")?.classList.add("is-visible"));

let readingFrame = 0;
const readingProgress = document.querySelector(".reading-progress > span");
function updateReadingProgress() {
  readingFrame = 0;
  const range = document.documentElement.scrollHeight - innerHeight;
  readingProgress.style.transform = `scaleX(${range > 0 ? Math.min(1, Math.max(0, scrollY / range)) : 0})`;
}
window.addEventListener("scroll", () => {
  if (!readingFrame) readingFrame = requestAnimationFrame(updateReadingProgress);
}, { passive: true });
window.addEventListener("resize", updateReadingProgress, { passive: true });
updateReadingProgress();
