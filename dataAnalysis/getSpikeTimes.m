%GETSPIKETIMES Get firing time steps and its firing neuron and spike count
%Read BrainGrid result in HDF5 format and convert spikesProbedNeurons to 
%easy-to-understand format for data analysis
% 
%   Syntax: getSpikeTimes(h5file)
%   
%   Input:  h5file  - BrainGrid simulation result (.h5)
%
%   Output: <allSpikeTime.csv>      - spike time step and neuron indexes 
%           <allSpikeTimeCount.csv> - spike time step and number of spikes

% Author:   Jewel Y. Lee (jewel87@uw.edu)
% Last updated: 4/16/2018
function getSpikeTimes(h5file)
%if exist([h5file '/allSpikeTime.csv'],'file') == 2 || ...
%    exist([h5file '/allSpikeTimeCount.csv'],'file') == 2
%    error('spikeTime file already exsited.');
%end
% ------------------------------------------------------------------------ 
% Read from input data and open output file
% - spikesProbedNeurons = neurons and its firing times (column = neuron)
% - spikesHistory = spike count in each 10ms bins
% ------------------------------------------------------------------------
P = (hdf5read([h5file '.h5'], 'spikesProbedNeurons'))';
n_timesteps = getH5datasetSize(h5file, 'spikesHistory')*100;   
% output file name
fid = fopen([h5file '/allSpikeTime1.csv'], 'w');           
fid2 = fopen([h5file '/allSpikeTimeCount1.csv'], 'w');          
% ------------------------------------------------------------------------ 
% Get spiking position(s) for every time step that has activities
% ------------------------------------------------------------------------
n_neurons = length(P(1,:));                     % total number of neurons
P = [P; zeros(1,n_neurons)];                    % for boundary condition

for i = 1:n_timesteps
    if any(P(1,:)) == 0   
        break;      % no more non-recorded data (first row is all zeros)
    end
    time = min(P(1, P(1,:) > 0));               % get next spike time 
    % condition: more than one neuron spikes at that time step 
    place = find(P(1,:) == time);               % get all spiking neurons
    fprintf(fid, '%d,', time);                  % record time step 
    fprintf(fid2,'%d,%d\n',time,length(place)); % record time and count 
    fprintf('time step: %d; neuron#: ', time);% for debugging 
    % --------------------------------------------------------------------- 
    % Record firing neurons for each time step
    % - find the smallest value in the first row (fire the earliest)
    % - copy neuron's next firing time to first row
    % - mark the one we just copied to 1st row as -1 (recorded)
    % - reach 0 means there are no more firing for this neuron (column)
    % - when the 1st row are all zeros, means we have recorded everything
    % ---------------------------------------------------------------------
    for j = 1:length(place)   
        fprintf(fid, '%d,', place(j));          % record neuron number     
        fprintf('%d,', place(j));             % for debugging 
        counter = 2;                            % start from the 2nd row
        while P(counter, place(j)) < 1          % find next firing time
            % no more spikes for this neuron to be recorded
            if P(counter, place(j)) == 0        
                break; 
            else
            % find the next unrecorded firing time (not -1s)
                counter = counter + 1;                             
            end
        end     
        P(1, place(j)) = P(counter, place(j));  % copy to 1st row
        P(counter, place(j)) = -1;              % and mark as recorded
    end
%fprintf(fid, '\n');                             % done with this time step
fprintf('\n');                                % for debugging 
end
fprintf('Total time steps that has activities: %d,', i);
fclose(fid);    
fclose(fid2);
