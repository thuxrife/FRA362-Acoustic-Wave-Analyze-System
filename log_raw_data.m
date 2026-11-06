%% Script 1: Raw Acoustic Data Logger (mp3/ -> logged/)
% Scans input directory hierarchy: mp3/{trial_folder}/{sample_name}.wav (or .mp3)
% Outputs aligned, step-tagged raw time-series CSV to:
%   logged/{trial_folder}/{sample_name}.csv
%
% CSV Schema Columns:
%   1. Time_s    : Time in seconds (aligned to 1st excitation peak at 0.0s, starts at -0.2s)
%   2. Amplitude : Raw mono acoustic pressure signal s(t)
%   3. Envelope  : Instantaneous Hilbert envelope E(t) = |s(t) + j*H{s(t)}|
%   4. Step_ID   : Integer frequency step index (0 = silence/baseline, 1..16 = active tone step)
%   5. Freq_Hz   : Detected excitation frequency in Hz for the active step (0 during silence)

clear; clc;

%% Configuration
INPUT_ROOT        = 'mp3';
LOGGED_ROOT       = 'logged';
AUTO_ALIGN        = true;   % Align time axis to 1st excitation spike peak
PRE_TRIGGER_S     = 0.2;    % Include 0.2s baseline prior to 1st spike peak
MIN_STEP_SEP_S    = 0.25;   % Minimum separation (s) between consecutive tone steps

%% Validate Input Directory
if ~exist(INPUT_ROOT, 'dir')
    error('Input directory "%s" does not exist.', INPUT_ROOT);
end

trialDirs = dir(INPUT_ROOT);
trialDirs = trialDirs([trialDirs.isdir] & ~ismember({trialDirs.name}, {'.', '..'}));

if isempty(trialDirs)
    fprintf('No trial folders found in "%s".\n', INPUT_ROOT);
    return;
end

analyzer = AudioAnalyzer('', ...
    'AutoAlign', AUTO_ALIGN, ...
    'PreTriggerSeconds', PRE_TRIGGER_S, ...
    'MinStepSeparation', MIN_STEP_SEP_S);

totalLogged = 0;

%% Process Each Trial and Export Raw CSV to /logged
for t = 1:length(trialDirs)
    trialName = trialDirs(t).name;
    trialPath = fullfile(INPUT_ROOT, trialName);

    audioFiles = [dir(fullfile(trialPath, '*.wav')); dir(fullfile(trialPath, '*.mp3'))];
    fprintf('\n--- Logging trial [%d/%d]: %s (%d files) ---\n', ...
        t, length(trialDirs), trialName, length(audioFiles));

    for f = 1:length(audioFiles)
        fileName = audioFiles(f).name;
        [~, baseName, ~] = fileparts(fileName);
        inFilePath  = fullfile(trialPath, fileName);
        outCsvPath  = fullfile(LOGGED_ROOT, trialName, [baseName, '.csv']);

        try
            analyzer.loadFile(inFilePath);
            analyzer.exportRawCSV(outCsvPath);
            totalLogged = totalLogged + 1;

            fprintf('  [LOGGED] %-26s -> %s (Duration: %.2fs, Ref Peak: %.3fs)\n', ...
                fileName, strrep(outCsvPath, '\', '/'), analyzer.Duration, analyzer.ReferencePeakTime);
        catch ME
            fprintf(2, '  [ERROR] Failed to log %s: %s\n', fileName, ME.message);
        end
    end
end

fprintf('\nDone! Logged %d raw CSV dataset(s) into "%s/".\n', totalLogged, LOGGED_ROOT);
