function T = plot_OptoTriggers(dataPath, outRoot)
% plot_OptoTriggers  Plot the photostimulation trigger channel and timing.
%
%   T = plot_OptoTriggers(dataPath)
%   T = plot_OptoTriggers(dataPath, outRoot)
%
%   Uses TriggerSyncData.mat (raw sync channels) and markpointData.mat
%   (trigger time + target of every stim). Saves
%   <outRoot>\Results\<TSeries name>\<TSeries name>_OptoTriggers.png
%   and returns a table of every stim (time, target, interval).
%
%   Panels:
%     1) whole recording: Stimulation channel with each detected trigger,
%        coloured by target
%     2) first 30 s: Stimulation + noise-frame (Frame) channels
%     3) one trigger at full resolution (pulse shape)
%     4) interval between consecutive stims
%     5) target sequence

if nargin < 2, outRoot = 'D:\Data\Claude Projects\WN analysis'; end
dataPath = regexprep(dataPath, '[\\/]+$', '');
[~, tsName] = fileparts(dataPath);
outDir = fullfile(outRoot, 'Results', tsName);
if ~isfolder(outDir), mkdir(outDir); end

S = load(fullfile(dataPath, 'TriggerSyncData.mat'), ...
    'ChannelNames', 'triggerSyncData', 'triggerSyncTimes', 'StimulationOnsetsTime');
M = load(fullfile(dataPath, 'markpointData.mat'), 'markpointData');
trig = [M.markpointData.Trigger]';
tgt  = [M.markpointData.Index]';

tS   = S.triggerSyncTimes(:);
chS  = find(strcmpi(S.ChannelNames, 'Stimulation'), 1);
chF  = find(strcmpi(S.ChannelNames, 'Frame'), 1);
assert(~isempty(chS), 'No "Stimulation" channel in TriggerSyncData.ChannelNames.');
vS = S.triggerSyncData(:, chS);
fs = 1 / median(diff(tS));

targets = unique(tgt);
nTg = numel(targets);
cols = lines(nTg);
isi = [NaN; diff(trig)];

fprintf('%s\n%d stims, %d targets. Sync sampled at %.0f Hz.\n', tsName, numel(trig), nTg, fs);
fprintf('Interval between stims: median %.3f s (min %.3f, max %.3f)\n', ...
    median(isi, 'omitnan'), min(isi), max(isi));
if numel(S.StimulationOnsetsTime) == numel(trig)
    fprintf('markpointData.Trigger vs TriggerSyncData.StimulationOnsetsTime: max diff %.4f s\n', ...
        max(abs(trig - S.StimulationOnsetsTime(:))));
else
    warning('%d triggers in markpointData but %d in TriggerSyncData.', numel(trig), numel(S.StimulationOnsetsTime));
end

f = figure('Visible', 'off', 'Position', [20 20 1500 1100]);
tl = tiledlayout(f, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% 1) whole recording (max envelope so short pulses are not lost)
ax = nexttile(tl, [1 2]);
[te, ve] = maxEnvelope(tS, vS, round(fs / 100));
plot(ax, te, ve, 'Color', [0.6 0.6 0.6]);  hold(ax, 'on');
yTop = max(vS) * 1.1;
h = gobjects(nTg, 1);
for j = 1:nTg
    k = tgt == targets(j);
    h(j) = plot(ax, trig(k), repmat(yTop, nnz(k), 1), '|', 'Color', cols(j, :), 'MarkerSize', 10, 'LineWidth', 1);
end
xlim(ax, tS([1 end]));  ylim(ax, [min(vS) - 0.1, yTop * 1.05]);
legend(ax, h, compose('T%d', targets), 'Orientation', 'horizontal', 'Location', 'southoutside');
title(ax, sprintf('Stimulation channel, whole recording (%d stims; ticks = markpointData.Trigger)', numel(trig)));
ylabel(ax, 'V');

% 2) first 30 s: stim + frame channels
ax = nexttile(tl, [1 2]);
w = tS >= trig(1) - 2 & tS <= trig(1) + 28;
plot(ax, tS(w), vS(w), 'k');  hold(ax, 'on');
leg = {'Stimulation'};
if ~isempty(chF)
    vF = S.triggerSyncData(:, chF);
    plot(ax, tS(w), vF(w) / max(vF) * max(vS) * 0.5 - max(vS) * 0.6, 'Color', [0.2 0.5 0.9]);
    leg{end+1} = 'Frame (noise frames, scaled)';
end
for k = find(trig >= tS(find(w, 1)) & trig <= tS(find(w, 1, 'last')))'
    j = find(targets == tgt(k));
    xline(ax, trig(k), '--', sprintf('T%d', tgt(k)), 'Color', cols(j, :), 'LabelOrientation', 'horizontal');
end
xlim(ax, tS([find(w, 1), find(w, 1, 'last')]));
legend(ax, leg, 'Location', 'southoutside', 'Orientation', 'horizontal');
title(ax, 'First 30 s');  ylabel(ax, 'V');

% 3) one trigger, full resolution
ax = nexttile(tl);
w = tS >= trig(1) - 0.05 & tS <= trig(1) + 0.6;
plot(ax, (tS(w) - trig(1)) * 1000, vS(w), 'k');
xline(ax, 0, 'r--');
title(ax, sprintf('Stim 1 (T%d), full resolution', tgt(1)));
xlabel(ax, 'Time from trigger (ms)');  ylabel(ax, 'V');

% 4) inter-stim interval
ax = nexttile(tl);  hold(ax, 'on');
for j = 1:nTg
    k = tgt == targets(j);
    scatter(ax, find(k), isi(k), 12, cols(j, :), 'filled');
end
yline(ax, median(isi, 'omitnan'), 'k:', sprintf('median %.3f s', median(isi, 'omitnan')));
title(ax, 'Interval from previous stim (colour = this stim''s target)');
xlabel(ax, 'Stim #');  ylabel(ax, 's');

% 5) target sequence
ax = nexttile(tl, [1 2]);  hold(ax, 'on');
for j = 1:nTg
    k = tgt == targets(j);
    plot(ax, trig(k), tgt(k), '.', 'Color', cols(j, :), 'MarkerSize', 8);
end
yticks(ax, targets);  ylim(ax, [min(targets) - 0.5, max(targets) + 0.5]);
xlim(ax, tS([1 end]));
title(ax, sprintf('Target sequence (stims per target: %s)', ...
    strjoin(compose('T%d = %d', [targets, arrayfun(@(x) nnz(tgt == x), targets)]), ', ')));
xlabel(ax, 'Time (s)');  ylabel(ax, 'Target');

title(tl, sprintf('%s: photostimulation triggers', tsName), 'Interpreter', 'none');
out = fullfile(outDir, sprintf('%s_OptoTriggers.png', tsName));
exportgraphics(f, out, 'Resolution', 150);
close(f);
fprintf('Saved %s\n', out);

T = table((1:numel(trig))', trig, tgt, isi, 'VariableNames', {'Stim', 'Time_s', 'Target', 'Interval_s'});
end

function [te, ve] = maxEnvelope(t, v, n)
% Max of each block of n samples, so brief pulses survive downsampling.
m = floor(numel(v) / n) * n;
ve = max(reshape(v(1:m), n, []), [], 1)';
te = t(1:n:m);
end
