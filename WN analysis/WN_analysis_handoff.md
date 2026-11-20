# WN analysis - handoff notes (from previous Claude session, 2026-11-04)

White-noise (WN) visual stimulation + ChRmine holographic opto stimulation, 2-photon, MATLAB R2024b.
User wants **script / live script only** for now (no GUI). Do not delete or overwrite existing scripts;
make new versioned files, and when the user asks for code "here", print it in chat instead of editing files.

## Example recording
`D:\Data\CBLN4-ChRmine\processedData\20261005_mAK02\Recording1\TSeries-10052026-mAK02-LH-cbln4-G6sflxchrmine-influence-5HzWN-1067`
- Opto stims come every 20 noise frames (~3.86 s, not 3 s).
- 2 missed frame triggers (frames 4362, 5218) were filled in the earlier analysis.
- Manual target match for this recording: `TargetROI = [7 124]` (T7 = ROI 124).
- Stimulus code: `PsychStim_WhiteNoise V2.1 (2026-05-07)\` in this folder.

## Files in this folder
- `WN_dFF_script.m` - function `D = WN_dFF_script(dataPath, opts)`. Loads ROI_Data.mat (rawResponse = F),
  relativeTime.mat, markpointData.mat (Trigger, Index), markPointCharacteristics.mat, yxShift.mat.
  - `dFF`: sliding-percentile F0 (F0Percentile-th pct within F0Window s, evaluated every win/4, interp1 to frames, floor eps).
  - `Dfbyf0_hui`: per-frame percentile F0 over +/- F0Window s (two-pointer window, prctile across ROIs at once).
  - `ZDfbyf0 = calc_zscore(Dfbyf0_hui)` (mean/SD per ROI over session, as in Furutachi et al. 2024).
  - Target->ROI matching: roiPoly shifted by mean yxShift; target = 16-pt circle (centre X/Y x 512, radius Width/2 x 512);
    one overlap -> that ROI; several -> min area(subtract(target, ROI)); none -> nearest centroid; TargetROI overrides.
  - Output struct D (t, F, F0, dFF, trig, target, targets, targetTable, roiXY, targetXY, Dfbyf0_hui, ZDfbyf0, ...);
    saved to `Results\<TSeries>\<TSeries>_dFF_targets.mat` (-v7.3).
- `WN_dFF_live_script.mlx` - main live script: Settings (incl. PeakWindow = [0 1.5]), calls WN_dFF_script,
  "Peak response" section (`P = optoPeakResponses(D, 'PeakWindow', PeakWindow)` + summary table), target traces,
  an empty "Heatmaps of Nontargets?" section, other ROIs.
- `WN_dFF_live.mlx` - earlier live version.
- `plot_ROI_trace.m` - black dFF trace with xlines at control-target (T1) stims; user added red `D.Dfbyf0_hui` line.
- `optoPeakResponses.m` - struct per target: Target, ROI, PeakWindow, StimTime, StimFrame, PeakValue, PeakTime,
  PeakFrame, PeakLatency (signal default `Dfbyf0_hui`), plus a per-target figure.
- `old\` - the first, full analysis (event-triggered averages, RFs, trigger checks, WN_dFF_Viewer GUI) and
  `WN_dFF_live_script_backup_2026-10-10.mlx`. Kept after the user chose to start over and simplify.
- `Results\` - outputs.

## Open / offered items
- "Heatmaps of Nontargets?" section of the live script is still empty (not yet specified by the user).
- Offered, not built: baseline-subtracted peak column in optoPeakResponses.
- Last topics discussed: z-score via GMM baseline (Furutachi 2024) and why z-scores can be negative.

## Environment tips
- MATLAB batch: `& "C:\Program Files\MATLAB\R2024b\bin\matlab.exe" -batch "..."`, run from `$env:TEMP`
  (long scratch paths break MATLAB cd). Run Remove-Item cleanup as a separate command.
- Live scripts can be edited via matlab.internal.liveeditor.openAndSave / openAndConvert / executeAndSave.
- If a function errors with a "transparency violation", check for leftover breakpoints (`dbquit all; dbclear all`).
