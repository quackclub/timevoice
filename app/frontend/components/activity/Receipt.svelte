<script lang="ts">
  import {
    KIND_COLORS,
    KIND_LABELS,
    formatClock,
    receiptDetail,
    type ActivityEvent,
  } from "../../lib/activity";

  interface Props {
    event: ActivityEvent;
    timeZone: string;
  }

  let { event, timeZone }: Props = $props();

  const fmtTime = (iso: string) =>
    new Date(iso)
      .toLocaleTimeString("en-US", {
        timeZone,
        hour: "numeric",
        minute: "2-digit",
      })
      .toLowerCase();

  let color = $derived(KIND_COLORS[event.kind]);
  let refText = $derived(
    event.kind === "coding"
      ? formatClock(event.duration_seconds || 0)
      : event.ref || "",
  );
  let message = $derived.by(() => {
    if (event.kind === "coding")
      return `${fmtTime(event.at)} – ${event.ended_at ? fmtTime(event.ended_at) : ""}`;
    if (event.kind === "pr") return `opened: ${event.title ?? ""}`;
    if (event.kind === "reviewed")
      return `reviewed & merged: ${event.title ?? ""}`;
    if (event.kind === "branch") return `new branch ${event.title ?? ""}`;
    return event.title ?? "";
  });
</script>

<li
  class="grid grid-cols-[3.5rem_4.5rem_4rem_1fr] max-sm:grid-cols-[4.5rem_4rem_1fr] gap-x-2 items-baseline py-0.5 text-sm {event.kind ===
  'coding'
    ? 'rounded-[6px] bg-bg-tertiary/40'
    : ''}"
>
  <span class="text-xs text-fg-dim tabular-nums max-sm:hidden"
    >{fmtTime(event.at)}</span
  >
  <span
    class="text-[10px] font-bold uppercase tracking-wide"
    style="color: {color}"
    title={KIND_LABELS[event.kind]}
    >{event.kind === "reviewed" ? "merged" : event.kind}</span
  >
  {#if event.url}
    <a
      href={event.url}
      target="_blank"
      rel="noopener noreferrer"
      class="font-mono text-xs truncate hover:underline"
      style="color: {color}">{refText}</a
    >
  {:else}
    <span class="font-mono text-xs truncate" style="color: {color}"
      >{refText}</span
    >
  {/if}
  <span class="min-w-0 text-fg-primary break-words">{message}</span>
  <span class="col-start-4 max-sm:col-start-3 text-xs text-fg-dim break-words"
    >{receiptDetail(event)}</span
  >
</li>
