%GETWINDOWS Get firing time steps and its firing neuron and spike count
%Read BrainGrid result in HDF5 format and convert spikesProbedNeurons to 
%easy-to-understand formats for data analysis
% 
%   Syntax:  getSpikeTimes(infile)
%   
%   Input:
%   infile - BrainGrid simulation result (.h5)
%
%   Output:
%   <allSpikeTime.csv> - spike time step and neuron indexes 
%   <allSpikeTimeCount.csv> - spike time step and number of spikes


%  - read <allSpikeTimeCount.csv>
%  - output burst, pre-burst, non-burst info to 
%    <allAvalanche.csv>, <allBurst.csv>, <preBurst.csv>, <nonBurst.csv>
function getWindows
% #########################################################################
% # USER_DEFINED VARIABLES ---------------------------------------------- #
% #########################################################################
windowLength = 100;             % number of spikes in pre/nonBurst windows
gapRightBeforeBurst = 50;       % gap between preburst and burst (ts)
gapInBetweenWindow = 1000;      % gap between preburst and nonburst (ts)
% #########################################################################
spiketime = csvread('allSpikeTimeCount.csv');
frame = spiketime(:,1);         % frames/timeStep that has activities
count = spiketime(:,2);         % spike counts for each frame
space = diff(frame);            % find interspike intervals (ISI)
totalCount = sum(count);        % total spike counts in the simulaiton
% -----------------------------------------------------------------
% Simulation parameters
% -----------------------------------------------------------------
numSim = 600;                   % number of simulation, 300 half, 600 full
Tsim = 100;                     % 100 seconds long for each simulaiton 
deltaT = 0.0001;                % time step size is 0.1 ms = 0.0001 sec
totalTimeSteps = numSim*Tsim*(1/deltaT);    % tatal number of time steps
meanISI = totalTimeSteps/totalCount;        % mean interspike-interval
fprintf('Total time steps: %d\n', totalTimeSteps);
fprintf('Total spikes: %d\n', totalCount);
fprintf('meanISI: %.4f\n', meanISI);
% -----------------------------------------------------------------
% Output files
% -----------------------------------------------------------------
% fid_aval = fopen('allAvalanche.csv', 'w') ;
% fprintf(fid_aval, 'ID,StartRow,EndRow,StartT,EndT,Width,TotalSpikes\n');
% fid_burst = fopen('allBurst.csv', 'w') ;
% fprintf(fid_burst, 'ID,StartRow,EndRow,StartT,EndT,Width,TotalSpikes,IBI\n');
fid_pre = fopen('preBurst100_pb50_np1000.csv', 'w') ;
fprintf(fid_pre, 'ID,StartRow,EndRow,StartT,EndT,TotalSpikes\n');
fid_non = fopen('nonBurst100_pb50_np1000.csv', 'w') ;
fprintf(fid_non, 'ID,StartRow,EndRow,StartT,EndT,TotalSpikes\n');

n_aval = 0;                     % number of avalanches 
n_bursts = 0;                   % number of bursts
last = 1;                       % keep track of last spike
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
        width = j - i + 1;                          % duration (ts)
        totalSpikes = sum(count(i:j));              % total spike count  
%         fprintf(fid_aval,'%d,%d,%d,%d,%d,%d,%d\n', ...
%             n_aval,i,j,spiketime(i),spiketime(j),width,totalSpikes);
        % --------------------------------------------------------------------- 
        % Identify bursts 
        % - if the avalanche is a burst (spikeRate > burstThreshold)
        % - output prebursta and nonburst window information to output file
        % ---------------------------------------------------------------------
		% width > 1000 can also be a criteria to detect burst
        if totalSpikes > 10000 
            n_bursts = n_bursts + 1;
            interval = spiketime(i) - spiketime(last);           
%             fprintf(fid_burst,'%d,%d,%d,%d,%d,%d,%d,%d\n', ...
%                 n_bursts,i,j,spiketime(i),spiketime(j),width,totalSpikes,interval);         
            % -----------------------------------------------------------------
            % Find pre-burst window 
            % -----------------------------------------------------------------
            preEnd = i - gapRightBeforeBurst;                    
            preStart = preEnd - 1;          
            while (preStart > last) && (sum(count(preStart:preEnd)) < windowLength)  
                preStart = preStart - 1;
            end
            fprintf(fid_pre,'%d,%d,%d,%d,%d,%d\n', ...
                n_bursts,preStart,preEnd,spiketime(preStart),spiketime(preEnd),sum(count(preStart:preEnd)));
            % -----------------------------------------------------------------
            % Find non-burst window
            % -----------------------------------------------------------------           
            nonEnd = preStart - gapInBetweenWindow;       
            nonStart = nonEnd - 1;
            while (nonStart > last) && (sum(count(nonStart:nonEnd)) < windowLength) 
                nonStart = nonStart - 1;
            end
            fprintf(fid_non,'%d,%d,%d,%d,%d,%d\n', ...
                n_bursts,nonStart,nonEnd,spiketime(nonStart),spiketime(nonEnd),sum(count(nonStart:nonEnd)));         
            last = j;                   % save the time of last burst
            fprintf('done with burst %d\n', n_bursts);    
        end  
        i = j + 1;
    end
    i = i + 1;
end
fprintf('Total number of avalanches: %d\n', n_aval);
fprintf('Total number of bursts: %d\n', n_bursts);
% fclose(fid_aval);
% fclose(fid_burst);
fclose(fid_pre);
fclose(fid_non);
