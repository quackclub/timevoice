<script lang="ts">
  import PageLayout from "../../components/PageLayout.svelte";
  import { page, router, useForm } from "@inertiajs/svelte";
  import { DateInput } from "date-picker-svelte";
  import SectionCard from "../../components/SectionCard.svelte";
  import Button from "../../components/Button.svelte";
  import FormField from "../../components/FormField.svelte";
  import Receipt from "../../components/activity/Receipt.svelte";
  import { Activity, Calendar, RefreshCw, RotateCcw } from "lucide-svelte";
  import { toDateString } from "../../lib/format";
  import { routes } from "../../lib/routes";
  import {
    KIND_COLORS,
    KIND_LABELS,
    formatClock,
    formatMinutes,
    type Estimates,
    type TimelineDay,
    type ActivityKind,
  } from "../../lib/activity";
  import {
    WEIGHT_LABELS,
    estimateByDay,
    type EstimatorEvent,
    type Weights,
  } from "../../lib/estimates";

  type ProjectStatus = {
    id: number;
    name: string;
    color: string;
    activity_synced_at: string | null;
    activity_sync_error: string | null;
    sources: boolean;
  };

  const workspaceId = $derived($page.props.auth?.workspace?.hashid);
  let days = $derived(($page.props.days as TimelineDay[]) || []);
  let estimates = $derived($page.props.estimates as Estimates);
  let estimatorEvents = $derived(
    ($page.props.estimatorEvents as EstimatorEvent[]) || [],
  );
  let projects = $derived(($page.props.projects as ProjectStatus[]) || []);
  let timeZone = $derived(($page.props.timezone as string) || "UTC");

  const initialRange = ($page.props.dateRange as {
    start: string;
    end: string;
  }) || { start: "", end: "" };

  let startDate = $state<Date | null>(
    initialRange.start ? new Date(initialRange.start + "T00:00:00") : null,
  );
  let endDate = $state<Date | null>(
    initialRange.end ? new Date(initialRange.end + "T00:00:00") : null,
  );

  let canUpdateRange = $derived(
    !!startDate && !!endDate && startDate <= endDate,
  );

  function updateRange() {
    if (!canUpdateRange || !workspaceId) return;
    router.get(routes.activity.index(workspaceId), {
      start_date: toDateString(startDate!),
      end_date: toDateString(endDate!),
    });
  }

  let syncForm = useForm({
    start_date: initialRange.start,
    end_date: initialRange.end,
  });

  function sync() {
    if (!workspaceId) return;
    $syncForm.post(routes.activity.sync(workspaceId), {
      preserveScroll: true,
    });
  }

  // Weights: defaults from the server, overrides kept per browser.
  const STORAGE_KEY = "timevoice-estimate-weights";
  function loadWeights(defaults: Weights): Weights {
    const w = { ...defaults };
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
      for (const k in w) if (typeof saved[k] === "number") w[k] = saved[k];
    } catch {
      // storage unavailable; use defaults
    }
    return w;
  }

  let weights = $state<Weights>(
    loadWeights(($page.props.estimates as Estimates)?.weights || {}),
  );

  function setWeight(key: string, raw: string) {
    const v = parseFloat(raw);
    if (Number.isNaN(v) || v < 0) return;
    weights[key] = v;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(weights));
    } catch {
      // ignore
    }
  }

  function resetWeights() {
    weights = { ...estimates.weights };
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      // ignore
    }
  }

  let live = $derived(estimateByDay(estimatorEvents, weights, timeZone));

  type Row = {
    date: string;
    billed: number;
    items: number;
    sessions: number;
    coded: number;
  };

  let rows = $derived.by<Row[]>(() => {
    const billed: Record<string, number> = {};
    for (const d of estimates?.days || []) billed[d.date] = d.billed;
    const dates = new Set([...Object.keys(billed), ...Object.keys(live)]);
    return [...dates].sort().map((date) => ({
      date,
      billed: billed[date] || 0,
      items: live[date]?.items || 0,
      sessions: live[date]?.sessions || 0,
      coded: live[date]?.coded || 0,
    }));
  });

  let totals = $derived(
    rows.reduce(
      (t, r) => ({
        billed: t.billed + r.billed,
        items: t.items + r.items,
        sessions: t.sessions + r.sessions,
        coded: t.coded + r.coded,
      }),
      { billed: 0, items: 0, sessions: 0, coded: 0 },
    ),
  );

  const METHODS = [
    { key: "items", short: "A", label: "Item weights" },
    { key: "sessions", short: "B", label: "Sessions" },
    { key: "coded", short: "C", label: "Hackatime" },
  ] as const;
  type MethodKey = (typeof METHODS)[number]["key"];
  let method = $state<MethodKey>("items");
  let methodMeta = $derived(METHODS.find((m) => m.key === method)!);

  const pct = (v: number) =>
    totals.billed > 0
      ? `${Math.round((v / totals.billed) * 100)}% of billed`
      : "";
  const hours = (s: number) => (s / 3600).toFixed(2);

  const dayLabel = (d: string, opts: Intl.DateTimeFormatOptions) =>
    new Date(d + "T12:00:00").toLocaleDateString("en-US", opts);

  // Chart geometry
  const W = 880;
  const H = 240;
  const L = 36;
  const R = 8;
  const T = 10;
  const B = 34;
  let maxHours = $derived(
    Math.max(
      1,
      Math.ceil(
        Math.max(0, ...rows.map((r) => Math.max(r.billed, r[method]))) / 3600,
      ),
    ),
  );
  let band = $derived(rows.length ? (W - L - R) / rows.length : 0);
  let barW = $derived(Math.max(3, Math.min(14, band / 2 - 3)));
  const y = (h: number) => T + (H - T - B) * (1 - h / maxHours);
  function barPath(x: number, secs: number): string {
    const h = secs / 3600;
    if (h <= 0) return "";
    const top = y(h);
    const base = y(0);
    const r = Math.min(4, base - top, barW / 2);
    return `M${x},${base} V${top + r} Q${x},${top} ${x + r},${top} H${x + barW - r} Q${x + barW},${top} ${x + barW},${top + r} V${base} Z`;
  }
  let hovered = $state<number | null>(null);
  let labelEvery = $derived(Math.max(1, Math.ceil(rows.length / 14)));

  const usedKinds = $derived.by(() => {
    const kinds = new Set<ActivityKind>();
    for (const d of days) {
      d.events.forEach((e) => kinds.add(e.kind));
      d.entries.forEach((en) => en.events.forEach((e) => kinds.add(e.kind)));
    }
    return [...kinds];
  });

  const fmtTime = (iso: string) =>
    new Date(iso)
      .toLocaleTimeString("en-US", {
        timeZone,
        hour: "numeric",
        minute: "2-digit",
      })
      .toLowerCase();

  const syncedLabel = (iso: string) =>
    new Date(iso).toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
