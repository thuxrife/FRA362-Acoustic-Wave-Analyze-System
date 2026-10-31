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

% Pipe Duct Geometry & Reflectometry Settings
MODEL_LENGTH    = 2.0;   % Pipe length in meters (L)
PIPE_DIAMETER   = 0.15;  % Model pipe diameter (150 mm = 0.15 m)
SOUND_SPEED     = 346.0; % Speed of sound in air at ~25 C (m/s)
ENABLE_DISTANCE = true;  % Export amplitude-distance plot
KNOWN_BLOCKAGE  = 0.40;  % Known blockage position in x/L (empty [] or NaN if unplaced)

% Acoustic Cut-off & Frequency Bounds
% Cut-off for 150mm circular pipe: f_c = 0.586 * v / D ~ 1352 Hz
MAX_FREQ    = 1500;  % Display through 1500 Hz to show cut-off boundary at ~1352 Hz
TIME_RANGE  = [];    % [] for full file duration
MAX_AMP     = [];    % Max amplitude limit (empty = auto-scale)

% Spectrogram Windowing for Discrete Tone Steps
WINDOW_LEN  = 1024;  
OVERLAP_LEN = 512;   
SAVE_FORMAT = 'svg'; % Image export format ('svg', 'png', etc.)
SAVE_FIG    = true;  % Save interactive MATLAB .fig file (enables zoom/pan in MATLAB)
SHOW_PLOTS  = false; % Set to true to display figures while running

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
    'SaveFormat', SAVE_FORMAT, ...
    'SaveFig', SAVE_FIG, ...
    'VisibleFigures', SHOW_PLOTS, ...
    'ModelLength', MODEL_LENGTH, ...
    'PipeDiameter', PIPE_DIAMETER, ...
    'SoundSpeed', SOUND_SPEED, ...
    'EnableDistance', ENABLE_DISTANCE, ...
    'KnownBlockage', KNOWN_BLOCKAGE);

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
            ampDistFig = fullfile(targetDir, 'amplitude-distance.fig');

            linkAmp  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amplitude]</a>', strrep(ampFig, '\', '/'));
            linkFreq = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Frequency]</a>', strrep(freqFig, '\', '/'));
            linkSpec = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram]</a>', strrep(specFig, '\', '/'));
            linkDist = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amp-Dist]</a>', strrep(ampDistFig, '\', '/'));
            linkDir  = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));

            fprintf('  [OK] %-8s -> 1-Click: %s %s %s %s | %s\n', ...
                fileName, linkAmp, linkFreq, linkSpec, linkDist, linkDir);

        catch ME
            fprintf(2, '  [ERROR] Failed to process %s: %s\n', fileName, ME.message);
        end
    end
end

fprintf('\nDone! Successfully processed %d audio files into "%s".\n', totalFilesProcessed, OUTPUT_ROOT);
