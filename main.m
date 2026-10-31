%% Main Batch Processing Script
% Scans input directory hierarchy: mp3/{trial_folder}/{id}.mp3
% Outputs analysis plots to: analyze/{trial_folder}/{id}/
%
% Generates 3 raw acoustic plots per audio file:
% 1. Amplitude vs Time (amplitude.svg / .fig)
% 2. Frequency Spectrum (frequency.svg / .fig)
% 3. Spectrogram (spectrogram.svg / .fig)

clear; clc;

%% Configuration
INPUT_ROOT  = 'mp3';
OUTPUT_ROOT = 'analyze';

% Time & Frequency Windowing
TIME_RANGE  = [];    % [] for full file duration (10-20s)
MAX_AMP     = [];    % Max amplitude limit (empty = auto-scale)
MAX_FREQ    = 3000;  % Focus display on acoustic experiment band (0 to 3000 Hz)

% Spectrogram Windowing for 10-20s Stepped Frequency Recordings
WINDOW_LEN  = 1024;  % Gives sharp frequency bins for discrete tone steps
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
    'VisibleFigures', SHOW_PLOTS);

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
            ampFig  = fullfile(targetDir, 'amplitude.fig');
            freqFig = fullfile(targetDir, 'frequency.fig');
            specFig = fullfile(targetDir, 'spectrogram.fig');

            linkAmp  = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Amplitude]</a>', strrep(ampFig, '\', '/'));
            linkFreq = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Frequency]</a>', strrep(freqFig, '\', '/'));
            linkSpec = sprintf('<a href="matlab:openfig(''%s'', ''visible'');">[Spectrogram]</a>', strrep(specFig, '\', '/'));
            linkDir  = sprintf('<a href="matlab:winopen(''%s'');">[Open Folder]</a>', strrep(targetDir, '\', '/'));

            fprintf('  [OK] %-8s -> 1-Click: %s %s %s | %s\n', ...
                fileName, linkAmp, linkFreq, linkSpec, linkDir);

        catch ME
            fprintf(2, '  [ERROR] Failed to process %s: %s\n', fileName, ME.message);
        end
    end
end

fprintf('\nDone! Successfully processed %d audio files into "%s".\n', totalFilesProcessed, OUTPUT_ROOT);
