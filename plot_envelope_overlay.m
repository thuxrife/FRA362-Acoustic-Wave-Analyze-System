function [outFigPath, fig] = plot_envelope_overlay(inputPaths, domain, taskName)
%% Acoustic Trace Envelope Engine (Envelope Data Mode)
% Plots standalone acoustic envelope curves across multiple conditions on a single graph.
% Routes and saves to:
%   - analyze/envelope/amplitude/{taskName}.fig   (Analytic Envelope E(t) or \Delta E(t))
%   - analyze/envelope/frequency/{taskName}.fig   (Envelope Energy Level dB spectrum)
%   - analyze/envelope/spectrogram/{taskName}.fig (Time-of-Flight Spectrogram Heatmaps)
%
% Aesthetics:
%   Clean IEEE/engineering graph plotter: pure white background ('w'), crisp black axes,
%   material depth-of-color progression (Clay: orange, Leaf: green, Stone: blue, Baseline: black).
%
% Usage:
%   plot_envelope_overlay('base.csv, test1.csv, test2.csv', 'amplitude', 'clay_env');
%   plot_envelope_overlay(); % Opens interactive GUI prompt

    OUTPUT_ROOT = fullfile('analyze', 'envelope');

    %% 1. Interactive Input Dialog if Arguments Omitted
    if nargin < 1 || isempty(inputPaths)
        prompt = {
            sprintf('Enter relative CSV, folder, or .fig paths separated by comma ",":\n(1st path = Reference Baseline, 2nd..N = Test conditions)'), ...
            'Envelope Domain (amplitude, frequency, spectrogram):', ...
            'Envelope Task Name (saves to analyze/envelope/{domain}/{taskName}.fig):'
        };
        dlgtitle = 'Acoustic Envelope Plotter (Single Graph)';
        dims = [4, 95; 1, 95; 1, 95];
        if nargin >= 3 && ~isempty(taskName)
            defaultName = taskName;
        else
            defaultName = sprintf('env_%s', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
        end
        if nargin >= 2 && ~isempty(domain)
            defaultDomain = domain;
        else
            defaultDomain = 'amplitude';
        end
        definput = {
            'logged/2026-11-08-baseline/sound_sample_baseline.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_25_h_middle.csv, logged/2026-11-08-exp-02-sediment-area/sound_sample_clay_50_h_middle.csv, logged/2026-11-08-exp-01-sediment-type/sound_sample_clay_100_h_middle.csv', ...
            defaultDomain, ...
            defaultName
        };
        opts.Resize = 'on';
        answer = inputdlg(prompt, dlgtitle, dims, definput, opts);

        if isempty(answer)
            fprintf('[Envelope Plotter] Cancelled by user.\n');
            outFigPath = '';
            fig = [];
            return;
        end

        inputPaths = answer{1};
        if ~isempty(strtrim(answer{2}))
            domain = lower(strtrim(answer{2}));
        else
            domain = 'amplitude';
        end
        if ~isempty(strtrim(answer{3}))
            taskName = strtrim(answer{3});
        end
    end

    if nargin < 2 || isempty(domain)
        domain = 'amplitude';
    else
        domain = lower(strtrim(domain));
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

    [baseCsvPath, baseShortName] = resolveAudioDataCsv(cleanedPaths{1});
    numTests = length(cleanedPaths) - 1;
    if numTests < 1
        testCsvPaths = {baseCsvPath};
        testShortNames = {baseShortName};
        numTests = 1;
    else
        testCsvPaths = cell(1, numTests);
        testShortNames = cell(1, numTests);
        for k = 1:numTests
            [testCsvPaths{k}, testShortNames{k}] = resolveAudioDataCsv(cleanedPaths{k + 1});
        end
    end

    if nargin < 3 || isempty(taskName)
        taskName = sprintf('env_%s_%s', domain, char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    % If user requested spectrogram, route directly to reflex map spectrogram engine
    if contains(domain, 'spec')
        [outFigPath, fig] = plot_acoustic_reflex_map(cleanedPaths, taskName);
        return;
    end

    targetDir = fullfile(OUTPUT_ROOT, domain);
    if ~exist(targetDir, 'dir'), mkdir(targetDir); end
    outFigPath = fullfile(targetDir, [taskName, '.fig']);

    %% 3. Ingest Data & Extract Envelopes
    t_base = readtable(baseCsvPath);
    minLen = height(t_base);
    tTables = cell(1, numTests);
    for k = 1:numTests
        tTables{k} = readtable(testCsvPaths{k});
        minLen = min(minLen, height(tTables{k}));
    end

    t_s = t_base.Time_s(1:minLen);
    sig_base = t_base.Amp_Avg(1:minLen);
    env_base = abs(hilbert(sig_base));

    envs = cell(1, numTests);
    d_envs = cell(1, numTests);
    for k = 1:numTests
        sig_k = tTables{k}.Amp_Avg(1:minLen);
        envs{k} = abs(hilbert(sig_k));
        d_envs{k} = envs{k} - env_base;
    end

    %% 4. Assign Depth of Color and Line Styles
    allLabels = lower(testShortNames);
    hasClay   = any(contains(allLabels, 'clay'));
    hasLeaf   = any(contains(allLabels, 'leaf'));
    hasStone  = any(contains(allLabels, 'stone') | contains(allLabels, 'sand') | contains(allLabels, 'gravel'));
    isMultiMaterial = ((hasClay + hasLeaf + hasStone) > 1);

    plotColors     = zeros(numTests, 3);
    plotLineStyles = cell(1, numTests);
    plotMarkers    = cell(1, numTests);
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
        isBase = contains(name, 'base') || contains(name, '0%');
        isPos  = contains(name, 'front') || contains(name, 'middle') || contains(name, 'mid') || contains(name, 'rear') || contains(name, 'back');
        if contains(name, '25') || contains(name, '50') || contains(name, '75')
            isPos = false;
        end

        % All Amplitude and Frequency lines strictly use solid lines
        plotLineStyles{k} = '-';

        if isPos
            if contains(name, 'front')
                posStr = 'Front'; plotMarkers{k} = 'o'; posFrac = 0.50;
            elseif contains(name, 'middle') || contains(name, 'mid')
                posStr = 'Middle'; plotMarkers{k} = 's'; posFrac = 0.75;
            else
                posStr = 'Rear'; plotMarkers{k} = '^'; posFrac = 1.00;
            end
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s [%s]', clean, posStr);
        elseif contains(name, '100')
            plotMarkers{k} = '^'; posFrac = 1.00;
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s (100%%)', clean);
        elseif contains(name, '75')
            plotMarkers{k} = 'd'; posFrac = 0.75;
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s (75%%)', clean);
        elseif contains(name, '50')
            plotMarkers{k} = 'o'; posFrac = 0.50;
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s (50%%)', clean);
        elseif contains(name, '25')
            plotMarkers{k} = 's'; posFrac = 0.25;
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s (25%%)', clean);
        elseif isBase
            plotMarkers{k} = 'o'; posFrac = 0.00;
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = sprintf('%s (0%%)', clean);
        else
            plotMarkers{k} = 'o'; posFrac = k / max(1, numTests);
            clean = regexprep(testShortNames{k}, '^sound_sample_', '');
            lbl = clean;
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

    %% 5. Render Standalone Single-Graph Figure
    fig = figure('Name', sprintf('Acoustic Envelope [%s] - %s', upper(domain), taskName), ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Position', [120, 80, 1080, 680], ...
        'Visible', 'on');

    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.08, 0.12, 0.88, 0.80], ...
        'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
        'LineWidth', 1.0, 'Box', 'on', ...
        'GridColor', [0.85, 0.85, 0.85], 'GridAlpha', 0.8);
    grid(ax, 'on'); hold(ax, 'on');

    if contains(domain, 'freq')
        % Frequency Spectrum of Envelope Energy (dB) across 16 steps
        freqs = 300:100:1800;
        nSteps = length(freqs);
        baseEnergy = zeros(1, nSteps);
        testEnergy = zeros(nSteps, numTests);

        for s = 1:nSteps
            idx_b = (t_base.Step_ID == s);
            if any(idx_b)
                baseEnergy(s) = 20 * log10(max(1e-6, rms(t_base.Amp_Avg(idx_b))));
            end
            for k = 1:numTests
                idx_t = (tTables{k}.Step_ID == s);
                if any(idx_t)
                    testEnergy(s, k) = 20 * log10(max(1e-6, rms(tTables{k}.Amp_Avg(idx_t))));
                end
            end
        end

        % Plot Baseline reference curve first
        plot(ax, freqs, baseEnergy, '-k', 'LineWidth', 2.0, ...
            'Marker', 'o', 'MarkerSize', 6.0, 'MarkerFaceColor', [0.2, 0.2, 0.2], ...
            'DisplayName', sprintf('Baseline Reference (%s)', strrep(baseShortName, '_', ' ')));

        plotLines = gobjects(1, numTests);
        for k = 1:numTests
            c = plotColors(k, :);
            ls = plotLineStyles{k};
            mk = plotMarkers{k};
            plotLines(k) = plot(ax, freqs, testEnergy(:, k), ...
                'LineStyle', ls, 'Color', c, 'LineWidth', 1.6, ...
                'Marker', mk, 'MarkerSize', 5.5, 'MarkerFaceColor', c, ...
                'MarkerEdgeColor', 'k', 'DisplayName', legendLabels{k});
        end

        f_cutoff = 0.586 * 346.0 / 0.10;
        xline(ax, f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
            'Color', [0.35, 0.35, 0.35], 'LineWidth', 1.1, 'LabelVerticalAlignment', 'top', ...
            'LabelColor', 'k');

        xlim(ax, [250, 1850]);
        xticks(ax, 300:100:1800);
        xlabel(ax, 'Frequency (Hz)', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        ylabel(ax, 'Energy Level (dBFS)', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        title(ax, sprintf('Envelope Frequency Spectrum: %s', taskName), ...
            'Color', 'k', 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'none');
        legend(ax, 'Location', 'southwest', 'Color', 'w', 'TextColor', 'k', ...
            'EdgeColor', [0.75, 0.75, 0.75], 'Interpreter', 'none');
    else
        % Amplitude Domain: Continuous Differential Envelope \Delta E(t)
        plotLines = gobjects(1, numTests);
        for k = 1:numTests
            c = plotColors(k, :);
            ls = plotLineStyles{k};
            plotLines(k) = plot(ax, t_s, d_envs{k}, 'LineStyle', ls, 'Color', c, ...
                'LineWidth', 1.3, 'DisplayName', legendLabels{k});
        end

        yline(ax, 0, '--', 'Color', [0.35, 0.35, 0.35], 'LineWidth', 1.0, ...
            'DisplayName', 'Baseline Reference (\Delta E = 0)');

        xlim(ax, [0, max(t_s)]);
        xlabel(ax, 'Time (s)', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        ylabel(ax, '\Delta A = A_{test} - A_{base} [FS]', 'Color', 'k', 'FontSize', 10.5, 'FontWeight', 'bold');
        title(ax, sprintf('Differential Amplitude: %s', taskName), ...
            'Color', 'k', 'FontSize', 11.5, 'FontWeight', 'bold', 'Interpreter', 'none');
        legend(ax, 'Location', 'northeast', 'Color', 'w', 'TextColor', 'k', ...
            'EdgeColor', [0.75, 0.75, 0.75], 'Interpreter', 'none');
    end

    pan(fig, 'on');

    %% 6. Save Figure to analyze/envelope/{domain}/{taskName}.fig
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);
    fprintf('\n[SAVED] Envelope Figure written to:\n  %s\n', outFigPath);

    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Envelope.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);
end

%% Helper: Locate logged raw CSV from path / folder / figure
function [csvPath, sampleName] = resolveAudioDataCsv(p)
    p = strrep(p, '\', '/');

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
