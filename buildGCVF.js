#!/usr/bin/env node
// buildGCVF.js — Usage: node buildGCVF.js <inputDir> <outputName>
// Produces: <outputName>.gcvf (zip) containing normalized slices, ConfigFile.xml, and gcvf_includes/*

import fs from "fs";
import path from "path";
import sharp from "sharp";
import { fileURLToPath } from "url";
import archiver from "archiver";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** ---- constants ---- */
const COLOR_MAP = {
  "0,255,255,255": "VeroCY-V", // Cyan
  "255,0,255,255": "VeroMGT-V", // Magenta
  "255,255,0,255": "VeroYL-V", // Yellow
  "255,255,255,255": "VUltraWhite", // White
};

/** ---- helpers ---- */
const err = (msg) => {
  console.error("Error:", msg);
  process.exit(1);
};

const validateDir = (dir) => {
  if (!fs.existsSync(dir)) err(`Directory not found: ${dir}`);
  const pngs = fs
    .readdirSync(dir)
    .filter((f) => f.toLowerCase().endsWith(".png"));
  if (pngs.length === 0) err("No PNG files found.");
  return pngs;
};

const normalizeName = (name) => {
  const m = name.match(/layer_(\d+)\.png$/i);
  if (!m) return null;
  return `layer_${parseInt(m[1], 10)}.png`; // strip zero padding
};

const collectAndNormalizeLayers = (dir, files) => {
  const layerFiles = [];
  const seenTargets = new Set();

  for (const f of files) {
    const normalized = normalizeName(f);
    if (!normalized) {
      console.warn(`⚠️  Ignoring non-layer file: ${f}`);
      continue;
    }
    const src = path.join(dir, f);
    const dst = path.join(dir, normalized);
    if (src !== dst) {
      if (fs.existsSync(dst)) {
        err(
          `Normalization collision: ${f} → ${normalized} but ${normalized} already exists. Remove duplicates.`
        );
      }
      fs.renameSync(src, dst);
    }
    if (seenTargets.has(normalized)) {
      err(`Duplicate layer after normalization: ${normalized}`);
    }
    seenTargets.add(normalized);
    layerFiles.push(normalized);
  }

  // sort by numeric index
  layerFiles.sort((a, b) => {
    const na = parseInt(a.match(/\d+/)[0], 10);
    const nb = parseInt(b.match(/\d+/)[0], 10);
    return na - nb;
  });

  if (layerFiles.length === 0) err("No valid layer_*.png files found.");

  // contiguity check: must start at 0 and have no gaps
  const indices = layerFiles.map((f) => parseInt(f.match(/\d+/)[0], 10));
  const expected = Array.from({ length: indices.length }, (_, i) => i);
  const missing = expected.filter((i) => !indices.includes(i));
  if (indices[0] !== 0 || missing.length) {
    err(
      `Layers must start at 0 and be contiguous with no gaps. ` +
        `Found indices: [${indices.slice(0, 5).join(",")}${
          indices.length > 5 ? ",..." : ""
        }] ` +
        `${missing.length ? `Missing: [${missing.join(", ")}]` : ""}`
    );
  }

  return layerFiles;
};

const probeDimensions = async (dir, firstLayer) => {
  const fp = path.join(dir, firstLayer);
  const { info } = await sharp(fp)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return { width: info.width, height: info.height };
};

const countVoxels = async (dir, files, expectedW, expectedH) => {
  const totals = {};
  for (const file of files) {
    const fpath = path.join(dir, file);
    const img = sharp(fpath);
    const { data, info } = await img
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    if (info.width !== expectedW || info.height !== expectedH) {
      err(
        `Invalid size in ${file}. Expected ${expectedW}x${expectedH}, got ${info.width}x${info.height}`
      );
    }

    for (let i = 0; i < data.length; i += 4) {
      const r = data[i],
        g = data[i + 1],
        b = data[i + 2],
        a = data[i + 3];
      const key = `${r},${g},${b},${a}`;
      if (key === "0,0,0,255") continue; // ignore black
      if (!COLOR_MAP[key]) continue; // ignore unknowns
      totals[key] = (totals[key] || 0) + 1;
    }
  }
  return totals;
};

