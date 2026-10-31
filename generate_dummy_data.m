%% Generate Realistic Stepped Frequency Acoustic Benchmarks
% Simulates a 15-second stepped-frequency acoustic test:
% 15 discrete 1-second tones from 400 Hz to 1800 Hz (100 Hz per step).

clear; clc;

fs = 44100;
stepDuration = 1.0;                 % 1 second per tone step
freqSteps = 400:100:1800;           % 15 frequency steps (15 seconds total)
totalSteps = length(freqSteps);
totalDuration = totalSteps * stepDuration;
t = 0:(1/fs):(totalDuration - 1/fs);
N = length(t);

%% Synthesize Benchmark Trial A (Flat / Baseline Response)
dirA = fullfile('mp3', '2026-31-10-stepped-sine-baseline');
if ~exist(dirA, 'dir'), mkdir(dirA); end

sigA = zeros(1, N);
for k = 1:totalSteps
    idxStart = (k - 1) * round(stepDuration * fs) + 1;
    idxEnd   = min(N, k * round(stepDuration * fs));
    tStep    = t(idxStart:idxEnd);
    fCurrent = freqSteps(k);

    gain = 0.5 + 0.1 * sin(2 * pi * k / totalSteps);
    sigA(idxStart:idxEnd) = gain .* sin(2 * pi * fCurrent * tStep);
end
sigA = sigA + 0.01 * randn(1, N);
audiowrite(fullfile(dirA, '1.wav'), sigA, fs);
fprintf('[Created] Stepped-Sine Baseline: %s (15 seconds, %d steps)\n', ...
    fullfile(dirA, '1.wav'), totalSteps);

%% Synthesize Benchmark Trial B (Attenuated / Modified Response)
dirB = fullfile('mp3', '2026-31-10-stepped-sine-modified');
if ~exist(dirB, 'dir'), mkdir(dirB); end

sigB = zeros(1, N);
for k = 1:totalSteps
    idxStart = (k - 1) * round(stepDuration * fs) + 1;
    idxEnd   = min(N, k * round(stepDuration * fs));
    tStep    = t(idxStart:idxEnd);
    fCurrent = freqSteps(k);

    % Attenuates specific tone bands (e.g., around 1000-1200 Hz)
    if fCurrent >= 1000 && fCurrent <= 1200
        gain = 0.12;
    else
        gain = 0.5 + 0.1 * sin(2 * pi * k / totalSteps);
    end
    sigB(idxStart:idxEnd) = gain .* sin(2 * pi * fCurrent * tStep);
end
sigB = sigB + 0.01 * randn(1, N);
audiowrite(fullfile(dirB, '1.wav'), sigB, fs);
fprintf('[Created] Stepped-Sine Modified: %s (15 seconds, %d steps)\n', ...
    fullfile(dirB, '1.wav'), totalSteps);

fprintf('\nDone! 15-second stepped-frequency acoustic datasets generated.\n');
