<script lang="ts">
  import PageLayout from "../../components/PageLayout.svelte";
  import Modal from "../../components/Modal.svelte";
  import Button from "../../components/Button.svelte";
  import FormField from "../../components/FormField.svelte";
  import TextInput from "../../components/TextInput.svelte";
  import TextArea from "../../components/TextArea.svelte";
  import { Link, page, router, useForm } from "@inertiajs/svelte";
  import ConfirmDeleteModal from "../../components/ConfirmDeleteModal.svelte";
  import {
    FileText,
    ArrowLeft,
    Calendar,
    Building2,
    Download,
    Mail,
    Trash2,
    Edit2,
    Check,
    X,
    ChevronDown,
    RefreshCw,
    SlidersHorizontal,
  } from "lucide-svelte";
  import { formatDate, getStatusClasses } from "../../lib/format";
  import { routes } from "../../lib/routes";
  import Turnstile from "../../components/Turnstile.svelte";
  import ReceiptList from "../../components/invoice/ReceiptList.svelte";
  import InvoiceOptionsFields, {
    type InvoiceOptions,
  } from "../../components/invoice/InvoiceOptionsFields.svelte";
  import {
    formatClock,
    formatMinutes,
    type Estimates,
    type TimelineDay,
  } from "../../lib/activity";

  const workspaceId = $derived($page.props.auth?.workspace?.hashid);

  type InvoiceLine = {
    id: number;
    description: string | null;
    qty_hours: number;
    rate_cents: number;
    amount_cents: number;
    amount: string;
    rate: string;
  };

  type Invoice = {
    id: number;
    hashid: string;
    invoice_number: number;
    status: string;
    period_start: string;
    period_end: string;
    issued_on: string | null;
    total_amount: string;
    client: {
      id: number;
      name: string;
      billing_address: string | null;
    };
    lines: InvoiceLine[];
    settings: InvoiceOptions;
  };

  let invoice = $derived($page.props.invoice as Invoice);
  let timeline = $derived(($page.props.timeline as TimelineDay[]) || []);
  let estimates = $derived(($page.props.estimates as Estimates | null) ?? null);
  let receiptKinds = $derived(($page.props.receiptKinds as string[]) || []);
  let timezone = $derived(($page.props.timezone as string) || "UTC");
  let detailed = $derived(invoice.settings?.layout === "detailed");
  let hasReceipts = $derived(
    timeline.some(
      (d) => d.events.length > 0 || d.entries.some((e) => e.events.length > 0),
    ),
  );

  let optionsModalOpen = $state(false);
  let refreshing = $state(false);
  let editOptions = $state<InvoiceOptions>({
    layout: "detailed",
    receipt_kinds: [],
    match: "entry",
    show_activity_only_days: true,
    reconciliation: false,
  });

  function openOptions() {
    editOptions = {
      ...invoice.settings,
      receipt_kinds: [...invoice.settings.receipt_kinds],
    };
    optionsModalOpen = true;
  }

  function saveOptions() {
    router.patch(
      routes.invoices.update(workspaceId, invoice.hashid),
      { invoice: { options: { ...editOptions } } },
      {
        preserveScroll: true,
        onSuccess: () => {
          optionsModalOpen = false;
        },
      },
    );
  }

  function refreshReceipts() {
    refreshing = true;
    router.post(
      routes.invoices.refreshActivity(workspaceId, invoice.hashid),
      {},
      { preserveScroll: true, onFinish: () => (refreshing = false) },
    );
  }

  function dayLabel(date: string) {
    return new Date(`${date}T12:00:00`).toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
  }

  function clockTime(iso: string | null) {
    if (!iso) return "";
    return new Date(iso)
      .toLocaleTimeString("en-US", {
        timeZone: timezone,
        hour: "numeric",
        minute: "2-digit",
      })
      .toLowerCase();
  }

  function pct(value: number) {
    if (!estimates || !estimates.totals.billed) return "";
    return `${Math.round((value / estimates.totals.billed) * 100)}% of billed`;
  }
  const userEmail = ($page.props.auth as any)?.user?.email || "";
  const isDevMode = $page.props.rails_env === "development";

  let emailModalOpen = $state(false);
  let emailRecipients = $state("");
  let emailMessage = $state("");
  let ccSelf = $state(false);
  let sending = $state(false);
  let showLetterOpenerHint = $state(false);
  let turnstileToken = $state("");
  let showDeleteModal = $state(false);
  let editingNumber = $state(false);
  let editInvoiceNumber = $state(0);
  let downloadMenuOpen = $state(false);

  function deleteInvoice() {
    router.delete(routes.invoices.delete(workspaceId, invoice.hashid), {
      onSuccess: () => {
        showDeleteModal = false;
      },
    });
  }

  function saveInvoiceNumber() {
    router.patch(
      routes.invoices.update(workspaceId, invoice.hashid),
      { invoice: { invoice_number: editInvoiceNumber } },
      {
        preserveScroll: true,
        onSuccess: () => {
          editingNumber = false;
        },
      },
    );
  }

  function openEmailModal() {
    emailRecipients = "";
    emailMessage = "";
    ccSelf = false;
    turnstileToken = "";
    emailModalOpen = true;
  }

  function startEditingInvoiceNumber() {
    editInvoiceNumber = invoice.invoice_number;
    editingNumber = true;
  }

  function cancelInvoiceNumberEdit() {
    editInvoiceNumber = invoice.invoice_number;
    editingNumber = false;
  }

  function sendEmail() {
    if (!emailRecipients.trim()) return;

    sending = true;
    router.post(
      routes.invoices.sendEmail(workspaceId, invoice.hashid),
      {
        recipients: emailRecipients,
        cc_self: ccSelf ? "true" : "false",
        message: emailMessage,
        "cf-turnstile-response": turnstileToken,
      },
      {
        onFinish: () => {
          sending = false;
          emailModalOpen = false;
          turnstileToken = "";
          if (isDevMode) {
            showLetterOpenerHint = true;
          }
        },
      },
    );
  }
