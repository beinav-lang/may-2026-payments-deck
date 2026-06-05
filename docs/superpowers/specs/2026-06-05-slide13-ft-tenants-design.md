# Slide 13 — First-Time Paying Tenants (Intake Health) · Design Spec

- **Date:** 2026-06-05
- **Deck:** May 2026 Tenant Payments review (`~/Projects/may_2026_payments_deck/deck.html`)
- **Cycle:** 2026-05 (Apr 25 → May 24 cadence; FT datasets are calendar-month grain, latest **complete** month = May 2026 / `2026-05-01`)
- **Status:** Approved — Approach A ("Healthy & compounding")

## Purpose

Replace the Slide 13 placeholder (`deck.html:3057`) with a dedicated "First-Time Paying Tenants" chapter. Slides 8–9 already own FT-tenant *payment-method* behavior (card vs ACH; why card share slid). Slide 13 takes the distinct **intake-health / volume** angle: FT payers as the leading indicator of payments growth — how many enter the base each cycle, the trend, and where they come from.

## Angle decision

- Chosen: **Intake health / volume**. (Rejected alternates: "FT-vs-returning economics", "speed to first payment".)
- Framing lean: **"Healthy & compounding"** — growth is real *and* base-led, with a soft watch-item on net-new acquisition. Positive accent, not the red/decline framing of Slides 8–9.

## Data sources (all already on disk; no new Snowflake pull)

From `window.DATA` (loaded via `data.js`):

| Key | Columns used | Feeds |
|---|---|---|
| `ft_by_account_type` | MONTH, ACCOUNT_PAID_SEGMENT ∈ {`Account first-time paid this month`, `Existing account (paid before)`}, TENANTS, DBTENANTS | New-vs-existing split → **hero chart** + tiles |
| `ft_by_account_age` | MONTH, ACCOUNT_AGE_BUCKET ∈ {Onboarding (0–2), Growth (3–6), Developed (7–12), Mature (13+)}, FIRST_TIME_PAYING_TENANTS | Total intake + **account-age composition** |
| `ft_by_segment` | MONTH, ACCOUNT_AGE_BUCKET, TENANTS, DBTENANTS | Per-account **expansion ratio** = TENANTS / DBTENANTS |

### Key figures (May 2026 / `2026-05-01`, verified from CSVs)

- Total FT payers: **14,369** (= 1,625 new-acct + 12,744 existing-acct; reconciles with `ft_by_account_age` bucket sum).
- YoY: May '25 = 11,780 → **+22%** (+2,589; precise 21.98%).
- Peak was Apr '26 = 15,254; MoM dip is seasonal (Dec troughs, Jan spikes) — YoY is the clean read.
- From existing accounts: 12,744 = **88.7%**; new-paying accounts: 1,625 = 11.3%.
- Existing-account expansion: 12,744 / 3,885 accts = **3.28 tenants/acct** (steady 3.3–3.6 across 2026).
- New-account share spikes every **January**: Jan '25 23.1%, Jan '26 22.2%; baseline ~11–12%.
- Account-age composition (share of FT): Mature **54.5%** (7,838) · Growth 18.3% (2,632) · Onboarding 14.7% (2,110) · Developed 12.4% (1,783).
- Per-account expansion by age (`ft_by_segment`, May): Onboarding **8.15** · Growth **5.24** · Developed 3.00 · Mature 2.82 tenants/acct.

## Slide structure (replaces placeholder, mirrors Slide 9 rhythm)

1. **slide-head** — num `13` + eyebrow "First Time Paying Tenants".
2. **H2 (`section-title`)** — *"First-time payers — the funnel's leading edge — grew `+22% YoY` to `14.4K`, almost entirely from existing accounts expanding."* (positive `title-accent`, **not** red.)
3. **Intro subhead** (muted, ≤2 lines) — FT payers = the new payers entering the base each cycle (leading indicator of future volume); intake is healthy & compounding YoY; the engine is the installed base deepening, not net-new logos.
4. **KPI tile strip** (4 tiles, reuse deck stat-tile style):
   - FT payers · May '26 = **14,369**
   - YoY = **+22%** (vs 11,780)
   - From existing accts = **88.7%** (12,744)
   - Expansion = **~3.3** tenants/acct
