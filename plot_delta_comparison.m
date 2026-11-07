%% Acoustic Difference Analyzer: Baseline vs Sand Middle vs Sand Back
% Reads features_by_frequency.csv from the 2026-11-07 dataset and plots:
%   1. Absolute Step Peak Amplitude comparison
%   2. Differential Energy (Delta dB = Test - Baseline)

clear; clc; close all;

%% 1. File Paths
baseDir = 'analyze/2026-11-07-sound-sample';
f_base = fullfile(baseDir, 'sound_sample_0_base_line', 'features_by_frequency.csv');
f_mid  = fullfile(baseDir, 'sound_sample_1_sand_middle', 'features_by_frequency.csv');
f_back = fullfile(baseDir, 'sound_sample_1_sand_back',   'features_by_frequency.csv');

if ~isfile(f_base) || ~isfile(f_mid) || ~isfile(f_back)
    error('CSV files not found. Ensure you run this from the project root.');
end

%% 2. Load Data
T_base = readtable(f_base);
T_mid  = readtable(f_mid);
T_back = readtable(f_back);

freq   = T_base.Freq_Hz;
d_mid  = T_mid.Energy_dB - T_base.Energy_dB;
d_back = T_back.Energy_dB - T_base.Energy_dB;

%% 3. Create Visualization Figure
outDir = fullfile('analyze', 'different');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

fig = figure('Name', 'Acoustic Difference Analysis', ...
             'Color', [0.12, 0.12, 0.15], ...
             'Position', [100, 80, 1100, 750], ...
             'Visible', 'on');

% --- Subplot 1: Absolute Peak Amplitude ---
ax1 = subplot(2, 1, 1);
hold(ax1, 'on');
grid(ax1, 'on');
set(ax1, 'Color', [0.08, 0.08, 0.10], 'GridColor', [0.3, 0.3, 0.35], ...
         'XColor', [0.85, 0.85, 0.90], 'YColor', [0.85, 0.85, 0.90]);

p0 = plot(ax1, freq, T_base.Step_Peak_Amp, '-o', 'Color', [0.00, 0.80, 1.00], ...
          'LineWidth', 1.8, 'MarkerSize', 6, 'MarkerFaceColor', [0.00, 0.80, 1.00], ...
          'DisplayName', 'Baseline (Clean Pipe)');
p1 = plot(ax1, freq, T_mid.Step_Peak_Amp,  '-s', 'Color', [1.00, 0.60, 0.10], ...
          'LineWidth', 1.8, 'MarkerSize', 6, 'MarkerFaceColor', [1.00, 0.60, 0.10], ...
          'DisplayName', 'Sand Middle (1.0 m)');
p2 = plot(ax1, freq, T_back.Step_Peak_Amp, '-^', 'Color', [0.95, 0.20, 0.25], ...
          'LineWidth', 1.8, 'MarkerSize', 6, 'MarkerFaceColor', [0.95, 0.20, 0.25], ...
          'DisplayName', 'Sand Back (1.8 m)');

title(ax1, '1. Measured Peak Amplitude across Frequencies (300 - 1800 Hz)', ...
      'Color', [0.95, 0.95, 0.98], 'FontSize', 12, 'FontWeight', 'bold');
xlabel(ax1, 'Frequency (Hz)', 'Color', [0.85, 0.85, 0.90]);
ylabel(ax1, 'Peak Amplitude', 'Color', [0.85, 0.85, 0.90]);
xticks(ax1, freq);
xtickangle(ax1, 45);
xlim(ax1, [250, 1850]);
leg1 = legend(ax1, [p0, p1, p2], 'Location', 'northeast');
set(leg1, 'TextColor', [0.95, 0.95, 0.98], 'Color', [0.15, 0.15, 0.20], 'EdgeColor', 'none');

% --- Subplot 2: Delta dB (Test - Baseline) ---
ax2 = subplot(2, 1, 2);
hold(ax2, 'on');
grid(ax2, 'on');
set(ax2, 'Color', [0.08, 0.08, 0.10], 'GridColor', [0.3, 0.3, 0.35], ...
         'XColor', [0.85, 0.85, 0.90], 'YColor', [0.85, 0.85, 0.90]);

b = bar(ax2, categorical(freq), [d_mid, d_back], 0.8);
b(1).FaceColor = [1.00, 0.60, 0.10]; % Middle (Orange)
b(2).FaceColor = [0.95, 0.20, 0.25]; % Back (Red)
b(1).EdgeColor = 'none';
b(2).EdgeColor = 'none';

yline(ax2, 0, '-', 'Color', [0.8, 0.8, 0.8], 'LineWidth', 1.0);

title(ax2, '2. Difference from Baseline: \Delta Energy (dB) = Test - Baseline', ...
      'Color', [0.95, 0.95, 0.98], 'FontSize', 12, 'FontWeight', 'bold');
xlabel(ax2, 'Frequency (Hz)', 'Color', [0.85, 0.85, 0.90]);
ylabel(ax2, '\Delta Energy (dB)', 'Color', [0.85, 0.85, 0.90]);
ylim(ax2, [-26, 8]);
leg2 = legend(ax2, {'Sand Middle Drop (\Delta dB)', 'Sand Back Drop (\Delta dB)'}, 'Location', 'southeast');
set(leg2, 'TextColor', [0.95, 0.95, 0.98], 'Color', [0.15, 0.15, 0.20], 'EdgeColor', 'none');

% Text annotations for critical frequencies
text(ax2, 10, -8, sprintf('1200 Hz Dies\\n(-4.9 dB)'), ...
     'Color', [1.00, 0.60, 0.10], 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

text(ax2, 13, -24, sprintf('1500 Hz Crashes\\n(-22.7 dB)'), ...
     'Color', [0.95, 0.20, 0.25], 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

%% 4. Save Output Artifacts
figFile = fullfile(outDir, 'delta_comparison.fig');
pngFile = fullfile(outDir, 'delta_comparison.png');

set(fig, 'Visible', 'on');
set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
savefig(fig, figFile);
saveas(fig, pngFile);

fprintf('[Success] Difference plots saved to:\n  - %s\n  - %s\n', figFile, pngFile);
