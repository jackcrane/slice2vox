#!/usr/bin/env node
// index.js — `node index.js in.png out_dir <numLayers> [--c=0.1 --m=0.0 --y=0.0 --w=0 --b=0]`
// Stochastic CMY halftoning for PolyJet.
// Requirement: full transparency => VOID; partial transparency => CLEAR material; full opacity => color.

import fs from "fs";
import path from "path";
import sharp from "sharp";

/** ---- palette ---- */
export const PALETTE = {
  cyan: "#00FFFF",
  magenta: "#FF00FF",
  yellow: "#FFFF00",
  white: "#FFFFFF",
  clear: "#898989", // CLEAR material
  black: "#F0F0F0", // light gray fallback
};

const DEFAULT_BUMPS = { c: 0.0, m: 0.0, y: 0.0, w: 0.0, b: 0.0 };

const hexToRgb = (hex) => {
  const h = hex.replace("#", "");
  const n = parseInt(h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};

const LUMA = (r, g, b) =>
  0.2126 * (r / 255) + 0.7152 * (g / 255) + 0.0722 * (b / 255);

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);

const parseBumpsFromArgs = (argv) => {
  const out = { ...DEFAULT_BUMPS };
  for (const a of argv) {
    if (!a.startsWith("--")) continue;
    const m = a.match(/^--([cmywb])=([-+]?\d*\.?\d+)$/i);
    if (m) {
      const key = m[1].toLowerCase();
      out[key] = Number(m[2]);
    }
  }
  return out;
};

/** ---- halftoning for a single output image ---- */
export const halftoneImage = async (
  inputPath,
  outputPath,
  bumps = DEFAULT_BUMPS
) => {
  const img = sharp(inputPath, { limitInputPixels: false });
  const { width, height } = await img.metadata();
  const raw = await img.ensureAlpha().raw().toBuffer(); // RGBA

  const out = Buffer.alloc(width * height * 4);

  const RGBA = Object.fromEntries(
    Object.entries(PALETTE).map(([k, hex]) => [k, [...hexToRgb(hex), 255]])
  );

  for (let i = 0; i < width * height; i++) {
    const idx = i * 4;
    const r = raw[idx + 0];
    const g = raw[idx + 1];
    const b = raw[idx + 2];
    const a = raw[idx + 3];

    // Transparency handling:
    // - a === 0     → VOID (true void; render as black pixel)
    // - 0 < a < 255 → CLEAR material
    // - a === 255   → proceed with CMY halftoning
    if (a === 0) {
      out.set([0, 0, 0, 255], idx);
      continue;
    }
    if (a > 0 && a < 255) {
      const [R, G, B, A] = RGBA.clear;
      out.set([R, G, B, A], idx);
      continue;
    }

    // Convert to subtractive CMY thresholds [0,1]
    const rn = r / 255,
      gn = g / 255,
      bn = b / 255;
    const c0 = 1 - rn;
    const m0 = 1 - gn;
    const y0 = 1 - bn;

    // apply probability bumps
    const c = clamp01(c0 + (bumps.c ?? 0));
    const m = clamp01(m0 + (bumps.m ?? 0));
    const y = clamp01(y0 + (bumps.y ?? 0));

    // stochastic screening
    const passC = Math.random() < c;
    const passM = Math.random() < m;
    const passY = Math.random() < y;

    const candidates = [];
    if (passC) candidates.push("cyan");
    if (passM) candidates.push("magenta");
    if (passY) candidates.push("yellow");

    let chosen;
    if (candidates.length > 0) {
      chosen = candidates[(Math.random() * candidates.length) | 0];
    } else {
      // fallback to white/black with bumps
      const l = LUMA(r, g, b);
      const whiteThresh = Math.max(0, 0.9 - 0.9 * clamp01(bumps.w ?? 0)); // more w → pick white more often
      const blackThresh = Math.min(1, 0.1 + 0.9 * clamp01(bumps.b ?? 0)); // more b → pick black more often
      if (l > whiteThresh) chosen = "white";
      else if (l < blackThresh) chosen = "black";
      else chosen = "white";
    }

    const [R, G, B, A] = RGBA[chosen];
    out.set([R, G, B, A], idx);
  }

  await sharp(out, { raw: { width, height, channels: 4 } })
    .png()
    .toFile(outputPath);
};

/** Generate all layers for one setting */
export const generateLayers = async (
  inPath,
  outDir,
  numLayers,
  bumps = DEFAULT_BUMPS
) => {
  fs.mkdirSync(outDir, { recursive: true });
  const pad = Math.max(2, String(numLayers - 1).length);
  for (let i = 0; i < numLayers; i++) {
    const name = `layer_${String(i).padStart(pad, "0")}.png`;
    const outPath = path.join(outDir, name);
    // eslint-disable-next-line no-await-in-loop
    await halftoneImage(inPath, outPath, bumps);
  }
};

/** ---- CLI ---- */
const main = async () => {
  const [, , inPath, outDir, layersArg, ...rest] = process.argv;

  if (!inPath || !outDir || !layersArg) {
    console.error(
      "Usage: node index.js <in.png> <out_dir> <numLayers> [--c=0.1 --m=0.0 --y=0.0 --w=0 --b=0]"
    );
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

  const bumps = parseBumpsFromArgs(rest);
  await generateLayers(inPath, outDir, nLayers, bumps);
};

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
