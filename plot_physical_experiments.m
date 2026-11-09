function plot_physical_experiments(expChoice)
%% Automated Physical Experiments Plotter & Runner
% Generates all standardized figures for the 3 defined physical experiments:
%
%   (1) Time Of Flight (ToF)
%       - Inputs: Clay, Leaf, Stone at Front, Middle, Rear (100% Area)
%       - Output: Amplitude (Raw)
%       - Destination: analyze/overlay/amplitude/
%
%   (2) Porous vs Non-Porous
%       - Inputs: Clay, Leaf, Stone at Middle (100% Area) vs Baseline
%       - Output: Raw Frequency Spectrum + Envelope Spectrogram Heatmap
%       - Destination: analyze/overlay/frequency/ and analyze/envelope/spectrogram/
%
%   (3) Area Blockage
%       - Inputs: Clay, Leaf, Stone across {0%, 25%, 50%, 75%, 100%} at Middle
%       - Output: Amplitude Envelope + Raw Frequency Spectrum + Envelope Spectrogram Heatmap
%       - Destination: analyze/envelope/amplitude/, analyze/overlay/frequency/, analyze/envelope/spectrogram/
%
% Usage:
%   plot_physical_experiments()         % Interactive mode selection or run all
%   plot_physical_experiments(1)        % Run only Exp 1 (ToF)
%   plot_physical_experiments(2)        % Run only Exp 2 (Porous vs Non-Porous)
%   plot_physical_experiments(3)        % Run only Exp 3 (Area Blockage)
%   plot_physical_experiments('all')    % Run all 3 experiments in batch

    baseDir = fileparts(mfilename('fullpath'));
    if ~isempty(baseDir), cd(baseDir); end
    addpath(pwd);

    baseCsv = fullfile('logged', '2026-11-08-baseline', 'sound_sample_baseline.csv');
    baseFreqFig = fullfile('analyze', '2026-11-08-baseline', 'sound_sample_baseline', 'frequency.fig');
    baseAmpFig = fullfile('analyze', '2026-11-08-baseline', 'sound_sample_baseline', 'amplitude.fig');

    exp1Logged = fullfile('logged', '2026-11-08-exp-01-sediment-type');
    exp2Logged = fullfile('logged', '2026-11-08-exp-02-sediment-area');
    exp1Analyze = fullfile('analyze', '2026-11-08-exp-01-sediment-type');
    exp2Analyze = fullfile('analyze', '2026-11-08-exp-02-sediment-area');

    if ~exist(baseCsv, 'file')
        error('Baseline file "%s" not found. Record or log baseline first.', baseCsv);
    end

    %% 1. Interactive Selection if Option Omitted
    if nargin < 1 || isempty(expChoice)
        choices = {
            'Run All Experiments (1, 2, 3)', ...
            '1. Time-of-Flight (ToF) - Position Progression', ...
            '2. Porous vs. Non-Porous - Material Characterization', ...
            '3. Area Blockage - 0% to 100% Constriction'
        };
        [sel, ok] = listdlg('PromptString', 'Select Physical Experiment to Plot:', ...
                            'SelectionMode', 'single', ...
                            'ListString', choices, ...
                            'ListSize', [420, 100], ...
                            'Name', 'Physical Experiment Runner');
        if ~ok || isempty(sel)
            fprintf('[Physical Experiments] Cancelled by user.\n');
            return;
        end
        switch sel
            case 1, expChoice = 'all';
            case 2, expChoice = 1;
            case 3, expChoice = 2;
            case 4, expChoice = 3;
        end
    end

    runExp1 = false;
    runExp2 = false;
    runExp3 = false;

    if ischar(expChoice) || isstring(expChoice)
        c = lower(strtrim(char(expChoice)));
        if strcmp(c, 'all') || strcmp(c, '123')
            runExp1 = true; runExp2 = true; runExp3 = true;
        elseif contains(c, 'tof') || strcmp(c, '1')
            runExp1 = true;
        elseif contains(c, 'porous') || strcmp(c, '2')
            runExp2 = true;
        elseif contains(c, 'area') || strcmp(c, '3')
            runExp3 = true;
        else
            runExp1 = true; runExp2 = true; runExp3 = true;
        end
    elseif isnumeric(expChoice)
        switch expChoice
            case 1, runExp1 = true;
            case 2, runExp2 = true;
            case 3, runExp3 = true;
            otherwise, runExp1 = true; runExp2 = true; runExp3 = true;
        end
    end

    fprintf('=================================================================\n');
    fprintf('           Acoustic Rig Physical Experiment Plotter              \n');
    fprintf('=================================================================\n');

    %% 2. Experiment (1): Time of Flight (ToF)
    if runExp1
        fprintf('\n>>> [1/3] RUNNING EXPERIMENT 1: TIME OF FLIGHT (ToF) [RAW AMPLITUDE] <<<\n');
        mats = {'clay', 'leaf', 'stone'};
        for i = 1:length(mats)
            m = mats{i};
            paths = {
                baseAmpFig, ...
                fullfile(exp1Analyze, sprintf('sound_sample_%s_100_h_front', m), 'amplitude.fig'), ...
                fullfile(exp1Analyze, sprintf('sound_sample_%s_100_h_middle', m), 'amplitude.fig'), ...
                fullfile(exp1Analyze, sprintf('sound_sample_%s_100_h_rear', m), 'amplitude.fig')
            };
            overlay_figures(paths, sprintf('tof_raw_amplitude_%s_positions', m), false);
        end

        % Multi-material comparison at Middle 100%
        overlay_figures({baseAmpFig, ...
            fullfile(exp1Analyze, 'sound_sample_clay_100_h_middle', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_leaf_100_h_middle', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_stone_100_h_middle', 'amplitude.fig')}, ...
            'tof_raw_amplitude_materials_middle', false);

        % Complete 9-condition matrix overlay
        all9Paths = {
            baseAmpFig, ...
            fullfile(exp1Analyze, 'sound_sample_clay_100_h_front', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_clay_100_h_middle', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_clay_100_h_rear', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_leaf_100_h_front', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_leaf_100_h_middle', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_leaf_100_h_rear', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_stone_100_h_front', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_stone_100_h_middle', 'amplitude.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_stone_100_h_rear', 'amplitude.fig')
        };
        overlay_figures(all9Paths, 'tof_raw_amplitude_all_9_conditions', false);
        fprintf('[DONE] Experiment 1 saved to: analyze/overlay/amplitude/\n');
    end

    %% 3. Experiment (2): Porous vs Non-Porous
    if runExp2
        fprintf('\n>>> [2/3] RUNNING EXPERIMENT 2: POROUS VS NON-POROUS <<<\n');
        % Raw Frequency
        rawFreqPaths = {
            baseFreqFig, ...
            fullfile(exp1Analyze, 'sound_sample_clay_100_h_middle', 'frequency.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_leaf_100_h_middle', 'frequency.fig'), ...
            fullfile(exp1Analyze, 'sound_sample_stone_100_h_middle', 'frequency.fig')
        };
        overlay_figures(rawFreqPaths, 'porous_raw_frequency_materials', false);

        % Envelope Spectrogram Heatmap
        envSpecPaths = {
            baseCsv, ...
            fullfile(exp1Logged, 'sound_sample_clay_100_h_middle.csv'), ...
            fullfile(exp1Logged, 'sound_sample_leaf_100_h_middle.csv'), ...
            fullfile(exp1Logged, 'sound_sample_stone_100_h_middle.csv')
        };
        plot_acoustic_reflex_map(envSpecPaths, 'porous_envelope_spectrogram_materials');
        fprintf('[DONE] Experiment 2 saved to: analyze/overlay/frequency/ & analyze/envelope/spectrogram/\n');
    end

    %% 4. Experiment (3): Area Blockage (0% to 100%)
    if runExp3
        fprintf('\n>>> [3/3] RUNNING EXPERIMENT 3: AREA BLOCKAGE (0%% - 100%%) <<<\n');
        mats = {'clay', 'leaf', 'stone'};
        for i = 1:length(mats)
            m = mats{i};
            fprintf('  Generating Area Blockage plots for %s...\n', upper(m));

            % Amplitude (Envelope)
            envAmpPaths = {
                baseCsv, ...
                fullfile(exp2Logged, sprintf('sound_sample_%s_25_h_middle.csv', m)), ...
                fullfile(exp2Logged, sprintf('sound_sample_%s_50_h_middle.csv', m)), ...
                fullfile(exp2Logged, sprintf('sound_sample_%s_75_h_middle.csv', m)), ...
                fullfile(exp1Logged, sprintf('sound_sample_%s_100_h_middle.csv', m))
            };
            plot_envelope_overlay(envAmpPaths, 'amplitude', sprintf('area_envelope_%s_0_to_100', m));

            % Raw Frequency
            rawFreqAreaPaths = {
                baseFreqFig, ...
                fullfile(exp2Analyze, sprintf('sound_sample_%s_25_h_middle', m), 'frequency.fig'), ...
                fullfile(exp2Analyze, sprintf('sound_sample_%s_50_h_middle', m), 'frequency.fig'), ...
                fullfile(exp2Analyze, sprintf('sound_sample_%s_75_h_middle', m), 'frequency.fig'), ...
                fullfile(exp1Analyze, sprintf('sound_sample_%s_100_h_middle', m), 'frequency.fig')
            };
            overlay_figures(rawFreqAreaPaths, sprintf('area_raw_frequency_%s_0_to_100', m), false);

            % Envelope Spectrogram Heatmap
            plot_acoustic_reflex_map(envAmpPaths, sprintf('area_envelope_spectrogram_%s_0_to_100', m));
        end
        fprintf('[DONE] Experiment 3 saved to: analyze/envelope/amplitude/, analyze/overlay/frequency/, analyze/envelope/spectrogram/\n');
    end

    fprintf('\n=================================================================\n');
    fprintf('  ALL REQUESTED EXPERIMENTAL FIGURES HAVE BEEN GENERATED!        \n');
    fprintf('=================================================================\n\n');
end