</script>

<PageLayout
  title={`Invoice #${invoice.invoice_number}`}
  icon={FileText}
  iconColor="text-bright-purple"
  variant="wide"
  flash={$page.props.flash}
>
  {#snippet headerActions()}
    <div
      class="flex flex-wrap items-center justify-end gap-2 whitespace-nowrap"
    >
      {#if showLetterOpenerHint && isDevMode}
        <a
          href={routes.devTools.letterOpener}
          target="_blank"
          class="inline-flex items-center gap-2 px-4 py-2 bg-green-950 border-2 border-dashed border-green-500 text-green-400 rounded-[10px] hover:bg-green-900 transition-colors duration-150"
        >
          <Mail class="w-4 h-4" />
          View Sent Email
        </a>
      {/if}
      {#if editingNumber}
        <div class="flex items-center gap-2">
          <TextInput
            type="number"
            bind:value={editInvoiceNumber}
            tone="purple"
            class="w-24 text-sm"
            min="1"
          />
          <Button variant="secondary" type="button" onclick={saveInvoiceNumber}>
            <Check class="w-4 h-4" />
          </Button>
          <Button
            variant="ghost"
            type="button"
            onclick={cancelInvoiceNumberEdit}
          >
            <X class="w-4 h-4" />
          </Button>
        </div>
      {:else}
        <Button
          variant="secondary"
          type="button"
          onclick={startEditingInvoiceNumber}
        >
          <Edit2 class="w-4 h-4" />
          Rename
        </Button>
      {/if}
      {#if detailed}
        <Button
          variant="secondary"
          type="button"
          onclick={refreshReceipts}
          disabled={refreshing}
        >
          <RefreshCw class="w-4 h-4 {refreshing ? 'animate-spin' : ''}" />
          Refresh receipts
        </Button>
      {/if}
      <Button variant="secondary" type="button" onclick={openOptions}>
        <SlidersHorizontal class="w-4 h-4" />
        Options
      </Button>
      <Button tone="purple" type="button" onclick={openEmailModal}>
        <Mail class="w-4 h-4" />
        Email Invoice
      </Button>
      <div class="relative">
        <Button
          variant="secondary"
          type="button"
          aria-haspopup="menu"
          aria-expanded={downloadMenuOpen}
          onclick={() => (downloadMenuOpen = !downloadMenuOpen)}
        >
          <Download class="w-4 h-4" />
          Download
          <ChevronDown class="w-4 h-4 text-fg-muted" aria-hidden="true" />
        </Button>

        {#if downloadMenuOpen}
          <div
            class="absolute top-full right-0 mt-2 min-w-[12rem] rounded-[10px] overflow-hidden z-40 bg-gradient-to-b from-bg-quaternary to-bg-tertiary shadow-[0_0_0_1px_rgba(0,0,0,0.55),inset_0_1px_0_rgba(255,255,255,0.08),inset_0_-1px_0_rgba(0,0,0,0.35),0_12px_24px_-8px_rgba(0,0,0,0.55),0_4px_8px_-4px_rgba(0,0,0,0.4)]"
            role="menu"
          >
            <a
              href={routes.invoices.pdf(workspaceId, invoice.hashid)}
              target="_blank"
              role="menuitem"
              class="flex items-center gap-2 px-4 py-2.5 text-sm text-fg-primary transition-[background-color,box-shadow,transform] duration-150 hover:bg-gradient-to-b hover:from-white/[0.06] hover:to-transparent active:scale-[0.985]"
              onclick={() => (downloadMenuOpen = false)}
            >
              <FileText class="w-4 h-4" aria-hidden="true" />
              Download PDF
            </a>
            <a
              href={routes.invoices.csv(workspaceId, invoice.hashid)}
              role="menuitem"
              class="flex items-center gap-2 px-4 py-2.5 text-sm text-fg-primary transition-[background-color,box-shadow,transform] duration-150 hover:bg-gradient-to-b hover:from-white/[0.06] hover:to-transparent active:scale-[0.985] shadow-[inset_0_1px_0_rgba(0,0,0,0.4),inset_0_2px_0_-1px_rgba(255,255,255,0.05)]"
              onclick={() => (downloadMenuOpen = false)}
            >
              <Download class="w-4 h-4" aria-hidden="true" />
              Export CSV
            </a>
          </div>
        {/if}
      </div>
      <Button
        variant="secondary"
        type="button"
        onclick={() => (showDeleteModal = true)}
      >
        <Trash2 class="w-4 h-4" />
        Delete
      </Button>
      <Link href={routes.invoices.index(workspaceId)}>
        <Button variant="secondary">
          <ArrowLeft class="w-4 h-4" />
          Back
        </Button>
      </Link>
    </div>
  {/snippet}

  <div class="bg-bg-secondary border border-bg-tertiary rounded-[10px]">
    <div
      class="p-4 border-b border-bg-tertiary flex items-start justify-between gap-4"
    >
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <h3 class="font-semibold text-lg truncate">{invoice.client.name}</h3>
          <span
            class="px-2 py-0.5 text-xs rounded-full capitalize {getStatusClasses(
              invoice.status,
            )}"
          >
            {invoice.status}
          </span>
        </div>
        <div
          class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-fg-muted"
        >
          <span class="inline-flex items-center gap-2">
            <Calendar class="w-4 h-4" />
            {formatDate(invoice.period_start)} - {formatDate(
              invoice.period_end,
            )}
          </span>
          <span
            >Issued: {invoice.issued_on
              ? formatDate(invoice.issued_on)
              : "Not issued"}</span
          >
        </div>
      </div>

      <div class="text-right">
        <div class="text-sm text-fg-muted">Total</div>
        <div class="text-2xl font-semibold">{invoice.total_amount}</div>
      </div>
    </div>

    <div class="p-4 grid grid-cols-1 md:grid-cols-2 gap-4">
      <div class="bg-bg-primary border border-bg-tertiary rounded-[10px] p-4">
        <div class="flex items-center gap-2 text-fg-muted mb-2">
          <Building2 class="w-4 h-4" />
          <span class="text-sm">Client</span>
        </div>
        <div class="font-medium">{invoice.client.name}</div>
        {#if invoice.client.billing_address}
          <div class="mt-1 text-sm text-fg-muted whitespace-pre-line">
            {invoice.client.billing_address}
          </div>
        {:else}
          <div class="mt-1 text-sm text-fg-dim italic">No billing address</div>
        {/if}
      </div>

      <div class="bg-bg-primary border border-bg-tertiary rounded-[10px] p-4">
        <div class="text-sm text-fg-muted mb-2">Line Items</div>
        <div class="text-sm text-fg-muted">
          {invoice.lines.length} item{invoice.lines.length === 1 ? "" : "s"}
        </div>
      </div>
    </div>

    {#if detailed}
      <div class="border-t border-bg-tertiary p-4 space-y-2">
        <div class="flex items-baseline justify-between gap-4">
          <h3 class="font-semibold">Work log</h3>
          <span class="text-xs text-fg-muted"
            >Grouped by day ({timezone}){invoice.settings.match === "entry"
              ? " · receipts sit under the entry they happened during"
              : ""}</span
          >
        </div>

        {#if !hasReceipts}
          <div
            class="text-sm text-fg-muted bg-bg-primary border border-dashed border-bg-tertiary rounded-[10px] p-4"
          >
            No receipts yet — add GitHub repos/Hackatime projects/Workers to
            this client's projects, then Refresh receipts.
          </div>
        {/if}

        {#each timeline as day (day.date)}
          <section class="border-t border-bg-tertiary pt-3 pb-2">
            <header class="flex items-baseline justify-between gap-4 mb-2">
              <h4
                class="font-semibold {day.entries.length
                  ? 'text-fg-primary'
                  : 'text-fg-muted'}"
              >
                {dayLabel(day.date)}
              </h4>
              <span class="text-xs text-fg-muted font-tabular">
                {#if day.coded_seconds > 0}
                  <span style="color: #d6336c"
                    >{formatMinutes(day.coded_seconds)} coded</span
                  > ·
                {/if}
                {day.entries.length
                  ? `${formatClock(day.billed_seconds)} billed`
                  : "no billed time"}
              </span>
            </header>

            {#each day.entries as entry (entry.id)}
              <div class="mb-2">
                <div
                  class="grid grid-cols-[1fr_auto] sm:grid-cols-[1fr_4rem_4.5rem_4.5rem_5rem] gap-x-3 items-baseline text-sm"
                >
                  <div class="min-w-0">
                    <span class="font-medium text-fg-primary"
                      >{entry.description || "No description"}</span
                    >
                    <div
                      class="flex flex-wrap items-center gap-x-2 text-xs text-fg-muted"
                    >
                      {#if entry.project}
                        <span class="inline-flex items-center gap-1">
                          <span
                            class="w-2 h-2 rounded-full"
                            style="background-color: {entry.project.color}"
                          ></span>
                          {entry.project.name}
                        </span>
                      {/if}
                      <span class="font-tabular"
                        >{clockTime(entry.start_at)} – {clockTime(
                          entry.end_at,
                        )}</span
                      >
                    </div>
                  </div>
                  <span
                    class="hidden sm:block text-right font-tabular text-fg-muted"
                    >{formatClock(entry.duration_seconds)}</span
                  >
                  <span class="hidden sm:block text-right font-tabular"
                    >{entry.qty_hours != null
                      ? `${Number(entry.qty_hours).toFixed(2)} h`
                      : ""}</span
                  >
                  <span class="hidden sm:block text-right font-tabular"
                    >{entry.rate ?? ""}</span
                  >
                  <span class="text-right font-tabular font-semibold"
                    >{entry.amount ?? ""}</span
                  >
                </div>
                {#if entry.events.length}
                  <div class="mt-1">
                    <ReceiptList events={entry.events} {timezone} />
                  </div>
                {/if}
              </div>
            {/each}

            {#if day.events.length}
              <div class="mt-2">
                <div class="text-xs font-semibold text-fg-muted mb-1">
                  {day.entries.length
                    ? "Other activity this day"
                    : "Activity (not billed)"}
                </div>
                <ReceiptList events={day.events} {timezone} />
              </div>
            {/if}
          </section>
        {/each}
      </div>

      {#if estimates}
        <div class="border-t border-bg-tertiary p-4 space-y-4">
          <div>
            <h3 class="font-semibold">Time reconciliation</h3>
            <p class="text-xs text-fg-muted">
              Billed time compared with three estimates from the receipts. A:
              item weights per commit, PR, branch, deploy and review. B:
              activity sessions ({estimates.weights.session_gap} min gap, {estimates
                .weights.lead_in} min lead-in). C: Hackatime coding time.
            </p>
          </div>
          <div
            class="grid grid-cols-2 md:grid-cols-4 gap-px bg-bg-tertiary border border-bg-tertiary rounded-[10px] overflow-hidden"
          >
            {#each [{ label: "Billed", v: estimates.totals.billed, sub: "" }, { label: "A · Item weights", v: estimates.totals.items, sub: pct(estimates.totals.items) }, { label: "B · Sessions", v: estimates.totals.sessions, sub: pct(estimates.totals.sessions) }, { label: "C · Hackatime coded", v: estimates.totals.coded, sub: pct(estimates.totals.coded) }] as tile}
              <div class="bg-bg-primary p-3">
                <div class="text-xs uppercase tracking-wide text-fg-muted">
                  {tile.label}
                </div>
                <div class="text-xl font-semibold font-tabular">
                  {(tile.v / 3600).toFixed(2)} h
                </div>
                <div class="text-xs text-fg-muted">{tile.sub}</div>
              </div>
            {/each}
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="text-fg-muted">
                <tr class="border-b border-bg-tertiary">
                  <th class="text-left font-medium py-2">Day</th>
                  <th class="text-right font-medium py-2">Billed</th>
                  <th class="text-right font-medium py-2">A · items</th>
                  <th class="text-right font-medium py-2">B · sessions</th>
                  <th class="text-right font-medium py-2">C · coded</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-bg-tertiary font-tabular">
                {#each estimates.days as d (d.date)}
                  <tr>
                    <td class="py-1.5 whitespace-nowrap">{dayLabel(d.date)}</td>
                    {#each [d.billed, d.items, d.sessions, d.coded] as v}
                      <td class="py-1.5 text-right"
                        >{v > 0 ? formatClock(v) : "—"}</td
                      >
                    {/each}
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
      {/if}
    {:else}
      <div class="border-t border-bg-tertiary">
        <div class="p-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="text-fg-muted">
              <tr class="border-b border-bg-tertiary">
                <th class="text-left font-medium py-2">Description</th>
                <th class="text-right font-medium py-2">Hours</th>
                <th class="text-right font-medium py-2">Rate</th>
                <th class="text-right font-medium py-2">Amount</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-bg-tertiary">
              {#each invoice.lines as line}
                <tr>
                  <td class="py-3 pr-4">
                    <span class="text-fg-primary"
                      >{line.description || "No description"}</span
                    >
                  </td>
                  <td class="py-3 text-right font-tabular"
                    >{Number(line.qty_hours).toFixed(2)}</td
                  >
                  <td class="py-3 text-right font-tabular">{line.rate}</td>
                  <td class="py-3 text-right font-tabular">{line.amount}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}
  </div>
</PageLayout>

<Modal
  bind:open={emailModalOpen}
  title={`Email Invoice #${invoice.invoice_number}`}
  maxWidth="max-w-lg"
>
  <form
    onsubmit={(e) => {
      e.preventDefault();
      sendEmail();
    }}
    class="space-y-4"
  >
    <FormField
      id="recipients"
      label="Recipients"
      description="Separate multiple emails with commas"
    >
      {#snippet children({ describedBy })}
        <TextInput
          id="recipients"
          tone="purple"
          bind:value={emailRecipients}
          placeholder="email@example.com, another@example.com"
          aria-describedby={describedBy}
          required
        />
      {/snippet}
    </FormField>

    <FormField id="message" label="Message (optional)">
      {#snippet children({ describedBy })}
        <TextArea
          id="message"
          tone="purple"
          bind:value={emailMessage}
          rows={4}
          placeholder="Add a personal message to include in the email..."
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>

    <div class="flex items-center gap-2">
      <input
        id="cc_self"
        type="checkbox"
        bind:checked={ccSelf}
        class="w-4 h-4 rounded border-bg-tertiary text-bright-purple focus:ring-bright-purple/50"
      />
      <label for="cc_self" class="text-sm">CC myself ({userEmail})</label>
    </div>

    <Turnstile onSuccess={(token) => (turnstileToken = token)} />

    <div class="flex justify-end gap-2 pt-2">
      <Button
        type="button"
        variant="secondary"
        onclick={() => (emailModalOpen = false)}
      >
        Cancel
      </Button>
      <Button
        type="submit"
        tone="purple"
        disabled={sending || !emailRecipients.trim()}
      >
        {sending ? "Sending..." : "Send Invoice"}
      </Button>
    </div>
  </form>
</Modal>

<Modal
  bind:open={optionsModalOpen}
  title={`Invoice #${invoice.invoice_number} options`}
  maxWidth="max-w-xl"
>
  <form
    onsubmit={(e) => {
      e.preventDefault();
      saveOptions();
    }}
    class="space-y-4"
  >
    <InvoiceOptionsFields
      bind:options={editOptions}
      {receiptKinds}
      idPrefix="edit"
    />
    <div class="flex justify-end gap-2 pt-2">
      <Button
        type="button"
        variant="secondary"
        onclick={() => (optionsModalOpen = false)}
      >
        Cancel
      </Button>
      <Button type="submit" tone="purple">Save options</Button>
    </div>
  </form>
</Modal>

<ConfirmDeleteModal
  bind:open={showDeleteModal}
  title="Delete Invoice"
  itemName={`Invoice #${invoice.invoice_number}`}
  warningMessage="This action cannot be undone. This will permanently delete the invoice and unbill all associated time entries."
  onConfirm={deleteInvoice}
  onClose={() => (showDeleteModal = false)}
>
  {#snippet details()}
    <div class="text-sm text-fg-muted space-y-1">
      <p>Client: {invoice.client.name}</p>
      <p>Amount: {invoice.total_amount}</p>
    </div>
  {/snippet}
</ConfirmDeleteModal>
