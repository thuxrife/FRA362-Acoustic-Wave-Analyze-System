%% Generate Realistic Step-Stop-Step Acoustic Benchmarks
% Simulates an 11-step stepped-frequency experiment in a 2-meter pipe:
% Based on Bin Ali, Horoshenkov, & Tait (2011) - Water Science & Technology
%
% Structure per step (1.0s total cycle):
% 1. Leading-Edge Transit Window (0 to 15 ms):
%    - Direct pulse packet (2 cycles at fCurrent) at x_bar = 0
%    - Quiet baseline along unobstructed pipe
%    - Blockage reflection wave packet at x_bar = 0.40 (x = 0.8m)
%    - Pipe end reflection wave packet at x_bar = 1.0 (x = 2.0m)
% 2. Steady-State Tone Body (15 ms to 800 ms):
%    - Continuous multi-cycle standing wave for FFT spectrum & spectrogram
% 3. Silence Gap (800 ms to 1000 ms):
%    - 200 ms quiet gap allowing reverberations to decay before next step

clear; clc;

fs = 44100;
freqSteps = 300:100:1300;           % 11 frequency steps below 1352 Hz cut-off
numSteps = length(freqSteps);
toneDuration = 0.8;                 % 0.8s tone
gapDuration  = 0.2;                 % 0.2s silence
stepCycle    = toneDuration + gapDuration; % 1.0s total cycle
totalDuration = numSteps * stepCycle;
t = 0:(1/fs):(totalDuration - 1/fs);
N = length(t);

v = 346.0;                          % Speed of sound in air (m/s)
L = 2.0;                            % Model pipe length (m)
x_blockage = 0.8;                   % Blockage at 0.8m (dimensionless x_bar = 0.40)
t_roundtrip = 2 * L / v;            % 11.56 ms round-trip time to pipe end
t_blockage  = 2 * x_blockage / v;   % 4.62 ms round-trip time to blockage

%% 1. Synthesize Clean Pipe Response (Baseline)
dirClean = fullfile('mp3', '2026-31-10-step-clean');
if ~exist(dirClean, 'dir'), mkdir(dirClean); end

sigClean = zeros(1, N);
for k = 1:numSteps
    tStart = (k - 1) * stepCycle;
    idxStart = round(tStart * fs) + 1;
    idxEnd   = min(N, round((tStart + toneDuration) * fs));
    tTone    = (0:(idxEnd - idxStart)) / fs;
    fCurrent = freqSteps(k);

    % Compact 2-cycle tone packet for reflectometry leading edge
    N_pulse = max(4, round(2 * fs / fCurrent));
    t_pulse = (0:N_pulse-1) / fs;
    pulseShape = sin(2 * pi * fCurrent * t_pulse) .* (0.5 * (1 - cos(2 * pi * (0:N_pulse-1) / N_pulse)));

    % Direct wave at entrance (t = 0, x_bar = 0)
    directPulse = zeros(size(tTone));
    directPulse(1:N_pulse) = 0.85 * pulseShape;

    % Pipe end reflection (t = 11.56 ms, x_bar = 1.0)
    endEcho = zeros(size(tTone));
    idxEndEcho = round(t_roundtrip * fs) + 1;
    if idxEndEcho + N_pulse - 1 <= length(tTone)
        endEcho(idxEndEcho : idxEndEcho + N_pulse - 1) = -0.55 * pulseShape;
    end

    % Transient reflectometry window (first 20 ms)
    transitSignal = directPulse + endEcho;

    % Steady-state standing-wave resonance (20 ms onward)
    kWave = 2 * pi * fCurrent / v;
    resonanceGain = 1 / (abs(sin(kWave * L)) + 0.4);
    steadyTone = 0.35 * (resonanceGain / 2.5) * sin(2 * pi * fCurrent * tTone);

    % Blend transit leading edge into steady state
    t_trans = 0.020; % 20 ms transition
    weightSteady = min(1, max(0, (tTone - 0.015) / (t_trans - 0.015)));
    toneSignal = (1 - weightSteady) .* transitSignal + weightSteady .* steadyTone;

    sigClean(idxStart:idxEnd) = toneSignal;
end
sigClean = sigClean + 0.002 * randn(1, N);
audiowrite(fullfile(dirClean, '1.wav'), sigClean, fs);
fprintf('[Created] Clean Pipe: %s (11 steps, 300-1300 Hz)\n', fullfile(dirClean, '1.wav'));

%% 2. Synthesize Blocked Pipe Response (Blockage at x = 0.8m, x_bar = 0.40)
dirBlocked = fullfile('mp3', '2026-31-10-step-blocked');
if ~exist(dirBlocked, 'dir'), mkdir(dirBlocked); end

sigBlocked = zeros(1, N);
for k = 1:numSteps
    tStart = (k - 1) * stepCycle;
    idxStart = round(tStart * fs) + 1;
    idxEnd   = min(N, round((tStart + toneDuration) * fs));
    tTone    = (0:(idxEnd - idxStart)) / fs;
    fCurrent = freqSteps(k);

    % Compact 2-cycle tone packet for reflectometry leading edge
    N_pulse = max(4, round(2 * fs / fCurrent));
    t_pulse = (0:N_pulse-1) / fs;
    pulseShape = sin(2 * pi * fCurrent * t_pulse) .* (0.5 * (1 - cos(2 * pi * (0:N_pulse-1) / N_pulse)));

    % Direct wave at entrance (t = 0, x_bar = 0)
    directPulse = zeros(size(tTone));
    directPulse(1:N_pulse) = 0.85 * pulseShape;

    % Blockage reflection (t = 4.62 ms, x_bar = 0.40)
    blockageEcho = zeros(size(tTone));
    idxBlock = round(t_blockage * fs) + 1;
    if idxBlock + N_pulse - 1 <= length(tTone)
        blockageEcho(idxBlock : idxBlock + N_pulse - 1) = 0.42 * pulseShape;
    end

    % Attenuated pipe end reflection (t = 11.56 ms, x_bar = 1.0)
    endEcho = zeros(size(tTone));
    idxEndEcho = round(t_roundtrip * fs) + 1;
    if idxEndEcho + N_pulse - 1 <= length(tTone)
        endEcho(idxEndEcho : idxEndEcho + N_pulse - 1) = -0.25 * pulseShape;
    end

    % Transient reflectometry window (first 20 ms)
    transitSignal = directPulse + blockageEcho + endEcho;

    % Modified steady-state standing wave
    kWave = 2 * pi * fCurrent / v;
    blockedGain = 1 / (abs(sin(kWave * x_blockage) + 0.5 * cos(kWave * (L - x_blockage))) + 0.4);
    steadyTone = 0.35 * (blockedGain / 2.5) * sin(2 * pi * fCurrent * tTone);

    t_trans = 0.020;
    weightSteady = min(1, max(0, (tTone - 0.015) / (t_trans - 0.015)));
    toneSignal = (1 - weightSteady) .* transitSignal + weightSteady .* steadyTone;

    sigBlocked(idxStart:idxEnd) = toneSignal;
end
sigBlocked = sigBlocked + 0.002 * randn(1, N);
audiowrite(fullfile(dirBlocked, '1.wav'), sigBlocked, fs);
fprintf('[Created] Blocked Pipe (x_bar=0.40): %s (11 steps, 300-1300 Hz)\n', fullfile(dirBlocked, '1.wav'));

fprintf('\nDone! Step-Stop-Step acoustic datasets generated.\n');
