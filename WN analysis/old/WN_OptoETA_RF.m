function R = WN_OptoETA_RF(dataPath, outRoot, opts)
% WN_OptoETA_RF  Opto event-triggered averages and white-noise receptive fields.
%
%   R = WN_OptoETA_RF(dataPath)
%   R = WN_OptoETA_RF(dataPath, outRoot, 'Name', value, ...)
%
%   dataPath : processed TSeries folder containing ROI_Data.mat,
%              markpointData.mat, markPointCharacteristics.mat,
%              stimulusData.mat, TriggerSyncData.mat, relativeTime.mat
%              (and optionally yxShift.mat).
%   outRoot  : results go to <outRoot>\Results\<TSeries name>\
%
%   1) Each ROI's rawResponse is z-scored over the whole recording.
%   2) Event-triggered average (ETA): the z-scored traces are sampled at
%      Trigger + [Window] for every photostimulation in markpointData and
%      grouped by target (markpointData.Index). The control target
%      (default 1) is subtracted from every other target.
%      A dF/F0 version is also computed (from JC_ContRecAnalysis): raw F
%      is averaged per target and normalised by its pre-stim mean (F0).
%   3) Receptive field: response-weighted average of the white-noise
%      frames (stimulusData.parameters.NoiseImg) shown LAG seconds before
%      each imaging frame. Significance is a z-score against circularly
%      shifted traces.
%
%   Options (name/value):
%     Window           [-0.5 1.5]  ETA window around each trigger (s)
%     RFLags           0:0.2:2     stimulus-to-response lags for the RF (s)
%     NShuffles        50          circular shifts for the RF null
%     RFzThresh        5           |z| needed to call an RF significant
%     ControlTarget    1           markpoint Index used as control
%     BaselineSubtract false       subtract each trial's pre-event mean
%     SaveFigures      true
%     GridFigures      true        one figure per target with every ROI's dF/F0 trace
%     TargetROI        []          manual target->ROI matches, [target roi; ...]
%                                  (overrides the automatic overlap match)
%     RFCondTargets    []          targets whose stim epochs get their own RFs
%                                  ([] = the control target only)
%     RFEpoch          [0 Inf]     frames counted as "during" a stim: time since
%                                  that stim (s); Inf = until the next stim
%     PeakFrameOffset  -0.25       for each target: average the noise frame shown
%                                  this many s from the target ROI's peak
%                                  dF/F0 response, across that target's stims
%     F0Window         60          sliding window (s) for the whole-trace dF/F0
%     F0Percentile     10          percentile of F in that window used as F0

arguments
    dataPath (1,:) char
    outRoot (1,:) char = 'D:\Data\Claude Projects\WN analysis'
    opts.Window (1,2) double = [-0.5 1.5]
    opts.RFLags (1,:) double = 0:0.2:2
    opts.NShuffles (1,1) double = 50
    opts.RFzThresh (1,1) double = 5
    opts.ControlTarget (1,1) double = 1
    opts.BaselineSubtract (1,1) logical = false
    opts.SaveFigures (1,1) logical = true
    opts.GridFigures (1,1) logical = true
    opts.TargetROI (:,2) double = zeros(0, 2)
    opts.RFCondTargets (1,:) double = []
    opts.RFEpoch (1,2) double = [0 Inf]
    opts.PeakFrameOffset (1,1) double = -0.25
    opts.F0Window (1,1) double = 60
    opts.F0Percentile (1,1) double = 10
end
if isempty(opts.RFCondTargets)
    opts.RFCondTargets = opts.ControlTarget;
end

dataPath = regexprep(dataPath, '[\\/]+$', '');
[~, tsName] = fileparts(dataPath);
outDir = fullfile(outRoot, 'Results', tsName);
if ~isfolder(outDir), mkdir(outDir); end
fprintf('Data:    %s\nResults: %s\n', dataPath, outDir);

%% Load
S = load(fullfile(dataPath, 'ROI_Data.mat'), 'ROI_Data');
ROI_Data = S.ROI_Data;
S = load(fullfile(dataPath, 'relativeTime.mat'), 'relativeTime');
tImg = S.relativeTime(:)';
S = load(fullfile(dataPath, 'markpointData.mat'), 'markpointData');
markpointData = S.markpointData;
S = load(fullfile(dataPath, 'markPointCharacteristics.mat'), 'MarkPointCharacteristics');
MPC = S.MarkPointCharacteristics;
S = load(fullfile(dataPath, 'stimulusData.mat'), 'stimulusData');
stimPar = S.stimulusData.parameters;
S = load(fullfile(dataPath, 'TriggerSyncData.mat'), 'frameOnsetsTime');
noiseOnsets = S.frameOnsetsTime(:);
if isfile(fullfile(dataPath, 'yxShift.mat'))
    S = load(fullfile(dataPath, 'yxShift.mat'), 'yxShift');
    roiShift = [mean(S.yxShift(:, 2)), mean(S.yxShift(:, 1))];   % [x y], as in the influence code
