function [outFigPath, fig] = plot_blockage_analysis(inputPaths, taskName)
%% Acoustic Blockage Analysis Engine (Per-Frequency Diagnostic Suite)
% Computes quantitative blockage diagnostics across all 16 frequencies (300 to 1800 Hz)
% using Time-Gated Pulse-Echo Reflectometry:
%   1. Direct pulse cancellation: \Delta s(t) = s_test(t) - s_base(t)
%   2. Echo peak extraction in Time-of-Flight window (\Delta t \approx 2x/v)
%   3. Reflection Coefficient: R(f) = Echo_Test(f) / Echo_Ref(f)
%   4. Blockage Area Percentage: \alpha(f) = (2R / (1 + R)) * 100%
%
% Panels:
%   Top Panel: Per-frequency blockage area % (\alpha) across all 16 frequencies with
%              color-coded academic zones (Choking, 1D Plane-Wave, Cavity Resonances).
%   Bottom Panel: Synchronized Time-of-Flight differential reflection envelope (\Delta E(t)).
%
% Output:
%   Saves interactive .fig to: analyze/blockage/{taskName}/{taskName}.fig

    fs = 44100;
    outRoot = fullfile('analyze', 'blockage');
    if ~exist(outRoot, 'dir'), mkdir(outRoot); end

    %% 1. Interactive Input Dialog if Arguments Omitted or Empty
    if nargin < 1 || isempty(inputPaths)
        prompt = {
            sprintf('Enter relative paths to raw logged CSVs or sample folders (separated by comma ","): \n(1st path = Reference Baseline, 2nd..N = Test Blockage files)'), ...
            'Blockage Task Name (saves to analyze/blockage/{taskName}):'
        };
        dlgtitle = 'Acoustic Blockage Analysis Input (Per-Frequency Assessment)';
        dims = [4, 95; 1, 95];
        if nargin < 2 || isempty(taskName)
            defaultName = sprintf('blockage_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        else
            defaultName = taskName;
        end
        definput = {
            'logged/2026-11-08-baseline/sound_sample_baseline.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_75_h_middle.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_clay_100_h_middle.csv', ...
            defaultName
        };
        opts.Resize = 'on';
        answer = inputdlg(prompt, dlgtitle, dims, definput, opts);

        if isempty(answer)
            fprintf('[Blockage] Cancelled by user.\n');
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

    for s = 1:nSteps
        i0_b = find(t_base.Step_ID == s, 1, 'first');
        if isempty(i0_b), continue; end

        w1_b = max(1, i0_b - round(0.005*fs)); w2_b = min(height(t_base), i0_b + round(0.005*fs));
        [~, rel_b] = max(abs(t_base.Amp_Avg(w1_b:w2_b))); pk_b = w1_b + rel_b - 1;
        nP = round(0.001 * fs); nF = round(0.017 * fs);
        s_b = t_base.Amp_Avg(max(1, pk_b - nP) : min(height(t_base), pk_b + nF - 1));
        env_b = abs(hilbert(s_b));

        % Baseline end reference peak
        t_sub_b = ((0:length(s_b)-1) - nP) / fs * 1000;
        ref_val = max(env_b(t_sub_b >= 12.0 & t_sub_b <= 16.0));
        if isempty(ref_val) || ref_val < 0.05
            ref_val = max(env_b) * 0.42;
        end

        for k = 1:numTests
            t_curr = tTables{k};
            i0_c = find(t_curr.Step_ID == s, 1, 'first');
            if isempty(i0_c), continue; end

            w1_c = max(1, i0_c - round(0.005*fs)); w2_c = min(height(t_curr), i0_c + round(0.005*fs));
            [~, rel_c] = max(abs(t_curr.Amp_Avg(w1_c:w2_c))); pk_c = w1_c + rel_c - 1;
            s_c = t_curr.Amp_Avg(max(1, pk_c - nP) : min(height(t_curr), pk_c + nF - 1));

            L_seg = min([length(s_b), length(s_c), length(tof_ms)]);
            row_diff = abs(hilbert(s_c(1:L_seg))) - abs(hilbert(s_b(1:L_seg)));
            echoEnvs{k}(s, 1:L_seg) = row_diff;

            t_sub = tof_ms(1:L_seg);
            mask_echo = (t_sub >= 3.0) & (t_sub <= 11.5);
            echo = max(row_diff(mask_echo));

            r = min(1.0, max(0.0, echo / ref_val));
            rMat(s, k) = r;
            alphaMat(s, k) = (2 * r / (1 + r)) * 100;
        end
    end

    %% 5. Render Upgraded 2-Panel Diagnostic Figure
    fig = figure('Name', sprintf('Per-Frequency Acoustic Blockage Suite: %s', taskDirName), ...
                 'Color', [0.11, 0.12, 0.14], ...
                 'Position', [60, 40, 1260, 840], ...
                 'Visible', 'on');

    colorPalette = [
        1.00, 0.62, 0.30;  % Bright Orange (Condition 1)
        0.30, 0.78, 0.95;  % Cyan (Condition 2)
        0.80, 0.55, 1.00;  % Purple (Condition 3)
        0.40, 0.88, 0.60;  % Mint Green (Condition 4)
        1.00, 0.45, 0.45;  % Coral Red (Condition 5)
    ];

    legendLabels = cellfun(@(s) strrep(s, '_', ' '), testShortNames, 'UniformOutput', false);

    % --- TOP PANEL: Per-Frequency Blockage % (\alpha) with Academic Zones ---
    axTop = subplot(2, 1, 1, 'Parent', fig);
    set(axTop, 'Color', [0.07, 0.08, 0.09], ...
               'XColor', [0.85, 0.88, 0.92], 'YColor', [0.85, 0.88, 0.92], ...
               'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    hold(axTop, 'on'); grid(axTop, 'on'); box(axTop, 'on');

    % Academic Zone Backgrounds
    patch(axTop, [240, 550, 550, 240], [0, 0, 115, 115], [0.85, 0.35, 0.35], 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    patch(axTop, [550, 1150, 1150, 550], [0, 0, 115, 115], [0.35, 0.85, 0.45], 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    patch(axTop, [1150, 1860, 1860, 1150], [0, 0, 115, 115], [0.35, 0.55, 0.95], 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');

    % Target Reference Guidelines
    yline(axTop, 100.0, ':', 'Solid Wall Limit (100%)', ...
          'Color', [0.65, 0.68, 0.72], 'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    yline(axTop, 75.0, '--', '75% Reference', 'Color', [1.0, 0.85, 0.30], 'LineWidth', 1.2, 'Alpha', 0.8, 'HandleVisibility', 'off');
    yline(axTop, 50.0, ':', '50% Reference', 'Color', [0.55, 0.75, 0.85], 'LineWidth', 1.0, 'Alpha', 0.7, 'HandleVisibility', 'off');

    % Bar Plots for each Condition
    b = bar(axTop, freqs, alphaMat, 0.80, 'grouped');
    for k = 1:numTests
        c = colorPalette(mod(k-1, size(colorPalette, 1)) + 1, :);
        b(k).FaceColor = c;
        b(k).EdgeColor = 'none';
        b(k).DisplayName = legendLabels{k};
    end

    % Annotate individual values on primary bars
    for s = 1:nSteps
        val = alphaMat(s, 1);
        c = colorPalette(1, :);
        if freqs(s) == 800
            c = [0.35, 1.0, 0.55]; % highlight 800 Hz
        end
        text(axTop, freqs(s), val + 2.8, sprintf('%.1f%%', val), ...
             'Color', c, 'FontSize', 8.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end

    % Academic Zone Header Labels
    text(axTop, 400, 108, {'ZONE 1: Acoustic Choking', '(\lambda > 58 cm: slit choked)'}, ...
         'Color', [1.0, 0.60, 0.60], 'FontSize', 9.0, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(axTop, 850, 108, {'ZONE 2: 1D Plane-Wave Window', '(True Cross-Sectional Area)'}, ...
         'Color', [0.45, 0.95, 0.65], 'FontSize', 9.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(axTop, 1500, 108, {'ZONE 3: High-Frequency Dispersions', '(Cavity Resonances & Cross-Modes)'}, ...
         'Color', [0.60, 0.78, 1.0], 'FontSize', 9.0, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    xticks(axTop, freqs);
    xlim(axTop, [240, 1860]);
    ylim(axTop, [0, 116]);
    ylabel(axTop, 'Calculated Blockage Area \alpha [%]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
    title(axTop, sprintf('1. Per-Frequency Blockage Assessment Across Academic Zones (Baseline: %s)', strrep(baseShortName, '_', ' ')), ...
          'Color', [0.95, 0.96, 0.98], 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'none');
    legend(axTop, 'Location', 'southwest', 'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], 'Interpreter', 'none');

    % --- BOTTOM PANEL: Time-of-Flight Differential Reflection Envelope (\Delta E(t)) ---
    axBottom = subplot(2, 1, 2, 'Parent', fig);
    set(axBottom, 'Color', [0.07, 0.08, 0.09], ...
                  'XColor', [0.85, 0.88, 0.92], 'YColor', [0.85, 0.88, 0.92], ...
                  'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    hold(axBottom, 'on'); grid(axBottom, 'on'); box(axBottom, 'on');

    v = 346.0;
    for k = 1:numTests
        c = colorPalette(mod(k-1, size(colorPalette, 1)) + 1, :);
        % Mean reflection envelope across the Plane-Wave Window (Zone 2: 700 to 1000 Hz)
        zone2_mask = (freqs >= 700) & (freqs <= 1000);
        meanEnvZone2 = mean(echoEnvs{k}(zone2_mask, :), 1);
        plot(axBottom, tof_ms, meanEnvZone2, 'Color', c, 'LineWidth', 1.8, ...
             'DisplayName', sprintf('%s (Zone 2 Average)', legendLabels{k}));

        % Find peak in obstacle zone (3 to 12 ms)
        maskObstacle = (tof_ms >= 3.0) & (tof_ms <= 12.0);
        [maxVal, idxSub] = max(meanEnvZone2(maskObstacle));
        tZone = tof_ms(maskObstacle);
        tPeak = tZone(idxSub);
        distEst = v * (tPeak * 0.001) / 2.0;

        xline(axBottom, tPeak, 'Color', c, 'LineStyle', '--', 'LineWidth', 1.2, 'HandleVisibility', 'off');
        text(axBottom, tPeak, maxVal + 0.03, sprintf('%s\nx \\approx %.2f m\n(\\Delta t = %.1f ms)', legendLabels{k}, distEst, tPeak), ...
             'Color', c, 'FontSize', 8.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
             'BackgroundColor', [0.10, 0.11, 0.15]);
    end

    xline(axBottom, 0.0, 'Color', [0.25, 0.85, 0.40], 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');
    text(axBottom, 0.2, 0.35, 'Direct Pulse (\Delta E \approx 0)', 'Color', [0.35, 0.85, 0.45], 'FontSize', 8.5, 'FontWeight', 'bold');

    xlim(axBottom, [-0.5, 16.5]);
    ylim(axBottom, [-0.15, 0.55]);
    xlabel(axBottom, 'Time-of-Flight \Delta t [milliseconds]', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
    ylabel(axBottom, 'Reflected Envelope \Delta E(t)', 'Color', [0.85, 0.88, 0.92], 'FontSize', 10.5, 'FontWeight', 'bold');
    title(axBottom, '2. Time-Gated Obstacle Echoes in the 1D Plane-Wave Window (Direct Pulse Cancelled)', ...
          'Color', [0.95, 0.96, 0.98], 'FontSize', 11.0, 'FontWeight', 'bold');
    legend(axBottom, 'Location', 'northeast', 'TextColor', [0.92, 0.94, 0.96], 'Color', [0.15, 0.16, 0.19], 'Interpreter', 'none');

    % Coordinate Tracker Status Bar
    sb = uicontrol('Parent', fig, 'Style', 'text', ...
        'String', ' [Blockage Diagnostic Suite] Top: Per-Frequency Blockage % across Academic Zones | Bottom: Time-Gated Echo Envelopes', ...
        'Units', 'normalized', ...
        'Position', [0.08, 0.012, 0.84, 0.03], ...
        'BackgroundColor', [0.15, 0.16, 0.19], ...
        'ForegroundColor', [0.45, 0.85, 0.95], ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    set(fig, 'WindowButtonMotionFcn', @(src, evt) onMouseMove(src, evt, axTop, axBottom, sb));

    %% 6. Save and Return Figure
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Upgraded Blockage Analysis Figure written to:\n  %s\n', outFigPath);
    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Blockage.fig]</a>', strrep(outFigPath, '\', '/'));
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

%% Helper for Status Bar Coordinate Tracker
function onMouseMove(~, ~, ax1, ax2, sb)
    cp1 = get(ax1, 'CurrentPoint');
    x1 = cp1(1, 1); y1 = cp1(1, 2);
    xL1 = xlim(ax1); yL1 = ylim(ax1);
    if x1 >= xL1(1) && x1 <= xL1(2) && y1 >= yL1(1) && y1 <= yL1(2)
        zoneStr = 'Zone 2: 1D Plane-Wave Window';
        if x1 < 550, zoneStr = 'Zone 1: Acoustic Choking'; end
        if x1 > 1150, zoneStr = 'Zone 3: Cavity Resonance & Dispersion'; end
        set(sb, 'String', sprintf('  [TOP PANEL] Freq: %6.0f Hz | Blockage Area: %.1f %% | %s', x1, y1, zoneStr));
        return;
    end

    cp2 = get(ax2, 'CurrentPoint');
    x2 = cp2(1, 1); y2 = cp2(1, 2);
    xL2 = xlim(ax2); yL2 = ylim(ax2);
    if x2 >= xL2(1) && x2 <= xL2(2) && y2 >= yL2(1) && y2 <= yL2(2)
        distEst = 346.0 * (x2 * 0.001) / 2.0;
        set(sb, 'String', sprintf('  [BOTTOM PANEL] ToF Delta t: %5.2f ms (x ~ %.2f m) | Reflected Echo Envelope: %+.3f', x2, distEst, y2));
    end
end
