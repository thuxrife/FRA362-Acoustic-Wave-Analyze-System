% STARTUP.M - FRA362 Acoustic Wave Analysis System Environment Initializer
% Automatically executed when MATLAB opens in the project root directory.

fprintf('[FRA362] Initializing Acoustic Wave Analysis System...\n');
repoRoot = fileparts(mfilename('fullpath'));
scriptDir = fullfile(repoRoot, 'MATLAB-script');

if exist(scriptDir, 'dir')
    addpath(scriptDir);
    fprintf('[FRA362] Added "MATLAB-script/" to MATLAB search path.\n');
else
    warning('[FRA362] Directory "MATLAB-script/" not found at %s', scriptDir);
end
