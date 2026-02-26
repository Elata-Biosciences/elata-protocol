#!/usr/bin/env tsx

import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

type GossipValidationTarget = {
  scenarioDir: string;
  scenarioName: string;
};

const TARGETS: GossipValidationTarget[] = [
  {
    scenarioDir: 'llm-governance-gossip-coordination',
    scenarioName: 'llm-governance-gossip-coordination',
  },
  {
    scenarioDir: 'llm-adversarial-rumor-coordination',
    scenarioName: 'llm-adversarial-rumor-coordination',
  },
];

async function latestRunDir(resultsDir: string, scenarioDir: string): Promise<string | null> {
  const scenarioPath = join(resultsDir, scenarioDir);
  const runEntries = await readdir(scenarioPath, { withFileTypes: true });
  const runs = runEntries
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()
    .reverse();
  const latest = runs[0];
  return latest ? join(scenarioPath, latest) : null;
}

function countMatches(content: string, needle: string): number {
  if (content.length === 0) return 0;
  return content.split(needle).length - 1;
}

async function validateScenario(resultsDir: string, target: GossipValidationTarget): Promise<string[]> {
  const errors: string[] = [];
  const runDir = await latestRunDir(resultsDir, target.scenarioDir);
  if (!runDir) {
    errors.push(`${target.scenarioName}: no run directory found`);
    return errors;
  }

  const gossipPath = join(runDir, 'gossip.ndjson');
  const memoryPath = join(runDir, 'agent_memory.ndjson');
  let gossipRaw = '';
  let memoryRaw = '';

  try {
    gossipRaw = await readFile(gossipPath, 'utf-8');
  } catch {
    errors.push(`${target.scenarioName}: missing gossip.ndjson`);
    return errors;
  }

  try {
    memoryRaw = await readFile(memoryPath, 'utf-8');
  } catch {
    errors.push(`${target.scenarioName}: missing agent_memory.ndjson`);
    return errors;
  }

  const postCount = countMatches(gossipRaw, '"kind":"gossip_post"');
  const deliverCount = countMatches(gossipRaw, '"kind":"gossip_deliver"');
  const readSignalCount = countMatches(memoryRaw, '"gossipReads"');
  const postSignalCount = countMatches(memoryRaw, '"posted_gossip_');
  const postFailureCount = countMatches(memoryRaw, '"gossip_post_failed_');

  if (postCount < 2) {
    errors.push(`${target.scenarioName}: expected >=2 gossip_post rows, got ${postCount}`);
  }
  if (deliverCount < 2) {
    errors.push(`${target.scenarioName}: expected >=2 gossip_deliver rows, got ${deliverCount}`);
  }
  if (readSignalCount < 1) {
    errors.push(`${target.scenarioName}: expected at least one gossipReads memory signal`);
  }
  if (postSignalCount < 1 && postFailureCount < 1) {
    errors.push(
      `${target.scenarioName}: expected post outcome memory signal (posted_gossip_* or gossip_post_failed_*)`
    );
  }

  return errors;
}

async function main(): Promise<void> {
  const resultsDir = join(process.cwd(), 'results');
  const allErrors: string[] = [];

  for (const target of TARGETS) {
    const errors = await validateScenario(resultsDir, target);
    allErrors.push(...errors);
  }

  if (allErrors.length > 0) {
    console.error('Gossip validation failed:');
    for (const err of allErrors) {
      console.error(`  - ${err}`);
    }
    process.exit(1);
  }

  console.log(`Gossip validation passed for ${TARGETS.length} scenario(s).`);
}

void main();
