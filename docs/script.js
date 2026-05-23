// =========================================================================
// TANK ARENA — landing page enhancements
//
// The download buttons already point at github.com/.../releases/latest/download/<file>
// which works without any JS as long as a release exists.
//
// This script enhances the page when the GitHub API is reachable:
//   - shows the release tag and publish date
//   - shows the file size next to each platform button
//   - falls back gracefully when no release exists yet
// =========================================================================

const REPO = "rossille/tta";
const API_URL = `https://api.github.com/repos/${REPO}/releases/latest`;

const platformToAsset = {
  windows: /\.exe$/i,
  macos:   /\.dmg$/i,
  linux:   /\.x86_64$|\.AppImage$|\.tar\.gz$/i,
};

function humanSize(bytes) {
  if (!bytes && bytes !== 0) return "";
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  let n = bytes;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

function fmtDate(iso) {
  try {
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  } catch {
    return iso;
  }
}

function setNoReleaseState() {
  document.querySelectorAll(".dl-btn, .deploy-card").forEach((btn) => {
    btn.classList.add("dl-btn--unavailable");
    btn.setAttribute("title", "No release published yet — check back soon");
  });

  const tag = document.getElementById("release-tag");
  const date = document.getElementById("release-date");
  if (tag) tag.textContent = "No release yet";
  if (date) date.textContent = "Builds will appear here once published.";
}

async function loadRelease() {
  const tagEl  = document.getElementById("release-tag");
  const dateEl = document.getElementById("release-date");

  try {
    const res = await fetch(API_URL, { headers: { Accept: "application/vnd.github+json" } });

    if (res.status === 404) {
      setNoReleaseState();
      return;
    }
    if (!res.ok) {
      // Network OK but API errored (rate limit etc.) — leave defaults alone.
      if (dateEl) dateEl.textContent = "Latest build (live links above)";
      return;
    }

    const data = await res.json();
    const tag  = data.tag_name || "latest";
    const date = data.published_at ? fmtDate(data.published_at) : "";

    if (tagEl)  tagEl.textContent  = tag;
    if (dateEl) dateEl.textContent = date ? `Published ${date}` : "Latest build";

    // Map assets by platform regex
    const assetsByPlatform = {};
    for (const asset of data.assets || []) {
      for (const [platform, rx] of Object.entries(platformToAsset)) {
        if (rx.test(asset.name)) {
          assetsByPlatform[platform] = asset;
          break;
        }
      }
    }

    // Update file size badges on download buttons
    document.querySelectorAll(".dl-btn[data-platform]").forEach((btn) => {
      const platform = btn.getAttribute("data-platform");
      const asset = assetsByPlatform[platform];
      const fileEl = btn.querySelector(".dl-btn__file");
      if (!asset) {
        btn.classList.add("dl-btn--unavailable");
        if (fileEl) fileEl.textContent = "Not in this build";
        return;
      }
      // Point href at the actual asset URL (handles renamed files)
      btn.href = asset.browser_download_url;
      if (fileEl) fileEl.textContent = `${asset.name} · ${humanSize(asset.size)}`;
    });

    // Update deploy-card links and filenames too
    document.querySelectorAll(".deploy-card[data-platform]").forEach((card) => {
      const platform = card.getAttribute("data-platform");
      const asset = assetsByPlatform[platform];
      if (!asset) {
        card.classList.add("dl-btn--unavailable");
        const cta = card.querySelector(".deploy-card__cta");
        if (cta) cta.textContent = "Not in this build";
        return;
      }
      card.href = asset.browser_download_url;
      const fn  = card.querySelector(".deploy-card__filename");
      const cta = card.querySelector(".deploy-card__cta");
      if (fn)  fn.textContent  = `${asset.name} · ${humanSize(asset.size)}`;
      if (cta) cta.textContent = `Download ${tag} →`;
    });
  } catch (err) {
    // Offline or CORS — links still work, just leave the default copy.
    console.warn("release fetch failed", err);
    if (dateEl) dateEl.textContent = "Latest build";
  }
}

loadRelease();

// =========================================================================
// Copy-to-clipboard buttons on .install-cmd code blocks
// =========================================================================
document.querySelectorAll(".install-cmd__copy").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const target = document.getElementById(btn.dataset.target);
    if (!target) return;
    const text = target.textContent.trim();
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // Fallback for older browsers / non-https contexts
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "absolute";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); } catch {}
      document.body.removeChild(ta);
    }
    const original = btn.textContent;
    btn.textContent = "Copied!";
    btn.classList.add("copied");
    setTimeout(() => {
      btn.textContent = original;
      btn.classList.remove("copied");
    }, 1500);
  });
});
