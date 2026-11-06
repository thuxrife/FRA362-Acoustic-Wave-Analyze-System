%% Script 2: Per-Frequency Feature Extraction & Handy Visualizer (logged/ -> analyze/)
% Accepts an array of relative paths to full CSV files logged in /logged.
% Extracts discrete per-frequency features (e.g., 16 frequency steps) and
% exports both feature tables and interactive visualizations into /analyze.
%
% Extracted Per-Frequency Features (features_by_frequency.csv):
%   1. Step_ID          : Step index (1..16)
%   2. Freq_Hz          : Dominant excitation frequency (Hz)
%   3. Onset_Time_s     : Aligned start time of the tone burst (s)
%   4. Duration_s       : Active tone duration (s)
%   5. Direct_Peak_Amp  : Leading-edge direct wave peak amplitude
%   6. Echo_Peak_Amp    : Reflected wave peak amplitude inside pipe (x/L in [0.15, 0.90])
%   7. Echo_Location_xL : Dimensionless distance (x/L) of reflection peak
%   8. Step_RMS         : Steady-state RMS amplitude of the frequency step
%   9. Step_Peak_Amp    : Maximum envelope amplitude of the frequency step
%  10. Energy_dB        : Acoustic energy level in dB (20*log10(Step_RMS))

clear; clc;

%% 1. Input Array of Logged CSV Files (Relative Paths)
% Specify target CSV files from /logged, or leave empty {} to process all CSVs in /logged
CSV_FILES = {
    'logged/2026-03-11-sound-sample-2/sound_sample_block.csv', ...
    'logged/2026-03-11-sound-sample-2/sound_sample_no_block.csv'
};

%% 2. Acoustic & Visualization Configuration
LOGGED_ROOT     = 'logged';
OUTPUT_ROOT     = 'analyze';
MODEL_LENGTH    = 2.0;    % Pipe length L (m)
PIPE_DIAMETER   = 0.10;   % Pipe diameter D (0.10 m = 100 mm -> f_c ~ 2028 Hz)
SOUND_SPEED     = 346.0;  % Speed of sound (m/s)
MAX_FREQ        = 2200;   % Upper frequency bound (Hz)
KNOWN_BLOCKAGE  = 0.40;   % Known blockage location (x/L)
MIN_STEP_SEP_S  = 0.25;   % Minimum separation (s) between frequency steps
SAVE_FORMAT     = 'svg';  % Export image format
SAVE_FIG        = true;   % Save interactive MATLAB .fig files
SHOW_PLOTS      = false;  % Set true to pop up figures interactively

%% Auto-discover CSV files if CSV_FILES is empty
if isempty(CSV_FILES)
    foundCsv = dir(fullfile(LOGGED_ROOT, '**', '*.csv'));
    CSV_FILES = cell(1, length(foundCsv));
    for k = 1:length(foundCsv)
        CSV_FILES{k} = fullfile(foundCsv(k).folder, foundCsv(k).name);
    end
end

if isempty(CSV_FILES)
    error('No CSV files specified or found in "%s/". Run log_raw_data.m first.', LOGGED_ROOT);
end

%% Initialize OOP Analyzer Engine
analyzer = AudioAnalyzer('', ...
    'MaxFrequency', MAX_FREQ, ...
    'SaveFormat', SAVE_FORMAT, ...
    'SaveFig', SAVE_FIG, ...
    'VisibleFigures', SHOW_PLOTS, ...
    'ModelLength', MODEL_LENGTH, ...
    'PipeDiameter', PIPE_DIAMETER, ...
    'SoundSpeed', SOUND_SPEED, ...
    'KnownBlockage', KNOWN_BLOCKAGE, ...
    'MinStepSeparation', MIN_STEP_SEP_S);

fprintf('=== Extracting Per-Frequency Features from %d CSV file(s) ===\n', length(CSV_FILES));

for idx = 1:length(CSV_FILES)
    csvPath = CSV_FILES{idx};
    if ~exist(csvPath, 'file')
        fprintf(2, '  [SKIP] CSV file not found: %s\n', csvPath);
        continue;
    end

    [parentPath, sampleName, ~] = fileparts(csvPath);
    [~, trialName, ~] = fileparts(parentPath);
    if isempty(trialName) || strcmpi(trialName, LOGGED_ROOT)
        trialName = 'default_trial';
    end

    targetDir = fullfile(OUTPUT_ROOT, trialName, sampleName);
    featCsvPath = fullfile(targetDir, 'features_by_frequency.csv');
    analyzer.TitlePrefix = sprintf('%s-%s', trialName, sampleName);

    try
        % Load logged raw CSV and extract per-frequency features
        T_raw = analyzer.loadFromCSV(csvPath);
        featTable = analyzer.extractStepFeatures(featCsvPath, T_raw);

        % Export standard 4-plot visual suite from CSV data
        analyzer.analyzeAndExport(targetDir);

        % Print 1-click MATLAB hyperlinks
        ampFig  = strrep(fullfile(targetDir, 'amplitude.fig'), '\', '/');
        freqFig = strrep(fullfile(targetDir, 'frequency.fig'), '\', '/');
        specFig = strrep(fullfile(targetDir, 'spectrogram.fig'), '\', '/');
        distFig = strrep(fullfile(targetDir, 'amplitude-distance.fig'), '\', '/');
        featCsv = strrep(featCsvPath, '\', '/');

        fprintf('  [OK] %-26s -> %2d freq steps | <a href="matlab:open(''%s'');">[Features CSV]</a> <a href="matlab:openfig(''%s'', ''visible'');">[Amplitude]</a> <a href="matlab:openfig(''%s'', ''visible'');">[Frequency]</a> <a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram]</a> <a href="matlab:openfig(''%s'', ''visible'');">[Amp-Dist]</a>\n', ...
            sampleName, height(featTable), featCsv, ampFig, freqFig, specFig, distFig);
    catch ME
        fprintf(2, '  [ERROR] Failed on %s: %s\n', csvPath, ME.message);
    end
end

fprintf('\nDone! Feature tables and visualizations exported to "%s/".\n', OUTPUT_ROOT);
