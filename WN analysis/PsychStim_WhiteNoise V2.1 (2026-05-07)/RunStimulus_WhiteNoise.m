function RunStimulus_WhiteNoise(Parameters)
% V2.1 (2026-05-07) by Hui Chen

    try         % put this is a try/catch, so that any crash won't leave screen hung
        
        fprintf( '\n\n\n\n\n' );
        
        
        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % 1. Initialize Parameters
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        %--------------------------------------------------------------------------
        % 1) Initialize Paralle Ports
        SyncType    = Parameters.SyncSourceVal;
        if strcmp( SyncType, 'Intan' ) || strcmp( SyncType, '2-photon' )
            triggerSync = 1;
        else
            triggerSync = 0;
        end

        if triggerSync
            %pin[9 8 7 6 5 4 3 2]
            [ioObj_Cond, address_Cond] = prepareParallelPort(Parameters.ParallelPortAddress_Cond);   
            io64(ioObj_Cond, address_Cond, 0);

            %pin[X X X X X X 3 2] 
            if isfield(Parameters, 'ParallelPortAddress_Stim' )
                [ioObj_Stim, address_Stim] = prepareParallelPort(Parameters.ParallelPortAddress_Stim);   
                io64(ioObj_Stim, address_Stim, 0);
            else
                ioObj_Stim      = [];
                address_Stim    = [];
            end
        end

        %--------------------------------------------------------------------------
        % 2) Initialize Screen
        InitializeMatlabOpenGL;                              % necessary for OpenGL calls (like ClutBlit)
        Screen('Preference', 'VBLTimestampingMode', 1);      % Enable beam position queries to allow accurate time stamping.
                                                             % This is disabled by default in Windows Dual Screen mode
        Screen('Preference', 'SkipSyncTests',       1);
        Screen('Preference', 'VisualDebuglevel',    3);      % Do no show Psychtoolbox start screen
        Screen('Preference', 'SuppressAllWarnings', 1);      % Do not show warning message
        Screen('Preference', 'Verbosity', 1);
        AssertOpenGL;

        [window, windowRect]            = Screen(Parameters.ScreenID, 'OpenWindow', 0);               % open window
        [ScreenCenterX, ScreenCenterY]  = RectCenter(windowRect);
         white                          = WhiteIndex(window);
         black                          = BlackIndex(window);
        
        % gamma correction
        flat_clut       = [(0:1/255:1)' (0:1/255:1)' (0:1/255:1)'];
        gamma_clut      = flat_clut.^( 1/Parameters.gamma );
        if Parameters.RecordStimulusVideo
            
        else
            Screen( 'LoadNormalizedGammaTable', window, gamma_clut );
        end
        clear gamma_clut
        
        % Enable alpha blending for typical drawing of masked textures:
        Screen('BlendFunction', window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        % Make sure this GPU supports shading at all:
        AssertGLSL;

        % Create a special texture drawing shader for masked texture drawing:
%       glsl = MakeTextureDrawShader(window, 'SeparateAlphaChannel');

        % Prepare to Record Stimulus Movie
        if Parameters.RecordStimulusVideo
            if isempty(Parameters.RecordVideoName)
                Parameters.RecordVideoName = 'StimulusVideo.mov';
            end
            moviePtr = Screen('CreateMovie', window, Parameters.RecordVideoName, [], [], Parameters.RefreshRate, ...
                              ':CodecSettings=Videoquality=0.5 Profile=2', 1, 8 ); 
        end
        
        %--------------------------------------------------------------------------
        % 3) Initialize parameters           
        ifi                 = 1/Parameters.RefreshRate;
        DegPerPix           = Parameters.DegX / Parameters.PixelsX;
        PixPerDeg           = 1/DegPerPix;
        
        PositionX           = round( Parameters.PositionX  * PixPerDeg );
        PositionY           = round( Parameters.PositionY  * PixPerDeg );

        GridNumber_X        = Parameters.GridNumber_X;
        GridNumber_Y        = Parameters.GridNumber_Y;
        GridWidth           = round( Parameters.GridWidth  * PixPerDeg );
        
        FrameDuration       = Parameters.FrameDuration;
        Parameters.WaitInterval = 1;
        
        BackgroundColor     = round( 0.5 *(black + white) );
        if Parameters.RecordStimulusVideo
            BackgroundColor = (BackgroundColor / 255) .^( 1/Parameters.gamma ) * 255;
        end
        
        Nimg                = Parameters.Nimg;
        NoiseImg            = Parameters.NoiseImg;
        
        % Set up texture components (ref FastNoiseDemo.m in Psychtoolbox)
        objRect             = SetRect(0,0, GridNumber_X, GridNumber_Y);
        dstRect             = CenterRectOnPoint(objRect * GridWidth, ScreenCenterX + PositionX, ScreenCenterY + PositionY);

        %--------------------------------------------------------------------------
        % 4) Log File
        logFileID           = fopen(Parameters.LogFileName, 'wt');
        

        
        %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % 2. finally, run stimulus!!
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%Ma%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        fprintf( '\n\n\n\n\n' );
        fprintf( '--------------------------------------------------\n');
        startTime    = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
        fprintf(            'Start Stimulus %s at %s\n',  'Show Image', startTime );
        fprintf(logFileID,  'Start Stimulus %s at %s\n',  'Show Image', startTime );
        tic;
        
        % 2) start listening for keyboard input
        ListenChar(2);                                                              
        Priority(2);
        
        %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        % 3) Start Recroding
        if triggerSync
            sendTriggerForStimulus(Parameters, SyncType, 'Start_Recording', ioObj_Cond, address_Cond, ioObj_Stim, address_Stim, ...
                                   [], [], [], [], [] ); 
        end
        %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        
        Screen('FillRect', window, BackgroundColor);
        Screen('Flip',     window);
        WaitSecs(1);
        
        vbl = Screen('Flip', window);
        
        frameIter   = 1;
        while frameIter <= Nimg

            noiseimg        = NoiseImg( frameIter, 1 : GridNumber_Y * GridNumber_X );
            noiseimg        = reshape(noiseimg, [GridNumber_Y GridNumber_X]);
            
            if Parameters.RecordStimulusVideo
            	noiseimg    = (noiseimg ./255) .^ (1/Parameters.gamma) * 255;
            end
                    
            tex             = Screen('MakeTexture', window, noiseimg);
            
            Screen('DrawTexture', window, tex, [], dstRect, [], 0);
            Screen('Close', tex);
            
            %-------------------------------------------------------------------------- 
            % Saving Vidio
            if Parameters.RecordStimulusVideo
                Screen('AddFrameToMovie', window, [], 'frontBuffer', moviePtr, FrameDuration );
                % Screen('AddFrameToMovie', windowPtr, CenterRect([0 0 512 512], Screen('Rect', scrnNum)), 'frontBuffer');
            end
            
            %-------------------------------------------------------------------------- 
            % Show it at next retrace:
            vbl = Screen('Flip', window, vbl + (FrameDuration - 0.5) * ifi,[],[],1);
            
            %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
            % Send Stimulus, Condition, Frame and Simulation trigger out
            if triggerSync

                if Parameters.UsePhotoStimulation && rem(frameIter, Parameters.StimulationFrequency)==1
                    sendTriggerForStimulus(Parameters, SyncType, 'Stimulus', ioObj_Cond, address_Cond, ioObj_Stim, address_Stim, ...
                                                              1, 1, 1, 1, 1 );

                else
                    sendTriggerForStimulus(Parameters, SyncType, 'Stimulus', ioObj_Cond, address_Cond, ioObj_Stim, address_Stim, ...
                                                              0, 1, 1, 1, [] );
                end
            end
            %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

            if KbCheck                                      
                break;
            end
            
            frameIter   = frameIter +1;
        end
        
        Screen('FillRect', window, BackgroundColor);
        Screen('Flip',     window);
