function figOut = stack_figures(path1, path2, varargin)
% STACK_FIGURES Displays two MATLAB figures (.fig) or image files together:
%   - 'overlay' mode: Plots Graph 1 directly on top of Graph 2 on the same axes.
%   - 'stack' mode:   Places Graph 1 in a top panel and Graph 2 in a bottom panel.
%
% Usage:
%   stack_figures('0/amplitude.fig', '1/amplitude.fig', 'Mode', 'overlay') % Overlaid on same plot
%   stack_figures('0/amplitude.fig', '1/amplitude.fig', 'out.svg', 'Mode', 'overlay') % Exported to out.svg
%   stack_figures('0/amplitude.fig', '1/amplitude.fig', 'Mode', 'stack')   % Top / Bottom panels

p = inputParser;
addRequired(p, 'path1', @ischar);
addRequired(p, 'path2', @ischar);
addParameter(p, 'OutputPath', '', @ischar);
addParameter(p, 'Mode', 'overlay', @(x) any(validatestring(x, {'overlay', 'stack'})));
addParameter(p, 'TopTitle', '', @ischar);
addParameter(p, 'BottomTitle', '', @ischar);
addParameter(p, 'Label1', 'Trial 0 (Blocked)', @ischar);
addParameter(p, 'Label2', 'Trial 1 (Clean)', @ischar);
addParameter(p, 'Alpha', 0.55, @(x) isnumeric(x) && x >= 0 && x <= 1);
addParameter(p, 'Color1', [0.88, 0.22, 0.18], @isnumeric); % Dimmed Red
addParameter(p, 'Color2', [0.12, 0.52, 0.88], @isnumeric); % Dimmed Sky Blue
addParameter(p, 'LinkX', true, @islogical);

% Detect optional positional outputPath if 3rd argument is not a param name
if ~isempty(varargin) && ischar(varargin{1}) && ~ismember(lower(varargin{1}), ...
        {'mode', 'toptitle', 'bottomtitle', 'label1', 'label2', 'alpha', 'color1', 'color2', 'linkx', 'outputpath'})
    optOut = varargin{1};
    remArgs = varargin(2:end);
else
    optOut = '';
    remArgs = varargin;
end

parse(p, path1, path2, remArgs{:});

outPath = p.Results.OutputPath;
if isempty(outPath)
    outPath = optOut;
end

% Check file existence
if ~exist(path1, 'file')
    error('First file not found: %s', path1);
end
if ~exist(path2, 'file')
    error('Second file not found: %s', path2);
end

[dir1, name1, ext1] = fileparts(path1);
[dir2, name2, ext2] = fileparts(path2);

% Auto-resolve .svg to .fig if corresponding .fig exists in the folder
if strcmpi(ext1, '.svg') && exist(fullfile(dir1, [name1, '.fig']), 'file')
    path1 = fullfile(dir1, [name1, '.fig']);
    ext1 = '.fig';
end
if strcmpi(ext2, '.svg') && exist(fullfile(dir2, [name2, '.fig']), 'file')
    path2 = fullfile(dir2, [name2, '.fig']);
    ext2 = '.fig';
end

