%% Generate Clean Test Sound Input for Speaker Playback
% Produces a noise-free, high-fidelity stepped-frequency audio track
% designed specifically for the 100 mm diameter laboratory pipe:
% - 16 discrete frequencies: 300 Hz to 1800 Hz (100 Hz steps, strictly below ~2028 Hz cut-off)
% - Cycle per step: 0.15s (150 ms) pure tone + 0.25s (250 ms) dead silence (0.40s total per step)
% - Total duration: 6.4 seconds (plus 0.5s leading silence pad = 6.9s)
% - Amplitude: 0.80 peak (normalized to prevent DAC clipping/distortion)
% - Zero noise added

clear; clc;

fs = 44100;                         % Standard 44.1 kHz sampling rate
freqSteps = 300:100:1800;           % 16 steps below 100mm pipe cut-off (~2028 Hz)
numSteps = length(freqSteps);

toneDuration = 0.15;                % 150 ms per tone (45 to 270 cycles; ~13x pipe round-trip time)
gapDuration  = 0.25;                % 250 ms silence gap between tones for full reverb decay
stepCycle    = toneDuration + gapDuration; % 0.40 seconds per step
totalDuration = numSteps * stepCycle;

t = 0:(1/fs):(totalDuration - 1/fs);
N = length(t);
signal = zeros(1, N);

for k = 1:numSteps
    tStart = (k - 1) * stepCycle;
    idxStart = round(tStart * fs) + 1;
    idxEnd   = min(N, round((tStart + toneDuration) * fs));
    
    tTone = (0:(idxEnd - idxStart)) / fs;
    fCurrent = freqSteps(k);

    % Pure sine tone with instant attack
    signal(idxStart:idxEnd) = 0.80 * sin(2 * pi * fCurrent * tTone);
end

% Create sound_input folder if it does not exist
outputDir = 'sound_input';
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

outputWav = fullfile(outputDir, 'stepped_tones_100mm_150ms_250ms.wav');
audiowrite(outputWav, signal, fs, 'BitsPerSample', 24);

fprintf('Successfully generated pure speaker excitation track:\n');
fprintf('  File:     %s\n', outputWav);
fprintf('  Steps:    %d frequencies (300 Hz to 1800 Hz in 100 Hz steps)\n', numSteps);
fprintf('  Timing:   %.0f ms tone + %.0f ms silence gap per frequency step\n', toneDuration*1000, gapDuration*1000);
fprintf('  Duration: %.1f seconds total\n', totalDuration);
fprintf('  Noise:    0.0%% (pure mathematical sine waves)\n');
