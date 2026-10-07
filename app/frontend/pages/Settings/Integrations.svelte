<script lang="ts">
  import PageLayout from "../../components/PageLayout.svelte";
  import { page, router } from "@inertiajs/svelte";
  import { Plug, CheckCircle2, Circle, Server } from "lucide-svelte";
  import SectionCard from "../../components/SectionCard.svelte";
  import Button from "../../components/Button.svelte";
  import SettingsTabs from "../../components/SettingsTabs.svelte";
  import { routes } from "../../lib/routes";

  type Identity = {
    provider: string;
    label: string;
    use: string;
    available: boolean;
    connected: boolean;
    username: string | null;
  };
  type ServerCreds = {
    github_token: boolean;
    hackatime_api_key: boolean;
    cloudflare: boolean;
  };

  const workspaceId = $derived($page.props.auth?.workspace?.hashid);
  let flash = $derived($page.props.flash || {});
  let identities = $derived(($page.props.identities as Identity[]) || []);
  let server = $derived(
    ($page.props.server as ServerCreds) || {
      github_token: false,
      hackatime_api_key: false,
      cloudflare: false,
    },
  );

  let serverRows = $derived([
    {
      key: "GITHUB_TOKEN",
      active: server.github_token,
      text: "Reads private repositories. Without it, GitHub sync uses your GitHub connection and sees public repos only.",
    },
    {
      key: "HACKATIME_API_KEY",
      active: server.hackatime_api_key,
      text: "Reads your Hackatime heartbeats when you have not connected Hackatime. Only applies to the account in HACKATIME_API_KEY_EMAIL.",
    },
    {
      key: "CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID",
      active: server.cloudflare,
      text: "Imports Cloudflare Worker deploys for the Workers listed on each project.",
    },
  ]);

  function disconnect(provider: string) {
    router.delete(routes.auth.disconnect(provider), { preserveScroll: true });
  }
</script>

<PageLayout
  title="Integrations"
  icon={Plug}
  iconColor="text-bright-purple"
  variant="narrow"
  {flash}
>
  <SectionCard class="overflow-hidden" bodyClass="p-0">
    <SettingsTabs {workspaceId} active="integrations" />
  </SectionCard>

  <SectionCard
    title="Connected accounts"
    description="Connections are personal. They let Timevoice import your commits, PRs and coding time as receipts on invoices."
    bodyClass="p-0"
  >
    <ul class="divide-y divide-bg-tertiary">
      {#each identities as identity (identity.provider)}
        <li class="p-4 flex flex-col sm:flex-row sm:items-center gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              {#if identity.connected}
                <CheckCircle2
                  class="w-4 h-4 text-bright-green"
                  aria-hidden="true"
                />
              {:else}
                <Circle class="w-4 h-4 text-fg-muted" aria-hidden="true" />
              {/if}
              <span class="font-medium text-fg-primary">{identity.label}</span>
            </div>
            <p class="text-sm text-fg-muted mt-1">{identity.use}</p>
            <p class="text-xs mt-1 text-fg-dim">
              {#if identity.connected}
                Connected{identity.username ? ` as ${identity.username}` : ""}
              {:else if identity.available}
                Not connected
              {:else}
                Not configured on this server
              {/if}
            </p>
          </div>
          <div class="shrink-0">
            {#if identity.connected}
              <Button
                variant="secondary"
                onclick={() => disconnect(identity.provider)}
              >
                Disconnect
              </Button>
            {:else if identity.available}
              <form
                action={routes.settings.connectIntegration(
                  workspaceId,
                  identity.provider,
                )}
                method="post"
              >
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={$page.props.csrf_token as string}
                />
                <Button tone="purple" type="submit">Connect</Button>
              </form>
            {/if}
          </div>
        </li>
      {/each}
    </ul>
  </SectionCard>

  <SectionCard
    title="Server credentials"
    description="Set as environment variables on the server. They apply to the whole instance."
    icon={Server}
    bodyClass="p-0"
  >
    <ul class="divide-y divide-bg-tertiary">
      {#each serverRows as row (row.key)}
        <li class="p-4 flex items-start gap-3">
          {#if row.active}
            <CheckCircle2
              class="w-4 h-4 mt-0.5 text-bright-green shrink-0"
              aria-hidden="true"
            />
          {:else}
            <Circle
              class="w-4 h-4 mt-0.5 text-fg-muted shrink-0"
              aria-hidden="true"
            />
          {/if}
          <div class="min-w-0">
            <code class="text-sm text-fg-primary break-all">{row.key}</code>
            <span class="text-xs text-fg-dim ml-2"
              >{row.active ? "active" : "not set"}</span
            >
            <p class="text-sm text-fg-muted mt-1">{row.text}</p>
          </div>
        </li>
      {/each}
    </ul>
  </SectionCard>
</PageLayout>
