function main(targetTrial)
%% Master Batch Pipeline Runner (mp3/ -> logged/ -> analyze/)
% Automates the end-to-end acoustic wave analysis pipeline in 2 stages:
%
%   STAGE 1 (Raw Ingestion & Logging):
%     - Scans mp3/{trial}/{sample}.wav (or .mp3)
%     - Detects acoustic onset and auto-aligns 1st excitation peak to t = 0.0s
%     - Retains 0.2s pre-trigger baseline (starts at t = -0.200s)
%     - Identifies active frequency steps (1..16) and Hilbert envelope
%     - Exports calibrated time series to: logged/{trial}/{sample}.csv
%
%   STAGE 2 (Feature Extraction & Interactive Visualization):
%     - Discovers all logged datasets in logged/{trial}/{sample}.csv
%     - Computes discrete per-frequency features (Step_ID, Freq_Hz, Onset_Time_s,
%       Duration_s, Step_RMS, Step_Peak_Amp, Energy_dB)
%     - Exports tabular summary to: analyze/{trial}/{sample}/features_by_frequency.csv
%     - Generates 3 interactive .fig plots with live coordinate bar:
%       * amplitude.fig   (Waveform + envelope + step highlights)
%       * frequency.fig   (Full spectrum + 16 step peak markers)
%       * spectrogram.fig (Time-frequency energy distribution)
%
% Usage:
%   main                               % Process all trials in mp3/
%   main('2026-11-06-recording-test')  % Process a specific trial only

    if nargin < 1 || isempty(targetTrial)
        targetTrial = ''; % Process all trials
    end

    %% Configuration
    INPUT_ROOT      = 'mp3';
    LOGGED_ROOT     = 'logged';
    OUTPUT_ROOT     = 'analyze';

    AUTO_ALIGN      = true;   % Sub-millisecond onset alignment (t=0 at 1st peak)
    PRE_TRIGGER_S   = 0.2;    % Retain 0.2s pre-excitation baseline
    MIN_STEP_SEP_S  = 0.25;   % Minimum step separation in seconds
    MAX_FREQ        = 2200;   % Display cut-off boundary (Hz)
    SAVE_FIG        = true;   % Generate interactive .fig files
    SAVE_IMAGE      = false;  % FIG only by default (no SVG)
    SHOW_PLOTS      = false;  % Run headlessly without pop-up windows

    fprintf('=================================================================\n');
    fprintf('         Acoustic Rig Master Batch Pipeline Runner               \n');
    fprintf('=================================================================\n');

    %% Stage 1: Ingest Raw Audio into Calibrated CSVs (mp3/ -> logged/)
    fprintf('\n>>> STAGE 1: Raw Data Ingestion & Time-Alignment (mp3/ -> logged/) <<<\n');
    if ~exist(INPUT_ROOT, 'dir')
        error('Input directory "%s" does not exist. Record samples first.', INPUT_ROOT);
    end

    if isempty(targetTrial)
        trialDirs = dir(INPUT_ROOT);
        trialDirs = trialDirs([trialDirs.isdir] & ~ismember({trialDirs.name}, {'.', '..'}));
    else
        specificPath = fullfile(INPUT_ROOT, targetTrial);
        if ~exist(specificPath, 'dir')
            error('Specified trial directory "%s" does not exist.', specificPath);
        end
        trialDirs = dir(specificPath);
        trialDirs = struct('name', targetTrial, 'isdir', true);
    end

    if isempty(trialDirs)
        fprintf('No trials found to process in "%s".\n', INPUT_ROOT);
        return;
    end

    loggerEngine = AudioAnalyzer('', ...
        'AutoAlign', AUTO_ALIGN, ...
        'PreTriggerSeconds', PRE_TRIGGER_S, ...
        'MinStepSeparation', MIN_STEP_SEP_S);

    totalLogged = 0;
    loggedCsvList = {};

    for t = 1:length(trialDirs)
        tName = trialDirs(t).name;
        tPath = fullfile(INPUT_ROOT, tName);

        audioFiles = [dir(fullfile(tPath, '*.wav')); dir(fullfile(tPath, '*.mp3'))];
        if isempty(audioFiles)
            continue;
        end

        fprintf('\n--- Ingesting trial [%d/%d]: %s (%d files) ---\n', ...
            t, length(trialDirs), tName, length(audioFiles));

        for f = 1:length(audioFiles)
            aName = audioFiles(f).name;
            [~, baseName, ~] = fileparts(aName);
            inFilePath  = fullfile(tPath, aName);
            outCsvPath  = fullfile(LOGGED_ROOT, tName, [baseName, '.csv']);

            try
                loggerEngine.loadFile(inFilePath);
                loggerEngine.exportRawCSV(outCsvPath);
                totalLogged = totalLogged + 1;
                loggedCsvList{end+1} = outCsvPath; %#ok<AGROW>

                fprintf('  [STAGE 1 LOGGED] %-22s -> %s (Duration: %.2fs, Spike: %.3fs)\n', ...
                    aName, strrep(outCsvPath, '\', '/'), loggerEngine.Duration, loggerEngine.ReferencePeakTime);
            catch ME
                fprintf(2, '  [ERROR] Ingestion failed for %s: %s\n', aName, ME.message);
            end
        end
    end

    fprintf('\nStage 1 Complete: %d dataset(s) logged to "%s/".\n', totalLogged, LOGGED_ROOT);

    %% Stage 2: Feature Extraction & Interactive Visualizations (logged/ -> analyze/)
    fprintf('\n>>> STAGE 2: Feature Extraction & FIG Plotting (logged/ -> analyze/) <<<\n');
    
    if isempty(loggedCsvList)
        % Fallback discovery in logged/ directory
        if isempty(targetTrial)
            foundCsv = dir(fullfile(LOGGED_ROOT, '**', '*.csv'));
        else
            foundCsv = dir(fullfile(LOGGED_ROOT, targetTrial, '*.csv'));
        end
        for k = 1:length(foundCsv)
            loggedCsvList{end+1} = fullfile(foundCsv(k).folder, foundCsv(k).name); %#ok<AGROW>
        end
    end

    if isempty(loggedCsvList)
        fprintf('No logged CSV files available for feature extraction.\n');
        return;
    end

    featureEngine = AudioAnalyzer('', ...
        'MaxFrequency', MAX_FREQ, ...
        'SaveFig', SAVE_FIG, ...
        'SaveImage', SAVE_IMAGE, ...
        'VisibleFigures', SHOW_PLOTS, ...
        'EnableDistance', false, ...
        'MinStepSeparation', MIN_STEP_SEP_S);

    totalAnalyzed = 0;

    for idx = 1:length(loggedCsvList)
        csvPath = loggedCsvList{idx};
        if ~exist(csvPath, 'file')
            continue;
        end

        [parentPath, sampleName, ~] = fileparts(csvPath);
        [~, trialName, ~] = fileparts(parentPath);
        if isempty(trialName) || strcmpi(trialName, LOGGED_ROOT)
            trialName = 'default_trial';
        end

        targetDir = fullfile(OUTPUT_ROOT, trialName, sampleName);
        featCsvPath = fullfile(targetDir, 'features_by_frequency.csv');
        featureEngine.TitlePrefix = sprintf('%s-%s', trialName, sampleName);

        try
            % Ingest logged CSV and compute discrete per-frequency table
            T_raw = featureEngine.loadFromCSV(csvPath);
            featTable = featureEngine.extractStepFeatures(featCsvPath, T_raw);

            % Generate interactive .fig plots with coordinate tracking
            featureEngine.analyzeAndExport(targetDir);
            totalAnalyzed = totalAnalyzed + 1;

            % Generate 1-Click Interactive Hyperlinks for MATLAB Command Window
            ampFig  = strrep(fullfile(targetDir, 'amplitude.fig'), '\', '/');
            freqFig = strrep(fullfile(targetDir, 'frequency.fig'), '\', '/');
            specFig = strrep(fullfile(targetDir, 'spectrogram.fig'), '\', '/');
            featCsv = strrep(featCsvPath, '\', '/');
            fDir    = strrep(targetDir, '\', '/');

            linkFeat = sprintf('<a href="matlab:open(''%s'');">[Features CSV]</a>', featCsv);
            linkAmp  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amplitude.fig]</a>', ampFig);
            linkFreq = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Frequency.fig]</a>', freqFig);
            linkSpec = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram.fig]</a>', specFig);
            linkDir  = sprintf('<a href="matlab:winopen(''%s'');">[Folder]</a>', fDir);

            fprintf('  [STAGE 2 OK] %-20s (%2d steps) -> %s %s %s %s | %s\n', ...
                sampleName, height(featTable), linkFeat, linkAmp, linkFreq, linkSpec, linkDir);

        catch ME
            fprintf(2, '  [ERROR] Feature extraction failed for %s: %s\n', csvPath, ME.message);
        end
    end

    fprintf('\n=================================================================\n');
    fprintf('  Pipeline Finished: %d sample(s) processed into "%s/".\n', totalAnalyzed, OUTPUT_ROOT);
    fprintf('=================================================================\n\n');
end
