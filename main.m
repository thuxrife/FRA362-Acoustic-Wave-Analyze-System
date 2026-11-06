%% Main Batch Processing Script
% Scans input directory hierarchy: mp3/{trial_folder}/{id}.mp3
% Outputs analysis plots to: analyze/{trial_folder}/{id}/
%
% Generates 4 acoustic plots per audio file:
% 1. Amplitude vs Time (amplitude.svg / .fig)
% 2. Frequency Spectrum (frequency.svg / .fig)
% 3. Spectrogram (spectrogram.svg / .fig)
% 4. Amplitude vs Dimensionless Distance (amplitude-distance.svg / .fig)

clear; clc;

%% Configuration
INPUT_ROOT  = 'mp3';
OUTPUT_ROOT = 'analyze';

% Pipe Duct Geometry Settings
MODEL_LENGTH    = 2.0;   % Pipe length in meters (L)
PIPE_DIAMETER   = 0.10;  % Model pipe diameter (100 mm = 0.10 m)
SOUND_SPEED     = 346.0; % Speed of sound in air at ~25 C (m/s)
ENABLE_DISTANCE = false; % Reflectometry disabled

% Acoustic Cut-off & Frequency Bounds
% Cut-off for 100mm circular pipe: f_c = 0.586 * v / D ~ 2028 Hz
MAX_FREQ    = 2200;  % Display through 2200 Hz to show cut-off boundary at ~2028 Hz
TIME_RANGE  = [];    % [] for full file duration
MAX_AMP     = [];    % Max amplitude limit (empty = auto-scale)

% Spectrogram Windowing for Discrete Tone Steps
WINDOW_LEN  = 1024;  
OVERLAP_LEN = 512;   
SAVE_IMAGE  = false; % Only save .fig by default (no SVG)
SAVE_FIG    = true;  % Save interactive MATLAB .fig file (enables zoom/pan in MATLAB)
SHOW_PLOTS  = false; % Set to true to display figures while running

% Signal Alignment
AUTO_ALIGN    = true; % Auto-align using first spike peak as reference
PRE_TRIGGER_S = 0.2;  % Pre-trigger duration (seconds) before peak to retain

%% Validate Input Directory
if ~exist(INPUT_ROOT, 'dir')
    warning('Input directory "%s" does not exist. Creating folder structure...', INPUT_ROOT);
    mkdir(INPUT_ROOT);
    fprintf('Please place your trial folders inside "%s" and run again.\n', INPUT_ROOT);
    return;
end

%% Discover Trial Folders
trialDirs = dir(INPUT_ROOT);
trialDirs = trialDirs([trialDirs.isdir] & ~ismember({trialDirs.name}, {'.', '..'}));

if isempty(trialDirs)
    fprintf('No trial folders found in "%s".\n', INPUT_ROOT);
    return;
end

%% Initialize Acoustic Analyzer
analyzer = AudioAnalyzer('', ...
    'TimeRange', TIME_RANGE, ...
    'MaxAmplitude', MAX_AMP, ...
    'MaxFrequency', MAX_FREQ, ...
    'WindowLength', WINDOW_LEN, ...
    'OverlapLength', OVERLAP_LEN, ...
    'SaveImage', SAVE_IMAGE, ...
    'SaveFig', SAVE_FIG, ...
    'VisibleFigures', SHOW_PLOTS, ...
    'ModelLength', MODEL_LENGTH, ...
    'PipeDiameter', PIPE_DIAMETER, ...
    'SoundSpeed', SOUND_SPEED, ...
    'EnableDistance', ENABLE_DISTANCE, ...
    'AutoAlign', AUTO_ALIGN, ...
    'PreTriggerSeconds', PRE_TRIGGER_S);

totalFilesProcessed = 0;

%% Process Each Trial and Audio File
for t = 1:length(trialDirs)
    trialName = trialDirs(t).name;
    trialPath = fullfile(INPUT_ROOT, trialName);
    
    % Find all supported audio files (.mp3, .wav)
    audioFiles = dir(fullfile(trialPath, '*.mp3'));
    if isempty(audioFiles)
        audioFiles = dir(fullfile(trialPath, '*.wav'));
    end
    
    fprintf('\n--- Processing trial [%d/%d]: %s (%d files) ---\n', ...
        t, length(trialDirs), trialName, length(audioFiles));

    for f = 1:length(audioFiles)
        fileName = audioFiles(f).name;
        [~, baseName, ~] = fileparts(fileName);
        filePath = fullfile(trialPath, fileName);
        
        analyzer.TitlePrefix = sprintf('%s-%s', trialName, baseName);
        targetDir = fullfile(OUTPUT_ROOT, trialName, baseName);
        
        try
            analyzer.loadFile(filePath);
            analyzer.analyzeAndExport(targetDir);
            totalFilesProcessed = totalFilesProcessed + 1;
            
            % Generate 1-click MATLAB hyperlinks for Command Window
            ampFig     = fullfile(targetDir, 'amplitude.fig');
            freqFig    = fullfile(targetDir, 'frequency.fig');
            specFig    = fullfile(targetDir, 'spectrogram.fig');

            linkAmp  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amplitude.fig]</a>', strrep(ampFig, '\', '/'));
            linkFreq = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Frequency.fig]</a>', strrep(freqFig, '\', '/'));
            linkSpec = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram.fig]</a>', strrep(specFig, '\', '/'));
            linkDir  = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));

            fprintf('  [OK] %-8s -> 1-Click: %s %s %s | %s\n', ...
                fileName, linkAmp, linkFreq, linkSpec, linkDir);

        catch ME
            fprintf(2, '  [ERROR] Failed to process %s: %s\n', fileName, ME.message);
        end
    end
end

fprintf('\nDone! Successfully processed %d audio files into "%s".\n', totalFilesProcessed, OUTPUT_ROOT);
