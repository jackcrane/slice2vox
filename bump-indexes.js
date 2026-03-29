// bump-indexes.js — safe two-pass renamer using a numeric “bump” window.
// Strategy:
//   1) Shift every file’s first integer by +BUMP (descending order) to free targets.
//   2) Rename from the bumped names to a contiguous sequence starting at <startIndex> (descending).
//
// Usage:
//   node bump-indexes.js <folder> <startIndex> [--bump=100] [--dry-run]
//
// Notes:
//   - Preserves zero-padding width of the matched number (e.g., 003 → 117 if bump=114).
//   - Aborts if the bump window collides with unrelated files. Increase --bump in that case.
//   - Only the first integer in each filename is considered.

import fs from "fs";
import path from "path";

const arg = (k, d = null) => {
  const hit = process.argv.find((s) => s.startsWith(`--${k}=`));
  return hit ? hit.split("=")[1] : d;
};

const [folder, startStr] = process.argv.slice(2);
const dryRun = process.argv.includes("--dry-run");
const bump = parseInt(arg("bump", "100"), 10);

if (!folder || !startStr || Number.isNaN(parseInt(startStr, 10))) {
  console.error("Usage: node bump-indexes.js <folder> <startIndex> [--bump=100] [--dry-run]");
  process.exit(1);
}

const startIndex = parseInt(startStr, 10);

const findFirstInt = (name) => {
  const m = name.match(/\d+/);
  return m ? { span: m[0], value: parseInt(m[0], 10) } : null;
};
const padLike = (span, n) => {
  const w = span.length;
  const s = String(n);
  return s.length >= w ? s : "0".repeat(w - s.length) + s;
};

let entries;
try {
  entries = fs.readdirSync(folder, { withFileTypes: true });
} catch (e) {
  console.error(`Cannot read folder: ${folder}`);
  process.exit(1);
}

const files = entries
  .filter((d) => d.isFile())
  .map((d) => d.name)
  .filter((f) => /\d+/.test(f));

if (files.length === 0) {
  console.error("No files with numbers found in the folder.");
  process.exit(1);
}

// Sort by their numeric token (ascending)
files.sort((a, b) => {
  const na = findFirstInt(a)?.value ?? Number.NEGATIVE_INFINITY;
  const nb = findFirstInt(b)?.value ?? Number.NEGATIVE_INFINITY;
  return na - nb;
});

// Build descriptors
const items = files.map((name, idx) => {
  const hit = findFirstInt(name);
  return {
    name,
    idx,
    num: hit.value,
    span: hit.span,
    bumpNum: hit.value + bump,
    finalNum: startIndex + idx,
  };
});

// Precompute names for bump pass and final pass
const bumpMap = new Map(); // oldName -> bumpName
const finalMap = new Map(); // bumpName -> finalName

for (const it of items) {
  const bumpName = it.name.replace(it.span, padLike(it.span, it.bumpNum));
  bumpMap.set(it.name, bumpName);
}
for (const it of items) {
  const bumpedName = it.name.replace(it.span, padLike(it.span, it.bumpNum));
  const finalName = it.name.replace(it.span, padLike(it.span, it.finalNum));
  finalMap.set(bumpedName, finalName);
}

// Collision checks for bump window against unrelated files
const sourceSet = new Set(files);
for (const [oldName, bumpName] of bumpMap) {
  const bumpPath = path.join(folder, bumpName);
  if (fs.existsSync(bumpPath) && !sourceSet.has(bumpName)) {
    console.error(
      `Bump target already exists and is not part of the rename set: "${bumpName}". Try a larger --bump.`
    );
    process.exit(1);
  }
}

// Collision checks for final targets (after bump, these should be free)
const finalTargets = new Set();
for (const [, finalName] of finalMap) {
  if (finalTargets.has(finalName)) {
    console.error(`Multiple files would become "${finalName}". Aborting.`);
    process.exit(1);
  }
  finalTargets.add(finalName);
}

// DRY RUN preview
if (dryRun) {
  console.log(`Dry run (no changes). Using bump=${bump}`);
  console.log("Phase 1: bump + rename (descending by original number)");
  [...items]
    .sort((a, b) => b.num - a.num)
    .forEach((it) => {
      const bumpName = bumpMap.get(it.name);
      if (it.name !== bumpName) console.log(`${it.name}  →  ${bumpName}`);
    });

  console.log("\nPhase 2: assign final sequence (descending by final number)");
  [...items]
    .sort((a, b) => b.finalNum - a.finalNum)
    .forEach((it) => {
      const bumpedName = bumpMap.get(it.name);
      const finalName = finalMap.get(bumpedName);
      if (bumpedName !== finalName) console.log(`${bumpedName}  →  ${finalName}`);
    });
  process.exit(0);
}

// Phase 1: bump pass (descending by original number)
for (const it of [...items].sort((a, b) => b.num - a.num)) {
  const oldPath = path.join(folder, it.name);
  const bumpName = bumpMap.get(it.name);
  const bumpPath = path.join(folder, bumpName);
  if (it.name === bumpName) continue; // no-op
  fs.renameSync(oldPath, bumpPath);
}

// Phase 2: final assignment (descending by final target number)
for (const it of [...items].sort((a, b) => b.finalNum - a.finalNum)) {
  const bumpedName = bumpMap.get(it.name);
  const finalName = finalMap.get(bumpedName);
  const from = path.join(folder, bumpedName);
  const to = path.join(folder, finalName);
  if (bumpedName === finalName) continue; // no-op
  fs.renameSync(from, to);
  console.log(`${bumpedName}  →  ${finalName}`);
}
