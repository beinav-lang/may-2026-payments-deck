# Slide 13 — First-Time Paying Tenants (Intake Health) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Slide 13 placeholder in `deck.html` with a "First-Time Paying Tenants" intake-health chapter — a positive, base-led growth story driven by a stacked-bar hero chart and two insight cards, all bound dynamically to `window.DATA`.

**Architecture:** Single self-contained `<section>` replacing the placeholder block, followed by one new `<script>` block holding two Chart.js IIFEs (hero new-vs-existing stacked bar + a mini account-age composition bar). All series are computed in JS from `window.DATA.ft_by_account_type` / `ft_by_account_age`, filtered to exclude the partial current month (`2026-06`). No new data, SQL, or build-step changes.

**Tech Stack:** Static HTML deck, Chart.js 4.4.1 + chartjs-plugin-datalabels 2.2.0 (already loaded via CDN), `window.DATA` global (from `data.js`). No JS unit-test framework exists in this repo — verification is by (a) a Python "oracle" that recomputes expected values from `data.js`, and (b) browser checks via the `preview_*` tools (console clean, snapshot, screenshot, and `preview_eval` reading back rendered chart datasets). This is the honest substitute for TDD given a static deck; follow it rather than inventing a fake harness.

**Spec:** `docs/superpowers/specs/2026-06-05-slide13-ft-tenants-design.md` (Approach A — "Healthy & compounding").

**Deviation from spec (intentional, baked in below):** Spec item 5 loosely states the hero spans "Jun '24 → May '26". The new-vs-existing split (`ft_by_account_type`) only exists from **Jan '25**; the earlier range exists only in the total-only `ft_by_account_age`. The hero therefore spans **Jan '25 → May '26** (17 months), which still captures *both* January new-account spikes the narrative calls out. All other spec figures reconcile exactly.

---

## Verified figures (May 2026 / `2026-05-01`) — the oracle

All confirmed against `data.js` on 2026-06-05:

| Figure | Value | Source |
|---|---|---|
| Total FT payers | **14,369** | `ft_by_account_type` sum |
| — Existing accounts | 12,744 (88.7%), 3,885 db-tenants, ratio **3.28** | `ft_by_account_type` |
| — New-paying accounts | 1,625 (11.3%), 248 db-tenants | `ft_by_account_type` |
| YoY | May '25 11,780 → **+21.98%** (+2,589) | `ft_by_account_type` |
| Peak | Apr '26 = 15,254 | `ft_by_account_type` |
| Partial June (EXCLUDE) | `2026-06-01` = 702 | `ft_by_account_type` |
| Age composition | Mature 7,838 (54.5%) · Growth 2,632 (18.3%) · Onboarding 2,110 (14.7%) · Developed 1,783 (12.4%) · Unknown 6 (0.0%) | `ft_by_account_age` |
| Per-acct expansion | Onboarding 8.15 · Growth 5.24 · Developed 3.00 · Mature 2.82 | `ft_by_segment` |
| Jan new-acct share | Jan '25 23.1% · Jan '26 22.2% · recent baseline ~11% | `ft_by_account_type` |

**Exact bucket strings (note en-dash `–` U+2013, must match verbatim in JS):**
- `ACCOUNT_PAID_SEGMENT`: `Account first-time paid this month`, `Existing account (paid before)`
- `ACCOUNT_AGE_BUCKET`: `Onboarding (0–2)`, `Growth (3–6)`, `Developed (7–12)`, `Mature (13+)`, `Unknown`

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `deck.html` (lines **3057–3070**) | Replace `<section>` | The full Slide 13 markup: head, headline, intro, 4 KPI tiles, hero chart-shell, 2 insight cards (Card 2 holds the mini canvas), takeaway strip |
| `deck.html` (new `<script>` immediately after the new `</section>`) | Add | Two Chart.js IIFEs binding to `window.DATA` |

No other files change. Do **not** touch `data.js`, SQL, `build.py`, the template repo, nav/TOC (already lists Slide 13), or any other slide.

---

## Task 1: Replace placeholder with the static section scaffold

**Files:**
- Modify: `deck.html:3057-3070` (the placeholder `<section data-slide-title="First Time Paying Tenants">…</section>`)

- [ ] **Step 1: Confirm the exact placeholder block is still at 3057–3070**

