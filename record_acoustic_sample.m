%% Interactive Acoustic Rig Hardware Interface & Recorder
% Scans system hardware, prompts for microphone and speaker selection,
% and records acoustic responses directly into the mp3/ folder hierarchy.
%
% Supported Operational Modes:
%   [1] Automated Test : Synchronously play excitation sound + record microphone
%   [2] Record Only    : Record microphone for N seconds (external speaker)
%   [3] Play Only      : Play excitation track through speaker (sound check)

clear; clc;

%% 1. Configuration & Default Paths
FS                  = 44100; % Standard 44.1 kHz sampling rate
BITS_PER_SAMPLE     = 16;    % 16-bit capture
DEFAULT_STIMULUS    = 'sound_input/stepped_tones_100mm_150ms_250ms.wav';
LEGACY_STIMULUS     = 'sound_input/stepped_tones_100mm_2s_1s.wav';
OUTPUT_ROOT         = 'mp3';

fprintf('=================================================================\n');
fprintf('          Acoustic Rig Hardware Interface & Recorder             \n');
fprintf('=================================================================\n\n');

%% 2. Query and Display Available Hardware
devs = audiodevinfo;

if isempty(devs.input)
    error('No audio input devices (microphones) detected on this system.');
end
if isempty(devs.output)
    error('No audio output devices (speakers) detected on this system.');
end

fprintf('[Detected Microphones (Input)]:\n');
for k = 1:length(devs.input)
    fprintf('  [%d] %s (ID: %d)\n', k, devs.input(k).Name, devs.input(k).ID);
end
fprintf('\n');

fprintf('[Detected Speakers (Output)]:\n');
for k = 1:length(devs.output)
    fprintf('  [%d] %s (ID: %d)\n', k, devs.output(k).Name, devs.output(k).ID);
end
fprintf('\n');

%% 3. Prompt for Device Selection
% Select Microphone
micChoice = input(sprintf('Select Microphone [1-%d, default=1]: ', length(devs.input)));
if isempty(micChoice) || micChoice < 1 || micChoice > length(devs.input)
    micChoice = 1;
end
selectedMicID   = devs.input(micChoice).ID;
selectedMicName = devs.input(micChoice).Name;

% Select Speaker
spkChoice = input(sprintf('Select Speaker    [1-%d, default=1]: ', length(devs.output)));
if isempty(spkChoice) || spkChoice < 1 || spkChoice > length(devs.output)
    spkChoice = 1;
end
selectedSpkID   = devs.output(spkChoice).ID;
selectedSpkName = devs.output(spkChoice).Name;

fprintf('\nConfigured Hardware:\n');
fprintf('  Microphone : [%d] %s\n', selectedMicID, selectedMicName);
fprintf('  Speaker    : [%d] %s\n\n', selectedSpkID, selectedSpkName);

%% 4. Prompt for Operational Mode
fprintf('Operational Modes:\n');
fprintf('  [1] Automated Test : Synchronously play excitation + record (Recommended)\n');
fprintf('  [2] Record Only    : Record microphone only (external sound source)\n');
fprintf('  [3] Sound Check    : Play excitation sound through speaker only\n');
modeChoice = input('Select Mode [1-3, default=1]: ');
if isempty(modeChoice) || ~ismember(modeChoice, [1, 2, 3])
    modeChoice = 1;
end

%% 5. Select Excitation Track (for Modes 1 and 3)
stimFile = DEFAULT_STIMULUS;
if ismember(modeChoice, [1, 3])
    if ~exist(DEFAULT_STIMULUS, 'file') && exist(LEGACY_STIMULUS, 'file')
        stimFile = LEGACY_STIMULUS;
    end
    fprintf('\nExcitation Track: %s\n', stimFile);
    if ~exist(stimFile, 'file')
        error('Excitation audio file "%s" not found. Run generate_sound_input.m first.', stimFile);
    end
    [stimSig, stimFs] = audioread(stimFile);
    stimDuration = length(stimSig) / stimFs;
end

%% 6. Prompt for Trial Folder and Sample Name (for Modes 1 and 2)
if ismember(modeChoice, [1, 2])
    todayStr = char(datetime('now', 'Format', 'yyyy-MM-dd'));
    defaultTrial = sprintf('%s-sound-sample', todayStr);

    trialInput = input(sprintf('\nEnter trial folder name [default: %s]: ', defaultTrial), 's');
    if isempty(trialInput)
        trialName = defaultTrial;
    else
        trialName = strtrim(trialInput);
    end

    sampleInput = input('Enter sample name [e.g. sound_sample_block]: ', 's');
    if isempty(sampleInput)
        sampleName = 'sound_sample_test';
    else
        sampleName = strtrim(sampleInput);
    end

    targetDir = fullfile(OUTPUT_ROOT, trialName);
    if ~exist(targetDir, 'dir')
        mkdir(targetDir);
    end
    targetWavPath = fullfile(targetDir, [sampleName, '.wav']);