%% Branch 1: Handling MATLAB .fig files (Interactive vector axes)
if strcmpi(ext1, '.fig') && strcmpi(ext2, '.fig')
    fig1 = openfig(path1, 'new', 'invisible');
    fig2 = openfig(path2, 'new', 'invisible');
    c1 = onCleanup(@() closeSafely(fig1));
    c2 = onCleanup(@() closeSafely(fig2));

    ax1 = findobj(fig1, 'Type', 'axes');
    ax2 = findobj(fig2, 'Type', 'axes');

    if isempty(ax1) || isempty(ax2)
        error('Could not extract axes from one of the .fig files.');
    end
    % If multiple axes (e.g., colorbars), take the primary data axes
    ax1 = ax1(end);
    ax2 = ax2(end);

    %% Overlay Mode: Graph 1 plotted directly on top of Graph 2 on same axes
    if strcmpi(p.Results.Mode, 'overlay')
        figOut = figure('Units', 'normalized', 'Position', [0.15, 0.15, 0.7, 0.7]);
        newAx = axes(figOut);
        hold(newAx, 'on');

        alphaVal = p.Results.Alpha;
        color1_rgba = [p.Results.Color1(1:3), alphaVal];
        color2_rgba = [p.Results.Color2(1:3), alphaVal];

        % Copy Graph 2 (Base curve - e.g. Clean) in Dimmed Blue
        ch2 = allchild(ax2);
        h2 = copyobj(ch2, newAx);
        for i = 1:length(h2)
            if isprop(h2(i), 'Color')
                h2(i).Color = color2_rgba;
                h2(i).LineWidth = 1.3;
            end
        end

        % Copy Graph 1 (On top curve - e.g. Blocked) in Dimmed Red
        ch1 = allchild(ax1);
        h1 = copyobj(ch1, newAx);
        for i = 1:length(h1)
            if isprop(h1(i), 'Color')
                h1(i).Color = color1_rgba;
                h1(i).LineWidth = 1.3;
            end
        end

        copyAxesProperties(ax1, newAx);
        
        % Add clear legend
        lines1 = findobj(h1, 'Type', 'line');
        lines2 = findobj(h2, 'Type', 'line');
        if ~isempty(lines1) && ~isempty(lines2)
            legend(newAx, [lines1(1), lines2(1)], {p.Results.Label1, p.Results.Label2}, ...
                'Location', 'best', 'Interpreter', 'none');
        end

        title(newAx, sprintf('Overlay Comparison: %s on top of %s', p.Results.Label1, p.Results.Label2), ...
            'Interpreter', 'none');
        grid(newAx, 'on');
        hold(newAx, 'off');
        zoom(figOut, 'on');

    %% Stack Mode: 2-Row Vertical Panels (Top & Bottom)
    else
        figOut = figure('Units', 'normalized', 'Position', [0.15, 0.1, 0.7, 0.8]);
        tiled = tiledlayout(figOut, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

        % Copy top axes
        newAx1 = nexttile(tiled, 1);
        copyobj(allchild(ax1), newAx1);
        copyAxesProperties(ax1, newAx1);
        if ~isempty(p.Results.TopTitle)
            title(newAx1, p.Results.TopTitle, 'Interpreter', 'none');
        end

        % Copy bottom axes
        newAx2 = nexttile(tiled, 2);
        copyobj(allchild(ax2), newAx2);
        copyAxesProperties(ax2, newAx2);
        if ~isempty(p.Results.BottomTitle)
            title(newAx2, p.Results.BottomTitle, 'Interpreter', 'none');
        end

        % Synchronize horizontal zooming/panning
        if p.Results.LinkX
            linkaxes([newAx1, newAx2], 'x');
        end

        zoom(figOut, 'on');
    end

%% Branch 2: Handling image files (.png, .jpg)
else
    img1 = imread(path1);
    img2 = imread(path2);

    % Match width by padding if necessary
    w1 = size(img1, 2);
    w2 = size(img2, 2);
    targetW = max(w1, w2);

    if w1 < targetW
        pad = 255 * ones(size(img1, 1), targetW - w1, size(img1, 3), 'like', img1);
        img1 = [img1, pad];
    elseif w2 < targetW
        pad = 255 * ones(size(img2, 1), targetW - w2, size(img2, 3), 'like', img2);
        img2 = [img2, pad];
    end

    stackedImg = [img1; img2];

    figOut = figure('Visible', 'on');
    imshow(stackedImg);
end

%% Export combined output if destination specified
if ~isempty(outPath)
    [outDir, ~, outExt] = fileparts(outPath);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    if strcmpi(outExt, '.fig')
        savefig(figOut, outPath);
    else
        saveas(figOut, outPath);
    end
    fprintf('[Saved] Combined stacked figure: %s\n', outPath);
end

end

%% Helper: Copy essential styling properties between axes
function copyAxesProperties(srcAx, dstAx)
    dstAx.XLim = srcAx.XLim;
    dstAx.YLim = srcAx.YLim;
    dstAx.XScale = srcAx.XScale;
    dstAx.YScale = srcAx.YScale;
    dstAx.XDir = srcAx.XDir;
    dstAx.YDir = srcAx.YDir;
    dstAx.XGrid = srcAx.XGrid;
    dstAx.YGrid = srcAx.YGrid;
    dstAx.XMinorGrid = srcAx.XMinorGrid;
    dstAx.YMinorGrid = srcAx.YMinorGrid;
    dstAx.Box = srcAx.Box;

    xlabel(dstAx, srcAx.XLabel.String, 'Interpreter', srcAx.XLabel.Interpreter);
    ylabel(dstAx, srcAx.YLabel.String, 'Interpreter', srcAx.YLabel.Interpreter);
    title(dstAx, srcAx.Title.String, 'Interpreter', srcAx.Title.Interpreter);
end

%% Helper: Safely close figure handle
function closeSafely(f)
    if ~isempty(f) && isvalid(f)
        close(f);
    end
end
