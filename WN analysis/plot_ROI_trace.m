function ax = plot_ROI_trace(D, r, opts)
% plot_ROI_trace  Plot one ROI's whole-recording dF/F0 (output of WN_dFF).
%
%   plot_ROI_trace(D, r)                      new figure
%   plot_ROI_trace(D, r, 'Parent', ax)        draw into existing axes
%   plot_ROI_trace(D, r, 'ShowStims', false)  hide opto stim ticks
%   plot_ROI_trace(D, r, 'ControlTarget', []) hide the control-stim lines
%
%   dF/F0 is drawn in black. Each stim of the control target (default T1)
%   is a vertical line; all opto stims are also drawn as ticks along the
%   top, one colour per target.

arguments
    D (1,1) struct
    r (1,1) double {mustBeInteger, mustBePositive}
    opts.Parent = []
    opts.ShowStims (1,1) logical = true
    opts.ControlTarget double = 1
end
assert(r <= size(D.dFF, 1), 'ROI %d does not exist (%d ROIs).', r, size(D.dFF, 1));

if isempty(opts.Parent)
    figure('Position', [50 50 1400 400]);
    ax = axes;
else
    ax = opts.Parent;
    cla(ax, 'reset');
end

hold(ax, 'on');
hCtrl = gobjects(0);
if ~isempty(opts.ControlTarget)
    ctrlStims = D.trig(D.target == opts.ControlTarget);
    if isempty(ctrlStims)
        warning('No stims of control target T%d.', opts.ControlTarget);
    else
        hCtrl = xline(ax, ctrlStims, '-', 'Color', [0 0.45 0.9], 'Alpha', 0.35, 'LineWidth', 0.5);
        hCtrl = hCtrl(1);
    end
end
% plot(ax, D.t, D.dFF(r, :), 'Color', 'r', 'LineWidth', 0.6); 
plot(ax, D.t, D.Dfbyf0_hui(r, :), 'Color', 'k', 'LineWidth', 0.6);
% plot(ax, D.t, D.ZDfbyf0(r, :), 'Color', 'r', 'LineWidth', 0.25);
xlim(ax, D.t([1 end]));
xlabel(ax, 'Time (s)');
ylabel(ax, [char(916) 'F/F_0']);
title(ax, sprintf('%s  -  ROI %d', D.tsName, r), 'Interpreter', 'none');
box(ax, 'off');

if opts.ShowStims
    yl = ylim(ax);
    cols = lines(numel(D.targets));
    h = gobjects(numel(D.targets), 1);
    for j = 1:numel(D.targets)
        st = D.trig(D.target == D.targets(j));
        h(j) = plot(ax, st, repmat(yl(2), size(st)), '|', 'Color', cols(j, :), 'MarkerSize', 8, 'LineWidth', 1);
    end
    ylim(ax, yl);
    labels = compose('T%d stim', D.targets);
    if ~isempty(hCtrl)
        h = [hCtrl; h];
        labels = [{sprintf('T%d (control) stim', opts.ControlTarget)}; labels(:)];
    end
    legend(ax, h, labels, 'Orientation', 'horizontal', 'Location', 'southoutside');
elseif ~isempty(hCtrl)
    legend(ax, hCtrl, sprintf('T%d (control) stim', opts.ControlTarget), 'Location', 'southoutside');
end
hold(ax, 'off');
end