Run: `sed -n '3057,3070p' deck.html`
Expected: the `<section data-slide-title="First Time Paying Tenants">` opening, the `slide-head`/`slide-num 13`, `<h2 class="section-title">First Time Paying Tenants.</h2>`, the dashed-border Placeholder div, and the closing `</section>`. If line numbers drifted, locate via `grep -n 'First Time Paying Tenants' deck.html` and adjust.

- [ ] **Step 2: Replace the entire placeholder section**

Use Edit. `old_string` = the full current block:

```html
<section data-slide-title="First Time Paying Tenants">
  <div class="wrap">
    <div style="margin-top: 18px">
      <div class="slide-head"><div class="slide-num">13</div><div class="title-eyebrow">First Time Paying Tenants</div></div>
      <h2 class="section-title">First Time Paying Tenants.</h2>
    </div>

    <!-- Placeholder content area — to be filled with FT-tenant analysis -->
    <div style="margin-top: 80px; padding: 80px 40px; background: #f8fafc; border: 2px dashed var(--border); border-radius: 12px; text-align: center">
      <div style="font-size: 13px; font-weight: 700; letter-spacing: 1.3px; text-transform: uppercase; color: var(--muted)">Placeholder</div>
      <div style="font-size: 15px; color: var(--muted); margin-top: 10px; line-height: 1.6">Content to be added in a follow-up cycle.</div>
    </div>
  </div>
</section>
```

`new_string` = the full new section (canvases are present but render empty until Tasks 2–3):

```html
<section data-slide-title="First Time Paying Tenants">
  <div class="wrap">
    <div style="margin-top: 18px">
      <div class="slide-head"><div class="slide-num">13</div><div class="title-eyebrow">First Time Paying Tenants</div></div>
      <h2 class="section-title">First-time payers — the funnel's leading edge — grew <span class="title-accent">+22% YoY</span> to 14.4K, almost entirely from existing accounts expanding.</h2>
    </div>

    <p style="font-size: 14px; color: var(--muted); line-height: 1.65; max-width: 900px; margin: 4px 0 18px">
      First-time payers are the new tenants entering the paying base each month — the leading indicator of future volume. Intake is healthy and compounding YoY, and the engine is the installed base deepening (existing accounts adding more paying tenants), not net-new logos.
    </p>

    <!-- KPI tile strip -->
    <div class="metrics-grid">
      <div class="metric up">
        <div class="metric-label">First-time Payers · May '26</div>
        <div class="metric-num">14,369</div>
        <div class="metric-tag"><span class="pos">▲ +22% YoY</span> · peak 15.3K Apr '26</div>
      </div>
      <div class="metric up">
        <div class="metric-label">YoY Growth</div>
        <div class="metric-num">+22%</div>
        <div class="metric-tag">+2,589 vs 11,780 (May '25)</div>
      </div>
      <div class="metric up">
        <div class="metric-label">From Existing Accounts</div>
        <div class="metric-num">88.7%</div>
        <div class="metric-tag">12,744 of 14,369 · land-and-expand</div>
      </div>
      <div class="metric up">
        <div class="metric-label">Tenants / Existing Acct</div>
        <div class="metric-num">3.28</div>
        <div class="metric-tag">steady 3.3–3.6 across 2026 · expansion engine</div>
      </div>
    </div>

    <!-- Hero chart -->
    <div class="chart-shell" style="margin-top: 16px">
      <div class="ch-title">First-time paying tenants per month · new vs existing accounts <span style="font-weight: 500; color: var(--muted); font-size: 11px">· Jan '25 → May '26</span></div>
      <div class="ch-sub">Stacked bars: navy = existing accounts expanding · pink = newly-paying accounts. Datalabel = monthly total.</div>
      <div class="chart-wrap h340"><canvas id="chart-ft-newvexisting"></canvas></div>
    </div>

    <!-- Two insight cards -->
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-top: 14px">

      <!-- Card 1 · Land-and-expand -->
      <div style="padding: 16px 20px; background: rgba(22,32,80,0.06); border-left: 4px solid #162050; border-radius: 8px">
        <div style="font-size: 12px; font-weight: 800; letter-spacing: 1.2px; text-transform: uppercase; color: #162050; margin-bottom: 8px">Land-and-expand · 89% from the installed base</div>
        <div style="font-size: 13px; color: var(--text); line-height: 1.55">
          <strong>12,744 of 14,369</strong> May payers came from accounts that had paid before — existing accounts add <strong>~3.3 tenants each</strong>, steady all year.
          Net-new-account intake (<strong>1,625 · 11%</strong>) spikes every January (<strong>~22%</strong>: Jan '25 23.1%, Jan '26 22.2% — the new-year onboarding wave) then settles to ~11%.
          The read: durable, base-driven growth.
        </div>
      </div>

      <!-- Card 2 · Where intake concentrates -->
      <div style="padding: 16px 20px; background: rgba(245,158,11,0.08); border-left: 4px solid #f59e0b; border-radius: 8px">
        <div style="font-size: 12px; font-weight: 800; letter-spacing: 1.2px; text-transform: uppercase; color: #b45309; margin-bottom: 8px">Where intake concentrates</div>
        <div style="background: #fff; border: 1px solid rgba(0,0,0,0.06); border-radius: 6px; padding: 10px 12px; margin: 4px 0 10px">
          <div style="font-size: 11px; font-weight: 700; color: var(--muted); letter-spacing: 0.5px; text-transform: uppercase; margin-bottom: 6px">Account-age mix of May FT volume</div>
          <div style="height: 96px"><canvas id="chart-ft-age-comp"></canvas></div>
        </div>
        <div style="font-size: 13px; color: var(--text); line-height: 1.55">
          <strong>Mature (13+ mo) accounts = 54.5%</strong> of FT volume on sheer count — but per-account expansion runs hottest in <em>young</em> accounts:
          <strong>Onboarding 8.2</strong> and <strong>Growth 5.2</strong> tenants/acct vs Mature 2.8. New accounts land in bulk; mature accounts dominate by mass.
        </div>
      </div>

    </div>

    <!-- Takeaway strip -->
    <div style="margin-top: 12px; padding: 10px 16px; background: rgba(5,150,105,0.07); border-left: 3px solid #059669; border-radius: 6px; font-size: 12.5px; color: var(--text); line-height: 1.5">
      <span style="color: #047857; font-weight: 800">✓ Intake is a strength.</span>
      The single watch-item is net-new-account acquisition, which only moves the needle in January — a new-logo push <em>outside</em> Q1 is the clearest upside lever on this funnel's leading edge.
    </div>

  </div>
</section>
```