</script>

<PageLayout
  title="Activity"
  icon={Activity}
  iconColor="text-bright-purple"
  variant="wide"
  flash={$page.props.flash}
>
  {#snippet headerActions()}
    <Button tone="purple" onclick={sync} disabled={$syncForm.processing}>
      <RefreshCw class="w-4 h-4" />
      {$syncForm.processing ? "Starting…" : "Sync activity"}
    </Button>
  {/snippet}

  <SectionCard bodyClass="p-4">
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4 items-end">
      <FormField id="activity-start" label="Start Date">
        {#snippet children({ describedBy })}
          <div class="date-input-gruvbox" aria-describedby={describedBy}>
            <DateInput
              id="activity-start"
              bind:value={startDate}
              max={endDate || undefined}
              format="yyyy-MM-dd"
              closeOnSelection={true}
            />
          </div>
        {/snippet}
      </FormField>
      <FormField id="activity-end" label="End Date">
        {#snippet children({ describedBy })}
          <div class="date-input-gruvbox" aria-describedby={describedBy}>
            <DateInput
              id="activity-end"
              bind:value={endDate}
              min={startDate || undefined}
              format="yyyy-MM-dd"
              closeOnSelection={true}
            />
          </div>
        {/snippet}
      </FormField>
      <Button tone="purple" onclick={updateRange} disabled={!canUpdateRange}>
        <Calendar class="w-4 h-4" />
        Update Range
      </Button>
    </div>
    {#if projects.length}
      <ul class="mt-4 pt-4 border-t border-bg-tertiary space-y-1 text-sm">
        {#each projects as p (p.id)}
          <li class="flex flex-wrap items-center gap-x-2">
            <span
              class="w-3 h-3 rounded-full shrink-0"
              style="background-color: {p.color}"
            ></span>
            <span class="text-fg-primary">{p.name}</span>
            <span class="text-xs text-fg-dim">
              {#if !p.sources}
                no activity sources
              {:else if p.activity_synced_at}
                synced {syncedLabel(p.activity_synced_at)}
              {:else}
                not synced yet
              {/if}
            </span>
            {#if p.activity_sync_error}
              <span
                class="text-xs text-bright-red truncate max-w-full"
                title={p.activity_sync_error}>{p.activity_sync_error}</span
              >
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </SectionCard>

  <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
    <div class="bg-bg-secondary border border-bg-tertiary rounded-[10px] p-4">
      <span class="text-sm text-fg-muted">Billed</span>
      <p class="text-2xl font-semibold tabular-nums">
        {hours(totals.billed)} h
      </p>
      <p class="text-xs text-fg-dim">time entries in range</p>
    </div>
    {#each METHODS as m (m.key)}
      <div class="bg-bg-secondary border border-bg-tertiary rounded-[10px] p-4">
        <span class="text-sm text-fg-muted">{m.short} · {m.label}</span>
        <p class="text-2xl font-semibold tabular-nums">
          {hours(totals[m.key])} h
        </p>
        <p class="text-xs text-fg-dim">{pct(totals[m.key])}</p>
      </div>
    {/each}
  </div>

  <SectionCard
    title="Billed vs estimate by day"
    description="A: each commit, PR, branch, deploy and review gets a time cost. B: events closer than the session gap count as one session, plus a lead-in. C: Hackatime coding time only."
    bodyClass="p-4"
  >
    <div class="flex flex-wrap items-center gap-4 mb-3">
      <div
        class="inline-flex border border-bg-tertiary rounded-[8px] overflow-hidden"
        role="group"
        aria-label="Estimate shown in chart"
      >
        {#each METHODS as m (m.key)}
          <button
            type="button"
            class="px-3 py-1.5 text-sm transition-colors duration-150 {method ===
            m.key
              ? 'bg-bg-tertiary text-fg-primary font-medium'
              : 'text-fg-muted hover:bg-bg-tertiary/50'}"
            aria-pressed={method === m.key}
            onclick={() => (method = m.key)}>{m.short} · {m.label}</button
          >
        {/each}
      </div>
      <div class="flex gap-4 text-xs text-fg-muted">
        <span class="flex items-center gap-1.5"
          ><span class="w-2.5 h-2.5 rounded-[2px] bg-[#2a78d6]"
          ></span>Billed</span
        >
        <span class="flex items-center gap-1.5"
          ><span class="w-2.5 h-2.5 rounded-[2px] bg-[#eb6834]"></span>Estimate {methodMeta.short}</span
        >
      </div>
    </div>

    {#if rows.length === 0}
      <p class="text-sm text-fg-muted py-8 text-center">
        No time entries or activity in this range. Add activity sources to a
        project, then sync.
      </p>
    {:else}
      <div class="relative">
        <svg
          viewBox="0 0 {W} {H}"
          class="w-full h-auto overflow-visible"
          role="img"
          aria-label="Billed versus estimated hours per day"
        >
          {#each Array.from({ length: maxHours + 1 }, (_, i) => i) as h}
            <line
              x1={L}
              x2={W - R}
              y1={y(h)}
              y2={y(h)}
              class="stroke-bg-tertiary"
              stroke-width="1"
            />
            <text
              x={L - 6}
              y={y(h) + 4}
              text-anchor="end"
              class="fill-fg-dim text-[11px]">{h}h</text
            >
          {/each}
          {#each rows as r, i (r.date)}
            {@const cx = L + band * i + band / 2}
            {#if hovered === i}
              <rect
                x={L + band * i}
                y={T}
                width={band}
                height={H - T - B}
                class="fill-bg-tertiary/40"
              />
            {/if}
            <path d={barPath(cx - barW - 1, r.billed)} fill="#2a78d6" />
            <path d={barPath(cx + 1, r[method])} fill="#eb6834" />
            {#if i % labelEvery === 0}
              <text
                x={cx}
                y={H - B + 16}
                text-anchor="middle"
                class="fill-fg-dim text-[11px]"
                >{dayLabel(r.date, { month: "short", day: "numeric" })}</text
              >
            {/if}
            <rect
              role="presentation"
              x={L + band * i}
              y={T}
              width={band}
              height={H - T - B}
              fill="transparent"
              onmouseenter={() => (hovered = i)}
              onmouseleave={() => (hovered = null)}
            />
          {/each}
        </svg>
        {#if hovered !== null && rows[hovered]}
          {@const r = rows[hovered]}
          <div
            class="absolute top-0 pointer-events-none bg-bg-secondary border border-bg-tertiary rounded-[8px] px-3 py-2 text-xs shadow-lg whitespace-nowrap"
            style="left: {Math.min(
              ((L + band * hovered + band) / W) * 100,
              75,
            )}%"
          >
            <p class="font-semibold text-fg-primary mb-1">
              {dayLabel(r.date, {
                weekday: "short",
                month: "short",
                day: "numeric",
              })}
            </p>
            <p>
              <span class="inline-block w-2 h-2 rounded-[2px] bg-[#2a78d6] mr-1"
              ></span>Billed {formatClock(r.billed)}
            </p>
            <p>
              <span class="inline-block w-2 h-2 rounded-[2px] bg-[#eb6834] mr-1"
              ></span>Estimate {methodMeta.short}
              {formatClock(r[method])}
            </p>
          </div>
        {/if}
      </div>

      <div class="overflow-x-auto mt-4">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-fg-muted">
              <th class="text-left font-medium py-2 pr-4">Day</th>
              <th class="text-right font-medium py-2 px-2">Billed</th>
              <th class="text-right font-medium py-2 px-2">A · items</th>
              <th class="text-right font-medium py-2 px-2">B · sessions</th>
              <th class="text-right font-medium py-2 pl-2">C · coded</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-bg-tertiary tabular-nums">
            {#each rows as r (r.date)}
              <tr>
                <td class="py-1.5 pr-4 whitespace-nowrap text-fg-secondary"
                  >{dayLabel(r.date, {
                    weekday: "short",
                    month: "short",
                    day: "numeric",
                  })}</td
                >
                {#each [r.billed, r.items, r.sessions, r.coded] as v, j}
                  <td
                    class="py-1.5 text-right {j === 0
                      ? 'px-2 text-fg-primary'
                      : 'px-2 text-fg-muted'}"
                    title={j > 0 && r.billed
                      ? `${Math.round((v / r.billed) * 100)}% of billed`
                      : undefined}>{v ? formatClock(v) : "—"}</td
                  >
                {/each}
              </tr>
            {/each}
          </tbody>
          <tfoot>
            <tr
              class="font-semibold border-t-2 border-bg-tertiary tabular-nums"
            >
              <td class="py-2 pr-4">Total</td>
              <td class="py-2 px-2 text-right">{formatClock(totals.billed)}</td>
              <td class="py-2 px-2 text-right">{formatClock(totals.items)}</td>
              <td class="py-2 px-2 text-right"
                >{formatClock(totals.sessions)}</td
              >
              <td class="py-2 pl-2 text-right">{formatClock(totals.coded)}</td>
            </tr>
          </tfoot>
        </table>
      </div>
    {/if}
  </SectionCard>

  <SectionCard
    title="Estimate assumptions"
    description="Minutes unless stated. Changes apply live and are saved in this browser."
    bodyClass="p-4"
  >
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-3">
      {#each Object.entries(WEIGHT_LABELS) as [key, [label, note]] (key)}
        <label class="flex items-start justify-between gap-3 text-sm">
          <span>
            <span class="text-fg-primary">{label}</span>
            <span class="block text-xs text-fg-dim">{note}</span>
          </span>
          <input
            type="number"
            min="0"
            step="any"
            value={weights[key]}
            oninput={(e) => setWeight(key, e.currentTarget.value)}
            class="w-20 shrink-0 bg-bg-primary border border-bg-tertiary rounded-[8px] px-2 py-1 text-right font-mono text-fg-primary focus:outline-none focus:border-bright-purple"
          />
        </label>
      {/each}
    </div>
    <div class="mt-4">
      <Button variant="secondary" onclick={resetWeights}>
        <RotateCcw class="w-4 h-4" />
        Reset to defaults
      </Button>
    </div>
  </SectionCard>

  <SectionCard title="Timeline" bodyClass="p-4">
    {#if usedKinds.length}
      <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-fg-muted mb-3">
        {#each usedKinds as k (k)}
          <span class="flex items-center gap-1.5"
            ><span
              class="w-2 h-2 rounded-[2px]"
              style="background-color: {KIND_COLORS[k]}"
            ></span>{KIND_LABELS[k]}</span
          >
        {/each}
      </div>
    {/if}
    {#if days.length === 0}
      <p class="text-sm text-fg-muted py-6 text-center">Nothing in range.</p>
    {:else}
      <div class="divide-y divide-bg-tertiary">
        {#each days as day (day.date)}
          <section class="py-4">
            <header class="flex items-baseline justify-between gap-3 mb-2">
              <h3
                class="font-semibold {day.entries.length
                  ? 'text-fg-primary'
                  : 'text-fg-muted font-normal'}"
              >
                {dayLabel(day.date, {
                  weekday: "short",
                  month: "short",
                  day: "numeric",
                })}
              </h3>
              <span class="text-xs text-fg-dim font-mono tabular-nums">
                {#if day.coded_seconds}
                  <span style="color: {KIND_COLORS.coding}"
                    >{formatMinutes(day.coded_seconds)} coded</span
                  > ·
                {/if}
                {day.entries.length
                  ? `${formatClock(day.billed_seconds)} tracked`
                  : "no tracked time"}
              </span>
            </header>

            {#each day.entries as entry (entry.id)}
              <div class="mb-2">
                <div class="flex items-baseline justify-between gap-3">
                  <div class="min-w-0">
                    <p class="font-medium text-fg-primary">
                      {entry.description}
                    </p>
                    <p class="text-xs text-fg-dim">
                      {fmtTime(entry.start_at)} – {entry.end_at
                        ? fmtTime(entry.end_at)
                        : "running"}
                      {#if entry.project}
                        · <span style="color: {entry.project.color}"
                          >{entry.project.name}</span
                        >
                      {/if}
                    </p>
                  </div>
                  <span class="text-sm font-mono tabular-nums text-fg-muted"
                    >{formatClock(entry.duration_seconds)}</span
                  >
                </div>
                {#if entry.events.length}
                  <ul class="mt-1 ml-1 pl-3 border-l-2 border-bg-tertiary">
                    {#each entry.events as event (event.id)}
                      <Receipt {event} {timeZone} />
                    {/each}
                  </ul>
                {/if}
              </div>
            {/each}

            {#if day.events.length}
              {#if day.entries.length}
                <p class="text-xs text-fg-dim mt-2 mb-1">
                  Other activity this day
                </p>
              {/if}
              <ul class="ml-1 pl-3 border-l-2 border-bg-tertiary">
                {#each day.events as event (event.id)}
                  <Receipt {event} {timeZone} />
                {/each}
              </ul>
            {/if}
          </section>
        {/each}
      </div>
    {/if}
  </SectionCard>
</PageLayout>
