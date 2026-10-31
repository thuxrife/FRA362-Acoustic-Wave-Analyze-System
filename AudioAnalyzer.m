classdef AudioAnalyzer < handle
    % AudioAnalyzer
    % Pure acoustic signal extraction engine:
    % 1. Amplitude vs Time (amplitude.svg / .fig)
    % 2. Frequency Spectrum (frequency.svg / .fig)
    % 3. Spectrogram (spectrogram.svg / .fig)

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
        MaxFrequency double = []          % Upper frequency limit in Hz (empty = full Fs/2)
        NFFT double = []                  % FFT length (defaults to nextpow2(L))
        WindowLength (1, 1) double = 1024 % Spectrogram window size
        OverlapLength (1, 1) double = 512 % Spectrogram overlap
        SaveFormat (1, :) char = 'svg'    % Image format ('svg', 'png', etc.)
        SaveFig (1, 1) logical = true     % Also save interactive MATLAB .fig for zooming/inspecting
        VisibleFigures (1, 1) logical = false % Display figures or run headless
        DynamicRangeDB (1, 1) double = 45 % Contrast threshold in dB below peak
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
            addParameter(p, 'VisibleFigures', obj.VisibleFigures, @islogical);
            addParameter(p, 'DynamicRangeDB', obj.DynamicRangeDB, @isnumeric);
            parse(p, varargin{:});

            obj.TimeRange = p.Results.TimeRange;
            obj.TitlePrefix = p.Results.TitlePrefix;
            obj.MaxAmplitude = p.Results.MaxAmplitude;
            obj.MaxFrequency = p.Results.MaxFrequency;
            obj.WindowLength = p.Results.WindowLength;
            obj.OverlapLength = p.Results.OverlapLength;
            obj.SaveFormat = p.Results.SaveFormat;
            obj.SaveFig = p.Results.SaveFig;
            obj.VisibleFigures = p.Results.VisibleFigures;
            obj.DynamicRangeDB = p.Results.DynamicRangeDB;

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
                xLabelText = sprintf('Time (%s)', xUnit);
            end

            plot(tPlot, obj.AudioData, 'b');
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
            plot(f, P1, 'r');
            xlabel('Frequency (Hz)');
            ylabel('|Amplitude|');
            
            header = obj.formatTitle('Frequency Spectrum (Raw FFT)');
            title(header, 'Interpreter', 'none');
            grid on;

            upperFreq = obj.resolveMaxFrequency();
            xlim([0, upperFreq]);

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

            imagesc(t, f, dB);
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
        end
    end

    methods (Access = private)
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

            if isempty(obj.TimeRange)
                obj.AudioData = obj.RawAudioData;
                obj.Duration = totalDuration;
                obj.TimeVector = (0:totalSamples-1) / obj.SampleRate;
                obj.IsMillisecondScale = (totalDuration <= 1.0);
            else
                tStart = max(0, obj.TimeRange(1));
                tEnd   = min(totalDuration, obj.TimeRange(2));
                
                idxStart = max(1, round(tStart * obj.SampleRate) + 1);
                idxEnd   = min(totalSamples, round(tEnd * obj.SampleRate));
                
                obj.AudioData = obj.RawAudioData(idxStart:idxEnd);
                obj.Duration = (idxEnd - idxStart + 1) / obj.SampleRate;
                obj.TimeVector = (idxStart-1 : idxEnd-1) / obj.SampleRate;
                
                obj.IsMillisecondScale = (obj.Duration <= 1.0);
            end
        end

        function upperLimit = resolveMaxFrequency(obj)
            if ~isempty(obj.MaxFrequency) && obj.MaxFrequency < (obj.SampleRate / 2)
                upperLimit = obj.MaxFrequency;
            else
                upperLimit = obj.SampleRate / 2;
            end
        end

        function fig = createFigure(obj)
            if obj.VisibleFigures
                fig = figure();
            else
                fig = figure('Visible', 'off');
            end
            
            zoom(fig, 'on');
            set(fig, 'WindowScrollWheelFcn', @obj.onScrollZoom);
        end

        function onScrollZoom(~, src, event)
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

        function exportFigure(obj, fig, targetPath)
            [parentDir, baseName, ext] = fileparts(targetPath);
            if strcmpi(ext, '.svg')
                saveas(fig, targetPath, 'svg');
            else
                saveas(fig, targetPath);
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
end