- [ ] **Step 3: Confirm no "Placeholder" text remains and the section is well-formed**

Run: `grep -n 'Placeholder\|Content to be added' deck.html`
Expected: no matches inside Slide 13 (the only acceptable matches, if any, are unrelated other slides — there should be none from this block).

Run: `grep -c 'chart-ft-newvexisting\|chart-ft-age-comp' deck.html`
Expected: `2` (one canvas id each).

- [ ] **Step 4: Browser check — text + tiles render, charts empty (expected)**

Start the preview server on the deck if not already running (`preview_start` with the deck.html), then:
- `preview_console_logs` → expected: no new errors (canvases empty is fine, no JS yet for them).
- `preview_snapshot` → expected: headline "First-time payers — the funnel's leading edge — grew +22% YoY to 14.4K…", the 4 tiles (14,369 / +22% / 88.7% / 3.28), both card headers ("Land-and-expand · 89%…", "Where intake concentrates"), and the takeaway strip text are all present.

- [ ] **Step 5: Commit**

```bash
git add deck.html
git commit -m "feat(slide13): replace placeholder with FT-tenant intake-health scaffold"
```

---

## Task 2: Hero stacked-bar chart (new vs existing accounts)

**Files:**
- Modify: `deck.html` — add a new `<script>` block immediately after the Slide 13 `</section>` (the line that now closes the section from Task 1; find it via `grep -n 'chart-ft-newvexisting' deck.html` then the next `</section>`).

- [ ] **Step 1: Establish the oracle — recompute expected hero series from data.js**

