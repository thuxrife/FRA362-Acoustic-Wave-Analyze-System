function [outFigPath, fig] = plot_blockage_analysis(inputPaths, taskName)
%% Acoustic Blockage Analysis Engine (Level 4 & 5: Reflection Coefficient & Area %)
% Ingests raw logged CSV files for Baseline (0%) and Test conditions (e.g. 25%, 50%, 75%, 100%).
%
% Panels:
%   Top Panel:    Per-Frequency Physical Blockage Area Assessment (%) across all 16 frequency steps (300-1800 Hz).
%   Bottom Panel: Interactive Time-Gated Differential Reflected Waveform Envelopes with
%                 Frequency Step Selector dropdown (Average Zone 2, Full Average, Step 1-16),
%                 Time-of-Flight horizontal scrolling slider, and Gate Width selector.
%
% Visual Style:
%   Clean IEEE/engineering graph plotter: pure white background ('w'), crisp black axes,
%   material depth-of-color progression (Clay: orange, Leaf: green, Stone: blue, Baseline: black).
%
% Output:
%   Saves interactive .fig to: analyze/blockage/{taskName}/{taskName}.fig
%
% Usage:
%   plot_blockage_analysis(); % Interactive dialog
%   plot_blockage_analysis('base.csv, test1.csv, test2.csv', 'clay_blockage');

    fs = 44100;
    outRoot = fullfile('analyze', 'blockage');
    if ~exist(outRoot, 'dir'), mkdir(outRoot); end

    %% 1. Interactive Input Dialog if Arguments Omitted or Empty
    if nargin < 1 || isempty(inputPaths)
        prompt = {
            sprintf('Enter relative paths to raw logged CSV files or folders (separated by comma ","): \n(1st path = Reference Baseline, 2nd..N = Test Blockage files)'), ...
            'Blockage Analysis Task Name (saves to analyze/blockage/{taskName}):'
        };
        dlgtitle = 'Acoustic Blockage Analysis Input (Level 4 & 5)';
        dims = [4, 95; 1, 95];
        if nargin < 2 || isempty(taskName)
            defaultName = sprintf('blockage_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
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
            fprintf('[Blockage Analysis] Cancelled by user.\n');
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

    if nargin < 2 || isempty(taskName)
        taskDirName = sprintf('blockage_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    else
        taskDirName = taskName;
    end

    targetDir = fullfile(outRoot, taskDirName);
    if ~exist(targetDir, 'dir'), mkdir(targetDir); end
    outFigPath = fullfile(targetDir, [taskDirName, '.fig']);

    %% 4. Ingest Data & Compute Per-Frequency Time-Gated Metrics
    t_base = readtable(baseCsvPath);
    minLen = height(t_base);
    tTables = cell(1, numTests);
    for k = 1:numTests
        tTables{k} = readtable(testCsvPaths{k});
        minLen = min(minLen, height(tTables{k}));
    end

    freqs = 300:100:1800;
    nSteps = length(freqs);
    tof_ms = linspace(-1.0, 17.0, round(0.018 * fs));

    alphaMat = zeros(nSteps, numTests);
    rMat     = zeros(nSteps, numTests);
    echoEnvs = cell(1, numTests);
    for k = 1:numTests
        echoEnvs{k} = zeros(nSteps, length(tof_ms));
    end

    rawEchoMat = zeros(nSteps, numTests);
    nP = round(0.001 * fs); nF = round(0.017 * fs);

    % Pass 1: Extract direct pulse and differential reflection envelopes
    for s = 1:nSteps
        i0_b = find(t_base.Step_ID == s, 1, 'first');
        if isempty(i0_b), continue; end

        w1_b = max(1, i0_b - round(0.005 * fs)); w2_b = min(height(t_base), i0_b + round(0.005 * fs));
        [~, rel_b] = max(abs(t_base.Amp_Avg(w1_b:w2_b))); pk_b = w1_b + rel_b - 1;
        s_b = t_base.Amp_Avg(max(1, pk_b - nP) : min(height(t_base), pk_b + nF - 1));

        for k = 1:numTests
            t_curr = tTables{k};
            i0_c = find(t_curr.Step_ID == s, 1, 'first');
            if isempty(i0_c), continue; end

            w1_c = max(1, i0_c - round(0.005 * fs)); w2_c = min(height(t_curr), i0_c + round(0.005 * fs));
            [~, rel_c] = max(abs(t_curr.Amp_Avg(w1_c:w2_c))); pk_c = w1_c + rel_c - 1;
            s_c = t_curr.Amp_Avg(max(1, pk_c - nP) : min(height(t_curr), pk_c + nF - 1));

            L_seg = min([length(s_b), length(s_c), length(tof_ms)]);
            row_diff = abs(hilbert(s_c(1:L_seg))) - abs(hilbert(s_b(1:L_seg)));
            echoEnvs{k}(s, 1:L_seg) = row_diff;

            t_sub = tof_ms(1:L_seg);
            mask_echo = (t_sub >= 3.0) & (t_sub <= 11.5);
            rawEchoMat(s, k) = max(0.0, max(row_diff(mask_echo)));
        end
    end

    % Pass 2: Reflection coefficient R and Blockage Area Percentage alpha
    idx100 = find(contains(testShortNames, '100'), 1);

    for s = 1:nSteps
        if ~isempty(idx100)
            ref_val = max(0.05, rawEchoMat(s, idx100));
        else
            i0_b = find(t_base.Step_ID == s, 1, 'first');
            w1_b = max(1, i0_b - round(0.005 * fs)); w2_b = min(height(t_base), i0_b + round(0.005 * fs));
            [~, rel_b] = max(abs(t_base.Amp_Avg(w1_b:w2_b))); pk_b = w1_b + rel_b - 1;
            s_b = t_base.Amp_Avg(max(1, pk_b - nP) : min(height(t_base), pk_b + nF - 1));
            env_b = abs(hilbert(s_b));
            t_sub_b = ((0:length(s_b)-1) - nP) / fs * 1000;
            ref_end = max(env_b(t_sub_b >= 12.0 & t_sub_b <= 16.0));
            if isempty(ref_end) || ref_end < 0.05
                ref_end = max(env_b) * 0.42;
            end
            ref_val = ref_end * 1.35;
        end

        for k = 1:numTests
            echo = rawEchoMat(s, k);
            r = min(1.0, max(0.0, echo / ref_val));
            rMat(s, k) = r;
            alphaMat(s, k) = (2 * r / (1 + r)) * 100;
        end
    end

    %% 5. Assign Depth of Color and Line Styles
    legendLabels = cell(1, numTests);
    for k = 1:numTests
        lbl = strrep(testShortNames{k}, '_', ' ');
        if contains(lower(testShortNames{k}), 'baseline') && ~contains(lower(testShortNames{k}), '0%')
            lbl = sprintf('%s (0%%)', lbl);
        end
        legendLabels{k} = lbl;
    end

    plotColors     = zeros(numTests, 3);
    plotLineStyles = cell(1, numTests);
    plotMarkers    = cell(1, numTests);

    for k = 1:numTests
        name = lower(testShortNames{k});
        if contains(name, '100')
            areaFrac = 1.00;
            plotLineStyles{k} = '-';
            plotMarkers{k} = '^';
        elseif contains(name, '75')
            areaFrac = 0.75;
            plotLineStyles{k} = '--';
            plotMarkers{k} = 'd';
        elseif contains(name, '50')
            areaFrac = 0.50;
            plotLineStyles{k} = '-';
            plotMarkers{k} = 'o';
        elseif contains(name, '25')
            areaFrac = 0.25;
            plotLineStyles{k} = '--';
            plotMarkers{k} = 's';
        elseif contains(name, 'baseline') || contains(name, '0%') || contains(name, '_base')
            areaFrac = 0.00;
            plotLineStyles{k} = '-';
            plotMarkers{k} = 'o';
        else
            areaFrac = k / numTests;
            plotLineStyles{k} = '-';
            plotMarkers{k} = 'o';
        end

        % Material Family Depth of Color
        if areaFrac == 0.00
            plotColors(k, :) = [0.15, 0.15, 0.15]; % Baseline Black
        elseif contains(name, 'leaf')
            cDark   = [0.04, 0.32, 0.10];
            cBright = [0.25, 0.90, 0.32];
            plotColors(k, :) = cDark + areaFrac * (cBright - cDark);
        elseif contains(name, 'stone') || contains(name, 'sand') || contains(name, 'gravel')
            cDark   = [0.05, 0.18, 0.50];
            cBright = [0.20, 0.80, 1.00];
            plotColors(k, :) = cDark + areaFrac * (cBright - cDark);
        elseif contains(name, 'clay')
            cDark   = [0.55, 0.20, 0.02];
            cBright = [1.00, 0.75, 0.15];
            plotColors(k, :) = cDark + areaFrac * (cBright - cDark);
        else
            plotColors(k, :) = [0.20, 0.40, 0.80];
        end
    end

    %% 6. Render IEEE Engineering Plotter with Interactive Step Controls
    fig = figure('Name', sprintf('Acoustic Blockage Analysis: %s', taskDirName), ...
                 'NumberTitle', 'off', ...
                 'Color', 'w', ...
                 'Position', [80, 50, 1150, 840], ...
                 'Visible', 'on');

    % --- TOP PANEL: Blockage Area vs Frequency ---
    axTop = subplot('Position', [0.08, 0.56, 0.88, 0.38], 'Parent', fig);
    set(axTop, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
               'LineWidth', 1.0, 'FontSize', 10, ...
               'GridColor', [0.82, 0.82, 0.82], 'GridAlpha', 0.8, 'GridLineStyle', ':');
    hold(axTop, 'on'); grid(axTop, 'on'); box(axTop, 'on');

    for k = 1:numTests
        plot(axTop, freqs, alphaMat(:, k), ...
             'LineStyle', plotLineStyles{k}, ...
             'LineWidth', 1.8, ...
             'Color', plotColors(k, :), ...
             'Marker', plotMarkers{k}, ...
             'MarkerSize', 6.0, ...
             'MarkerFaceColor', plotColors(k, :), ...
             'MarkerEdgeColor', 'k', ...
             'DisplayName', legendLabels{k});
    end

    yline(axTop, 100.0, '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    xticks(axTop, 300:100:1800);
    xlim(axTop, [min(freqs), max(freqs)]);
    ylim(axTop, [0, 105]);
    xlabel(axTop, 'Frequency (Hz)', 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', 'k');
    ylabel(axTop, 'Blockage Area \alpha (%)', 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', 'k');
    title(axTop, sprintf('Per-Frequency Blockage Area Assessment (Baseline: %s)', strrep(baseShortName, '_', ' ')), ...
          'FontSize', 11.5, 'FontWeight', 'bold', 'Color', 'k', 'Interpreter', 'none');
    legend(axTop, 'Location', 'southwest', 'Color', 'w', 'EdgeColor', [0.7, 0.7, 0.7], 'FontSize', 9);

    % --- BOTTOM PANEL: Time-of-Flight Reflected Envelopes ---
    axBottom = subplot('Position', [0.08, 0.14, 0.88, 0.34], 'Parent', fig);
    set(axBottom, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
                  'LineWidth', 1.0, 'FontSize', 10, ...
                  'GridColor', [0.82, 0.82, 0.82], 'GridAlpha', 0.8, 'GridLineStyle', ':');
    hold(axBottom, 'on'); grid(axBottom, 'on'); box(axBottom, 'on');

    zone2_mask = (freqs >= 700) & (freqs <= 1000);
    bottomLines = gobjects(1, numTests);

    for k = 1:numTests
        meanEnvZone2 = mean(echoEnvs{k}(zone2_mask, :), 1);
        bottomLines(k) = plot(axBottom, tof_ms, meanEnvZone2, ...
             'LineStyle', plotLineStyles{k}, ...
             'LineWidth', 1.8, ...
             'Color', plotColors(k, :), ...
             'DisplayName', legendLabels{k});
    end

    yline(axBottom, 0.0, '-k', 'LineWidth', 0.6, 'HandleVisibility', 'off');
    xlim(axBottom, [min(tof_ms), max(tof_ms)]);
    ylim(axBottom, 'auto');
    yLimits = ylim(axBottom);
    ylim(axBottom, [yLimits(1) - 0.02, yLimits(2) + 0.04]);

    xlabel(axBottom, 'Time-of-Flight \Delta t (ms)', 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', 'k');
    ylabel(axBottom, 'Reflected Envelope \Delta E(t)', 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', 'k');
    title(axBottom, 'Time-Gated Differential Reflected Waveform: Average (Zone 2: 700-1000 Hz)', ...
          'FontSize', 11.5, 'FontWeight', 'bold', 'Color', 'k');
    legend(axBottom, 'Location', 'northeast', 'Color', 'w', 'EdgeColor', [0.7, 0.7, 0.7], 'FontSize', 9);

    % --- INTERACTIVE STEP SELECTOR & SCROLLING CONTROLS ---
    stepDropdownItems = cell(1, nSteps + 2);
    stepDropdownItems{1} = 'Average: Optimal Sensitivity Zone (700-1000 Hz)';
    stepDropdownItems{2} = 'Average: Full Band (300-1800 Hz)';
    for s = 1:nSteps
        stepDropdownItems{s + 2} = sprintf('Step %d (%d Hz)', s, freqs(s));
    end

    popStep = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.08, 0.045, 0.32, 0.038], ...
        'String', stepDropdownItems, 'Value', 1, ...
        'BackgroundColor', 'w', 'ForegroundColor', 'k', ...
        'FontSize', 9, ...
        'Tooltip', 'Select frequency step to inspect in bottom panel');

    minTof = min(tof_ms);
    maxTof = max(tof_ms);

    sldTime = uicontrol('Parent', fig, 'Style', 'slider', ...
        'Units', 'normalized', ...
        'Position', [0.43, 0.045, 0.30, 0.035], ...
        'Min', minTof, 'Max', maxTof - 2.0, 'Value', minTof, ...
        'SliderStep', [0.02, 0.15], ...
        'BackgroundColor', [0.94, 0.94, 0.94], ...
        'Tooltip', 'Scroll Time-of-Flight window horizontally');

    widthLabels = {
        'Full ToF Window (-1 to 17 ms)', ...
        'Obstacle Zone (2 to 12 ms)', ...
        'Direct Pulse Zone (-1 to 4 ms)', ...
        'Pipe End Zone (10 to 17 ms)'
    };
    widthRanges = [
        -1.0, 17.0;
         2.0, 12.0;
        -1.0,  4.0;
        10.0, 17.0
    ];

    popWidth = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.75, 0.045, 0.21, 0.038], ...
        'String', widthLabels, 'Value', 1, ...
        'BackgroundColor', 'w', 'ForegroundColor', 'k', ...
        'FontSize', 9, ...
        'Tooltip', 'Select time-of-flight zoom window');

    %% 7. Store State & Wire Persistent Interactive Callbacks
    figData.tof_ms       = tof_ms;
    figData.echoEnvs     = echoEnvs;
    figData.freqs        = freqs;
    figData.nSteps       = nSteps;
    figData.numTests     = numTests;
    figData.zone2_mask   = zone2_mask;
    figData.axBottom     = axBottom;
    figData.bottomLines  = bottomLines;
    figData.popStep      = popStep;
    figData.sldTime      = sldTime;
    figData.popWidth     = popWidth;
    figData.widthRanges  = widthRanges;
    figData.stepDropdownItems = stepDropdownItems;
    set(fig, 'UserData', figData);

    set(popStep, 'Callback', @(src, evt) onStepChanged(fig));
    set(sldTime, 'Callback', @(src, evt) onSliderChanged(fig));
    set(popWidth, 'Callback', @(src, evt) onWidthChanged(fig));

    % Enable standard MATLAB Pan and Zoom
    pan(fig, 'on');

    %% 8. Save and Return Figure
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Upgraded Blockage Analysis Figure written to:\n  %s\n', outFigPath);
    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Blockage.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);
end

%% --- Interactive Callback Functions ---

function onStepChanged(fig)
    data = get(fig, 'UserData');
    if isempty(data), return; end

    val = get(data.popStep, 'Value');
    nTests = data.numTests;

    if val == 1
        % Zone 2 Average (700-1000 Hz)
        for k = 1:nTests
            env = mean(data.echoEnvs{k}(data.zone2_mask, :), 1);
            set(data.bottomLines(k), 'YData', env);
        end
        titleStr = 'Time-Gated Differential Reflected Waveform: Average (Zone 2: 700-1000 Hz)';
    elseif val == 2
        % Full Band Average (300-1800 Hz)
        for k = 1:nTests
            env = mean(data.echoEnvs{k}, 1);
            set(data.bottomLines(k), 'YData', env);
        end
        titleStr = 'Time-Gated Differential Reflected Waveform: Average (Full Band: 300-1800 Hz)';
    else
        % Individual Step s
        s = val - 2;
        freqHz = data.freqs(s);
        for k = 1:nTests
            env = data.echoEnvs{k}(s, :);
            set(data.bottomLines(k), 'YData', env);
        end
        titleStr = sprintf('Time-Gated Differential Reflected Waveform: Step %d (%d Hz)', s, freqHz);
    end

    title(data.axBottom, titleStr, 'FontSize', 11.5, 'FontWeight', 'bold', 'Color', 'k');
    ylim(data.axBottom, 'auto');
    yLimits = ylim(data.axBottom);
    ylim(data.axBottom, [yLimits(1) - 0.02, yLimits(2) + 0.04]);
end

function onSliderChanged(fig)
    data = get(fig, 'UserData');
    if isempty(data), return; end

    tStart = get(data.sldTime, 'Value');
    curXLim = xlim(data.axBottom);
    curWidth = curXLim(2) - curXLim(1);
    xlim(data.axBottom, [tStart, tStart + curWidth]);
end

function onWidthChanged(fig)
    data = get(fig, 'UserData');
    if isempty(data), return; end

    wIdx = get(data.popWidth, 'Value');
    range = data.widthRanges(wIdx, :);
    xlim(data.axBottom, range);
    set(data.sldTime, 'Value', range(1));
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
