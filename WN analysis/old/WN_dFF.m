function D = WN_dFF(dataPath, opts)
% WN_dFF  Whole-recording dF/F0 for every ROI in a processed TSeries folder.
%
%   D = WN_dFF(dataPath)
%   D = WN_dFF(dataPath, 'F0Window', 60, 'F0Percentile', 10, 'OutRoot', folder, 'Save', true)
%
%   Reads from dataPath:
%     ROI_Data.mat       ROI_Data(r).rawResponse  -> F (ROIs x frames)
%     relativeTime.mat   time of each imaging frame (s)
%     markpointData.mat  Trigger (opto stim time, s) and Index (target)
%
%   F0 is a sliding baseline: the F0Percentile-th percentile of F within a
%   F0Window-second window, evaluated every F0Window/4 s and interpolated
%   to every frame.  dF/F0 = (F - F0) ./ F0.
%
%   Output struct D (also saved to <OutRoot>\Results\<TSeries>\<TSeries>_dFF.mat):
%     tsName, dataPath, t (1 x frames), F, F0, dFF (ROIs x frames),
%     trig (stims x 1), target (stims x 1), targets, opts

arguments
    dataPath (1,:) char
    opts.F0Window (1,1) double {mustBePositive} = 60
    opts.F0Percentile (1,1) double {mustBeInRange(opts.F0Percentile, 0, 100)} = 10
    opts.OutRoot (1,:) char = 'D:\Data\Claude Projects\WN analysis'
    opts.Save (1,1) logical = true
end

dataPath = regexprep(dataPath, '[\\/]+$', '');
[~, tsName] = fileparts(dataPath);

S = load(fullfile(dataPath, 'ROI_Data.mat'), 'ROI_Data');
F = double(vertcat(S.ROI_Data.rawResponse));
S = load(fullfile(dataPath, 'relativeTime.mat'), 'relativeTime');
t = S.relativeTime(:)';
assert(size(F, 2) == numel(t), 'rawResponse has %d frames but relativeTime has %d.', size(F, 2), numel(t));
S = load(fullfile(dataPath, 'markpointData.mat'), 'markpointData');
trig   = [S.markpointData.Trigger]';
target = [S.markpointData.Index]';

F0  = slidingPercentile(F, t, opts.F0Window, opts.F0Percentile);
dFF = (F - F0) ./ F0;

D = struct('tsName', tsName, 'dataPath', dataPath, 't', t, 'F', F, 'F0', F0, 'dFF', dFF, ...
    'trig', trig, 'target', target, 'targets', unique(target), 'opts', opts);

fprintf('%s: %d ROIs, %d frames (%.0f s), %d opto stims\n', tsName, size(F, 1), numel(t), t(end) - t(1), numel(trig));

if opts.Save
    outDir = fullfile(opts.OutRoot, 'Results', tsName);
    if ~isfolder(outDir), mkdir(outDir); end
    save(fullfile(outDir, [tsName '_dFF.mat']), 'D', '-v7.3');
end
end

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