Run:
```bash
python3 -c "
import json
from collections import defaultdict
s=open('data.js').read(); s=s[s.index('{'):]; s=s.rsplit('}',1)[0]+'}'
D=json.loads(s)
rows=[r for r in D['ft_by_account_type'] if r['MONTH']<='2026-05-01']
months=sorted(set(r['MONTH'] for r in rows))
ex=[sum(r['TENANTS'] for r in rows if r['MONTH']==m and r['ACCOUNT_PAID_SEGMENT']=='Existing account (paid before)') for m in months]
nw=[sum(r['TENANTS'] for r in rows if r['MONTH']==m and r['ACCOUNT_PAID_SEGMENT']=='Account first-time paid this month') for m in months]
tot=[e+n for e,n in zip(ex,nw)]
print('n_months',len(months),'(expect 17)')
print('first',months[0],'last',months[-1],'(expect 2025-01-01 .. 2025-05-01? -> last must be 2026-05-01)')
print('existing',ex)
print('new     ',nw)
print('totals  ',tot)
print('last total (May 26):',tot[-1],'(expect 14369)')
"
```
Expected: `n_months 17`, `last 2026-05-01`, last total `14369`, and **no 702** appearing anywhere (June excluded).

- [ ] **Step 2: Add the hero chart IIFE**

Insert this `<script>` block right after the Slide 13 closing `</section>`:

```html
<script>
// Slide 13 · Hero — first-time paying tenants per month, new vs existing accounts.
// Source: window.DATA.ft_by_account_type. Excludes partial current month via CYCLE_MONTH.
(function() {
  document.addEventListener('DOMContentLoaded', function() {
    if (typeof Chart === 'undefined') return;
    const el = document.getElementById('chart-ft-newvexisting');
    if (!el || !window.DATA || !window.DATA.ft_by_account_type) return;

    const CYCLE_MONTH = '2026-05-01';                       // latest COMPLETE calendar month
    const rows = window.DATA.ft_by_account_type.filter(r => r.MONTH <= CYCLE_MONTH);
    const months = [...new Set(rows.map(r => r.MONTH))].sort();

    const fmt = m => {
      const d = new Date(m + 'T00:00:00');
      return d.toLocaleString('en-US', { month: 'short' }) + " '" + String(d.getFullYear()).slice(2);
    };
    const labels = months.map(fmt);

    const sumBy = seg => months.map(m =>
      rows.filter(r => r.MONTH === m && r.ACCOUNT_PAID_SEGMENT === seg)
          .reduce((a, r) => a + r.TENANTS, 0));
    const existing = sumBy('Existing account (paid before)');
    const newAcct  = sumBy('Account first-time paid this month');
    const totals   = months.map((_, i) => existing[i] + newAcct[i]);

    new Chart(el, {
      type: 'bar',
      data: {
        labels,
        datasets: [
          {
            label: 'Existing accounts (paid before)',
            data: existing, backgroundColor: '#162050', stack: 'ft',
            datalabels: { display: false }
          },
          {
            label: 'New-paying accounts',
            data: newAcct, backgroundColor: '#ff4998', stack: 'ft',
            borderRadius: { topLeft: 4, topRight: 4 }, borderSkipped: false,
            datalabels: {
              display: true, anchor: 'end', align: 'end', offset: 2,
              color: '#162050', font: { weight: 800, size: 10 },
              formatter: (v, ctx) => (totals[ctx.dataIndex] / 1000).toFixed(1) + 'K'
            }
          }
        ]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        layout: { padding: { top: 24, right: 12, bottom: 4, left: 8 } },
        plugins: {
          legend: { display: true, position: 'top', align: 'start',
            labels: { boxWidth: 14, boxHeight: 12, font: { size: 12, weight: 700 }, padding: 12, color: '#162050' } },
          datalabels: { clip: false },
          tooltip: {
            mode: 'index', intersect: false,
            callbacks: {
              footer: items => 'Total: ' + items.reduce((a, i) => a + i.parsed.y, 0).toLocaleString(),
              label: ctx => ctx.dataset.label + ': ' + ctx.parsed.y.toLocaleString()
            }
          }
        },
        scales: {
          x: { stacked: true, grid: { display: false },
               ticks: { font: { size: 10, weight: 600 }, color: '#64748b', maxRotation: 0, autoSkipPadding: 4 } },
          y: { stacked: true, beginAtZero: true, grid: { color: 'rgba(22,32,80,0.06)' },
               ticks: { font: { size: 10, weight: 600 }, color: '#94a3b8', callback: v => (v / 1000) + 'K' } }
        }
      }
    });
  });
})();
</script>
```

