classdef WN_dFF_Viewer < matlab.apps.AppBase
    % WN_dFF_Viewer  Browse whole-recording dF/F0 traces of every ROI.
    %
    %   1. Browse to a processed TSeries folder; it loads automatically
    %      (WN_dFF computes dF/F0 and saves it to the results folder).
    %   2. Click an ROI (or use the arrow keys) to plot its trace.
    %   3. "Save figure" writes the current ROI's plot as a PNG.
    %
    %   Run with:  app = WN_dFF_Viewer;

    properties (Access = public)
        UIFigure            matlab.ui.Figure
        FolderEditField     matlab.ui.control.EditField
        BrowseButton        matlab.ui.control.Button
        ReloadButton        matlab.ui.control.Button
        F0WindowField       matlab.ui.control.NumericEditField
        F0PctField          matlab.ui.control.NumericEditField
        ShowStimsCheckBox   matlab.ui.control.CheckBox
        RoiListBox          matlab.ui.control.ListBox
        SaveFigButton       matlab.ui.control.Button
        OpenFolderButton    matlab.ui.control.Button
        Axes                matlab.ui.control.UIAxes
        StatusLabel         matlab.ui.control.Label
    end

    properties (Access = private)
        D = []          % output of WN_dFF
    end

    properties (Constant, Access = private)
        OutRoot = 'D:\Data\Claude Projects\WN analysis'
    end

    methods (Access = private)

        function setStatus(app, msg, isError)
            if nargin < 3, isError = false; end
            app.StatusLabel.Text = msg;
            app.StatusLabel.FontColor = [0.8 0 0] * isError;
            drawnow limitrate
        end

        function d = resultsDir(app)
            d = fullfile(app.OutRoot, 'Results', app.D.tsName);
        end

        function loadData(app)
            p = strtrim(app.FolderEditField.Value);
            if ~isfolder(p)
                setStatus(app, 'Folder not found.', true);
                return
            end
            dlg = uiprogressdlg(app.UIFigure, 'Title', 'Loading', 'Indeterminate', 'on', ...
                'Message', 'Loading ROI_Data and computing dF/F0...');
            try
                app.D = WN_dFF(p, 'F0Window', app.F0WindowField.Value, ...
                    'F0Percentile', app.F0PctField.Value, 'OutRoot', app.OutRoot);
            catch err
                close(dlg);
                app.D = [];
                app.RoiListBox.Items = {};
                cla(app.Axes, 'reset');
                setStatus(app, ['Error: ' err.message], true);
                return
            end
            close(dlg);
            n = size(app.D.dFF, 1);
            prev = app.RoiListBox.Value;
            app.RoiListBox.Items = compose('ROI %d', (1:n)');
            app.RoiListBox.ItemsData = num2cell(1:n);
            if isnumeric(prev) && isscalar(prev) && prev >= 1 && prev <= n
                app.RoiListBox.Value = prev;
            else
                app.RoiListBox.Value = 1;
            end
            plotCurrent(app);
            setStatus(app, sprintf('%s: %d ROIs, %d opto stims. F0 = %gth percentile, %g s window.', ...
                app.D.tsName, n, numel(app.D.trig), app.F0PctField.Value, app.F0WindowField.Value));
        end

        function plotCurrent(app)
            if isempty(app.D) || isempty(app.RoiListBox.Value), return, end
            plot_ROI_trace(app.D, app.RoiListBox.Value, 'Parent', app.Axes, ...
                'ShowStims', app.ShowStimsCheckBox.Value);
        end
    end

    % Callbacks
    methods (Access = private)

        function BrowseButtonPushed(app, ~)
            start = strtrim(app.FolderEditField.Value);
            if ~isfolder(start), start = pwd; end
            d = uigetdir(start, 'Select processed TSeries folder');
            figure(app.UIFigure)
            if isequal(d, 0), return, end
            app.FolderEditField.Value = d;
            loadData(app);
        end

        function ReloadButtonPushed(app, ~)
            loadData(app);
        end

        function RoiChanged(app, ~)
            plotCurrent(app);
        end

        function SaveFigButtonPushed(app, ~)
            if isempty(app.D), return, end
            r = app.RoiListBox.Value;
            outDir = resultsDir(app);
            if ~isfolder(outDir), mkdir(outDir); end
            file = fullfile(outDir, sprintf('%s_ROI%03d_dFF.png', app.D.tsName, r));
            f = figure('Visible', 'off', 'Position', [50 50 1600 450]);
            ax = axes(f);
            plot_ROI_trace(app.D, r, 'Parent', ax, 'ShowStims', app.ShowStimsCheckBox.Value);
            try
                exportgraphics(f, file, 'Resolution', 150);
                setStatus(app, ['Saved ' file]);
            catch err
                setStatus(app, ['Could not save (is the file open?): ' err.message], true);
            end
            close(f);
        end

        function OpenFolderButtonPushed(app, ~)
            if isempty(app.D), return, end
            d = resultsDir(app);
            if ~isfolder(d), mkdir(d); end
            if ispc, winopen(d); elseif ismac, system(sprintf('open "%s"', d)); else, system(sprintf('xdg-open "%s" &', d)); end
        end
    end

    % Component initialization
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off', 'Position', [60 60 1400 700], ...
                'Name', 'WN dF/F0 viewer');
            main = uigridlayout(app.UIFigure, [2 2], 'ColumnWidth', {260, '1x'}, 'RowHeight', {'1x', 22});

            left = uigridlayout(main, [10 2], 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
                'ColumnWidth', {'1x', '1x'}, ...
                'RowHeight', {22, 22, 26, 22, 22, 22, 22, '1x', 26, 26});
            left.Layout.Row = 1;  left.Layout.Column = 1;

            put(uilabel(left, 'Text', 'TSeries folder', 'FontWeight', 'bold'), 1, [1 2]);
            app.FolderEditField = uieditfield(left, 'text');
            put(app.FolderEditField, 2, [1 2]);
            app.BrowseButton = uibutton(left, 'Text', 'Browse...', ...
                'ButtonPushedFcn', createCallbackFcn(app, @BrowseButtonPushed, true));
            put(app.BrowseButton, 3, 1);
            app.ReloadButton = uibutton(left, 'Text', 'Load / Reload', ...
                'Tooltip', 'Load the folder typed above, or recompute after changing F0 settings', ...
                'ButtonPushedFcn', createCallbackFcn(app, @ReloadButtonPushed, true));
            put(app.ReloadButton, 3, 2);

            put(uilabel(left, 'Text', 'F0 window (s)'), 4, 1);
            app.F0WindowField = uieditfield(left, 'numeric', 'Value', 60, 'Limits', [1 Inf]);
            put(app.F0WindowField, 4, 2);
            put(uilabel(left, 'Text', 'F0 percentile'), 5, 1);
            app.F0PctField = uieditfield(left, 'numeric', 'Value', 10, 'Limits', [0 100]);
            put(app.F0PctField, 5, 2);

            app.ShowStimsCheckBox = uicheckbox(left, 'Text', 'Show opto stims', 'Value', true, ...
                'ValueChangedFcn', createCallbackFcn(app, @RoiChanged, true));
            put(app.ShowStimsCheckBox, 6, [1 2]);

            put(uilabel(left, 'Text', 'ROIs', 'FontWeight', 'bold'), 7, [1 2]);
            app.RoiListBox = uilistbox(left, 'Items', {}, ...
                'ValueChangedFcn', createCallbackFcn(app, @RoiChanged, true));
            put(app.RoiListBox, 8, [1 2]);

            app.SaveFigButton = uibutton(left, 'Text', 'Save figure', ...
                'ButtonPushedFcn', createCallbackFcn(app, @SaveFigButtonPushed, true));
            put(app.SaveFigButton, 9, [1 2]);
            app.OpenFolderButton = uibutton(left, 'Text', 'Open results folder', ...
                'ButtonPushedFcn', createCallbackFcn(app, @OpenFolderButtonPushed, true));
            put(app.OpenFolderButton, 10, [1 2]);

            app.Axes = uiaxes(main);
            put(app.Axes, 1, 2);

            app.StatusLabel = uilabel(main, 'Text', 'Choose a TSeries folder to begin.');
            put(app.StatusLabel, 2, [1 2]);

            app.UIFigure.Visible = 'on';

            function put(c, row, col)
                c.Layout.Row = row;  c.Layout.Column = col;
            end
        end
    end

    methods (Access = public)

        function app = WN_dFF_Viewer
            addpath(fileparts(mfilename('fullpath')));
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
