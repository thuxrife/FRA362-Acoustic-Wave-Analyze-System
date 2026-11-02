%% Generate Clean Test Sound Input for Speaker Playback
% Produces a noise-free, high-fidelity stepped-frequency audio track
% designed specifically for the 100 mm diameter laboratory pipe:
% - 17 discrete frequencies: 300 Hz to 1900 Hz (100 Hz steps, strictly below ~2028 Hz cut-off)
% - Cycle per step: 2.0s pure tone + 1.0s dead silence (3.0s total per step)
% - Total duration: 51.0 seconds
% - Amplitude: 0.80 peak (normalized to prevent DAC clipping/distortion)
% - Zero noise added

clear; clc;

fs = 44100;                         % Standard 44.1 kHz sampling rate
freqSteps = 300:100:1900;           % 17 steps below 100mm pipe cut-off (~2028 Hz)
numSteps = length(freqSteps);

toneDuration = 2.0;                 % 2.0 seconds per tone
gapDuration  = 1.0;                 % 1.0 second silence gap between tones
stepCycle    = toneDuration + gapDuration; % 3.0 seconds per step
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

outputWav = fullfile(outputDir, 'stepped_tones_100mm_2s_1s.wav');
audiowrite(outputWav, signal, fs, 'BitsPerSample', 24);

fprintf('Successfully generated pure speaker excitation track:\n');
fprintf('  File:     %s\n', outputWav);
fprintf('  Steps:    %d frequencies (300 Hz to 1900 Hz in 100 Hz steps)\n', numSteps);
fprintf('  Timing:   2.0s tone + 1.0s silence gap per frequency step\n');
fprintf('  Duration: %.1f seconds total (51.0s)\n', totalDuration);
fprintf('  Noise:    0.0%% (pure mathematical sine waves)\n');
