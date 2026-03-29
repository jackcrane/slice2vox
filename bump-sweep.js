#!/usr/bin/env node
// bump-sweep.js — `node bump-sweep.js in.png out_blue_squares 100`
// Runs halftoning across C/M/Y bump combinations (+0.1 each) and writes to:
//   out_blue_squares/c-01, m-01, y-01, cm-01, cy-01, my-01, cmy-01

import fs from "fs";
import path from "path";
import { generateLayers } from "./index.js";

const combos = ["", "c", "m", "y", "cm", "cy", "my"];

const labelSorted = (s) =>
  s
    .split("")
    .sort((a, b) => "cmy".indexOf(a) - "cmy".indexOf(b))
    .join("");

const bumpsFor = (label) => ({
  c: label.includes("c") ? 0.1 : 0.0,
  m: label.includes("m") ? 0.1 : 0.0,
  y: label.includes("y") ? 0.1 : 0.0,
  w: 0.0,
  b: 0.0,
});

const main = async () => {
  const [, , inPath, outRoot, layersArg] = process.argv;
  if (!inPath || !outRoot || !layersArg) {
    console.error("Usage: node bump-sweep.js <in.png> <out_root> <numLayers>");
    process.exit(1);
  }
  if (!fs.existsSync(inPath)) {
    console.error(`Input not found: ${inPath}`);
    process.exit(1);
  }
  const nLayers = Number(layersArg);
  if (!Number.isInteger(nLayers) || nLayers <= 0) {
    console.error(`Invalid <numLayers>: ${layersArg}`);
    process.exit(1);
  }

  fs.mkdirSync(outRoot, { recursive: true });

  for (const rawLabel of combos) {
    const label = labelSorted(rawLabel); // ensure c<m<y order in folder names
    const dir = path.join(outRoot, `${label}-01`);
    const bumps = bumpsFor(label);
    console.log(`==> ${label}-01  (c=${bumps.c}, m=${bumps.m}, y=${bumps.y})`);
    // eslint-disable-next-line no-await-in-loop
    await generateLayers(inPath, dir, nLayers, bumps);
  }

  console.log("Done.");
};

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
