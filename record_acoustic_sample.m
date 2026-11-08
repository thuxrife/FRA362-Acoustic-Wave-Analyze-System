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
    STIM_DIR         = 'sound_input';
    DEFAULT_STIMULUS = 'sound_input/stepped_tones_100mm_2waves_500ms_gap.wav';
    FALLBACK_STIM    = 'sound_input/stepped_tones_100mm_150ms_250ms.wav';
    OUTPUT_ROOT      = 'mp3';

    % Discover available stimulus files in sound_input/
    [stimPaths, stimNames] = scanStimulusFolder(STIM_DIR, DEFAULT_STIMULUS, FALLBACK_STIM);
    stimFile = stimPaths{1};
    stimDuration = 0;
    stimSig = [];
    stimFs  = FS;
    if ~isempty(stimFile) && exist(stimFile, 'file')
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

    % Sample Name and Repeats Inputs
    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Sample Name (.wav):', ...
        'Position', [15, 388, 180, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    txtSample = uicontrol('Parent', pnlCtrl, 'Style', 'edit', 'String', 'sound_sample_01', ...
        'Position', [15, 364, 180, 24], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'HorizontalAlignment', 'left');

    uicontrol('Parent', pnlCtrl, 'Style', 'text', 'String', 'Repeats (N):', ...
        'Position', [205, 388, 105, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', cTextSec, 'FontSize', 9);
    txtRepeats = uicontrol('Parent', pnlCtrl, 'Style', 'edit', 'String', '1', ...
        'Position', [205, 364, 105, 24], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 9, 'HorizontalAlignment', 'center', ...
        'Tooltip', 'Number of trials to repeat and ensemble-average for acoustic noise reduction');

    % Selectable Stimulus Track Input (Dropdown + Browse Button)
    lblStim = uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', sprintf('Stimulus Input (%.2fs, 16 steps):', stimDuration), ...
        'Position', [15, 340, 295, 18], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', cPanelBg, 'ForegroundColor', [0.45, 0.75, 0.95], 'FontSize', 8, 'FontWeight', 'bold');

    popStim = uicontrol('Parent', pnlCtrl, 'Style', 'popupmenu', ...
        'String', stimNames, ...
        'Position', [15, 314, 222, 25], 'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextPri, 'FontSize', 8, 'Value', 1, ...
        'Tooltip', 'Select excitation sound file from sound_input/ at any time', ...
        'Callback', @onStimulusChange);

    btnBrowseStim = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Browse...', ...
        'Position', [242, 314, 68, 25], ...
        'BackgroundColor', [0.22, 0.28, 0.36], 'ForegroundColor', cTextPri, ...
        'FontSize', 8, ...
        'Tooltip', 'Browse for a custom .wav or .mp3 stimulus file', ...
        'Callback', @onBrowseStimulus);

    % Action Buttons
    btnRecord = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'START RECORDING / TEST', ...
        'Position', [15, 266, 295, 42], ...
        'BackgroundColor', cAccentGrn, 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'Callback', @onRecordClick);

    btnPlay = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Play Recorded Audio', ...
        'Position', [15, 228, 142, 32], ...
        'BackgroundColor', cControlBg, 'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'Enable', 'off', ...
        'Callback', @onPlayRecorded);

    btnRetake = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Clear / Retake', ...
        'Position', [168, 228, 142, 32], ...
        'BackgroundColor', cControlBg, 'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'Enable', 'off', ...
        'Callback', @onRetakeClick);

    % Status Readout Badge
    lblStatus = uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', 'STATUS: READY', ...
        'Position', [15, 188, 295, 34], ...
        'BackgroundColor', [0.18, 0.20, 0.24], ...
        'ForegroundColor', cTextPri, ...
        'FontSize', 9, 'FontWeight', 'bold');

    % Numerical Diagnostics Box
    txtDiag = uicontrol('Parent', pnlCtrl, 'Style', 'text', ...
        'String', sprintf('Duration : -- s\nPeak Amp : --\nRMS Level: -- dBFS\nClipping : NONE'), ...
        'Position', [15, 106, 295, 76], ...
        'BackgroundColor', cControlBg, ...
        'ForegroundColor', cTextSec, ...
        'FontSize', 9, 'HorizontalAlignment', 'left');

    % Figure Overlay, Subtraction, & Delta Comparison Tool Buttons
    btnOverlay = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Overlay', ...
        'Position', [15, 64, 93, 36], ...
        'BackgroundColor', [0.38, 0.25, 0.55], 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Tooltip', 'Overlay multiple spectral curves for visual comparison', ...
        'Callback', @onOverlayClick);

    btnDiff = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Blockage', ...
        'Position', [116, 64, 93, 36], ...
        'BackgroundColor', [0.85, 0.28, 0.20], 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Tooltip', 'Acoustic Blockage Analysis (Level 4 & 5): Delta dB & Physical Blockage Area %', ...
        'Callback', @onBlockageClick);

    btnDelta = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'Reflex Map', ...
        'Position', [217, 64, 93, 36], ...
        'BackgroundColor', [0.10, 0.55, 0.60], 'ForegroundColor', [1, 1, 1], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Tooltip', 'Acoustic Reflex Map (Option C): 8s Timeline & Synchronized 16-Step Heatmaps', ...
        'Callback', @onReflexClick);

    % 1-Click Pipeline Button
    btnPipeline = uicontrol('Parent', pnlCtrl, 'Style', 'pushbutton', ...
        'String', 'RUN MASTER PIPELINE (main.m)', ...
        'Position', [15, 14, 295, 44], ...
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

    % 4B. Instant Frequency Spectrum Axes (Bottom Graph: Matches frequency.fig)
    axSpec = axes('Parent', pnlGraph, 'Units', 'pixels', ...
        'Position', [65, 55, 625, 240], ...
        'Color', cPlotBg, 'XColor', cTextSec, 'YColor', cTextSec, ...
        'GridColor', [0.22, 0.24, 0.28], 'GridAlpha', 0.8);
    grid(axSpec, 'on'); box(axSpec, 'on'); hold(axSpec, 'on');
    title(axSpec, 'Frequency Spectrum (Raw FFT)', ...
        'Color', cTextPri, 'FontSize', 10, 'FontWeight', 'bold');
    xlabel(axSpec, 'Frequency (Hz)', 'Color', cTextSec, 'FontSize', 9);
    ylabel(axSpec, '|Amplitude|', 'Color', cTextSec, 'FontSize', 9);
    xlim(axSpec, [0, 2200]);
    ylim(axSpec, [0, 0.05]);
    hSpecLine = plot(axSpec, [0, 1], [0, 0], 'Color', [0.95, 0.35, 0.25], 'LineWidth', 1.2);
    hSpecPeaks = plot(axSpec, nan, nan, 'o', 'Color', [1.0, 0.85, 0.20], ...
        'MarkerFaceColor', [0.95, 0.35, 0.25], 'MarkerSize', 5, 'LineWidth', 1.0);

    % Plane wave cut-off frequency guide (2028 Hz for 100 mm pipe)
    f_cutoff = 0.586 * 346.0 / 0.10;
    xline(axSpec, f_cutoff, '--', sprintf('Cut-Off: %.0f Hz', f_cutoff), ...
        'Color', [0.65, 0.68, 0.74], 'LineWidth', 1.1, 'LabelVerticalAlignment', 'top', ...
        'LabelColor', [0.85, 0.88, 0.92]);

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
        % Check if cursor is over Waveform Oscilloscope
        cpW = get(axWave, 'CurrentPoint');
        xW = cpW(1, 1); yW = cpW(1, 2);
        xLimW = xlim(axWave); yLimW = ylim(axWave);

        if xW >= xLimW(1) && xW <= xLimW(2) && yW >= yLimW(1) && yW <= yLimW(2)
            totalN = length(state.recordedData);
            sampleIdx = round(xW * state.FS) + 1;
            if sampleIdx >= 1 && sampleIdx <= totalN
                sampleAmp = state.recordedData(sampleIdx);
                set(lblCoord, 'String', sprintf('  [WAVE] Time: %7.4f s | Amp: %+7.4f | Sample: #%d / %d', ...
                    xW, sampleAmp, sampleIdx, totalN));
            end
            return;
        end

        % Check if cursor is over Frequency Spectrum
        if isfield(state, 'fAxis') && ~isempty(state.fAxis)
            cpS = get(axSpec, 'CurrentPoint');
            xS = cpS(1, 1); yS = cpS(1, 2);
            xLimS = xlim(axSpec); yLimS = ylim(axSpec);

            if xS >= xLimS(1) && xS <= xLimS(2) && yS >= yLimS(1) && yS <= yLimS(2)
                [~, nearIdx] = min(abs(state.fAxis - xS));
                fNear = state.fAxis(nearIdx);
                pNear = state.P1(nearIdx);
                set(lblCoord, 'String', sprintf('  [SPECTRUM] Freq: %6.1f Hz | |Amplitude|: %.5f  [Nearest Bin: %.1f Hz, Amp: %.5f]', ...
                    xS, yS, fNear, pNear));
                return;
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

        % Refresh Stimulus Input Dropdown from sound_input/
        [stimPaths, stimNames] = scanStimulusFolder(STIM_DIR, DEFAULT_STIMULUS, FALLBACK_STIM);
        oldStim = get(popStim, 'Value');
        newStimIdx = min(max(oldStim, 1), length(stimPaths));
        set(popStim, 'String', stimNames, 'Value', newStimIdx);
        loadSelectedStimulus(stimPaths{newStimIdx});

        nMic = length(devs.input);
        nSpk = length(devs.output);
        set(lblStatus, 'String', sprintf('RESCANNED: %d MIC(S), %d SPK(S)', nMic, nSpk), ...
            'BackgroundColor', [0.12, 0.45, 0.35]);
        fprintf('[Hardware Rescan] Detected %d microphone(s), %d speaker(s), and %d stimulus track(s).\n', ...
            nMic, nSpk, length(stimPaths));
    end

    function onStimulusChange(~, ~)
        idx = get(popStim, 'Value');
        if idx >= 1 && idx <= length(stimPaths) && ~isempty(stimPaths{idx})
            loadSelectedStimulus(stimPaths{idx});
        end
    end

    function onBrowseStimulus(~, ~)
        [fName, fDir] = uigetfile({'*.wav;*.mp3', 'Audio Files (*.wav, *.mp3)'}, ...
            'Select Custom Stimulus Sound File', STIM_DIR);
        if isequal(fName, 0)
            return;
        end
        chosenPath = fullfile(fDir, fName);
        % Prepend or select in dropdown
        matchIdx = find(strcmpi(stimPaths, chosenPath), 1);
        if isempty(matchIdx)
            stimPaths = [{chosenPath}, stimPaths];
            stimNames = [{fName}, stimNames];
            set(popStim, 'String', stimNames, 'Value', 1);
        else
            set(popStim, 'Value', matchIdx);
        end
        loadSelectedStimulus(chosenPath);
    end

    function loadSelectedStimulus(targetPath)
        if isempty(targetPath) || ~exist(targetPath, 'file')
            return;
        end
        try
            [sSig, sFs] = audioread(targetPath);
            if size(sSig, 2) > 1
                sSig = mean(sSig, 2);
            end
            stimFile     = targetPath;
            stimSig      = sSig;
            stimFs       = sFs;
            stimDuration = length(stimSig) / stimFs;
            [~, sBase, sExt] = fileparts(stimFile);
            set(lblStim, 'String', sprintf('Stimulus Input (%.2fs, 16 steps):', stimDuration));
            set(lblStatus, 'String', sprintf('STIMULUS: %s%s (%.2fs)', sBase, sExt, stimDuration), ...
                'BackgroundColor', [0.16, 0.32, 0.48]);
            fprintf('[Stimulus Selected] %s (Duration: %.2fs, Fs: %d Hz)\n', stimFile, stimDuration, stimFs);
        catch ME
            errordlg(sprintf('Failed to load stimulus file:\n%s', ME.message), 'Stimulus Error');
        end
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

        % Read number of experiment repeats for coherent averaging
        numRepStr = strtrim(get(txtRepeats, 'String'));
        numRepeats = str2double(numRepStr);
        if isnan(numRepeats) || numRepeats < 1
            numRepeats = 1;
        else
            numRepeats = round(numRepeats);
        end

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

                    repWavList = cell(1, numRepeats);
                    repeatSignals = [];
                    for rep = 1:numRepeats
                        if numRepeats > 1
                            set(lblStatus, 'String', sprintf('STATUS: EXCITING & RECORDING [%d/%d]...', rep, numRepeats), ...
                                'BackgroundColor', [0.75, 0.20, 0.15]);
                        else
                            set(lblStatus, 'String', 'STATUS: RECORDING & EXCITING PIPE...', ...
                                'BackgroundColor', [0.75, 0.20, 0.15]);
                        end
                        drawnow;

                        recObj = audiorecorder(FS, BITS, 1, selectedMicID);
                        player = audioplayer(stimSig, stimFs, BITS, selectedSpkID);

                        record(recObj);
                        pause(0.2);          % 200ms pre-excitation lead-in
                        playblocking(player); % Synchronous playback through duct
                        pause(0.5);          % 500ms duct decay / reverberation tail
                        stop(recObj);

                        singleData = getaudiodata(recObj);

                        if numRepeats > 1
                            % Save individual raw repeat: {sample}_rep1.wav, _rep2.wav...
                            repWav = fullfile(targetDir, sprintf('%s_rep%d.wav', sampleName, rep));
                            audiowrite(repWav, singleData, FS);
                            repWavList{rep} = repWav;
                            fprintf('  [Repeat %d/%d Saved] -> %s\n', rep, numRepeats, repWav);

                            if isempty(repeatSignals)
                                repeatSignals = zeros(length(singleData), numRepeats);
                            end
                            minL = min(size(repeatSignals, 1), length(singleData));
                            repeatSignals(1:minL, rep) = singleData(1:minL);

                            % Inter-repeat pause for duct reverberation to settle
                            if rep < numRepeats
                                set(lblStatus, 'String', sprintf('STATUS: DUCT SETTLING (PAUSE %d/%d)...', rep, numRepeats), ...
                                    'BackgroundColor', [0.45, 0.35, 0.15]);
                                drawnow;
                                pause(0.8);
                            end
                        else
                            recordedData = singleData;
                        end
                    end

                    if numRepeats > 1
                        % Time-align all repeats to Step 1 (t = 0.000s) before coherent averaging
                        try
                            aligner = AudioAnalyzer('', 'AutoAlign', true, 'PreTriggerSeconds', 0.2, 'StimulusPath', stimFile);
                            aligner.loadRepeatFiles(repWavList);
                            recordedData = aligner.AudioData;
                        catch
                            recordedData = mean(repeatSignals, 2);
                        end
                        fprintf('[Ensemble Averaging] Time-aligned and averaged %d repeats for %s\n', numRepeats, sampleName);
                    end

                case 2 % Mode 2: Record Only
                    recTime = max(7.0, round(stimDuration + 1.0, 1));
                    repWavList = cell(1, numRepeats);
                    repeatSignals = [];
                    for rep = 1:numRepeats
                        if numRepeats > 1
                            set(lblStatus, 'String', sprintf('STATUS: RECORDING [%d/%d] (%.1fs)...', rep, numRepeats, recTime), ...
                                'BackgroundColor', [0.75, 0.20, 0.15]);
                        else
                            set(lblStatus, 'String', sprintf('STATUS: RECORDING ONLY (%.1fs)...', recTime), ...
                                'BackgroundColor', [0.75, 0.20, 0.15]);
                        end
                        drawnow;

                        recObj = audiorecorder(FS, BITS, 1, selectedMicID);
                        recordblocking(recObj, recTime);
                        singleData = getaudiodata(recObj);

                        if numRepeats > 1
                            repWav = fullfile(targetDir, sprintf('%s_rep%d.wav', sampleName, rep));
                            audiowrite(repWav, singleData, FS);
                            repWavList{rep} = repWav;
                            if isempty(repeatSignals)
                                repeatSignals = zeros(length(singleData), numRepeats);
                            end
                            minL = min(size(repeatSignals, 1), length(singleData));
                            repeatSignals(1:minL, rep) = singleData(1:minL);
                            if rep < numRepeats, pause(0.8); end
                        else
                            recordedData = singleData;
                        end
                    end

                    if numRepeats > 1
                        try
                            aligner = AudioAnalyzer('', 'AutoAlign', true, 'PreTriggerSeconds', 0.2, 'StimulusPath', stimFile);
                            aligner.loadRepeatFiles(repWavList);
                            recordedData = aligner.AudioData;
                        catch
                            recordedData = mean(repeatSignals, 2);
                        end
                        fprintf('[Ensemble Averaging] Time-aligned and averaged %d repeats for %s\n', numRepeats, sampleName);
                    end

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

            % Save active stimulus reference alongside recording for exact pipeline schedule alignment
            if ~isempty(stimFile)
                stimMetaPath = fullfile(targetDir, [sampleName, '_stimulus.txt']);
                fid = fopen(stimMetaPath, 'w');
                if fid > 0
                    fprintf(fid, '%s\n', stimFile);
                    fclose(fid);
                end
            end

            % Update Waveform Oscilloscope Display
            tAxis = (0:length(recordedData)-1)' / FS;
            set(hWaveLine, 'XData', tAxis, 'YData', recordedData);
            xlim(axWave, [0, max(tAxis(end), 0.01)]);
            peakVal = max(abs(recordedData));
            maxDisplay = max(1.05, peakVal * 1.1);
            ylim(axWave, [-maxDisplay, maxDisplay]);

            % Update Frequency Spectrum Display (Exact match to AudioAnalyzer.plotFrequency)
            N = length(recordedData);
            Nfft = 2^nextpow2(N);
            Y = fft(recordedData, Nfft);
            P2 = abs(Y / N);
            P1 = P2(1:floor(Nfft/2) + 1);
            P1(2:end-1) = 2 * P1(2:end-1);
            fAxis = FS * (0:(Nfft/2)) / Nfft;

            set(hSpecLine, 'XData', fAxis, 'YData', P1);
            xlim(axSpec, [0, 2200]);

            % Store in state for coordinate hover tracker
            state.fAxis = fAxis;
            state.P1    = P1;

            % Auto-scale Y-axis based on in-band peak amplitude
            inBand = (fAxis >= 0) & (fAxis <= 2200);
            maxP1 = max(P1(inBand));
            if isempty(maxP1) || maxP1 <= 0, maxP1 = 0.01; end
            ylim(axSpec, [0, maxP1 * 1.25]);

            % Detect and highlight discrete frequency step peaks (300 to 1800 Hz)
            inStimBand = (fAxis >= 250) & (fAxis <= 1900);
            fStim = fAxis(inStimBand);
            pStim = P1(inStimBand);

            minPkHeight = max(maxP1 * 0.15, 1e-4);
            try
                minDistSamples = max(round(70 / (fAxis(2) - fAxis(1))), 3);
                [pks, locs] = findpeaks(pStim, 'MinPeakHeight', minPkHeight, 'MinPeakDistance', minDistSamples);
                set(hSpecPeaks, 'XData', fStim(locs), 'YData', pks);
            catch
                isLocalMax = [false, (pStim(2:end-1) > pStim(1:end-2)) & (pStim(2:end-1) > pStim(3:end)), false];
                locs = find(isLocalMax & (pStim' > minPkHeight));
                set(hSpecPeaks, 'XData', fStim(locs), 'YData', pStim(locs));
            end

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

            repTag = '';
            if numRepeats > 1
                repTag = sprintf('Repeats  : %d (Ensemble Avg)\n', numRepeats);
            end

            set(txtDiag, 'String', sprintf('Duration : %.2f s (%d smp)\n%sPeak Amp : %.4f (%.1f dBFS)\nRMS Level: %.4f (%.1f dBFS)\nClipping : %s\nTarget   : %s', ...
                durVal, length(recordedData), repTag, peakVal, peakDB, rmsVal, rmsDB, clipStr, savedStr));

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
        state.fAxis = [];
        state.P1 = [];
        set(hWaveLine, 'XData', [0, 1], 'YData', [0, 0]);
        set(hSpecLine, 'XData', [0, 1], 'YData', [0, 0]);
        set(hSpecPeaks, 'XData', nan, 'YData', nan);
        set(hMeterBar, 'YData', -60);
        set(lblClip, 'BackgroundColor', [0.25, 0.08, 0.08], 'ForegroundColor', [0.55, 0.55, 0.55]);
        set(btnPlay, 'Enable', 'off');
        set(btnRetake, 'Enable', 'off');
        set(lblStatus, 'String', 'STATUS: CLEARED / READY', 'BackgroundColor', [0.18, 0.20, 0.24]);
        set(txtDiag, 'String', sprintf('Duration : -- s\nPeak Amp : --\nRMS Level: -- dBFS\nClipping : NONE'));
        set(lblCoord, 'String', '  [Coordinate Tracker] Ready for new recording');
    end

    function onOverlayClick(~, ~)
        try
            trialName = strtrim(get(txtTrial, 'String'));
            if isempty(trialName), trialName = defaultTrial; end
            taskName = sprintf('compare_%s', trialName);

            set(lblStatus, 'String', 'STATUS: SELECTING FIGURES...', 'BackgroundColor', [0.38, 0.25, 0.55]);
            drawnow;

            outPath = overlay_figures({}, taskName, true);
            if ~isempty(outPath)
                set(lblStatus, 'String', 'STATUS: OVERLAY GENERATED', 'BackgroundColor', [0.12, 0.55, 0.28]);
            else
                set(lblStatus, 'String', 'STATUS: READY', 'BackgroundColor', [0.18, 0.20, 0.24]);
            end
        catch ME
            errordlg(sprintf('Overlay tool error: %s', ME.message), 'Overlay Failed');
            set(lblStatus, 'String', 'STATUS: OVERLAY FAILED', 'BackgroundColor', cAccentRed);
        end
    end

    function onBlockageClick(~, ~)
        try
            trialName = strtrim(get(txtTrial, 'String'));
            if isempty(trialName), trialName = defaultTrial; end
            taskName = sprintf('blockage_%s', trialName);

            set(lblStatus, 'String', 'STATUS: SELECTING BLOCKAGE FILES...', 'BackgroundColor', [0.85, 0.28, 0.20]);
            drawnow;

            outPath = plot_blockage_analysis({}, taskName);
            if ~isempty(outPath)
                set(lblStatus, 'String', 'STATUS: BLOCKAGE CHART SAVED', 'BackgroundColor', [0.12, 0.55, 0.28]);
            else
                set(lblStatus, 'String', 'STATUS: READY', 'BackgroundColor', [0.18, 0.20, 0.24]);
            end
        catch ME
            errordlg(sprintf('Blockage analysis error: %s', ME.message), 'Blockage Tool Failed');
            set(lblStatus, 'String', 'STATUS: BLOCKAGE FAILED', 'BackgroundColor', cAccentRed);
        end
    end

    function onReflexClick(~, ~)
        try
            trialName = strtrim(get(txtTrial, 'String'));
            if isempty(trialName), trialName = defaultTrial; end
            taskName = sprintf('reflex_%s', trialName);

            set(lblStatus, 'String', 'STATUS: SELECTING REFLEX FILES...', 'BackgroundColor', [0.10, 0.55, 0.60]);
            drawnow;

            outPath = plot_acoustic_reflex_map({}, taskName);
            if ~isempty(outPath)
                set(lblStatus, 'String', 'STATUS: REFLEX MAP SAVED', 'BackgroundColor', [0.12, 0.55, 0.28]);
            else
                set(lblStatus, 'String', 'STATUS: READY', 'BackgroundColor', [0.18, 0.20, 0.24]);
            end
        catch ME
            errordlg(sprintf('Reflex Map error: %s', ME.message), 'Reflex Tool Failed');
            set(lblStatus, 'String', 'STATUS: REFLEX FAILED', 'BackgroundColor', cAccentRed);
        end
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

function [stimPaths, stimNames] = scanStimulusFolder(stimDir, pref1, pref2)
    % Scans sound_input/ for .wav and .mp3 tracks, placing preferred tracks at the top
    stimPaths = {};
    stimNames = {};

    if exist(pref1, 'file')
        [~, b, e] = fileparts(pref1);
        stimPaths{end+1} = pref1;
        stimNames{end+1} = [b, e];
    end
    if exist(pref2, 'file') && ~any(strcmpi(stimPaths, pref2))
        [~, b, e] = fileparts(pref2);
        stimPaths{end+1} = pref2;
        stimNames{end+1} = [b, e];
    end

    if exist(stimDir, 'dir')
        files = [dir(fullfile(stimDir, '*.wav')); dir(fullfile(stimDir, '*.mp3'))];
        for k = 1:length(files)
            fPath = fullfile(stimDir, files(k).name);
            % Normalize slashes for comparison
            normCand = strrep(fPath, '\', '/');
            isDup = false;
            for j = 1:length(stimPaths)
                if strcmpi(strrep(stimPaths{j}, '\', '/'), normCand)
                    isDup = true;
                    break;
                end
            end
            if ~isDup
                stimPaths{end+1} = normCand; %#ok<AGROW>
                stimNames{end+1} = files(k).name; %#ok<AGROW>
            end
        end
    end

    if isempty(stimPaths)
        stimPaths = {''};
        stimNames = {'[No Stimulus Found - Run generate_sound_input.m]'};
    end
end
