function [outFigPath, fig] = plot_delta_comparison(mode, taskName)
%% Unified Acoustic Delta Comparison Engine
% Ingests discrete per-frequency CSV features (features_by_frequency.csv)
% and plots 2-panel comparative diagnostics:
%   1. Absolute Step Peak Amplitude
%   2. Differential Energy (Delta dB = Test - Baseline) with -3 dB threshold
%
% Modes:
%   1: 'cross_day' - Compares 100% Sand Back across Today (Nov 08) vs Yesterday (Nov 07)
%   2: 'position'  - Compares Middle vs Back blockage within the same trial
%   3: 'custom'    - Opens file dialog to pick any Baseline and Test CSVs
%
% Usage:
%   plot_delta_comparison();                  % Opens interactive mode selection dialog
%   plot_delta_comparison('cross_day');       % Directly runs cross-environment mode
%   plot_delta_comparison('position');        % Runs position progression mode

    outRoot = fullfile('analyze', 'different');
    if ~exist(outRoot, 'dir'), mkdir(outRoot); end

    %% 1. Interactive Selection if Mode Omitted
    if nargin < 1 || isempty(mode)
        choices = {
            '1. Cross-Environment Comparison (Today vs Yesterday 100% Sand Back)', ...
            '2. Position Progression (Baseline vs Middle vs Back on Nov 07)', ...
            '3. Custom CSV Picker (Select Baseline and Test CSVs manually)'
        };
        [sel, ok] = listdlg('PromptString', 'Select Delta Comparison Mode:', ...
                            'SelectionMode', 'single', ...
                            'ListString', choices, ...
                            'ListSize', [450, 100], ...
                            'Name', 'Acoustic Delta Analyzer');
        if ~ok || isempty(sel)
            fprintf('[Delta Comparison] Cancelled by user.\n');
            outFigPath = '';
            return;
        end
        switch sel
            case 1, mode = 'cross_day';
            case 2, mode = 'position';
            case 3, mode = 'custom';
        end
    end

    if nargin < 2 || isempty(taskName)
        taskName = sprintf('delta_%s_%s', mode, char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    end

    %% 2. Load Data Based on Mode
    switch lower(mode)
        case {'cross_day', 'crossday', '1'}
            f_n08_sand = fullfile('analyze', '2026-11-08-sound-sample', 'sound_sample_2_sand_back', 'features_by_frequency.csv');
            f_n08_base = fullfile('analyze', '2026-11-08-sound-sample', 'sound_sample_0_baseline',    'features_by_frequency.csv');
            f_n07_sand = fullfile('analyze', '2026-11-07-sound-sample', 'sound_sample_2_sand_back', 'features_by_frequency.csv');
            f_n07_base = fullfile('analyze', '2026-11-07-sound-sample', 'sound_sample_0_base_line',  'features_by_frequency.csv');

            t_n08_s = readtable(f_n08_sand);
            t_n08_b = readtable(f_n08_base);
            t_n07_s = readtable(f_n07_sand);
            t_n07_b = readtable(f_n07_base);

            freq    = t_n08_b.Freq_Hz;
            d_case1 = t_n08_s.Energy_dB - t_n08_b.Energy_dB;
            d_case2 = t_n07_s.Energy_dB - t_n07_b.Energy_dB;

            subTaskDir = fullfile(outRoot, 'cross_day_sand_back');
            figTitle1 = '1. Cross-Environment Blockage Effect (\Delta dB = Sand Back - Local Baseline)';
            label1 = 'Today (2026-11-08, Dome Room, 10 Reps)';
            label2 = 'Yesterday (2026-11-07, Original Room, 5 Reps)';
            deltaMat = [d_case1, d_case2];
            peakMat  = [t_n08_s.Step_Peak_Amp, t_n07_s.Step_Peak_Amp];

        case {'position', '2'}
            baseDir = fullfile('analyze', '2026-11-07-sound-sample');
            f_base = fullfile(baseDir, 'sound_sample_0_base_line', 'features_by_frequency.csv');
            f_mid  = fullfile(baseDir, 'sound_sample_1_sand_middle', 'features_by_frequency.csv');
            f_back = fullfile(baseDir, 'sound_sample_1_sand_back',   'features_by_frequency.csv');

            t_base = readtable(f_base);
            t_mid  = readtable(f_mid);
            t_back = readtable(f_back);

            freq    = t_base.Freq_Hz;
            d_mid   = t_mid.Energy_dB - t_base.Energy_dB;
            d_back  = t_back.Energy_dB - t_base.Energy_dB;

            subTaskDir = fullfile(outRoot, 'position_progression');
            figTitle1 = '1. Position Progression (\Delta dB = Test - Baseline)';
            label1 = 'Sand Middle (1.0 m)';
            label2 = 'Sand Back (1.8 m)';
            deltaMat = [d_mid, d_back];
            peakMat  = [t_mid.Step_Peak_Amp, t_back.Step_Peak_Amp];

        otherwise
            % Custom mode
            [bFile, bPath] = uigetfile('*.csv', 'Select Reference Baseline features_by_frequency.csv');
            if isequal(bFile, 0), outFigPath = ''; return; end
            [tFile, tPath] = uigetfile('*.csv', 'Select Test Blockage features_by_frequency.csv');
            if isequal(tFile, 0), outFigPath = ''; return; end

            t_base = readtable(fullfile(bPath, bFile));
            t_test = readtable(fullfile(tPath, tFile));

            freq    = t_base.Freq_Hz;
            d_test  = t_test.Energy_dB - t_base.Energy_dB;

            subTaskDir = fullfile(outRoot, taskName);
            figTitle1 = sprintf('1. Delta Energy: %s vs %s', tFile, bFile);
            label1 = strrep(tFile, '.csv', '');
            label2 = 'Baseline Reference';
            deltaMat = d_test;
            peakMat  = [t_test.Step_Peak_Amp, t_base.Step_Peak_Amp];
    end

    if ~exist(subTaskDir, 'dir'), mkdir(subTaskDir); end

    %% 3. Generate 2-Panel Plot
    fig = figure('Name', 'Acoustic Delta Analysis', ...
                 'Color', [0.12, 0.12, 0.15], ...
                 'Position', [100, 80, 1150, 780], ...
                 'Visible', 'on');

    % Top Panel: Overlay Lines
    ax1 = subplot(2, 1, 1);
    hold(ax1, 'on'); grid(ax1, 'on');
    set(ax1, 'Color', [0.08, 0.08, 0.10], 'GridColor', [0.3, 0.3, 0.35], ...
             'XColor', [0.85, 0.85, 0.90], 'YColor', [0.85, 0.85, 0.90]);

    p1 = plot(ax1, freq, deltaMat(:, 1), '-o', 'Color', [0.00, 0.85, 1.00], ...
              'LineWidth', 2.0, 'MarkerSize', 7, 'MarkerFaceColor', [0.00, 0.85, 1.00], 'DisplayName', label1);
    if size(deltaMat, 2) >= 2
        p2 = plot(ax1, freq, deltaMat(:, 2), '-s', 'Color', [1.00, 0.45, 0.15], ...
                  'LineWidth', 2.0, 'MarkerSize', 7, 'MarkerFaceColor', [1.00, 0.45, 0.15], 'DisplayName', label2);
        leg1 = legend(ax1, [p1, p2], 'Location', 'northeast');
    else
        leg1 = legend(ax1, p1, 'Location', 'northeast');
    end
    set(leg1, 'TextColor', [0.95, 0.95, 0.98], 'Color', [0.15, 0.15, 0.20], 'EdgeColor', 'none');

    yline(ax1, 0, '-', 'Color', [0.7, 0.7, 0.7], 'LineWidth', 1.0);
    yline(ax1, -3, '--', 'Color', [0.95, 0.25, 0.25], 'LineWidth', 1.2, ...
          'Label', 'Detection Threshold (-3 dB)', 'LabelHorizontalAlignment', 'left', ...
          'LabelColor', [0.95, 0.25, 0.25]);

    title(ax1, figTitle1, 'Color', [0.95, 0.95, 0.98], 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax1, 'Frequency (Hz)', 'Color', [0.85, 0.85, 0.90]);
    ylabel(ax1, '\Delta Energy (dB)', 'Color', [0.85, 0.85, 0.90]);
    xticks(ax1, freq); xtickangle(ax1, 45);
    xlim(ax1, [250, 1850]);

    % Bottom Panel: Bar Chart
    ax2 = subplot(2, 1, 2);
    hold(ax2, 'on'); grid(ax2, 'on');
    set(ax2, 'Color', [0.08, 0.08, 0.10], 'GridColor', [0.3, 0.3, 0.35], ...
             'XColor', [0.85, 0.85, 0.90], 'YColor', [0.85, 0.85, 0.90]);

    b = bar(ax2, categorical(freq), deltaMat, 0.8);
    b(1).FaceColor = [0.00, 0.85, 1.00];
    b(1).EdgeColor = 'none';
    if length(b) >= 2
        b(2).FaceColor = [1.00, 0.45, 0.15];
        b(2).EdgeColor = 'none';
        leg2 = legend(ax2, {label1, label2}, 'Location', 'southwest');
    else
        leg2 = legend(ax2, {label1}, 'Location', 'southwest');
    end
    set(leg2, 'TextColor', [0.95, 0.95, 0.98], 'Color', [0.15, 0.15, 0.20], 'EdgeColor', 'none');

    yline(ax2, 0, '-', 'Color', [0.7, 0.7, 0.7], 'LineWidth', 1.0);
    yline(ax2, -3, '--', 'Color', [0.95, 0.25, 0.25], 'LineWidth', 1.2);

    title(ax2, '2. Discrete Energy Drop per Frequency Band', ...
          'Color', [0.95, 0.95, 0.98], 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax2, 'Frequency (Hz)', 'Color', [0.85, 0.85, 0.90]);
    ylabel(ax2, '\Delta Energy (dB)', 'Color', [0.85, 0.85, 0.90]);

    %% 4. Save Outputs (.fig only)
    outFigPath = fullfile(subTaskDir, [taskName, '.fig']);

    set(fig, 'Visible', 'on');
    set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(fig, outFigPath);

    linkFig = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Open Delta.fig]</a>', strrep(outFigPath, '\', '/'));
    linkDir = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(subTaskDir, '\', '/'));
    fprintf('[SUCCESS] Delta comparison saved to:\n  - %s\n', outFigPath);
    fprintf('1-Click Actions: %s | %s\n\n', linkFig, linkDir);
end
