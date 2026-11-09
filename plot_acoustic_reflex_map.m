function [outFigPath, fig] = plot_acoustic_reflex_map(inputPaths, taskName)
%% Acoustic Reflex Map Engine (Option C: 8-Second Timeline + Synchronized Spectrogram Heatmaps)
% Computes differential analytic envelope \Delta E(t) = E_Test(t) - E_Baseline(t)
% across all 16 frequency steps, completely suppressing the direct speaker pulse (down to ~0.01)
% while resolving moving obstacle reflections into synchronized vertical ridges.
%
% Panels:
%   Top Panel:    Full 8.0-second continuous differential timeline showing all test conditions.
%   Bottom Panel: Synchronized Time-of-Flight (0-16 ms) differential spectrograms/heatmaps
%                 across all 16 frequencies (300-1800 Hz) side-by-side.
%
% Visual Style:
%   Clean IEEE/engineering graph plotter: pure white background ('w'), crisp black axes,
%   material depth-of-color lines in the top panel, and a smooth Purple-to-Yellow
%   heatmap colormap matching the Option C standard.
%
% Output:
%   Saves interactive .fig to: analyze/envelope/spectrogram/{taskName}.fig
%
% Usage:
%   plot_acoustic_reflex_map(); % Interactive dialog
%   plot_acoustic_reflex_map('base.csv, test1.csv, test2.csv', 'task_name');

    fs = 44100;
    outRoot = fullfile('analyze', 'envelope', 'spectrogram');
    if ~exist(outRoot, 'dir'), mkdir(outRoot); end

    %% 1. Interactive Input Dialog if Arguments Omitted or Empty
    if nargin < 1 || isempty(inputPaths)
        prompt = {
            sprintf('Enter relative paths to raw logged CSV files or folders (separated by comma ","): \n(1st path = Reference Baseline, 2nd..N = Test Reflex files)'), ...
            'Reflex Map Task Name (saves to analyze/envelope/spectrogram/{taskName}.fig):'
        };
        dlgtitle = 'Acoustic Reflex Map Input (Option C Spectrogram Heatmaps)';
        dims = [4, 95; 1, 95];
        if nargin < 2 || isempty(taskName)
            defaultName = sprintf('reflex_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        else
            defaultName = taskName;
        end
        definput = {
            'logged/2026-11-08-baseline/sound_sample_baseline.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_25_h_middle.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_50_h_middle.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_75_h_middle.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_clay_100_h_middle.csv', ...
            defaultName
        };
        opts.Resize = 'on';
        answer = inputdlg(prompt, dlgtitle, dims, definput, opts);

        if isempty(answer)
            fprintf('[Reflex Map] Cancelled by user.\n');
            outFigPath = '';
            fig = [];
            return;
        end

        inputPaths = answer{1};
        if ~isempty(strtrim(answer{2}))
            taskName = strtrim(answer{2});
        end
    end

    %% 2. Parse and Clean Comma-Separated Input
    if ischar(inputPaths) || isstring(inputPaths)
        if ischar(inputPaths) && size(inputPaths, 1) > 1
            inputPaths = strjoin(cellstr(inputPaths), ',');
        end
        rawStr = char(inputPaths);
        rawCells = strsplit(rawStr, {',', ';', newline});
    elseif iscell(inputPaths)
        rawCells = {};
        for k = 1:length(inputPaths)
            parts = strsplit(char(inputPaths{k}), {',', ';', newline});
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

    if isempty(cleanedPaths)
        error('No valid file or folder paths provided.');
    end

    %% 3. Determine Baseline and Test Paths
    if length(cleanedPaths) == 1 && ~endsWith(cleanedPaths{1}, '.csv', 'IgnoreCase', true) && ...
       ~endsWith(cleanedPaths{1}, '.fig', 'IgnoreCase', true)
        trialName = cleanedPaths{1};
        trialName = regexprep(trialName, '^logged/|^analyze/', '');
        trialLoggedDir = fullfile('logged', trialName);
        csvList = dir(fullfile(trialLoggedDir, '*.csv'));
        if isempty(csvList)
            error('No logged CSV files found in "%s".', trialLoggedDir);
        end

        baseIdx = find(contains({csvList.name}, 'base', 'IgnoreCase', true), 1);
        if ~isempty(baseIdx)
            baseCsvPath = fullfile(trialLoggedDir, csvList(baseIdx).name);
            baseShortName = strrep(csvList(baseIdx).name, '.csv', '');
            testFiles = csvList(~contains({csvList.name}, 'base', 'IgnoreCase', true));
        elseif exist(fullfile('logged', '2026-11-08-baseline', 'sound_sample_baseline.csv'), 'file')
            baseCsvPath = fullfile('logged', '2026-11-08-baseline', 'sound_sample_baseline.csv');
            baseShortName = 'sound_sample_baseline';
            testFiles = csvList;
        else
            baseCsvPath = fullfile(trialLoggedDir, csvList(1).name);
            baseShortName = strrep(csvList(1).name, '.csv', '');
            testFiles = csvList(2:end);
        end

        numTests = min(6, length(testFiles));
        testCsvPaths = cell(1, numTests);
        testShortNames = cell(1, numTests);
        for k = 1:numTests
            testCsvPaths{k} = fullfile(trialLoggedDir, testFiles(k).name);
            testShortNames{k} = strrep(testFiles(k).name, '.csv', '');
        end
        defaultTask = sprintf('reflex_%s', trialName);
    else
        [baseCsvPath, baseShortName] = resolveAudioDataCsv(cleanedPaths{1});
        numTests = length(cleanedPaths) - 1;
        if numTests < 1
            error('At least 2 paths must be provided (1st = Reference Baseline, 2nd..N = Test conditions).');
        end
        testCsvPaths = cell(1, numTests);
        testShortNames = cell(1, numTests);
        for k = 1:numTests
            [testCsvPaths{k}, testShortNames{k}] = resolveAudioDataCsv(cleanedPaths{k + 1});
        end
        defaultTask = sprintf('reflex_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    if nargin < 2 || isempty(taskName)
        taskDirName = defaultTask;
    else
        taskDirName = taskName;
    end

    targetDir = outRoot;
    if ~exist(targetDir, 'dir'), mkdir(targetDir); end
    outFigPath = fullfile(targetDir, [taskDirName, '.fig']);

    %% 4. Ingest Data & Compute Differential Analytic Signal Envelopes
    t_base = readtable(baseCsvPath);
    minLen = height(t_base);
    tTables = cell(1, numTests);
    for k = 1:numTests
        tTables{k} = readtable(testCsvPaths{k});
        minLen = min(minLen, height(tTables{k}));
    end

    t_s = t_base.Time_s(1:minLen);
    env_base = abs(hilbert(t_base.Amp_Avg(1:minLen)));

    d_envs = cell(1, numTests);
    for k = 1:numTests
        d_envs{k} = abs(hilbert(tTables{k}.Amp_Avg(1:minLen))) - env_base;
    end

    %% 5. Build 16-Step Synchronized Time-of-Flight Matrices
    freqs = 300:100:1800;
    nSteps = length(freqs);
    tof_ms = linspace(-1.0, 17.0, round(0.018 * fs));
    stepMatrices = cell(1, numTests);
    stepOnsets = zeros(1, nSteps);
    stepTimes = zeros(1, nSteps);

    for s = 1:nSteps
        idx_b = find(t_base.Step_ID == s, 1, 'first');
        if ~isempty(idx_b)
            stepOnsets(s) = idx_b;
            stepTimes(s) = t_s(idx_b);
        else
            approxTime = (s - 1) * 0.504;
            [~, idx_b] = min(abs(t_s - approxTime));
            stepOnsets(s) = idx_b;
            stepTimes(s) = t_s(idx_b);
        end
    end

    for k = 1:numTests
        t_curr = tTables{k};
        mat = zeros(nSteps, length(tof_ms));
        for s = 1:nSteps
            i0_b = find(t_base.Step_ID == s, 1, 'first');
            i0_t = find(t_curr.Step_ID == s, 1, 'first');
            if isempty(i0_b) || isempty(i0_t), continue; end

            w1_b = max(1, i0_b - round(0.005 * fs)); w2_b = min(height(t_base), i0_b + round(0.005 * fs));
            w1_t = max(1, i0_t - round(0.005 * fs)); w2_t = min(height(t_curr), i0_t + round(0.005 * fs));

            [~, rel_b] = max(abs(t_base.Amp_Avg(w1_b:w2_b))); pk_b = w1_b + rel_b - 1;
            [~, rel_t] = max(abs(t_curr.Amp_Avg(w1_t:w2_t))); pk_t = w1_t + rel_t - 1;

            nP = round(0.001 * fs); nF = round(0.017 * fs);
            s_b = t_base.Amp_Avg(max(1, pk_b - nP) : min(height(t_base), pk_b + nF - 1));
            s_t = t_curr.Amp_Avg(max(1, pk_t - nP) : min(height(t_curr), pk_t + nF - 1));

            L_seg = min([length(s_b), length(s_t), length(tof_ms)]);
            row = abs(hilbert(s_t(1:L_seg))) - abs(hilbert(s_b(1:L_seg)));
            mat(s, 1:L_seg) = row;
        end
        stepMatrices{k} = mat;
    end

    %% 6. Depth of Color Assignment per Material and Blockage Area
    % Detect whether multiple sediment types are mixed in this graph
    allLabels = lower(testShortNames);
    hasClay   = any(contains(allLabels, 'clay'));
    hasLeaf   = any(contains(allLabels, 'leaf'));
    hasStone  = any(contains(allLabels, 'stone') | contains(allLabels, 'sand') | contains(allLabels, 'gravel'));
    isMultiMaterial = ((hasClay + hasLeaf + hasStone) > 1);

    plotColors     = zeros(numTests, 3);
    plotLineStyles = cell(1, numTests);
    legendLabels   = cell(1, numTests);

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

    for k = 1:numTests
        name = lower(testShortNames{k});
        isBase = contains(name, 'baseline') || contains(name, '0%') || contains(name, '_base');
        isPos  = contains(name, 'front') || contains(name, 'middle') || contains(name, 'mid') || contains(name, 'rear') || contains(name, 'back');
        if contains(name, '25') || contains(name, '50') || contains(name, '75')
            isPos = false;
        end

        plotLineStyles{k} = '-';

        if isPos
            if contains(name, 'front')
                posStr = 'Front'; posFrac = 0.50;
            elseif contains(name, 'middle') || contains(name, 'mid')
                posStr = 'Middle'; posFrac = 0.75;
            else
                posStr = 'Rear'; posFrac = 1.00;
            end
            lbl = sprintf('%s [%s]', testShortNames{k}, posStr);
        elseif contains(name, '100')
            posFrac = 1.00;
            lbl = sprintf('%s (100%%)', testShortNames{k});
        elseif contains(name, '75')
            posFrac = 0.75;
            lbl = sprintf('%s (75%%)', testShortNames{k});
        elseif contains(name, '50')
            posFrac = 0.50;
            lbl = sprintf('%s (50%%)', testShortNames{k});
        elseif contains(name, '25')
            posFrac = 0.25;
            lbl = sprintf('%s (25%%)', testShortNames{k});
        elseif isBase
            posFrac = 0.00;
            lbl = sprintf('%s (0%%)', testShortNames{k});
        else
            posFrac = k / max(1, numTests);
            lbl = testShortNames{k};
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

    %% 7. Custom Smooth Purple-to-Yellow Colormap
    cmPurpleYellow = getPurpleYellowColormap(256);

    %% 8. Render Publication-Standard White-Background Figure
    fig = figure('Name', sprintf('Acoustic Reflex Map: %s', taskDirName), ...
                 'NumberTitle', 'off', ...
                 'Color', 'w', ...
                 'Position', [50, 40, 1300, 840], ...
                 'Visible', 'on');

    % --- TOP PANEL: Full 8.0-Second Continuous Differential Timeline ---
    axTop = subplot('Position', [0.07, 0.60, 0.85, 0.34], 'Parent', fig);
    set(axTop, 'Color', 'w', ...
               'XColor', 'k', 'YColor', 'k', ...
               'LineWidth', 1.0, 'Box', 'on', ...
               'GridColor', [0.85, 0.85, 0.85], 'GridAlpha', 0.8);
    hold(axTop, 'on'); grid(axTop, 'on');

    topLines = gobjects(1, numTests);
    for k = 1:numTests
        c = plotColors(k, :);
        ls = plotLineStyles{k};
        topLines(k) = plot(axTop, t_s, d_envs{k}, 'LineStyle', ls, 'Color', c, ...
            'LineWidth', 1.3, 'DisplayName', legendLabels{k});
    end

    % Baseline 0 reference line
    yline(axTop, 0, '--', 'Color', [0.35, 0.35, 0.35], 'LineWidth', 1.0, 'HandleVisibility', 'off');

    % Step frequency boundary demarcations
    maxEnvVal = 0.55; minEnvVal = -0.45;
    for k = 1:numTests
        maxEnvVal = max(maxEnvVal, max(d_envs{k}));
        minEnvVal = min(minEnvVal, min(d_envs{k}));
    end
    yTopMax = ceil((maxEnvVal + 0.08) * 10) / 10;
    yTopMin = floor((minEnvVal - 0.05) * 10) / 10;
    ylim(axTop, [yTopMin, yTopMax]);
    xlim(axTop, [0, max(t_s)]);

    for s = 1:nSteps
        xline(axTop, stepTimes(s), ':', 'Color', [0.75, 0.75, 0.75], 'LineWidth', 0.8, 'HandleVisibility', 'off');
        text(axTop, stepTimes(s) + 0.03, yTopMax - 0.04 * (yTopMax - yTopMin), ...
            sprintf('%d Hz', freqs(s)), 'Color', [0.35, 0.35, 0.35], 'FontSize', 7.5, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'HandleVisibility', 'off');
    end

    xlabel(axTop, 'Time (s)', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
    ylabel(axTop, '\Delta A = A_{test} - A_{base} [FS]', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
    title(axTop, '1. Continuous Differential Amplitude: \Delta A(t) = A_{test}(t) - A_{base}(t) [FS]', ...
          'Color', 'k', 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'tex');

    lgdTop = legend(axTop, topLines, legendLabels, 'Location', 'northeast', ...
        'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.75, 0.75, 0.75], 'Interpreter', 'none');
    set(lgdTop, 'FontSize', 8.5);

    % --- BOTTOM SECTION: Synchronized Time-of-Flight Spectrogram Heatmaps ---
    axHeatmaps = gobjects(1, numTests);
    v = 346.0; % Speed of sound in m/s

    leftMargin = 0.07;
    rightMargin = 0.91;
    totalW = rightMargin - leftMargin;
    gapW = 0.02;
    subplotW = (totalW - (numTests - 1) * gapW) / numTests;
    hmBottom = 0.12;
    hmHeight = 0.38;

    for k = 1:numTests
        axPos = [leftMargin + (k - 1) * (subplotW + gapW), hmBottom, subplotW, hmHeight];
        axHm = axes('Parent', fig, 'Position', axPos);
        axHeatmaps(k) = axHm;

        imagesc(axHm, tof_ms, 1:nSteps, stepMatrices{k});
        colormap(axHm, cmPurpleYellow);
        clim(axHm, [-0.20, 0.45]);

        set(axHm, 'YDir', 'normal', ...
                  'Color', 'w', ...
                  'XColor', 'k', 'YColor', 'k', ...
                  'LineWidth', 1.0, 'Box', 'on', ...
                  'GridColor', [0.85, 0.85, 0.85]);

        xlabel(axHm, 'Time-of-Flight \Delta t [ms]', 'Color', 'k', 'FontSize', 10, 'FontWeight', 'bold');

        cleanTitle = legendLabels{k};
        title(axHm, cleanTitle, 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold', 'Interpreter', 'none');

        if k == 1
            set(axHm, 'YTick', 1:nSteps, 'YTickLabel', cellstr(num2str(freqs', '%d Hz')));
            ylabel(axHm, 'Excitation Frequency f [Hz]', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        else
            set(axHm, 'YTick', []);
        end

        % Direct pulse guide (Delta t = 0 ms)
        xline(axHm, 0.0, 'Color', [0.20, 0.75, 0.35], 'LineStyle', '--', 'LineWidth', 1.1);

        % Detect dominant reflection ridge in [3.0, 12.0] ms
        zoneMask = (tof_ms >= 3.0) & (tof_ms <= 12.0);
        meanEchoProfile = mean(stepMatrices{k}(:, zoneMask), 1);
        [~, maxSubIdx] = max(meanEchoProfile);
        zoneTimes = tof_ms(zoneMask);
        peakEchoTime = zoneTimes(maxSubIdx);
        calcDist = v * (peakEchoTime * 0.001) / 2.0;

        % Mark vertical ridge and distance annotation
        xline(axHm, peakEchoTime, 'Color', [1, 1, 1], 'LineWidth', 1.6);
        text(axHm, peakEchoTime, 15.6, sprintf('x \\approx %.2f m\n(\\Delta t = %.1f ms)', calcDist, peakEchoTime), ...
             'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
             'BackgroundColor', [1, 1, 1, 0.85], 'EdgeColor', [0.6, 0.6, 0.6], 'Margin', 2);

        % Far end pipe blockage zone (~14 ms)
        xline(axHm, 14.0, 'Color', [0.35, 0.55, 0.90], 'LineStyle', ':', 'LineWidth', 1.0);
    end

    % Colorbar with explicit scientific units and labels
    cbar = colorbar(axHeatmaps(end), 'Position', [0.925, hmBottom, 0.016, hmHeight]);
    cbar.Color = 'k';
    ylabel(cbar, '\Delta Amplitude [FS]', 'Color', 'k', 'FontSize', 9.5, 'FontWeight', 'bold');

    %% 9. Save and Return Figure
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Acoustic Reflex Map Figure written to:\n  %s\n', outFigPath);
    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open ReflexMap.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);
end

%% Helper: Purple-to-Yellow Colormap
function cm = getPurpleYellowColormap(N)
    if nargin < 1, N = 256; end
    % Key control points: Deep Purple -> Violet -> Magenta -> Coral -> Bright Amber -> Sunny Yellow
    pts = [
        0.00,  0.18, 0.05, 0.35;  % Deep Purple
        0.20,  0.35, 0.08, 0.55;  % Violet / Indigo
        0.40,  0.65, 0.12, 0.55;  % Magenta / Fuchsia
        0.60,  0.88, 0.28, 0.25;  % Coral / Red-Orange
        0.80,  0.98, 0.60, 0.12;  % Bright Amber / Orange
        1.00,  0.98, 0.95, 0.20   % Sunny Yellow
    ];
    x = pts(:, 1);
    r = pts(:, 2);
    g = pts(:, 3);
    b = pts(:, 4);
    xi = linspace(0, 1, N)';
    cm = [interp1(x, r, xi, 'pchip'), interp1(x, g, xi, 'pchip'), interp1(x, b, xi, 'pchip')];
    cm = max(0, min(1, cm));
end

%% Helper: Locate logged raw CSV from path / folder / figure
function [csvPath, sampleName] = resolveAudioDataCsv(p)
    p = strrep(p, '\', '/');

    % 1. Direct logged CSV
    if exist(p, 'file') && endsWith(p, '.csv', 'IgnoreCase', true)
        if ~endsWith(p, 'features_by_frequency.csv', 'IgnoreCase', true) && ~endsWith(p, 'record_profile.csv', 'IgnoreCase', true)
            csvPath = p;
            [~, sampleName] = fileparts(p);
            return;
        else
            [parentDir, ~] = fileparts(p);
            [~, sampleName] = fileparts(parentDir);
            pNorm = regexprep(parentDir, '^analyze/', '');
            [trialDir, ~] = fileparts(pNorm);
            candLogged = fullfile('logged', trialDir, [sampleName, '.csv']);
            candLogged = strrep(candLogged, '\', '/');
            if exist(candLogged, 'file')
                csvPath = candLogged;
                return;
            end
        end
    end

    % 2. Directory path (e.g. analyze/trial/sample or logged/trial/sample)
    if exist(p, 'dir')
        [parentDir, sampleName] = fileparts(p);
        pNorm = regexprep(parentDir, '^analyze/|^logged/', '');
        candLogged = fullfile('logged', pNorm, [sampleName, '.csv']);
        candLogged = strrep(candLogged, '\', '/');
        if exist(candLogged, 'file')
            csvPath = candLogged;
            return;
        end
    end

    % 3. Figure path (e.g. analyze/trial/sample/spectrogram.fig)
    if exist(p, 'file') && endsWith(p, '.fig', 'IgnoreCase', true)
        [parentDir, ~] = fileparts(p);
        [trialParent, sampleName] = fileparts(parentDir);
        trialNorm = regexprep(trialParent, '^analyze/', '');
        candLogged = fullfile('logged', trialNorm, [sampleName, '.csv']);
        candLogged = strrep(candLogged, '\', '/');
        if exist(candLogged, 'file')
            csvPath = candLogged;
            return;
        end
    end

    error('Could not locate raw logged time-series CSV for specified path: "%s"', p);
end
