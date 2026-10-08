export type ActivityKind =
  | "commit"
  | "main"
  | "merge"
  | "pr"
  | "reviewed"
  | "branch"
  | "deploy"
  | "coding";

export interface ActivityEvent {
  id: number;
  kind: ActivityKind;
  source: string;
  at: string;
  ended_at: string | null;
  duration_seconds: number | null;
  title: string | null;
  url: string | null;
  ref: string | null;
  project_id: number;
  metadata: Record<string, any>;
}

export interface TimelineEntry {
  id: number;
  description: string;
  start_at: string;
  end_at: string | null;
  duration_seconds: number;
  project: { id: number; name: string; color: string } | null;
  qty_hours: number | null;
  rate: string | null;
  amount: string | null;
  events: ActivityEvent[];
}

export interface TimelineDay {
  date: string;
  billed_seconds: number;
  coded_seconds: number;
  entries: TimelineEntry[];
  events: ActivityEvent[];
}

export interface Estimates {
  weights: Record<string, number>;
  days: {
    date: string;
    billed: number;
    items: number;
    sessions: number;
    coded: number;
  }[];
  totals: { billed: number; items: number; sessions: number; coded: number };
}

export const KIND_LABELS: Record<ActivityKind, string> = {
  commit: "Commit in PR",
  main: "Direct commit",
  merge: "Squash-merge",
  pr: "PR opened",
  reviewed: "Merged others' PR",
  branch: "Branch created",
  deploy: "Deploy",
  coding: "Coding block",
};

// Colours match the PDF receipts (app/services/invoice_pdf.rb KIND_COLORS)
export const KIND_COLORS: Record<ActivityKind, string> = {
  commit: "#33a36b",
  main: "#a633d6",
  merge: "#8c6b2a",
  pr: "#338eda",
  reviewed: "#0e8a8a",
  branch: "#5c6370",
  deploy: "#f38020",
  coding: "#d6336c",
};

export function formatClock(seconds: number): string {
  const s = Math.round(seconds / 60);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function receiptDetail(e: ActivityEvent): string {
  const m = e.metadata || {};
  const repo = String(m.repo || "")
    .split("/")
    .pop();
  const prs = (m.prs || []).map((n: number) => `#${n}`).join(" ");
  switch (e.kind) {
    case "pr":
      return `${repo} · ${m.state ?? ""}`;
    case "commit":
      return `${repo} · in ${prs}`;
    case "merge":
      return `${repo} · squash-merge of ${prs}`;
    case "main":
      return `${repo} · direct to default branch`;
    case "reviewed":
      return `${repo} · opened by @${m.opened_by}`;
    case "branch":
      return `${m.repo}${m.times > 1 ? ` · created ×${m.times}` : ""}`;
    case "deploy":
      return m.provider === "vercel"
        ? ["vercel", m.branch, m.commit_sha, m.state?.toLowerCase()]
            .filter(Boolean)
            .join(" · ")
        : `cloudflare · ${m.worker} · version ${e.ref ?? ""}`;
    case "coding":
      return `hackatime · ${m.heartbeats} heartbeats${m.via_catchall ? ` · ${m.via_catchall} via catch-all (filename match)` : ""}${m.top_files?.length ? ` · ${m.top_files.join(", ")}` : ""}`;
    default:
      return "";
  }
}
