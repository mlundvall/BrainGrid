"""
@file     clustering1.py 
@author   Jewel Lee (jewel87@uw.edu)
@date     5/16/2018

@brief    Perform spatiotemporal clustering on spikes
          
          1. have an empty list of avalanches (A)
          2. read <allSpikeTime.csv> line by line, spike by spike (Spike S) 
          3. check if S can be added to existed avalanches by finding avalanches 
             from A which has spike that is close in time and space from S
            
             3.1 if no matches, create a new avalanche in A for S (avalanche size = 1)
             3.2 if one match, add S into the existed avalanche  (avalanche size + 1)
             3.3 if more than one matches, add S to the latest avalanche (close in time)
                 and merge those matched avalanches into one avalanche
          
          4. after all spikes in <allSpikeTime.csv> get processed, remove avalanches 
             in A that has only one spike (size = 1)
          5. output sizes of avalanches in A to <allAvalSizes.csv>
             (optional) output all spike ids for each avalanche to <allAvalList.csv>
          
"""
import os
import sys
import csv
import numpy as np
from SpikeData import Spike
from SpikeData import Avalanche

###############################################################################
# USER DEFINED VARIABLES
###############################################################################
GRID = 100          # grid size (e.g. 100 is 100 x 100, 10000 neurons)
TAU = 50            # temporal window (unit: time steps (0.1ms))
RADIUS = 8          # spatial window (unit: neuron distances)
meanISI = 1.5
###############################################################################

# -----------------------------------------------------------------------------
# getXY()
# get X, Y location using its neuron ID
# -----------------------------------------------------------------------------
def getXY(n):
    y = np.floor_divide((n-1), GRID) + 1
    x = n - (GRID*y) + GRID
    return x, y

# -----------------------------------------------------------------------------
# getDistance()
# get distance between two neurons
# -----------------------------------------------------------------------------
def getDistance(n1, n2):
    x1, y1 = getXY(n1)
    x2, y2 = getXY(n2)
    d = np.sqrt((x1 - x2)**2 + (y1 - y2)**2)
    return abs(d)

# -----------------------------------------------------------------------------
# mergeAval()
# merge list of matched avalanches into one
# -----------------------------------------------------------------------------
def mergeKAvals(match):
    k = len(match) - 1      # latest avalanche in the list
    i = 0                   # earliest avalanche in the list
    while i < k:
        # merge later avalanche into early avalanche
        A[match[i+1]].merge(A[match[i]])
        # so removing later avalanche doesn't affect indexes
        A.remove(A[match[i]])
        i = i + 1
    return

# -----------------------------------------------------------------------------
# findAval()
# find if current spike belongs to any existed avalanches (within TAU and RADIUS)
# return True when one or more matched avalanches were found and spike was added
# return False so new avalanche has to be created for this spike
# -----------------------------------------------------------------------------
def spatial():
    if len(A) > 0:
        for a in reversed(A):
            node = a.tail
            while node is not None and len(a) > 1:
                temp = node.prev
                if findMatch(node, a) is False:
                    a.remove(node)
                node = temp


def findMatch(target, a):
    node = a.tail
    while node is not None:
        d = getDistance(target.id, node.id)
        tdiff = abs(target.ts - node.ts)
        if 0 < d < RADIUS and tdiff < TAU:
            return True
        node = node.prev
    return False


# -----------------------------------------------------------------------------
# removeSingles()
# remove single spike avalanches that has no impact on current spikes
# -----------------------------------------------------------------------------
def removeSingles():
    for a in reversed(A):
        if len(a) < 2 or a is None:
            A.remove(a)

# -----------------------------------------------------------------------------
# outputAvalSize() write sizes of all avalanches to outfile
# -----------------------------------------------------------------------------
def outputAvalSize(outfile1):
    f = open(outfile1, 'w')
    for a in A:
        #print(len(a))
        f.write("%i\n" % len(a))
    f.close()

# -----------------------------------------------------------------------------
# outputAvalList() write all avalanche lists to outfile
# -----------------------------------------------------------------------------
def outputAvalList(outfile2):
    f = open(outfile2, 'w')
    for a in A:
        # print(a.head.ts)
        node = a.head
        f.write("%i" % node.ts)
        while node is not None:
            f.write(",%i" % node.id)
            node = node.next
        f.write("\n")
    f.close()

###############################################################################
# MAIN PROGRAM
###############################################################################
infile = sys.argv[1]
filename, file_extension = os.path.splitext(infile)
outfile1 = filename + '_size.csv'
outfile2 = filename + '_list.csv'

# -----------------------------------------------------------------------------
# Step 1: Create an empty list to hold avalanche objects
# -----------------------------------------------------------------------------
A = []
readCSV = csv.reader(open(infile), delimiter=',')
# -----------------------------------------------------------------------------
# Step 2: Read <allSpikeTime.csv> and process it spike by spike
# -----------------------------------------------------------------------------
for line in readCSV:
    current_ts = np.uint32(line[0])
    col = 1
    print(current_ts)   # debugging
# -----------------------------------------------------------------------------
# Step 3: Perform spatiotemporal clustering for each spike
# -----------------------------------------------------------------------------
    while col < len(line):
        current_id = np.uint16(line[col])
        # see if current spike can be added to existed avalanches
        if len(A) > 0 and (current_ts - A[-1].tail.ts) < meanISI:
            A[-1].add_node(current_ts, current_id)
        else:
            new_a = Avalanche()
            A.append(new_a)
            new_a.add_node(current_ts, current_id)
        # endif
        col = col + 1
# -----------------------------------------------------------------------------
# Step 4: All spikes processed, remove all single spike avalanches
# -----------------------------------------------------------------------------
removeSingles()
# -----------------------------------------------------------------------------
# Step 5: Apply Spatial Constraint
# -----------------------------------------------------------------------------
spatial()
removeSingles()
# -----------------------------------------------------------------------------
# Step 5: Output results
# -----------------------------------------------------------------------------
outputAvalSize(outfile1)
outputAvalList(outfile2)
