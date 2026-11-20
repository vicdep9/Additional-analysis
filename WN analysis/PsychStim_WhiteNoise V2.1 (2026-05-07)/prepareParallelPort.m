function [ioObj,address] =  prepareParallelPort(physicalAddress)
    % physicalAddress: String(e.g. 'D010', can be found in Windows Device Manger -> Ports -> Resources

    %create an instance of the io32 object
    ioObj = io64;

    %initialize the inpoutx64 system driver
    status = io64(ioObj);
    %if status = 0, you are now ready to write and read to a hardware port

    if(status == 0)

        fprintf(repmat('\b',1,25));
        fprintf(repmat('\b',1,15));

        address = hex2dec(physicalAddress);          %LPT1 output port address

        %Test if the address is right or not
        data_out = bin2dec('11110000');
        io64(ioObj,address, data_out ); %pin[9 8 7 6 5 4 3 2]
        data_in=io64(ioObj,address);
        if( data_in ~= data_out )
            fprintf( 'Parallel Port Error!\n');
            clear all;
            return;
        else
            io64(ioObj,address, bin2dec('00000000')); %pin[9 8 7 6 5 4 3 2] 
        end

        %output command
        data_in=io64(ioObj,address);
        if( data_in ~= 0 )
            io64(ioObj,address, bin2dec('00000000')); %pin[9 8 7 6 5 4 3 2]  

            %check the ioObj is right
            data_in=io64(ioObj,address);
            if( data_in ~= 0 )
                fprintf( 'Parallel Port Error!\n');
                clear all;
                return;
            end
        end

    else
        fprintf( 'Parallel Port Error!\n');
        clear all;
    end

    % For MEA Recording
    %                   pin [2 3 4 5    ]
    % startRecordingTrigger [x - - - GND] signals the array to start recording
    % stimulusTrigger       [- x - - GND] signals the start of each new stimulus type
    % stimulusTrigger       [- - x - GND] signals the start of each stimulus pattern (Frames)
    % stopRecordingTrigger  [- - - x GND] signals the array to stop recording

