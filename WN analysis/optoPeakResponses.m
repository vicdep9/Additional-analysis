function P = optoPeakResponses(D, opts)
% optoPeakResponses  Peak response of each target's ROI to every one of its opto stims.
%
%   P = optoPeakResponses(D)
%   P = optoPeakResponses(D, 'PeakWindow', [0 1.5], 'Signal', 'Dfbyf0_hui')
%
%   D comes from WN_dFF_script (needs t, trig, target, targetTable and the
%   signal field, default Dfbyf0_hui).
%
%   P is a struct array, one element per target. Scalar fields:
%     Target, ROI, PeakWindow
%   Column fields, one row per stim of that target:
%     StimTime     opto trigger time (s)
%     StimFrame    first imaging frame at or after the trigger
%     PeakValue    max of the signal in [StimTime + PeakWindow(1), StimTime + PeakWindow(2)]
%     PeakTime     time of that maximum (s)
%     PeakFrame    frame of that maximum
%     PeakLatency  PeakTime - StimTime (s)

arguments
    D (1,1) struct
    opts.PeakWindow (1,2) double = [0 1.5]     % s after each stim to search for the peak
    opts.Signal (1,:) char = 'Dfbyf0_hui'
end
assert(isfield(D, opts.Signal), 'D has no field "%s".', opts.Signal);
assert(opts.PeakWindow(2) > opts.PeakWindow(1), 'PeakWindow must be [start end] with end > start.');

sig = D.(opts.Signal);
t = D.t(:)';
T = D.targetTable;

P = struct('Target', {}, 'ROI', {}, 'PeakWindow', {}, 'StimTime', {}, 'StimFrame', {}, ...
    'PeakValue', {}, 'PeakTime', {}, 'PeakFrame', {}, 'PeakLatency', {});

for k = 1:height(T)
    roi = T.ROI(k);
    stimTime = D.trig(D.target == T.Target(k));
    stimTime = stimTime(:);
    n = numel(stimTime);

    stimFrame   = nan(n, 1);
    peakValue   = nan(n, 1);
    peakFrame   = nan(n, 1);
    for s = 1:n
        f = find(t >= stimTime(s), 1, 'first');
        if isempty(f), continue, end                        % stim after the last frame
        stimFrame(s) = f;
        inWin = find(t >= stimTime(s) + opts.PeakWindow(1) & t <= stimTime(s) + opts.PeakWindow(2));
        if isempty(inWin), continue, end
        [peakValue(s), i] = max(sig(roi, inWin));
        peakFrame(s) = inWin(i);
    end
    peakTime = nan(n, 1);
    ok = ~isnan(peakFrame);
    peakTime(ok) = t(peakFrame(ok));

    P(k).Target      = T.Target(k);
    P(k).ROI         = roi;
    P(k).PeakWindow  = opts.PeakWindow;
    P(k).StimTime    = stimTime;
    P(k).StimFrame   = stimFrame;
    P(k).PeakValue   = peakValue;
    P(k).PeakTime    = peakTime;
    P(k).PeakFrame   = peakFrame;
    P(k).PeakLatency = peakTime - stimTime;

    figure('Position',[ 100, 100, 1000, 300])
    plot(peakTime, peakValue,  'r*'); hold on
    xline(stimTime);
    xlabel('Time (s)'); ylabel(opts.Signal, 'Interpreter', 'none');
    title(sprintf('T%d - ROI %d', T.Target(k), roi));
end

if any(arrayfun(@(p) any(isnan(p.PeakFrame)), P))
    warning('Some stims had no imaging frames in the peak window (e.g. at the end of the recording); their values are NaN.');
end
end