const writeXML = (totals, outDir, width, height, numLayers) => {
  // Keep material ordering stable according to COLOR_MAP
  const materials = Object.entries(COLOR_MAP)
    .filter(([rgba]) => totals[rgba])
    .map(([rgba, name]) => {
      const count = totals[rgba];
      const parts = rgba.split(",").join(" ");
      return `        <Material>
            <Name>${name}</Name>
            <RGBA>${parts}</RGBA>
            <VoxelCount>${count}</VoxelCount>
        </Material>`;
    })
    .join("\n");

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!--  GCVF - GrabCad Voxel Print File  -  -->
<GCVF>
    <Version>2</Version>
    <Resolution>
        <XDpi>600</XDpi>
        <YDpi>300</YDpi>
        <SliceThicknessNanoMeter>27000</SliceThicknessNanoMeter>
    </Resolution>
    <SliceDimensions>
        <SliceWidth>${width}</SliceWidth>
        <SliceHeight>${height}</SliceHeight>
    </SliceDimensions>
    <SliceRange>
        <StartIndex>0</StartIndex>
        <NumberOfSlices>${numLayers}</NumberOfSlices>
    </SliceRange>
    <BitDepth>4</BitDepth>
    <MaxNumberOfColors>6</MaxNumberOfColors>
    <DataSemantics>Materials</DataSemantics>
    <CreationMode>MODEL_ONLY</CreationMode>
    <ImageFilePrefix>layer_</ImageFilePrefix>
    <MaterialList>
        <BackGroundMaterialRGBA>0 0 0 255</BackGroundMaterialRGBA>
${materials}
    </MaterialList>
</GCVF>
`;
  fs.writeFileSync(path.join(outDir, "ConfigFile.xml"), xml);
};

const zipGCVF = (outName, sources) =>
  new Promise((resolve, reject) => {
    const output = fs.createWriteStream(`${outName}.gcvf`);
    const archive = archiver("zip", { zlib: { level: 9 } });
    output.on("close", () => resolve());
    archive.on("error", (e) => reject(e));
    archive.pipe(output);
    sources.forEach(({ path: p, name }) => archive.file(p, { name }));
    archive.finalize();
  });

/** ---- main ---- */
const main = async () => {
  const [, , inputDirRaw, outputNameRaw] = process.argv;
  if (!inputDirRaw || !outputNameRaw)
    err("Usage: node buildGCVF.js <inputDir> <outputName>");

  const inputDir = path.resolve(inputDirRaw);
  const outputName = path.resolve(outputNameRaw);

  // Gather PNGs, normalize valid layer names, and enforce contiguity
  const pngs = validateDir(inputDir);
  const layerFiles = collectAndNormalizeLayers(inputDir, pngs);

  // Infer dimensions from first layer; enforce uniform dimensions across all
  const { width, height } = await probeDimensions(inputDir, layerFiles[0]);
  const numLayers = layerFiles.length;

  console.log(`Detected ${numLayers} layers, dimensions ${width}x${height}.`);

  console.log("Counting voxels...");
  const totals = await countVoxels(inputDir, layerFiles, width, height);

  console.log("Generating ConfigFile.xml...");
  const tempDir = fs.mkdtempSync(path.join(__dirname, "tmp_gcvf_"));
  writeXML(totals, tempDir, width, height, numLayers);

  console.log("Zipping...");
  const includeDir = path.join(inputDir, "gcvf_includes");
  const includeFiles = fs.existsSync(includeDir)
    ? fs.readdirSync(includeDir).map((f) => ({
        path: path.join(includeDir, f),
        name: f,
      }))
    : [];

  const sources = [
    ...layerFiles.map((f) => ({ path: path.join(inputDir, f), name: f })),
    { path: path.join(tempDir, "ConfigFile.xml"), name: "ConfigFile.xml" },
    ...includeFiles,
  ];

  await zipGCVF(outputName, sources);
  fs.rmSync(tempDir, { recursive: true, force: true });
  console.log(`✅ Created ${outputName}.gcvf`);
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