%       WaitSecs(1);
        
        
        %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        % Stop Recording
        if triggerSync
            sendTriggerForStimulus(Parameters, SyncType, 'Stop_Recording', ioObj_Cond, address_Cond, ioObj_Stim, address_Stim, ...
                                   [], [], [], [], [] );
        end
        %XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
        
        endTime     = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
        totalTime   = toc;
        fprintf(             '\nStimulus ends at %s. The duration is %.0f (s).\n', endTime, totalTime);
        fprintf( logFileID,  '\nStimulus ends at %s. The duration is %.0f (s).\n', endTime, totalTime);

        if Parameters.RecordStimulusVideo
            Screen('FinalizeMovie', moviePtr);
        end

        %-------------------------------------------------------------------------- 
        % Cleanup 
        %-------------------------------------------------------------------------- 
        Screen('LoadNormalizedGammaTable', window, flat_clut);
        Screen('CloseAll');

        ListenChar(1);  % stop listening for keyboard input
        Priority(0);

        fprintf('\n\n');
        
        clear all %#ok<CLALL>

        
    
    catch   % if there's an error, clean up and rethrow the error

        flat_clut	= [(0:1/255:1)' (0:1/255:1)' (0:1/255:1)'];
        Screen('LoadNormalizedGammaTable', window, flat_clut);
        Screen('CloseAll');

        ListenChar(1);                                                      % stop listening for keyboard input
        Priority(0);

        fprintf('\n\n');
        
        psychrethrow(psychlasterror);
        
        clear all %#ok<CLALL>
        
    end
    
    
end


