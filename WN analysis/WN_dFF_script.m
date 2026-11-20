function D = WN_dFF_script(dataPath, opts)
%  WN_DFF_LIVE Whole-recording dF/F0 for every ROI, plus matching of each opto target (markpoint)
% to an ROI.
%
% D = WN_dFF_live(dataPath)
%
% D = WN_dFF_live(dataPath, 'F0Window', 60, 'F0Percentile', 10, 'TargetROI',
% [7 124])
%
% Options
%%
% * F0Window (60): sliding window (s) for the baseline
% * F0Percentile (10): percentile of F in that window used as F0
% * TargetROI ([]): manual matches [target roi; ...], override the automatic
% match
% * PlotFOV (true): show ROIs, targets and matches
% * OutRoot: results go to OutRoot\Results\(TSeries name)\
% * Save (true): save D as (TSeries name)_dFF_targets.mat
arguments
    dataPath (1,:) char
    opts.F0Window (1,1) double {mustBePositive} = 60
    opts.F0Percentile (1,1) double {mustBeInRange(opts.F0Percentile, 0, 100)} = 10
    opts.TargetROI (:,2) double = zeros(0, 2)
    opts.PlotFOV (1,1) logical = true
    opts.OutRoot (1,:) char = 'D:\Data\Claude Projects\WN analysis'
    opts.Save (1,1) logical = true
end
%% Load data
% ROI_Data.rawResponse is F (ROIs x frames), relativeTime is the time of each
% imaging frame, markpointData holds the time (Trigger) and target (Index) of
% every opto stim, markPointCharacteristics holds where each target is.
dataPath = regexprep(dataPath, '[\\/]+$', '');
[~, tsName] = fileparts(dataPath);
S = load(fullfile(dataPath, 'ROI_Data.mat'), 'ROI_Data');
ROI_Data = S.ROI_Data;
F = double(vertcat(ROI_Data.rawResponse));
S = load(fullfile(dataPath, 'relativeTime.mat'), 'relativeTime');
t = S.relativeTime(:)';
assert(size(F, 2) == numel(t), 'rawResponse has %d frames but relativeTime has %d.', size(F, 2), numel(t));
S = load(fullfile(dataPath, 'markpointData.mat'), 'markpointData');
trig   = [S.markpointData.Trigger]';
target = [S.markpointData.Index]';
S = load(fullfile(dataPath, 'markPointCharacteristics.mat'), 'MarkPointCharacteristics');
MPC = S.MarkPointCharacteristics;
%% dF/F0
% F0 is the F0Percentile-th percentile of F within a F0Window-second window,
% evaluated every F0Window/4 s and interpolated to every frame. dF/F0 = (F - F0)
% / F0.
F0  = slidingPercentile(F, t, opts.F0Window, opts.F0Percentile);
dFF = (F - F0) ./ F0;
Dfbyf0_hui = slidingPercentile_Hui(F, t, opts.F0Window, opts.F0Percentile);

%% Zscore
% calculate the zscore of the raw fluoresence
ZDfbyf0 = calc_zscore(Dfbyf0_hui);


% from   Furutachi et al 2024 z-scored ΔF/F was computed by subtracting the mean value of
% ΔF/F of a session and dividing the resulting trace by the standard deviation.

%% Match each opto target to an ROI
% Same method as the influence analysis:
%%
% # ROI outlines (roiPoly) are shifted by the mean yxShift (registration offset).
% # Each target is a 16-point circle: centre = [X Y] x resolution, radius =
% Width/2 x resolution.
% # One ROI overlaps the target: take it. Several overlap: take the one with
% the smallest area(subtract(target, ROI)), i.e. the largest overlap. None overlap:
% take the ROI with the closest centroid.
% # Matches given in TargetROI replace the automatic ones.
res = size(ROI_Data(1).mask);                          % [rows cols], e.g. 512 x 512
umPerPx = ROI_Data(1).Parameters.micronsPerPixel(1).valueAttribute;
if isfile(fullfile(dataPath, 'yxShift.mat'))
    S = load(fullfile(dataPath, 'yxShift.mat'), 'yxShift');
    avgy = mean(S.yxShift(:, 1));
    avgx = mean(S.yxShift(:, 2));
