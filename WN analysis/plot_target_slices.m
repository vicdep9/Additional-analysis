function win = plot_target_slices(D, opts)
% plot_target_slices  Random short slice of each target ROI's trace, one panel per target.
%
%   win = plot_target_slices(D)
%   win = plot_target_slices(D, 'Duration', 10, 'SameWindow', false, 'Seed', [], 'Signal', 'Dfbyf0_hui')
%
%   D comes from WN_dFF_script. One figure, panels stacked, one per target in
%   D.targetTable. Signal in black; the target's own opto stims are red lines;
%   ticks along the top are all opto stims, one colour per target (as in
%   plot_ROI_trace).
%
% Options
%   Duration (10)       s per slice
%   SameWindow (false)  true = the same random window for every target
%   Seed ([])           rng seed for reproducible slices; [] = shuffle
%   Signal ('Dfbyf0_hui')  field of D to plot (e.g. 'dFF', 'ZDfbyf0')
%   ShowStims (true)    ticks for all opto stims
%
%   Returns win, nTargets x 2, the [start end] time (s) of each slice.

arguments
    D (1,1) struct
    opts.Duration (1,1) double {mustBePositive} = 10
    opts.SameWindow (1,1) logical = false
    opts.Seed double = []
    opts.Signal (1,:) char = 'Dfbyf0_hui'
    opts.ShowStims (1,1) logical = true
end
assert(isfield(D, opts.Signal), 'D has no field "%s".', opts.Signal);
assert(opts.Duration < D.t(end) - D.t(1), 'Duration is longer than the recording.');
if isempty(opts.Seed), rng('shuffle'); else, rng(opts.Seed); end

sig = D.(opts.Signal);
T = D.targetTable;
nT = height(T);
cols = lines(numel(D.targets));

% random start times, so that the whole slice fits in the recording
startRange = [D.t(1), D.t(end) - opts.Duration];
if opts.SameWindow
    starts = repmat(startRange(1) + rand * diff(startRange), nT, 1);
else
    starts = startRange(1) + rand(nT, 1) * diff(startRange);
end
win = [starts, starts + opts.Duration];

figure('Name', [D.tsName ' target slices'], 'Position', [50 50 900 170 * nT]);
tl = tiledlayout(nT, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:nT
    ax = nexttile(tl);
    hold(ax, 'on');
    r = T.ROI(k);
    inWin = D.t >= win(k, 1) & D.t <= win(k, 2);

    own = D.trig(D.target == T.Target(k));
    own = own(own >= win(k, 1) & own <= win(k, 2));
    if ~isempty(own)
        xline(ax, own, '-', 'Color', [0.85 0.1 0.1], 'LineWidth', 1);
    end
    plot(ax, D.t(inWin), sig(r, inWin), 'k', 'LineWidth', 0.8);
    xlim(ax, win(k, :));

    if opts.ShowStims
        yl = ylim(ax);
        for j = 1:numel(D.targets)
            st = D.trig(D.target == D.targets(j));
            st = st(st >= win(k, 1) & st <= win(k, 2));
            plot(ax, st, repmat(yl(2), size(st)), '|', 'Color', cols(j, :), ...
                'MarkerSize', 8, 'LineWidth', 1.5);
        end
        ylim(ax, yl);
    end
    ylabel(ax, opts.Signal, 'Interpreter', 'none');
    title(ax, sprintf('T%d - ROI %d   (%.1f-%.1f s, %d own stims)', ...
        T.Target(k), r, win(k, 1), win(k, 2), numel(own)), 'FontWeight', 'normal');
    box(ax, 'off');
    hold(ax, 'off');
end
xlabel(tl, 'Time (s)');
title(tl, sprintf('%s - random %g s slices (red = own stims)', D.tsName, opts.Duration), ...
    'Interpreter', 'none', 'FontSize', 9);
end
