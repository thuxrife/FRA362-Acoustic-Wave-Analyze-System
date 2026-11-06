function record_acoustic_sample()
%% Acoustic Rig Audio Interface & Oscilloscope GUI
% Modern studio-grade interface for hardware selection, synchronized playback/capture,
% live waveform & spectrum monitoring, VU metering, and 1-click pipeline execution.
%
% Usage:
%   record_acoustic_sample        % Launches the interactive GUI

    %% 1. Default Configuration & Audio Discovery
    FS               = 44100;
    BITS             = 16;
    DEFAULT_STIMULUS = 'sound_input/stepped_tones_100mm_150ms_250ms.wav';
    LEGACY_STIMULUS  = 'sound_input/stepped_tones_100mm_2s_1s.wav';
    OUTPUT_ROOT      = 'mp3';

    % Determine stimulus file
    stimFile = DEFAULT_STIMULUS;
    if ~exist(stimFile, 'file') && exist(LEGACY_STIMULUS, 'file')
        stimFile = LEGACY_STIMULUS;
    end
    stimDuration = 0;
    stimSig = [];
    stimFs  = FS;
    if exist(stimFile, 'file')
        [stimSig, stimFs] = audioread(stimFile);
        stimDuration = length(stimSig) / stimFs;
    end

    % Hardware Query with Driver Reset
    try
        if exist('audiodevreset', 'builtin') || exist('audiodevreset', 'file')
            audiodevreset; % Flush MATLAB audio driver cache to detect newly plugged devices
        end
        devs = audiodevinfo;
    catch
        devs = struct('input', [], 'output', []);
    end

    if isempty(devs.input)
        micNames = {'[None] No Microphones Detected (Click Rescan)'};
    else
        micNames = cell(1, length(devs.input));
        for k = 1:length(devs.input)
            micNames{k} = sprintf('[%d] %s', devs.input(k).ID, devs.input(k).Name);
        end
    end

    if isempty(devs.output)
        spkNames = {'[None] No Speakers Detected (Click Rescan)'};
    else
        spkNames = cell(1, length(devs.output));
        for k = 1:length(devs.output)
            spkNames{k} = sprintf('[%d] %s', devs.output(k).ID, devs.output(k).Name);
        end
    end

    % Session state storage
    state = struct();
    state.recordedData  = [];
    state.FS            = FS;
    state.savedFilePath = '';
    state.isRecording   = false;
    state.activePlayer  = [];

    %% 2. Construct Modern Audio Interface Figure
    fig = figure('Name', 'Acoustic Rig Audio Interface & Monitor', ...
        'NumberTitle', 'off', ...
        'Color', [0.11, 0.12, 0.14], ...
        'Position', [120, 80, 1180, 720], ...
        'MenuBar', 'none', ...
        'ToolBar', 'figure', ...
        'Resize', 'on', ...
        'CloseRequestFcn', @onClose);

    % Color Theme Palette
    cPanelBg   = [0.15, 0.16, 0.19];
    cControlBg = [0.20, 0.22, 0.26];
    cTextPri   = [0.92, 0.94, 0.96];
    cTextSec   = [0.65, 0.68, 0.74];
    cAccentGrn = [0.12, 0.68, 0.38];
    cAccentCyn = [0.00, 0.82, 0.95];
    cAccentRed = [0.90, 0.22, 0.24];
    cPlotBg    = [0.07, 0.08, 0.09];

    %% 3. Control Panel (Left Column: x=15, width=320)
    pnlCtrl = uipanel('Parent', fig, ...
        'Title', ' HARDWARE & SESSION CONTROLS ', ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'ForegroundColor', cTextPri, ...
        'BackgroundColor', cPanelBg, ...
        'HighlightColor', [0.25, 0.28, 0.32], ...
        'Units', 'pixels', ...
        'Position', [15, 15, 330, 690]);

    % Microphone Selector
    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Microphone Input:', ...
        'Position', [15, 642, 290, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    popMic = uicontrol('Parent', pnlCtrl, 'Style', 'popupmenu', 'String', micNames, ...
        'Position', [15, 616, 295, 26], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'Value', 1);

    % Speaker Selector
    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Speaker Output:', ...
        'Position', [15, 586, 290, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    popSpk = uicontrol('Parent', pnlCtrl, 'Style', 'popupmenu', 'String', spkNames, ...
        'Position', [15, 560, 295, 26], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'Value', 1);

    % Rescan Hardware Button
    btnRescan = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Rescan Audio Devices (Refresh)', ...
        'Position', [15, 526, 295, 28], ...
        'BackgroundColor', [0.20, 0.28, 0.38], 'ForegroundColor', [0.85, 0.92, 1.0], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Callback', @onRescanClick);

    % Mode Selector
    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Operational Mode:', ...
        'Position', [15, 496, 290, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    modeOptions = {
        'Mode 1: Automated Test (Play + Record)'
        'Mode 2: Record Only (External Stimulus)'
        'Mode 3: Sound Check (Speaker Play Only)'
    };
    popMode = uicontrol('Parent', pnlCtrl, 'Style', 'popupmenu', 'String', modeOptions, ...
        'Position', [15, 470, 295, 26], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'Value', 1);

    % Trial & Sample Name Inputs
    todayStr = char(datetime('now', 'Format', 'yyyy-MM-dd'));
    defaultTrial = sprintf('%s-sound-sample', todayStr);

    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Trial Folder (inside mp3/):', ...
        'Position', [15, 440, 290, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    txtTrial = uicontrol('Parent', pnlCtrl, 'Style', 'edit', 'String', defaultTrial, ...
        'Position', [15, 416, 295, 24], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'HorizontalAlignment', 'left');

    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Sample Name (.wav):', ...
        'Position', [15, 388, 290, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    txtSample = uicontrol('Parent', pnlCtrl, 'Style', 'edit', 'String', 'sound_sample_01', ...
        'Position', [15, 364, 295, 24], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'HorizontalAlignment', 'left');

    % Stimulus Track Info
    [~, stimBase, stimExt] = fileparts(stimFile);
    uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', sprintf('Stimulus: %s%s (%.1fs, 16 steps)', stimBase, stimExt, stimDuration), ...
        'Position', [15, 336, 295, 22], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', [0.45, 0.75, 0.95], 'FontSize', 8);

    % Action Buttons
    btnRecord = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'START RECORDING / TEST', ...
        'Position', [15, 284, 295, 44], ...
        'BackgroundColor', cAccentGrn, 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'Callback', @onRecordClick);

    btnPlay = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Play Recorded Audio', ...
        'Position', [15, 244, 142, 34], ...
        'BackgroundColor', cControlBg, 'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'Enable', 'off', ...
        'Callback', @onPlayRecorded);

    btnRetake = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Clear / Retake', ...
        'Position', [168, 244, 142, 34], ...
        'BackgroundColor', cControlBg, 'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'Enable', 'off', ...
        'Callback', @onRetakeClick);

    % Status Readout Badge
    lblStatus = uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', 'STATUS: READY', ...
        'Position', [15, 200, 295, 36], ...
        'BackgroundColor', [0.18, 0.20, 0.24], ...
        'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'FontWeight', 'bold');

    % Numerical Diagnostics Box
    txtDiag = uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', sprintf('Duration : -- s\nPeak Amp : --\nRMS Level: -- dBFS\nClipping : NONE'), ...
        'Position', [15, 114, 295, 80], ...
        'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextSec, ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    % 1-Click Pipeline Button
    btnPipeline = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'RUN MASTER PIPELINE (main.m)', ...
        'Position', [15, 22, 295, 42], ...
        'BackgroundColor', [0.18, 0.45, 0.78], 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Callback', @onRunPipeline);

    %% 4. GraphView & Meter Panel (Right Area: x=360, width=805)
    pnlGraph = uipanel('Parent', fig, ...
        'Title', ' ACOUSTIC MONITOR & OSCILLOSCOPE GRAPHVIEW ', ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'ForegroundColor', cTextPri, ...
        'BackgroundColor', cPanelBg, ...
        'HighlightColor', [0.25, 0.28, 0.32], ...
        'Units', 'pixels', ...
        'Position', [360, 15, 805, 690]);

    % 4A. Waveform Oscilloscope Axes (Top Graph)
    axWave = axes('Parent', pnlGraph, 'Units', 'pixels', ...
        'Position', [65, 375, 625, 260], ...
        'Color', cPlotBg, 'XColor', cTextSec, 'YColor', cTextSec, ...
        'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    grid(axWave, 'on'); box(axWave, 'on');
    title(axWave, 'Raw Waveform Oscilloscope s(t)', 'Color', cTextPri, 'FontSize', 10, 'FontWeight', 'bold');
    xlabel(axWave, 'Time (seconds)', 'Color', cTextSec, 'FontSize', 9);
    ylabel(axWave, 'Amplitude', 'Color', cTextSec, 'FontSize', 9);
    ylim(axWave, [-1.05, 1.05]);
    hWaveLine = line(axWave, [0, 1], [0, 0], 'Color', cAccentCyn, 'LineWidth', 1.0);

    % Coordinate Status Bar (Option C) below Waveform
    lblCoord = uicontrol('Parent', pnlGraph, 'Style', 'text', ...
        'String', '  [Coordinate Tracker] Hover cursor over waveform to view sample details', ...
        'Position', [65, 342, 625, 22], ...
        'BackgroundColor', [0.10, 0.11, 0.13], ...
        'ForegroundColor', [0.45, 0.85, 0.95], ...
        'FontSize', 8, 'HorizontalAlignment', 'left');

    % 4B. Instant Frequency Spectrum Axes (Bottom Graph)
    axSpec = axes('Parent', pnlGraph, 'Units', 'pixels', ...
        'Position', [65, 55, 625, 240], ...
        'Color', cPlotBg, 'XColor', cTextSec, 'YColor', cTextSec, ...
        'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    grid(axSpec, 'on'); box(axSpec, 'on');
    title(axSpec, 'Acoustic Frequency Spectrum |S(f)| (0 - 2200 Hz)', ...
        'Color', cTextPri, 'FontSize', 10, 'FontWeight', 'bold');
    xlabel(axSpec, 'Frequency (Hz)', 'Color', cTextSec, 'FontSize', 9);
    ylabel(axSpec, 'Magnitude (dBFS)', 'Color', cTextSec, 'FontSize', 9);
    xlim(axSpec, [0, 2200]);
    ylim(axSpec, [-90, 5]);
    hSpecLine = line(axSpec, [0, 1], [-90, -90], 'Color', [0.95, 0.75, 0.20], 'LineWidth', 1.1);

    % 4C. Vertical VU Level Meter Axes
    axMeter = axes('Parent', pnlGraph, 'Units', 'pixels', ...
        'Position', [725, 100, 42, 490], ...
        'Color', [0.05, 0.05, 0.06], 'XColor', 'none', 'YColor', cTextSec, ...
        'YAxisLocation', 'right');
    ylim(axMeter, [-60, 0]);
    ylabel(axMeter, 'Level (dBFS)', 'Color', cTextSec, 'FontSize', 8);
    yticks(axMeter, [-60, -48, -36, -24, -18, -12, -6, -3, 0]);
    box(axMeter, 'on'); hold(axMeter, 'on');
    hMeterBar = bar(axMeter, 0, -60, 0.7, 'FaceColor', cAccentGrn, 'EdgeColor', 'none');

    % Peak Clipping LED Badge above VU Meter
    lblClip = uicontrol('Parent', pnlGraph, 'Style', 'text', ...
        'String', 'CLIP', ...
        'Position', [718, 605, 56, 24], ...
        'BackgroundColor', [0.25, 0.08, 0.08], ...
        'ForegroundColor', [0.55, 0.55, 0.55], ...
        'FontSize', 9, 'FontWeight', 'bold');

    % Set window mouse motion callback for Coordinate Tracker
    set(fig, 'WindowButtonMotionFcn', @onMouseMove);

    %% 5. Interactive Callbacks & Operational Logic

    function onMouseMove(~, ~)
        if isempty(state.recordedData)
            return;
        end
        cp = get(axWave, 'CurrentPoint');
        xPos = cp(1, 1);
        yPos = cp(1, 2);
        xLim = xlim(axWave);
        yLim = ylim(axWave);

        if xPos >= xLim(1) && xPos <= xLim(2) && yPos >= yLim(1) && yPos <= yLim(2)
            sampleIdx = round(xPos * state.FS) + 1;
            totalN = length(state.recordedData);
            if sampleIdx >= 1 && sampleIdx <= totalN
                sampleAmp = state.recordedData(sampleIdx);
                set(lblCoord, 'String', sprintf('  [TRACKER] Time: %7.4f s | Amp: %+7.4f | Sample: #%d / %d', ...
                    xPos, sampleAmp, sampleIdx, totalN));
            end
        end
    end

    function onRescanClick(~, ~)
        try
            % Purge MATLAB internal audio cache to detect newly attached Bluetooth & USB endpoints
            if exist('audiodevreset', 'builtin') || exist('audiodevreset', 'file')
                audiodevreset;
            end
            devs = audiodevinfo;
        catch ME
            errordlg(sprintf('Hardware scan error: %s', ME.message), 'Scan Error');
            return;
        end

        % Update Microphone Dropdown
        if isempty(devs.input)
            micNames = {'[None] No Microphones Detected (Check connection)'};
            set(popMic, 'String', micNames, 'Value', 1);
        else
            micNames = cell(1, length(devs.input));
            for k = 1:length(devs.input)
                micNames{k} = sprintf('[%d] %s', devs.input(k).ID, devs.input(k).Name);
            end
            oldMic = get(popMic, 'Value');
            set(popMic, 'String', micNames, 'Value', min(max(oldMic, 1), length(devs.input)));
        end

        % Update Speaker Dropdown
        if isempty(devs.output)
            spkNames = {'[None] No Speakers Detected (Check connection)'};
            set(popSpk, 'String', spkNames, 'Value', 1);
        else
            spkNames = cell(1, length(devs.output));
            for k = 1:length(devs.output)
                spkNames{k} = sprintf('[%d] %s', devs.output(k).ID, devs.output(k).Name);
            end
            oldSpk = get(popSpk, 'Value');
            set(popSpk, 'String', spkNames, 'Value', min(max(oldSpk, 1), length(devs.output)));
        end

        nMic = length(devs.input);
        nSpk = length(devs.output);
        set(lblStatus, 'String', sprintf('RESCANNED: %d MIC(S), %d SPK(S)', nMic, nSpk), ...
            'BackgroundColor', [0.12, 0.45, 0.35]);
        fprintf('[Hardware Rescan] Detected %d microphone(s) and %d speaker(s).\n', nMic, nSpk);
    end

    function onRecordClick(~, ~)
        if state.isRecording
            return;
        end

        % Validate hardware presence
        if isempty(devs.input) || isempty(devs.output)
            errordlg('No active microphone or speaker detected. Please connect your hardware and click "Rescan Audio Devices".', 'Hardware Missing');
            return;
        end

        state.isRecording = true;

        % Gather hardware settings
        micIdx = get(popMic, 'Value');
        spkIdx = get(popSpk, 'Value');
        modeVal = get(popMode, 'Value');
        selectedMicID = devs.input(micIdx).ID;
        selectedSpkID = devs.output(spkIdx).ID;

        trialName  = strtrim(get(txtTrial, 'String'));
        sampleName = strtrim(get(txtSample, 'String'));
        if isempty(trialName), trialName = defaultTrial; end
        if isempty(sampleName), sampleName = 'sound_sample_01'; end

        % Prepare target path
        targetDir = fullfile(OUTPUT_ROOT, trialName);
        if ~exist(targetDir, 'dir'), mkdir(targetDir); end
        targetWav = fullfile(targetDir, [sampleName, '.wav']);

        % Update UI state
        set(lblStatus, 'String', 'STATUS: PREPARING RIG...', 'BackgroundColor', [0.65, 0.45, 0.10]);
        set(btnRecord, 'Enable', 'off');
        set(btnPipeline, 'Enable', 'off');
        drawnow;

        try
            switch modeVal
                case 1 % Mode 1: Automated Test (Synchronous Play + Record)
                    if isempty(stimSig)
                        error('Excitation sound file not found. Run generate_sound_input.m first.');
                    end
                    set(lblStatus, 'String', 'STATUS: RECORDING & EXCITING PIPE...', ...
                        'BackgroundColor', [0.75, 0.20, 0.15]);
                    drawnow;

                    recObj = audiorecorder(FS, BITS, 1, selectedMicID);
                    player = audioplayer(stimSig, stimFs, BITS, selectedSpkID);

                    record(recObj);
                    pause(0.2);          % 200ms pre-excitation lead-in
                    playblocking(player); % Synchronous playback through duct
                    pause(0.5);          % 500ms duct decay / reverberation tail
                    stop(recObj);

                    recordedData = getaudiodata(recObj);

                case 2 % Mode 2: Record Only
                    recTime = 7.0;
                    set(lblStatus, 'String', sprintf('STATUS: RECORDING ONLY (%.1fs)...', recTime), ...
                        'BackgroundColor', [0.75, 0.20, 0.15]);
                    drawnow;

                    recObj = audiorecorder(FS, BITS, 1, selectedMicID);
                    recordblocking(recObj, recTime);
                    recordedData = getaudiodata(recObj);

                case 3 % Mode 3: Sound Check (Speaker Only)
                    set(lblStatus, 'String', 'STATUS: PLAYING SOUND CHECK...', ...
                        'BackgroundColor', [0.20, 0.50, 0.70]);
                    drawnow;

                    player = audioplayer(stimSig, stimFs, BITS, selectedSpkID);
                    playblocking(player);

                    set(lblStatus, 'String', 'STATUS: SOUND CHECK FINISHED', ...
                        'BackgroundColor', [0.18, 0.20, 0.24]);
                    set(btnRecord, 'Enable', 'on');
                    set(btnPipeline, 'Enable', 'on');
                    state.isRecording = false;
                    return;
            end

            % Process and validate captured data
            state.recordedData = recordedData;
            state.savedFilePath = targetWav;

            wasReplaced = exist(targetWav, 'file') > 0;

            % Write audio file (automatically replaces/overwrites existing sample)
            audiowrite(targetWav, recordedData, FS);

            % Update Waveform Oscilloscope Display
            tAxis = (0:length(recordedData)-1)' / FS;
            set(hWaveLine, 'XData', tAxis, 'YData', recordedData);
            xlim(axWave, [0, max(tAxis(end), 0.01)]);
            peakVal = max(abs(recordedData));
            maxDisplay = max(1.05, peakVal * 1.1);
            ylim(axWave, [-maxDisplay, maxDisplay]);

            % Update Frequency Spectrum Display
            N = length(recordedData);
            Nfft = 2^nextpow2(N);
            fAxis = (0:Nfft/2) * (FS / Nfft);
            X = abs(fft(recordedData, Nfft)) / N;
            X_half = X(1:Nfft/2+1);
            X_dB = 20 * log10(X_half + eps);
            set(hSpecLine, 'XData', fAxis, 'YData', X_dB);
            xlim(axSpec, [0, 2200]);
            ylim(axSpec, [-90, max(max(X_dB) + 5, 0)]);

            % Compute Quality Diagnostics
            rmsVal = rms(recordedData);
            rmsDB  = 20 * log10(rmsVal + eps);
            peakDB = 20 * log10(peakVal + eps);
            durVal = length(recordedData) / FS;

            % Update VU Level Meter Bar
            set(hMeterBar, 'YData', max(peakDB, -60));
            if peakDB >= -3
                set(hMeterBar, 'FaceColor', cAccentRed);
            elseif peakDB >= -12
                set(hMeterBar, 'FaceColor', [0.95, 0.75, 0.15]);
            else
                set(hMeterBar, 'FaceColor', cAccentGrn);
            end

            % Update Clipping LED and Status Readout
            isClipped = (peakVal >= 0.95);
            isLow     = (peakVal < 0.02);

            if isClipped
                set(lblClip, 'BackgroundColor', cAccentRed, 'ForegroundColor', [1, 1, 1]);
                clipStr = 'DETECTED (>= 0.95)';
                set(lblStatus, 'String', 'WARNING: CLIPPING! REDUCE GAIN', ...
                    'BackgroundColor', cAccentRed);
            elseif isLow
                set(lblClip, 'BackgroundColor', [0.25, 0.08, 0.08], 'ForegroundColor', [0.55, 0.55, 0.55]);
                clipStr = 'LOW / MUTED (< 0.02)';
                set(lblStatus, 'String', 'WARNING: SIGNAL VERY WEAK', ...
                    'BackgroundColor', [0.70, 0.50, 0.10]);
            else
                set(lblClip, 'BackgroundColor', [0.25, 0.08, 0.08], 'ForegroundColor', [0.55, 0.55, 0.55]);
                clipStr = 'NONE (Clean)';
                set(lblStatus, 'String', 'STATUS: CAPTURED & SAVED OK', ...
                    'BackgroundColor', [0.12, 0.55, 0.28]);
            end

            if wasReplaced
                savedStr = sprintf('%s (Replaced/Overwritten)', [sampleName, '.wav']);
                actionStr = 'REPLACED';
            else
                savedStr = sprintf('%s (Saved)', [sampleName, '.wav']);
                actionStr = 'SAVED';
            end

            set(txtDiag, 'String', sprintf('Duration : %.2f s (%d smp)\nPeak Amp : %.4f (%.1f dBFS)\nRMS Level: %.4f (%.1f dBFS)\nClipping : %s\nTarget   : %s', ...
                durVal, length(recordedData), peakVal, peakDB, rmsVal, rmsDB, clipStr, savedStr));

            set(btnPlay, 'Enable', 'on');
            set(btnRetake, 'Enable', 'on');

            fprintf('[Audio Interface] Successfully %s audio:\n  %s\n', actionStr, targetWav);

        catch ME
            errordlg(sprintf('Recording error: %s', ME.message), 'Capture Failed');
            set(lblStatus, 'String', 'STATUS: ERROR OCCURRED', 'BackgroundColor', cAccentRed);
        end

        set(btnRecord, 'Enable', 'on');
        set(btnPipeline, 'Enable', 'on');
        state.isRecording = false;
    end

    function onPlayRecorded(~, ~)
        if isempty(state.recordedData)
            return;
        end
        spkIdx = get(popSpk, 'Value');
        selectedSpkID = devs.output(spkIdx).ID;
        
        % Normalize playback signal for audible listening if recording was quiet
        playData = state.recordedData;
        maxAmp = max(abs(playData));
        if maxAmp > 0 && maxAmp < 0.5
            playData = playData / maxAmp * 0.7; % Boost to audible 0.7 level
        end
        
        % Retain player handle in state so MATLAB garbage collector does not terminate playback
        state.activePlayer = audioplayer(playData, state.FS, BITS, selectedSpkID);
        play(state.activePlayer);
    end

    function onRetakeClick(~, ~)
        state.recordedData = [];
        set(hWaveLine, 'XData', [0, 1], 'YData', [0, 0]);
        set(hSpecLine, 'XData', [0, 1], 'YData', [-90, -90]);
        set(hMeterBar, 'YData', -60);
        set(lblClip, 'BackgroundColor', [0.25, 0.08, 0.08], 'ForegroundColor', [0.55, 0.55, 0.55]);
        set(btnPlay, 'Enable', 'off');
        set(btnRetake, 'Enable', 'off');
        set(lblStatus, 'String', 'STATUS: CLEARED / READY', 'BackgroundColor', [0.18, 0.20, 0.24]);
        set(txtDiag, 'String', sprintf('Duration : -- s\nPeak Amp : --\nRMS Level: -- dBFS\nClipping : NONE'));
        set(lblCoord, 'String', '  [Coordinate Tracker] Ready for new recording');
    end

    function onRunPipeline(~, ~)
        trialName = strtrim(get(txtTrial, 'String'));
        if isempty(trialName), trialName = defaultTrial; end
        fprintf('\n>>> Triggering Master Pipeline (main.m) from Audio Interface GUI for trial: %s <<<\n', trialName);
        set(lblStatus, 'String', 'STATUS: RUNNING PIPELINE...', 'BackgroundColor', [0.18, 0.45, 0.78]);
        drawnow;
        try
            main(trialName);
            set(lblStatus, 'String', 'STATUS: PIPELINE COMPLETED', 'BackgroundColor', [0.12, 0.55, 0.28]);
        catch ME
            errordlg(sprintf('Pipeline execution failed: %s', ME.message), 'Pipeline Error');
            set(lblStatus, 'String', 'STATUS: PIPELINE FAILED', 'BackgroundColor', cAccentRed);
        end
    end

    function onClose(~, ~)
        delete(fig);
    end
end
