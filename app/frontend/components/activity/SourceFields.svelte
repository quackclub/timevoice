<script lang="ts">
  import FormField from "../FormField.svelte";
  import TextArea from "../TextArea.svelte";

  interface Props {
    idPrefix: string;
    github_repos?: string;
    hackatime_projects?: string;
    hackatime_catchall_projects?: string;
    cloudflare_workers?: string;
    vercel_projects?: string;
  }

  let {
    idPrefix,
    github_repos = $bindable(""),
    hackatime_projects = $bindable(""),
    hackatime_catchall_projects = $bindable(""),
    cloudflare_workers = $bindable(""),
    vercel_projects = $bindable(""),
  }: Props = $props();
</script>

<details class="rounded-[10px] border border-bg-tertiary">
  <summary
    class="cursor-pointer px-4 py-2 text-sm font-medium text-fg-secondary select-none"
  >
    Activity sources
    <span class="text-fg-dim font-normal">
      · git, Hackatime and deploy receipts for invoices</span
    >
  </summary>
  <div class="p-4 pt-2 grid grid-cols-1 md:grid-cols-2 gap-4">
    <FormField
      id="{idPrefix}-github"
      label="GitHub repos"
      description="One owner/repo per line. Forks count too."
    >
      {#snippet children({ describedBy })}
        <TextArea
          id="{idPrefix}-github"
          tone="green"
          rows={3}
          bind:value={github_repos}
          placeholder="hackclub/slacker-news"
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>
    <FormField
      id="{idPrefix}-hackatime"
      label="Hackatime projects"
      description="One Hackatime project name per line."
    >
      {#snippet children({ describedBy })}
        <TextArea
          id="{idPrefix}-hackatime"
          tone="green"
          rows={3}
          bind:value={hackatime_projects}
          placeholder="slacker-news"
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>
    <FormField
      id="{idPrefix}-catchall"
      label="Hackatime catch-all projects"
      description="Parent-folder projects like 'projects'. Heartbeats count only when the file path is inside one of the repos above and the file exists in that repo."
    >
      {#snippet children({ describedBy })}
        <TextArea
          id="{idPrefix}-catchall"
          tone="green"
          rows={2}
          bind:value={hackatime_catchall_projects}
          placeholder="projects"
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>
    <FormField
      id="{idPrefix}-workers"
      label="Cloudflare Workers"
      description="One Worker script name per line. Each deploy becomes a receipt."
    >
      {#snippet children({ describedBy })}
        <TextArea
          id="{idPrefix}-workers"
          tone="green"
          rows={2}
          bind:value={cloudflare_workers}
          placeholder="indigest"
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>
    <FormField
      id="{idPrefix}-vercel"
      label="Vercel projects"
      description="One Vercel project name per line. Your deploys (and deploys of your commits) become receipts."
    >
      {#snippet children({ describedBy })}
        <TextArea
          id="{idPrefix}-vercel"
          tone="green"
          rows={2}
          bind:value={vercel_projects}
          placeholder="slacker-news"
          aria-describedby={describedBy}
        />
      {/snippet}
    </FormField>
  </div>
</details>
