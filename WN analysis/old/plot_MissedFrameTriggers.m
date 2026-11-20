function G = plot_MissedFrameTriggers(dataPath, outRoot)
% plot_MissedFrameTriggers  Show gaps in the white-noise frame triggers.
%
%   G = plot_MissedFrameTriggers(dataPath)
%   G = plot_MissedFrameTriggers(dataPath, outRoot)
%
%   A gap of ~2+ frame periods in TriggerSyncData.frameOnsetsTime means a
%   noise-frame trigger is missing. This plots:
%     1) the interval between consecutive frame onsets (gaps highlighted)
%     2) the raw Frame channel around each gap, with detected onsets and
%        the onset(s) inferred to be missing
%     3) which noise frame each opto trigger lands on, relative to the
%        expected every-Nth frame, before and after filling the gaps
%   Saves <outRoot>\Results\<TSeries>\<TSeries>_MissedFrameTriggers.png
%   and returns a table of the gaps.

if nargin < 2, outRoot = 'D:\Data\Claude Projects\WN analysis'; end
dataPath = regexprep(dataPath, '[\\/]+$', '');
[~, tsName] = fileparts(dataPath);
outDir = fullfile(outRoot, 'Results', tsName);
if ~isfolder(outDir), mkdir(outDir); end

S = load(fullfile(dataPath, 'TriggerSyncData.mat'), ...
    'ChannelNames', 'triggerSyncData', 'triggerSyncTimes', 'frameOnsetsTime');
M = load(fullfile(dataPath, 'markpointData.mat'), 'markpointData');
P = load(fullfile(dataPath, 'stimulusData.mat'), 'stimulusData');
stimEvery = P.stimulusData.parameters.StimulationFrequency;
trig = [M.markpointData.Trigger]';

on  = S.frameOnsetsTime(:);
tS  = S.triggerSyncTimes(:);
chF = find(strcmpi(S.ChannelNames, 'Frame'), 1);
vF  = S.triggerSyncData(:, chF);

d   = diff(on);
med = median(d);
gap = find(d > 1.5 * med);
nMiss = round(d(gap) / med) - 1;
fprintf('%s\n%d frame onsets, median interval %.4f s. %d gap(s):\n', tsName, numel(on), med, numel(gap));

% Filled onsets
onFill = on;
for g = numel(gap):-1:1
    i = gap(g);
    ins = on(i) + (1:nMiss(g))' * d(i) / (nMiss(g) + 1);
    onFill = [onFill(1:i); ins; onFill(i+1:end)];
end

% Which frame each opto trigger lands on, minus the expected 1 + N*(k-1)
expected = 1 + stimEvery * (0:numel(trig) - 1)';
[~, kRaw]  = min(abs(on - trig'), [], 1);
[~, kFill] = min(abs(onFill - trig'), [], 1);
offRaw  = kRaw(:)  - expected;
offFill = kFill(:) - expected;

% Raw Frame channel: count pulses in each gap (threshold at half max)
thr = (max(vF) + min(vF)) / 2;
rising = tS(find(diff(vF > thr) == 1) + 1);
G = table(gap + 1, on(gap), on(gap + 1), d(gap), nMiss, zeros(numel(gap), 1), ...
    'VariableNames', {'FrameAfterGap', 'GapStart_s', 'GapEnd_s', 'Interval_s', 'MissingOnsets', 'RawPulsesInGap'});
for g = 1:numel(gap)
    G.RawPulsesInGap(g) = nnz(rising > on(gap(g)) + 0.5*med/2 & rising < on(gap(g) + 1) - 0.5*med/2);
end
disp(G)
fprintf('Raw Frame channel: %d rising edges vs %d detected onsets.\n', numel(rising), numel(on));

nG = numel(gap);
f = figure('Visible', 'off', 'Position', [20 20 1500 300 + 280*max(nG, 1) + 300]);
tl = tiledlayout(f, 2 + max(nG, 1), 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% 1) frame intervals
ax = nexttile(tl);
plot(ax, on(2:end), d * 1000, '.', 'Color', [0.5 0.5 0.5], 'MarkerSize', 4);  hold(ax, 'on');
plot(ax, on(gap + 1), d(gap) * 1000, 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
for g = 1:nG
    text(ax, on(gap(g) + 1), d(gap(g)) * 1000 - 25 * (g - 1), sprintf('  frame %d (%.0f s): %.0f ms', ...
        gap(g) + 1, on(gap(g) + 1), d(gap(g)) * 1000), 'Color', 'r', 'VerticalAlignment', 'top');
end
yline(ax, med * 1000, 'k:', sprintf('median %.1f ms', med * 1000));
xlim(ax, on([1 end]));
title(ax, sprintf('Interval between detected noise-frame onsets (%d gaps of ~2 frames)', nG));
xlabel(ax, 'Time (s)');  ylabel(ax, 'ms');

% 2) raw Frame channel around each gap
for g = 1:nG
    ax = nexttile(tl);
    t0 = on(gap(g));
    w = tS >= t0 - 1 & tS <= t0 + 1.4;
    plot(ax, tS(w) - t0, vF(w), 'Color', [0.2 0.5 0.9]);  hold(ax, 'on');
    yl = [min(vF) - 0.2, max(vF) * 1.25];
    k = on >= t0 - 1 & on <= t0 + 1.4;
    plot(ax, on(k) - t0, repmat(max(vF) * 1.12, nnz(k), 1), 'kv', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
    ins = onFill(onFill > on(gap(g)) & onFill < on(gap(g) + 1));
    plot(ax, ins - t0, repmat(max(vF) * 1.12, numel(ins), 1), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
    patch(ax, [0 d(gap(g)) d(gap(g)) 0], yl([1 1 2 2]), 'r', 'FaceAlpha', 0.07, 'EdgeColor', 'none');
    st = trig(trig >= t0 - 1 & trig <= t0 + 1.4);
    if ~isempty(st), xline(ax, st - t0, 'm--', 'opto'); end
    ylim(ax, yl);  xlim(ax, [-1 1.4]);
    title(ax, sprintf(['Gap %d at %.2f s: raw Frame channel (blue), detected onsets (black), ' ...
        'inferred missing onset (red); raw pulses inside gap: %d'], g, t0, G.RawPulsesInGap(g)));
    xlabel(ax, 'Time from last onset before gap (s)');  ylabel(ax, 'V');
end
if nG == 0
    ax = nexttile(tl);  text(ax, 0.5, 0.5, 'No gaps found', 'HorizontalAlignment', 'center');  axis(ax, 'off');
end

% 3) opto trigger -> frame alignment
ax = nexttile(tl);
plot(ax, 1:numel(trig), offRaw, 'r.-', 'MarkerSize', 6);  hold(ax, 'on');
plot(ax, 1:numel(trig), offFill, 'k.-', 'MarkerSize', 6);
ylim(ax, [min([offRaw; 0]) - 0.5, max([offRaw; 0]) + 0.5]);
legend(ax, {'detected onsets', 'after filling gaps'}, 'Location', 'southwest');
title(ax, sprintf('Frame each opto trigger lands on minus expected (1 + %d(k-1)); 0 = aligned', stimEvery));
xlabel(ax, 'Opto stim #');  ylabel(ax, 'frames');

title(tl, sprintf('%s: missed noise-frame triggers', tsName), 'Interpreter', 'none');
out = fullfile(outDir, sprintf('%s_MissedFrameTriggers.png', tsName));
exportgraphics(f, out, 'Resolution', 150);
close(f);
fprintf('Saved %s\n', out);
end
