classdef WN_OptoETA_RF_App < matlab.apps.AppBase
    % WN_OptoETA_RF_App  GUI for WN_OptoETA_RF (opto ETAs + white-noise RFs).
    %
    %   1. Browse to a processed TSeries folder. The file check and the
    %      list of stimulated targets are filled in automatically.
    %   2. Adjust settings. In the Target -> ROI table, type an ROI number
    %      to override the automatic match (leave NaN for automatic).
    %   3. Click "Run analysis". The log, a results table and every saved
    %      figure appear on the right.
    %
    %   Run with:  app = WN_OptoETA_RF_App;

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        MainGrid                matlab.ui.container.GridLayout
        SettingsPanel           matlab.ui.container.Panel
        SettingsGrid            matlab.ui.container.GridLayout
        DataFolderEditField     matlab.ui.control.EditField
        BrowseDataButton        matlab.ui.control.Button
        OutRootEditField        matlab.ui.control.EditField
        BrowseOutButton         matlab.ui.control.Button
        FileCheckLabel          matlab.ui.control.Label
        WinStartField           matlab.ui.control.NumericEditField
        WinEndField             matlab.ui.control.NumericEditField
        ControlDropDown         matlab.ui.control.DropDown
        BaselineCheckBox        matlab.ui.control.CheckBox
        TargetROITable          matlab.ui.control.Table
        RFLagsField             matlab.ui.control.EditField
        ShufflesField           matlab.ui.control.NumericEditField
        ZThreshField            matlab.ui.control.NumericEditField
        RFCondListBox           matlab.ui.control.ListBox
        EpochStartField         matlab.ui.control.NumericEditField
        EpochEndField           matlab.ui.control.EditField
        PeakOffsetField         matlab.ui.control.NumericEditField
        F0WindowField           matlab.ui.control.NumericEditField
        F0PctField              matlab.ui.control.NumericEditField
        SaveFigsCheckBox        matlab.ui.control.CheckBox
        GridFigsCheckBox        matlab.ui.control.CheckBox
        RunButton               matlab.ui.control.Button
        OptoTrigButton          matlab.ui.control.Button
        MissedTrigButton        matlab.ui.control.Button
        TabGroup                matlab.ui.container.TabGroup
        LogTab                  matlab.ui.container.Tab
        LogTextArea             matlab.ui.control.TextArea
        ResultsTab              matlab.ui.container.Tab
        ResultsTable            matlab.ui.control.Table
        FiguresTab              matlab.ui.container.Tab
        FigureListBox           matlab.ui.control.ListBox
        FigureImage             matlab.ui.control.Image
        RoiTab                  matlab.ui.container.Tab
        RoiListBox              matlab.ui.control.ListBox
        RoiAxes                 matlab.ui.control.UIAxes
        ShowStimsCheckBox       matlab.ui.control.CheckBox
        RoiInfoLabel            matlab.ui.control.Label
        OpenFolderButton        matlab.ui.control.Button
        ToWorkspaceButton       matlab.ui.control.Button
        StatusLabel             matlab.ui.control.Label
    end

    properties (Access = private)
        Results = []        % struct R from the last run
        Targets = []        % targets found in markpointData
    end

    properties (Constant, Access = private)
        DefaultOutRoot = 'D:\Data\Claude Projects\WN analysis'
        RequiredFiles = {'ROI_Data.mat', 'relativeTime.mat', 'markpointData.mat', ...
            'markPointCharacteristics.mat', 'stimulusData.mat', 'TriggerSyncData.mat'}
    end

    methods (Access = private)

        function setStatus(app, msg, isError)
            if nargin < 3, isError = false; end
            app.StatusLabel.Text = msg;
            app.StatusLabel.FontColor = [0 0 0] + isError * [0.8 0 0];
            drawnow limitrate
        end

        function appendLog(app, txt)
            lines = splitlines(string(txt));
            app.LogTextArea.Value = [app.LogTextArea.Value; cellstr(lines)];
            scroll(app.LogTextArea, 'bottom');
        end

        function d = dataPath(app)
            d = regexprep(strtrim(app.DataFolderEditField.Value), '[\\/]+$', '');
        end

        function d = resultsDir(app)
            [~, ts] = fileparts(dataPath(app));
            d = fullfile(strtrim(app.OutRootEditField.Value), 'Results', ts);
        end

        function ok = checkFolder(app, loadTargets)
            % Report which required files exist; with loadTargets, also
            % (re)read the target list and reset the target controls.
            if nargin < 2, loadTargets = false; end
            p = dataPath(app);
            ok = false;
            if ~isfolder(p)
                app.FileCheckLabel.Text = 'Folder not found.';
                app.FileCheckLabel.FontColor = [0.8 0 0];
                return
            end
            have = cellfun(@(f) isfile(fullfile(p, f)), app.RequiredFiles);
            marks = strings(1, numel(have));
            marks(have) = char(10003) + " " + string(app.RequiredFiles(have));
            marks(~have) = char(10007) + " " + string(app.RequiredFiles(~have));
            app.FileCheckLabel.Text = strjoin(marks, '   ');
            app.FileCheckLabel.FontColor = [0 0.45 0] * all(have) + [0.8 0 0] * ~all(have);
            if ~all(have), return, end
            ok = true;
            if ~loadTargets, return, end

            S = load(fullfile(p, 'markpointData.mat'), 'markpointData');
            tg = [S.markpointData.Index];
            app.Targets = unique(tg(:));
            items = compose('T%d', app.Targets');
            app.ControlDropDown.Items = items;
            app.ControlDropDown.ItemsData = num2cell(app.Targets');
            if any(app.Targets == 1)
                app.ControlDropDown.Value = 1;
            end
            app.RFCondListBox.Items = items;
            app.RFCondListBox.ItemsData = num2cell(app.Targets');
            app.RFCondListBox.Value = {app.ControlDropDown.Value};
            n = arrayfun(@(x) nnz(tg == x), app.Targets);
            app.TargetROITable.Data = table(app.Targets, n, nan(size(app.Targets)), ...
                'VariableNames', {'Target', 'nStims', 'ROI'});
            app.TargetROITable.ColumnEditable = [false false true];
        end

        function args = collectOptions(app)
            lags = str2num(app.RFLagsField.Value); %#ok<ST2NM>
            if isempty(lags) || ~isnumeric(lags)
                error('RF lags must be a MATLAB vector, e.g. 0:0.2:2');
            end
            ep2 = str2double(app.EpochEndField.Value);
            if isnan(ep2), error('RF epoch end must be a number or Inf'); end
            T = app.TargetROITable.Data;
            man = ~isnan(T.ROI);
            cond = app.RFCondListBox.Value;
            if iscell(cond), cond = cell2mat(cond); end
            args = {'Window', [app.WinStartField.Value app.WinEndField.Value], ...
                'ControlTarget', app.ControlDropDown.Value, ...
                'BaselineSubtract', app.BaselineCheckBox.Value, ...
                'TargetROI', [T.Target(man), T.ROI(man)], ...
                'RFLags', lags(:)', ...
                'NShuffles', app.ShufflesField.Value, ...
                'RFzThresh', app.ZThreshField.Value, ...
                'RFCondTargets', cond(:)', ...
                'RFEpoch', [app.EpochStartField.Value ep2], ...
                'PeakFrameOffset', app.PeakOffsetField.Value, ...
                'F0Window', app.F0WindowField.Value, ...
                'F0Percentile', app.F0PctField.Value, ...
                'SaveFigures', app.SaveFigsCheckBox.Value, ...
                'GridFigures', app.GridFigsCheckBox.Value};
        end

        function showResults(app)
            R = app.Results;
            if isempty(R), return, end
            T = R.targetTable;
            post = R.tw >= 0;
            n = height(T);
            peakDFF = nan(n, 1);  peakDFFctrl = nan(n, 1);  dz = nan(n, 1);  p = nan(n, 1);
            for j = 1:n
                r = T.ROI(j);
                peakDFF(j)     = max(R.dffMean(r, post, j));
                peakDFFctrl(j) = max(R.dffMean(r, post, R.controlIdx));
                dz(j) = R.dAmp(r, j);
                p(j)  = R.pVsCtrl(r, j);
            end
            T.PeakDFF = round(peakDFF, 3);
            T.PeakDFF_ctrl = round(peakDFFctrl, 3);
            T.dZ_vs_ctrl = round(dz, 3);
            T.p_vs_ctrl = p;
            app.ResultsTable.Data = T;
        end

        function refreshFigures(app)
            d = resultsDir(app);
            f = dir(fullfile(d, '*.png'));
            if isempty(f)
                app.FigureListBox.Items = {'(no figures yet)'};
                app.FigureListBox.ItemsData = {''};
                app.FigureImage.ImageSource = '';
                return
            end
            [~, ts] = fileparts(dataPath(app));
            names = erase({f.name}, [ts '_']);
            app.FigureListBox.Items = names;
            app.FigureListBox.ItemsData = fullfile(d, {f.name});
            app.FigureListBox.Value = app.FigureListBox.ItemsData{1};
            app.FigureImage.ImageSource = app.FigureListBox.Value;
        end

        function ok = loadResultsFromDisk(app)
            % Load R from <results folder>\*_OptoETA_RF.mat if not already loaded.
            ok = ~isempty(app.Results);
            if ok, return, end
            f = dir(fullfile(resultsDir(app), '*_OptoETA_RF.mat'));
            if isempty(f), return, end
            setStatus(app, 'Loading saved results...');
            S = load(fullfile(f(1).folder, f(1).name), 'R');
            app.Results = S.R;
            % Restore manual target -> ROI overrides used for those results
            RT = S.R.targetTable;
            T = app.TargetROITable.Data;
            if ismember('Manual', RT.Properties.VariableNames) && ~isempty(T)
                for j = find(RT.Manual)'
                    T.ROI(T.Target == RT.Target(j)) = RT.ROI(j);
                end
                app.TargetROITable.Data = T;
            end
            showResults(app);
            populateRoiList(app);
            setStatus(app, sprintf('Loaded saved results from %s', f(1).name));
            ok = true;
        end

        function populateRoiList(app)
            R = app.Results;
            if isempty(R) || ~isfield(R, 'dFF')
                app.RoiListBox.Items = {'(run the analysis first)'};
                app.RoiListBox.ItemsData = {0};
                cla(app.RoiAxes, 'reset');
                return
            end
            n = size(R.Z, 1);
            items = compose('ROI %d', (1:n)');
            T = R.targetTable;
            for j = 1:height(T)
                items{T.ROI(j)} = sprintf('%s  - T%d target', items{T.ROI(j)}, T.Target(j));
            end
            app.RoiListBox.Items = items;
            app.RoiListBox.ItemsData = num2cell(1:n);
            app.RoiListBox.Value = T.ROI(1);
            plotRoi(app);
        end

        function plotRoi(app)
            R = app.Results;
            r = app.RoiListBox.Value;
            if isempty(R) || ~isfield(R, 'dFF') || isempty(r) || r == 0, return, end
            ax = app.RoiAxes;
            cla(ax, 'reset');
            red = [0.85 0.1 0.1];  blue = [0.1 0.3 0.85];
            yyaxis(ax, 'left');
            plot(ax, R.tImg, R.dFF(r, :), '-', 'Color', red, 'LineWidth', 0.6);
            ylabel(ax, [char(916) 'F/F_0']);
            ax.YAxis(1).Color = red;
            yyaxis(ax, 'right');
            plot(ax, R.tImg, R.Z(r, :), '-', 'Color', [blue 0.7], 'LineWidth', 0.6);
            ylabel(ax, 'z-score');
            ax.YAxis(2).Color = blue;
            xlim(ax, R.tImg([1 end]));
            xlabel(ax, 'Time (s)');

            T = R.targetTable;
            isT = find(T.ROI == r);
            ttl = sprintf('ROI %d', r);
            if ~isempty(isT)
                ttl = [ttl sprintf(' (target of T%d)', T.Target(isT))];
            end
            if app.ShowStimsCheckBox.Value
                hold(ax, 'on');
                yl = ylim(ax);
                cols = lines(numel(R.targets));
                h = gobjects(numel(R.targets), 1);
                for j = 1:numel(R.targets)
                    st = R.trig(R.trigTarget == R.targets(j));
                    h(j) = plot(ax, st, repmat(yl(2), size(st)), '|', 'Color', cols(j, :), ...
                        'MarkerSize', 8, 'LineWidth', 1);
                end
                ylim(ax, yl);
                legend(ax, h, compose('T%d stim', R.targets), 'Orientation', 'horizontal', ...
                    'Location', 'southoutside');
            end
            title(ax, ttl);

            % Per-target response summary for this ROI
            post = R.tw >= 0;
            parts = strings(1, numel(R.targets));
            for j = 1:numel(R.targets)
                parts(j) = sprintf('T%d: peak %sF/F0 %.3f', R.targets(j), char(916), max(R.dffMean(r, post, j)));
                if j ~= R.controlIdx
                    parts(j) = parts(j) + sprintf(' (%sz %+.2f, p=%.2g)', char(916), R.dAmp(r, j), R.pVsCtrl(r, j));
                end
            end
            app.RoiInfoLabel.Text = sprintf('ROI %d ETA (%.1f to %.1f s): %s', r, R.tw(1), R.tw(end), ...
                strjoin(parts, '   |   '));
        end

        function setBusy(app, busy)
            state = matlab.lang.OnOffSwitchState(~busy);
            app.RunButton.Enable = state;
            app.OptoTrigButton.Enable = state;
            app.MissedTrigButton.Enable = state;
        end
    end

    % Callbacks
    methods (Access = private)

        function BrowseDataButtonPushed(app, ~)
            start = dataPath(app);
            if ~isfolder(start), start = pwd; end
            d = uigetdir(start, 'Select processed TSeries folder');
            figure(app.UIFigure)
            if isequal(d, 0), return, end
            app.DataFolderEditField.Value = d;
            DataFolderChanged(app);
        end

        function DataFolderChanged(app, ~)
            app.Results = [];
            app.ResultsTable.Data = table();
            populateRoiList(app);
            if checkFolder(app, true)
                setStatus(app, sprintf('%d targets found. Adjust settings, then Run analysis.', numel(app.Targets)));
            else
                setStatus(app, 'Folder is missing required files.', true);
            end
            refreshFigures(app);
        end

        function BrowseOutButtonPushed(app, ~)
            start = app.OutRootEditField.Value;
            if ~isfolder(start), start = pwd; end
            d = uigetdir(start, 'Select output root (results go to <root>\Results\<TSeries>)');
            figure(app.UIFigure)
            if isequal(d, 0), return, end
            app.OutRootEditField.Value = d;
            refreshFigures(app);
        end

        function RunButtonPushed(app, ~)
            if isempty(app.Targets)
                checkFolder(app, true);       % folder typed but not yet loaded
            end
            if ~checkFolder(app)
                uialert(app.UIFigure, 'Choose a TSeries folder that has all the required files.', 'Missing files');
                return
            end
            try
                args = collectOptions(app); %#ok<NASGU>
            catch err
                uialert(app.UIFigure, err.message, 'Invalid setting');
                return
            end
            dp = dataPath(app); %#ok<NASGU>
            outRoot = strtrim(app.OutRootEditField.Value); %#ok<NASGU>
            setBusy(app, true);
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Running analysis', 'Indeterminate', 'on', ...
                'Message', 'Loading data, computing ETAs and RFs, saving figures (about 1-2 min)...');
            app.TabGroup.SelectedTab = app.LogTab;
            appendLog(app, sprintf('\n===== %s =====', char(datetime('now'))));
            setStatus(app, 'Running...');
            R = [];
            try
                txt = evalc('R = WN_OptoETA_RF(dp, outRoot, args{:});');
                appendLog(app, txt);
                app.Results = R;
                showResults(app);
                populateRoiList(app);
                refreshFigures(app);
                app.TabGroup.SelectedTab = app.ResultsTab;
                setStatus(app, sprintf('Done. Results in %s', resultsDir(app)));
            catch err
                appendLog(app, getReport(err, 'extended', 'hyperlinks', 'off'));
                setStatus(app, ['Error: ' err.message], true);
            end
            close(dlg);
            setBusy(app, false);
        end

        function OptoTrigButtonPushed(app, ~)
            runSide(app, 'plot_OptoTriggers', 'Plotting opto triggers...');
        end

        function MissedTrigButtonPushed(app, ~)
            runSide(app, 'plot_MissedFrameTriggers', 'Checking noise-frame triggers...');
        end

        function runSide(app, fname, msg)
            if ~checkFolder(app)
                uialert(app.UIFigure, 'Choose a TSeries folder that has all the required files.', 'Missing files');
                return
            end
            dp = dataPath(app); %#ok<NASGU>
            outRoot = strtrim(app.OutRootEditField.Value); %#ok<NASGU>
            setBusy(app, true);
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Working', 'Indeterminate', 'on', 'Message', msg);
            appendLog(app, sprintf('\n===== %s: %s =====', char(datetime('now')), fname));
            try
                txt = evalc([fname '(dp, outRoot);']);
                appendLog(app, txt);
                refreshFigures(app);
                pngs = app.FigureListBox.ItemsData;
                hit = find(contains(pngs, erase(fname, 'plot_')), 1);
                if ~isempty(hit)
                    app.FigureListBox.Value = pngs{hit};
                    app.FigureImage.ImageSource = pngs{hit};
                end
                app.TabGroup.SelectedTab = app.FiguresTab;
                setStatus(app, 'Done.');
            catch err
                appendLog(app, getReport(err, 'extended', 'hyperlinks', 'off'));
                setStatus(app, ['Error: ' err.message], true);
            end
            close(dlg);
            setBusy(app, false);
        end

        function FigureSelected(app, ~)
            if ~isempty(app.FigureListBox.Value)
                app.FigureImage.ImageSource = app.FigureListBox.Value;
            end
        end

        function OpenFolderButtonPushed(app, ~)
            d = resultsDir(app);
            if ~isfolder(d), d = strtrim(app.OutRootEditField.Value); end
            if ~isfolder(d)
                uialert(app.UIFigure, 'No results folder yet.', 'Not found');
                return
            end
            if ispc, winopen(d); elseif ismac, system(sprintf('open "%s"', d)); else, system(sprintf('xdg-open "%s" &', d)); end
        end

        function RoiSelected(app, ~)
            plotRoi(app);
        end

        function TabChanged(app, ~)
            if app.TabGroup.SelectedTab == app.RoiTab && isempty(app.Results) && isfolder(dataPath(app))
                if loadResultsFromDisk(app)
                    refreshFigures(app);
                end
            end
        end

        function ToWorkspaceButtonPushed(app, ~)
            if ~loadResultsFromDisk(app)
                uialert(app.UIFigure, 'Run the analysis first.', 'No results');
                return
            end
            assignin('base', 'R', app.Results);
            setStatus(app, 'Results copied to the base workspace as R.');
        end
    end

    % Component initialization
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off', 'Position', [60 60 1400 860], ...
                'Name', 'WN Opto ETA + RF analysis');
            app.MainGrid = uigridlayout(app.UIFigure, [2 2], ...
                'ColumnWidth', {440, '1x'}, 'RowHeight', {'1x', 22});

            % ---------------- settings (left) ----------------
            app.SettingsPanel = uipanel(app.MainGrid, 'Title', 'Settings', 'Scrollable', 'on');
            app.SettingsPanel.Layout.Row = 1;  app.SettingsPanel.Layout.Column = 1;
            nRows = 27;
            g = uigridlayout(app.SettingsPanel, [nRows 3], 'ColumnWidth', {150, '1x', 70}, ...
                'RowSpacing', 4, 'Padding', [8 8 8 8]);
            g.RowHeight = repmat({22}, 1, nRows);
            app.SettingsGrid = g;
            r = 0;

            r = r + 1;  hdr(g, r, 'Data');
            r = r + 1;  lbl(g, r, 'TSeries folder');
            app.DataFolderEditField = uieditfield(g, 'text', ...
                'ValueChangedFcn', createCallbackFcn(app, @DataFolderChanged, true));
            put(app.DataFolderEditField, r, 2);
            app.BrowseDataButton = uibutton(g, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseDataButtonPushed, true));
            put(app.BrowseDataButton, r, 3);
            r = r + 1;  lbl(g, r, 'Output root');
            app.OutRootEditField = uieditfield(g, 'text', 'Value', app.DefaultOutRoot);
            put(app.OutRootEditField, r, 2);
            app.BrowseOutButton = uibutton(g, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseOutButtonPushed, true));
            put(app.BrowseOutButton, r, 3);
            r = r + 1;  g.RowHeight{r} = 48;
            app.FileCheckLabel = uilabel(g, 'Text', 'Choose a folder.', 'WordWrap', 'on', ...
                'FontSize', 10, 'VerticalAlignment', 'top');
            put(app.FileCheckLabel, r, [1 3]);

            r = r + 1;  hdr(g, r, 'Event-triggered average');
            r = r + 1;  lbl(g, r, 'Window start / end (s)');
            wg = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            put(wg, r, [2 3]);
            app.WinStartField = uieditfield(wg, 'numeric', 'Value', -0.5);
            app.WinEndField   = uieditfield(wg, 'numeric', 'Value', 1.5);
            r = r + 1;  lbl(g, r, 'Control target');
            app.ControlDropDown = uidropdown(g, 'Items', {'(choose folder)'}, 'ItemsData', {1});
            put(app.ControlDropDown, r, [2 3]);
            r = r + 1;
            app.BaselineCheckBox = uicheckbox(g, 'Text', 'Subtract each trial''s pre-stim mean', 'Value', false);
            put(app.BaselineCheckBox, r, [1 3]);
            r = r + 1;  lbl(g, r, 'Target -> ROI (type ROI to override; NaN = auto)', [1 3]);
            r = r + 1;  g.RowHeight{r} = 120;
            app.TargetROITable = uitable(g, 'Data', table(), 'RowName', {});
            put(app.TargetROITable, r, [1 3]);

            r = r + 1;  hdr(g, r, 'Receptive field (white noise)');
            r = r + 1;  lbl(g, r, 'Lags (s)');
            app.RFLagsField = uieditfield(g, 'text', 'Value', '0:0.2:2');
            put(app.RFLagsField, r, [2 3]);
            r = r + 1;  lbl(g, r, 'Shuffles / z threshold');
            sg = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            put(sg, r, [2 3]);
            app.ShufflesField = uieditfield(sg, 'numeric', 'Value', 50, 'Limits', [1 Inf], ...
                'RoundFractionalValues', 'on');
            app.ZThreshField  = uieditfield(sg, 'numeric', 'Value', 5, 'Limits', [0 Inf]);
            r = r + 1;  g.RowHeight{r} = 70;  lbl(g, r, 'RFs during stims of');
            app.RFCondListBox = uilistbox(g, 'Items', {}, 'Multiselect', 'on', ...
                'Tooltip', 'Ctrl/Shift-click to select several targets');
            put(app.RFCondListBox, r, [2 3]);
            r = r + 1;  lbl(g, r, 'Epoch after stim (s)');
            eg = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            put(eg, r, [2 3]);
            app.EpochStartField = uieditfield(eg, 'numeric', 'Value', 0);
            app.EpochEndField   = uieditfield(eg, 'text', 'Value', 'Inf', ...
                'Tooltip', 'Inf = until the next stim');
            r = r + 1;  lbl(g, r, 'Noise frame vs peak (s)');
            app.PeakOffsetField = uieditfield(g, 'numeric', 'Value', -0.25, ...
                'Tooltip', 'Average the noise frame shown this many s from each target''s peak response');
            put(app.PeakOffsetField, r, [2 3]);

            r = r + 1;  hdr(g, r, 'Whole-trace dF/F0');
            r = r + 1;  lbl(g, r, 'F0 window (s) / percentile');
            fg = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            put(fg, r, [2 3]);
            app.F0WindowField = uieditfield(fg, 'numeric', 'Value', 60, 'Limits', [1 Inf]);
            app.F0PctField    = uieditfield(fg, 'numeric', 'Value', 10, 'Limits', [0 100]);

            r = r + 1;  hdr(g, r, 'Output');
            r = r + 1;
            app.SaveFigsCheckBox = uicheckbox(g, 'Text', 'Save figures', 'Value', true);
            put(app.SaveFigsCheckBox, r, [1 2]);
            r = r + 1;
            app.GridFigsCheckBox = uicheckbox(g, 'Text', 'All-ROI dF/F0 grid figures (slower)', 'Value', true);
            put(app.GridFigsCheckBox, r, [1 3]);
            r = r + 1;  g.RowHeight{r} = 36;
            app.RunButton = uibutton(g, 'Text', 'Run analysis', 'FontWeight', 'bold', 'FontSize', 14, ...
                'BackgroundColor', [0.85 0.93 1], ...
                'ButtonPushedFcn', createCallbackFcn(app, @RunButtonPushed, true));
            put(app.RunButton, r, [1 3]);
            r = r + 1;  g.RowHeight{r} = 28;
            bg = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            put(bg, r, [1 3]);
            app.OptoTrigButton = uibutton(bg, 'Text', 'Plot opto triggers', ...
                'ButtonPushedFcn', createCallbackFcn(app, @OptoTrigButtonPushed, true));
            app.MissedTrigButton = uibutton(bg, 'Text', 'Check frame triggers', ...
                'ButtonPushedFcn', createCallbackFcn(app, @MissedTrigButtonPushed, true));
            g.RowHeight = g.RowHeight(1:r);

            % ---------------- results (right) ----------------
            rg = uigridlayout(app.MainGrid, [2 1], 'RowHeight', {'1x', 30}, 'Padding', [0 0 0 0]);
            rg.Layout.Row = 1;  rg.Layout.Column = 2;
            app.TabGroup = uitabgroup(rg);
            app.LogTab = uitab(app.TabGroup, 'Title', 'Log');
            lg = uigridlayout(app.LogTab, [1 1]);
            app.LogTextArea = uitextarea(lg, 'Editable', 'off', 'FontName', 'Consolas', 'Value', {''});
            app.ResultsTab = uitab(app.TabGroup, 'Title', 'Targets');
            tg = uigridlayout(app.ResultsTab, [1 1]);
            app.ResultsTable = uitable(tg, 'Data', table(), 'RowName', {});
            app.FiguresTab = uitab(app.TabGroup, 'Title', 'Figures');
            fg2 = uigridlayout(app.FiguresTab, [1 2], 'ColumnWidth', {260, '1x'});
            app.FigureListBox = uilistbox(fg2, 'Items', {'(no figures yet)'}, 'ItemsData', {''}, ...
                'ValueChangedFcn', createCallbackFcn(app, @FigureSelected, true));
            app.FigureImage = uiimage(fg2, 'ScaleMethod', 'fit');

            app.RoiTab = uitab(app.TabGroup, 'Title', 'ROI traces');
            rg2 = uigridlayout(app.RoiTab, [3 2], 'ColumnWidth', {180, '1x'}, ...
                'RowHeight', {22, '1x', 40});
            app.ShowStimsCheckBox = uicheckbox(rg2, 'Text', 'Show stim times', 'Value', true, ...
                'ValueChangedFcn', createCallbackFcn(app, @RoiSelected, true));
            app.ShowStimsCheckBox.Layout.Row = 1;  app.ShowStimsCheckBox.Layout.Column = 1;
            app.RoiListBox = uilistbox(rg2, 'Items', {'(run the analysis first)'}, 'ItemsData', {0}, ...
                'ValueChangedFcn', createCallbackFcn(app, @RoiSelected, true));
            app.RoiListBox.Layout.Row = [2 3];  app.RoiListBox.Layout.Column = 1;
            app.RoiAxes = uiaxes(rg2);
            app.RoiAxes.Layout.Row = [1 2];  app.RoiAxes.Layout.Column = 2;
            app.RoiInfoLabel = uilabel(rg2, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
                'VerticalAlignment', 'top');
            app.RoiInfoLabel.Layout.Row = 3;  app.RoiInfoLabel.Layout.Column = 2;
            app.TabGroup.SelectionChangedFcn = createCallbackFcn(app, @TabChanged, true);

            bg2 = uigridlayout(rg, [1 3], 'ColumnWidth', {160, 200, '1x'}, 'Padding', [0 0 0 0]);
            app.OpenFolderButton = uibutton(bg2, 'Text', 'Open results folder', ...
                'ButtonPushedFcn', createCallbackFcn(app, @OpenFolderButtonPushed, true));
            app.ToWorkspaceButton = uibutton(bg2, 'Text', 'Send results to workspace (R)', ...
                'ButtonPushedFcn', createCallbackFcn(app, @ToWorkspaceButtonPushed, true));

            app.StatusLabel = uilabel(app.MainGrid, 'Text', 'Choose a TSeries folder to begin.');
            app.StatusLabel.Layout.Row = 2;  app.StatusLabel.Layout.Column = [1 2];

            app.UIFigure.Visible = 'on';

            function put(c, row, col)
                c.Layout.Row = row;  c.Layout.Column = col;
            end
            function lbl(parent, row, txt, col)
                if nargin < 4, col = 1; end
                put(uilabel(parent, 'Text', txt), row, col);
            end
            function hdr(parent, row, txt)
                put(uilabel(parent, 'Text', txt, 'FontWeight', 'bold', 'FontColor', [0.1 0.3 0.6]), row, [1 3]);
            end
        end
    end

    % App creation and deletion
    methods (Access = public)

        function app = WN_OptoETA_RF_App
            addpath(fileparts(mfilename('fullpath')));   % analysis functions live next to the app
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