- [ ] **Step 3: Browser check — hero renders and matches the oracle**

Reload the preview (`preview_eval` → `window.location.reload()` if no HMR).
- `preview_console_logs` → expected: no errors.
- `preview_eval` → `(() => { const c = Chart.getChart('chart-ft-newvexisting'); return { labels: c.data.labels, existing: c.data.datasets[0].data, newAcct: c.data.datasets[1].data, lastLabel: c.data.labels[c.data.labels.length-1], n: c.data.labels.length }; })()`
  Expected: `n` = 17, `lastLabel` = `May '25`? **No** — must be `May '26`; `existing`/`newAcct` arrays equal the oracle's `existing`/`new` arrays; last `existing` = 12744, last `newAcct` = 1625.
- `preview_screenshot` → expected: navy-dominant stacked bars with a thin pink cap, total `K` labels on top, two-Januaries pink-spike visible, last bar = May '26.

- [ ] **Step 4: Commit**

```bash
git add deck.html
git commit -m "feat(slide13): hero stacked-bar (new vs existing) bound to window.DATA"
```

---

## Task 3: Mini account-age composition bar (Card 2)

**Files:**
- Modify: `deck.html` — add a second IIFE inside the same `<script>` block created in Task 2 (before its closing `</script>`).

- [ ] **Step 1: Oracle — recompute expected composition from data.js**

Run:
```bash
python3 -c "
import json
s=open('data.js').read(); s=s[s.index('{'):]; s=s.rsplit('}',1)[0]+'}'
D=json.loads(s)
rows=[r for r in D['ft_by_account_age'] if r['MONTH']=='2026-05-01' and r['ACCOUNT_AGE_BUCKET']!='Unknown']
tot=sum(r['FIRST_TIME_PAYING_TENANTS'] for r in rows)
for b in ['Mature (13+)','Growth (3–6)','Onboarding (0–2)','Developed (7–12)']:
    v=next(r['FIRST_TIME_PAYING_TENANTS'] for r in rows if r['ACCOUNT_AGE_BUCKET']==b)
    print(b, v, round(100*v/tot), '%')
print('total (excl Unknown):', tot, '(expect 14363)')
"
```
Expected: Mature 7838 54% · Growth 2632 18% · Onboarding 2110 15% · Developed 1783 12% · total 14363.

- [ ] **Step 2: Add the mini composition IIFE**

Insert directly above the closing `</script>` from Task 2:

```html
// Slide 13 · Card 2 mini — account-age composition of latest-month FT volume.
// Source: window.DATA.ft_by_account_age (CYCLE_MONTH only, excl. 'Unknown').
(function() {
  document.addEventListener('DOMContentLoaded', function() {
    if (typeof Chart === 'undefined') return;
    const el = document.getElementById('chart-ft-age-comp');
    if (!el || !window.DATA || !window.DATA.ft_by_account_age) return;

    const CYCLE_MONTH = '2026-05-01';
    const order  = ['Mature (13+)', 'Growth (3–6)', 'Onboarding (0–2)', 'Developed (7–12)'];
    const colors = { 'Mature (13+)': '#162050', 'Growth (3–6)': '#3185FC', 'Onboarding (0–2)': '#ff4998', 'Developed (7–12)': '#94a3b8' };

    const rows  = window.DATA.ft_by_account_age.filter(r => r.MONTH === CYCLE_MONTH && r.ACCOUNT_AGE_BUCKET !== 'Unknown');
    const total = rows.reduce((a, r) => a + r.FIRST_TIME_PAYING_TENANTS, 0);
    const valOf = b => { const r = rows.find(x => x.ACCOUNT_AGE_BUCKET === b); return r ? r.FIRST_TIME_PAYING_TENANTS : 0; };

    const datasets = order.map(b => ({
      label: b.replace(/\s*\(.*\)/, ''),
      data: [valOf(b)],
      backgroundColor: colors[b], stack: 'age', borderSkipped: false,
      datalabels: {
        display: () => (valOf(b) / total) > 0.10,
        color: '#fff', font: { weight: 800, size: 11 },
        formatter: () => Math.round(100 * valOf(b) / total) + '%'
      }
    }));

    new Chart(el, {
      type: 'bar',
      data: { labels: [''], datasets },
      options: {
        indexAxis: 'y',
        responsive: true, maintainAspectRatio: false,
        layout: { padding: { top: 2, right: 6, bottom: 0, left: 6 } },
        plugins: {
          legend: { display: true, position: 'bottom', align: 'start',
            labels: { boxWidth: 10, boxHeight: 10, font: { size: 10, weight: 700 }, padding: 8, color: '#162050' } },
          datalabels: { clip: false },
          tooltip: { callbacks: { label: ctx => ctx.dataset.label + ': ' + ctx.parsed.x.toLocaleString() + ' (' + Math.round(100 * ctx.parsed.x / total) + '%)' } }
        },
        scales: {
          x: { stacked: true, display: false, beginAtZero: true, max: total },
          y: { stacked: true, display: false }
        }
      }
    });
  });
})();
```

