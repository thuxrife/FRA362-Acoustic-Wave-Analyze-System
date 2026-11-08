function main(targetTrial, forceReprocess)
%% Master Batch Pipeline Runner (mp3/ -> logged/ -> analyze/)
% Automates the end-to-end acoustic wave analysis pipeline in 2 stages:
%
%   STAGE 1 (Raw Ingestion & Logging):
%     - Scans mp3/{trial}/{sample}.wav (or .mp3)
%     - Skips files already logged unless the .wav was re-recorded or forceReprocess = true
%     - Aligns Step 1 (300 Hz) to t = 0.000s with -0.200s baseline
%     - Exports calibrated time series to: logged/{trial}/{sample}.csv
%
%   STAGE 2 (Feature Extraction & Interactive Visualization):
%     - Skips samples already analyzed in analyze/{trial}/{sample}/ unless updated
%     - Computes discrete per-frequency features (Step_ID, Freq_Hz, Onset_Time_s,
%       Duration_s, Step_RMS, Step_Peak_Amp, Energy_dB)
%     - Exports tabular summary to: analyze/{trial}/{sample}/features_by_frequency.csv
%     - Generates 3 interactive .fig plots with live coordinate bar:
%       * amplitude.fig   (Waveform + envelope + step highlights)
%       * frequency.fig   (Full spectrum + 16 step peak markers)
%       * spectrogram.fig (Time-frequency energy distribution)
%
% Usage:
%   main                                     % Process only new/updated samples in all trials
%   main('2026-11-06-recording-test')        % Process only new/updated samples in specific trial
%   main('2026-11-06-recording-test', true)  % Force re-analyze all samples in trial

    if nargin < 1 || isempty(targetTrial)
        targetTrial = ''; % Process all trials
    end
    if nargin < 2 || isempty(forceReprocess)
        forceReprocess = false; % Skip already-analyzed files by default
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

        % Group audio files by base sample name (stripping _rep1, _rep2, etc.)
        allNames = {audioFiles.name};
        baseSamples = {};
        for f = 1:length(allNames)
            [~, bName, ~] = fileparts(allNames{f});
            cleanBase = regexprep(bName, '_rep\d+$', '');
            if ~ismember(cleanBase, baseSamples)
                baseSamples{end+1} = cleanBase; %#ok<AGROW>
            end
        end

        fprintf('\n--- Ingesting trial [%d/%d]: %s (%d sample group(s)) ---\n', ...
            t, length(trialDirs), tName, length(baseSamples));

        for s = 1:length(baseSamples)
            sBase = baseSamples{s};
            outCsvPath = fullfile(LOGGED_ROOT, tName, [sBase, '.csv']);

            % Check for optional stimulus hint file saved by GUI
            stimHintFile = fullfile(tPath, [sBase, '_stimulus.txt']);
            if exist(stimHintFile, 'file')
                loggerEngine.StimulusPath = strtrim(fileread(stimHintFile));
            else
                loggerEngine.StimulusPath = '';
            end

            % Find all repeat files matching {sBase}_rep<k>.wav/.mp3
            repIndices = [];
            repPaths   = {};
            mainFilePath = '';

            for f = 1:length(allNames)
                [~, bName, ~] = fileparts(allNames{f});
                if strcmp(bName, sBase)
                    mainFilePath = fullfile(tPath, allNames{f});
                else
                    tok = regexp(bName, ['^', regexptranslate('escape', sBase), '_rep(\d+)$'], 'tokens');
                    if ~isempty(tok)
                        repIndices(end+1) = str2double(tok{1}{1}); %#ok<AGROW>
                        repPaths{end+1}   = fullfile(tPath, allNames{f}); %#ok<AGROW>
                    end
                end
            end

            try
                % Determine newest source audio timestamp to check if Stage 1 can be skipped
                srcFiles = repPaths;
                if ~isempty(mainFilePath)
                    srcFiles{end+1} = mainFilePath; %#ok<AGROW>
                end
                newestAudioTime = 0;
                for sf = 1:length(srcFiles)
                    infoSrc = dir(srcFiles{sf});
                    if ~isempty(infoSrc)
                        newestAudioTime = max(newestAudioTime, infoSrc(1).datenum);
                    end
                end

                stage1UpToDate = false;
                if ~forceReprocess && exist(outCsvPath, 'file')
                    infoCsv = dir(outCsvPath);
                    if ~isempty(infoCsv) && infoCsv(1).datenum >= newestAudioTime
                        % Verify CSV uses the new Amp_Avg schema
                        fid = fopen(outCsvPath, 'r');
                        if fid > 0
                            headerLine = fgetl(fid);
                            fclose(fid);
                            if ischar(headerLine) && contains(headerLine, 'Amp_Avg')
                                stage1UpToDate = true;
                            end
                        end
                    end
                end

                if stage1UpToDate
                    loggedCsvList{end+1} = outCsvPath; %#ok<AGROW>
                    fprintf('  [STAGE 1 SKIP]   %-22s -> Already logged & up-to-date (%s)\n', ...
                        sBase, strrep(outCsvPath, '\', '/'));
                elseif ~isempty(repPaths)
                    [~, sortOrd] = sort(repIndices);
                    repPaths = repPaths(sortOrd);
                    loggerEngine.loadRepeatFiles(repPaths);
                    loggerEngine.exportRawCSV(outCsvPath);
                    totalLogged = totalLogged + 1;
                    loggedCsvList{end+1} = outCsvPath; %#ok<AGROW>

                    % Clean up any legacy standalone _rep*.csv files in logged/
                    for r = 1:length(repIndices)
                        oldRepCsv = fullfile(LOGGED_ROOT, tName, sprintf('%s_rep%d.csv', sBase, repIndices(r)));
                        if exist(oldRepCsv, 'file'), delete(oldRepCsv); end
                    end

                    fprintf('  [STAGE 1 LOGGED] %-22s (%d repeats) -> %s (t0: %.3fs)\n', ...
                        sBase, length(repPaths), strrep(outCsvPath, '\', '/'), loggerEngine.ReferencePeakTime);
                elseif ~isempty(mainFilePath)
                    loggerEngine.loadFile(mainFilePath);
                    loggerEngine.exportRawCSV(outCsvPath);
                    totalLogged = totalLogged + 1;
                    loggedCsvList{end+1} = outCsvPath; %#ok<AGROW>

                    fprintf('  [STAGE 1 LOGGED] %-22s (Single)    -> %s (t0: %.3fs)\n', ...
                        sBase, strrep(outCsvPath, '\', '/'), loggerEngine.ReferencePeakTime);
                end
            catch ME
                fprintf(2, '  [ERROR] Ingestion failed for %s: %s\n', sBase, ME.message);
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
        profCsvPath = fullfile(targetDir, 'record_profile.csv');
        featureEngine.TitlePrefix = sprintf('%s-%s', trialName, sampleName);

        % Generate 1-Click Interactive Hyperlinks for MATLAB Command Window
        profFigPath = fullfile(targetDir, 'record_profile.fig');
        ampFigPath  = fullfile(targetDir, 'amplitude.fig');
        freqFigPath = fullfile(targetDir, 'frequency.fig');
        specFigPath = fullfile(targetDir, 'spectrogram.fig');

        profFig = strrep(profFigPath, '\', '/');
        ampFig  = strrep(ampFigPath, '\', '/');
        freqFig = strrep(freqFigPath, '\', '/');
        specFig = strrep(specFigPath, '\', '/');
        featCsv = strrep(featCsvPath, '\', '/');
        profCsv = strrep(profCsvPath, '\', '/');
        fDir    = strrep(targetDir, '\', '/');

        linkFeat  = sprintf('<a href="matlab:open(''%s'');">[Features CSV]</a>', featCsv);
        linkProf  = sprintf('<a href="matlab:open(''%s'');">[Quality CSV]</a>', profCsv);
        linkPFig  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Profile.fig]</a>', profFig);
        linkAmp   = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amplitude.fig]</a>', ampFig);
        linkFreq  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Frequency.fig]</a>', freqFig);
        linkSpec  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram.fig]</a>', specFig);
        linkDir   = sprintf('<a href="matlab:winopen(''%s'');">[Folder]</a>', fDir);

        % Check if Stage 2 outputs already exist and are newer than the logged CSV
        stage2UpToDate = false;
        if ~forceReprocess && exist(featCsvPath, 'file') && exist(profCsvPath, 'file') && ...
                exist(ampFigPath, 'file') && exist(freqFigPath, 'file') && exist(specFigPath, 'file')
            infoCsv  = dir(csvPath);
            infoFeat = dir(featCsvPath);
            infoAmp  = dir(ampFigPath);
            if ~isempty(infoCsv) && ~isempty(infoFeat) && ~isempty(infoAmp) && ...
                    infoFeat(1).datenum >= infoCsv(1).datenum && infoAmp(1).datenum >= infoCsv(1).datenum
                try
                    T_exist = readtable(featCsvPath);
                    if height(T_exist) >= 16
                        stage2UpToDate = true;
                    end
                catch
                end
            end
        end

        if stage2UpToDate
            fprintf('  [STAGE 2 SKIP] %-20s (Already Analyzed) -> %s %s %s %s %s %s | %s\n', ...
                sampleName, linkProf, linkPFig, linkFeat, linkAmp, linkFreq, linkSpec, linkDir);
            continue;
        end

        try
            % Ingest logged CSV and compute discrete per-frequency table
            T_raw = featureEngine.loadFromCSV(csvPath);
            featTable = featureEngine.extractStepFeatures(featCsvPath, T_raw);
            profTable = featureEngine.exportRecordProfile(profCsvPath, T_raw);

            % Generate interactive .fig plots with coordinate tracking
            featureEngine.analyzeAndExport(targetDir);
            totalAnalyzed = totalAnalyzed + 1;

            verdictStr = 'VALID';
            try
                verdictStr = profTable.Value{strcmp(profTable.Metric, 'Data_Quality_Verdict')};
            catch
            end

            fprintf('  [STAGE 2 OK]   %-20s [%-18s] -> %s %s %s %s %s %s | %s\n', ...
                sampleName, verdictStr, linkProf, linkPFig, linkFeat, linkAmp, linkFreq, linkSpec, linkDir);

        catch ME
            fprintf(2, '  [ERROR] Feature extraction failed for %s: %s\n', csvPath, ME.message);
        end
    end

    fprintf('\n=================================================================\n');
    fprintf('  Pipeline Finished: %d sample(s) processed into "%s/".\n', totalAnalyzed, OUTPUT_ROOT);
    fprintf('=================================================================\n\n');
end
