# Additional Analysis

Smaller MATLAB analysis projects for two-photon imaging with ChRmine holographic photostimulation, separate from the main [SC-Mapping-Toolbox](https://github.com/vicdep9/SC-Mapping-Toolbox).

Developed on MATLAB R2024b. Data and results are not stored in this repository.

## Projects

### `TSeriesImageViewer/`: Pstim image viewer (GUI)

A MATLAB app for viewing photostimulation-triggered dF/F0 and subtraction images from a processed TSeries folder.

```matlab
addpath('TSeriesImageViewer')
app = TSeriesImageViewerv4_1;
```

1. Browse to a processed TSeries folder containing `stimulusData.mat`, `markpointData.mat` and `ResponsesChannel.tif`.
2. Click **Load & Process**. The frame-averaged images are cached in the data folder as `-tiffs_<N>frameavg.mat`.
3. Choose the image type, target and condition. Choose "All conditions" for a grid, or pick a single condition.
4. Save the current plot, or **Save all** grids, to an output folder.

Versions:

| File | Notes |
|---|---|
| `TSeriesImageViewerv4_1.m` | Latest |
| `TSeriesImageViewerv4.m` | Adds per-condition view, overlay of all targets (threshold and smoothing), shared colour scale |
| `TSeriesImageViewer.m` | Original version |
| `old/` | Earlier development versions (v1–v3, v5) |

Each version is its own app class, so its class name must match its filename. Don't rename the files.

### `WN analysis/`: white-noise + opto stimulation

Analysis of recordings in which white-noise visual stimuli are shown while target neurons are photostimulated (ChRmine, Bruker MarkPoints).

| File | Purpose |
|---|---|
| `WN_dFF_live_script.mlx` | **Main live script.** Settings, dF/F, peak responses, target traces |
| `WN_dFF_script.m` | `D = WN_dFF_script(dataPath, opts)`: loads a recording, computes dF/F (sliding-percentile F0), z-scores, and matches photostim targets to ROIs. Saves `Results/<TSeries>/<TSeries>_dFF_targets.mat` |
| `optoPeakResponses.m` | Peak response, time and latency for each target after each stimulation |
| `plot_ROI_trace.m`, `plot_target_slices.m` | Trace and target plots |
| `exportWNFrames.m`, `warpWNFrames.m` | Export and warp white-noise stimulus frames |
| `JC_ContRecAnalysis.mlx` | Alternative event-triggered analysis of the same continuous-recording data, written by another lab member |
| `WN_dFF_live.mlx` | Earlier version of the live script |
| `WN_analysis_handoff.md` | Detailed notes: example recording, methods, open items |
| `old/` | The first full analysis: event-triggered averages, receptive fields, trigger checks, `WN_dFF_Viewer` GUI |
| `PsychStim_WhiteNoise V2.1 (2026-05-07)/` | Stimulus program (Psychtoolbox app) that generates the white noise and sends triggers, written by Hui. Version history is in its `.txt` file |

Input: a processed TSeries folder containing `ROI_Data.mat`, `relativeTime.mat`, `markpointData.mat`, `markPointCharacteristics.mat` and `yxShift.mat`.

Output goes to `WN analysis/Results/`, which is git-ignored.

## What is tracked

`.gitignore` ignores everything except code and documentation: `.m`, `.mlx`, `.mlapp`, `.md`, and text notes. Data (`.mat`, `.tif`), figures and `Results/` folders stay out of the repository.
