% Whole-recording dF/F0 + opto target -> ROI matching (live function WN_dFF_live.mlx).
% Run section by section (Ctrl+Enter) or the whole file (F5).

%% Settings
dataPath = 'D:\Data\CBLN4-ChRmine\processedData\20261005_mAK02\Recording1\TSeries-10052026-mAK02-LH-cbln4-G6sflxchrmine-influence-5HzWN-1067';
F0Window     = 60;          % s, sliding window for the baseline
F0Percentile = 10;          % percentile of F in that window used as F0
TargetROI    = [7 124];     % manual target -> ROI matches [target roi; ...]; [] = all automatic

%% Compute dF/F0 and match targets to ROIs (shows the FOV figure)
D = WN_dFF_live(dataPath, 'F0Window', F0Window, 'F0Percentile', F0Percentile, 'TargetROI', TargetROI);

%% Plot each target's ROI
for k = 1:height(D.targetTable)
    ax = plot_ROI_trace(D, D.targetTable.ROI(k));
    title(ax, sprintf('%s  -  ROI %d (target T%d)', D.tsName, D.targetTable.ROI(k), D.targetTable.Target(k)), ...
        'Interpreter', 'none');
end
