%MAKESEQUENCE output t, x, y sequences for every spike in target event
%Read time and x,y location for every spike in target event (preBurst or 
%nonBurst)from spikeTime as features, return an array. 
%  
%   Syntax:  sequence = makeSequence(spikeTime, n_spikes)
%   
%   Input:
%   spikeTime - matrix contains spikeTime info for target event
%   n_spikes  - number of spikes in target event
%
%   Output:
%   sequence  - array of size 1 x (3*n_spikes)

%Author: Jewel Y. Lee (jewel87@uw.edu)
function sequence = makeSequence(spikeTime, n_spikes)
load('config.mat','xloc')
load('config.mat','yloc')
t_offset = spikeTime(1,1);          % relative time offset
features = n_spikes*3;              % 3 features (t,x,y) for each spike
counter = 1;
sequence = zeros(1,features);
for row = 1:size(spikeTime,1)       % for each timestep in this event
    t = spikeTime(row,1) - t_offset;     
    col = 2;                        % neuron idx starts at 2nd column
    % for all spikes in this timestep
    while spikeTime(row,col) > 0 && counter < features  
        sequence(counter) = t;
        sequence(counter+1) = xloc(spikeTime(row,col));
        sequence(counter+2) = yloc(spikeTime(row,col));
        col = col + 1;
        counter = counter + 3;
    end   
end
end