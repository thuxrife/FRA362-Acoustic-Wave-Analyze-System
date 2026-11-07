function outFigPath = diff_figures(figPaths, taskName, showPlot)
%% Acoustic Baseline Subtraction & Difference Engine (Test - Baseline)
% Ingests an array or comma-separated string of MATLAB .fig files (minimum 2).
% The 1st file is treated as the Reference Baseline; all subsequent files (2..N)
% are subtracted against the 1st file (Delta = Test - Baseline).
%
% Automatically detects the figure type:
%   - Frequency Response (frequency.fig):
%       * Top Panel:    Delta Peak Amplitude = Amp_Test - Amp_Baseline
%       * Bottom Panel: Delta Energy (dB)    = dB_Test  - dB_Baseline (Bar Chart)
%   - Time Waveform (amplitude.fig):
%       * Plots residual waveform Delta s(t) = s_Test(t) - s_Baseline(t)
%   - 2D Spectrogram (spectrogram.fig):
%       * Plots Differential Attenuation Heatmap Delta dB(t,f) = dB_Test - dB_Baseline
%
% Saves interactive .fig output to: analyze/different/{taskName}/{taskName}.fig
%
% Usage:
%   diff_figures('analyze/.../base/frequency.fig, analyze/.../mid/frequency.fig, analyze/.../back/frequency.fig', 'sand_diff');
%   diff_figures(); % Opens interactive GUI prompt

    OUTPUT_ROOT = fullfile('analyze', 'different');

    %% 1. Interactive Input Dialog if Arguments Omitted
    if nargin < 1 || isempty(figPaths)
        prompt = {
            sprintf('Enter relative .fig paths separated by comma ","\n(1st file = Baseline, 2nd..N = Test samples to subtract):'), ...
            'Difference Task Name (saves to analyze/different/{taskName}):'
        };
        dlgtitle = 'Acoustic Baseline Subtraction (Test - Baseline)';
        dims = [4, 95; 1, 95];
        defaultName = sprintf('diff_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        definput = {
            'analyze/2026-11-07-sound-sample/sound_sample_0_base_line/frequency.fig, analyze/2026-11-07-sound-sample/sound_sample_1_sand_middle/frequency.fig, analyze/2026-11-07-sound-sample/sound_sample_1_sand_back/frequency.fig', ...
            defaultName
        };
        opts.Resize = 'on';
        answer = inputdlg(prompt, dlgtitle, dims, definput, opts);

        if isempty(answer)
            fprintf('[Difference] Cancelled by user.\n');
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

    if length(figPaths) < 2
        error('At least 2 .fig paths are required: [1] Baseline file, [2..N] Test file(s) to subtract.');
    end

    if nargin < 2 || isempty(taskName)
        taskName = sprintf('diff_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    if nargin < 3 || isempty(showPlot)
        showPlot = true;
    end

    targetDir = fullfile(OUTPUT_ROOT, taskName);
    if ~exist(targetDir, 'dir')
        mkdir(targetDir);
    end
    outFigPath = fullfile(targetDir, [taskName, '.fig']);

    %% 3. Ingest Figures and Companion CSVs
    fprintf('\n=================================================================\n');
    fprintf('       Acoustic Baseline Subtraction Engine (Test - Baseline)    \n');
    fprintf('=================================================================\n');
    fprintf('Ingesting %d figure(s) (File #1 = Reference Baseline)...\n', length(figPaths));

    extractedData = struct('type', {}, 'label', {}, 'shortName', {}, ...
        'x', {}, 'y', {}, 'db', {}, 'c', {}, 'xLabel', {}, 'yLabel', {});
    isSpectrogramMode = false;

    for i = 1:length(figPaths)
        fPath = figPaths{i};
        if ~exist(fPath, 'file')
            fprintf(2, '  [SKIP] File not found: %s\n', fPath);
            continue;
        end

        [fDir, fBase, ~] = fileparts(fPath);
        [~, sampleDir] = fileparts(fDir);
        if isempty(sampleDir)
            sampleDir = fBase;
        end
        traceLabel = sprintf('%s (%s)', sampleDir, fBase);

        try
            srcFig = openfig(fPath, 'invisible');
            srcAxes = findobj(srcFig, 'Type', 'axes');
            if isempty(srcAxes)
                close(srcFig);
                continue;
            end
            primaryAxes = srcAxes(end);

            % 3A. Check for 2D Spectrogram Image
            imgs = findobj(primaryAxes, 'Type', 'image');
            if ~isempty(imgs)
                isSpectrogramMode = true;
                bestImg = imgs(1);
                xData = bestImg.XData;
                yData = bestImg.YData;
                cData = bestImg.CData;

                if length(xData) == 2 && size(cData, 2) > 2
                    xData = linspace(xData(1), xData(2), size(cData, 2));
                end
                if length(yData) == 2 && size(cData, 1) > 2
                    yData = linspace(yData(1), yData(2), size(cData, 1));
                end

                entry = struct();
                entry.type      = 'spectrogram';
                entry.label     = traceLabel;
                entry.shortName = sampleDir;
                entry.x         = xData;
                entry.y         = yData;
                entry.db        = [];
                entry.c         = cData;
                entry.xLabel    = char(string(primaryAxes.XLabel.String));
                entry.yLabel    = char(string(primaryAxes.YLabel.String));
                extractedData(end+1) = entry; %#ok<AGROW>

                close(srcFig);
                fprintf('  [+] Ingested Spectrogram #%d: %s\n', i, traceLabel);
                continue;
            end

            % 3B. Check for 1D Line Plot (frequency.fig or amplitude.fig)
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

                xVec = bestLine.XData(:);
                yVec = bestLine.YData(:);
                dbVec = [];

                % Check if companion features_by_frequency.csv exists for exact Energy_dB
                csvCandidate = fullfile(fDir, 'features_by_frequency.csv');
                if strcmpi(fBase, 'frequency') && exist(csvCandidate, 'file')
                    try
                        T_csv = readtable(csvCandidate);
                        if ismember('Freq_Hz', T_csv.Properties.VariableNames) && ...
                           ismember('Step_Peak_Amp', T_csv.Properties.VariableNames) && ...
                           ismember('Energy_dB', T_csv.Properties.VariableNames)
                            xVec  = T_csv.Freq_Hz(:);
                            yVec  = T_csv.Step_Peak_Amp(:);
                            dbVec = T_csv.Energy_dB(:);
                        end
                    catch
                    end
                end

                if isempty(dbVec)
                    dbVec = 20 * log10(max(abs(yVec), eps));
                end

                entry = struct();
                entry.type      = 'line';
                entry.label     = traceLabel;
                entry.shortName = sampleDir;
                entry.x         = xVec;
                entry.y         = yVec;
                entry.db        = dbVec;
                entry.c         = [];
                entry.xLabel    = char(string(primaryAxes.XLabel.String));
                entry.yLabel    = char(string(primaryAxes.YLabel.String));
                extractedData(end+1) = entry; %#ok<AGROW>

                close(srcFig);
                fprintf('  [+] Ingested Trace #%d:       %s (%d points)\n', i, traceLabel, length(entry.x));
                continue;
            end

            close(srcFig);
        catch ME
            fprintf(2, '  [ERROR] Ingestion failed for %s: %s\n', fPath, ME.message);
        end
    end

    if length(extractedData) < 2
        error('At least 2 valid figures are required to compute a subtraction.');
    end

    baseData = extractedData(1);
    testData = extractedData(2:end);
    numTests = length(testData);

    colorPalette = [
        1.00, 0.60, 0.10;  % Vivid Orange (Test 1)
        0.95, 0.25, 0.30;  % Coral Crimson (Test 2)
        0.00, 0.82, 0.95;  % Electric Cyan (Test 3)
        0.20, 0.85, 0.40;  % Emerald Green (Test 4)
        0.75, 0.40, 0.90;  % Bright Purple (Test 5)
        0.95, 0.80, 0.15;  % Gold Amber (Test 6)
    ];
    numColors = size(colorPalette, 1);

    %% 4A. Render 2D Differential Spectrograms (Test_k - Baseline)
    if isSpectrogramMode
        fig = figure('Name', sprintf('Spectrogram Subtraction (Test - Baseline) - %s', taskName), ...
            'NumberTitle', 'off', ...
            'Color', [0.11, 0.12, 0.14], ...
            'Position', [100, 60, 1120, min(300 * numTests + 100, 860)], ...
            'Visible', 'off');

        sb = uicontrol('Parent', fig, 'Style', 'text', ...
            'String', ' [Difference Tracker] Hover cursor over heatmaps to inspect Delta dB (Test - Baseline)', ...
            'Units', 'normalized', ...
            'Position', [0.08, 0.01, 0.88, 0.035], ...
            'BackgroundColor', [0.15, 0.16, 0.19], ...
            'ForegroundColor', [0.45, 0.85, 0.95], ...
            'FontSize', 9, 'HorizontalAlignment', 'left', ...
            'Tag', 'CoordinateStatusBar');

        axList = gobjects(1, numTests);
        f_cutoff = 0.586 * 346.0 / 0.10;

        for k = 1:numTests
            axList(k) = subplot(numTests, 1, k, 'Parent', fig);
            gridBase = baseData.c;
            gridTest = testData(k).c;
            minR = min(size(gridBase, 1), size(gridTest, 1));
            minC = min(size(gridBase, 2), size(gridTest, 2));

            deltaDB = gridTest(1:minR, 1:minC) - gridBase(1:minR, 1:minC);
            tCommon = baseData.x(1:minC);
            fCommon = baseData.y(1:minR);

            imagesc(axList(k), tCommon, fCommon, deltaDB);
            axis(axList(k), 'xy');
            try
                colormap(axList(k), turbo);
            catch
                colormap(axList(k), jet);
            end
            cb = colorbar(axList(k));
            ylabel(cb, '\Delta Energy (dB)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 8);
            set(cb, 'Color', [0.85, 0.88, 0.92]);
            maxDelta = max(abs(deltaDB(:)));
            if maxDelta > 0
                caxis(axList(k), [-maxDelta, maxDelta]);
            end

            title(axList(k), sprintf('\\Delta dB = [%s] - [%s (Baseline)]', testData(k).shortName, baseData.shortName), ...
                'Color', [0.95, 0.96, 0.98], 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
            ylabel(axList(k), 'Freq (Hz)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
            ylim(axList(k), [0, 2200]);
            yline(axList(k), f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                'Color', [0.75, 0.78, 0.82], 'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left', ...
                'LabelColor', [0.85, 0.88, 0.92]);
            set(axList(k), 'Color', [0.07, 0.08, 0.09], 'XColor', [0.65, 0.68, 0.74], 'YColor', [0.65, 0.68, 0.74]);
        end
        xlabel(axList(end), 'Time (seconds)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9);
        linkaxes(axList, 'xy');
        set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMoveSpec(src, evt, axList, sb));

    %% 4B. Render 1D Frequency / Waveform Subtraction (Test_k - Baseline)
    else
        isFreq = contains(lower(string(baseData.xLabel)), 'freq') || ...
                 contains(lower(string(baseData.label)), 'freq');

        if isFreq && length(baseData.x) <= 32
            % 2-Panel Discrete Step Subtraction (Top: Delta Amplitude, Bottom: Delta dB Bars)
            fig = figure('Name', sprintf('Acoustic Baseline Subtraction - %s', taskName), ...
                'NumberTitle', 'off', ...
                'Color', [0.11, 0.12, 0.14], ...
                'Position', [120, 60, 1100, 760], ...
                'Visible', 'off');

            sb = uicontrol('Parent', fig, 'Style', 'text', ...
                'String', ' [Subtraction Tracker] Hover over plots to inspect (Test - Baseline) differences', ...
                'Units', 'normalized', ...
                'Position', [0.08, 0.015, 0.88, 0.035], ...
                'BackgroundColor', [0.15, 0.16, 0.19], ...
                'ForegroundColor', [0.45, 0.85, 0.95], ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'Tag', 'CoordinateStatusBar');

            % --- TOP PANEL: Delta Peak Amplitude (Test - Baseline) ---
            ax1 = subplot(2, 1, 1, 'Parent', fig);
            set(ax1, 'Position', [0.08, 0.56, 0.88, 0.37], ...
                'Color', [0.07, 0.08, 0.09], ...
                'XColor', [0.82, 0.85, 0.90], 'YColor', [0.82, 0.85, 0.90], ...
                'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
            grid(ax1, 'on'); box(ax1, 'on'); hold(ax1, 'on');

            yline(ax1, 0, '--', sprintf('Baseline Reference: %s (0 = No Change)', baseData.shortName), ...
                'Color', [0.75, 0.80, 0.85], 'LineWidth', 1.2, ...
                'LabelHorizontalAlignment', 'left', 'LabelColor', [0.85, 0.88, 0.92], 'Interpreter', 'none');

            freqVec = baseData.x(:);
            nFreq = length(freqVec);
            deltaAmpMat = zeros(nFreq, numTests);
            deltaDBMat  = zeros(nFreq, numTests);
            plotLines1  = gobjects(1, numTests);
            legendNames = cell(1, numTests);

            fprintf('\n--- Subtraction Summary (Relative to %s) ---\n', baseData.shortName);

            for k = 1:numTests
                c = colorPalette(mod(k - 1, numColors) + 1, :);
                minLen = min(nFreq, length(testData(k).y));
                dAmp = testData(k).y(1:minLen) - baseData.y(1:minLen);
                dDB  = testData(k).db(1:minLen) - baseData.db(1:minLen);

                deltaAmpMat(1:minLen, k) = dAmp;
                deltaDBMat(1:minLen, k)  = dDB;

                % Find worst drop (minimum Delta dB and minimum Delta Amp)
                [minDB, idxMinDB] = min(dDB);
                [minAmp, idxMinAmp] = min(dAmp);
                fprintf('  * %s:\n', testData(k).shortName);
                fprintf('       Max Amplitude Drop : %+.4f at %d Hz (Baseline %.4f -> Test %.4f)\n', ...
                    minAmp, round(freqVec(idxMinAmp)), baseData.y(idxMinAmp), testData(k).y(idxMinAmp));
                fprintf('       Max Energy dB Drop : %+.2f dB at %d Hz (Baseline %.2f dB -> Test %.2f dB)\n', ...
                    minDB, round(freqVec(idxMinDB)), baseData.db(idxMinDB), testData(k).db(idxMinDB));

                lbl = sprintf('%s - %s', testData(k).shortName, baseData.shortName);
                legendNames{k} = lbl;

                h = plot(ax1, freqVec(1:minLen), dAmp, '-o', 'Color', c, ...
                    'LineWidth', 1.8, 'MarkerSize', 6, 'MarkerFaceColor', c, ...
                    'DisplayName', lbl);

                % Mark the biggest amplitude drop with a diamond halo
                plot(ax1, freqVec(idxMinAmp), minAmp, 'p', 'Color', [1, 1, 1], ...
                    'MarkerSize', 11, 'LineWidth', 1.5, 'HandleVisibility', 'off');
                text(ax1, freqVec(idxMinAmp), minAmp, ...
                    sprintf('  %d Hz (%+.3f)', round(freqVec(idxMinAmp)), minAmp), ...
                    'Color', c, 'FontSize', 8.5, 'FontWeight', 'bold', 'VerticalAlignment', 'top');

                try
                    h.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Frequency', 'XData', '%.0f Hz');
                    h.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Delta Amp (Test - Base)', 'YData', '%+.5f');
                    h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow('Comparison', repmat({lbl}, 1, minLen));
                catch
                end

                plotLines1(k) = h;
            end

            title(ax1, sprintf('1. Amplitude Difference: \\Delta Peak Amplitude = Test - Baseline (%s)', baseData.shortName), ...
                'Color', [0.95, 0.96, 0.98], 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            ylabel(ax1, '\Delta Peak Amplitude', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
            xticks(ax1, freqVec);
            xlim(ax1, [min(freqVec) - 50, max(freqVec) + 50]);
            lgd1 = legend(ax1, plotLines1, legendNames, 'Location', 'southwest', ...
                'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], ...
                'EdgeColor', [0.28, 0.30, 0.35], 'Interpreter', 'none');
            set(lgd1, 'FontSize', 8.5);

            % --- BOTTOM PANEL: Delta Energy (dB) Bar Chart ---
            ax2 = subplot(2, 1, 2, 'Parent', fig);
            set(ax2, 'Position', [0.08, 0.11, 0.88, 0.37], ...
                'Color', [0.07, 0.08, 0.09], ...
                'XColor', [0.82, 0.85, 0.90], 'YColor', [0.82, 0.85, 0.90], ...
                'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
            grid(ax2, 'on'); box(ax2, 'on'); hold(ax2, 'on');

            b = bar(ax2, freqVec, deltaDBMat, 0.82, 'grouped');
            for k = 1:numTests
                c = colorPalette(mod(k - 1, numColors) + 1, :);
                b(k).FaceColor = c;
                b(k).EdgeColor = 'none';
                b(k).DisplayName = sprintf('%s (\\Delta dB)', legendNames{k});

                % Annotate worst dB drop bar
                [minDB, idxMinDB] = min(deltaDBMat(:, k));
                text(ax2, freqVec(idxMinDB), minDB - 0.8, ...
                    sprintf('%d Hz: %+.1f dB', round(freqVec(idxMinDB)), minDB), ...
                    'Color', c, 'FontSize', 8.5, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            end

            yline(ax2, 0, '-', 'Color', [0.80, 0.82, 0.86], 'LineWidth', 1.0, 'HandleVisibility', 'off');

            title(ax2, sprintf('2. Energy Difference: \\Delta Energy (dB) = Test - Baseline (%s)', baseData.shortName), ...
                'Color', [0.95, 0.96, 0.98], 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            xlabel(ax2, 'Excitation Frequency (Hz)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
            ylabel(ax2, '\Delta Energy (dB)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
            xticks(ax2, freqVec);
            xlim(ax2, [min(freqVec) - 60, max(freqVec) + 60]);
            minY = min(deltaDBMat(:));
            maxY = max(deltaDBMat(:));
            ylim(ax2, [min(minY - 4, -5), max(maxY + 3, 5)]);

            lgd2 = legend(ax2, b, legendNames, 'Location', 'southwest', ...
                'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], ...
                'EdgeColor', [0.28, 0.30, 0.35], 'Interpreter', 'none');
            set(lgd2, 'FontSize', 8.5);

            linkaxes([ax1, ax2], 'x');
            set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMoveDual(src, evt, ax1, ax2, sb));

        else
            % Continuous Line Subtraction (e.g. amplitude.fig waveform residual)
            fig = figure('Name', sprintf('Waveform Subtraction - %s', taskName), ...
                'NumberTitle', 'off', ...
                'Color', [0.11, 0.12, 0.14], ...
                'Position', [150, 100, 1050, 620], ...
                'Visible', 'off');

            ax = axes('Parent', fig, 'Units', 'normalized', ...
                'Position', [0.08, 0.12, 0.88, 0.80], ...
                'Color', [0.07, 0.08, 0.09], ...
                'XColor', [0.65, 0.68, 0.74], 'YColor', [0.65, 0.68, 0.74], ...
                'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
            grid(ax, 'on'); box(ax, 'on'); hold(ax, 'on');

            sb = uicontrol('Parent', fig, 'Style', 'text', ...
                'String', ' [Subtraction Tracker] Hover cursor over traces to inspect Delta coordinates', ...
                'Units', 'normalized', ...
                'Position', [0.08, 0.02, 0.88, 0.04], ...
                'BackgroundColor', [0.15, 0.16, 0.19], ...
                'ForegroundColor', [0.45, 0.85, 0.95], ...
                'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'Tag', 'CoordinateStatusBar');

            plotLines = [];
            legendLabels = {};
            for k = 1:numTests
                c = colorPalette(mod(k - 1, numColors) + 1, :);
                minLen = min(length(baseData.y), length(testData(k).y));
                dY = testData(k).y(1:minLen) - baseData.y(1:minLen);
                lbl = sprintf('%s - %s', testData(k).shortName, baseData.shortName);

                h = plot(ax, baseData.x(1:minLen), dY, 'Color', c, 'LineWidth', 1.2, 'DisplayName', lbl);
                plotLines(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = lbl; %#ok<AGROW>
            end

            xlabel(ax, baseData.xLabel, 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
            ylabel(ax, ['\Delta ', baseData.yLabel], 'Color', [0.85, 0.88, 0.92], 'FontSize', 10);
            title(ax, sprintf('Residual Difference (Test - Baseline): %s', taskName), ...
                'Color', [0.95, 0.96, 0.98], 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            legend(ax, plotLines, legendLabels, 'Location', 'northeast', ...
                'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], 'Interpreter', 'none');
        end
    end

    %% 5. Save Difference Figure to analyze/different/{taskName}/{taskName}.fig
    set(fig, 'Visible', 'on');
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Difference figure successfully written to:\n  %s\n', outFigPath);

    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Diff.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);

    if ~showPlot
        close(fig);
    end
end

%% Helper Callbacks for Live Coordinate Tracking
function onMouseMoveDual(~, ~, ax1, ax2, sb)
    cp1 = get(ax1, 'CurrentPoint');
    x1 = cp1(1, 1); y1 = cp1(1, 2);
    xLim1 = xlim(ax1); yLim1 = ylim(ax1);
    if x1 >= xLim1(1) && x1 <= xLim1(2) && y1 >= yLim1(1) && y1 <= yLim1(2)
        set(sb, 'String', sprintf('  [TOP PANEL: DELTA AMPLITUDE] Freq: %6.0f Hz | Delta Peak Amp (Test - Base): %+.5f', x1, y1));
        return;
    end

    cp2 = get(ax2, 'CurrentPoint');
    x2 = cp2(1, 1); y2 = cp2(1, 2);
    xLim2 = xlim(ax2); yLim2 = ylim(ax2);
    if x2 >= xLim2(1) && x2 <= xLim2(2) && y2 >= yLim2(1) && y2 <= yLim2(2)
        set(sb, 'String', sprintf('  [BOTTOM PANEL: DELTA ENERGY] Freq: %6.0f Hz | Delta Energy (Test - Base): %+.2f dB', x2, y2));
    end
end

function onMouseMoveSpec(~, ~, axList, sb)
    for a = 1:length(axList)
        ax = axList(a);
        cp = get(ax, 'CurrentPoint');
        x = cp(1, 1); y = cp(1, 2);
        xLim = xlim(ax); yLim = ylim(ax);
        if x >= xLim(1) && x <= xLim(2) && y >= yLim(1) && y <= yLim(2)
            set(sb, 'String', sprintf('  [DIFF PANEL %d] Time: %6.3f s | Frequency: %6.1f Hz', a, x, y));
            return;
        end
    end
end
