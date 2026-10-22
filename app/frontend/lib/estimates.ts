// Browser copy of app/services/activity/estimator.rb so weights can be edited live. Keep in step.
export interface EstimatorEvent {
  kind: string;
  at: number;
  end: number;
  title: string | null;
  secs: number;
  add: number;
  del: number;
  merge_branch: boolean;
  ref: string | null;
}

export type Weights = Record<string, number>;

export const WEIGHT_LABELS: Record<string, [string, string]> = {
  commit_base: ["Commit base", "minutes per authored commit"],
  per_line: ["Per line changed", "minutes per added or deleted line"],
  line_cap: ["Line cap", "lines counted per commit at most"],
  commit_cap: ["Commit cap", "most minutes for one commit"],
  repeated_commit: [
    "Repeated commit",
    "same message again that day (cherry-pick)",
  ],
  merge_branch: ["Merge-branch commit", "“Merge branch …” commits"],
  squash: ["Squash-merge", "landing a PR"],
  pr: ["PR opened", "title, description, self-review"],
  reviewed: ["Review others' PR", "reviewing and merging"],
  branch: ["Branch created", "per new branch"],
  deploy: ["Deploy", "build, deploy, smoke-check"],
  session_gap: ["Session gap", "B: longest pause inside one session"],
  lead_in: ["Session lead-in", "B: work before a session's first event"],
};

export function itemMinutes(
  e: EstimatorEvent,
  w: Weights,
  repeated: boolean,
): number {
  switch (e.kind) {
    case "commit":
    case "main":
      if (e.merge_branch) return w.merge_branch;
      if (repeated) return w.repeated_commit;
      return Math.min(
        w.commit_cap,
        w.commit_base + w.per_line * Math.min(w.line_cap, e.add + e.del),
      );
    case "merge":
      return w.squash;
    case "pr":
      return w.pr;
    case "reviewed":
      return w.reviewed;
    case "branch":
      return w.branch;
    case "deploy":
      return w.deploy;
    default:
      return 0;
  }
}

export function estimateByDay(
  events: EstimatorEvent[],
  w: Weights,
  timeZone: string,
) {
  const dayOf = (t: number) =>
    new Date(t * 1000).toLocaleDateString("en-CA", { timeZone });
  const days: Record<
    string,
    { items: number; sessions: number; coded: number }
  > = {};
  const ensure = (d: string) =>
    (days[d] ??= { items: 0, sessions: 0, coded: 0 });
  const seen = new Set<string>();
  const sorted = [...events].sort((a, b) => a.at - b.at);
  for (const e of sorted) {
    const d = dayOf(e.at);
    if (e.kind === "coding") {
      ensure(d).coded += e.secs;
      continue;
    }
    const key = `${d}|${e.title}`;
    const repeated =
      (e.kind === "commit" || e.kind === "main") && seen.has(key);
    seen.add(key);
    ensure(d).items += itemMinutes(e, w, repeated) * 60;
  }
  let cur: [number, number] | null = null;
  const close = () => {
    if (cur) ensure(dayOf(cur[0])).sessions += cur[1] - cur[0] + w.lead_in * 60;
  };
  for (const e of sorted) {
    if (cur && e.at - cur[1] <= w.session_gap * 60)
      cur[1] = Math.max(cur[1], e.end);
    else {
      close();
      cur = [e.at, e.end];
    }
  }
  close();
  return days;
}
