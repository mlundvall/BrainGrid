classdef Burst
   properties
       id           % unique burst ID
       start        % start burst bin#
       ended        % end burst bin#
       width        % duration (unit: 10ms)
       count        % total spike count
       mean         % mean spike rate
       peak         % peak bin#
       height       % number of spike at peak
       interval     % between current and previous burst (peak-peak)
   end
end