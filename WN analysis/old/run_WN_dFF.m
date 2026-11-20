% Compute whole-recording dF/F0 and plot ROIs.
% Run section by section (Ctrl+Enter) or the whole file (F5).

%% Settings
dataPath = 'D:\Data\CBLN4-ChRmine\processedData\20261005_mAK02\Recording1\TSeries-10052026-mAK02-LH-cbln4-G6sflxchrmine-influence-5HzWN-1067';
F0Window     = 15;      % s, sliding window for the baseline
F0Percentile = 10;      % percentile of F in that window used as F0
roisToPlot   = [1 2 3 4 124];

%% Compute dF/F0 (saved to Results\<TSeries>\<TSeries>_dFF.mat)
D = WN_dFF(dataPath, 'F0Window', F0Window, 'F0Percentile', F0Percentile);

%% Plot
for r = roisToPlot
    plot_ROI_trace(D, r);
end

%% Save the plotted figures as PNGs
outDir = fullfile('D:\Data\Claude Projects\WN analysis', 'Results', D.tsName);
for r = roisToPlot
    f = figure('Visible', 'off', 'Position', [50 50 1600 450]);
    plot_ROI_trace(D, r, 'Parent', axes(f));
    exportgraphics(f, fullfile(outDir, sprintf('%s_ROI%03d_dFF.png', D.tsName, r)), 'Resolution', 150);
    close(f);
end
