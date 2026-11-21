classdef TSeriesImageViewerv4 < matlab.apps.AppBase
    % TSeriesImageViewerv4  GUI for the Pstim dF/F0 / subtraction image analysis.
    %
    %   1. Browse to a processed TSeries folder (contains stimulusData.mat,
    %      markpointData.mat and ResponsesChannel.tif).
    %   2. Click "Load & Process". The frame-averaged tiffs are cached in
    %      <folder>\-tiffs_<N>frameavg.mat, exactly as in the original script.
    %   3. Pick the image type, target and condition to view
    %      ("All conditions" = the grid; or one condition on its own).
    %   4. Pick an output folder and save the current plot (grid or the
    %      single condition shown), or "Save all" grids.
    %
    %   Overlay (Target = "Overlay: all targets except T1"): each target in
    %   its own colour. Two settings clean up the background:
    %     Threshold (x noise SD): per target, only pixels more than this many
    %       robust SDs (median absolute deviation) above that target's median
    %       are shown. 0 = off.
    %     Smoothing sigma (px): Gaussian blur of each map before the
    %       threshold, removes single-pixel speckle. 0 = off.
    %
    %   "Same colour scale for all targets": the single-target views (grid
    %   and single condition) use one colour range, +/- the largest |value|
    %   over every target and condition of the selected image type, instead
    %   of each target's own range. Also used by "Save all".
    %
    %   Run with:  app = TSeriesImageViewerv4;

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        GridLayout              matlab.ui.container.GridLayout
        ControlPanel            matlab.ui.container.Panel
        ControlGrid             matlab.ui.container.GridLayout
        DataFolderLabel         matlab.ui.control.Label
        DataFolderEditField     matlab.ui.control.EditField
        BrowseDataButton        matlab.ui.control.Button
        AvgWinLabel             matlab.ui.control.Label
        AvgWinSpinner           matlab.ui.control.Spinner
        ProcessButton           matlab.ui.control.Button
        ImageTypeLabel          matlab.ui.control.Label
        ImageTypeDropDown       matlab.ui.control.DropDown
        TargetLabel             matlab.ui.control.Label
        TargetDropDown          matlab.ui.control.DropDown
        ConditionLabel          matlab.ui.control.Label
        ConditionDropDown       matlab.ui.control.DropDown
        PopOutButton            matlab.ui.control.Button
        SameScaleCheckBox       matlab.ui.control.CheckBox
        ThresholdLabel          matlab.ui.control.Label
        ThresholdSpinner        matlab.ui.control.Spinner
        SmoothLabel             matlab.ui.control.Label
        SmoothSpinner           matlab.ui.control.Spinner
        OutFolderLabel          matlab.ui.control.Label
        OutFolderEditField      matlab.ui.control.EditField
        BrowseOutButton         matlab.ui.control.Button
        FileNameLabel           matlab.ui.control.Label
        FileNameEditField       matlab.ui.control.EditField
        FormatDropDown          matlab.ui.control.DropDown
        SaveButton              matlab.ui.control.Button
        SaveAllButton           matlab.ui.control.Button
        OpenFolderButton        matlab.ui.control.Button
        StatusLabel            matlab.ui.control.Label
        PlotPanel               matlab.ui.container.Panel
    end

    % Data shared between callbacks
    properties (Access = private)
        Results = []    % struct returned by processTSeries
        Tiles           % tiledlayout currently shown in PlotPanel
    end

    methods (Access = private)

        function setStatus(app, msg, isError)
            if nargin < 3, isError = false; end
            app.StatusLabel.Text = msg;
            if isError
                app.StatusLabel.FontColor = [0.8 0 0];
            else
                app.StatusLabel.FontColor = [0 0 0];
            end
            drawnow limitrate
        end

        function updatePlot(app)
            R = app.Results;
            if isempty(R) || isempty(app.TargetDropDown.ItemsData)
                return
            end
            field  = app.ImageTypeDropDown.Value;
            target = app.TargetDropDown.Value;
            cond   = app.ConditionDropDown.Value;     % 0 = all conditions
            if strcmp(field, 'subtraction') && isempty(R.subtraction)
                setStatus(app, 'No target 1 (control) in this recording, so no subtraction image.', true);
                return
            end
            [thr, sig] = overlaySettings(app);
            cmax = sharedScale(app, field);
            app.Tiles = TSeriesImageViewerv4.plotImages(app.PlotPanel, R, field, target, cond, thr, sig, cmax);
            app.FileNameEditField.Value = TSeriesImageViewerv4.defaultFileName(R, field, target, cond, thr, sig, ~isempty(cmax));
            app.SaveButton.Enable = 'on';
            app.SaveAllButton.Enable = 'on';
            app.PopOutButton.Enable = 'on';
            isOverlay = matlab.lang.OnOffSwitchState(target == -1);   % settings only apply to the overlay
            app.ThresholdSpinner.Enable = isOverlay;
            app.SmoothSpinner.Enable = isOverlay;
            app.SameScaleCheckBox.Enable = ~isOverlay;                 % overlay already uses one scale
        end

        function [thr, sig] = overlaySettings(app)
            thr = app.ThresholdSpinner.Value;
            sig = app.SmoothSpinner.Value;
        end

        function cmax = sharedScale(app, field)
            % [] = each target uses its own colour range
            cmax = [];
            if app.SameScaleCheckBox.Value
                cmax = TSeriesImageViewerv4.sharedCLim(app.Results, field);
            end
        end

        function outFile = exportCurrent(app, baseName)
            ext = app.FormatDropDown.Value;
            outFile = fullfile(app.OutFolderEditField.Value, [baseName ext]);
            if ismember(ext, {'.png', '.jpg', '.tif'})
                exportgraphics(app.Tiles, outFile, 'Resolution', 300);
            else
                exportgraphics(app.Tiles, outFile, 'ContentType', 'vector');
            end
        end

        function ok = checkOutFolder(app)
            ok = isfolder(app.OutFolderEditField.Value);
            if ~ok
                uialert(app.UIFigure, 'Choose a valid output folder first.', 'No output folder');
            end
        end
    end

    % Callbacks that handle component events
    methods (Access = private)

        function BrowseDataButtonPushed(app, ~)
            startDir = app.DataFolderEditField.Value;
            if ~isfolder(startDir), startDir = pwd; end
            d = uigetdir(startDir, 'Select processed TSeries folder');
            figure(app.UIFigure)   % bring app back to front
            if isequal(d, 0), return, end
            app.DataFolderEditField.Value = d;
            setStatus(app, 'Folder selected. Click "Load & Process".');
        end

        function ProcessButtonPushed(app, ~)
            p = strtrim(app.DataFolderEditField.Value);
            if ~isfolder(p)
                uialert(app.UIFigure, 'Choose a valid TSeries folder first.', 'No data folder');
                return
            end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Processing', ...
                'Message', 'Starting...', 'Indeterminate', 'on');
            cleanup = onCleanup(@() close(dlg));
            try
                app.Results = TSeriesImageViewerv4.processTSeries(p, ...
                    app.AvgWinSpinner.Value, @(m) set(dlg, 'Message', m));
            catch err
                app.Results = [];
                setStatus(app, ['Error: ' err.message], true);
                uialert(app.UIFigure, err.message, 'Processing failed');
                return
            end
            R = app.Results;
            app.TargetDropDown.Items     = compose('Target %d', R.targets(:)');
            app.TargetDropDown.ItemsData = num2cell(R.targets(:)');
            if numel(R.targets) > 1
                % -1 = colour overlay of every target except the control (T1)
                app.TargetDropDown.Items{end+1}     = 'Overlay: all targets except T1';
                app.TargetDropDown.ItemsData{end+1} = -1;
            end
            app.TargetDropDown.Value     = R.targets(1);
            nCond = numel(R.numCond);
            app.ConditionDropDown.Items = [{'All conditions'}, ...
                arrayfun(@(i) TSeriesImageViewerv4.conditionLabel(R, i), 1:nCond, 'UniformOutput', false)];
            app.ConditionDropDown.ItemsData = num2cell(0:nCond);
            app.ConditionDropDown.Value = 0;
            if isempty(app.OutFolderEditField.Value)
                app.OutFolderEditField.Value = p;
            end
            msg = sprintf('%s  T%s: %d targets, %d conditions.', R.name, R.tseriesNum, ...
                numel(R.targets), numel(R.numCond));
            if isempty(R.subtraction)
                msg = [msg ' No target 1, so subtraction images are unavailable.'];
            end
            setStatus(app, msg);
            updatePlot(app);
        end

        function SelectionChanged(app, ~)
            updatePlot(app);
        end

        function PopOutButtonPushed(app, ~)
            % Draw what is currently shown into a normal, resizable figure window
            R = app.Results;
            if isempty(R), return, end
            field  = app.ImageTypeDropDown.Value;
            target = app.TargetDropDown.Value;
            cond   = app.ConditionDropDown.Value;
            if strcmp(field, 'subtraction') && isempty(R.subtraction)
                setStatus(app, 'No target 1 (control) in this recording, so no subtraction image.', true);
                return
            end
            [thr, sig] = overlaySettings(app);
            cmax = sharedScale(app, field);
            f = figure('Name', TSeriesImageViewerv4.defaultFileName(R, field, target, cond, thr, sig, ~isempty(cmax)), ...
                'NumberTitle', 'off', 'Color', 'w', 'Position', [100 100 900 800]);
            TSeriesImageViewerv4.plotImages(f, R, field, target, cond, thr, sig, cmax);
        end

        function BrowseOutButtonPushed(app, ~)
            startDir = app.OutFolderEditField.Value;
            if ~isfolder(startDir), startDir = app.DataFolderEditField.Value; end
            if ~isfolder(startDir), startDir = pwd; end
            d = uigetdir(startDir, 'Select folder to save plots');
            figure(app.UIFigure)
            if isequal(d, 0), return, end
            app.OutFolderEditField.Value = d;
        end

        function SaveButtonPushed(app, ~)
            if ~checkOutFolder(app), return, end
            baseName = strtrim(app.FileNameEditField.Value);
            if isempty(baseName)
                uialert(app.UIFigure, 'Enter a file name.', 'No file name');
                return
            end
            outFile = fullfile(app.OutFolderEditField.Value, [baseName app.FormatDropDown.Value]);
            if isfile(outFile)
                sel = uiconfirm(app.UIFigure, sprintf('%s already exists. Overwrite?', outFile), ...
                    'File exists', 'Options', {'Overwrite', 'Cancel'}, 'DefaultOption', 2);
                if strcmp(sel, 'Cancel'), return, end
            end
            try
                exportCurrent(app, baseName);
                setStatus(app, ['Saved ' outFile]);
            catch err
                setStatus(app, ['Save failed: ' err.message], true);
            end
        end

        function OpenFolderButtonPushed(app, ~)
            if ~checkOutFolder(app), return, end
            d = app.OutFolderEditField.Value;
            if ispc
                winopen(d);
            elseif ismac
                system(sprintf('open "%s"', d));
            else
                system(sprintf('xdg-open "%s" &', d));
            end
        end

        function SaveAllButtonPushed(app, ~)
            if ~checkOutFolder(app), return, end
            R = app.Results;
            fields = {'dfbyf0', 'subtraction'};
            if isempty(R.subtraction), fields = {'dfbyf0'}; end
            origType = app.ImageTypeDropDown.Value;
            origTarget = app.TargetDropDown.Value;
            origCond = app.ConditionDropDown.Value;
            n = numel(fields) * numel(R.targets);
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Saving all plots', 'Cancelable', 'on');
            k = 0;
            try
                for f = 1:numel(fields)
                    cmax = sharedScale(app, fields{f});
                    for t = 1:numel(R.targets)
                        if dlg.CancelRequested, break, end
                        k = k + 1;
                        dlg.Value = k / n;
                        dlg.Message = sprintf('Saving %d of %d', k, n);
                        app.Tiles = TSeriesImageViewerv4.plotImages(app.PlotPanel, R, fields{f}, R.targets(t), 0, 0, 0, cmax);
                        exportCurrent(app, TSeriesImageViewerv4.defaultFileName(R, fields{f}, R.targets(t), 0, 0, 0, ~isempty(cmax)));
                    end
                end
                setStatus(app, sprintf('Saved %d plots to %s', k, app.OutFolderEditField.Value));
            catch err
                setStatus(app, ['Save failed: ' err.message], true);
            end
            close(dlg);
            app.ImageTypeDropDown.Value = origType;
            app.TargetDropDown.Value = origTarget;
            app.ConditionDropDown.Value = origCond;
            updatePlot(app);
        end
    end

    % Analysis and plotting (static, so they can also be called without the GUI)
    methods (Static)

        function R = processTSeries(path, avg_win, statusFcn)
            % Port of the original analysis script. Returns a struct with
            % the dF/F0 and subtraction images for every target.
            if nargin < 3, statusFcn = @(m) []; end
            path = regexprep(path, '[\\/]+$', '');

            [~, Name]   = fileparts(fileparts(fileparts(path)));
            Tseries_num = path(end-3:end);

            statusFcn('Loading stimulusData.mat and markpointData.mat...');
            S = load(fullfile(path, 'stimulusData.mat'), 'stimulusData');
            stimulusData = S.stimulusData;
            M = load(fullfile(path, 'markpointData.mat'), 'markpointData');
            markpointData = M.markpointData;

            condition_frames = stimulusData.stimulusOnsets(:);
            condition_num    = stimulusData.conditionNumbers(:);

            idxVals       = [markpointData.Index];   % same as extractfield(markpointData, 'Index')
            index         = idxVals ~= 0;
            Pstim_framesi = find(index)';
            blank_framesi = find(~index)';
            Target_nums   = idxVals(index)';

            PStim_Frame_strt = condition_frames(Pstim_framesi);
            Pstim_cond       = condition_num(Pstim_framesi);
            blank_Frame_strt = condition_frames(blank_framesi);

            trial_control_log = (Target_nums ~= 1);
            pstim_trials = horzcat(trial_control_log, PStim_Frame_strt, Pstim_cond, Target_nums);

            cachePath = fullfile(path, sprintf('-tiffs_%dframeavg.mat', avg_win));
            cacheOK = false;
            if isfile(cachePath)
                % Use the cache only if it holds both variables with one image
                % per trial. Caches saved before the v7.3 fix can be missing
                % avg_Pstim_tiff (variables > 2 GB were silently skipped).
                vars = who('-file', cachePath);
                if all(ismember({'avg_Pstim_tiff', 'avg_blank_tiff'}, vars))
                    statusFcn('Loading cached frame averages...');
                    C = load(cachePath, 'avg_Pstim_tiff', 'avg_blank_tiff');
                    avg_Pstim_tiff = C.avg_Pstim_tiff;
                    avg_blank_tiff = C.avg_blank_tiff;
                    clear C
                    cacheOK = numel(avg_Pstim_tiff) == numel(PStim_Frame_strt) && ...
                              numel(avg_blank_tiff) == numel(blank_Frame_strt);
                end
                if ~cacheOK
                    warning('TSeriesImageViewer:badCache', ...
                        '%s is incomplete or does not match this recording; rebuilding it from the TIFF.', cachePath);
                end
            end
            if ~cacheOK
                statusFcn('Reading ResponsesChannel.tif (this can take a while)...');
                tiffs = tiffreadVolume(fullfile(path, 'ResponsesChannel.tif'));
                nFrames = size(tiffs, 3);
                statusFcn(sprintf('Averaging %d-frame windows...', avg_win));
                avg_blank_tiff = cell(1, numel(blank_Frame_strt));
                for ii = 1:numel(blank_Frame_strt)
                    fr = blank_Frame_strt(ii):min(blank_Frame_strt(ii) + avg_win, nFrames);
                    avg_blank_tiff{ii} = mean(tiffs(:, :, fr), 3);
                end
                avg_Pstim_tiff = cell(1, numel(PStim_Frame_strt));
                for i = 1:numel(PStim_Frame_strt)
                    fr = PStim_Frame_strt(i):min(PStim_Frame_strt(i) + avg_win, nFrames);
                    avg_Pstim_tiff{i} = mean(tiffs(:, :, fr), 3);
                end
                clear tiffs
                statusFcn('Saving frame-average cache (v7.3, can take a minute for large recordings)...');
                save(cachePath, 'avg_Pstim_tiff', 'avg_blank_tiff', '-v7.3')   % no 2 GB limit
            end

            statusFcn('Computing dF/F0 images...');
            blank_trials    = cat(3, avg_blank_tiff{:});
            pstim_trials_im = cat(3, avg_Pstim_tiff{:});
            avg_blank       = mean(blank_trials, 3);

            targets  = unique(pstim_trials(:, 4));
            num_cond = unique(pstim_trials(:, 3));
            theta    = stimulusData.parameters.Var1Range;

            [h, w] = size(avg_blank);
            dfbyf0_mat = cell(numel(targets), 1);
            for j = 1:numel(targets)
                avg_dfbyf0 = zeros(h, w, numel(num_cond));
                for i = 1:numel(num_cond)
                    sel = pstim_trials(:, 4) == targets(j) & pstim_trials(:, 3) == num_cond(i);
                    avgim_cond = mean(pstim_trials_im(:, :, sel), 3);
                    avg_dfbyf0(:, :, i) = (avgim_cond - avg_blank) ./ avg_blank;  % df/f0
                end
                dfbyf0_mat{j} = avg_dfbyf0;
            end

            % Subtraction relative to the control target (target 1)
            ctrlIdx = find(targets == 1, 1);
            if isempty(ctrlIdx)
                subtraction_im = {};
            else
                ctrl_img = dfbyf0_mat{ctrlIdx};
                subtraction_im = cellfun(@(im) im - ctrl_img, dfbyf0_mat, 'UniformOutput', false);
            end

            R = struct('name', Name, 'tseriesNum', Tseries_num, 'path', path, ...
                'avgWin', avg_win, 'targets', targets, 'numCond', num_cond, ...
                'theta', theta, 'dfbyf0', {dfbyf0_mat}, 'subtraction', {subtraction_im});
        end

        function t = plotImages(parent, R, field, targetn, cond, thr, sig, cmax)
            % Same layout as plot_images.m, but for one target, drawn into
            % PARENT (a panel or figure). Returns the tiledlayout.
            % COND = 0 (default): all conditions as a grid.
            % COND = i: only condition i, as one large image. The colour
            % scale is the same as in that target's grid.
            % TARGETN = -1: colour overlay of all targets except T1, with
            % threshold THR (x noise SD) and smoothing SIG (px); 0 = off.
            % CMAX: colour limits [-CMAX CMAX] (e.g. from sharedCLim, to use
            % the same scale for every target). [] (default) = this target's
            % own max |value|. Ignored for the overlay.
            if nargin < 5, cond = 0; end
            if nargin < 6, thr = 0; end
            if nargin < 7, sig = 0; end
            if nargin < 8, cmax = []; end
            if targetn == -1
                t = TSeriesImageViewerv4.plotOverlay(parent, R, field, cond, thr, sig);
                return
            end
            delete(parent.Children);
            image_toplot = R.(field){R.targets == targetn};
            nCond = numel(R.numCond);
            if isempty(cmax)
                c = max(abs(image_toplot(:)), [], 'omitnan');
            else
                c = cmax;
            end
            cmap = TSeriesImageViewerv4.getRedBlue(256);
            if strcmp(field, 'subtraction'), label = 'subtraction'; else, label = 'dfbyf0'; end

            if cond > 0
                t = tiledlayout(parent, 1, 1, 'Padding', 'loose');
                ax = nexttile(t);
                imagesc(ax, image_toplot(:, :, cond));
                set(ax, 'XTickLabel', [], 'YTickLabel', []);
                colormap(ax, cmap);
                axis(ax, 'image');
                if ~(isempty(c) || c == 0 || isnan(c))
                    clim(ax, [-c, c]);
                end
                title(ax, {sprintf('%s - %s target %d', R.name, label, targetn), ...
                    TSeriesImageViewerv4.conditionLabel(R, cond)}, 'Interpreter', 'none');
                cb = colorbar(ax);
                cb.Layout.Tile = 'east';
                cb.FontSize = 18;
                return
            end

            numberOfRows = ceil(sqrt(nCond));
            numberOfCols = ceil(nCond / numberOfRows);
            t = tiledlayout(parent, numberOfRows, numberOfCols, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            for ii = 1:nCond
                ax = nexttile(t);
                imagesc(ax, image_toplot(:, :, ii));
                set(ax, 'XTickLabel', [], 'YTickLabel', []);
                colormap(ax, cmap);
                if isempty(c) || c == 0 || isnan(c)
                    continue
                end
                clim(ax, [-c, c]);
                axis(ax, 'square');
                if ii <= numel(R.theta)
                    title(ax, sprintf('%g', R.theta(ii)));
                end
            end
            title(t, sprintf('%s - %s target %d', R.name, label, targetn), 'Interpreter', 'none');
            cb = colorbar(ax);
            cb.Layout.Tile = 'east';
            cb.FontSize = 18;
        end

        function t = plotOverlay(parent, R, field, cond, thr, sig)
            % Colour overlay of every target except the control (T1): each
            % target's map in its own colour on black, added together
            % (overlaps mix colours).
            %   1. SIG > 0: Gaussian-smooth each condition image (sigma SIG px).
            %   2. Per target, the floor (black) is
            %        THR > 0: median + THR x robust SD of that target's map
            %                 (robust SD = 1.4826 x median absolute deviation,
            %                 over all its conditions), so each target is
            %                 judged against its own noise;
            %        THR = 0: 0 (show all positive values, as in v2).
            %   3. Brightness = value above the floor, on one shared scale:
            %      full brightness = 99.5th percentile of the above-floor
            %      values shown, so targets can be compared and single hot
            %      pixels don't dim the rest.
            if nargin < 5, thr = 0; end
            if nargin < 6, sig = 0; end
            delete(parent.Children);
            sel = find(R.targets ~= 1);
            if isempty(sel), sel = (1:numel(R.targets))'; end
            maps = R.(field)(sel);
            nCond = numel(R.numCond);
            if cond > 0, conds = cond; else, conds = 1:nCond; end
            cols = TSeriesImageViewerv4.overlayColors(numel(sel));

            % 1) smoothing, 2) per-target floor
            floorVal = zeros(numel(sel), 1);
            for j = 1:numel(sel)
                m = maps{j};
                m(~isfinite(m)) = 0;
                if sig > 0
                    for ci = 1:size(m, 3)
                        m(:, :, ci) = imgaussfilt(m(:, :, ci), sig);
                    end
                end
                maps{j} = m;
                if thr > 0
                    x = m(:);
                    med = median(x);
                    floorVal(j) = med + thr * 1.4826 * median(abs(x - med));
                end
            end

            % 3) shared brightness scale
            above = cellfun(@(m, f) reshape(m(:, :, conds) - f, [], 1), maps, num2cell(floorVal), ...
                'UniformOutput', false);
            above = vertcat(above{:});
            above = above(above > 0);
            if isempty(above), c = 1; else, c = prctile(above, 99.5); end

            if isscalar(conds)
                t = tiledlayout(parent, 1, 1, 'Padding', 'loose');
            else
                nr = ceil(sqrt(nCond));
                t = tiledlayout(parent, nr, ceil(nCond / nr), 'TileSpacing', 'compact', 'Padding', 'compact');
            end
            for ci = conds
                rgb = zeros([size(maps{1}, [1 2]) 3]);
                for j = 1:numel(sel)
                    a = min(max(maps{j}(:, :, ci) - floorVal(j), 0) / c, 1);
                    rgb = rgb + a .* reshape(cols(j, :), 1, 1, 3);
                end
                ax = nexttile(t);
                image(ax, min(rgb, 1));
                axis(ax, 'image');
                set(ax, 'XTick', [], 'YTick', []);
                if isscalar(conds)
                    title(ax, TSeriesImageViewerv4.conditionLabel(R, ci));
                elseif ci <= numel(R.theta)
                    title(ax, sprintf('%g', R.theta(ci)));
                else
                    title(ax, sprintf('Cond %d', ci));
                end
            end

            % Legend: one coloured square per target
            hold(ax, 'on');
            h = gobjects(numel(sel), 1);
            for j = 1:numel(sel)
                h(j) = plot(ax, NaN, NaN, 's', 'MarkerFaceColor', cols(j, :), ...
                    'MarkerEdgeColor', 'none', 'MarkerSize', 10);
            end
            hold(ax, 'off');
            lgd = legend(ax, h, compose('T%d', R.targets(sel)));
            lgd.Layout.Tile = 'east';

            if strcmp(field, 'subtraction'), label = 'subtraction'; else, label = 'dfbyf0'; end
            if thr > 0
                floorTxt = sprintf('threshold %g x noise SD', thr);
            else
                floorTxt = 'positive values';
            end
            if sig > 0
                smTxt = sprintf('smoothing %s = %g px', char(963), sig);
            else
                smTxt = 'no smoothing';
            end
            title(t, {sprintf('%s - %s overlay, all targets except T1', R.name, label), ...
                sprintf('%s; %s; full brightness = %.3g above threshold', floorTxt, smTxt, c)}, ...
                'Interpreter', 'none');
        end

        function c = sharedCLim(R, field)
            % Largest |value| over every target and condition of FIELD
            c = max(cellfun(@(m) max(abs(m(:)), [], 'omitnan'), R.(field)));
        end

        function cols = overlayColors(n)
            base = [1 0 0; 0 1 0; 0 0.45 1; 1 0 1; 1 1 0; 0 1 1; 1 0.5 0; 0.6 0.3 1];
            cols = base(mod(0:n-1, size(base, 1)) + 1, :);
        end

        function name = defaultFileName(R, field, targetn, cond, thr, sig, sameScale)
            if nargin < 4, cond = 0; end
            if nargin < 5, thr = 0; end
            if nargin < 6, sig = 0; end
            if nargin < 7, sameScale = false; end
            if targetn == -1
                name = sprintf('%s_T%s_%s_overlay', R.name, strrep(R.tseriesNum, '-', ''), field);
                num = @(v) strrep(sprintf('%g', v), '.', 'p');
                if thr > 0, name = [name '_thr' num(thr)]; end
                if sig > 0, name = [name '_sm' num(sig)]; end
            else
                name = sprintf('%s_T%s_%s_target%d', R.name, strrep(R.tseriesNum, '-', ''), field, targetn);
                if sameScale, name = [name '_samescale']; end
            end
            if cond > 0
                name = sprintf('%s_cond%d', name, cond);
                if cond <= numel(R.theta)
                    name = sprintf('%s_%sdeg', name, strrep(sprintf('%g', R.theta(cond)), '.', 'p'));
                end
            end
        end

        function s = conditionLabel(R, i)
            % e.g. 'Condition 3: 90°' (angle from stimulusData Var1Range)
            if i <= numel(R.theta)
                s = sprintf('Condition %d: %g%s', i, R.theta(i), char(176));
            else
                s = sprintf('Condition %d', i);
            end
        end

        function cmap = getRedBlue(m)
            % Uses your redblue.m if it is on the path, otherwise a built-in
            % blue-white-red map.
            if exist('redblue', 'file') == 2
                cmap = redblue(m);
                return
            end
            half = floor(m / 2);
            up   = linspace(0, 1, half)';
            down = flipud(up);
            cmap = [[up; ones(m - half, 1)], [up; down(1:m - half)], [ones(half, 1); down(1:m - half)]];
        end
    end

    % Component initialization
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1200 750];
            app.UIFigure.Name = 'TSeries Image Viewer';

            app.GridLayout = uigridlayout(app.UIFigure, [1 2]);
            app.GridLayout.ColumnWidth = {320, '1x'};

            % Left: controls
            app.ControlPanel = uipanel(app.GridLayout, 'Title', 'Controls');
            app.ControlPanel.Layout.Row = 1;
            app.ControlPanel.Layout.Column = 1;

            g = uigridlayout(app.ControlPanel, [23 2]);
            g.ColumnWidth = {'1x', 80};
            g.RowHeight = [repmat({22}, 1, 22), {'1x'}];
            g.RowHeight{22} = 12;   % spacer before status
            app.ControlGrid = g;

            app.DataFolderLabel = uilabel(g, 'Text', 'TSeries data folder', 'FontWeight', 'bold');
            place(app.DataFolderLabel, 1, [1 2]);
            app.DataFolderEditField = uieditfield(g, 'text');
            place(app.DataFolderEditField, 2, 1);
            app.BrowseDataButton = uibutton(g, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseDataButtonPushed, true));
            place(app.BrowseDataButton, 2, 2);

            app.AvgWinLabel = uilabel(g, 'Text', 'Frames to average (avg_win)');
            place(app.AvgWinLabel, 3, 1);
            app.AvgWinSpinner = uispinner(g, 'Limits', [0 1000], 'Value', 10, ...
                'RoundFractionalValues', 'on');
            place(app.AvgWinSpinner, 3, 2);

            app.ProcessButton = uibutton(g, 'Text', 'Load & Process', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', createCallbackFcn(app, @ProcessButtonPushed, true));
            place(app.ProcessButton, 4, [1 2]);

            app.ImageTypeLabel = uilabel(g, 'Text', 'Image type', 'FontWeight', 'bold');
            place(app.ImageTypeLabel, 6, [1 2]);
            app.ImageTypeDropDown = uidropdown(g, ...
                'Items', {'dF/F0', 'Subtraction (minus target 1)'}, ...
                'ItemsData', {'dfbyf0', 'subtraction'}, ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.ImageTypeDropDown, 7, [1 2]);

            app.TargetLabel = uilabel(g, 'Text', 'Target', 'FontWeight', 'bold');
            place(app.TargetLabel, 8, [1 2]);
            app.TargetDropDown = uidropdown(g, 'Items', {'(load data first)'}, 'ItemsData', {}, ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.TargetDropDown, 9, [1 2]);

            app.ConditionLabel = uilabel(g, 'Text', 'Condition', 'FontWeight', 'bold');
            place(app.ConditionLabel, 10, [1 2]);
            app.ConditionDropDown = uidropdown(g, 'Items', {'All conditions'}, 'ItemsData', {0}, ...
                'Tooltip', 'Show (and save) all conditions as a grid, or a single condition', ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.ConditionDropDown, 11, [1 2]);

            app.PopOutButton = uibutton(g, 'Text', 'Pop out image', 'Enable', 'off', ...
                'Tooltip', 'Open the current image in a separate, resizable figure window', ...
                'ButtonPushedFcn', createCallbackFcn(app, @PopOutButtonPushed, true));
            place(app.PopOutButton, 12, [1 2]);

            app.SameScaleCheckBox = uicheckbox(g, 'Text', 'Same colour scale for all targets', ...
                'Value', false, ...
                'Tooltip', 'Use one colour range (max |value| over all targets) so targets can be compared', ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.SameScaleCheckBox, 13, [1 2]);

            app.ThresholdLabel = uilabel(g, 'Text', 'Overlay threshold (x noise SD)');
            place(app.ThresholdLabel, 14, 1);
            app.ThresholdSpinner = uispinner(g, 'Limits', [0 20], 'Step', 0.5, 'Value', 3, ...
                'Enable', 'off', ...
                'Tooltip', 'Overlay only: hide pixels less than this many robust SDs above each target''s median. 0 = off', ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.ThresholdSpinner, 14, 2);
            app.SmoothLabel = uilabel(g, 'Text', ['Overlay smoothing ' char(963) ' (px)']);
            place(app.SmoothLabel, 15, 1);
            app.SmoothSpinner = uispinner(g, 'Limits', [0 10], 'Step', 0.5, 'Value', 1, ...
                'Enable', 'off', ...
                'Tooltip', 'Overlay only: Gaussian blur of each map before the threshold. 0 = off', ...
                'ValueChangedFcn', createCallbackFcn(app, @SelectionChanged, true));
            place(app.SmoothSpinner, 15, 2);

            app.OutFolderLabel = uilabel(g, 'Text', 'Save plots to folder', 'FontWeight', 'bold');
            place(app.OutFolderLabel, 16, [1 2]);
            app.OutFolderEditField = uieditfield(g, 'text');
            place(app.OutFolderEditField, 17, 1);
            app.BrowseOutButton = uibutton(g, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseOutButtonPushed, true));
            place(app.BrowseOutButton, 17, 2);

            app.FileNameLabel = uilabel(g, 'Text', 'File name / format');
            place(app.FileNameLabel, 18, [1 2]);
            app.FileNameEditField = uieditfield(g, 'text');
            place(app.FileNameEditField, 19, 1);
            app.FormatDropDown = uidropdown(g, 'Items', {'.png', '.tif', '.jpg', '.pdf', '.eps'});
            place(app.FormatDropDown, 19, 2);

            app.SaveButton = uibutton(g, 'Text', 'Save plot', 'Enable', 'off', ...
                'Tooltip', 'Save what is shown: the grid, or the single condition', ...
                'ButtonPushedFcn', createCallbackFcn(app, @SaveButtonPushed, true));
            place(app.SaveButton, 20, 1);
            app.SaveAllButton = uibutton(g, 'Text', 'Save all', 'Enable', 'off', ...
                'Tooltip', 'Save every target''s grid, for both image types', ...
                'ButtonPushedFcn', createCallbackFcn(app, @SaveAllButtonPushed, true));
            place(app.SaveAllButton, 20, 2);

            app.OpenFolderButton = uibutton(g, 'Text', 'Open save folder', ...
                'Tooltip', 'Open the output folder in File Explorer', ...
                'ButtonPushedFcn', createCallbackFcn(app, @OpenFolderButtonPushed, true));
            place(app.OpenFolderButton, 21, [1 2]);

            app.StatusLabel = uilabel(g, 'Text', 'Choose a TSeries folder to begin.', ...
                'WordWrap', 'on', 'VerticalAlignment', 'top');
            place(app.StatusLabel, 23, [1 2]);

            % Right: plot area
            app.PlotPanel = uipanel(app.GridLayout, 'BackgroundColor', 'w', 'BorderType', 'none');
            app.PlotPanel.Layout.Row = 1;
            app.PlotPanel.Layout.Column = 2;

            app.UIFigure.Visible = 'on';

            function place(c, row, col)
                c.Layout.Row = row;
                c.Layout.Column = col;
            end
        end
    end

    % App creation and deletion
    methods (Access = public)

        function app = TSeriesImageViewerv4
            createComponents(app)
            registerApp(app, app.UIFigure)
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure)
        end
    end
end
