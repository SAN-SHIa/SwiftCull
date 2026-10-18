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
const featurePanel = document.querySelector("#feature-panel");
const featureScreenshot = document.querySelector("#feature-screenshot");
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
  heroZoom.dataset.zoom = source;
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
function renderFeature() {
  const feature = features[selectedFeature];
  const active = featureTabs.find((tab) => tab.dataset.feature === selectedFeature);
  featureTabs.forEach((tab) => {
    const selected = tab === active;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  featurePanel.setAttribute("aria-labelledby", active.id);
  const title = document.querySelector("#feature-title");
  const description = document.querySelector("#feature-description");
  title.dataset.i18n = `feature.${selectedFeature}.title`;
  description.dataset.i18n = `feature.${selectedFeature}.description`;
  title.textContent = t(title.dataset.i18n);
  description.textContent = t(description.dataset.i18n);
  const shortcuts = document.querySelector("#feature-shortcut");
  shortcuts.replaceChildren();
  feature.keys.forEach((key, index) => {
    const value = document.createElement(selectedFeature === "frame" ? "span" : "kbd");
    if (selectedFeature === "frame") value.className = "feature-fact";
    value.textContent = key;
    shortcuts.append(value, document.createTextNode(t(`feature.${selectedFeature}.key${index + 1}`)));
  });
  const source = `./assets/${feature.image}.webp`;
  if (featureScreenshot.getAttribute("src") !== source) featureScreenshot.src = source;
  featureScreenshot.alt = t(`feature.${selectedFeature}.alt`);
  const zoom = featureScreenshot.closest("[data-zoom]");
  zoom.dataset.zoom = source;
  zoom.dataset.zoomAlt = featureScreenshot.alt;
}
function selectFeature(button, focus = false) {
  selectedFeature = button.dataset.feature;
  renderFeature();
  if (focus) {
    button.focus({ preventScroll: true });
    button.scrollIntoView({ behavior: "instant", block: "nearest", inline: "nearest" });
  }
}

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
