function [outFigPath, fig] = plot_acoustic_reflex_map(inputPaths, taskName)
%% Acoustic Reflex Map Engine (Option C: 8-Second Timeline + Time-of-Flight Heatmaps)
% Computes differential envelope \Delta E(t) = E_Test(t) - E_Baseline(t)
% across all 16 frequency steps, completely suppressing the direct speaker pulse (down to ~0.01)
% while resolving moving obstacle reflections into synchronized vertical ridges.
%
% Panels:
%   Top Panel: Full 8.0-second continuous differential timeline showing all test conditions.
%   Bottom Panels: Synchronized Time-of-Flight (0-16 ms) heatmaps across all 16 frequencies
%                  with explicit colorbar scale, frequency units (Hz), and time units (ms).
%
% Output:
%   Saves interactive .fig to: analyze/different/{taskName}/{taskName}.fig
%
% Usage:
%   plot_acoustic_reflex_map();                       % Interactive dialog (same as Overlay)
%   plot_acoustic_reflex_map('base.csv, test1.csv, test2.csv', 'task_name');
%   plot_acoustic_reflex_map('2026-11-08-exp-01-sediment-type'); % Auto-detect fallback

    fs = 44100;
    outRoot = fullfile('analyze', 'different');
    if ~exist(outRoot, 'dir'), mkdir(outRoot); end

    %% 1. Interactive Input Dialog if Arguments Omitted or Empty
    if nargin < 1 || isempty(inputPaths)
        prompt = {
            sprintf('Enter relative paths to raw logged CSV files or folders (separated by comma ","): \n(1st path = Reference Baseline, 2nd..N = Test Reflex files)'), ...
            'Reflex Map Task Name (saves to analyze/different/{taskName}):'
        };
        dlgtitle = 'Acoustic Reflex Map Input (Option C)';
        dims = [4, 95; 1, 95];
        if nargin < 2 || isempty(taskName)
            defaultName = sprintf('reflex_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        else
            defaultName = taskName;
        end
        definput = {
            'logged/2026-11-08-baseline/sound_sample_baseline.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_leaf_100_h_front.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_leaf_100_h_middle.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_leaf_100_h_rear.csv', ...
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
        % Auto-discover baseline and test files in trial folder (fallback)
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

        numTests = min(3, length(testFiles));
        testCsvPaths = cell(1, numTests);
        testShortNames = cell(1, numTests);
        for k = 1:numTests
            testCsvPaths{k} = fullfile(trialLoggedDir, testFiles(k).name);
            testShortNames{k} = strrep(testFiles(k).name, '.csv', '');
        end
        defaultTask = sprintf('reflex_%s', trialName);
    else
        % Explicit user paths: 1st is Baseline, 2nd..N are Tests
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

    targetDir = fullfile(outRoot, taskDirName);
    if ~exist(targetDir, 'dir'), mkdir(targetDir); end
    outFigPath = fullfile(targetDir, [taskDirName, '.fig']);

    %% 4. Ingest Data & Compute Analytic Signal Envelopes
    t_base = readtable(baseCsvPath);
    minLen = height(t_base);
    tTables = cell(1, length(testCsvPaths));
    for k = 1:length(testCsvPaths)
        tTables{k} = readtable(testCsvPaths{k});
        minLen = min(minLen, height(tTables{k}));
    end

    t_s = t_base.Time_s(1:minLen);
    env_base = abs(hilbert(t_base.Amp_Avg(1:minLen)));

    numTests = length(tTables);
    d_envs = cell(1, numTests);
    for k = 1:numTests
        d_envs{k} = abs(hilbert(tTables{k}.Amp_Avg(1:minLen))) - env_base;
    end

    %% 5. Build 16-Step Synchronized Time-of-Flight Matrices
    freqs = 300:100:1800;
    nSteps = length(freqs);
    tof_ms = linspace(-1.0, 17.0, round(0.018 * fs));
    stepMatrices = cell(1, numTests);

    for k = 1:numTests
        t_curr = tTables{k};
        mat = zeros(nSteps, length(tof_ms));
        for s = 1:nSteps
            i0_b = find(t_base.Step_ID == s, 1, 'first');
            i0_t = find(t_curr.Step_ID == s, 1, 'first');
            if isempty(i0_b) || isempty(i0_t), continue; end

            w1_b = max(1, i0_b - round(0.005*fs)); w2_b = min(height(t_base), i0_b + round(0.005*fs));
            w1_t = max(1, i0_t - round(0.005*fs)); w2_t = min(height(t_curr), i0_t + round(0.005*fs));

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

    %% 6. Render Publication-Standard 2-Panel Figure
    fig = figure('Name', sprintf('Acoustic Reflex Map: %s', taskDirName), ...
                 'Color', [0.11, 0.12, 0.14], ...
                 'Position', [60, 40, 1320, 860], ...
                 'Visible', 'on');

    colorPalette = [
        1.00, 0.65, 0.35;  % Orange (Condition 1)
        0.75, 0.55, 1.00;  % Purple (Condition 2)
        1.00, 0.48, 0.45;  % Coral Red (Condition 3)
        0.35, 0.85, 0.65;  % Mint Green (Condition 4)
        0.40, 0.75, 1.00;  % Sky Blue (Condition 5)
        0.95, 0.85, 0.30   % Amber (Condition 6)
    ];

    % --- TOP PANEL: Full 8.0-Second Continuous Timeline ---
    axTop = subplot(3, numTests, 1:numTests, 'Parent', fig);
    set(axTop, 'Color', [0.07, 0.08, 0.09], ...
               'XColor', [0.85, 0.88, 0.92], 'YColor', [0.85, 0.88, 0.92], ...
               'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    hold(axTop, 'on'); grid(axTop, 'on'); box(axTop, 'on');

    for k = 1:numTests
        c = colorPalette(mod(k-1, size(colorPalette, 1)) + 1, :);
        cleanLbl = strrep(testShortNames{k}, '_', ' ');
        plot(axTop, t_s, d_envs{k}, 'Color', c, 'LineWidth', 1.2, 'DisplayName', cleanLbl);
    end

    yline(axTop, 0, '--', sprintf('Baseline: %s (\\Delta E = 0)', strrep(baseShortName, '_', ' ')), ...
          'Color', [0.70, 0.72, 0.76], 'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left');
    xlim(axTop, [0, 8.0]); ylim(axTop, [-0.45, 0.55]);
    xlabel(axTop, 'Global Recording Time t [seconds]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
    ylabel(axTop, '\Delta Amplitude [normalized 0-1]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
    title(axTop, '1. Full 8-Second Continuous Differential Envelope (\Delta E(t) = E_{Test}(t) - E_{Base}(t))', ...
          'Color', [0.95, 0.96, 0.98], 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'none');
    legend(axTop, 'Location', 'northeast', 'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], ...
           'Orientation', 'horizontal', 'Interpreter', 'none');

    % Step frequency labels across the 8s sweep
    stepOnsets = [0.0, 0.51, 1.01, 1.52, 2.02, 2.52, 3.02, 3.53, 4.03, 4.53, 5.03, 5.53, 6.04, 6.54, 7.04, 7.54];
    for s = 1:min(length(stepOnsets), nSteps)
        xline(axTop, stepOnsets(s), 'Color', [0.20, 0.65, 0.35], 'LineStyle', ':', 'Alpha', 0.5);
        text(axTop, stepOnsets(s) + 0.02, 0.46, sprintf('%d Hz', freqs(s)), ...
             'Color', [0.45, 0.85, 0.55], 'FontSize', 7.5, 'Rotation', 90, 'VerticalAlignment', 'top');
    end

    % --- BOTTOM PANELS: Synchronized Time-of-Flight Heatmaps ---
    axHeatmaps = gobjects(1, numTests);
    v = 346.0; % Speed of sound in m/s

    for k = 1:numTests
        c = colorPalette(mod(k-1, size(colorPalette, 1)) + 1, :);
        axHm = subplot(3, numTests, numTests + k + [0, numTests], 'Parent', fig);
        axHeatmaps(k) = axHm;

        imagesc(axHm, tof_ms, 1:nSteps, stepMatrices{k});
        colormap(axHm, 'turbo');
        caxis(axHm, [-0.25, 0.45]);

        set(axHm, 'YDir', 'normal', ...
                  'XColor', [0.85, 0.88, 0.92], 'YColor', [0.85, 0.88, 0.92], ...
                  'GridColor', [0.25, 0.28, 0.32]);
        xlabel(axHm, 'Time-of-Flight \Delta t [milliseconds]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10, 'FontWeight', 'bold');

        cleanTitle = strrep(testShortNames{k}, '_', ' ');
        title(axHm, cleanTitle, 'Color', c, 'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');

        if k == 1
            set(axHm, 'YTick', 1:nSteps, 'YTickLabel', cellstr(num2str(freqs', '%d Hz')));
            ylabel(axHm, 'Excitation Frequency f [Hz]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
        else
            set(axHm, 'YTick', []);
        end

        % Direct pulse guide (Delta t = 0 ms)
        xline(axHm, 0.0, 'Color', [0.25, 0.85, 0.40], 'LineStyle', '--', 'LineWidth', 1.2);
        if k == 1
            text(axHm, 0.2, 16.0, 'Direct Pulse (\Delta E \approx 0)', 'Color', [0.35, 0.85, 0.45], 'FontSize', 8, 'FontWeight', 'bold');
        end

        % Detect dominant reflection ridge in [3.0, 12.0] ms
        zoneMask = (tof_ms >= 3.0) & (tof_ms <= 12.0);
        meanEchoProfile = mean(stepMatrices{k}(:, zoneMask), 1);
        [~, maxSubIdx] = max(meanEchoProfile);
        zoneTimes = tof_ms(zoneMask);
        peakEchoTime = zoneTimes(maxSubIdx);
        calcDist = v * (peakEchoTime * 0.001) / 2.0;

        % Mark vertical ridge and position annotation
        xline(axHm, peakEchoTime, 'Color', [1, 1, 1], 'LineWidth', 2.0);
        text(axHm, peakEchoTime, 15.6, sprintf('x \\approx %.2f m\n(\\Delta t = %.1f ms)', calcDist, peakEchoTime), ...
             'Color', [1, 1, 1], 'FontSize', 8.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
             'BackgroundColor', [0.10, 0.11, 0.15]);

        % Far end pipe blockage zone (~14 ms)
        xline(axHm, 14.0, 'Color', [0.30, 0.65, 0.95], 'LineStyle', ':', 'LineWidth', 1.0);
        text(axHm, 14.0, 1.2, 'Pipe End Blocked', 'Color', [0.45, 0.75, 0.98], 'FontSize', 7.5, 'HorizontalAlignment', 'center');
    end

    % Colorbar with explicit scientific units and labels
    cbar = colorbar(axHeatmaps(end), 'Position', [0.92, 0.12, 0.018, 0.52]);
    cbar.Color = [0.85, 0.88, 0.92];
    ylabel(cbar, '\Delta Amplitude / Energy Index [\Delta E]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 9.5, 'FontWeight', 'bold');

    % Coordinate Tracker Status Bar
    sb = uicontrol('Parent', fig, 'Style', 'text', ...
        'String', ' [Option C Diagnostic Tracker] Top: 8s Global Continuous Waveform | Bottom: 16-Step Synchronized Time-of-Flight Heatmaps', ...
        'Units', 'normalized', ...
        'Position', [0.08, 0.012, 0.84, 0.03], ...
        'BackgroundColor', [0.15, 0.16, 0.19], ...
        'ForegroundColor', [0.45, 0.85, 0.95], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMove(src, evt, axTop, axHeatmaps, tof_ms, freqs, sb));

    %% 7. Save and Return Figure
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Acoustic Reflex Map Figure written to:\n  %s\n', outFigPath);
    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open ReflexMap.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);
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
            % User gave features_by_frequency.csv or record_profile.csv -> find logged CSV
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

%% Helper for Coordinate Tracker
function onMouseMove(~, ~, axTop, axHeatmaps, tof_ms, freqs, sb)
    cpTop = get(axTop, 'CurrentPoint');
    xT = cpTop(1, 1); yT = cpTop(1, 2);
    xLT = xlim(axTop); yLT = ylim(axTop);
    if xT >= xLT(1) && xT <= xLT(2) && yT >= yLT(1) && yT <= yLT(2)
        set(sb, 'String', sprintf('  [TOP TIMELINE] Time: %6.3f s | Delta Envelope Amp: %+.3f', xT, yT));
        return;
    end

    for k = 1:length(axHeatmaps)
        axH = axHeatmaps(k);
        cpH = get(axH, 'CurrentPoint');
        xH = cpH(1, 1); yH = cpH(1, 2);
        xLH = xlim(axH); yLH = ylim(axH);
        if xH >= xLH(1) && xH <= xLH(2) && yH >= yLH(1) && yH <= yLH(2)
            stepIdx = max(1, min(length(freqs), round(yH)));
            dist_m = 346.0 * (xH * 0.001) / 2.0;
            set(sb, 'String', sprintf('  [HEATMAP #%d] ToF Delta t: %5.2f ms (x ~ %.2f m) | Frequency: %d Hz (Step %d)', ...
                k, xH, dist_m, freqs(stepIdx), stepIdx));
            return;
        end
    end
end
