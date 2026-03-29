# slice2vox

`slice2vox` is a small set of shell wrappers around ImageMagick and a Node-based dithering step for turning 2D source images into voxel-print image stacks for PolyJet printing. The overall process follows the voxel printing workflow described in [the SLU CAM paper](https://sites.google.com/slu.edu/slu-cam/voxel-print-wp).

The repository is built around shell entrypoints rather than a single CLI. The main entrypoint is `run_profiles.sh`, which handles the standard "convert, dither, then scale" pipeline. The other shell files are smaller helpers for color tests, matrix generation, scaling, and pixel inspection.

## Requirements

These scripts assume the following tools and files are already available on the machine:

- `magick` from ImageMagick
- `node`
- The Node script `index.js` in this repository
- A printer ICC/ICM profile, typically `./Stratasys_J750_Vivid_CMY_1mm.icm`
- A source RGB ICC profile path passed on the CLI

Common source profile locations to try:

- macOS: `/System/Library/ColorSync/Profiles/sRGB Profile.icc`
- Ubuntu/Debian with Ghostscript profiles: `/usr/share/color/icc/ghostscript/srgb.icc`
- Ubuntu/Debian with colord profiles: `/usr/share/color/icc/colord/sRGB.icc`

If those do not exist on your machine, search for one with:

```sh
find /usr/share/color -iname '*srgb*.icc' 2>/dev/null
```

Most scripts expect to be run from this repository or rely on paths relative to the script location.

## Main workflow: `run_profiles.sh`

`run_profiles.sh` is the main orchestration script for normal production use. It resolves sibling scripts relative to itself, validates that the printer profile exists, checks that ImageMagick is installed, and then runs the pipeline:

1. `convert.sh` converts the source image from sRGB into the target printer profile.
2. `dither.sh` calls `index.js` to generate dithered output.
3. `run_profiles.sh` scales the generated PNGs in-place by `200%x100%` using point filtering so edges stay sharp.

### Usage

```sh
./run_profiles.sh <source_profile.icc> [source_path] [out_root] [--layers=100]
```

### Defaults

- `source_path`: `input.png`
- `out_root`: `out`
- `--layers`: `100`

### Supported modes

#### Single-image mode

If `source_path` is a file, `run_profiles.sh` treats it as a single image and produces a full output stack:

```sh
./run_profiles.sh /usr/share/color/icc/ghostscript/srgb.icc input.png out --layers=100
```

Behavior:

- Deletes and recreates `out_root`
- Writes the profile-converted intermediate image to `out_root/pre.png`
- Runs dithering with the requested layer count
- Scales every generated PNG in the output directory

This is the mode to use when you want a layer stack suitable for voxel printing from one source image.

#### Directory mode

If `source_path` is a directory, the script switches to batch mode:

```sh
./run_profiles.sh /usr/share/color/icc/ghostscript/srgb.icc source_images batch_out
```

Behavior:

- Deletes and recreates `out_root`
- Finds `png`, `jpg`, `jpeg`, `tif`, and `tiff` inputs
- Processes each image independently through `convert.sh`
- Forces `dither.sh` to generate exactly one layer per source image
- Renames that layer to `<original-name>.png`
- Scales the final PNG in-place

In directory mode, `--layers` is ignored on purpose. The output is one PNG per input image, not a stack per input.

### Important implementation details

- Script paths are resolved relative to `run_profiles.sh`, not the current working directory.
- The expected printer profile is `./Stratasys_J750_Vivid_CMY_1mm.icm`.
- Existing output directories are removed before processing starts.
- Temporary directories are created per input image in directory mode and cleaned up automatically.
- Scaling is done after dithering, not before.

## Shell scripts

### `convert.sh`

```sh
./convert.sh <source_profile.icc> <profile.icc|icm> <input_image> <output_image>
```

Purpose:

- Converts an input image from the provided source RGB ICC profile into the target printer ICC/ICM profile
- Emits a PNG with 8-bit RGBA output, no interlacing, and stripped metadata

This is the color-management step used by `run_profiles.sh` before dithering.

### `dither.sh`

```sh
./dither.sh <input_png> <out_dir> [layers]
```

Purpose:

- Thin shell wrapper around `index.js`
- Resolves `index.js` relative to the script directory
- Ensures the output directory exists
- Passes the input path, output directory, and layer count through to Node

This is the handoff point from shell orchestration into the repository's JavaScript dithering logic.

### `matrix.sh`

```sh
./matrix.sh <source_profile.icc> [out_root] [hex_rgb] [--layers=N] [--vary=cm|my|cy]
```

Purpose:

- Generates a 1xN bump matrix for a target color
- Creates a profiled color swatch with `gencolor.sh`
- Runs the halftone step repeatedly while sweeping two CMY channels across a sequence
- Merges the generated columns horizontally with white spacers
- Scales the merged slices by `200%x100%`

This is a calibration and exploration tool for understanding how CMY sweep combinations behave across a printed stack.

Notable environment variables:

- `PROFILE`: printer profile path
- `HALFTONE_JS`: path to `index.js`
- `GENCOLOR`: path to `gencolor.sh`
- `SWEEP_A_SEQ`, `SWEEP_B_SEQ`: channel sweep definitions in `start:end:step` form
- `FIXED_VAL`: fixed value for the non-varying channel
- `KEEP_WORK=1`: preserves the temporary workspace for inspection

### `gencolor.sh`

```sh
./gencolor.sh <source_profile.icc> <icc_profile_path> <output_image> [hex_rgb]
```

Purpose:

- Creates a solid color image, defaulting to blue (`0000FF`)
- Normalizes 3-digit or 6-digit hex input
- Applies sRGB-to-printer-profile conversion

`matrix.sh` uses this to build the profiled source swatch before halftoning.

### `count_px.sh`

```sh
./count_px.sh input.png
```

Purpose:

- Computes the total number of pixels in an image
- Prints a histogram-style summary of pixel counts and percentages by color

This is useful for inspecting the output distribution of a dithered slice.

### `make-matrices.sh`

Purpose:

- Convenience script that runs three preset matrix builds:
  - blue with `--vary=cm`
  - red with `--vary=my`
  - green with `--vary=cy`

This is a shortcut for generating a standard set of color calibration matrices.

### `process.sh`

Purpose:

- Batch-resizes PNGs inside `icc-bw`, `icc-fw`, and `no-icc`
- Uses point filtering and `50%x100%` scaling

This looks like a one-off post-processing helper for three specific output folders rather than a general-purpose entrypoint.

### `scale.sh`

Purpose:

- Batch-scales PNGs under `out/*/`
- Uses point filtering and `200%x100%` scaling

This is a minimal helper for applying the same horizontal scaling that `run_profiles.sh` now performs automatically.

## Typical commands

Generate a voxel stack from a single image:

```sh
./run_profiles.sh /usr/share/color/icc/ghostscript/srgb.icc input.png out --layers=100
```

Batch-process a directory into one output PNG per source image:

```sh
./run_profiles.sh /usr/share/color/icc/ghostscript/srgb.icc ./inputs ./batch_out
```

Generate a blue calibration matrix:

```sh
./matrix.sh /usr/share/color/icc/ghostscript/srgb.icc blue_matrix 0000FF --layers=100 --vary=cm
```

Inspect the pixel distribution of a generated slice:

```sh
./count_px.sh out/layer_00.png
```
