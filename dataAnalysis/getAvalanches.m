%% Jewel Y. Lee 2017 (Documented. Last updated: Dec 9, 2017)
%  - read BrainGrid simulation result (.h5)
%  - output spike time step and neuron index to <allSpikeTime.csv>
function getAvalanches
spiketime = csvread('allSpikeTimeCount.csv');

frame = spiketime(:,1);         % frames/timeStep that has activities
count = spiketime(:,2);         % spike counts for each frame
space = diff(frame);            % find interspike intervals (ISI)
totalCount = sum(count);
% totalSpace = sum(space);

numSim = 300;                   % number of simulation, 300 half, 600 full
Tsim = 100;                     % 100 seconds long for each simulaiton 
deltaT = 0.0001;                % time step size is 0.1 ms
totalTimeSteps = numSim*Tsim*(1/deltaT);    % tatal number of time steps
meanISI = totalTimeSteps/totalCount;        % mean interspike-interval

fid = fopen('allAvalanche.csv', 'w') ;
fprintf(fid, 'ID,StartRow,EndRow,StartT,EndT,Width,TotalSpikeCount,isBurst\n');
n_aval = 0;                     % number of avalanches
i = 1;                          % incrementer 
while i < length(space)
    % --------------------------------------------------------------------- 
    % Identify avalanches and bursts
    % - if the interval of two spikes < meanISI, it's an avalanche event
    % - find where the avalanche ends and see if this avalanche is a burst
    % ---------------------------------------------------------------------
    if ((space(i) < meanISI) || (count(i) > 1))
        n_aval = n_aval + 1;
        j = i + 1;
        while ((j < length(space)) && (space(j) < meanISI))
            j = j + 1;
        end     
        width = j - i + 1;                          % avalanche duration
        totalSpikeCount = sum(count(i:j));          % total spike count      
        % --------------------------------------------------------------------- 
        % Identify bursts and find pre-burst & non-burst window
        % - if the avalanche is a burst (spikeRate > burstThreshold)
        % - output preburst window information to output file
        % ---------------------------------------------------------------------
        if width > 500
            isBurst = 1;                            % is a burst  
        else
            isBurst = 0;
        end
        fprintf(fid,'%d,%d,%d,%d,%d,%d,%d,%d\n', n_aval,i,j,spiketime(i),spiketime(j),width,totalSpikeCount,isBurst);
        i = j + 1;
    end
    %fprintf('done with avalanche %d\n', i);    % for debugging 
    i = i + 1;
end
fprintf('Total number of avalanches: %d\n', n_aval);
fclose(fid);




