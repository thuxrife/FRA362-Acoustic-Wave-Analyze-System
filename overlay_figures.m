function [outFigPath, fig] = overlay_figures(figPaths, taskName, showPlot)
%% Acoustic Trace Overlay Engine (Raw Data Mode)
% Overlays raw data traces across multiple conditions onto a single standalone graph.
% Automatically detects the input domain and saves to:
%   - analyze/overlay/amplitude/{taskName}.fig
%   - analyze/overlay/frequency/{taskName}.fig
%   - analyze/overlay/spectrogram/{taskName}.fig
%
% Aesthetics:
%   Clean IEEE/engineering style: pure white background ('w'), crisp black axes,
%   material depth-of-color lines with distinct markers, subtle grid, and no dark themes.
%
% Usage:
%   overlay_figures('analyze/.../frequency.fig, analyze/.../frequency.fig', 'freq_compare');
%   overlay_figures(); % Opens interactive GUI prompt

    OUTPUT_ROOT = fullfile('analyze', 'overlay');

    %% 1. Interactive Input Dialog if Arguments Omitted
    if nargin < 1 || isempty(figPaths)
        prompt = {
            sprintf('Enter relative .fig or .csv paths separated by comma ",":\n(e.g., analyze/.../frequency.fig, analyze/.../frequency.fig)'), ...
            'Overlay Task Name (saves to analyze/overlay/{domain}/{taskName}.fig):'
        };
        dlgtitle = 'Raw Data Trace Overlay (Single Graph)';
        dims = [4, 95; 1, 95];
        defaultName = sprintf('overlay_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        definput = {
            'analyze/2026-11-08-baseline/sound_sample_baseline/frequency.fig, analyze/2026-11-08-exp-02-sediment-area/sound_sample_clay_25_h_middle/frequency.fig, analyze/2026-11-08-exp-02-sediment-area/sound_sample_clay_50_h_middle/frequency.fig', ...
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
            figPaths = strjoin(cellstr(figPaths), ',');
        end
        rawStr = char(figPaths);
        rawCells = strsplit(rawStr, {',', ';', newline});
    elseif iscell(figPaths)
        rawCells = {};
        for k = 1:length(figPaths)
            parts = strsplit(char(figPaths{k}), {',', ';', newline});
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
        error('No valid paths found in the input string.');
    end

    if nargin < 2 || isempty(taskName)
        taskName = sprintf('overlay_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    if nargin < 3 || isempty(showPlot)
        showPlot = true;
    end

    %% 3. Ingest Figures / CSVs and Extract Raw Traces
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

            % Check for 2D Spectrogram Image
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
                entry.type   = 'spectrogram';
                entry.label  = traceLabel;
                entry.x      = xData;
                entry.y      = yData;
                entry.c      = cData;
                entry.xLabel = char(string(primaryAxes.XLabel.String));
                entry.yLabel = char(string(primaryAxes.YLabel.String));
                extractedData(end+1) = entry; %#ok<AGROW>

                close(srcFig);
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
                continue;
            end
            close(srcFig);
        catch ME
            fprintf(2, '  [WARN] Failed to inspect %s: %s\n', fPath, ME.message);
        end
    end

    if isempty(extractedData)
        error('No valid line or image traces could be extracted from input paths.');
    end

    %% 4. Determine Output Domain Subfolder
    isFreq = contains(lower(string(extractedData(1).xLabel)), 'freq') || ...
             contains(lower(string(extractedData(1).label)), 'freq');

    if isSpectrogramMode
        domainFolder = 'spectrogram';
    elseif isFreq
        domainFolder = 'frequency';
    else
        domainFolder = 'amplitude';
    end

    targetDir = fullfile(OUTPUT_ROOT, domainFolder);
    if ~exist(targetDir, 'dir'), mkdir(targetDir); end
    outFigPath = fullfile(targetDir, [taskName, '.fig']);

    %% 5. Render Standalone Single-Graph Figure (Pure White Aesthetic)
    fig = figure('Name', sprintf('Raw Trace Overlay [%s] - %s', upper(domainFolder), taskName), ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Position', [120, 80, 1080, 680], ...
        'Visible', 'off');

    numTraces = length(extractedData);

    % Detect whether multiple sediment types are mixed in this graph
    allLabels = lower({extractedData.label});
    hasClay   = any(contains(allLabels, 'clay'));
    hasLeaf   = any(contains(allLabels, 'leaf'));
    hasStone  = any(contains(allLabels, 'stone') | contains(allLabels, 'sand') | contains(allLabels, 'gravel'));
    isMultiMaterial = ((hasClay + hasLeaf + hasStone) > 1);

    plotColors     = zeros(numTraces, 3);
    plotLineStyles = cell(1, numTraces);
    plotMarkers    = cell(1, numTraces);
    legendLabels   = cell(1, numTraces);

    distinctPalette = [
        0.15, 0.15, 0.15;  % 1: Charcoal / Baseline
        0.00, 0.45, 0.75;  % 2: Deep Blue (25% / Front)
        0.12, 0.65, 0.28;  % 3: Forest Green (50% / Middle)
        0.92, 0.58, 0.05;  % 4: Amber Gold (75% / Rear)
        0.85, 0.15, 0.15;  % 5: Ruby Red (100%)
        0.55, 0.20, 0.70;  % 6: Purple
        0.00, 0.65, 0.75;  % 7: Cyan
        0.65, 0.40, 0.15   % 8: Brown
    ];

    for k = 1:numTraces
        name = lower(extractedData(k).label);
        isBase = contains(name, 'base') || contains(name, '0%');
        isPos  = contains(name, 'front') || contains(name, 'middle') || contains(name, 'mid') || contains(name, 'rear') || contains(name, 'back');
        if contains(name, '25') || contains(name, '50') || contains(name, '75')
            isPos = false;
        end

        % All Amplitude and Frequency line traces strictly use solid lines
        plotLineStyles{k} = '-';

        % Assign Labels and Markers
        if isPos
            if contains(name, 'front')
                posStr = 'Front'; plotMarkers{k} = 'o'; posFrac = 0.50;
            elseif contains(name, 'middle') || contains(name, 'mid')
                posStr = 'Middle'; plotMarkers{k} = 's'; posFrac = 0.75;
            else
                posStr = 'Rear'; plotMarkers{k} = '^'; posFrac = 1.00;
            end
            clean = regexprep(extractedData(k).label, '^sound_sample_', '');
            lbl = sprintf('%s [%s]', clean, posStr);
        elseif contains(name, '100')
            plotMarkers{k} = '^'; posFrac = 1.00;
            lbl = extractedData(k).label;
        elseif contains(name, '75')
            plotMarkers{k} = 'd'; posFrac = 0.75;
            lbl = extractedData(k).label;
        elseif contains(name, '50')
            plotMarkers{k} = 'o'; posFrac = 0.50;
            lbl = extractedData(k).label;
        elseif contains(name, '25')
            plotMarkers{k} = 's'; posFrac = 0.25;
            lbl = extractedData(k).label;
        elseif isBase
            plotMarkers{k} = 'o'; posFrac = 0.00;
            lbl = extractedData(k).label;
        else
            plotMarkers{k} = 'o'; posFrac = k / max(1, numTraces);
            lbl = extractedData(k).label;
        end
        legendLabels{k} = strrep(lbl, '_', ' ');

        % --- Color Assignment ---
        if isMultiMaterial
            % Rule 1: Mixed Sediments in 1 graph -> Enforce Sediment Color Code
            if isBase
                plotColors(k, :) = [0.15, 0.15, 0.15]; % Baseline Black
            elseif contains(name, 'clay')
                cBase = [0.90, 0.45, 0.08]; % Orange
                plotColors(k, :) = cBase * (0.65 + 0.35 * posFrac);
            elseif contains(name, 'leaf')
                cBase = [0.12, 0.68, 0.28]; % Green
                plotColors(k, :) = cBase * (0.65 + 0.35 * posFrac);
            elseif contains(name, 'stone') || contains(name, 'sand') || contains(name, 'gravel')
                cBase = [0.10, 0.45, 0.88]; % Blue
                plotColors(k, :) = cBase * (0.65 + 0.35 * posFrac);
            else
                plotColors(k, :) = [0.55, 0.20, 0.70]; % Purple
            end
        else
            % Rule 2: Single Sediment in 1 graph -> Distinct High-Contrast Colors
            if isBase
                plotColors(k, :) = [0.15, 0.15, 0.15]; % Baseline Black
            elseif isPos
                if contains(name, 'front')
                    plotColors(k, :) = [0.00, 0.45, 0.75]; % Deep Blue
                elseif contains(name, 'middle') || contains(name, 'mid')
                    plotColors(k, :) = [0.90, 0.48, 0.05]; % Vivid Amber
                else
                    plotColors(k, :) = [0.55, 0.18, 0.60]; % Crimson Violet
                end
            else
                if contains(name, '25')
                    plotColors(k, :) = [0.00, 0.45, 0.75]; % Deep Blue
                elseif contains(name, '50')
                    plotColors(k, :) = [0.12, 0.65, 0.28]; % Forest Green
                elseif contains(name, '75')
                    plotColors(k, :) = [0.92, 0.58, 0.05]; % Amber Gold
                elseif contains(name, '100')
                    plotColors(k, :) = [0.85, 0.15, 0.15]; % Ruby Red
                else
                    plotColors(k, :) = distinctPalette(mod(k-1, size(distinctPalette, 1)) + 1, :);
                end
            end
        end
    end

    if isSpectrogramMode
        % Synchronized Spectrogram Subplots: 3 Rows x 1 Column (Stretched Horizontally)
        numSpecs = length(extractedData);
        axList = gobjects(1, numSpecs);
        f_cutoff = 0.586 * 346.0 / 0.10;

        leftM = 0.08; width = 0.81;
        bottomM = 0.08; topM = 0.94; totalH = topM - bottomM;
        gap = 0.04; subH = (totalH - (numSpecs - 1) * gap) / numSpecs;

        % Dedicated Purple -> Yellow Heatmap Colormap (Plasma style)
        purpleYellowMap = [
            linspace(0.08, 0.55, 64)', linspace(0.02, 0.10, 64)', linspace(0.25, 0.65, 64)';
            linspace(0.55, 0.92, 64)', linspace(0.10, 0.45, 64)', linspace(0.65, 0.15, 64)';
            linspace(0.92, 0.98, 64)', linspace(0.45, 0.85, 64)', linspace(0.15, 0.10, 64)';
            linspace(0.98, 0.99, 64)', linspace(0.85, 0.98, 64)', linspace(0.10, 0.55, 64)'
        ];

        for k = 1:numSpecs
            yPos = topM - k * subH - (k - 1) * gap;
            ax = axes('Parent', fig, 'Position', [leftM, yPos, width, subH]);
            axList(k) = ax;
            imagesc(ax, extractedData(k).x, extractedData(k).y, extractedData(k).c);
            axis(ax, 'xy');
            colormap(ax, purpleYellowMap);
            set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'LineWidth', 1.0, 'Box', 'on');
            title(ax, legendLabels{k}, 'Color', 'k', 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
            ylabel(ax, 'Freq (Hz)', 'Color', 'k', 'FontSize', 9.5);
            if k == numSpecs
                xlabel(ax, 'Time (s)', 'Color', 'k', 'FontSize', 9.5, 'FontWeight', 'bold');
            else
                set(ax, 'XTickLabel', []);
            end
            ylim(ax, [0, 2200]);
            yline(ax, f_cutoff, '--', 'Color', [0.35, 0.35, 0.35], 'LineWidth', 1.0);
        end
        cb = colorbar(axList(end), 'Position', [0.91, bottomM, 0.02, totalH]);
        cb.Color = 'k';
        ylabel(cb, 'Sound Energy (dB)', 'Color', 'k', 'FontSize', 9.0, 'FontWeight', 'bold');
        linkaxes(axList, 'xy');
    else
        % Standalone 1D Line Graph
        ax = axes('Parent', fig, 'Units', 'normalized', ...
            'Position', [0.08, 0.12, 0.88, 0.80], ...
            'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
            'LineWidth', 1.0, 'Box', 'on', ...
            'GridColor', [0.85, 0.85, 0.85], 'GridAlpha', 0.8);
        grid(ax, 'on'); hold(ax, 'on');

        plotLines = gobjects(1, numTraces);
        for k = 1:numTraces
            c = plotColors(k, :);
            ls = plotLineStyles{k};
            mk = plotMarkers{k};

            if isFreq && length(extractedData(k).x) <= 32
                h = plot(ax, extractedData(k).x, extractedData(k).y, ...
                    'LineStyle', ls, 'Color', c, 'LineWidth', 1.6, ...
                    'Marker', mk, 'MarkerSize', 5.5, 'MarkerFaceColor', c, ...
                    'MarkerEdgeColor', 'k', 'DisplayName', legendLabels{k});
            else
                h = plot(ax, extractedData(k).x, extractedData(k).y, ...
                    'LineStyle', ls, 'Color', c, 'LineWidth', 1.2, ...
                    'DisplayName', legendLabels{k});
            end
            plotLines(k) = h;
        end

        xlabel(ax, extractedData(1).xLabel, 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        yLbl = extractedData(1).yLabel;
        if strcmpi(domainFolder, 'amplitude') && ~contains(yLbl, '[FS]')
            yLbl = 'Amplitude [FS]';
        end
        ylabel(ax, yLbl, 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        title(ax, sprintf('Raw %s Overlay: %s', upper(domainFolder), taskName), ...
            'Color', 'k', 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'none');

        if isFreq
            f_cutoff = 0.586 * 346.0 / 0.10;
            xline(ax, f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                'Color', [0.35, 0.35, 0.35], 'LineWidth', 1.1, 'LabelVerticalAlignment', 'top', ...
                'LabelColor', 'k');
            xlim(ax, [min(extractedData(1).x) - 50, max(extractedData(1).x) + 50]);
            xticks(ax, 300:100:1800);
        end

        lgd = legend(ax, plotLines, legendLabels, 'Location', 'northeast', ...
            'TextColor', 'k', 'Color', 'w', 'EdgeColor', [0.75, 0.75, 0.75], 'Interpreter', 'none');
        set(lgd, 'FontSize', 9);
        pan(fig, 'on');
    end

    %% 6. Save Figure to analyze/overlay/{domain}/{taskName}.fig
    set(fig, 'Visible', 'on');
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Raw Overlay Figure written to:\n  %s\n', outFigPath);

    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Overlay.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);

    if ~showPlot
        close(fig);
    end
end
