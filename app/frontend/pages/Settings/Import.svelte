<script lang="ts">
  import { page } from "@inertiajs/svelte";
  import { ArrowDownToLine, Copy, Check } from "lucide-svelte";
  import PageLayout from "../../components/PageLayout.svelte";
  import SectionCard from "../../components/SectionCard.svelte";
  import SettingsTabs from "../../components/SettingsTabs.svelte";
  import FormField from "../../components/FormField.svelte";
  import TextInput from "../../components/TextInput.svelte";
  import Button from "../../components/Button.svelte";
  import { routes } from "../../lib/routes";

  interface LastImport {
    source: string;
    at: string;
    clients: number;
    projects: number;
    tags: number;
    time_entries: number;
    invoices: number;
    linked_lines: number;
  }

  const workspaceId = $derived($page.props.auth?.workspace?.hashid);
  let flash = $derived($page.props.flash || {});
  let redirectUri = $derived($page.props.redirectUri as string);
  let defaultSource = $derived($page.props.defaultSource as string);
  let lastImport = $derived($page.props.lastImport as LastImport | null);

  let sourceUrl = $state("");
  let clientId = $state("");
  let clientSecret = $state("");
  let workspaceCode = $state("");
  let submitting = $state(false);
  let copied = $state(false);

  let sourceHost = $derived.by(() => {
    try {
      return new URL(sourceUrl || defaultSource).host;
    } catch {
      return "your old instance";
    }
  });

  async function copyRedirect() {
    try {
      await navigator.clipboard.writeText(redirectUri);
      copied = true;
      setTimeout(() => (copied = false), 1500);
    } catch {
      copied = false;
    }
  }
</script>

<PageLayout
  title="Import"
  icon={ArrowDownToLine}
  iconColor="text-bright-purple"
  variant="narrow"
  {flash}
>
  <SectionCard class="overflow-hidden" bodyClass="p-0">
    <SettingsTabs {workspaceId} active="import" />
  </SectionCard>

  <SectionCard
    title="Migrate from another Timevoice"
    description="Copy your clients, projects, tags, time entries and invoices from another Timevoice instance into this workspace. Nothing on the old instance changes."
    bodyClass="p-4 space-y-5"
  >
    <ol class="space-y-5 text-sm">
      <li class="space-y-2">
        <div class="font-medium text-fg-primary">
          1. Create an OAuth app on {sourceHost}
        </div>
        <p class="text-fg-muted">
          Sign in there, open <strong>Settings → Developer</strong> and create a new
          OAuth application with:
        </p>
        <dl
          class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 bg-bg-primary border border-bg-tertiary rounded-[10px] p-3"
        >
          <dt class="text-fg-muted">Application Name</dt>
          <dd>Timevoice import</dd>
          <dt class="text-fg-muted">Redirect URI</dt>
          <dd class="flex items-center gap-2 min-w-0">
            <code class="truncate">{redirectUri}</code>
            <button
              type="button"
              class="shrink-0 text-fg-muted hover:text-fg-primary"
              aria-label="Copy redirect URI"
              onclick={copyRedirect}
            >
              {#if copied}<Check class="w-4 h-4" />{:else}<Copy
                  class="w-4 h-4"
                />{/if}
            </button>
          </dd>
          <dt class="text-fg-muted">Application Type</dt>
          <dd>Confidential</dd>
          <dt class="text-fg-muted">Scopes</dt>
          <dd><code>read</code> only</dd>
        </dl>
        <p class="text-fg-muted">
          Copy the client ID and client secret it shows. The secret is only
          shown once.
        </p>
      </li>

      <li class="space-y-2">
        <div class="font-medium text-fg-primary">
          2. Find your workspace code
        </div>
        <p class="text-fg-muted">
          Open any page on the old instance and look at the address bar. In
          <code>https://{sourceHost}/<strong>xXk2dL</strong>/timer</code> the
          code is <code>xXk2dL</code>. You can paste the whole address instead.
        </p>
      </li>

      <li class="space-y-2">
        <div class="font-medium text-fg-primary">3. Authorize and import</div>
        <p class="text-fg-muted">
          Fill in the form below. You'll be sent to {sourceHost} to approve read-only
          access, then brought back here while the import runs.
        </p>
      </li>
    </ol>

    <form
      method="post"
      action={routes.settings.import(workspaceId)}
      class="space-y-4 border-t border-bg-tertiary pt-4"
      onsubmit={() => (submitting = true)}
    >
      <input
        type="hidden"
        name="authenticity_token"
        value={$page.props.csrf_token as string}
      />
      <FormField
        id="import-source"
        label="Old instance URL"
        description="Leave blank for {defaultSource}."
      >
        {#snippet children({ describedBy })}
          <TextInput
            id="import-source"
            name="source_url"
            type="url"
            tone="purple"
            bind:value={sourceUrl}
            placeholder={defaultSource}
            aria-describedby={describedBy}
          />
        {/snippet}
      </FormField>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <FormField id="import-client-id" label="Client ID" required>
          {#snippet children({ describedBy })}
            <TextInput
              id="import-client-id"
              name="client_id"
              tone="purple"
              bind:value={clientId}
              autocomplete="off"
              aria-describedby={describedBy}
            />
          {/snippet}
        </FormField>
        <FormField id="import-client-secret" label="Client secret" required>
          {#snippet children({ describedBy })}
            <TextInput
              id="import-client-secret"
              name="client_secret"
              type="password"
              tone="purple"
              bind:value={clientSecret}
              autocomplete="off"
              aria-describedby={describedBy}
            />
          {/snippet}
        </FormField>
      </div>
      <FormField
        id="import-workspace"
        label="Workspace code or address"
        required
      >
        {#snippet children({ describedBy })}
          <TextInput
            id="import-workspace"
            name="workspace_code"
            tone="purple"
            bind:value={workspaceCode}
            placeholder="xXk2dL or https://{sourceHost}/xXk2dL/timer"
            aria-describedby={describedBy}
          />
        {/snippet}
      </FormField>
      <div class="flex justify-end">
        <Button
          type="submit"
          tone="purple"
          disabled={submitting || !clientId || !clientSecret || !workspaceCode}
        >
          {submitting ? "Redirecting…" : "Authorize and import"}
        </Button>
      </div>
    </form>
  </SectionCard>

  {#if lastImport}
    <SectionCard title="Last import" bodyClass="p-4 text-sm space-y-1">
      <p class="text-fg-muted">
        From {lastImport.source} · {new Date(lastImport.at).toLocaleString()}
      </p>
      <p>
        Added {lastImport.time_entries} time entries, {lastImport.invoices} invoices
        ({lastImport.linked_lines} lines linked to entries), {lastImport.clients}
        clients, {lastImport.projects} projects and {lastImport.tags} tags.
      </p>
    </SectionCard>
  {/if}

  <SectionCard title="Good to know" bodyClass="p-4">
    <ul class="list-disc pl-5 space-y-1.5 text-sm text-fg-muted">
      <li>
        Running the import again is safe. Clients, projects and tags are matched
        by name, time entries by start time, and invoices by client, period and
        total, so nothing is duplicated.
      </li>
      <li>
        Time entries go to your account. Timers still running on the old
        instance are skipped.
      </li>
      <li>
        The old API doesn't link invoice lines to time entries, so lines are
        matched back to entries by description and hours.
      </li>
      <li>
        Your sender name and address aren't exposed by the old API; set them in
        Settings → Billing. Your rate is taken from imported invoice lines.
      </li>
      <li>
        When you're done, delete the OAuth app on the old instance to revoke
        access.
      </li>
    </ul>
  </SectionCard>
</PageLayout>
