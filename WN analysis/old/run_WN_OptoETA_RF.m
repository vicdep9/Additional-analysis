% Run the opto event-triggered average + white-noise RF analysis.
% Results (figures + .mat) go to <outRoot>\Results\<TSeries name>\

dataPath = 'D:\Data\CBLN4-ChRmine\processedData\20261005_mAK02\Recording1\TSeries-10052026-mAK02-LH-cbln4-G6sflxchrmine-influence-5HzWN-1067';
outRoot  = 'D:\Data\Claude Projects\WN analysis';

R = WN_OptoETA_RF(dataPath, outRoot, ...
    'Window', [-0.5 1.5], ...       % s around each photostim trigger
    'ControlTarget', 1, ...
    'TargetROI', [7 124], ...       % manual matches [target roi; ...]
    'RFLags', 0:0.2:2, ...          % s between noise frame and response
    'NShuffles', 50, ...
    'RFzThresh', 5);