else
    avgy = 0;  avgx = 0;
    warning('No yxShift.mat in the folder; ROI outlines are not shifted.');
end
warning('off', 'MATLAB:polyshape:repairedBySimplify');
nROI = numel(ROI_Data);
ROI_poly = repmat(polyshape(), nROI, 1);
for i = 1:nROI
    ROI_poly(i) = polyshape(ROI_Data(i).roiPoly + [avgx avgy]);
end
[ROI_x, ROI_y] = centroid(ROI_poly);
MPT = struct2table(MPC);
[markpoints, first] = unique(MPT.Index);
centers = [MPT.X(first) * res(1), MPT.Y(first) * res(2)];
radii   = MPT.Width(first) / 2 * res(1);
nMP = numel(markpoints);
th = (0:15)' * 2*pi/16;
MP_poly = repmat(polyshape(), nMP, 1);
for k = 1:nMP
    MP_poly(k) = polyshape(centers(k, 1) + radii(k)*cos(th), centers(k, 2) + radii(k)*sin(th));
end
[MP_x, MP_y] = centroid(MP_poly);
ROI_MP = zeros(nMP, 1);
nOverlap = zeros(nMP, 1);
for k = 1:nMP
    overlapi = find(overlaps(MP_poly(k), ROI_poly));
    nOverlap(k) = numel(overlapi);
    if numel(overlapi) > 1
        A = arrayfun(@(j) area(subtract(MP_poly(k), ROI_poly(j))), overlapi);
        [~, best] = min(A);
        ROI_MP(k) = overlapi(best);
    elseif isscalar(overlapi)
        ROI_MP(k) = overlapi;
    else
        [~, ROI_MP(k)] = min(hypot(ROI_x - MP_x(k), ROI_y - MP_y(k)));
    end
end
autoROI = ROI_MP;
manual = false(nMP, 1);
for m = 1:size(opts.TargetROI, 1)
    k = find(markpoints == opts.TargetROI(m, 1));
    if isempty(k)
        warning('TargetROI: target %d was not stimulated.', opts.TargetROI(m, 1));
        continue
    end
    ROI_MP(k) = opts.TargetROI(m, 2);
    manual(k) = true;
end
dist_um = hypot(ROI_x(ROI_MP) - MP_x, ROI_y(ROI_MP) - MP_y) * umPerPx;
nStims  = arrayfun(@(x) nnz(target == x), markpoints);
targetTable = table(markpoints, ROI_MP, autoROI, nOverlap, round(dist_um, 1), manual, nStims, ...
    'VariableNames', {'Target', 'ROI', 'AutoROI', 'nOverlapping', 'Distance_um', 'Manual', 'nStims'});
disp(targetTable)
%% Plot FOV
% Gray = ROIs, red circles = targets, filled = the matched ROI.
if opts.PlotFOV
    figure('Name', [tsName ' targets'], 'Position', [50 50 700 700]);
    ax = axes;
    plot(ax, ROI_poly, 'FaceColor', [0.75 0.75 0.75], 'FaceAlpha', 0.3, 'EdgeColor', [0.4 0.4 0.4]);
    hold(ax, 'on');
    for k = 1:nMP
        plot(ax, ROI_poly(ROI_MP(k)), 'FaceColor', [1 0.6 0], 'FaceAlpha', 0.7, 'EdgeColor', 'k');
        plot(ax, MP_poly(k), 'FaceColor', 'none', 'EdgeColor', 'r', 'LineWidth', 1.5);
        text(ax, MP_x(k) + radii(k) + 3, MP_y(k), sprintf('T%d - ROI %d', markpoints(k), ROI_MP(k)), ...
            'Color', 'r', 'FontWeight', 'bold');
    end
    text(ax, ROI_x, ROI_y, string(1:nROI), 'FontSize', 6, 'HorizontalAlignment', 'center', ...
        'Color', [0.3 0.3 0.3]);
    set(ax, 'YDir', 'reverse');
    axis(ax, 'image');
    xlim(ax, [0 res(2)]);  ylim(ax, [0 res(1)]);
    title(ax, {tsName, 'targets (red) and matched ROIs (orange)'}, 'Interpreter', 'none', 'FontSize', 9);
