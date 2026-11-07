%% Generate Clean Test Sound Inputs for Speaker Playback
% Synthesizes noise-free 24-bit stepped-frequency excitation tracks in sound_input/
% for the 100 mm diameter laboratory pipe (16 steps: 300 Hz to 1800 Hz in 100 Hz increments,
% strictly below the ~2028 Hz plane-wave cut-off limit):
%
%   Track 1 (Continuous Short Burst): stepped_tones_100mm_150ms_250ms.wav
%     - 150 ms pure tone + 250 ms silence gap per step (0.40s/step, 6.4s total)
%
%   Track 2 (2-Wave Impulse + 0.5s Gap): stepped_tones_100mm_2waves_500ms_gap.wav
%     - 2 complete wave cycles per frequency: T_tone(k) = 2 / f_k (6.67 ms at 300 Hz down to 1.11 ms at 1800 Hz)
%     - Fixed 0.50s (500 ms) dead-silence gap after each 2-wave impulse (~8.04s total)

clear; clc;

fs = 44100;               % Standard 44.1 kHz sampling rate
freqSteps = 300:100:1800; % 16 steps below 100mm pipe cut-off (~2028 Hz)
numSteps = length(freqSteps);
peakAmp = 0.80;           % Normalized to 0.80 to prevent DAC clipping

outputDir = 'sound_input';
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 1. Track A: 150 ms Tone + 250 ms Gap (stepped_tones_100mm_150ms_250ms.wav)
toneDurA = 0.15;
gapDurA  = 0.25;
cycleA   = toneDurA + gapDurA;
totalDurA = numSteps * cycleA;
sigA = zeros(1, round(totalDurA * fs));

for k = 1:numSteps
    tStart = (k - 1) * cycleA;
    idx1 = round(tStart * fs) + 1;
    idx2 = min(length(sigA), round((tStart + toneDurA) * fs));
    tTone = (0:(idx2 - idx1)) / fs;
    sigA(idx1:idx2) = peakAmp * sin(2 * pi * freqSteps(k) * tTone);
end

wavPathA = fullfile(outputDir, 'stepped_tones_100mm_150ms_250ms.wav');
audiowrite(wavPathA, sigA, fs, 'BitsPerSample', 24);
fprintf('[Generated Track 1] %s (%.2fs, 150ms tone + 250ms gap)\n', wavPathA, totalDurA);

%% 2. Track B: 2-Wave Impulse (T = 2/f) + Fixed 0.5s Gap (stepped_tones_100mm_2waves_500ms_gap.wav)
numWaves = 2;             % 2 complete sine wave cycles per step
gapDurB  = 0.50;          % Fixed 0.5s silence gap between impulses

toneDursB = numWaves ./ freqSteps; % Proportional to period: 2 / f_k
stepCyclesB = toneDursB + gapDurB;
totalDurB = sum(stepCyclesB);
sigB = zeros(1, round(totalDurB * fs));

cursorTime = 0;
for k = 1:numSteps
    fCurrent = freqSteps(k);
    tBurst   = toneDursB(k);

    idx1 = round(cursorTime * fs) + 1;
    nBurstSamples = max(2, round(tBurst * fs));
    idx2 = min(length(sigB), idx1 + nBurstSamples - 1);

    tTone = (0:(idx2 - idx1)) / fs;
    % Exact 2-cycle sine impulse starting and ending at zero-crossing
    sigB(idx1:idx2) = peakAmp * sin(2 * pi * fCurrent * tTone);

    cursorTime = cursorTime + tBurst + gapDurB;
end

wavPathB = fullfile(outputDir, 'stepped_tones_100mm_2waves_500ms_gap.wav');
audiowrite(wavPathB, sigB, fs, 'BitsPerSample', 24);

fprintf('[Generated Track 2] %s\n', wavPathB);
fprintf('  Steps:    %d frequencies (300 Hz to 1800 Hz in 100 Hz steps)\n', numSteps);
fprintf('  Impulse:  2 wave cycles per step (%.2f ms at 300 Hz -> %.2f ms at 1800 Hz)\n', ...
    toneDursB(1)*1000, toneDursB(end)*1000);
fprintf('  Gap:      %.0f ms fixed silence between steps\n', gapDurB*1000);
fprintf('  Duration: %.3f seconds total\n', totalDurB);
