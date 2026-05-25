#!/usr/bin/env node

// Migration guard for k8s/nats/values.yaml.
//
// The 2026-05-25 tank-operator chat-submission outage was a JetStream
// quorum loss produced by three independent NATS chart defects that
// compounded: R=2 cluster (no Raft tiebreaker), BestEffort QoS (Linux
// CFS deprioritized NATS under host CPU contention), and no
// pod anti-affinity (both replicas co-tenanted on a saturated node).
//
// This guard refuses to merge a regression of any of the three.
// Pattern follows tank-operator's scripts/check-removed-chat-runtime.mjs:
// fail-fast at CI with a runbook-style explanation that names the
// past incident, so a future hand can't quietly drop the hardening.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const valuesPath = path.join(repoRoot, "k8s", "nats", "values.yaml");

if (!fs.existsSync(valuesPath)) {
  console.error(`check-nats-chart: ${valuesPath} not found`);
  process.exit(1);
}

const source = fs.readFileSync(valuesPath, "utf8");

const failures = [];

// Guard 1: cluster.replicas must not be 2. JetStream Raft requires
// R ∈ {1, 3, 5}; R=2 produced the 2026-05-25 incident.
const replicasMatch = source.match(/^\s*replicas:\s*(\d+)\s*$/m);
if (!replicasMatch) {
  failures.push({
    name: "cluster-replicas-missing",
    explanation: [
      "Could not find a `replicas: <N>` line in values.yaml.",
      "The NATS subchart's cluster.replicas controls Raft size; missing",
      "it falls back to the upstream default. Set it explicitly to 3.",
    ].join(" "),
  });
} else {
  const replicas = Number.parseInt(replicasMatch[1], 10);
  if (replicas === 2) {
    failures.push({
      name: "cluster-replicas-equals-two",
      explanation: [
        "cluster.replicas: 2 is the structural defect that produced the",
        "2026-05-25 chat-submission outage. JetStream Raft requires",
        "R ∈ {1, 3, 5}; R=2 has no tiebreaker and halts on a single",
        "slow / dead member. Use 3 (or 5 if the cluster grows).",
      ].join(" "),
    });
  }
  if (![1, 3, 5].includes(replicas)) {
    failures.push({
      name: "cluster-replicas-not-raft-safe",
      explanation: [
        `cluster.replicas: ${replicas} is not a valid Raft cluster size.`,
        "NATS JetStream supports R=1 (single-node, no fault tolerance),",
        "R=3 (tolerates 1 failure), or R=5 (tolerates 2 failures).",
        "Even-N sizes (2, 4) have no quorum tiebreaker and are strictly",
        "worse than the next odd size down.",
      ].join(" "),
    });
  }
}

// Guard 2: container.resources.requests must be set (Burstable QoS).
// BestEffort QoS is what let the Linux CFS scheduler deprioritize
// NATS on 2026-05-25; the requests block flips QoS to Burstable.
if (!/^\s+container:/m.test(source)) {
  failures.push({
    name: "container-block-missing",
    explanation: "Could not find a `container:` block under `nats:`.",
  });
} else if (!/resources:\s*\n\s+requests:\s*\n\s+cpu:/m.test(source)) {
  failures.push({
    name: "container-resources-requests-missing",
    explanation: [
      "container.resources.requests is missing — NATS pods default to",
      "BestEffort QoS, which lets the Linux CFS scheduler deprioritize",
      "Raft heartbeats under host CPU contention (the 2026-05-25 shape).",
      "Set container.resources.requests.cpu and .memory to put NATS in",
      "Burstable QoS so the scheduler guarantees the requested slice.",
    ].join(" "),
  });
}

// Guard 3: pod-level topology spread on kubernetes.io/hostname must
// be required, not preferred. Preferred-during-scheduling would let
// the scheduler co-tenant NATS replicas on a single node when no
// other constraint forces spread — exactly the 2026-05-25 placement.
if (!/topologySpreadConstraints:/m.test(source)) {
  failures.push({
    name: "topology-spread-missing",
    explanation: [
      "podTemplate.topologySpreadConstraints is missing. Without it,",
      "the Kubernetes scheduler can co-tenant all NATS replicas on a",
      "single node, which was the 2026-05-25 placement. Add a",
      "kubernetes.io/hostname constraint with whenUnsatisfiable:",
      "DoNotSchedule.",
    ].join(" "),
  });
} else if (!/whenUnsatisfiable:\s*DoNotSchedule/m.test(source)) {
  failures.push({
    name: "topology-spread-not-required",
    explanation: [
      "podTemplate.topologySpreadConstraints is present but does not",
      "use whenUnsatisfiable: DoNotSchedule. preferred-during-scheduling",
      "allows the scheduler to co-tenant NATS replicas under pressure,",
      "which reproduces the 2026-05-25 placement. The guard requires",
      "DoNotSchedule so a NATS pod sits Pending rather than co-tenant.",
    ].join(" "),
  });
}

if (failures.length === 0) {
  console.log("check-nats-chart: PASS");
  process.exit(0);
}

console.error("check-nats-chart: FAIL");
for (const failure of failures) {
  console.error("");
  console.error(`  [${failure.name}]`);
  for (const line of failure.explanation.match(/.{1,76}(\s|$)/g) ?? [failure.explanation]) {
    console.error(`    ${line.trim()}`);
  }
}
console.error("");
console.error(
  "  See k8s/nats/values.yaml header comment for the 2026-05-25 incident",
);
console.error(
  "  context. To bypass this guard, the post-incident hardening must be",
);
console.error(
  "  intentionally retired and the guard updated in the same PR.",
);
process.exit(1);