else
    roiShift = [0 0];
    warning('No yxShift.mat; ROI positions are not shifted.');
end
clear S

nROI = numel(ROI_Data);
F = double(vertcat(ROI_Data.rawResponse));
assert(size(F, 2) == numel(tImg), 'rawResponse length (%d) ~= relativeTime length (%d).', size(F, 2), numel(tImg));
dt = median(diff(tImg));

%% 1) z-score
Z = zscore(F, 0, 2);
Z(~isfinite(Z)) = 0;

% Whole-trace dF/F0 with a sliding-percentile baseline
F0trace = runningPercentile(F, tImg, opts.F0Window, opts.F0Percentile);
dFF = (F - F0trace) ./ F0trace;

%% 2) Event-triggered averages by target
trig = [markpointData.Trigger]';
tgt  = [markpointData.Index]';
fprintf('%d photostimulations, median interval %.3f s\n', numel(trig), median(diff(trig)));

tw = (round(opts.Window(1)/dt):round(opts.Window(2)/dt)) * dt;
sampT = trig + tw;                                         % nEv x nT
Zi = interp1(tImg, Z', sampT(:), 'linear', NaN);           % (nEv*nT) x nROI
trials = permute(reshape(Zi, numel(trig), numel(tw), nROI), [3 2 1]);   % nROI x nT x nEv
pre  = tw < 0;
post = tw >= 0;
if opts.BaselineSubtract
    trials = trials - mean(trials(:, pre, :), 2, 'omitnan');
end

targets = unique(tgt);
nTg = numel(targets);
ci = find(targets == opts.ControlTarget, 1);
assert(~isempty(ci), 'Control target %d not found in markpointData.Index.', opts.ControlTarget);

etaMean = zeros(nROI, numel(tw), nTg);
etaSEM  = zeros(nROI, numel(tw), nTg);
nTrials = zeros(nTg, 1);
amp = cell(nTg, 1);              % per-trial response: mean(post) - mean(pre), nROI x nTrials
for j = 1:nTg
    tr = trials(:, :, tgt == targets(j));
    nTrials(j) = size(tr, 3);
    etaMean(:, :, j) = mean(tr, 3, 'omitnan');
    etaSEM(:, :, j)  = std(tr, 0, 3, 'omitnan') ./ sqrt(nTrials(j));
    amp{j} = squeeze(mean(tr(:, post, :), 2, 'omitnan') - mean(tr(:, pre, :), 2, 'omitnan'));
end
etaSub = etaMean - etaMean(:, :, ci);                      % target minus control

% dF/F0 ETA (JC_ContRecAnalysis): average raw F per target, F0 = pre-stim mean
Fi = interp1(tImg, F', sampT(:), 'linear', NaN);
trialsF = permute(reshape(Fi, numel(trig), numel(tw), nROI), [3 2 1]);   % nROI x nT x nEv
dffMean = zeros(nROI, numel(tw), nTg);
dffSEM  = zeros(nROI, numel(tw), nTg);
for j = 1:nTg
    tr = trialsF(:, :, tgt == targets(j));
    avgF = mean(tr, 3, 'omitnan');
    F0 = mean(avgF(:, pre), 2, 'omitnan');
    dffMean(:, :, j) = (avgF - F0) ./ F0;
    dffSEM(:, :, j)  = std((tr - F0) ./ F0, 0, 3, 'omitnan') ./ sqrt(nTrials(j));
end
dffSub = dffMean - dffMean(:, :, ci);

% Per-ROI comparison of response amplitude, target vs control (rank-sum)
pVsCtrl = nan(nROI, nTg);
dAmp    = nan(nROI, nTg);
for j = 1:nTg
    if j == ci, continue, end
    for r = 1:nROI
        pVsCtrl(r, j) = ranksum(amp{j}(r, :), amp{ci}(r, :));
    end
    dAmp(:, j) = mean(amp{j}, 2, 'omitnan') - mean(amp{ci}, 2, 'omitnan');
end

%% Match each target to an ROI
res  = [ROI_Data(1).Parameters.pixelsPerLine, ROI_Data(1).Parameters.linesPerFrame];
umPx = ROI_Data(1).Parameters.micronsPerPixel(1).valueAttribute;
[~, ia] = unique([MPC.Index]);
MPC = MPC(ia);
mpXY = [[MPC.X]' * res(1), [MPC.Y]' * res(2)];
mpR  = [MPC.Width]' / 2 * res(1);

warning('off', 'MATLAB:polyshape:repairedBySimplify');
roiPoly = repmat(polyshape(), nROI, 1);
roiXY = zeros(nROI, 2);
for r = 1:nROI
    roiPoly(r) = polyshape(ROI_Data(r).roiPoly + roiShift);
    [roiXY(r, 1), roiXY(r, 2)] = centroid(roiPoly(r));
end
th = linspace(0, 2*pi, 33); th(end) = [];
targetROI = nan(nTg, 1); targetDist = nan(nTg, 1); targetOverlap = false(nTg, 1); targetManual = false(nTg, 1);
mpPoly = repmat(polyshape(), nTg, 1);
for j = 1:nTg
    k = find([MPC.Index] == targets(j), 1);
    mpPoly(j) = polyshape(mpXY(k, 1) + mpR(k)*cos(th), mpXY(k, 2) + mpR(k)*sin(th));
    ov = arrayfun(@(p) area(intersect(mpPoly(j), p)), roiPoly);
    d  = hypot(roiXY(:, 1) - mpXY(k, 1), roiXY(:, 2) - mpXY(k, 2));
    if any(ov > 0)
        [~, targetROI(j)] = max(ov);
        targetOverlap(j) = true;
    else
        [~, targetROI(j)] = min(d);
    end
    m = find(opts.TargetROI(:, 1) == targets(j), 1);
    if ~isempty(m)
        r = opts.TargetROI(m, 2);
        assert(r >= 1 && r <= nROI && r == round(r), 'TargetROI: ROI %g does not exist.', r);
        targetROI(j) = r;
        targetOverlap(j) = ov(r) > 0;
        targetManual(j) = true;
    end
    targetDist(j) = d(targetROI(j)) * umPx;
end
unknown = setdiff(opts.TargetROI(:, 1), targets);
if ~isempty(unknown)
    warning('TargetROI lists target(s) %s that were never stimulated.', mat2str(unknown'));
end
targetTable = table(targets, targetROI, targetOverlap, round(targetDist, 1), nTrials, targetManual, ...
    'VariableNames', {'Target', 'ROI', 'Overlaps', 'Distance_um', 'nStims', 'Manual'});
disp(targetTable)

% Distance of every ROI from every target (um)
distToTarget = zeros(nROI, nTg);
for j = 1:nTg
    k = find([MPC.Index] == targets(j), 1);
    distToTarget(:, j) = hypot(roiXY(:, 1) - mpXY(k, 1), roiXY(:, 2) - mpXY(k, 2)) * umPx;
end

%% 3) White-noise receptive fields
Ny = stimPar.GridNumber_Y;  Nx = stimPar.GridNumber_X;
[noiseOnsets, nInserted] = fillMissedFrames(noiseOnsets);
nShown = numel(noiseOnsets);
assert(nShown <= size(stimPar.NoiseImg, 1), 'More frame triggers (%d) than noise frames (%d).', nShown, size(stimPar.NoiseImg, 1));
stimEvery = stimPar.StimulationFrequency;
kStim = 1 + stimEvery * (0:numel(trig) - 1)';
kStim = kStim(kStim <= nShown);
alignErr = max(abs(noiseOnsets(kStim) - trig(1:numel(kStim))));
fprintf('Noise frames shown: %d (%d missed triggers filled). Stim/frame alignment error: %.4f s\n', ...
    nShown, nInserted, alignErr);
if alignErr > 0.05
    warning('Photostim triggers do not line up with every %dth noise frame (max error %.3f s). Check frame onsets.', ...
        stimEvery, alignErr);
end

Snz = stimPar.NoiseImg(1:nShown, 1:Ny*Nx);
Snz = (Snz - mean(Snz, 1)) ./ max(std(Snz, 0, 1), eps);
edges = [noiseOnsets; noiseOnsets(end) + median(diff(noiseOnsets))];
lags = opts.RFLags;
nL = numel(lags);
kIdx = cell(nL, 1);
for L = 1:nL
    kIdx{L} = discretize(tImg(:) - lags(L), edges);       % noise frame on screen LAG s before each imaging frame
end
Zt = Z';
allFrames = true(size(Zt, 1), 1);
minShift = round(60 / dt);
RF = rfAllLags(Zt, Snz, kIdx, allFrames);                 % nROI x nPix x nL
fprintf('RF null: %d circular shifts... ', opts.NShuffles);
rng(0);
[nullMu, nullSD] = rfNull(Zt, Snz, kIdx, allFrames, opts.NShuffles, minShift);
fprintf('done\n');
RFz = (RF - nullMu) ./ nullSD;

% Patch centres in degrees (screen centre = 0; elevation + = up)
xDeg =  ((1:Nx) - (Nx + 1)/2) * stimPar.GridWidth + stimPar.PositionX;
yDeg = -((1:Ny) - (Ny + 1)/2) * stimPar.GridWidth - stimPar.PositionY;

RFpeak = rfPeakTable(RFz, opts.RFzThresh, lags, xDeg, yDeg, Ny, Nx);
fprintf('%d of %d ROIs have |z| >= %g RFs\n', nnz(RFpeak.Significant), nROI, opts.RFzThresh);

% RFs from only the imaging frames that follow stims of particular targets
kTrig = discretize(tImg(:), [trig; Inf]);                 % most recent stim before each frame
since = nan(size(kTrig));
has = ~isnan(kTrig);
since(has) = tImg(has)' - trig(kTrig(has));
RFcond = struct('target', {}, 'epoch', {}, 'nFrames', {}, 'RFz', {}, 'peak', {});
for c = opts.RFCondTargets(:)'
    mask = false(size(kTrig));
    mask(has) = tgt(kTrig(has)) == c & since(has) >= opts.RFEpoch(1) & since(has) < opts.RFEpoch(2);
    fprintf('RF during T%d stims (%d frames, %d shifts)... ', c, nnz(mask), opts.NShuffles);
    RFc = rfAllLags(Zt, Snz, kIdx, mask);
    [mu, sd] = rfNull(Zt, Snz, kIdx, mask, opts.NShuffles, minShift);
    RFcz = (RFc - mu) ./ sd;
    RFcond(end+1) = struct('target', c, 'epoch', opts.RFEpoch, 'nFrames', nnz(mask), ...
        'RFz', reshape(RFcz, nROI, Ny, Nx, nL), ...
        'peak', rfPeakTable(RFcz, opts.RFzThresh, lags, xDeg, yDeg, Ny, Nx)); %#ok<AGROW>
    fprintf('%d ROIs with |z| >= %g\n', nnz(RFcond(end).peak.Significant), opts.RFzThresh);
end

% Average noise frame at (target ROI's peak response + PeakFrameOffset) on
% each stim of that target. z = (average - mean) / (SD / sqrt(n)) per patch.
Sraw = stimPar.NoiseImg(1:nShown, 1:Ny*Nx);
muN = mean(Sraw, 1);  sdN = std(Sraw, 0, 1);
tPost = tw(post);
peakFrame = struct('target', {}, 'roi', {}, 'tPeak', {}, 'tFrame', {}, 'frameOffset', {}, ...
    'n', {}, 'avg', {}, 'z', {});
for j = 1:nTg
    r = targetTable.ROI(j);
    [~, ip] = max(dffMean(r, post, j));
    sel = tgt == targets(j);
    tq = trig(sel) + tPost(ip) + opts.PeakFrameOffset;
    kq = discretize(tq, edges);
    k0 = discretize(trig(sel), edges);
    ok = ~isnan(kq) & ~isnan(k0);
    A = mean(Sraw(kq(ok), :), 1);
    peakFrame(j) = struct('target', targets(j), 'roi', r, 'tPeak', tPost(ip), ...
        'tFrame', tPost(ip) + opts.PeakFrameOffset, 'frameOffset', unique(kq(ok) - k0(ok))', ...
        'n', nnz(ok), 'avg', reshape(A, Ny, Nx), ...
        'z', reshape((A - muN) ./ (sdN / sqrt(nnz(ok))), Ny, Nx));
    fprintf('T%d (ROI %d): peak %.2f s -> noise frame at %+.2f s (frame %s after the stim frame), n = %d, max |z| = %.2f\n', ...
        targets(j), r, tPost(ip), peakFrame(j).tFrame, mat2str(peakFrame(j).frameOffset), ...
        peakFrame(j).n, max(abs(peakFrame(j).z(:))));
end

%% Collect results
R = struct();
R.tsName = tsName;  R.dataPath = dataPath;  R.outDir = outDir;  R.opts = opts;
R.tImg = tImg;  R.dt = dt;  R.Z = Z;  R.dFF = dFF;
R.trig = trig;  R.trigTarget = tgt;
R.tw = tw;  R.trials = trials;  R.targets = targets;  R.controlIdx = ci;
R.etaMean = etaMean;  R.etaSEM = etaSEM;  R.etaSub = etaSub;  R.nTrials = nTrials;
R.dffMean = dffMean;  R.dffSEM = dffSEM;  R.dffSub = dffSub;
R.amp = amp;  R.dAmp = dAmp;  R.pVsCtrl = pVsCtrl;
R.targetTable = targetTable;  R.distToTarget = distToTarget;
R.roiXY = roiXY;  R.mpXY = mpXY;  R.mpR = mpR;  R.roiShift = roiShift;  R.umPerPx = umPx;
R.noiseOnsets = noiseOnsets;  R.nMissedFrameTriggers = nInserted;  R.stimAlignErr = alignErr;
R.RF = reshape(RF, nROI, Ny, Nx, nL);  R.RFz = reshape(RFz, nROI, Ny, Nx, nL);
R.RFlags = lags;  R.xDeg = xDeg;  R.yDeg = yDeg;  R.RFpeak = RFpeak;  R.RFcond = RFcond;  R.peakFrame = peakFrame;

save(fullfile(outDir, sprintf('%s_OptoETA_RF.mat', tsName)), 'R', '-v7.3');

%% Figures
if opts.SaveFigures
    makeFigures(R, roiPoly, mpPoly, outDir);
    if opts.GridFigures
        makeGridFigures(R, outDir);
    end
    makeRFCondFigures(R, outDir);
    makeTraceFigures(R, outDir);
    makePeakFrameFigure(R, outDir);
end
end

% ------------------------------------------------------------------------
function RF = rfAllLags(Zt, Snz, kIdx, mask)
% Response-weighted average of the stimulus for every lag, using only the
% imaging frames in MASK.
nL = numel(kIdx);
RF = zeros(size(Zt, 2), size(Snz, 2), nL);
for L = 1:nL
    v = mask & ~isnan(kIdx{L});
    RF(:, :, L) = (Zt(v, :)' * Snz(kIdx{L}(v), :)) / nnz(v);
end
end

function [mu, sd] = rfNull(Zt, Snz, kIdx, mask, nShuffles, minShift)
% Per-ROI mean/SD of RF values when the traces are circularly shifted
% relative to the stimulus (same frames, same mask).
nROI = size(Zt, 2);
s1 = zeros(nROI, 1);  s2 = zeros(nROI, 1);  n = 0;
for s = 1:nShuffles
    Rs = rfAllLags(circshift(Zt, randi([minShift, size(Zt, 1) - minShift]), 1), Snz, kIdx, mask);
    Rs = reshape(Rs, nROI, []);
    s1 = s1 + sum(Rs, 2);
    s2 = s2 + sum(Rs.^2, 2);
    n = n + size(Rs, 2);
end
mu = s1 / n;
sd = sqrt(max(s2 / n - mu.^2, eps));
end

function T = rfPeakTable(RFz, thresh, lags, xDeg, yDeg, Ny, Nx)
% Strongest |z| per ROI over all patches and lags.
nROI = size(RFz, 1);
[pk, idx] = max(abs(reshape(RFz, nROI, [])), [], 2);
[pix, lag] = ind2sub([Ny*Nx, numel(lags)], idx);
sgn = sign(RFz(sub2ind([nROI, Ny*Nx, numel(lags)], (1:nROI)', pix, lag)));
[row, col] = ind2sub([Ny Nx], pix);
T = table((1:nROI)', pk, sgn, lags(lag)', xDeg(col)', yDeg(row)', pk >= thresh, ...
    'VariableNames', {'ROI', 'PeakAbsZ', 'Sign', 'Lag_s', 'Azimuth_deg', 'Elevation_deg', 'Significant'});
end

function [on, nIns] = fillMissedFrames(on)
% Insert onsets where a frame trigger was missed (gap of ~2+ frame periods).
d = diff(on);
med = median(d);
n = round(d / med);
nIns = sum(n(n > 1) - 1);
if nIns == 0, return, end
out = zeros(numel(on) + nIns, 1);
o = 1;  out(1) = on(1);
for i = 1:numel(d)
    for m = 1:n(i) - 1
        o = o + 1;  out(o) = on(i) + m * d(i) / n(i);
    end
    o = o + 1;  out(o) = on(i + 1);
end
on = out;
end

% ------------------------------------------------------------------------
function makeFigures(R, roiPoly, mpPoly, outDir)
nm = R.tsName;
nTg = numel(R.targets);
ci = R.controlIdx;
cmap = bwr(256);
tt = R.targetTable;
save1 = @(h, tag) savePNG(h, fullfile(outDir, sprintf('%s_%s.png', nm, tag)), 200);

% --- FOV with targets
f = figure('Visible', 'off', 'Position', [50 50 700 700]);
ax = axes(f);
plot(ax, roiPoly, 'FaceColor', [0.6 0.6 0.6], 'FaceAlpha', 0.3, 'EdgeColor', [0.3 0.3 0.3]); hold(ax, 'on');
for j = 1:nTg
    plot(ax, mpPoly(j), 'FaceColor', 'r', 'FaceAlpha', 0.6, 'EdgeColor', 'r');
    [cx, cy] = centroid(mpPoly(j));
    text(ax, cx + 8, cy, sprintf('T%d (ROI %d)', R.targets(j), tt.ROI(j)), 'Color', 'r', 'FontWeight', 'bold');
end
set(ax, 'YDir', 'reverse');  axis(ax, 'image');  xlim(ax, [0 512]);  ylim(ax, [0 512]);
title(ax, sprintf('%s: targets (red) and ROIs', nm), 'Interpreter', 'none');
save1(f, 'FOV_targets');  close(f);

% --- ETA of each target's own ROI: target stims vs control stims
f = figure('Visible', 'off', 'Position', [50 50 300*nTg 320]);
tl = tiledlayout(f, 1, nTg, 'TileSpacing', 'compact', 'Padding', 'compact');
for j = 1:nTg
    ax = nexttile(tl);  r = tt.ROI(j);
    shaded(ax, R.tw, R.etaMean(r, :, ci), R.etaSEM(r, :, ci), [0.5 0.5 0.5]);
    if j ~= ci
        shaded(ax, R.tw, R.etaMean(r, :, j), R.etaSEM(r, :, j), [0.85 0.1 0.1]);
    end
    xline(ax, 0, 'k--');
    title(ax, sprintf('T%d -> ROI %d', R.targets(j), r));
    xlabel(ax, 'Time from stim (s)');
    if j == 1, ylabel(ax, 'z-scored F'); end
    box(ax, 'off');
end
title(tl, sprintf('%s: target ROI ETAs (red = target stim, gray = control T%d)', nm, R.targets(ci)), 'Interpreter', 'none');
save1(f, 'ETA_targetROIs');  close(f);

% --- Heatmaps: control ETA and (target - control) for all ROIs
c = max(abs(R.etaSub(:)), [], 'omitnan');
cCtrl = max(abs(R.etaMean(:, :, ci)), [], 'all', 'omitnan');
f = figure('Visible', 'off', 'Position', [50 50 280*nTg 700]);
tl = tiledlayout(f, 1, nTg, 'TileSpacing', 'compact', 'Padding', 'compact');
for j = 1:nTg
    ax = nexttile(tl);
    if j == ci
        M = R.etaMean(:, :, ci);  lim = cCtrl;  ttl = sprintf('Control T%d', R.targets(j));
    else
        M = R.etaSub(:, :, j);    lim = c;      ttl = sprintf('T%d - control', R.targets(j));
    end
    [~, ord] = sort(mean(M(:, R.tw >= 0), 2, 'omitnan'), 'descend');
    imagesc(ax, R.tw, 1:size(M, 1), M(ord, :));
    clim(ax, [-lim lim]);  colormap(ax, cmap);  xline(ax, 0, 'k--');
    hold(ax, 'on');
    rowT = find(ord == tt.ROI(j));
    plot(ax, R.tw(1), rowT, 'k>', 'MarkerFaceColor', 'k');
    title(ax, ttl);  xlabel(ax, 'Time (s)');
    if j == 1, ylabel(ax, 'ROIs (sorted by post-stim mean)'); end
    colorbar(ax);
end
title(tl, sprintf('%s: z-scored ETAs (arrow = target ROI)', nm), 'Interpreter', 'none');
save1(f, 'ETA_heatmaps');  close(f);

% --- Population mean of non-target ROIs, (target - control)
f = figure('Visible', 'off', 'Position', [50 50 500 380]);
ax = axes(f);  hold(ax, 'on');
cols = lines(nTg);  hl = gobjects(0);  lab = {};
for j = 1:nTg
    if j == ci, continue, end
    keep = setdiff(1:size(R.etaSub, 1), tt.ROI(j));
    M = R.etaSub(keep, :, j);
    hl(end+1) = shaded(ax, R.tw, mean(M, 1, 'omitnan'), std(M, 0, 1, 'omitnan') / sqrt(numel(keep)), cols(j, :)); %#ok<AGROW>
    lab{end+1} = sprintf('T%d', R.targets(j)); %#ok<AGROW>
end
xline(ax, 0, 'k--');  yline(ax, 0, 'k:');
legend(ax, hl, lab, 'Location', 'best');  xlabel(ax, 'Time from stim (s)');  ylabel(ax, '\Delta z (target - control)');
title(ax, sprintf('%s: mean of non-target ROIs', nm), 'Interpreter', 'none');
save1(f, 'ETA_population');  close(f);

% --- RF maps at peak lag, significant ROIs (up to 36, strongest first)
P = R.RFpeak;
sig = find(P.Significant);
[~, o] = sort(P.PeakAbsZ(sig), 'descend');
sig = sig(o(1:min(36, numel(o))));
if ~isempty(sig)
    nr = ceil(sqrt(numel(sig)));  nc = ceil(numel(sig) / nr);
    f = figure('Visible', 'off', 'Position', [50 50 260*nc 210*nr]);
    tl = tiledlayout(f, nr, nc, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:numel(sig)
        r = sig(i);  L = find(R.RFlags == P.Lag_s(r), 1);
        ax = nexttile(tl);
        rfImage(ax, R, r, L, cmap);
        title(ax, sprintf('ROI %d  lag %.1fs  z=%.1f', r, P.Lag_s(r), P.PeakAbsZ(r) * P.Sign(r)), 'FontSize', 8);
    end
    title(tl, sprintf('%s: significant RFs (z-score at peak lag)', nm), 'Interpreter', 'none');
    save1(f, 'RF_significant');  close(f);
end

% --- RF across lags for each target ROI
nL = numel(R.RFlags);
f = figure('Visible', 'off', 'Position', [50 50 150*nL 150*nTg]);
tl = tiledlayout(f, nTg, nL, 'TileSpacing', 'tight', 'Padding', 'compact');
for j = 1:nTg
    for L = 1:nL
        ax = nexttile(tl);
        rfImage(ax, R, tt.ROI(j), L, cmap);
        set(ax, 'XTick', [], 'YTick', []);
        if j == 1, title(ax, sprintf('%.1f s', R.RFlags(L)), 'FontSize', 8); end
        if L == 1, ylabel(ax, sprintf('T%d / ROI %d', R.targets(j), tt.ROI(j)), 'FontSize', 8); end
    end
end
title(tl, sprintf('%s: target-ROI RFs by lag (z, clim \\pm5)', nm), 'Interpreter', 'none');
save1(f, 'RF_targetROIs_lags');  close(f);
end

function makeGridFigures(R, outDir)
% One figure per non-control target: every ROI's dF/F0 ETA (red = target,
% gray = control), shared y-limits, target ROI title in red.
nROI = size(R.dffMean, 1);
ci = R.controlIdx;
nc = ceil(sqrt(nROI));  nr = ceil(nROI / nc);
lim = max(abs(R.dffMean(:, :, setdiff(1:numel(R.targets), ci))), [], 'all', 'omitnan');
lim = min(lim, 0.1);                         % keep small responses visible; target ROIs clip
for j = 1:numel(R.targets)
    if j == ci, continue, end
    f = figure('Visible', 'off', 'Position', [20 20 110*nc 85*nr]);
    tl = tiledlayout(f, nr, nc, 'TileSpacing', 'none', 'Padding', 'compact');
    for r = 1:nROI
        ax = nexttile(tl);  hold(ax, 'on');
        plot(ax, R.tw, R.dffMean(r, :, ci), 'Color', [0.6 0.6 0.6]);
        plot(ax, R.tw, R.dffMean(r, :, j), 'Color', [0.85 0.1 0.1], 'LineWidth', 1);
        xline(ax, 0, 'k:');
        xlim(ax, R.tw([1 end]));  ylim(ax, [-lim lim]);
        set(ax, 'XTick', [], 'YTick', []);
        c = 'k';  if r == R.targetTable.ROI(j), c = 'r'; end
        text(ax, R.tw(1), lim * 0.8, sprintf(' %d', r), 'FontSize', 7, 'Color', c);
    end
    title(tl, sprintf('%s: T%d dF/F0 (red) vs control T%d (gray), y = %s%.2f', R.tsName, ...
        R.targets(j), R.targets(ci), char(177), lim), 'Interpreter', 'none');
    savePNG(f, fullfile(outDir, sprintf('%s_dFF_grid_T%d.png', R.tsName, R.targets(j))), 150);
    close(f);
end
end

function makeRFCondFigures(R, outDir)
% For each conditional RF: every non-target ROI's map at its peak lag.
cmap = bwr(256);
nonT = setdiff(1:size(R.Z, 1), R.targetTable.ROI);
nc = ceil(sqrt(numel(nonT)));  nr = ceil(numel(nonT) / nc);
for c = 1:numel(R.RFcond)
    C = R.RFcond(c);  P = C.peak;
    f = figure('Visible', 'off', 'Position', [20 20 125*nc 110*nr]);
    tl = tiledlayout(f, nr, nc, 'TileSpacing', 'tight', 'Padding', 'compact');
    for r = nonT
        L = find(R.RFlags == P.Lag_s(r), 1);
        ax = nexttile(tl);
        imagesc(ax, R.xDeg, R.yDeg, squeeze(C.RFz(r, :, :, L)));
        axis(ax, 'xy');  axis(ax, 'image');  clim(ax, [-5 5]);  colormap(ax, cmap);
        set(ax, 'XTick', [], 'YTick', []);
        col = [0.4 0.4 0.4];  fw = 'normal';
        if P.Significant(r), col = [0.8 0 0];  fw = 'bold'; end
        title(ax, sprintf('%d  %.1fs  %.1f', r, P.Lag_s(r), P.Sign(r) * P.PeakAbsZ(r)), ...
            'FontSize', 7, 'Color', col, 'FontWeight', fw);
    end
    if isinf(C.epoch(2)), ep = sprintf('%g s to next stim', C.epoch(1));
    else, ep = sprintf('%g-%g s after stim', C.epoch); end
    title(tl, sprintf(['%s: non-target RFs during T%d stims (%s, %d frames). ' ...
        'Title = ROI, peak lag, z; red = |z| >= %g; color = z, %s5'], R.tsName, C.target, ep, ...
        C.nFrames, R.opts.RFzThresh, char(177)), 'Interpreter', 'none', 'FontSize', 10);
    savePNG(f, fullfile(outDir, sprintf('%s_RF_nontargets_duringT%d.png', R.tsName, C.target)), 150);
    close(f);
end
end

function makeTraceFigures(R, outDir)
% Whole-recording trace of each target ROI: dF/F0 (red, left axis) and
% z-score (blue, right axis). Top: full recording; bottom: 2-min zoom.
% Black ticks = stims of that target.
red = [0.85 0.1 0.1];  blue = [0.1 0.3 0.85];
for j = 1:numel(R.targets)
    r = R.targetTable.ROI(j);
    st = R.trig(R.trigTarget == R.targets(j));
    f = figure('Visible', 'off', 'Position', [20 20 1600 650]);
    tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    zoomWin = max(st(1) - 10, R.tImg(1)) + [0 120];
    for k = 1:2
        ax = nexttile(tl);
        yyaxis(ax, 'left');
        plot(ax, R.tImg, R.dFF(r, :), '-', 'Color', red, 'LineWidth', 0.6);
        ylabel(ax, '\DeltaF/F_0');  ax.YAxis(1).Color = red;
        yyaxis(ax, 'right');
        plot(ax, R.tImg, R.Z(r, :), '-', 'Color', [blue 0.7], 'LineWidth', 0.6);
        ylabel(ax, 'z-score');  ax.YAxis(2).Color = blue;
        hold(ax, 'on');
        yl = ylim(ax);
        if k == 1
            xlim(ax, R.tImg([1 end]));
            plot(ax, st, repmat(yl(2), size(st)), 'k|', 'MarkerSize', 6);
            title(ax, sprintf('T%d -> ROI %d, whole recording (ticks = T%d stims, n = %d)', ...
                R.targets(j), r, R.targets(j), numel(st)));
        else
            xlim(ax, zoomWin);
            xline(ax, st(st >= zoomWin(1) & st <= zoomWin(2)), 'k:');
            title(ax, sprintf('Zoom %.0f-%.0f s (dotted = T%d stims)', zoomWin, R.targets(j)));
            xlabel(ax, 'Time (s)');
        end
        ylim(ax, yl);
        box(ax, 'off');
    end
    title(tl, sprintf('%s: ROI %d (red = %sF/F0, sliding %g s / %gth pct baseline; blue = z-score)', ...
        R.tsName, r, char(916), R.opts.F0Window, R.opts.F0Percentile), 'Interpreter', 'none');
    savePNG(f, fullfile(outDir, sprintf('%s_trace_T%d_ROI%d.png', R.tsName, R.targets(j), r)), 150);
    close(f);
end
end

function makePeakFrameFigure(R, outDir)
% Per target: average noise frame (gray levels) and its z-score.
PF = R.peakFrame;  n = numel(PF);
cmap = bwr(256);
f = figure('Visible', 'off', 'Position', [20 20 760 230*n]);
tl = tiledlayout(f, n, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for j = 1:n
    ax = nexttile(tl);
    imagesc(ax, R.xDeg, R.yDeg, PF(j).avg);
    axis(ax, 'xy');  axis(ax, 'image');  clim(ax, [0 255]);  colormap(ax, gray(256));  colorbar(ax);
    title(ax, sprintf('T%d (ROI %d): mean frame at %+.2f s (peak %.2f s %+.2f), n = %d', PF(j).target, ...
        PF(j).roi, PF(j).tFrame, PF(j).tPeak, R.opts.PeakFrameOffset, PF(j).n), 'FontSize', 8);
    ax = nexttile(tl);
    imagesc(ax, R.xDeg, R.yDeg, PF(j).z);
    axis(ax, 'xy');  axis(ax, 'image');  clim(ax, [-4 4]);  colormap(ax, cmap);  colorbar(ax);
    title(ax, sprintf('z vs noise statistics (max |z| = %.2f; frame %s after stim frame)', ...
        max(abs(PF(j).z(:))), mat2str(PF(j).frameOffset)), 'FontSize', 8);
end
xlabel(tl, 'Azimuth (deg)');  ylabel(tl, 'Elevation (deg)');
title(tl, {R.tsName, sprintf('Noise frame %+.0f ms from each target''s peak response', ...
    R.opts.PeakFrameOffset * 1000)}, 'Interpreter', 'none', 'FontSize', 9);
savePNG(f, fullfile(outDir, sprintf('%s_NoiseAtPeak.png', R.tsName)), 150);
close(f);
end

function F0 = runningPercentile(F, t, win, p)
% Sliding-window percentile of each row of F, evaluated every win/4 s and
% linearly interpolated to every frame.
centers = t(1):win/4:t(end);
if centers(end) < t(end), centers(end+1) = t(end); end
vals = zeros(size(F, 1), numel(centers));
for k = 1:numel(centers)
    idx = abs(t - centers(k)) <= win/2;
    vals(:, k) = prctile(F(:, idx), p, 2);
end
F0 = interp1(centers, vals', t, 'linear')';
F0 = max(F0, eps);
end

function savePNG(h, file, dpi)
% Save a figure; warn instead of stopping if the file is locked (e.g. open in a viewer).
try
    exportgraphics(h, file, 'Resolution', dpi);
catch err
    warning('Could not save %s (is it open in another program?): %s', file, err.message);
end
end

function rfImage(ax, R, r, L, cmap)
imagesc(ax, R.xDeg, R.yDeg, squeeze(R.RFz(r, :, :, L)));
axis(ax, 'xy');  axis(ax, 'image');
clim(ax, [-5 5]);  colormap(ax, cmap);
end

function h = shaded(ax, x, m, e, col)
hold(ax, 'on');
fill(ax, [x fliplr(x)], [m + e, fliplr(m - e)], col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
h = plot(ax, x, m, 'Color', col, 'LineWidth', 1.5);
end

function c = bwr(m)
h = floor(m/2);  up = linspace(0, 1, h)';  dn = flipud(linspace(0, 1, m - h)');
c = [[up; ones(m - h, 1)], [up; dn], [ones(h, 1); dn]];
end
