<script lang="ts" module>
  export type InvoiceOptions = {
    layout: "simple" | "detailed";
    receipt_kinds: string[];
    match: "entry" | "day";
    show_activity_only_days: boolean;
    reconciliation: boolean;
  };
</script>

<script lang="ts">
  import SelectInput from "../SelectInput.svelte";
  import {
    KIND_LABELS,
    KIND_COLORS,
    type ActivityKind,
  } from "../../lib/activity";

  interface Props {
    options: InvoiceOptions;
    receiptKinds: string[];
    idPrefix?: string;
  }

  let {
    options = $bindable(),
    receiptKinds,
    idPrefix = "opt",
  }: Props = $props();

  function toggleKind(kind: string, checked: boolean) {
    options.receipt_kinds = checked
      ? [...options.receipt_kinds.filter((k) => k !== kind), kind]
      : options.receipt_kinds.filter((k) => k !== kind);
  }
</script>

<fieldset class="space-y-4">
  <legend class="block text-sm font-medium text-fg-secondary mb-2">
    Invoice layout
  </legend>

  <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
    {#each [{ value: "simple", label: "Simple line items", hint: "One row per time entry, like before." }, { value: "detailed", label: "Detailed work log", hint: "Grouped by day with git, deploy and Hackatime receipts." }] as choice}
      <label
        class="flex items-start gap-3 p-3 rounded-[10px] border cursor-pointer transition-colors duration-150 {options.layout ===
        choice.value
          ? 'border-bright-purple bg-bg-tertiary'
          : 'border-bg-tertiary hover:bg-bg-tertiary'}"
      >
        <input
          type="radio"
          name="{idPrefix}-layout"
          value={choice.value}
          bind:group={options.layout}
          class="mt-1 text-bright-purple focus:ring-bright-purple/50"
        />
        <span>
          <span class="block text-sm font-medium text-fg-primary"
            >{choice.label}</span
          >
          <span class="block text-xs text-fg-muted">{choice.hint}</span>
        </span>
      </label>
    {/each}
  </div>

  {#if options.layout === "detailed"}
    <div>
      <span class="block text-sm font-medium text-fg-secondary mb-2"
        >Receipts to include</span
      >
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
        {#each receiptKinds as kind}
          <label class="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={options.receipt_kinds.includes(kind)}
              onchange={(e) => toggleKind(kind, e.currentTarget.checked)}
              class="w-4 h-4 rounded border-bg-tertiary text-bright-purple focus:ring-bright-purple/50"
            />
            <span
              class="w-2 h-2 rounded-sm"
              style="background-color: {KIND_COLORS[kind as ActivityKind]}"
            ></span>
            {KIND_LABELS[kind as ActivityKind] ?? kind}
          </label>
        {/each}
      </div>
    </div>

    <div>
      <label
        for="{idPrefix}-match"
        class="block text-sm font-medium text-fg-secondary mb-1"
        >Place receipts</label
      >
      <SelectInput
        id="{idPrefix}-match"
        tone="purple"
        bind:value={options.match}
      >
        <option value="entry">Under the time entry they happened during</option>
        <option value="day">By day</option>
      </SelectInput>
    </div>

    <div class="space-y-2">
      <label class="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          bind:checked={options.show_activity_only_days}
          class="w-4 h-4 rounded border-bg-tertiary text-bright-purple focus:ring-bright-purple/50"
        />
        Show days with activity but no billed time
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          bind:checked={options.reconciliation}
          class="w-4 h-4 rounded border-bg-tertiary text-bright-purple focus:ring-bright-purple/50"
        />
        Append time reconciliation page
      </label>
    </div>
  {/if}
</fieldset>
