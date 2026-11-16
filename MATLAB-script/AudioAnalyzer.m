classdef AudioAnalyzer < handle
    % AudioAnalyzer
    % Acoustic signal analysis engine:
    % 1. Amplitude vs Time (amplitude.svg / .fig)
    % 2. Frequency Spectrum (frequency.svg / .fig)
    % 3. Spectrogram (spectrogram.svg / .fig)
    % 4. Amplitude vs Dimensionless Distance (amplitude-distance.svg / .fig)

    properties
        FilePath (1, :) char = ''
        SampleRate (1, 1) double = 44100
        RawAudioData double = []          % Full uncropped audio
        AudioData double = []             % Active audio data
        NumChannels (1, 1) double = 1
        Duration (1, 1) double = 0        % Duration in seconds
        TimeVector double = []            % Time vector in seconds
        IsMillisecondScale logical = false

        % Configurable parameters with defaults (no magic numbers)
        TimeRange double = []             % [tStart, tEnd] in seconds. Empty = full file
        TitlePrefix (1, :) char = ''      % Header prefix for plot titles (e.g., 'trial_name-1')
        MaxAmplitude double = []          % Upper limit for amplitude y-axis (empty = auto)
        MaxFrequency double = []          % Upper frequency limit in Hz (empty = cut-off limit)
        NFFT double = []                  % FFT length (defaults to nextpow2(L))
        WindowLength (1, 1) double = 1024 % Spectrogram window size
        OverlapLength (1, 1) double = 512 % Spectrogram overlap
        SaveFormat (1, :) char = 'fig'    % Primary format
        SaveFig (1, 1) logical = true     % Save interactive MATLAB .fig for zooming/inspecting
        SaveImage (1, 1) logical = false  % Do not export static images (.svg/.png) by default
        VisibleFigures (1, 1) logical = false % Display figures or run headless
        DynamicRangeDB (1, 1) double = 45 % Contrast threshold in dB below peak

        % Acoustic duct parameters
        ModelLength (1, 1) double = 2.0   % Pipe length in meters
        PipeDiameter (1, 1) double = 0.10 % Pipe diameter in meters (100 mm = 0.10 m for ~2028 Hz cut-off)
        SoundSpeed (1, 1) double = 346.0  % Speed of sound in m/s
        EnableDistance (1, 1) logical = false % Disabled (x/L reflectometry removed)
        KnownBlockage (1, 1) double = NaN % Dimensionless position of known blockage (e.g. 0.40)

        % Signal Alignment & Stimulus Schedule Parameters
        AutoAlign (1, 1) logical = true   % Align time axis using matched stimulus comb + first peak
        PreTriggerSeconds (1, 1) double = 0.2 % Buffer duration (seconds) before first step to retain
        ReferencePeakTime double = NaN    % Timestamp (seconds in raw audio) of aligned Step 1 origin
        MinStepSeparation (1, 1) double = 0.25 % Minimum time (s) between consecutive frequency step onsets
        StimulusPath (1, :) char = ''     % Optional path to excitation stimulus .wav track
        RepeatDataMatrix double = []      % Matrix [M x N] storing aligned [Amp_1, ..., Amp_N]
        ActiveSchedule struct = struct()  % Resolved step schedule (freqSteps, relOnsets, toneDurs, gapDurs)
    end

    methods
        function obj = AudioAnalyzer(filePath, varargin)
            if nargin > 0 && ~isempty(filePath)
                obj.FilePath = filePath;
            end

            p = inputParser;
            addParameter(p, 'TimeRange', obj.TimeRange, @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && x(2) > x(1)));
            addParameter(p, 'TitlePrefix', obj.TitlePrefix, @ischar);
            addParameter(p, 'MaxAmplitude', obj.MaxAmplitude, @(x) isempty(x) || (isnumeric(x) && x > 0));
            addParameter(p, 'MaxFrequency', obj.MaxFrequency, @(x) isempty(x) || (isnumeric(x) && x > 0));
            addParameter(p, 'WindowLength', obj.WindowLength, @isnumeric);
            addParameter(p, 'OverlapLength', obj.OverlapLength, @isnumeric);
            addParameter(p, 'SaveFormat', obj.SaveFormat, @ischar);
            addParameter(p, 'SaveFig', obj.SaveFig, @islogical);
            addParameter(p, 'SaveImage', obj.SaveImage, @islogical);
            addParameter(p, 'VisibleFigures', obj.VisibleFigures, @islogical);
            addParameter(p, 'DynamicRangeDB', obj.DynamicRangeDB, @isnumeric);
            addParameter(p, 'ModelLength', obj.ModelLength, @(x) isnumeric(x) && x > 0);
            addParameter(p, 'PipeDiameter', obj.PipeDiameter, @(x) isnumeric(x) && x > 0);
            addParameter(p, 'SoundSpeed', obj.SoundSpeed, @(x) isnumeric(x) && x > 0);
            addParameter(p, 'EnableDistance', obj.EnableDistance, @islogical);
            addParameter(p, 'KnownBlockage', obj.KnownBlockage, @isnumeric);
            addParameter(p, 'AutoAlign', obj.AutoAlign, @islogical);
            addParameter(p, 'PreTriggerSeconds', obj.PreTriggerSeconds, @(x) isnumeric(x) && x >= 0);
            addParameter(p, 'MinStepSeparation', obj.MinStepSeparation, @(x) isnumeric(x) && x > 0);
            addParameter(p, 'StimulusPath', obj.StimulusPath, @(x) ischar(x) || isstring(x));
            parse(p, varargin{:});

            obj.TimeRange = p.Results.TimeRange;
            obj.TitlePrefix = p.Results.TitlePrefix;
            obj.MaxAmplitude = p.Results.MaxAmplitude;
            obj.MaxFrequency = p.Results.MaxFrequency;
            obj.WindowLength = p.Results.WindowLength;
            obj.OverlapLength = p.Results.OverlapLength;
            obj.SaveFormat = p.Results.SaveFormat;
            obj.SaveFig = p.Results.SaveFig;
            obj.SaveImage = p.Results.SaveImage;
            obj.VisibleFigures = p.Results.VisibleFigures;
            obj.DynamicRangeDB = p.Results.DynamicRangeDB;
            obj.ModelLength = p.Results.ModelLength;
            obj.PipeDiameter = p.Results.PipeDiameter;
            obj.SoundSpeed = p.Results.SoundSpeed;
            obj.EnableDistance = p.Results.EnableDistance;
            obj.KnownBlockage = p.Results.KnownBlockage;
            obj.AutoAlign = p.Results.AutoAlign;
            obj.PreTriggerSeconds = p.Results.PreTriggerSeconds;
            obj.MinStepSeparation = p.Results.MinStepSeparation;
            obj.StimulusPath = char(p.Results.StimulusPath);

            if ~isempty(obj.FilePath)
                obj.loadFile(obj.FilePath);
            end
        end

        function loadFile(obj, filePath)
            % Loads a single audio file and aligns it using the stimulus comb matched filter
            obj.loadRepeatFiles({filePath});
        end

        function loadRepeatFiles(obj, filePaths)
            % Loads 1 or N repeat audio files, aligns each repeat to t = 0.0s (Step 1 origin),
            % stores individual repeats in RepeatDataMatrix, and sets AudioData to the ensemble average.
            if ischar(filePaths) || isstring(filePaths)
                filePaths = {char(filePaths)};
            end
            numReps = length(filePaths);
            obj.FilePath = filePaths{1};

            % Check for sidecar stimulus metadata file (<sample>_stimulus.txt)
            stimHint = obj.StimulusPath;
            if isempty(stimHint)
                [pDir, baseN, ~] = fileparts(obj.FilePath);
                cleanBase = regexprep(baseN, '_rep\d+$', '');
                metaFile = fullfile(pDir, [cleanBase, '_stimulus.txt']);
                if exist(metaFile, 'file')
                    try
                        txt = strtrim(fileread(metaFile));
                        if ~isempty(txt)
                            stimHint = txt;
                        end
                    catch
                    end
                end
            end

            alignedCell = cell(1, numReps);
            refTimes = zeros(1, numReps);
            fsCommon = 44100;

            for r = 1:numReps
                [data, fs] = audioread(filePaths{r});
                if size(data, 2) > 1
                    monoData = mean(data, 2);
                else
                    monoData = data(:);
                end
                fsCommon = fs;
                obj.NumChannels = size(data, 2);

                if r == 1
                    % Resolve active stimulus schedule on the first file
                    obj.ActiveSchedule = obj.resolveStimulusSchedule(monoData, fs, stimHint);
                end

                if obj.AutoAlign
                    [alignedSig, refTime] = obj.alignSignalWithComb(monoData, fs, obj.ActiveSchedule);
                    alignedCell{r} = alignedSig(:);
                    refTimes(r) = refTime;
                else
                    alignedCell{r} = monoData(:);
                    refTimes(r) = NaN;
                end
            end

            obj.SampleRate = fsCommon;
            obj.ReferencePeakTime = refTimes(1);

            % Synchronize lengths across all N repeats
            minLen = min(cellfun(@length, alignedCell));
            repMat = zeros(minLen, numReps);
            for r = 1:numReps
                repMat(:, r) = alignedCell{r}(1:minLen);
            end

            obj.RepeatDataMatrix = repMat;
            obj.RawAudioData = mean(repMat, 2);
            obj.applyTimeWindow();

            if numReps > 1
                repMat = obj.alignRepeatsPerStep(repMat);
                obj.RepeatDataMatrix = repMat;
                obj.RawAudioData = mean(repMat, 2);
                obj.applyTimeWindow();
            end
        end

        function setTimeRange(obj, timeRange)
            obj.TimeRange = timeRange;
            if ~isempty(obj.RawAudioData)
                obj.applyTimeWindow();
            end
        end

        function plotAmplitude(obj, outputFilePath)
            fig = obj.createFigure();
            
            if obj.IsMillisecondScale
                tPlot = (obj.TimeVector - obj.TimeVector(1)) * 1000;
                xUnit = 'ms';
                xLabelText = sprintf('Time (%s) [relative to window start]', xUnit);
            else
                tPlot = obj.TimeVector;
                xUnit = 's';
                if obj.AutoAlign && ~isnan(obj.ReferencePeakTime)
                    xLabelText = sprintf('Time (%s) [Aligned: 1st Peak at 0s, Pre-trigger -%.1fs]', xUnit, obj.PreTriggerSeconds);
                else
                    xLabelText = sprintf('Time (%s)', xUnit);
                end
            end

            hLine = plot(tPlot, obj.AudioData, 'b');
            try
                hLine.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Time', 'XData', '%+.5f s');
                hLine.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Amplitude', 'YData', '%+.5f');
                sampleIdx = 1:length(tPlot);
                hLine.DataTipTemplate.DataTipRows(end + 1) = dataTipTextRow('Sample #', sampleIdx, '%d');
            catch
            end
            xlabel(xLabelText);
            ylabel('Amplitude [FS]');
            
            header = obj.formatTitle(sprintf('Amplitude vs Time (%s)', xUnit));
            title(header, 'Interpreter', 'none');
            grid on;
            xlim([tPlot(1), tPlot(end)]);

            if ~isempty(obj.MaxAmplitude)
                ylim([-obj.MaxAmplitude, obj.MaxAmplitude]);
            end

            if nargin > 1 && ~isempty(outputFilePath)
                obj.exportFigure(fig, outputFilePath);
            end
            obj.closeFigure(fig);
        end

        function plotFrequency(obj, outputFilePath)
            fs = obj.SampleRate;
            upperFreq = obj.resolveMaxFrequency();

            % Option 1: Direct Raw Discrete Step Response (no curvy envelope, no background smearing)
            [stepOnsets, stepEnds, stepFreqs] = obj.detectFrequencySteps();
            numSteps = length(stepFreqs);

            fig = obj.createFigure();
            hold on;

            if numSteps >= 2
                f_steps  = stepFreqs(:)';
                amp_step = zeros(1, numSteps);
                M = length(obj.AudioData);
                winPre  = round(0.015 * fs);
                winPost = round(0.035 * fs);

                for k = 1:numSteps
                    idx1 = max(1, min(M, stepOnsets(k)));
                    idx2 = max(idx1, min(M, stepEnds(k)));
                    L_gate = max(8, idx2 - idx1 + 1);

                    % Center the L_gate excitation window on the step's burst peak
                    w1 = max(1, idx1 - winPre);
                    w2 = min(M, idx2 + winPost);
                    [~, pkRel] = max(abs(obj.AudioData(w1:w2)));
                    pkAbs = w1 + pkRel - 1;
                    c1 = max(1, pkAbs - floor(L_gate / 2));
                    c2 = min(M, c1 + L_gate - 1);
                    sigStep = obj.AudioData(c1:c2);
                    L_step = length(sigStep);

                    % Windowed single-sided FFT normalized by step length L_step
                    nfft = max(4096, 2^nextpow2(L_step));
                    Y = fft(sigStep, nfft);
                    P2 = abs(Y / L_step);
                    P1 = P2(1:floor(nfft/2) + 1);
                    P1(2:end-1) = 2 * P1(2:end-1);
                    f_axis = fs * (0:(nfft/2)) / nfft;

                    bandMask = abs(f_axis - f_steps(k)) <= 100;
                    if any(bandMask)
                        amp_step(k) = max(P1(bandMask));
                    else
                        [~, idxFk] = min(abs(f_axis - f_steps(k)));
                        amp_step(k) = P1(idxFk);
                    end
                end

                % Single clean frequency-domain line with solid markers on measured steps
                hLine = plot(f_steps, amp_step, 'b-o', 'LineWidth', 1.5, ...
                    'MarkerSize', 6, 'MarkerFaceColor', [0.20, 0.60, 1.0], ...
                    'DisplayName', 'Windowed Step FFT |Y(f_k)|');

                try
                    hLine.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Frequency', 'XData', '%.0f Hz');
                    hLine.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Step FFT |Y(f)|', 'YData', '%.5f');
                catch
                end

                maxAmpVal = max(amp_step);
                if maxAmpVal > 0
                    ylim([0, maxAmpVal * 1.25]);
                end
            else
                % Fallback for unsegmented single continuous signals (pure raw FFT)
                L = length(obj.AudioData);
                nfft = 2^nextpow2(L);
                Y = fft(obj.AudioData, nfft);
                P2 = abs(Y / L);
                P1 = P2(1:floor(nfft/2) + 1);
                P1(2:end-1) = 2 * P1(2:end-1);
                f = fs * (0:(nfft/2)) / nfft;

                hLine = plot(f, P1, 'r-', 'LineWidth', 1.2);
                try
                    hLine.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Frequency', 'XData', '%.1f Hz');
                    hLine.DataTipTemplate.DataTipRows(2) = dataTipTextRow('|Amplitude|', 'YData', '%.5f');
                catch
                end
            end

            xlabel('Frequency (Hz)');
            ylabel('Peak Amplitude |s(t)|');
            header = obj.formatTitle('Discrete Frequency Response (Raw Measurements)');
            title(header, 'Interpreter', 'none');
            grid on;
            xlim([0, upperFreq]);

            % Show plane wave cut-off frequency guide
            f_cutoff = 0.586 * obj.SoundSpeed / obj.PipeDiameter;
            if f_cutoff <= upperFreq
                xline(f_cutoff, 'k--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
                    'LineWidth', 1.2, 'LabelVerticalAlignment', 'top');
            end

            if ~isempty(obj.MaxAmplitude)
                ylim([0, obj.MaxAmplitude]);
            end

            if nargin > 1 && ~isempty(outputFilePath)
                obj.exportFigure(fig, outputFilePath);
            end
            obj.closeFigure(fig);
        end

        function plotSpectrogram(obj, outputFilePath)
            fig = obj.createFigure();
            wLen = min(obj.WindowLength, length(obj.AudioData));
            oLen = min(obj.OverlapLength, floor(wLen / 2));

            [~, f, t, ps] = spectrogram(obj.AudioData, wLen, oLen, wLen, obj.SampleRate);
            dB = 10 * log10(abs(ps) + eps);
            maxDB = max(dB(:));
            minDB = maxDB - obj.DynamicRangeDB;

            if obj.AutoAlign && ~isnan(obj.ReferencePeakTime)
                tPlot = t - obj.PreTriggerSeconds;
            else
                tPlot = t;
            end

            imagesc(tPlot, f, dB);
            axis xy;
            colormap jet;
            colorbar;
            caxis([minDB, maxDB]);

            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            
            header = obj.formatTitle('Spectrogram');
            title(header, 'Interpreter', 'none');

            upperFreq = obj.resolveMaxFrequency();
            ylim([0, upperFreq]);

            if nargin > 1 && ~isempty(outputFilePath)
                obj.exportFigure(fig, outputFilePath);
            end
            obj.closeFigure(fig);
        end

        function plotAmplitudeDistance(obj, outputFilePath)
            if isempty(obj.AudioData)
                return;
            end

            fs = obj.SampleRate;
            v = obj.SoundSpeed;
            L = obj.ModelLength;
            T_pipe = 2 * L / v;
            maxT = 1.15 * T_pipe;
            x_grid = linspace(0, 1.15, 600);

            % Detect all tone step onsets in the recording
            envFull = abs(obj.AudioData);
            noiseFloor = median(envFull(1:min(length(envFull), round(0.05 * fs))));
            thresh = max(0.08 * max(envFull), 3 * noiseFloor);

            % Find step onsets by detecting threshold crossings after silence (> 0.1s gap)
            isAbove = envFull > thresh;
            diffAbove = [0; diff(isAbove)];
            risingEdges = find(diffAbove == 1);
            
            % Enforce minimum separation between step onsets
            minSamples = round(obj.MinStepSeparation * fs);
            stepOnsets = [];
            for idx = risingEdges'
                if isempty(stepOnsets) || (idx - stepOnsets(end) >= minSamples)
                    stepOnsets(end + 1) = idx; %#ok<AGROW>
                end
            end

            if isempty(stepOnsets)
                stepOnsets = 1;
            end

            numSteps = length(stepOnsets);
            env_all = zeros(numSteps, length(x_grid));
            maxWinSamples = round(maxT * fs);

            fig = obj.createFigure();
            hold on;

            % Process each frequency step
            for k = 1:numSteps
                idxStart = stepOnsets(k);
                % Locate direct wave peak within initial 8 ms of step
                idxSearchEnd = min(length(envFull), idxStart + round(0.008 * fs));
                [~, relPeak] = max(envFull(idxStart:idxSearchEnd));
                idxDirect = idxStart + relPeak - 1;

                idxEndWin = min(length(obj.AudioData), idxDirect + maxWinSamples);
                sigWin = obj.AudioData(idxDirect:idxEndWin);
                tWin = (0:length(sigWin) - 1) / fs;
                x_raw = (tWin * v) / (2 * L);

                envStep = abs(sigWin);

                % Interpolate to common dimensionless distance grid
                env_all(k, :) = interp1(x_raw, envStep, x_grid, 'linear', 'extrap');

                % Plot individual step envelopes faintly if multi-step
                if numSteps > 1
                    plot(x_grid, env_all(k, :), 'Color', [0.82, 0.88, 0.95], 'LineWidth', 0.8);
                end
            end

            % Compute composite multitone reflection envelope
            mean_env = mean(env_all, 1);
            plot(x_grid, mean_env, 'b-', 'LineWidth', 2.0);

            % Mark Entrance (x_bar = 0) and Pipe End (x_bar = 1.0)
            xline(0.0, 'r--', 'Entrance (x/L = 0.0)', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
            xline(1.0, 'k--', 'Pipe End (x/L = 1.0)', 'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');

            % Mark Known Blockage if provided
            if ~isnan(obj.KnownBlockage) && obj.KnownBlockage > 0 && obj.KnownBlockage < 1.0
                xline(obj.KnownBlockage, 'm-.', ...
                    sprintf('Blockage (x/L = %.2f)', obj.KnownBlockage), ...
                    'LineWidth', 1.5, 'LabelVerticalAlignment', 'top');
            end

            hold off;
            grid on;
            xlim([0, 1.15]);
            xlabel('Dimensionless Distance (x/L)');
            ylabel('Acoustic Reflected Amplitude');

            header = obj.formatTitle(sprintf('Multitone Reflectometry (%d Steps, L = %.1fm, T_{pipe} = %.1fms)', ...
                numSteps, L, T_pipe * 1000));
            title(header, 'Interpreter', 'none');

            if ~isempty(obj.MaxAmplitude)
                ylim([0, obj.MaxAmplitude]);
            else
                ylim([0, max(1.0, max(mean_env) * 1.15)]);
            end

            if nargin > 1 && ~isempty(outputFilePath)
                obj.exportFigure(fig, outputFilePath);
            end
            obj.closeFigure(fig);
        end

        function analyzeAndExport(obj, outputDir)
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            ampFile  = fullfile(outputDir, ['amplitude.', obj.SaveFormat]);
            freqFile = fullfile(outputDir, ['frequency.', obj.SaveFormat]);
            specFile = fullfile(outputDir, ['spectrogram.', obj.SaveFormat]);

            obj.plotAmplitude(ampFile);
            obj.plotFrequency(freqFile);
            obj.plotSpectrogram(specFile);

            if obj.EnableDistance
                distFile = fullfile(outputDir, ['amplitude-distance.', obj.SaveFormat]);
                obj.plotAmplitudeDistance(distFile);
            end
        end

        function exportRawCSV(obj, csvFilePath)
            % Exports aligned time-series and deterministic step metadata to /logged CSV
            % Schema: Time_s, Step_ID, Freq_Input, Amp_1, [Amp_2, ...], Amp_Avg, Amp_SD
            [parentDir, ~, ~] = fileparts(csvFilePath);
            if ~isempty(parentDir) && ~exist(parentDir, 'dir')
                mkdir(parentDir);
            end

            [stepOnsets, stepEnds, stepFreqs] = obj.detectFrequencySteps();
            M = length(obj.AudioData);
            stepIDCol    = zeros(M, 1);
            freqInputCol = zeros(M, 1);

            for k = 1:length(stepOnsets)
                idx1 = max(1, min(M, stepOnsets(k)));
                idx2 = max(idx1, min(M, stepEnds(k)));
                stepIDCol(idx1:idx2)    = k;
                freqInputCol(idx1:idx2) = stepFreqs(k);
            end

            % Prepare Repeat Matrix [M x N]
            if ~isempty(obj.RepeatDataMatrix) && size(obj.RepeatDataMatrix, 1) >= M
                repMat = obj.RepeatDataMatrix(1:M, :);
            else
                repMat = obj.AudioData(:);
            end
            numReps = size(repMat, 2);

            ampAvg = mean(repMat, 2);
            if numReps > 1
                ampSD = std(repMat, 0, 2);
            else
                ampSD = zeros(M, 1);
            end

            % Build dynamic table columns: Time_s, Step_ID, Freq_Input, Amp_1..N, Amp_Avg, Amp_SD
            varNames = [{'Time_s', 'Step_ID', 'Freq_Input'}, ...
                        arrayfun(@(r) sprintf('Amp_%d', r), 1:numReps, 'UniformOutput', false), ...
                        {'Amp_Avg', 'Amp_SD'}];

            colCells = cell(1, 3 + numReps + 2);
            colCells{1} = round(obj.TimeVector(:), 6);
            colCells{2} = stepIDCol;
            colCells{3} = freqInputCol;
            for r = 1:numReps
                colCells{3 + r} = round(repMat(:, r), 6);
            end
            colCells{3 + numReps + 1} = round(ampAvg, 6);
            colCells{3 + numReps + 2} = round(ampSD, 6);

            T = table(colCells{:}, 'VariableNames', varNames);
            writetable(T, csvFilePath);
        end

        function T_raw = loadFromCSV(obj, csvFilePath)
            % Loads a logged CSV file back into AudioAnalyzer
            % Supports both new schema (Time_s, Step_ID, Freq_Input, Amp_1..N, Amp_Avg, Amp_SD)
            % and legacy schema (Time_s, Amplitude, Envelope, Step_ID, Freq_Hz)
            obj.FilePath = csvFilePath;
            T_raw = readtable(csvFilePath);
            colNames = T_raw.Properties.VariableNames;

            obj.TimeVector = T_raw.Time_s(:)';

            if ismember('Amp_Avg', colNames)
                obj.AudioData = T_raw.Amp_Avg(:);
            elseif ismember('Amplitude', colNames)
                obj.AudioData = T_raw.Amplitude(:);
            elseif ismember('Amp_1', colNames)
                obj.AudioData = T_raw.Amp_1(:);
            else
                error('CSV file "%s" does not contain Amp_Avg, Amplitude, or Amp_1 column.', csvFilePath);
            end

            if length(obj.TimeVector) > 1
                dt = median(diff(obj.TimeVector));
                obj.SampleRate = round(1 / dt);
            end
            obj.Duration = length(obj.AudioData) / obj.SampleRate;
            obj.IsMillisecondScale = (obj.Duration <= 1.0);
            if obj.TimeVector(1) < 0
                obj.ReferencePeakTime = abs(obj.TimeVector(1));
                obj.PreTriggerSeconds = abs(obj.TimeVector(1));
            end

            % Reconstruct RepeatDataMatrix from Amp_1..Amp_N columns and phase-align per step
            ampCols = colNames(~cellfun(@isempty, regexp(colNames, '^Amp_\d+$')));
            if ~isempty(ampCols)
                repMat = zeros(height(T_raw), length(ampCols));
                for r = 1:length(ampCols)
                    repMat(:, r) = T_raw.(ampCols{r})(:);
                end
                if size(repMat, 2) > 1
                    repMat = obj.alignRepeatsPerStep(repMat, T_raw);
                    for r = 1:length(ampCols)
                        T_raw.(ampCols{r}) = repMat(:, r);
                    end
                    obj.AudioData = mean(repMat, 2);
                    if ismember('Amp_Avg', colNames)
                        T_raw.Amp_Avg = obj.AudioData;
                    end
                end
                obj.RepeatDataMatrix = repMat;
            else
                obj.RepeatDataMatrix = obj.AudioData(:);
            end

            obj.RawAudioData = obj.AudioData;
            obj.NumChannels = 1;
        end

        function featTable = extractStepFeatures(obj, outputCsvPath, T_raw)
            % Extracts per-frequency step features directly from raw discrete audio samples (no Hilbert transform)
            if nargin >= 3 && ~isempty(T_raw) && ismember('Step_ID', T_raw.Properties.VariableNames)
                colNames = T_raw.Properties.VariableNames;
                if ismember('Freq_Input', colNames)
                    freqVec = T_raw.Freq_Input(:);
                elseif ismember('Freq_Hz', colNames)
                    freqVec = T_raw.Freq_Hz(:);
                else
                    freqVec = zeros(height(T_raw), 1);
                end

                uniqueSteps = unique(T_raw.Step_ID(T_raw.Step_ID > 0), 'stable');
                numSteps = length(uniqueSteps);
                stepOnsets = zeros(numSteps, 1);
                stepEnds   = zeros(numSteps, 1);
                stepFreqs  = zeros(numSteps, 1);
                for k = 1:numSteps
                    mask = (T_raw.Step_ID == uniqueSteps(k));
                    stepOnsets(k) = find(mask, 1, 'first');
                    stepEnds(k)   = find(mask, 1, 'last');
                    stepFreqs(k)  = median(freqVec(mask));
                end
            else
                [stepOnsets, stepEnds, stepFreqs] = obj.detectFrequencySteps();
                numSteps = length(stepOnsets);
            end

            fs = obj.SampleRate;
            M  = length(obj.AudioData);

            Step_ID       = (1:numSteps)';
            Freq_Hz       = zeros(numSteps, 1);
            Onset_Time_s  = zeros(numSteps, 1);
            Duration_s    = zeros(numSteps, 1);
            Step_RMS      = zeros(numSteps, 1);
            Step_Peak_Amp = zeros(numSteps, 1);
            Step_FFT_Amp  = zeros(numSteps, 1);
            Energy_dB     = zeros(numSteps, 1);

            winPre  = round(0.015 * fs);
            winPost = round(0.035 * fs);

            for k = 1:numSteps
                idx1 = max(1, min(M, stepOnsets(k)));
                idx2 = max(idx1, min(M, stepEnds(k)));
                L_gate = max(8, idx2 - idx1 + 1);

                sigStep = obj.AudioData(idx1:idx2);

                % Windowed single-sided FFT centered on the step's active burst
                w1 = max(1, idx1 - winPre);
                w2 = min(M, idx2 + winPost);
                [~, pkRel] = max(abs(obj.AudioData(w1:w2)));
                pkAbs = w1 + pkRel - 1;
                c1 = max(1, pkAbs - floor(L_gate / 2));
                c2 = min(M, c1 + L_gate - 1);
                sigBurst = obj.AudioData(c1:c2);
                L_b = length(sigBurst);
                nfft = max(4096, 2^nextpow2(L_b));
                Y = fft(sigBurst, nfft);
                P2 = abs(Y / L_b);
                P1 = P2(1:floor(nfft/2) + 1);
                P1(2:end-1) = 2 * P1(2:end-1);
                f_axis = fs * (0:(nfft/2)) / nfft;
                bandMask = abs(f_axis - stepFreqs(k)) <= 100;
                if any(bandMask)
                    fftAmp = max(P1(bandMask));
                else
                    [~, idxFk] = min(abs(f_axis - stepFreqs(k)));
                    fftAmp = P1(idxFk);
                end

                Freq_Hz(k)       = stepFreqs(k);
                Onset_Time_s(k)  = round(obj.TimeVector(idx1), 4);
                Duration_s(k)    = round((idx2 - idx1 + 1) / fs, 4);
                Step_RMS(k)      = round(rms(sigStep), 6);
                Step_Peak_Amp(k) = round(max(abs(sigStep)), 6);
                Step_FFT_Amp(k)  = round(fftAmp, 6);
                Energy_dB(k)     = round(20 * log10(Step_RMS(k) + eps), 3);
            end

            featTable = table(Step_ID, Freq_Hz, Onset_Time_s, Duration_s, ...
                Step_RMS, Step_Peak_Amp, Step_FFT_Amp, Energy_dB);

            if nargin >= 2 && ~isempty(outputCsvPath)
                [pDir, ~, ~] = fileparts(outputCsvPath);
                if ~isempty(pDir) && ~exist(pDir, 'dir')
                    mkdir(pDir);
                end
                writetable(featTable, outputCsvPath);
            end
        end

        function profileTable = exportRecordProfile(obj, outputFilePath, T_raw)
            % Evaluates data quality using Range [Min - Max] across all 16 frequencies for
            % Coefficient of Variation (CV%), STDEV (dB), and Peak-to-Peak Repeat Span (dB),
            % exporting record_profile.csv and an interactive box plot (record_profile.fig).
            numReps = size(obj.RepeatDataMatrix, 2);
            durS = obj.Duration;
            maxPeak = max(abs(obj.AudioData));
            clipCount = sum(abs(obj.AudioData) >= 0.98);

            cv_min = NaN; cv_max = NaN;
            sd_min = NaN; sd_max = NaN;
            sp_min = NaN; sp_max = NaN;
            passedSteps = 0;
            numSteps = 0;
            verdict     = 'GRADE_A_EXCELLENT';
            status_cv   = 'N/A';
            status_sd   = 'N/A';
            status_step = 'N/A';

            stepFreqs = (300:100:1800)';
            stepPeaks = [];
            stepDBs   = [];
            step_cvs  = [];
            db_spans  = [];

            if numReps >= 2 && nargin >= 3 && ~isempty(T_raw) && ismember('Step_ID', T_raw.Properties.VariableNames)
                stepIDs = unique(T_raw.Step_ID(T_raw.Step_ID > 0), 'stable');
                numSteps = length(stepIDs);
                ampCols = T_raw.Properties.VariableNames(~cellfun(@isempty, regexp(T_raw.Properties.VariableNames, '^Amp_\d+$')));
                if isempty(ampCols)
                    ampCols = arrayfun(@(k) sprintf('Amp_%d', k), 1:numReps, 'UniformOutput', false);
                end
                actReps = min(numReps, length(ampCols));

                if ismember('Freq_Input', T_raw.Properties.VariableNames)
                    fCol = T_raw.Freq_Input;
                elseif ismember('Freq_Hz', T_raw.Properties.VariableNames)
                    fCol = T_raw.Freq_Hz;
                else
                    fCol = zeros(height(T_raw), 1);
                end

                if numSteps >= 4 && actReps >= 2
                    stepFreqs = zeros(numSteps, 1);
                    stepPeaks = zeros(numSteps, actReps);
                    stepDBs   = zeros(numSteps, actReps);
                    padSamples = round(0.015 * obj.SampleRate);
                    N_rows = height(T_raw);

                    for sIdx = 1:numSteps
                        sID = stepIDs(sIdx);
                        mask = (T_raw.Step_ID == sID);
                        stepFreqs(sIdx) = median(fCol(mask));
                        iStart = find(mask, 1, 'first');
                        iEnd   = find(mask, 1, 'last');
                        idx1 = max(1, iStart - padSamples);
                        idx2 = min(N_rows, iEnd + padSamples);

                        for rIdx = 1:actReps
                            cName = ampCols{rIdx};
                            if ismember(cName, T_raw.Properties.VariableNames)
                                rSig = T_raw.(cName)(idx1:idx2);
                            else
                                rSig = obj.RepeatDataMatrix(idx1:idx2, rIdx);
                            end
                            pkVal  = max(abs(rSig));
                            rmsVal = sqrt(mean(rSig.^2));
                            stepPeaks(sIdx, rIdx) = pkVal;
                            if rmsVal > 0
                                stepDBs(sIdx, rIdx) = 20 * log10(rmsVal);
                            else
                                stepDBs(sIdx, rIdx) = -100;
                            end
                        end
                    end

                    % 1. Per-frequency CV (%) using spectrum median floor to avoid deficit-frequency bias
                    step_means = mean(stepPeaks, 2);
                    ref_denom  = max(step_means, median(step_means));
                    step_pk_sd = std(stepPeaks, 0, 2);
                    step_cvs   = (step_pk_sd ./ max(ref_denom, 1e-6)) * 100;

                    cv_min = min(step_cvs);
                    cv_max = max(step_cvs);

                    % 2. Per-frequency STDEV in dB & Peak-to-Peak Range (Max - Min) in dB
                    step_sds = std(stepDBs, 0, 2);
                    sd_min   = min(step_sds);
                    sd_max   = max(step_sds);

                    db_spans = max(stepDBs, [], 2) - min(stepDBs, [], 2);
                    sp_min   = min(db_spans);
                    sp_max   = max(db_spans);

                    passedSteps = sum(step_cvs <= 5.5);

                    if cv_max <= 5.5
                        status_cv = 'PASS';
                    elseif cv_max <= 10.0
                        status_cv = 'WARNING';
                    else
                        status_cv = 'FAIL';
                    end

                    if sd_max <= 0.50
                        status_sd = 'PASS';
                    elseif sd_max <= 1.00
                        status_sd = 'WARNING';
                    else
                        status_sd = 'FAIL';
                    end

                    if passedSteps == numSteps
                        status_step = 'PASS';
                    elseif sum(step_cvs <= 10.0) == numSteps
                        status_step = 'WARNING';
                    else
                        status_step = 'FAIL';
                    end
                end
            end

            if clipCount > 0
                status_clip = 'FAIL';
                verdict = 'GRADE_C_CLIPPED_RE_RECORD';
            else
                status_clip = 'PASS';
            end

            if clipCount == 0
                if maxPeak < 0.005
                    verdict = 'GRADE_C_NOISY_RE_RECORD';
                elseif numReps >= 2
                    if (isnan(cv_max) || cv_max <= 5.5) && (isnan(sd_max) || sd_max <= 0.50)
                        verdict = 'GRADE_A_EXCELLENT';
                    elseif (cv_max <= 10.0) && (sd_max <= 1.00)
                        verdict = 'GRADE_B_USABLE';
                    else
                        verdict = 'GRADE_C_NOISY_RE_RECORD';
                    end
                else
                    verdict = 'SINGLE_TRIAL_VALID';
                end
            end

            status_overall = 'VALID';
            if startsWith(verdict, 'GRADE_C')
                status_overall = 'RE_RECORD';
            end

            Metric = {
                'Num_Repeats';
                'CV_Range_pct';
                'STDEV_Range_dB';
                'Repeat_Span_Range_dB';
                'Valid_Freq_Steps';
                'Max_Peak_Amplitude';
                'Clipping_Sample_Count';
                'Total_Duration_s';
                'Data_Quality_Verdict'
            };

            Value = {
                sprintf('%d', numReps);
                sprintf('%.2f - %.2f (Span: %.2f)', cv_min, cv_max, cv_max - cv_min);
                sprintf('%.2f - %.2f (Span: %.2f)', sd_min, sd_max, sd_max - sd_min);
                sprintf('%.2f - %.2f', sp_min, sp_max);
                sprintf('%d / %d', passedSteps, numSteps);
                sprintf('%.4f', maxPeak);
                sprintf('%d', clipCount);
                sprintf('%.3f', durS);
                verdict
            };

            Unit = {
                'repeats';
                '%';
                'dB';
                'dB (Max-Min)';
                'steps';
                'normalized (0-1)';
                'samples';
                'seconds';
                'category'
            };

            Criteria = {
                'N >= 5 recommended';
                'Max CV <= 5.5% (Pass), <= 10.0% (Usable)';
                'Max SD <= 0.50 dB (Pass), <= 1.00 dB (Usable)';
                'Max-Min spread across repeats';
                'All 16 frequencies <= 5.5% CV';
                'Peak < 0.98 (No clipping)';
                '0 samples (Pass)';
                '>= 5.0 s';
                'Grade A / B valid for analysis'
            };

            Status = {
                'PASS';
                status_cv;
                status_sd;
                status_sd;
                status_step;
                status_clip;
                status_clip;
                'PASS';
                status_overall
            };

            profileTable = table(Metric, Value, Unit, Criteria, Status);

            if nargin >= 2 && ~isempty(outputFilePath)
                [pDir, ~, ~] = fileparts(outputFilePath);
                if ~isempty(pDir) && ~exist(pDir, 'dir')
                    mkdir(pDir);
                end
                try
                    writetable(profileTable, outputFilePath);
                catch ME
                    warning('Could not write %s (file may be open in another program): %s', outputFilePath, ME.message);
                end

                if ~isempty(stepPeaks) && size(stepPeaks, 2) >= 2
                    profFigPath = fullfile(pDir, 'record_profile.fig');
                    obj.plotRecordProfile(profFigPath, stepFreqs, stepPeaks, stepDBs, step_cvs, db_spans, verdict);
                end
            end
        end

        function plotRecordProfile(obj, outputFigPath, stepFreqs, stepPeaks, stepDBs, step_cvs, db_spans, verdict)
            % Generates a 2-panel interactive Box Plot & Per-Frequency Uncertainty Distribution (.fig)
            fig = obj.createFigure();
            set(fig, 'Name', 'Per-Frequency Repeat Distribution & Box Plot', 'Position', [100, 70, 1180, 780]);

            numSteps = length(stepFreqs);
            actReps  = size(stepPeaks, 2);

            % --- Subplot 1: Box-and-Whisker Plot of Repeat Amplitudes per Frequency ---
            ax1 = subplot(2, 1, 1);
            hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');

            boxHalfW = 22;
            capHalfW = 12;

            for k = 1:numSteps
                f_k  = stepFreqs(k);
                vals = sort(stepPeaks(k, :));
                vMin = vals(1);
                vMax = vals(end);
                vMed = median(vals);
                nV   = length(vals);
                q25  = vals(max(1, round(0.25 * nV)));
                q75  = vals(min(nV, round(0.75 * nV)));

                % Min-Max Range Whisker
                plot(ax1, [f_k, f_k], [vMin, vMax], '-', 'Color', [0.35, 0.45, 0.60], 'LineWidth', 1.4, 'HandleVisibility', 'off');
                plot(ax1, [f_k - capHalfW, f_k + capHalfW], [vMin, vMin], '-', 'Color', [0.35, 0.45, 0.60], 'LineWidth', 1.4, 'HandleVisibility', 'off');
                plot(ax1, [f_k - capHalfW, f_k + capHalfW], [vMax, vMax], '-', 'Color', [0.35, 0.45, 0.60], 'LineWidth', 1.4, 'HandleVisibility', 'off');

                % 25th-75th IQR Box
                boxH = max(q75 - q25, 0.0015);
                patch(ax1, [f_k - boxHalfW, f_k + boxHalfW, f_k + boxHalfW, f_k - boxHalfW], ...
                           [q25, q25, q25 + boxH, q25 + boxH], [0.15, 0.52, 0.85], ...
                           'FaceAlpha', 0.35, 'EdgeColor', [0.10, 0.40, 0.75], 'LineWidth', 1.2, 'HandleVisibility', 'off');

                % Median Line
                plot(ax1, [f_k - boxHalfW, f_k + boxHalfW], [vMed, vMed], '-', 'Color', [0.90, 0.25, 0.15], 'LineWidth', 2.0, 'HandleVisibility', 'off');

                % Individual Repeat Scatter Points
                jitter = linspace(-10, 10, actReps);
                if k == 1
                    plot(ax1, f_k + jitter, stepPeaks(k, :), 'o', 'Color', [0.10, 0.30, 0.55], ...
                        'MarkerFaceColor', [0.20, 0.65, 0.95], 'MarkerSize', 4.5, 'DisplayName', sprintf('Individual Repeats (N = %d)', actReps));
                else
                    plot(ax1, f_k + jitter, stepPeaks(k, :), 'o', 'Color', [0.10, 0.30, 0.55], ...
                        'MarkerFaceColor', [0.20, 0.65, 0.95], 'MarkerSize', 4.5, 'HandleVisibility', 'off');
                end
            end

            % Median Envelope Curve across Frequencies
            medCurve = median(stepPeaks, 2);
            plot(ax1, stepFreqs, medCurve, '-', 'Color', [0.90, 0.25, 0.15], 'LineWidth', 1.5, 'DisplayName', 'Median Response Curve');

            xticks(ax1, stepFreqs);
            xlim(ax1, [min(stepFreqs) - 60, max(stepFreqs) + 60]);
            xlabel(ax1, 'Frequency Step (Hz)');
            ylabel(ax1, 'Step Peak Amplitude');
            title(ax1, obj.formatTitle(sprintf('1. Per-Frequency Box Plot & Repeat Distribution (N = %d Repeats | Verdict: %s)', ...
                actReps, verdict)), 'Interpreter', 'none');
            legend(ax1, 'Location', 'northwest');
            hold(ax1, 'off');

            % --- Subplot 2: Per-Frequency CV (%) & Range Spread ---
            ax2 = subplot(2, 1, 2);
            hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');

            b = bar(ax2, stepFreqs, step_cvs, 0.55, 'FaceColor', 'flat', 'EdgeColor', 'none', 'DisplayName', 'Per-Frequency C.V. (%)');
            for k = 1:numSteps
                if step_cvs(k) <= 5.5
                    b.CData(k, :) = [0.15, 0.68, 0.38]; % Pass Green
                elseif step_cvs(k) <= 10.0
                    b.CData(k, :) = [0.95, 0.60, 0.15]; % Warning Orange
                else
                    b.CData(k, :) = [0.90, 0.22, 0.24]; % Deficit Red
                end
                text(ax2, stepFreqs(k), step_cvs(k) + max(0.25, 0.04 * max(step_cvs)), ...
                    sprintf('%.1f%%\n(\\Delta%.2fdB)', step_cvs(k), db_spans(k)), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7.5);
            end

            yline(ax2, 5.5, '--', 'Pass Limit (5.5%)', 'Color', [0.12, 0.55, 0.30], 'LineWidth', 1.3, 'LabelHorizontalAlignment', 'left');
            xticks(ax2, stepFreqs);
            xlim(ax2, [min(stepFreqs) - 60, max(stepFreqs) + 60]);
            ylim(ax2, [0, max(7.0, max(step_cvs) * 1.28)]);
            xlabel(ax2, 'Frequency Step (Hz)');
            ylabel(ax2, 'Normalized C.V. (%)');
            title(ax2, sprintf('2. Per-Frequency Spread | C.V. Range: [%.2f%% to %.2f%%] | Max-Min dB Span: [%.2f to %.2f dB]', ...
                min(step_cvs), max(step_cvs), min(db_spans), max(db_spans)), 'Interpreter', 'none');
            hold(ax2, 'off');

            if nargin >= 2 && ~isempty(outputFigPath)
                obj.exportFigure(fig, outputFigPath);
            end
            obj.closeFigure(fig);
        end
    end

    methods (Access = private)
        function alignedMat = alignRepeatsPerStep(obj, repMat, T_raw)
            % Phase-aligns all N repeats at each of the 16 frequency steps via local
            % cross-correlation to eliminate soundcard clock drift and destructive phase cancellation.
            [M, N] = size(repMat);
            alignedMat = repMat;
            if N < 2 || M < 100
                return;
            end

            fs = obj.SampleRate;
            if isempty(fs) || fs <= 0
                fs = 44100;
            end

            if nargin >= 3 && ~isempty(T_raw) && ismember('Step_ID', T_raw.Properties.VariableNames)
                uSteps = unique(T_raw.Step_ID(T_raw.Step_ID > 0), 'stable');
                numSteps = length(uSteps);
                stepStarts = zeros(numSteps, 1);
                for k = 1:numSteps
                    stepStarts(k) = find(T_raw.Step_ID == uSteps(k), 1, 'first');
                end
            else
                [stepStarts, ~, ~] = obj.detectFrequencySteps();
                numSteps = length(stepStarts);
            end

            if numSteps < 2
                return;
            end

            winPre  = round(0.015 * fs);
            winPost = round(0.035 * fs);
            maxLag  = round(0.025 * fs);

            for k = 1:numSteps
                i0 = stepStarts(k);
                if k == 1
                    seg1 = 1;
                else
                    seg1 = floor((stepStarts(k-1) + stepStarts(k)) / 2);
                end
                if k == numSteps
                    seg2 = M;
                else
                    seg2 = floor((stepStarts(k) + stepStarts(k+1)) / 2) - 1;
                end

                w1 = max(1, i0 - winPre);
                w2 = min(M, i0 + winPost);
                if w2 <= w1 + 10
                    continue;
                end

                % Pick the repeat whose burst peak is closest to the median peak index
                pkLocs = zeros(1, N);
                for r = 1:N
                    [~, pkLocs(r)] = max(abs(repMat(w1:w2, r)));
                end
                medPk = median(pkLocs);
                [~, refR] = min(abs(pkLocs - medPk));
                refBurst = repMat(w1:w2, refR);

                for r = 1:N
                    if r == refR
                        continue;
                    end
                    candBurst = repMat(w1:w2, r);
                    % Direct dot-product cross-correlation over [-maxLag, +maxLag]
                    bestScore = -inf;
                    bestLag = 0;
                    L_b = length(refBurst);
                    effMaxLag = min(maxLag, floor(L_b / 2));
                    for lag = -effMaxLag:effMaxLag
                        if lag >= 0
                            sc = sum(candBurst(1+lag:L_b) .* refBurst(1:L_b-lag));
                        else
                            sh = -lag;
                            sc = sum(candBurst(1:L_b-sh) .* refBurst(1+sh:L_b));
                        end
                        if sc > bestScore
                            bestScore = sc;
                            bestLag = lag;
                        end
                    end

                    seg = repMat(seg1:seg2, r);
                    L_seg = length(seg);
                    if bestLag > 0 && bestLag < L_seg
                        alignedMat(seg1:seg2, r) = [seg(1+bestLag:end); zeros(bestLag, 1)];
                    elseif bestLag < 0 && (-bestLag) < L_seg
                        sh = -bestLag;
                        alignedMat(seg1:seg2, r) = [zeros(sh, 1); seg(1:end-sh)];
                    end
                end
            end
        end

        function [stepOnsets, stepEnds, stepFreqs] = detectFrequencySteps(obj, ~)
            % Deterministically maps all 16 frequency steps from the active stimulus schedule
            % aligned to t = 0.0s so zero frequency steps are ever filtered or cut out.
            fs = obj.SampleRate;
            M  = length(obj.AudioData);

            if isempty(obj.ActiveSchedule) || ~isfield(obj.ActiveSchedule, 'freqSteps')
                obj.ActiveSchedule = obj.resolveStimulusSchedule(obj.AudioData, fs, obj.StimulusPath);
            end

            sched = obj.ActiveSchedule;
            numSteps = length(sched.freqSteps);

            % Find sample index corresponding to t = 0.0s
            if ~isempty(obj.TimeVector)
                [~, idxZero] = min(abs(obj.TimeVector - 0.0));
            elseif obj.AutoAlign
                idxZero = round(obj.PreTriggerSeconds * fs) + 1;
            else
                idxZero = 1;
            end

            stepOnsets = zeros(numSteps, 1);
            stepEnds   = zeros(numSteps, 1);
            stepFreqs  = sched.freqSteps(:);

            for k = 1:numSteps
                t1 = sched.relOnsets(k);
                t2 = t1 + sched.toneDurs(k);

                idx1 = idxZero + round(t1 * fs);
                idx2 = idxZero + round(t2 * fs) - 1;

                idx1 = max(1, min(M, idx1));
                idx2 = max(idx1, min(M, idx2));

                stepOnsets(k) = idx1;
                stepEnds(k)   = idx2;
            end
        end

        function sched = resolveStimulusSchedule(~, monoData, fs, stimHint)
            % Builds candidate stimulus schedules and selects the active one via hint or comb correlation
            freqs = 300:100:1800;
            nSteps = length(freqs);

            % Candidate 1: 150ms tone + 250ms gap (0.40s step cycle)
            s1 = struct();
            s1.name      = '150ms_250ms';
            s1.freqSteps = freqs;
            s1.toneDurs  = repmat(0.15, 1, nSteps);
            s1.gapDurs   = repmat(0.25, 1, nSteps);
            s1.relOnsets = (0:nSteps-1) * 0.40;

            % Candidate 2: 2-wave impulse (2/f_k) + 0.50s fixed gap
            s2 = struct();
            s2.name      = '2waves_500ms_gap';
            s2.freqSteps = freqs;
            s2.toneDurs  = 2 ./ freqs;
            s2.gapDurs   = repmat(0.50, 1, nSteps);
            s2.relOnsets = [0, cumsum(s2.toneDurs(1:end-1) + s2.gapDurs(1:end-1))];

            % Candidate 3: Legacy 2.0s tone + 1.0s gap (3.0s step cycle)
            s3 = struct();
            s3.name      = '2s_1s';
            s3.freqSteps = freqs;
            s3.toneDurs  = repmat(2.0, 1, nSteps);
            s3.gapDurs   = repmat(1.0, 1, nSteps);
            s3.relOnsets = (0:nSteps-1) * 3.0;

            if ~isempty(stimHint)
                hintLower = lower(char(stimHint));
                if contains(hintLower, '2wave') || contains(hintLower, '500ms')
                    sched = s2;
                    return;
                elseif contains(hintLower, '150ms') || contains(hintLower, '250ms')
                    sched = s1;
                    return;
                elseif contains(hintLower, '2s_1s')
                    sched = s3;
                    return;
                end
            end

            % Auto-detect from recording duration & comb correlation
            recDur = length(monoData) / fs;
            if recDur > 25.0
                sched = s3;
                return;
            end

            % Compare Comb Correlation Score between s1 (150ms/250ms) and s2 (2waves/500ms)
            [~, score1] = AudioAnalyzer.computeCombOrigin(monoData, fs, s1);
            [~, score2] = AudioAnalyzer.computeCombOrigin(monoData, fs, s2);

            if score2 > score1 * 1.05
                sched = s2;
            else
                sched = s1;
            end
        end

        function [alignedSig, refPeakTime] = alignSignalWithComb(obj, monoData, fs, sched)
            % Aligns the recording to the true start of Step 1 (300 Hz) at t = 0.000s
            % using 16-step narrowband comb correlation + high-SNR step back-projection.
            [tOrigin, ~] = AudioAnalyzer.computeCombOrigin(monoData, fs, sched);
            refPeakTime = tOrigin;

            idxOrigin = max(1, round(tOrigin * fs) + 1);
            preSamples = round(obj.PreTriggerSeconds * fs);

            idxStart = idxOrigin - preSamples;
            if idxStart >= 1
                alignedSig = monoData(idxStart:end);
            else
                % Pad leading baseline so t = 0.000s is strictly at sample index (preSamples + 1)
                nPad = 1 - idxStart;
                baselineVal = median(monoData(1:min(length(monoData), max(1, idxOrigin))));
                alignedSig = [repmat(baselineVal, nPad, 1); monoData(:)];
            end
        end
        function header = formatTitle(obj, defaultTitle)
            if ~isempty(obj.TitlePrefix)
                header = {obj.TitlePrefix; defaultTitle};
            else
                header = defaultTitle;
            end
        end

        function applyTimeWindow(obj)
            totalSamples = length(obj.RawAudioData);
            totalDuration = totalSamples / obj.SampleRate;

            if obj.AutoAlign && ~isnan(obj.ReferencePeakTime)
                timeOffset = obj.PreTriggerSeconds;
            else
                timeOffset = 0;
            end

            if isempty(obj.TimeRange)
                obj.AudioData = obj.RawAudioData;
                obj.Duration = totalDuration;
                obj.TimeVector = (0:totalSamples-1) / obj.SampleRate - timeOffset;
                obj.IsMillisecondScale = (totalDuration <= 1.0);
            else
                tStart = max(0, obj.TimeRange(1));
                tEnd   = min(totalDuration, obj.TimeRange(2));
                
                idxStart = max(1, round(tStart * obj.SampleRate) + 1);
                idxEnd   = min(totalSamples, round(tEnd * obj.SampleRate));
                
                obj.AudioData = obj.RawAudioData(idxStart:idxEnd);
                obj.Duration = (idxEnd - idxStart + 1) / obj.SampleRate;
                obj.TimeVector = (idxStart-1 : idxEnd-1) / obj.SampleRate - timeOffset;
                
                obj.IsMillisecondScale = (obj.Duration <= 1.0);
            end
        end

        function upperLimit = resolveMaxFrequency(obj)
            f_cutoff = 0.586 * obj.SoundSpeed / obj.PipeDiameter;
            if ~isempty(obj.MaxFrequency)
                upperLimit = min(obj.MaxFrequency, obj.SampleRate / 2);
            else
                upperLimit = min(f_cutoff, obj.SampleRate / 2);
            end
        end

        function fig = createFigure(obj)
            if obj.VisibleFigures
                fig = figure();
            else
                fig = figure('Visible', 'off');
            end
            
            % Interactive coordinate status bar at the bottom
            uicontrol(fig, 'Style', 'text', 'Tag', 'CoordinateStatusBar', ...
                'String', ' Cursor: Hover over plot to inspect coordinates | Click points for data tips', ...
                'Units', 'normalized', 'Position', [0.02, 0.005, 0.96, 0.035], ...
                'HorizontalAlignment', 'left', 'FontName', 'Consolas', 'FontSize', 9, ...
                'BackgroundColor', [0.94, 0.94, 0.94], 'ForegroundColor', [0.15, 0.15, 0.15]);

            zoom(fig, 'on');
            set(fig, 'WindowScrollWheelFcn', @AudioAnalyzer.onScrollZoom);
            set(fig, 'WindowButtonMotionFcn', @AudioAnalyzer.onMouseMove);
        end

        function exportFigure(obj, fig, targetPath)
            [parentDir, baseName, ext] = fileparts(targetPath);
            if obj.SaveImage
                if strcmpi(obj.SaveFormat, 'svg') || strcmpi(ext, '.svg')
                    saveas(fig, fullfile(parentDir, [baseName, '.svg']), 'svg');
                else
                    saveas(fig, fullfile(parentDir, [baseName, '.', obj.SaveFormat]));
                end
            end

            if obj.SaveFig
                figPath = fullfile(parentDir, [baseName, '.fig']);
                set(fig, 'Visible', 'on');
                set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
                savefig(fig, figPath);
                if ~obj.VisibleFigures
                    set(fig, 'Visible', 'off');
                end
            end
        end

        function closeFigure(obj, fig)
            if ~obj.VisibleFigures && isvalid(fig)
                close(fig);
            end
        end
    end

    methods (Static)
        function onMouseMove(src, ~)
            ax = get(src, 'CurrentAxes');
            if isempty(ax), return; end
            
            sb = findobj(src, 'Tag', 'CoordinateStatusBar');
            if isempty(sb), return; end

            cp = ax.CurrentPoint(1, 1:2);
            x = cp(1);
            y = cp(2);

            xLim = ax.XLim;
            yLim = ax.YLim;

            if x >= xLim(1) && x <= xLim(2) && y >= yLim(1) && y <= yLim(2)
                lines = findobj(ax, 'Type', 'line');
                if ~isempty(lines) && ~isempty(lines(1).XData)
                    xData = lines(1).XData;
                    yData = lines(1).YData;
                    [~, idxNear] = min(abs(xData - x));
                    xNear = xData(idxNear);
                    yNear = yData(idxNear);

                    xLabelStr = string(ax.XLabel.String);
                    if contains(lower(xLabelStr), 'freq')
                        sb.String = sprintf(' Cursor: Freq = %.1f Hz | |Amp| = %.5f  [Nearest: %.1f Hz, Amp: %.5f | Bin #%d]', ...
                            x, y, xNear, yNear, idxNear);
                    else
                        sb.String = sprintf(' Cursor: t = %+.5f s | Amp = %+.5f  [Nearest Sample #%d: t = %+.5f s, Amp = %+.5f]', ...
                            x, y, idxNear, xNear, yNear);
                    end
                else
                    sb.String = sprintf(' Cursor: X = %+.5f | Y = %+.5f', x, y);
                end
            else
                sb.String = ' Cursor: Outside axes boundary';
            end
        end

        function onScrollZoom(src, event)
            ax = get(src, 'CurrentAxes');
            if isempty(ax), return; end
            
            cp = ax.CurrentPoint(1, 1:2);
            xLim = ax.XLim;
            
            scale = 1.15;
            if event.VerticalScrollCount < 0
                factor = 1 / scale;
            else
                factor = scale;
            end
            
            newXLim = cp(1) + (xLim - cp(1)) * factor;
            ax.XLim = newXLim;
        end

        function [tOrigin, maxScore] = computeCombOrigin(monoData, fs, sched)
            % Multi-step comb cross-correlation + high-SNR back-projection
            % Finds the exact time tOrigin (seconds) of Step 1 (300 Hz) even if
            % low frequencies (300-700 Hz) are heavily attenuated by pipe blockage.
            N = length(monoData);
            if N < 10
                tOrigin = 0;
                maxScore = 0;
                return;
            end

            winSmooth = max(1, round(0.003 * fs));
            env = movmean(abs(monoData(:)), winSmooth);

            % Coarse envelope at ~500 Hz (2 ms step) for fast 16-step comb matching
            stepSamples = max(1, round(0.002 * fs));
            envCoarse = env(1:stepSamples:end);
            fsCoarse = fs / stepSamples;

            maxEnv = max(envCoarse);
            if maxEnv <= eps
                tOrigin = 0;
                maxScore = 0;
                return;
            end
            envNorm = envCoarse / maxEnv;

            numSteps = length(sched.freqSteps);
            totalSpan = sched.relOnsets(end) + max(sched.toneDurs(end), 0.030) + 0.10;
            nComb = max(10, round(totalSpan * fsCoarse));
            combTemplate = -0.35 * ones(nComb, 1);

            for k = 1:numSteps
                effDur = max(sched.toneDurs(k), 0.025);
                i1 = max(1, round(sched.relOnsets(k) * fsCoarse) + 1);
                i2 = min(nComb, round((sched.relOnsets(k) + effDur) * fsCoarse));
                if i2 >= i1
                    combTemplate(i1:i2) = 1.0;
                end
            end

            maxLag = min(length(envNorm) - 1, round(3.0 * fsCoarse));
            bestScore = -inf;
            bestLag = 0;

            for lag = 0:maxLag
                segLen = min(nComb, length(envNorm) - lag);
                if segLen < round(0.25 * nComb)
                    break;
                end
                sc = sum(envNorm(lag+1 : lag+segLen) .* combTemplate(1:segLen)) / segLen;
                if sc > bestScore
                    bestScore = sc;
                    bestLag = lag;
                end
            end

            tCoarse = bestLag / fsCoarse;
            maxScore = bestScore;

            % Sub-millisecond refinement via back-projection from high-SNR steps
            t0Est    = nan(numSteps, 1);
            stepSNR  = zeros(numSteps, 1);
            stepPeak = zeros(numSteps, 1);

            for k = 1:numSteps
                tExp = tCoarse + sched.relOnsets(k);
                effDur = max(sched.toneDurs(k), 0.025);

                wStart = max(1, round((tExp - 0.045) * fs) + 1);
                wEnd   = min(N, round((tExp + effDur + 0.030) * fs));
                if wEnd <= wStart
                    continue;
                end

                gStart = max(1, round((tExp - 0.120) * fs) + 1);
                gEnd   = max(gStart, round((tExp - 0.050) * fs));

                pkVal = max(env(wStart:wEnd));
                nfVal = median(env(gStart:gEnd)) + 1e-6;

                stepPeak(k) = pkVal;
                stepSNR(k)  = pkVal / nfVal;

                % Locate leading edge of step k (25% of step envelope peak)
                relCross = find(env(wStart:wEnd) >= 0.25 * pkVal, 1, 'first');
                if ~isempty(relCross)
                    idxEdge = wStart + relCross - 1;
                    idxSearchEnd = min(N, idxEdge + round(0.0035 * fs));
                    [~, relPk] = max(abs(monoData(idxEdge:idxSearchEnd)));
                    idxStepPeak = idxEdge + relPk - 1;
                    t0Est(k) = (idxStepPeak - 1) / fs - sched.relOnsets(k);
                end
            end

            maxStepPk = max(stepPeak);
            validMask = ~isnan(t0Est) & (stepSNR >= 2.5) & (stepPeak >= 0.08 * maxStepPk);

            if any(validMask)
                tOrigin = max(0, median(t0Est(validMask)));
            else
                tOrigin = max(0, tCoarse);
            end
        end
    end
end
