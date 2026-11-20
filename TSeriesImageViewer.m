classdef TSeriesImageViewer < matlab.apps.AppBase
    % TSeriesImageViewer  GUI for the Pstim dF/F0 / subtraction image analysis.
    %
    %   1. Browse to a processed TSeries folder (contains stimulusData.mat,
    %      markpointData.mat and ResponsesChannel.tif).
    %   2. Click "Load & Process". The frame-averaged tiffs are cached in
    %      <folder>\-tiffs_<N>frameavg.mat, exactly as in the original script.
    %   3. Pick the image type and target to view.
    %   4. Pick an output folder and save the current plot, or all of them.
    %
    %   Run with:  app = TSeriesImageViewer;

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
            if strcmp(field, 'subtraction') && isempty(R.subtraction)
                setStatus(app, 'No target 1 (control) in this recording, so no subtraction image.', true);
                return
            end
            app.Tiles = TSeriesImageViewer.plotImages(app.PlotPanel, R, field, target);
            app.FileNameEditField.Value = TSeriesImageViewer.defaultFileName(R, field, target);
            app.SaveButton.Enable = 'on';
            app.SaveAllButton.Enable = 'on';
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
                app.Results = TSeriesImageViewer.processTSeries(p, ...
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
            app.TargetDropDown.Value     = R.targets(1);
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
            n = numel(fields) * numel(R.targets);
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Saving all plots', 'Cancelable', 'on');
            k = 0;
            try
                for f = 1:numel(fields)
                    for t = 1:numel(R.targets)
                        if dlg.CancelRequested, break, end
                        k = k + 1;
                        dlg.Value = k / n;
                        dlg.Message = sprintf('Saving %d of %d', k, n);
                        app.Tiles = TSeriesImageViewer.plotImages(app.PlotPanel, R, fields{f}, R.targets(t));
                        exportCurrent(app, TSeriesImageViewer.defaultFileName(R, fields{f}, R.targets(t)));
                    end
                end
                setStatus(app, sprintf('Saved %d plots to %s', k, app.OutFolderEditField.Value));
            catch err
                setStatus(app, ['Save failed: ' err.message], true);
            end
            close(dlg);
            app.ImageTypeDropDown.Value = origType;
            app.TargetDropDown.Value = origTarget;
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
            if ~isfile(cachePath)
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
                statusFcn('Saving frame-average cache...');
                save(cachePath, 'avg_Pstim_tiff', 'avg_blank_tiff')
            else
                statusFcn('Loading cached frame averages...');
                C = load(cachePath, 'avg_Pstim_tiff', 'avg_blank_tiff');
                avg_Pstim_tiff = C.avg_Pstim_tiff;
                avg_blank_tiff = C.avg_blank_tiff;
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

        function t = plotImages(parent, R, field, targetn)
            % Same layout as plot_images.m, but for one target, drawn into
            % PARENT (a panel or figure). Returns the tiledlayout.
            delete(parent.Children);
            image_toplot = R.(field){R.targets == targetn};
            nCond = numel(R.numCond);
            numberOfRows = ceil(sqrt(nCond));
            numberOfCols = ceil(nCond / numberOfRows);
            t = tiledlayout(parent, numberOfRows, numberOfCols, ...
                'TileSpacing', 'compact', 'Padding', 'compact');

            c = max(abs(image_toplot(:)), [], 'omitnan');
            cmap = TSeriesImageViewer.getRedBlue(256);
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
            if strcmp(field, 'subtraction'), label = 'subtraction'; else, label = 'dfbyf0'; end
            title(t, sprintf('%s - %s target %d', R.name, label, targetn), 'Interpreter', 'none');
            cb = colorbar(ax);
            cb.Layout.Tile = 'east';
        end

        function name = defaultFileName(R, field, targetn)
            name = sprintf('%s_T%s_%s_target%d', R.name, strrep(R.tseriesNum, '-', ''), field, targetn);
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

            g = uigridlayout(app.ControlPanel, [18 2]);
            g.ColumnWidth = {'1x', 80};
            g.RowHeight = [repmat({22}, 1, 17), {'1x'}];
            g.RowHeight{17} = 12;   % spacer before status
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

            app.OutFolderLabel = uilabel(g, 'Text', 'Save plots to folder', 'FontWeight', 'bold');
            place(app.OutFolderLabel, 11, [1 2]);
            app.OutFolderEditField = uieditfield(g, 'text');
            place(app.OutFolderEditField, 12, 1);
            app.BrowseOutButton = uibutton(g, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseOutButtonPushed, true));
            place(app.BrowseOutButton, 12, 2);

            app.FileNameLabel = uilabel(g, 'Text', 'File name / format');
            place(app.FileNameLabel, 13, [1 2]);
            app.FileNameEditField = uieditfield(g, 'text');
            place(app.FileNameEditField, 14, 1);
            app.FormatDropDown = uidropdown(g, 'Items', {'.png', '.tif', '.jpg', '.pdf', '.eps'});
            place(app.FormatDropDown, 14, 2);

            app.SaveButton = uibutton(g, 'Text', 'Save plot', 'Enable', 'off', ...
                'ButtonPushedFcn', createCallbackFcn(app, @SaveButtonPushed, true));
            place(app.SaveButton, 15, 1);
            app.SaveAllButton = uibutton(g, 'Text', 'Save all', 'Enable', 'off', ...
                'Tooltip', 'Save every target, for both image types', ...
                'ButtonPushedFcn', createCallbackFcn(app, @SaveAllButtonPushed, true));
            place(app.SaveAllButton, 15, 2);

            app.OpenFolderButton = uibutton(g, 'Text', 'Open save folder', ...
                'Tooltip', 'Open the output folder in File Explorer', ...
                'ButtonPushedFcn', createCallbackFcn(app, @OpenFolderButtonPushed, true));
            place(app.OpenFolderButton, 16, [1 2]);

            app.StatusLabel = uilabel(g, 'Text', 'Choose a TSeries folder to begin.', ...
                'WordWrap', 'on', 'VerticalAlignment', 'top');
            place(app.StatusLabel, 18, [1 2]);

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

        function app = TSeriesImageViewer
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
