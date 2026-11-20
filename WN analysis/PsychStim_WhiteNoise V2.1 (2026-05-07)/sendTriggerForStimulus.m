function flagNewCondition = sendTriggerForStimulus(Parameters, SyncType, TrigerType, ioObj_Cond, address_Cond, ioObj_Stim, address_Stim, ...
                                                   flagNewCondition, nCond, currentCond, conditionIter, stimulation )

    % ------------------------------------------------------------------------------
    % For Intan :  [X(8), X(7), X(6), X(5), X(4), Trigger(3); Frame(2); Stimulus(1)]
    % ------------------------------------------------------------------------------
    if      strcmp( SyncType, 'Intan' )

        % ------------------------------------------------------------------------------
        if strcmpi( TrigerType, 'Start_Recording' )
            io64(ioObj_Stim, address_Stim, bin2dec('00000100') );   
            
        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Stop_Recording' )
            io64(ioObj_Stim, address_Stim,   0 ); 
            io64(ioObj_Cond, address_Cond,   0 );

        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Stimulus' )

            % New Condition
            if flagNewCondition
                if nCond<=255
                    io64( ioObj_Cond, address_Cond,   currentCond);
                else
                    trigger     = rem( currentCond, 255 );
                    if trigger  == 0, trigger = 255; end
                    io64( ioObj_Cond, address_Cond,   trigger);
                end
    
                flagNewCondition    = 0;
            end
    
            % With Inter Stimulus Interval, Keep Stimulus trigger ON
            if Parameters.WaitInterval > 0
                    % [X(8), X(7), X(6), X(5), X(4), Trigger(3); Frame(2); Stimulus(1)]
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000111') );
                    WaitSecs(0.0001);
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000101') );
    
            % Stimulus without Inter Stimulus Interval, switch Stimulus trigger between ON and OFF 
            else
                % Odd Number - Stimulus trigger  ON
                if mod(conditionIter, 2) == 0 
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000111') );
                    WaitSecs(0.0001);
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000101') );
    
                % Even Number - Stimulus trigger  OFF
                else
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000110') );
                    WaitSecs(0.0001);
                    io64( ioObj_Stim,   address_Stim,   bin2dec('00000100') );
                end
            end

        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Interval' )
            io64( ioObj_Stim,   address_Stim,   bin2dec('00000110') );
            WaitSecs(0.0001);
            io64( ioObj_Stim,   address_Stim,   bin2dec('00000100') );
        end
    % ------------------------------------------------------------------------------


    % ------------------------------------------------------------------------------
    % For 2-photon : [x(8), x(7), x(6), Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)]
    % ------------------------------------------------------------------------------
    elseif  strcmp( SyncType, '2-photon' )   
        % ------------------------------------------------------------------------------
        if strcmpi( TrigerType, 'Start_Recording' )
            io64(ioObj_Cond, address_Cond, bin2dec('00000001') ); 

        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Stop_Recording' )
            io64(ioObj_Cond,   address_Cond,   0 );  

            if ~isempty(ioObj_Stim) && ~isempty(address_Stim)
                io64(ioObj_Stim,   address_Stim, 0 ); 
            end
        
        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Stimulus' )

            % With Inter Stimulus Interval, Keep Stimulus trigger ON
            if Parameters.WaitInterval > 0
                % New Condition
                if flagNewCondition
    
                    % Send Stimulation
                    if ismember( currentCond, stimulation)
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00011111') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000011') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                    else
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00001111') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000011') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                    end
    
                    flagNewCondition    = 0;
                else
                    io64( ioObj_Cond,   address_Cond,   bin2dec('00001011') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                    WaitSecs(0.002);
                    io64( ioObj_Cond,   address_Cond,   bin2dec('00000011') );      % Stimulation(5), Frame(4), Condition(3), Stimulus(2), Trigger(1)
                end
    
            % Stimulus without Inter Stimulus Interval, switch Stimulus trigger between ON and OFF 
            else
                % Odd Number - Stimulus trigger  ON
                if mod(conditionIter, 2) == 0 
                    % New Condition
                    if flagNewCondition
    
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00001111') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000011') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
    
                        flagNewCondition    = 0;
                    else
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00001011') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000011') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                    end
                % Even Number - Stimulus trigger  OFF
                else
                    % New Condition
                    if flagNewCondition
    
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00001101') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000001') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
    
                        flagNewCondition    = 0;
                    else
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00001001') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                        WaitSecs(0.002);
                        io64( ioObj_Cond,   address_Cond,   bin2dec('00000001') );  % Frame(4), Condition(3), Stimulus(2), Trigger(1)
                    end
                end
            end

        % ------------------------------------------------------------------------------
        elseif strcmpi( TrigerType, 'Interval' )
            
            io64( ioObj_Cond,   address_Cond,   bin2dec('00001001') ); 
            WaitSecs(0.002);
            io64( ioObj_Cond,   address_Cond,   bin2dec('00000001') ); 

        end
    end