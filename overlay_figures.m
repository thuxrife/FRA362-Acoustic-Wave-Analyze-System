function outFigPath = overlay_figures(figPaths, taskName, showPlot)
%% Acoustic Figure Overlay & Comparison Engine
% Ingests an array or comma-separated string of MATLAB .fig files.
% Automatically detects the figure type:
%   - 1D Line Curves (frequency.fig, amplitude.fig): Overlays curves onto a single high-contrast axes.
%   - 2D Heatmaps (spectrogram.fig): Generates synchronized multi-panel subplots with
%     Differential Attenuation Spectrogram (Delta dB = dB_A - dB_B) and linked zoom/pan.
%
% Usage:
%   overlay_figures('analyze/.../frequency.fig, analyze/.../frequency.fig', 'freq_compare');
%   overlay_figures('analyze/.../spectrogram.fig, analyze/.../spectrogram.fig', 'spectrogram_diff');
%   overlay_figures(); % Interactive prompt

    OUTPUT_ROOT = fullfile('analyze', 'overlay');

    %% 1. Interactive Input Dialog if Arguments Omitted
    if nargin < 1 || isempty(figPaths)
        prompt = {
            sprintf('Enter relative paths to .fig files (separated by comma ","):'), ...
            'Comparison / Task Name (saves to analyze/overlay/{taskName}):'
        };
        dlgtitle = 'Acoustic Figure Overlay Input';
        dims = [4, 95; 1, 95];
        defaultName = sprintf('overlay_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        definput = {
            'analyze/2026-11-06-sound-sample-test/sound_sample_01_sand-1-piece-front/spectrogram.fig, analyze/2026-11-06-sound-sample-test/sound_sample_01_sand-1-piece/spectrogram.fig', ...
            defaultName
        };
        opts.Resize = 'on';
        answer = inputdlg(prompt, dlgtitle, dims, definput, opts);

        if isempty(answer)
            fprintf('[Overlay] Cancelled by user.\n');
            outFigPath = '';
            return;
        end

        figPaths = answer{1};
        if ~isempty(strtrim(answer{2}))
            taskName = strtrim(answer{2});
        end
    end

    %% 2. Parse and Clean Comma-Separated Input
    if ischar(figPaths) || isstring(figPaths)
        if ischar(figPaths) && size(figPaths, 1) > 1
            % Flatten multi-line inputdlg char matrix into a single comma-delimited row
            figPaths = strjoin(cellstr(figPaths), ',');
        end
        rawStr = char(figPaths);
        rawCells = strsplit(rawStr, {',', ';'});
    elseif iscell(figPaths)
        rawCells = {};
        for k = 1:length(figPaths)
            parts = strsplit(char(figPaths{k}), ',');
            rawCells = [rawCells, parts]; %#ok<AGROW>
        end
    else
        error('Input paths must be a comma-separated string or a cell array of paths.');
    end

    cleanedPaths = {};
    for k = 1:length(rawCells)
        p = strtrim(rawCells{k});
        p = regexprep(p, '^[''"]+|[''"]+$', '');
        p = strtrim(p);
        p = strrep(p, '\', '/');
        if ~isempty(p)
            cleanedPaths{end+1} = p; %#ok<AGROW>
        end
    end
    figPaths = cleanedPaths;

    if isempty(figPaths)
        error('No valid .fig paths found in the input string.');
    end

    if nargin < 2 || isempty(taskName)
        taskName = sprintf('overlay_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    if nargin < 3 || isempty(showPlot)
        showPlot = true;
    end

    targetDir = fullfile(OUTPUT_ROOT, taskName);
    if ~exist(targetDir, 'dir')
        mkdir(targetDir);
    end
    outFigPath = fullfile(targetDir, [taskName, '.fig']);

    %% 3. Ingest Figures and Detect Data Types (Line vs Spectrogram Image)
    fprintf('\n=================================================================\n');
    fprintf('          Acoustic Trace Overlay & Comparison Engine             \n');
    fprintf('=================================================================\n');
    fprintf('Ingesting %d figure(s)...\n', length(figPaths));

    extractedData = struct('type', {}, 'label', {}, 'x', {}, 'y', {}, 'c', {}, 'xLabel', {}, 'yLabel', {});
    isSpectrogramMode = false;

    for i = 1:length(figPaths)
        fPath = figPaths{i};
        if ~exist(fPath, 'file')
            fprintf(2, '  [SKIP] File not found: %s\n', fPath);
            continue;
        end

        [fDir, fBase, ~] = fileparts(fPath);
        [subDir, sampleDir] = fileparts(fDir);
        [~, trialDir] = fileparts(subDir);
        if isempty(trialDir) || strcmpi(trialDir, 'analyze')
            traceLabel = sprintf('%s (%s)', sampleDir, fBase);
        else
            traceLabel = sprintf('%s - %s', sampleDir, fBase);
        end

        try
            srcFig = openfig(fPath, 'invisible');
            srcAxes = findobj(srcFig, 'Type', 'axes');
            if isempty(srcAxes)
                close(srcFig);
                continue;
            end
            primaryAxes = srcAxes(end);

            % Check for 2D Spectrogram Image first
            imgs = findobj(primaryAxes, 'Type', 'image');
            if ~isempty(imgs)
                isSpectrogramMode = true;
                bestImg = imgs(1);
                
                xData = bestImg.XData;
                yData = bestImg.YData;
                cData = bestImg.CData;

                % Expand 2-element bounds into vectors if necessary
                if length(xData) == 2 && size(cData, 2) > 2
                    xData = linspace(xData(1), xData(2), size(cData, 2));
                end
                if length(yData) == 2 && size(cData, 1) > 2
                    yData = linspace(yData(1), yData(2), size(cData, 1));
                end

                entry = struct();
                entry.type   = 'spectrogram';
                entry.label  = traceLabel;
                entry.x      = xData;
                entry.y      = yData;
                entry.c      = cData;
                entry.xLabel = char(string(primaryAxes.XLabel.String));
                entry.yLabel = char(string(primaryAxes.YLabel.String));
                extractedData(end+1) = entry; %#ok<AGROW>

                close(srcFig);
                fprintf('  [+] Ingested Spectrogram: %s [%dx%d]\n', traceLabel, size(cData, 1), size(cData, 2));
                continue;
            end

            % Check for 1D Line Plot (frequency.fig or amplitude.fig)
            lines = findobj(primaryAxes, 'Type', 'line');
            if ~isempty(lines)
                bestLine = lines(1);
                maxLen = length(bestLine.XData);
                for l = 2:length(lines)
                    if length(lines(l).XData) > maxLen
                        bestLine = lines(l);
                        maxLen = length(lines(l).XData);
                    end
                end

                entry = struct();
                entry.type   = 'line';
                entry.label  = traceLabel;
                entry.x      = bestLine.XData;
                entry.y      = bestLine.YData;
                entry.c      = [];
                entry.xLabel = char(string(primaryAxes.XLabel.String));
                entry.yLabel = char(string(primaryAxes.YLabel.String));
                extractedData(end+1) = entry; %#ok<AGROW>

                close(srcFig);
                fprintf('  [+] Ingested Line Trace:  %s (%d points)\n', traceLabel, length(entry.x));
                continue;
            end

            close(srcFig);
        catch ME
            fprintf(2, '  [ERROR] Ingestion failed for %s: %s\n', fPath, ME.message);
        end
    end

    if isempty(extractedData)
        error('No valid line traces or spectrogram images could be extracted from the specified files.');
    end

    %% 4A. Render 2D Spectrogram Comparison (Subplots + Differential Attenuation Map)
    if isSpectrogramMode
        numSpecs = length(extractedData);
        hasDiff = (numSpecs == 2);
        totalPanels = numSpecs + double(hasDiff);

        fig = figure('Name', sprintf('Acoustic Spectrogram Comparison - %s', taskName), ...
            'NumberTitle', 'off', ...
            'Color', [0.11, 0.12, 0.14], ...
            'Position', [100, 50, 1120, min(240 * totalPanels + 100, 880)], ...
            'Visible', 'off');

        sb = uicontrol('Parent', fig, 'Style', 'text', ...
            'String', ' [Spectrogram Tracker] Hover cursor over heatmaps to inspect time-frequency acoustic power', ...
            'Units', 'normalized', ...
            'Position', [0.08, 0.01, 0.88, 0.03], ...
            'BackgroundColor', [0.15, 0.16, 0.19], ...
            'ForegroundColor', [0.45, 0.85, 0.95], ...
            'FontSize', 9, 'HorizontalAlignment', 'left', ...
            'Tag', 'CoordinateStatusBar');

        axList = gobjects(1, totalPanels);
        f_cutoff = 0.586 * 346.0 / 0.10;

        for k = 1:numSpecs
            axList(k) = subplot(totalPanels, 1, k, 'Parent', fig);
            imagesc(axList(k), extractedData(k).x, extractedData(k).y, extractedData(k).c);
            axis(axList(k), 'xy');
            colormap(axList(k), jet);
            cb = colorbar(axList(k));
            ylabel(cb, 'PSD (dBFS)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 8);
            set(cb, 'Color', [0.85, 0.88, 0.92]);

            title(axList(k), sprintf('[Condition %d] %s', k, extractedData(k).label), ...
                'Color', [0.95, 0.96, 0.98], 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
            ylabel(axList(k), 'Freq (Hz)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
            ylim(axList(k), [0, 2200]);
            yline(axList(k), f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                'Color', [0.75, 0.78, 0.82], 'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left', ...
                'LabelColor', [0.85, 0.88, 0.92]);

            set(axList(k), 'Color', [0.07, 0.08, 0.09], 'XColor', [0.65, 0.68, 0.74], 'YColor', [0.65, 0.68, 0.74]);
        end

        % Compute Differential Attenuation Map if exactly 2 spectrograms
        if hasDiff
            axDiff = subplot(totalPanels, 1, 3, 'Parent', fig);
            axList(3) = axDiff;

            % Align grids for subtraction
            gridC1 = extractedData(1).c;
            gridC2 = extractedData(2).c;
            minR = min(size(gridC1, 1), size(gridC2, 1));
            minC = min(size(gridC1, 2), size(gridC2, 2));

            deltaDB = gridC1(1:minR, 1:minC) - gridC2(1:minR, 1:minC);
            tCommon = extractedData(1).x(1:minC);
            fCommon = extractedData(1).y(1:minR);

            imagesc(axDiff, tCommon, fCommon, deltaDB);
            axis(axDiff, 'xy');
            try
                colormap(axDiff, turbo);
            catch
                colormap(axDiff, jet);
            end
            cbDiff = colorbar(axDiff);
            ylabel(cbDiff, '\Delta Energy (dB)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 8);
            set(cbDiff, 'Color', [0.85, 0.88, 0.92]);
            maxDelta = max(abs(deltaDB(:)));
            caxis(axDiff, [-maxDelta, maxDelta]);

            title(axDiff, sprintf('Differential Spectrogram: \\Delta dB = [%s] - [%s]', ...
                extractedData(1).label, extractedData(2).label), ...
                'Color', [1.0, 0.85, 0.25], 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
            xlabel(axDiff, 'Time (seconds)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
            ylabel(axDiff, 'Freq (Hz)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
            ylim(axDiff, [0, 2200]);
            yline(axDiff, f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                'Color', [0.75, 0.78, 0.82], 'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left', ...
                'LabelColor', [0.85, 0.88, 0.92]);

            set(axDiff, 'Color', [0.07, 0.08, 0.09], 'XColor', [0.65, 0.68, 0.74], 'YColor', [0.65, 0.68, 0.74]);
        else
            xlabel(axList(end), 'Time (seconds)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
        end

        % Synchronize time & frequency zoom across all panels
        linkaxes(axList, 'xy');

        % Coordinate tracker mouse callback for heatmaps
        set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMoveSpec(src, evt, axList, sb));

    %% 4B. Render 1D Multi-Curve Line Overlay (frequency.fig / amplitude.fig)
    else
        colorPalette = [
            0.00, 0.82, 0.95;  % Electric Cyan
            0.95, 0.35, 0.25;  % Coral Red
            0.95, 0.80, 0.15;  % Gold Amber
            0.20, 0.85, 0.40;  % Emerald Green
            0.75, 0.40, 0.90;  % Bright Purple
            1.00, 0.55, 0.00;  % Vivid Orange
            0.40, 0.65, 1.00;  % Sky Blue
            0.90, 0.40, 0.60;  % Rose Pink
        ];
        numColors = size(colorPalette, 1);

        fig = figure('Name', sprintf('Acoustic Trace Comparison - %s', taskName), ...
            'NumberTitle', 'off', ...
            'Color', [0.11, 0.12, 0.14], ...
            'Position', [150, 100, 1050, 650], ...
            'Visible', 'off');

        ax = axes('Parent', fig, 'Units', 'normalized', ...
            'Position', [0.08, 0.12, 0.88, 0.80], ...
            'Color', [0.07, 0.08, 0.09], ...
            'XColor', [0.65, 0.68, 0.74], 'YColor', [0.65, 0.68, 0.74], ...
            'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
        grid(ax, 'on'); box(ax, 'on'); hold(ax, 'on');

        sb = uicontrol('Parent', fig, 'Style', 'text', ...
            'String', ' [Coordinate Tracker] Hover cursor over traces to inspect coordinates', ...
            'Units', 'normalized', ...
            'Position', [0.08, 0.02, 0.88, 0.04], ...
            'BackgroundColor', [0.15, 0.16, 0.19], ...
            'ForegroundColor', [0.45, 0.85, 0.95], ...
            'FontSize', 9, 'HorizontalAlignment', 'left', ...
            'Tag', 'CoordinateStatusBar');

        plotLines = [];
        legendLabels = {};
        isFreq = contains(lower(string(extractedData(1).xLabel)), 'freq') || ...
                 contains(lower(string(extractedData(1).label)), 'freq');

        for k = 1:length(extractedData)
            cIdx = mod(k - 1, numColors) + 1;
            c = colorPalette(cIdx, :);

            h = plot(ax, extractedData(k).x, extractedData(k).y, 'Color', c, 'LineWidth', 1.2, ...
                'DisplayName', extractedData(k).label);

            % Native datatips
            try
                if isFreq
                    h.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Frequency', 'XData', '%.1f Hz');
                    h.DataTipTemplate.DataTipRows(2) = dataTipTextRow('|Amplitude|', 'YData', '%.5f');
                else
                    h.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Time', 'XData', '%.4f s');
                    h.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Amplitude', 'YData', '%.5f');
                end
                h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow('Condition', repmat({extractedData(k).label}, 1, length(extractedData(k).x)));
            catch
            end

            plotLines(end+1) = h; %#ok<AGROW>
            legendLabels{end+1} = extractedData(k).label; %#ok<AGROW>
        end

        xlabel(ax, extractedData(1).xLabel, 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
        ylabel(ax, extractedData(1).yLabel, 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
        title(ax, sprintf('Acoustic Trace Comparison: %s', taskName), ...
            'Color', [0.95, 0.96, 0.98], 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');

        if isFreq
            f_cutoff = 0.586 * 346.0 / 0.10;
            xline(ax, f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                'Color', [0.65, 0.68, 0.74], 'LineWidth', 1.1, 'LabelVerticalAlignment', 'top', ...
                'LabelColor', [0.85, 0.88, 0.92]);
            xlim(ax, [0, 2200]);
        end

        lgd = legend(ax, plotLines, legendLabels, 'Location', 'northeast', ...
            'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], ...
            'EdgeColor', [0.28, 0.30, 0.35], 'Interpreter', 'none');
        set(lgd, 'FontSize', 9);

        set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMoveLine(src, evt, ax, sb, isFreq));
    end

    %% 5. Save Overlay Figure to analyze/overlay/
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Overlaid figure successfully written to:\n  %s\n', outFigPath);

    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Overlay.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);

    if showPlot
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end
end

%% Helper Callbacks for Live Coordinate Tracking
function onMouseMoveLine(~, ~, ax, sb, isFreq)
    cp = get(ax, 'CurrentPoint');
    x = cp(1, 1); y = cp(1, 2);
    xLim = xlim(ax); yLim = ylim(ax);

    if x >= xLim(1) && x <= xLim(2) && y >= yLim(1) && y <= yLim(2)
        if isFreq
            set(sb, 'String', sprintf('  [OVERLAY TRACKER] Freq: %6.1f Hz | |Amplitude|: %.5f', x, y));
        else
            set(sb, 'String', sprintf('  [OVERLAY TRACKER] Time: %7.4f s | Amplitude: %+.5f', x, y));
        end
    end
end

function onMouseMoveSpec(~, ~, axList, sb)
    for a = 1:length(axList)
        ax = axList(a);
        cp = get(ax, 'CurrentPoint');
        x = cp(1, 1); y = cp(1, 2);
        xLim = xlim(ax); yLim = ylim(ax);

        if x >= xLim(1) && x <= xLim(2) && y >= yLim(1) && y <= yLim(2)
            set(sb, 'String', sprintf('  [PANEL %d TRACKER] Time: %6.3f s | Frequency: %6.1f Hz', a, x, y));
            return;
        end
    end
end
