#pragma once

#include "AllSpikingSynapses.h"
#include "AllDSSynapses.h"
#include "AllSTDPSynapses.h"

#if defined(__CUDACC__)

extern __device__ enumClassSynapses classSynapses_d;

/**
 *  CUDA code for advancing spiking synapses.
 *  Perform updating synapses for one time step.
 *
 *  @param[in] total_synapse_counts  Number of synapses.
 *  @param  synapseIndexMapDevice    Reference to the SynapseIndexMap on device memory.
 *  @param[in] simulationStep        The current simulation step.
 *  @param[in] deltaT                Inner simulation step duration.
 *  @param[in] allSynapsesDevice     Pointer to Synapse structures in device memory.
 *  @param[in] iStepOffset           Offset from the current simulation step.
 */
extern __global__ void advanceSpikingSynapsesDevice ( int total_synapse_counts, SynapseIndexMap* synapseIndexMapDevice, uint64_t simulationStep, const BGFLOAT deltaT, AllSpikingSynapsesDeviceProperties* allSynapsesDevice, int iStepOffset );

/*
 *  CUDA code for advancing STDP synapses.
 *  Perform updating synapses for one time step.
 *
 *  @param[in] total_synapse_counts  Number of synapses.
 *  @param  synapseIndexMapDevice    Reference to the SynapseIndexMap on device memory.
 *  @param[in] simulationStep        The current simulation step.
 *  @param[in] deltaT                Inner simulation step duration.
 *  @param[in] allSynapsesDevice     Pointer to AllSTDPSynapsesDeviceProperties structures 
 *                                   on device memory.
 *  @param[in] iStepOffset           Offset from the current simulation step.
 */
extern __global__ void advanceSTDPSynapsesDevice ( int total_synapse_counts, SynapseIndexMap* synapseIndexMapDevice, uint64_t simulationStep, const BGFLOAT deltaT, AllSTDPSynapsesDeviceProperties* allSynapsesDevice, AllSpikingNeuronsDeviceProperties* allNeuronsDevice, int max_spikes, int width, int iStepOffset );

/**
 * Adjust the strength of the synapse or remove it from the synapse map if it has gone below
 * zero.
 *
 * @param[in] num_neurons        Number of neurons.
 * @param[in] deltaT             The time step size.
 * @param[in] W_d                Array of synapse weight.
 * @param[in] maxSynapses        Maximum number of synapses per neuron.
 * @param[in] allNeuronsDevice   Pointer to the Neuron structures in device memory.
 * @param[in] allSynapsesDevice  Pointer to the Synapse structures in device memory.
 * @param[in] neuron_type_map_d  Pointer to the neurons type map in device memory.
 * @param[in] totalClusterNeurons  Total number of neurons in the cluster.
 * @param[in] clusterNeuronsBegin  Begin neuron index of the cluster.
 */
extern __global__ void updateSynapsesWeightsDevice( int num_neurons, BGFLOAT deltaT, BGFLOAT* W_d, int maxSynapses, AllSpikingNeuronsDeviceProperties* allNeuronsDevice, AllSpikingSynapsesDeviceProperties* allSynapsesDevice, neuronType* neuron_type_map_d, int totalClusterNeurons, int clusterNeuronsBegin );

/** 
 * Adds a synapse to the network.  Requires the locations of the source and
 * destination neurons.
 *
 * @param allSynapsesDevice      Pointer to the Synapse structures in device memory.
 * @param pSummationMap          Pointer to the summation point.
 * @param width                  Width of neuron map (assumes square).
 * @param deltaT                 The simulation time step size.
 * @param weight                 Synapse weight.
 */
extern __global__ void initSynapsesDevice( int n, AllDSSynapsesDeviceProperties* allSynapsesDevice, BGFLOAT *pSummationMap, int width, const BGFLOAT deltaT, BGFLOAT weight );

/**
 * Perform updating preSpikeQueue for one time step.
 *
 *  @param  allSynapsesDevice  Reference to the AllSpikingSynapsesDeviceProperties struct
 *                             on device memory.
 *  @param  iStep              Simulation steps to advance.
 */
extern __global__ void advanceSpikingSynapsesEventQueueDevice(AllSpikingSynapsesDeviceProperties* allSynapsesDevice, int iStep);

/**
 * Perform updating postSpikeQueue for one time step.
 *
 *  @param  allSynapsesDevice  Reference to the AllSpikingSynapsesDeviceProperties struct
 *                             on device memory.
 *  @param  iStep              Simulation steps to advance.
 */
extern __global__ void advanceSTDPSynapsesEventQueueDevice(AllSTDPSynapsesDeviceProperties* allSynapsesDevice, int iStep);
#endif 
