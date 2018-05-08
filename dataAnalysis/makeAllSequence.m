function makeAllSequence(h5file, infile, window)
% infile = 'csv/nonBurst_100_gap_1000';
% infile = 'csv/preBurst_100_gap_10';
% h5file = 'tR_1.0--fE_0.90_10000';
% #########################################################################
spikeTimeFile = 'csv/allSpikeTime.csv';    
data = csvread([infile '.csv'],1,1);        % read window info 
w = min(data(:,5));	                        % window width
if window > w
    error('ERROR: Wrong window size given');
end
n = size(data,1);     
fid = fopen([infile '_Seq.csv'], 'w') ;     % output file for ML
for i = 1:n                                 % number of examples
    command = ['sed -n ''',num2str(data(i,1)),',',...
        num2str(data(i,2)),' p'' ',spikeTimeFile,' > csv/temp.csv'];
    system(command);                
    temp = csvread('csv/temp.csv');
    % for every spike in the event, convert them into t,x,y sequences
    sequence = makeSequence(h5file, temp, window);
    for j = 1:window*3
        fprintf(fid, '%d,',sequence(j));
    end
    fprintf(fid,'\n'); 
    fprintf('Event: %d/%d\n', i, n);                  % debugging
end
fclose(fid);
end
