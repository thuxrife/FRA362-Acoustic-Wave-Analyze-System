%% Script 1: Raw Acoustic Data Logger (mp3/ -> logged/)
% Scans input directory hierarchy: mp3/{trial_folder}/{sample_name}.wav (or .mp3)
% Automatically groups multi-repeat recordings ({sample}_rep1..N.wav) into a single CSV.
% Outputs aligned, step-tagged raw time-series CSV to:
%   logged/{trial_folder}/{sample_name}.csv
%
% CSV Schema Columns:
%   1. Time_s      : Time in seconds (aligned to Step 1 @ 300 Hz at t = 0.000s, starts at -0.200s)
%   2. Step_ID     : Integer frequency step index (0 = silence/gap, 1..16 = active tone step)
%   3. Freq_Input  : Scheduled input excitation frequency in Hz for the active step (0 during gap)
%   4. Amp_1..Amp_N: Aligned acoustic waveform amplitude for each repeat trial (Amp_1 for single run)
%   5. Amp_Avg     : Ensemble mean amplitude across all N repeats
%   6. Amp_SD      : Sample standard deviation across repeats (0 for single run N=1)

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
    if isempty(audioFiles)
        continue;
    end

    allNames = {audioFiles.name};
    baseSamples = {};
    for f = 1:length(allNames)
        [~, bName, ~] = fileparts(allNames{f});
        cleanBase = regexprep(bName, '_rep\d+$', '');
        if ~ismember(cleanBase, baseSamples)
            baseSamples{end+1} = cleanBase; %#ok<AGROW>
        end
    end

    fprintf('\n--- Logging trial [%d/%d]: %s (%d sample group(s)) ---\n', ...
        t, length(trialDirs), trialName, length(baseSamples));

    for s = 1:length(baseSamples)
        sBase = baseSamples{s};
        outCsvPath = fullfile(LOGGED_ROOT, trialName, [sBase, '.csv']);

        stimHintFile = fullfile(trialPath, [sBase, '_stimulus.txt']);
        if exist(stimHintFile, 'file')
            analyzer.StimulusPath = strtrim(fileread(stimHintFile));
        else
            analyzer.StimulusPath = '';
        end

        repIndices = [];
        repPaths   = {};
        mainFilePath = '';

        for f = 1:length(allNames)
            [~, bName, ~] = fileparts(allNames{f});
            if strcmp(bName, sBase)
                mainFilePath = fullfile(trialPath, allNames{f});
            else
                tok = regexp(bName, ['^', regexptranslate('escape', sBase), '_rep(\d+)$'], 'tokens');
                if ~isempty(tok)
                    repIndices(end+1) = str2double(tok{1}{1}); %#ok<AGROW>
                    repPaths{end+1}   = fullfile(trialPath, allNames{f}); %#ok<AGROW>
                end
            end
        end

        try
            if ~isempty(repPaths)
                [~, sortOrd] = sort(repIndices);
                repPaths = repPaths(sortOrd);
                analyzer.loadRepeatFiles(repPaths);
                analyzer.exportRawCSV(outCsvPath);
                totalLogged = totalLogged + 1;

                fprintf('  [LOGGED] %-26s (%d repeats) -> %s (t0: %.3fs)\n', ...
                    sBase, length(repPaths), strrep(outCsvPath, '\', '/'), analyzer.ReferencePeakTime);
            elseif ~isempty(mainFilePath)
                analyzer.loadFile(mainFilePath);
                analyzer.exportRawCSV(outCsvPath);
                totalLogged = totalLogged + 1;

                fprintf('  [LOGGED] %-26s (Single)    -> %s (t0: %.3fs)\n', ...
                    sBase, strrep(outCsvPath, '\', '/'), analyzer.ReferencePeakTime);
            end
        catch ME
            fprintf(2, '  [ERROR] Failed to log %s: %s\n', sBase, ME.message);
        end
    end
end

fprintf('\nDone! Logged %d raw CSV dataset(s) into "%s/".\n', totalLogged, LOGGED_ROOT);
