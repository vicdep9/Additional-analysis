function outFiles = warpWNFrames(inFiles, opts)
% warpWNFrames  Perspective-warp WN frame PNGs so they look like a tilted screen.
%
%   outFiles = warpWNFrames()                    % all Results\WN_frames\WN_frame_*.png
%   outFiles = warpWNFrames(inFiles, 'Yaw', 35, 'Pitch', 10, 'Focal', 2)
%
%   The frame is treated as a flat rectangle in 3D, rotated by Yaw (about the
%   vertical axis) and Pitch (about the horizontal axis), then projected with a
%   pinhole camera. The 4 projected corners define a projective transform
%   (fitgeotform2d) that is applied with imwarp. Outside the screen is
%   transparent (PNG alpha).
%
% Options
%   Yaw (35)      deg; + = right edge turned away from the viewer
%   Pitch (0)     deg; + = top edge turned away from the viewer
%   Focal (2)     camera distance in screen widths; smaller = stronger perspective
%   Interp ('linear')  'nearest' keeps hard edges but looks jagged once tilted
%   Border (0)    px of black frame drawn around the screen before warping (0 = none)
%   OutDir        default: <folder of inFiles>\warped
%
%   Returns the saved file names: <name>_warp_y<Yaw>_p<Pitch>.png

arguments
    inFiles = fullfile(fileparts(mfilename('fullpath')), 'Results', 'WN_frames', 'WN_frame_*.png')
    opts.Yaw (1,1) double = 35
    opts.Pitch (1,1) double = 0
    opts.Focal (1,1) double {mustBePositive} = 2
    opts.Interp (1,:) char {mustBeMember(opts.Interp, {'linear', 'nearest', 'cubic'})} = 'linear'
    opts.Border (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    opts.OutDir (1,:) char = ''
end

% expand a wildcard / folder / list into a cellstr of files
if ischar(inFiles) || isstring(inFiles)
    inFiles = cellstr(inFiles);
end
files = {};
for i = 1:numel(inFiles)
    d = dir(inFiles{i});
    d = d(~[d.isdir]);
    files = [files, fullfile({d.folder}, {d.name})]; %#ok<AGROW>
end
assert(~isempty(files), 'No input images found.');
outDir = opts.OutDir;
if isempty(outDir), outDir = fullfile(fileparts(files{1}), 'warped'); end
if ~isfolder(outDir), mkdir(outDir); end

outFiles = cell(1, numel(files));
for i = 1:numel(files)
    img = imread(files{i});
    if opts.Border > 0
        img = padarray(img, [opts.Border opts.Border], 0);
    end
    [h, w, ~] = size(img);

    tform = tiltTransform(w, h, opts.Yaw, opts.Pitch, opts.Focal);
    warped = imwarp(img, tform, opts.Interp, 'FillValues', 0);
    alpha  = imwarp(ones(h, w), tform, opts.Interp, 'FillValues', 0);   % screen mask

    [~, name] = fileparts(files{i});
    outFiles{i} = fullfile(outDir, sprintf('%s_warp_y%g_p%g.png', name, opts.Yaw, opts.Pitch));
    imwrite(warped, outFiles{i}, 'Alpha', alpha);
    fprintf('Saved %s\n', outFiles{i});
end
end

%% Local functions
function tform = tiltTransform(w, h, yaw, pitch, focal)
% corners of the image (x right, y down), centred on the origin, z = 0
src = [1 1; w 1; w h; 1 h];
P = [src - [(w+1)/2 (h+1)/2], zeros(4, 1)];
% rotate: yaw about the vertical (y) axis, pitch about the horizontal (x) axis
% (signs chosen so +yaw pushes the right edge, +pitch the top edge, to +z = away)
Ry = [cosd(yaw) 0 -sind(yaw); 0 1 0; sind(yaw) 0 cosd(yaw)];
Rx = [1 0 0; 0 cosd(pitch) sind(pitch); 0 -sind(pitch) cosd(pitch)];
P = (Rx * Ry * P')';
% pinhole projection, camera at distance f in front of the screen (+z = away)
f = focal * max(w, h);
dst = f * P(:, 1:2) ./ (f + P(:, 3));
dst = dst - min(dst) + 1;                       % shift into positive pixel coords
tform = fitgeotform2d(src, dst, 'projective');
end
