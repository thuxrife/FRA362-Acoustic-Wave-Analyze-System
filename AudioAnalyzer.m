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

        % Signal Alignment Parameters
        AutoAlign (1, 1) logical = true   % Align time axis using the first spike peak as reference
        PreTriggerSeconds (1, 1) double = 0.2 % Buffer duration (seconds) before first peak to retain
        ReferencePeakTime double = NaN    % Timestamp (seconds in raw audio) of detected reference peak
        MinStepSeparation (1, 1) double = 0.25 % Minimum time (s) between consecutive frequency step onsets
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

            if ~isempty(obj.FilePath)
                obj.loadFile(obj.FilePath);
            end
        end

        function loadFile(obj, filePath)
            obj.FilePath = filePath;
            [data, fs] = audioread(filePath);
            
            if size(data, 2) > 1
                monoData = mean(data, 2);
            else
                monoData = data;
            end

            obj.SampleRate = fs;
            obj.NumChannels = size(data, 2);

            % Auto-alignment to first excitation spike peak with pre-trigger buffer
            if obj.AutoAlign
                try
                    env = abs(hilbert(monoData));
                catch
                    env = abs(monoData);
                end
                
                threshOnset = 0.08 * max(env);
                pOnset = find(env > threshOnset, 1);
                if ~isempty(pOnset)
                    % Locate the immediate first peak of the leading excitation cycle (within 15 ms)
                    searchWin = min(length(env), pOnset + round(0.015 * fs));
                    [~, locs] = findpeaks(env(pOnset:searchWin), 'MinPeakDistance', round(0.002 * fs));
                    if ~isempty(locs)
                        idxPeak = pOnset + locs(1) - 1;
                    else
                        [~, relPeak] = max(env(pOnset:searchWin));
                        idxPeak = pOnset + relPeak - 1;
                    end
                    obj.ReferencePeakTime = (idxPeak - 1) / fs;
                    
                    % Add pre-trigger seconds back of time
                    idxStart = max(1, idxPeak - round(obj.PreTriggerSeconds * fs));
                    monoData = monoData(idxStart:end);
                else
                    obj.ReferencePeakTime = NaN;
                end
            else
                obj.ReferencePeakTime = NaN;
            end

            obj.RawAudioData = monoData;

            obj.applyTimeWindow();
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
            ylabel('Amplitude');
            
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
            L = length(obj.AudioData);
            if isempty(obj.NFFT)
                nfft = 2^nextpow2(L);
            else
                nfft = obj.NFFT;
            end

            Y = fft(obj.AudioData, nfft);
            P2 = abs(Y / L);
            P1 = P2(1:floor(nfft/2) + 1);
            P1(2:end-1) = 2 * P1(2:end-1);
            f = obj.SampleRate * (0:(nfft/2)) / nfft;

            fig = obj.createFigure();
            hLine = plot(f, P1, 'r');
            try
                hLine.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Frequency', 'XData', '%.1f Hz');
                hLine.DataTipTemplate.DataTipRows(2) = dataTipTextRow('|Amplitude|', 'YData', '%.5f');
                binIdx = 1:length(f);
                hLine.DataTipTemplate.DataTipRows(end + 1) = dataTipTextRow('FFT Bin', binIdx, '%d');
            catch
            end
            xlabel('Frequency (Hz)');
            ylabel('|Amplitude|');
            
            header = obj.formatTitle('Frequency Spectrum (Raw FFT)');
            title(header, 'Interpreter', 'none');
            grid on;

            upperFreq = obj.resolveMaxFrequency();
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

                try
                    envStep = abs(hilbert(sigWin));
                catch
                    envStep = abs(sigWin);
                end

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
            % Exports aligned raw time-series and step metadata to /logged CSV
            % Columns: Time_s, Amplitude, Envelope, Step_ID, Freq_Hz
            [parentDir, ~, ~] = fileparts(csvFilePath);
            if ~isempty(parentDir) && ~exist(parentDir, 'dir')
                mkdir(parentDir);
            end

            try
                env = abs(hilbert(obj.AudioData));
            catch
                env = abs(obj.AudioData);
            end

            [stepOnsets, stepEnds, stepFreqs] = obj.detectFrequencySteps(env);
            N = length(obj.AudioData);
            stepIDCol = zeros(N, 1);
            freqCol   = zeros(N, 1);

            for k = 1:length(stepOnsets)
                idx1 = stepOnsets(k);
                idx2 = stepEnds(k);
                stepIDCol(idx1:idx2) = k;
                freqCol(idx1:idx2)   = stepFreqs(k);
            end

            T = table( ...
                round(obj.TimeVector(:), 6), ...
                round(obj.AudioData(:), 6), ...
                round(env(:), 6), ...
                stepIDCol, ...
                freqCol, ...
                'VariableNames', {'Time_s', 'Amplitude', 'Envelope', 'Step_ID', 'Freq_Hz'});

            writetable(T, csvFilePath);
        end

        function T_raw = loadFromCSV(obj, csvFilePath)
            % Loads a logged raw CSV file back into AudioAnalyzer
            obj.FilePath = csvFilePath;
            T_raw = readtable(csvFilePath);

            obj.TimeVector = T_raw.Time_s(:)';
            obj.AudioData  = T_raw.Amplitude(:);
            obj.RawAudioData = obj.AudioData;
            obj.NumChannels = 1;

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
        end

        function featTable = extractStepFeatures(obj, outputCsvPath, T_raw)
            % Extracts per-frequency step features (e.g. 16 frequency steps)
            if nargin >= 3 && ~isempty(T_raw) && ismember('Step_ID', T_raw.Properties.VariableNames)
                try
                    env = T_raw.Envelope(:);
                catch
                    env = abs(hilbert(obj.AudioData));
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
                    stepFreqs(k)  = median(T_raw.Freq_Hz(mask));
                end
            else
                try
                    env = abs(hilbert(obj.AudioData));
                catch
                    env = abs(obj.AudioData);
                end
                [stepOnsets, stepEnds, stepFreqs] = obj.detectFrequencySteps(env);
                numSteps = length(stepOnsets);
            end

            fs = obj.SampleRate;

            Step_ID          = (1:numSteps)';
            Freq_Hz          = zeros(numSteps, 1);
            Onset_Time_s     = zeros(numSteps, 1);
            Duration_s       = zeros(numSteps, 1);
            Step_RMS         = zeros(numSteps, 1);
            Step_Peak_Amp    = zeros(numSteps, 1);
            Energy_dB        = zeros(numSteps, 1);

            for k = 1:numSteps
                idx1 = stepOnsets(k);
                idx2 = stepEnds(k);
                sigStep = obj.AudioData(idx1:idx2);
                envStep = env(idx1:idx2);

                Freq_Hz(k)       = stepFreqs(k);
                Onset_Time_s(k)  = round(obj.TimeVector(idx1), 4);
                Duration_s(k)    = round((idx2 - idx1 + 1) / fs, 4);
                Step_RMS(k)      = round(rms(sigStep), 6);
                Step_Peak_Amp(k) = round(max(envStep), 6);
                Energy_dB(k)     = round(20 * log10(Step_RMS(k) + eps), 3);
            end

            featTable = table(Step_ID, Freq_Hz, Onset_Time_s, Duration_s, ...
                Step_RMS, Step_Peak_Amp, Energy_dB);

            if nargin >= 2 && ~isempty(outputCsvPath)
                [pDir, ~, ~] = fileparts(outputCsvPath);
                if ~isempty(pDir) && ~exist(pDir, 'dir')
                    mkdir(pDir);
                end
                writetable(featTable, outputCsvPath);
            end
        end
    end

    methods (Access = private)
        function [stepOnsets, stepEnds, stepFreqs] = detectFrequencySteps(obj, env)
            fs = obj.SampleRate;
            smoothEnv = movmean(env, max(1, round(0.008 * fs)));
            noiseFloor = median(smoothEnv(1:min(length(smoothEnv), round(0.1 * fs))));
            thresh = max(0.08 * max(smoothEnv), 3.5 * noiseFloor);

            isAbove = smoothEnv > thresh;
            diffAbove = [0; diff(isAbove(:))];
            risingEdges = find(diffAbove == 1);

            minSamples = round(obj.MinStepSeparation * fs);
            stepOnsets = [];
            for idx = risingEdges'
                if isempty(stepOnsets) || (idx - stepOnsets(end) >= minSamples)
                    stepOnsets(end + 1, 1) = idx; %#ok<AGROW>
                end
            end

            if isempty(stepOnsets)
                stepOnsets = 1;
            end

            numSteps = length(stepOnsets);
            stepEnds  = zeros(numSteps, 1);
            stepFreqs = zeros(numSteps, 1);

            for k = 1:numSteps
                idx1 = stepOnsets(k);
                if k < numSteps
                    maxIdx = stepOnsets(k + 1) - 1;
                else
                    maxIdx = length(smoothEnv);
                end

                % Find where step tone drops back below threshold
                subBelow = find(~isAbove(idx1:maxIdx), 1, 'first');
                if ~isempty(subBelow) && subBelow > round(0.02 * fs)
                    idx2 = idx1 + subBelow - 1;
                else
                    idx2 = min(maxIdx, idx1 + round(0.8 * (maxIdx - idx1)));
                end
                stepEnds(k) = max(idx1 + 1, idx2);

                % Estimate dominant excitation frequency via FFT
                seg = obj.AudioData(idx1:stepEnds(k));
                Lseg = length(seg);
                nfft = 2^nextpow2(max(1024, Lseg));
                Y = abs(fft(seg, nfft));
                P1 = Y(1:floor(nfft/2) + 1);
                fVec = fs * (0:(nfft/2)) / nfft;
                validF = (fVec >= 250) & (fVec <= 2500);
                if any(validF)
                    subP = P1(validF);
                    subF = fVec(validF);
                    [~, iMax] = max(subP);
                    rawF = subF(iMax);
                    if abs(rawF - round(rawF / 100) * 100) <= 22
                        stepFreqs(k) = round(rawF / 100) * 100;
                    else
                        stepFreqs(k) = round(rawF);
                    end
                end
            end

            % Filter out spurious low-energy reverb tails between steps
            stepRmsVec = zeros(numSteps, 1);
            for k = 1:numSteps
                stepRmsVec(k) = rms(obj.AudioData(stepOnsets(k):stepEnds(k)));
            end
            validSteps = (stepRmsVec >= 0.20 * median(stepRmsVec)) & (stepFreqs >= 250);
            stepOnsets = stepOnsets(validSteps);
            stepEnds   = stepEnds(validSteps);
            stepFreqs  = stepFreqs(validSteps);
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
    end
end
