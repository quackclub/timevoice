<script lang="ts">
  import {
    KIND_COLORS,
    formatClock,
    receiptDetail,
    type ActivityEvent,
  } from "../../lib/activity";

  interface Props {
    events: ActivityEvent[];
    timezone: string;
  }

  let { events, timezone }: Props = $props();

  const TAGS: Record<string, string> = {
    commit: "commit",
    main: "main",
    merge: "merge",
    pr: "PR",
    reviewed: "merged",
    branch: "branch",
    deploy: "deploy",
    coding: "coding",
  };

  function time(iso: string) {
    return new Date(iso)
      .toLocaleTimeString("en-US", {
        timeZone: timezone,
        hour: "numeric",
        minute: "2-digit",
      })
      .toLowerCase();
  }

  function refText(e: ActivityEvent) {
    if (e.kind === "coding") return formatClock(e.duration_seconds ?? 0);
    if (e.kind === "branch") return "";
    return e.ref ?? "";
  }

  function title(e: ActivityEvent) {
    if (e.kind === "pr") return `opened: ${e.title ?? ""}`;
    if (e.kind === "reviewed") return `reviewed & merged: ${e.title ?? ""}`;
    if (e.kind === "branch") return `new branch ${e.title ?? ""}`;
    if (e.kind === "coding" && e.ended_at)
      return `${time(e.at)} – ${time(e.ended_at)}`;
    return e.title ?? "";
  }
</script>

<ul class="border-l-2 border-bg-tertiary pl-3 space-y-1">
  {#each events as e (e.id)}
    <li
      class="grid grid-cols-[4.5rem_4rem_4.5rem_1fr] gap-x-2 items-baseline text-xs py-0.5 {e.kind ===
      'coding'
        ? 'rounded'
        : ''}"
      style={e.kind === "coding"
        ? `background-color: color-mix(in srgb, ${KIND_COLORS.coding} 8%, transparent)`
        : ""}
    >
      <span class="text-fg-dim font-tabular">{time(e.at)}</span>
      <span
        class="uppercase tracking-wide font-bold text-[10px]"
        style="color: {KIND_COLORS[e.kind]}">{TAGS[e.kind]}</span
      >
      {#if e.url && refText(e)}
        <a
          href={e.url}
          target="_blank"
          rel="noopener noreferrer"
          class="font-mono hover:underline"
          style="color: {KIND_COLORS[e.kind]}">{refText(e)}</a
        >
      {:else}
        <span class="font-mono" style="color: {KIND_COLORS[e.kind]}"
          >{refText(e)}</span
        >
      {/if}
      <span class="min-w-0">
        {#if e.kind === "branch" && e.url}
          new branch <a
            href={e.url}
            target="_blank"
            rel="noopener noreferrer"
            class="font-mono hover:underline">{e.title}</a
          >
        {:else}
          <span class="text-fg-primary break-words">{title(e)}</span>
        {/if}
        <span class="block text-fg-dim text-[11px]">{receiptDetail(e)}</span>
      </span>
    </li>
  {/each}
</ul>
