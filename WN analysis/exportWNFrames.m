function frames = exportWNFrames(wnFile, opts)
% exportWNFrames  Save white-noise stimulus frames as PNG images.
%
%   frames = exportWNFrames(wnFile)
%   frames = exportWNFrames(wnFile, 'N', 3, 'Frames', [], 'Scale', 20, 'Seed', [])
%
%   wnFile is the session's *_WhiteNoise.mat (NoiseImg = Nimg x (GridY*GridX),
%   gray levels 0-255). Each row is reshaped to [GridNumber_Y GridNumber_X],
%   exactly as RunStimulus_WhiteNoise.m does before Screen('MakeTexture').
%
% Options
%   N (3)        number of random frames (ignored if Frames is given)
%   Frames ([])  specific frame numbers to export
%   Scale (20)   screen pixels per grid square in the PNG (nearest neighbour)
%   Seed ([])    rng seed for reproducible picks; [] = shuffle
%   OutDir       default: <folder of this file>\Results\WN_frames
%
%   Returns the frame numbers that were saved. Files: WN_frame_<n>.png

arguments
    wnFile (1,:) char
    opts.N (1,1) double {mustBePositive, mustBeInteger} = 3
    opts.Frames (1,:) double = []
    opts.Scale (1,1) double {mustBePositive, mustBeInteger} = 20
    opts.Seed double = []
    opts.OutDir (1,:) char = fullfile(fileparts(mfilename('fullpath')), 'Results', 'WN_frames')
end

m  = load(wnFile, 'NoiseImg', 'GridNumber_X', 'GridNumber_Y');   % not -v7.3, so load once
nx = m.GridNumber_X;
ny = m.GridNumber_Y;
nImg = size(m.NoiseImg, 1);

if isempty(opts.Frames)
    if isempty(opts.Seed), rng('shuffle'); else, rng(opts.Seed); end
    frames = sort(randperm(nImg, opts.N));
else
    frames = opts.Frames;
    assert(all(frames >= 1 & frames <= nImg), 'Frames must be between 1 and %d.', nImg);
end

if ~isfolder(opts.OutDir), mkdir(opts.OutDir); end
for f = frames
    row = m.NoiseImg(f, 1:ny*nx);
    img = reshape(row, [ny nx]);                                      % as shown on screen
    img = uint8(round(kron(img, ones(opts.Scale))));                   % enlarge, keep sharp squares
    fn  = fullfile(opts.OutDir, sprintf('WN_frame_%05d.png', f));
    imwrite(img, fn);
    fprintf('Saved frame %d -> %s\n', f, fn);
end
end