- [ ] **Step 3: Browser check — mini chart renders and matches the oracle**

Reload the preview.
- `preview_console_logs` → expected: no errors.
- `preview_eval` → `(() => { const c = Chart.getChart('chart-ft-age-comp'); return { labels: c.data.datasets.map(d=>d.label), vals: c.data.datasets.map(d=>d.data[0]) }; })()`
  Expected: labels `["Mature","Growth","Onboarding","Developed"]`, vals `[7838, 2632, 2110, 1783]`.
- `preview_screenshot` → expected: a single horizontal bar inside Card 2, navy Mature segment ~54% of width with "54%" label, then blue/pink/grey segments with their %s; legend below.

- [ ] **Step 4: Commit**

```bash
git add deck.html
git commit -m "feat(slide13): Card 2 mini account-age composition bar"
```

---

## Task 4: Full-slide verification and final commit

**Files:** none (verification only); commit only if a fix was needed.

- [ ] **Step 1: Acceptance pass against the spec**

- `preview_console_logs` → expected: zero errors across the whole deck.
- `preview_snapshot` of Slide 13 → confirm every spec acceptance item: no "Placeholder" text; headline reads "+22% YoY to 14.4K"; 4 tiles reconcile (14,369 / +22% / 88.7% / 3.28); both charts populated; takeaway strip present.
- `preview_eval` → `(() => { const c = Chart.getChart('chart-ft-newvexisting'); return c.data.labels[c.data.labels.length-1]; })()` → expected `May '26` (NOT June — confirms the partial-month exclusion).
- `preview_resize` to a narrow width (e.g. 900px) → `preview_screenshot` → confirm tiles/cards wrap gracefully and charts stay readable.

- [ ] **Step 2: Regression check on neighbors**

`preview_screenshot` of Slides 12 and the slide after 13 (the funnel-methodology / cascade content) → expected: unchanged; the new `<script>` block did not disturb adjacent layout or other charts (`Chart.getChart('chart-pm-tenure-decomp')` etc. still defined via `preview_eval`).

- [ ] **Step 3: Final commit only if Step 1–2 surfaced a fix**

```bash
git add deck.html
git commit -m "fix(slide13): polish from full-slide verification pass"
```

If no fix was needed, skip — the Task 1–3 commits already capture the work.

---

## Self-Review (completed during planning)

- **Spec coverage:** head/eyebrow ✓ (Task 1); positive H2 with non-red `title-accent` ✓; intro subhead ✓; 4 KPI tiles ✓; hero stacked bar navy+pink with total datalabel ✓ (Task 2); two insight cards ✓ (Card 1 navy/positive, Card 2 amber/neutral with optional mini chart ✓ Task 3); takeaway strip ✓. CYCLE_MONTH partial-month exclusion ✓ (Tasks 2–3 + verified Task 4). `window.DATA` dynamic binding ✓.
- **Placeholder scan:** none — every code block is complete and literal.
- **Type/id consistency:** canvas ids `chart-ft-newvexisting` (Task 1 markup ↔ Task 2 JS) and `chart-ft-age-comp` (Task 1 markup ↔ Task 3 JS) match; bucket strings use the exact en-dash forms verified from `data.js`; `CYCLE_MONTH = '2026-05-01'` is identical across both IIFEs.
- **Known deviation:** hero range Jan '25 → May '26 (data-bound), documented at top.
