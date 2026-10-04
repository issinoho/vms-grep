// openvms.issinoho.com: renders the ports from projects.json and their latest
// GitHub releases. releases.json is a snapshot taken at deploy time; the GitHub
// API is then asked directly so a new release shows up without a redeploy.
(() => {
  "use strict";

  const OWNER = "issinoho";
  const CACHE_KEY = "vmsReleases.v1";
  const CACHE_MS = 30 * 60 * 1000;
  const ARCH = { I64VMS: "IA64", X86VMS: "x86-64", AXPVMS: "Alpha" };
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  let projects = [];
  let releases = {};
  let installProduct = null;

  const $ = (sel) => document.querySelector(sel);
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  // v3.12-vms3 -> { upstream: "3.12", level: 3 }
  function parseTag(tag) {
    const m = /^v(.+)-vms(\d+)$/.exec(tag || "");
    return m ? { upstream: m[1], level: Number(m[2]) } : { upstream: tag || "?", level: null };
  }

  // ISSINOHO-X86VMS-GREP-V0312-3-1.PCSI -> { arch: "x86-64", product: "GREP" }
  function parseKit(name) {
    const m = /^[A-Z0-9]+-([A-Z0-9]+VMS)-([A-Z0-9_$]+)-V.*\.PCSI$/i.exec(name);
    return m ? { arch: ARCH[m[1].toUpperCase()] || m[1], product: m[2].toUpperCase() } : null;
  }

  const fmtSize = (n) => n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.round(n / 1024) + " KB";

  function fmtDate(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return "";
    const midnight = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate());
    const days = Math.round((midnight(new Date()) - midnight(d)) / 86400000);
    const abs = d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
    const rel = days <= 0 ? "today" : days === 1 ? "yesterday" : days < 60 ? days + " days ago" : null;
    return rel ? `${abs} (${rel})` : abs;
  }

  function trimRelease(r) {
    return {
      tag_name: r.tag_name, name: r.name, published_at: r.published_at, html_url: r.html_url,
      assets: (r.assets || []).map((a) => ({ name: a.name, size: a.size, browser_download_url: a.browser_download_url })),
    };
  }

  const kitsOf = (rel) => (rel && rel.assets || []).filter((a) => parseKit(a.name));

  // ---------- ports grid ----------
  function cardHTML(p) {
    const rel = releases[p.repo];
    const repoUrl = `https://github.com/${OWNER}/${p.repo}`;
    const tags = [
      p.kind === "library" ? `<span class="tag tag-lib">library</span>` : `<span class="tag">tool</span>`,
      `<span class="tag">PCSI ${esc(p.product)}</span>`,
      p.requires ? `<span class="tag tag-req">needs ${esc(p.requires)}</span>` : "",
    ].join("");
    const head = (ver, sub) => `
      <div class="port-head">
        <div><h3 class="port-name">${esc(p.name)}</h3>
          <a class="port-repo" href="${repoUrl}">${OWNER}/${esc(p.repo)}</a></div>
        <div class="ver">${ver}<small>${sub}</small></div>
      </div>`;
    const body = `
      <div class="port-body">
        <div class="tags">${tags}</div>
        <p>${esc(p.blurb)}</p>
        ${p.try ? `<pre class="try">${esc(p.try)}</pre>` : ""}
      </div>`;

    if (!rel) {
      return head(p.status === "in progress" ? "WIP" : "&mdash;", esc(p.status || "no release yet")) + body +
        `<div class="port-wip"><p>No release yet. Follow progress on <a href="${repoUrl}">GitHub</a>.</p></div>`;
    }

    const t = parseTag(rel.tag_name);
    const sums = rel.assets.find((a) => a.name === "SHA256SUMS");
    const dls = kitsOf(rel).map((a) => {
      const k = parseKit(a.name);
      return `<a class="dl" href="${esc(a.browser_download_url)}" title="${esc(a.name)}">
        <b>${esc(k.arch)}</b><span>.PCSI &middot; ${fmtSize(a.size)}</span></a>`;
    }).join("");
    return head(esc(t.upstream), t.level ? `vms${t.level}` : esc(rel.tag_name)) + body +
      `<div class="downloads">${dls}</div>
       <div class="port-foot">
         <span class="muted">${esc(rel.tag_name)} &middot; ${fmtDate(rel.published_at)}</span>
         <a href="${esc(rel.html_url)}">Release notes</a>
         ${sums ? `<a href="${esc(sums.browser_download_url)}">SHA256SUMS</a>` : ""}
         <a href="${esc(p.upstream)}">Upstream</a>
       </div>`;
  }

  function renderPorts() {
    const grid = $("#ports-grid");
    grid.innerHTML = projects.map((p) =>
      `<article class="port" data-kind="${esc(p.kind)}" id="port-${esc(p.repo)}">${cardHTML(p)}</article>`).join("");
    applyFilter(document.querySelector(".chip.is-on").dataset.filter);

    const released = projects.filter((p) => releases[p.repo]);
    $("#stat-ports").textContent = released.length;
    $("#stat-kits").textContent = released.reduce((n, p) => n + kitsOf(releases[p.repo]).length, 0);
    renderInstall();
  }

  function applyFilter(f) {
    document.querySelectorAll(".port").forEach((el) => { el.hidden = f !== "all" && el.dataset.kind !== f; });
  }

  document.querySelectorAll(".chip").forEach((chip) => chip.addEventListener("click", () => {
    document.querySelectorAll(".chip").forEach((c) => {
      c.classList.toggle("is-on", c === chip);
      c.setAttribute("aria-selected", c === chip);
    });
    applyFilter(chip.dataset.filter);
  }));

  // ---------- install snippet ----------
  function renderInstall() {
    const avail = projects.filter((p) => kitsOf(releases[p.repo]).length);
    if (!avail.length) return;
    if (!avail.some((p) => p.repo === installProduct)) installProduct = avail[0].repo;
    const picker = $("#install-picker");
    picker.innerHTML = avail.map((p) =>
      `<button type="button" role="tab" data-repo="${esc(p.repo)}" aria-selected="${p.repo === installProduct}"
        class="${p.repo === installProduct ? "is-on" : ""}">${esc(p.product)}</button>`).join("");
    picker.querySelectorAll("button").forEach((b) => b.addEventListener("click", () => {
      installProduct = b.dataset.repo;
      renderInstall();
    }));

    const p = avail.find((x) => x.repo === installProduct);
    const kit = kitsOf(releases[p.repo])[0].name.replace(/-(I64|X86|AXP)VMS-/i, "-*-");
    const lines = [
      `<span class="dim">$! ${esc(p.name)} ${esc(releases[p.repo].tag_name)}${p.requires ? ` (needs the ${esc(p.requires)})` : ""}</span>`,
      `$ SET FILE/ATTRIBUTE=(RFM:FIX,LRL:8192,MRS:8192,RAT:NONE) -`,
      `_$    ${esc(kit)}`,
      `$ PRODUCT INSTALL ${esc(p.product)} /PRODUCER=ISSINOHO /SOURCE=dev:[dir]`,
      p.setup ? `${esc(p.setup)} <span class="dim">! per user, e.g. in LOGIN.COM</span>` : "",
    ].filter(Boolean);
    $("#install-cmds").innerHTML = lines.join("\n");
  }

  $("#install-copy").addEventListener("click", async (e) => {
    const text = $("#install-cmds").innerText.split("\n")
      .filter((l) => !l.startsWith("$!")).map((l) => l.replace(/\s*! per user.*$/, "")).join("\n");
    try {
      await navigator.clipboard.writeText(text);
      e.target.textContent = "Copied";
    } catch {
      e.target.textContent = "Select & copy";
    }
    setTimeout(() => { e.target.textContent = "Copy"; }, 1600);
  });

  // ---------- hero terminal ----------
  function heroScript() {
    const g = releases["vms-grep"];
    const gt = g ? parseTag(g.tag_name) : { upstream: "3.12", level: 3 };
    const gv = gt.upstream;
    const pcsiVer = `V${gv}-${gt.level}`;
    const pv = releases["vms-pcre2"] ? parseTag(releases["vms-pcre2"].tag_name).upstream : "10.49";
    return [
      ["out", `<span class="dim">  Welcome to OpenVMS (TM) x86_64 Operating System</span>`],
      ["out", ""],
      ["cmd", `PRODUCT INSTALL GREP /PRODUCER=ISSINOHO`],
      ["out", `<span class="dim">The following product has been selected:</span>\n    ISSINOHO X86VMS GREP ${esc(pcsiVer)}  Layered Product\n  ...\n<span class="amb">The following product has been installed:</span>\n    ISSINOHO X86VMS GREP ${esc(pcsiVer)}  Layered Product`],
      ["cmd", `@GREP$ROOT:[000000]GREP$SETUP.COM`],
      ["cmd", `grep --version`],
      ["out", `grep (GNU grep) ${esc(gv)}\n<span class="dim">Copyright (C) 2025 Free Software Foundation, Inc.\n  ...</span>\ngrep -P uses PCRE2 ${esc(pv)}`],
      ["cmd", `grep "-c" "OpenVMS" SYS$MANAGER:SYSTARTUP_VMS.COM`],
      ["out", `42`],
    ];
  }

  let termRun = 0;
  async function runTerminal() {
    const el = $("#hero-term");
    const run = ++termRun;
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const script = heroScript();
    const cursor = `<span class="cursor"></span>`;
    let html = "";
    if (reduceMotion) {
      el.innerHTML = script.map(([k, t]) => k === "cmd" ? `$ ${esc(t)}` : t).join("\n") + "\n$ " + cursor;
      return;
    }
    for (const [kind, text] of script) {
      if (run !== termRun) return;
      if (kind === "cmd") {
        html += "$ ";
        for (const ch of text) {
          if (run !== termRun) return;
          html += esc(ch);
          el.innerHTML = html + cursor;
          await sleep(28 + Math.random() * 60);
        }
        await sleep(350);
        html += "\n";
      } else {
        html += text + "\n";
        el.innerHTML = html + cursor;
        await sleep(450);
      }
      el.scrollTop = el.scrollHeight;
    }
    el.innerHTML = html + "$ " + cursor;
  }

  // ---------- data ----------
  function readCache() {
    try {
      const c = JSON.parse(localStorage.getItem(CACHE_KEY));
      return c && Date.now() - c.at < CACHE_MS ? c.releases : null;
    } catch { return null; }
  }
  function writeCache(r) {
    try { localStorage.setItem(CACHE_KEY, JSON.stringify({ at: Date.now(), releases: r })); } catch { /* private mode */ }
  }

  async function fetchLive() {
    const cached = readCache();
    if (cached) return { releases: cached, cached: true };
    const out = {};
    const results = await Promise.all(projects.map(async (p) => {
      const r = await fetch(`https://api.github.com/repos/${OWNER}/${p.repo}/releases/latest`,
        { headers: { Accept: "application/vnd.github+json" } });
      if (r.status === 404) return true; // no release yet
      if (!r.ok) throw new Error(`GitHub API ${r.status}`);
      out[p.repo] = trimRelease(await r.json());
      return true;
    }));
    if (results.every(Boolean)) writeCache(out);
    return { releases: out, cached: false };
  }

  function setSource(text) { $("#data-source").textContent = text; }

  async function main() {
    try {
      const [pj, rj] = await Promise.all([
        fetch("projects.json").then((r) => r.json()),
        fetch("releases.json").then((r) => r.ok ? r.json() : null).catch(() => null),
      ]);
      projects = pj;
      if (rj) {
        releases = rj.releases || {};
        setSource(`Snapshot from ${fmtDate(rj.generated)}; checking GitHub…`);
      }
    } catch (e) {
      $("#ports-grid").innerHTML = `<p class="muted">Could not load the project list. See the
        <a href="https://github.com/${OWNER}?tab=repositories&q=vms-">repositories on GitHub</a>.</p>`;
      return;
    }
    renderPorts();
    runTerminal();

    try {
      const live = await fetchLive();
      const changed = JSON.stringify(live.releases) !== JSON.stringify(releases);
      releases = live.releases;
      setSource(live.cached ? "Live from GitHub (cached for 30 minutes)." : "Live from GitHub releases.");
      if (changed) { renderPorts(); runTerminal(); }
    } catch {
      setSource(Object.keys(releases).length
        ? "Showing the deploy-time snapshot: GitHub's API is not available right now."
        : "GitHub's API is not available right now.");
    }
  }

  main();
})();
