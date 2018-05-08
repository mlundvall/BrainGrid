%% Jewel Y. Lee 2017
%  - read BrainGrid simulation result (.h5)
%  - output spike time step and neuron number to <allSpikeTime.csv>
function getSpikeTime2(infile)
%infile = '1011_half_tR_1.0--fE_0.90_10000';   % half simulation
% infile = '1102_full_tR_1.0--fE_0.90_10000';   % full simulation
P = double((hdf5read([infile '.h5'], 'spikesProbedNeurons'))');
spikesHistory = double((hdf5read([infile '.h5'], 'spikesHistory'))');  
imax = sum(spikesHistory);
fid1 = fopen('testSpikeTime.csv', 'w');  
fid2 = fopen('testSpikeTimeCount.csv', 'w'); 
fprintf(fid1, 'FiringTime,NeuronNumber\n');
% ------------------------------------------------------------------------ 
% get spiking position(s) for every time step that has activities
% ------------------------------------------------------------------------
for i = 214926614:imax
    if any(P(1,:)) == 0 % if there are no more non-recorded data
        break;
    end
    time = min(P(1, P(1,:) > 0));           % get next spike time 
    fprintf(fid1, '%d,', time);             % record time step 
    fprintf(fid2, '%d,', time);
    fprintf('time step %d\n', time);
    place = find(P(1,:) == time);           % get spike place (neuron index)
    fprintf(fid2, '%d\n', length(place));
    % --------------------------------------------------------------------- 
    % copy the neuron's next firing time to first row
    % ---------------------------------------------------------------------
    for j = 1:length(place)   
        fprintf(fid1, '%d,', place(j));     % record neuron number     
        counter = 2;
        while P(counter, place(j)) < 1
            if P(counter, place(j)) == 0    % no more spike for this neuron
                break;
            else
                counter = counter + 1;                 
            end
        end     
        P(1, place(j)) = P(counter, place(j));
        P(counter, place(j)) = -1;          % mark as recorded
    end
fprintf(fid1, '\n');                        % done with this time step
end
fclose(fid1);
fclose(fid2);
disp(i);