5. **Hero chart** (`chart-shell` → `ch-title` → `chart-wrap` → canvas) — *"First-time paying tenants per month · new vs existing accounts."* **Stacked bar**, Jun '24 → **May '26**. Series: Existing accounts (navy `#162050`, bottom of stack) + New-paying accounts (pink `#ff4998`, top); **total datalabel** on top of each bar. Source: `ft_by_account_type`.
6. **Two insight cards** (CSS grid `1fr / 1fr`, Slide-9 driver-card inline style):
   - **Card 1 · "Land-and-expand · 89% from the installed base"** (navy/positive left border) — 12,744 of 14,369 May payers came from accounts that had paid before; existing accounts add ~3.3 tenants each, steady all year. Net-new-account intake (1,625, 11%) spikes every January (~22% — new-year onboarding wave) then settles. Read: durable, base-driven growth.
   - **Card 2 · "Where intake concentrates"** (amber/neutral left border) — Mature (13+) = 54.5% of FT volume on sheer count, but per-account expansion is hottest in young accounts: Onboarding 8.2, Growth 5.2 vs Mature 2.8 tenants/acct. Optional mini stacked bar = account-age composition (source `ft_by_account_age` / `ft_by_segment`).
7. **Takeaway strip** (soft, one line, deck "insight + WHY" ethos) — intake is a strength; the single watch-item is net-new-account acquisition, which only moves the needle in January — a new-logo push outside Q1 is the upside lever.

## Data binding & gotchas

- **Bind to `window.DATA.<key>` dynamically**, computing arrays in JS — follows the template header's stated migrate-to-`window.DATA` intent (`deck.html:18–19`). New slide → no legacy inline array to preserve.
- **CRITICAL — exclude the partial current month.** `2026-06` holds only 702 FT (month in progress). Define `const CYCLE_MONTH = '2026-05';` and filter rows to `MONTH <= CYCLE_MONTH + '-01'`. Without this the trend shows a false cliff. (Parameterizing this in `build.py` is out of scope.)
- Reuse existing CSS classes: `slide-head`, `slide-num`, `title-eyebrow`, `section-title`, `title-accent`, `chart-shell`, `ch-title`, `chart-wrap`; the driver-card inline-style pattern from Slide 9; the deck's KPI stat-tile component (match Slide 3 / KPI slides).
- Chart.js 4.4.1 + chartjs-plugin-datalabels 2.2.0; IIFE on `DOMContentLoaded`; deck color palette.

## Acceptance criteria

- Placeholder block (`deck.html:3057–3070`) fully replaced; no "Placeholder" text remains.
- Deck renders with no console errors; hero (and optional mini) chart populate.
- Trend ends at **May '26** — no June cliff.
- Tile/headline numbers reconcile with the CSVs (14,369; +22%; 88.7%; ~3.3).
- Visual styling matches neighboring slides (8/9): fonts, colors, card pattern, tile pattern.
- No changes to other slides, nav/TOC (already lists Slide 13), SQL, or data.

## Out of scope / deferred

- No payment-method / card-share content (Slides 8–9 own it).
- No new SQL / Snowflake pull.
- **Deferred hypothesis (Slide 9, not 13):** whether the FT card-adoption decline is partly a *PM customer-segment* mix effect (Emerging / SMB / Mid-Market / Upmarket — higher segment → cheaper leases → more card-prone tenants) rather than purely PM-*age*. Worth a separate investigation. Note: the current pull's `ft_by_segment` is by account **age**, not customer segment; testing this needs a segment-grain FT query.