end

%% 7. Execute Selected Mode
switch modeChoice
    case 1 % Automated Test: Synchronous Play + Record
        totalRecordTime = stimDuration + 0.8; % Lead-in + trailing reverberation
        fprintf('\n>>> Mode 1: Automated Test Selected <<<\n');
        fprintf('  Target Output : %s\n', targetWavPath);
        fprintf('  Stimulus      : %.1f seconds (%s)\n', stimDuration, stimFile);
        fprintf('  Total Capture : %.1f seconds\n', totalRecordTime);
        fprintf('Starting in 2 seconds...\n');
        pause(2);

        % Initialize Recorder and Player
        recObj = audiorecorder(FS, BITS_PER_SAMPLE, 1, selectedMicID);
        player = audioplayer(stimSig, stimFs, BITS_PER_SAMPLE, selectedSpkID);

        fprintf('  [1/3] Triggering microphone capture...\n');
        record(recObj);
        pause(0.2); % 200ms lead-in buffer

        fprintf('  [2/3] Playing excitation tone burst through speaker...\n');
        playblocking(player);

        fprintf('  [3/3] Capturing trailing duct reverberation...\n');
        pause(0.5);
        stop(recObj);

        recordedData = getaudiodata(recObj);

    case 2 % Record Only
        recTimeInput = input('Enter recording duration in seconds [default=7]: ');
        if isempty(recTimeInput) || recTimeInput <= 0
            recTime = 7.0;
        else
            recTime = recTimeInput;
        end

        fprintf('\n>>> Mode 2: Record Only Selected <<<\n');
        fprintf('  Target Output : %s\n', targetWavPath);
        fprintf('  Duration      : %.1f seconds\n', recTime);
        fprintf('Starting recording in 2 seconds...\n');
        pause(2);

        recObj = audiorecorder(FS, BITS_PER_SAMPLE, 1, selectedMicID);
        fprintf('  [*] RECORDING NOW (%.1fs)...\n', recTime);
        recordblocking(recObj, recTime);
        fprintf('  [*] Recording complete.\n');

        recordedData = getaudiodata(recObj);

    case 3 % Sound Check (Play Only)
        fprintf('\n>>> Mode 3: Sound Check (Play Only) <<<\n');
        fprintf('Playing %s through speaker [%d]...\n', stimFile, selectedSpkID);
        player = audioplayer(stimSig, stimFs, BITS_PER_SAMPLE, selectedSpkID);
        playblocking(player);
        fprintf('Playback finished.\n');
        return;
end

%% 8. Signal Quality Check & Diagnostics
peakAmp = max(abs(recordedData));
rmsAmp  = rms(recordedData);
recDuration = length(recordedData) / FS;

fprintf('\n=== Recording Quality Diagnostics ===\n');
fprintf('  Captured Duration : %.2f seconds (%d samples)\n', recDuration, length(recordedData));
fprintf('  Peak Amplitude    : %.4f\n', peakAmp);
fprintf('  RMS Energy Level  : %.4f (%.2f dBFS)\n', rmsAmp, 20 * log10(rmsAmp + eps));

if peakAmp >= 0.95
    fprintf(2, '  [WARNING] CLIPPING DETECTED! (Peak = %.2f >= 0.95)\n', peakAmp);
    fprintf(2, '            Reduce microphone input gain or decrease speaker volume to prevent distortion.\n');
elseif peakAmp < 0.02
    fprintf(2, '  [WARNING] SIGNAL TOO WEAK OR MUTED! (Peak = %.4f < 0.02)\n', peakAmp);
    fprintf(2, '            Check that the microphone is plugged in, unmuted, and positioned at the pipe entrance.\n');
else
    fprintf('  [STATUS] Signal health OK (Nominal dynamic range).\n');
end

%% 9. Save Audio File and Provide Hyperlinks
audiowrite(targetWavPath, recordedData, FS);
fprintf('\n[SAVED] Audio successfully written to:\n  %s\n\n', targetWavPath);

% Print 1-Click Action Hyperlinks for MATLAB Command Window
linkFolder = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));
linkLog    = '<a href="matlab:log_raw_data;">[Run log_raw_data]</a>';
linkFeat   = '<a href="matlab:extract_features;">[Run extract_features]</a>';

fprintf('Next Pipeline Actions: %s | %s | %s\n', linkLog, linkFeat, linkFolder);
