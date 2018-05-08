%% Jewel Y. Lee (Documented. Last updated: Nov 29, 2017)  
%  - read BrainGrid simulation result (.h5)
%  - output spike time step and neuron number to <allSpikeTime.csv>
function getSpikeTime(infile)
% ------------------------------------------------------------------------ 
% Read from input data and open output file
% - spikesProbedNeurons = neurons and its firing times (column = neuron)
% - spikesHistory = spike count in each 10ms bins
% ------------------------------------------------------------------------
% infile = '1011_half_tR_1.0--fE_0.90_10000';   % half simulation
% infile = '1102_full_tR_1.0--fE_0.90_10000';   % full simulation
P = double((hdf5read([infile '.h5'], 'spikesProbedNeurons'))');
SH = double((hdf5read([infile '.h5'], 'spikesHistory'))');  
fid = fopen('allSpikeTime.csv', 'w');           % output file name
fid2 = fopen('allSpikeTimeCount.csv', 'w');          
fprintf(fid, 'firingTime,neuronNumber\n');
% ------------------------------------------------------------------------ 
% Get spiking position(s) for every time step that has activities
% ------------------------------------------------------------------------
imax = length(SH) * 100;                        % total time step = 0.1ms
n_neurons = length(P(1,:));                     % total number of neurons
P = [P; zeros(1,n_neurons)];                    % for boundary condition

for i = 1:imax 
    if any(P(1,:)) == 0   
        break;      % no more non-recorded data (first row is all zeros)
    end
    time = min(P(1, P(1,:) > 0));               % get next spike time 
    place = find(P(1,:) == time);               % get place (neuron index)
    fprintf(fid, '%d,', time);                  % record time step 
    fprintf(fid2,'%d,%d\n',time,length(place)); % record time and count 
    % fprintf('time step: %d; neuron#: ', time);% for debugging 
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
        % fprintf('%d,', place(j));             % for debugging 
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
fprintf(fid, '\n');                             % done with this time step
% fprintf('\n');                                % for debugging 
end
fprintf('Total time steps that has activities: %d,', i);
fclose(fid);    
fclose(fid2);