end
%% Output
D = struct('tsName', tsName, 'dataPath', dataPath, 't', t, 'F', F, 'F0', F0, 'dFF', dFF, ...
    'trig', trig, 'target', target, 'targets', markpoints, 'targetTable', targetTable, ...
    'roiXY', [ROI_x(:) ROI_y(:)], 'targetXY', [MP_x(:) MP_y(:)], 'targetRadius', radii, ...
    'roiShift', [avgx avgy], 'opts', opts, 'Dfbyf0_hui', Dfbyf0_hui, 'ZDfbyf0', ZDfbyf0);
fprintf('%s: %d ROIs, %d frames (%.0f s), %d opto stims, %d targets\n', ...
    tsName, nROI, numel(t), t(end) - t(1), numel(trig), nMP);
if opts.Save
    outDir = fullfile(opts.OutRoot, 'Results', tsName);
    if ~isfolder(outDir), mkdir(outDir); end
    save(fullfile(outDir, [tsName '_dFF_targets.mat']), 'D', '-v7.3');
end
end

%% Local functions
function F0 = slidingPercentile(F, t, win, p)
centers = t(1):win/4:t(end);
if centers(end) < t(end), centers(end+1) = t(end); end
vals = zeros(size(F, 1), numel(centers));
for k = 1:numel(centers)
    inWin = abs(t - centers(k)) <= win/2;
    vals(:, k) = prctile(F(:, inWin), p, 2);
end
F0 = interp1(centers, vals', t, 'linear')';
F0 = max(F0, eps);
end

%%

% Hui style sliding percentage DfbyF0  from  DeltaFbyFo = postProcess_processROI_LinearTrack(F, relativeTime)
% removed the median portion
function DeltaFbyFo =  slidingPercentile_Hui(F, relativeTime, TimeWindow, PercentileValue)
[nROI, nPoints] = size(F);
F0 = zeros(nROI, nPoints);
lo = 1;  hi = 1;
for ii = 1:nPoints
    % window = frames within +/- TimeWindow s of frame ii
    while relativeTime(lo) < relativeTime(ii) - TimeWindow
        lo = lo + 1;
    end
    while hi < nPoints && relativeTime(hi + 1) <= relativeTime(ii) + TimeWindow
        hi = hi + 1;
    end
    % one prctile call per frame, for ALL ROIs at once (row-wise, dim 2)
    F0(:, ii) = prctile(F(:, lo:hi), PercentileValue, 2);
end
% SmoothTrace = F - F0;
% MedianValue = median(SmoothTrace, 2);                   % nROI x 1, one per ROI
% DeltaFbyFo  = (SmoothTrace - MedianValue) ./ MedianValue;   % implicit expansion
DeltaFbyFo  = (F - F0) ./ F0;
end

%%
function[zscorred]= calc_zscore(F)
% First, calculate the mean of each column in the data matrix. 
% Subtract all the elements of each column from the mean of each column, 
% adjusting the mean of each column to 0. Then, calculate the standard 
% deviation for each column in the data matrix. Then, divide all elements
% in each column minus the mean by the standard deviation of that column, 
% thus adjusting the standard deviation of each column to 1. The standardized
% data have the characteristics of mean 0 and standard deviation 1. 

avg_ROI = mean(F, 2);
std_ROI = std(F, [], 2);
F0 = F-avg_ROI;
zscorred = F0./std_ROI;

end