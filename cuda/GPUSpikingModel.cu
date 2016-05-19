/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - **\ 
 * @authors Aaron Oziel, Sean Blackbourn 
 *
 * Fumitaka Kawasaki (5/3/14):
 * All functions were completed and working. Therefore, the followng comments
 * were removed. 
 *
 * Aaron Wrote (2/3/14):
 * All comments are now tracking progress in conversion from old GpuSim_struct.cu
 * file to the new one here. This is a quick key to keep track of their meanings. 
 *
 *	TODO = 	Needs work and/or is blank. Used to indicate possibly problematic 
 *				functions. 
 *	DONE = 	Likely complete functions. Will still need to be checked for
 *				variable continuity and proper arguments. 
 *   REMOVED =	Deleted, likely due to it becoming unnecessary or not necessary 
 *				for GPU implementation. These functions will likely have to be 
 *				removed from the Model super class.
 *    COPIED = 	These functions were in the original GpuSim_struct.cu file 
 *				and were directly copy-pasted across to this file. 
 *
\** - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - **/

#include "GPUSpikingModel.h"

#ifdef PERFORMANCE_METRICS
float g_time;
cudaEvent_t start, stop;
#endif // PERFORMANCE_METRICS

__constant__ int d_debug_mask[1];

// ----------------------------------------------------------------------------

GPUSpikingModel::GPUSpikingModel(Connections *conns, IAllNeurons *neurons, IAllSynapses *synapses, Layout *layout) : 	
	Model::Model(conns, neurons, synapses, layout),
	synapseIndexMapDevice(NULL),
	randNoise_d(NULL),
	m_allNeuronsDevice(NULL),
	m_allSynapsesDevice(NULL)
{
}

GPUSpikingModel::~GPUSpikingModel() 
{
	//Let Model base class handle de-allocation
}

/*
 * Allocates and initializes memories on CUDA device.
 *
 * @param[out] allNeuronsDevice          Memory loation of the pointer to the neurons list on device memory.
 * @param[out] allSynapsesDevice         Memory loation of the pointer to the synapses list on device memory.
 * @param[in]  sim_info			Pointer to the simulation information.
 */
void GPUSpikingModel::allocDeviceStruct(void** allNeuronsDevice, void** allSynapsesDevice, SimulationInfo *sim_info)
{
	// Allocate Neurons and Synapses strucs on GPU device memory
	m_neurons->allocNeuronDeviceStruct( allNeuronsDevice, sim_info );
	m_synapses->allocSynapseDeviceStruct( allSynapsesDevice, sim_info );

	// Allocate memory for random noise array
	int neuron_count = sim_info->totalNeurons;
	size_t randNoise_d_size = neuron_count * sizeof (float);	// size of random noise array
	HANDLE_ERROR( cudaMalloc ( ( void ** ) &randNoise_d, randNoise_d_size ) );

	// Copy host neuron and synapse arrays into GPU device
	m_neurons->copyNeuronHostToDevice( allNeuronsDevice, sim_info );
	m_synapses->copySynapseHostToDevice( *allSynapsesDevice, sim_info );

	// allocate synapse inverse map in device memory
	allocSynapseImap( neuron_count );
}

/*
 * Copies device memories to host memories and deallocaes them.
 *
 * @param[out] allNeuronsDevice          Memory loation of the pointer to the neurons list on device memory.
 * @param[out] allSynapsesDevice         Memory loation of the pointer to the synapses list on device memory.
 * @param[in]  sim_info                  Pointer to the simulation information.
 */
void GPUSpikingModel::deleteDeviceStruct(void** allNeuronsDevice, void** allSynapsesDevice, SimulationInfo *sim_info)
{
   // copy device synapse and neuron structs to host memory
   m_neurons->copyNeuronDeviceToHost( allNeuronsDevice, sim_info );

   // Deallocate device memory
   m_neurons->deleteNeuronDeviceStruct( *allNeuronsDevice, sim_info );

   // copy device synapse and neuron structs to host memory
   m_synapses->copySynapseDeviceToHost( *allSynapsesDevice, sim_info );

   // Deallocate device memory
   m_synapses->deleteSynapseDeviceStruct( *allSynapsesDevice );

   deleteSynapseImap();

   HANDLE_ERROR( cudaFree( randNoise_d ) );
}

/*
 *  Sets up the Simulation.
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::setupSim(SimulationInfo *sim_info)
{
    // Set device ID
    HANDLE_ERROR( cudaSetDevice( g_deviceId ) );

    // Set DEBUG flag
    HANDLE_ERROR( cudaMemcpyToSymbol (d_debug_mask, &g_debug_mask, sizeof(int) ) );

    Model::setupSim(sim_info);

   for(int i = 0; i < sim_info->numGPU; i++){
      cudaSetDevice(i);
      //initialize Mersenne Twister
      //assuming neuron_count >= 100 and is a multiple of 100. Note rng_mt_rng_count must be <= MT_RNG_COUNT
      int rng_blocks = 25; //# of blocks the kernel will use
      int rng_nPerRng = 4; //# of iterations per thread (thread granularity, # of rands generated per thread)
      int rng_mt_rng_count = sim_info->individualGPUInfo[i].totalNeurons/rng_nPerRng; //# of threads to generate for neuron_count rand #s
      int rng_threads = rng_mt_rng_count/rng_blocks; //# threads per block needed
      initMTGPU(sim_info->seed, rng_blocks, rng_threads, rng_nPerRng, rng_mt_rng_count);
   }
   
#ifdef PERFORMANCE_METRICS
    cudaEventCreate( &start );
    cudaEventCreate( &stop );

    t_gpu_rndGeneration = 0.0f;
    t_gpu_advanceNeurons = 0.0f;
    t_gpu_advanceSynapses = 0.0f;
    t_gpu_calcSummation = 0.0f;
#endif // PERFORMANCE_METRICS

   m_allNeuronsDevice = new  AllSpikingNeurons*[sim_info->numGPU];
   m_allSynapsesDevice = new AllSpikingSynapses*[sim_info->numGPU];

   for(int i = 0; i < sim_info->numGPU; i++){
      cudaSetDevice(i);
      
      // allocates memories on CUDA device
      allocDeviceStruct((void **)&m_allNeuronsDevice[i], (void **)&m_allSynapsesDevice[i], &sim_info->individualGPUInfo[i]);

      // set device summation points
      int neuron_count = sim_info->individualGPUInfo[i].totalNeurons;
      const int threadsPerBlock = 256;
      int blocksPerGrid = ( neuron_count + threadsPerBlock - 1 ) / threadsPerBlock;
      setSynapseSummationPointDevice <<< blocksPerGrid, threadsPerBlock >>> (neuron_count, m_allNeuronsDevice[i], m_allSynapsesDevice[i], sim_info->maxSynapsesPerNeuron, sim_info->individualGPUInfo[i].width);

      // copy inverse map to the device memory
      copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);

      // set some parameters used for advanceNeuronsDevice
      m_neurons->setAdvanceNeuronsDeviceParams(*m_synapses);

      // set some parameters used for advanceSynapsesDevice
      m_synapses->setAdvanceSynapsesDeviceParams();
   }
}

/* 
 *  Begin terminating the simulator.
 *
 *  @param  sim_info    SimulationInfo to refer.
 */
void GPUSpikingModel::cleanupSim(SimulationInfo *sim_info)
{
    // deallocates memories on CUDA device
    deleteDeviceStruct((void**)&m_allNeuronsDevice, (void**)&m_allSynapsesDevice, sim_info);

#ifdef PERFORMANCE_METRICS
    cudaEventDestroy( start );
    cudaEventDestroy( stop );
#endif // PERFORMANCE_METRICS
}

/*
 *  Loads the simulation based on istream input.
 *
 *  @param  input   istream to read from.
 *  @param  sim_info    used as a reference to set info for neurons and synapses.
 */
void GPUSpikingModel::deserialize(istream& input, const SimulationInfo *sim_info)
{
   Model::deserialize(input, sim_info);
   
   // copy inverse map to the device memory
   copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);

   // Reinitialize device struct - Copy host neuron and synapse arrays into GPU device
   m_neurons->copyNeuronHostToDevice( reinterpret_cast<void**>(m_allNeuronsDevice), sim_info );
   m_synapses->copySynapseHostToDevice( m_allSynapsesDevice, sim_info );

   for(int i = 0; i < sim_info->numGPU; i++){
      cudaSetDevice(i);
      // set device summation points
      int neuron_count = sim_info->individualGPUInfo[i].totalNeurons;
      const int threadsPerBlock = 256;
      int blocksPerGrid = ( neuron_count + threadsPerBlock - 1 ) / threadsPerBlock;
      setSynapseSummationPointDevice <<< blocksPerGrid, threadsPerBlock >>> (neuron_count, m_allNeuronsDevice[i], m_allSynapsesDevice[i], sim_info->maxSynapsesPerNeuron, sim_info->individualGPUInfo[i].width);
   }
}

/* 
 *  Advance everything in the model one time step. In this case, that
 *  means calling all of the kernels that do the "micro step" updating
 *  (i.e., NOT the stuff associated with growth).
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::advance(const SimulationInfo *sim_info)
{
#ifdef PERFORMANCE_METRICS
	startTimer();
#endif // PERFORMANCE_METRICS

	normalMTGPU(randNoise_d);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_rndGeneration);
	startTimer();
#endif // PERFORMANCE_METRICS

	// display running info to console
	// Advance neurons ------------->
   m_neurons->advanceNeurons(*m_synapses, reinterpret_cast<IAllNeurons **>(m_allNeuronsDevice), (IAllSynapses **)(m_allSynapsesDevice), sim_info, randNoise_d, synapseIndexMapDevice);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_advanceNeurons);
	startTimer();
#endif // PERFORMANCE_METRICS

	// Advance synapses ------------->
   for(int i = 0; i < sim_info->numGPU; i++){
      cudaSetDevice(i);
	   m_synapses->advanceSynapses(m_allSynapsesDevice[i], m_allNeuronsDevice[i], synapseIndexMapDevice[i], &sim_info->individualGPUInfo[i]);
   }
   
#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_advanceSynapses);
	startTimer();
#endif // PERFORMANCE_METRICS

	// calculate summation point
   calcSummationMap(sim_info);

#ifdef PERFORMANCE_METRICS
	lapTime(t_gpu_calcSummation);
#endif // PERFORMANCE_METRICS
}

/*
 * Add psr of all incoming synapses to summation points.
 *
 * @param[in] sim_info                   Pointer to the simulation information.
 */
void GPUSpikingModel::calcSummationMap(const SimulationInfo *sim_info)
{
    // CUDA parameters
    const int threadsPerBlock = 256;
   for(int i = 0; i < sim_info->numGPU; i++){
      cudaSetDevice(i);
      int blocksPerGrid = ( sim_info->individualGPUInfo[i].totalNeurons + threadsPerBlock - 1 ) / threadsPerBlock;
      calcSummationMapDevice <<< blocksPerGrid, threadsPerBlock >>> ( sim_info->individualGPUInfo[i].totalNeurons, m_allNeuronsDevice[i], m_allSynapsesDevice[i], sim_info->maxSynapsesPerNeuron);
   }
}

/* 
 *  Update the connection of all the Neurons and Synapses of the simulation.
 *
 *  @param  sim_info    SimulationInfo class to read information from.
 */
void GPUSpikingModel::updateConnections(const SimulationInfo *sim_info)
{
        dynamic_cast<AllSpikingNeurons*>(m_neurons)->copyNeuronDeviceSpikeCountsToHost(m_allNeuronsDevice, sim_info);
        dynamic_cast<AllSpikingNeurons*>(m_neurons)->copyNeuronDeviceSpikeHistoryToHost(m_allNeuronsDevice, sim_info);

        // Update Connections data
        if (m_conns->updateConnections(*m_neurons, sim_info, m_layout)) {
	         m_conns->updateSynapsesWeights(sim_info->totalNeurons, *m_neurons, *m_synapses, sim_info, m_allNeuronsDevice, m_allSynapsesDevice, m_layout);
            // create synapse inverse map
            m_synapses->createSynapseImap(m_synapseIndexMap, sim_info);
            // copy inverse map to the device memory
            copySynapseIndexMapHostToDevice(*m_synapseIndexMap, sim_info->totalNeurons);
        }
}

/*
 *  Update the Neuron's history.
 *
 *  @param  sim_info    SimulationInfo to refer from.
 */
void GPUSpikingModel::updateHistory(const SimulationInfo *sim_info)
{
    Model::updateHistory(sim_info);

    // clear spike count
    dynamic_cast<AllSpikingNeurons*>(m_neurons)->clearNeuronSpikeCounts(m_allNeuronsDevice, sim_info);
}

/* ------------------*\
|* # Helper Functions
\* ------------------*/

/*
 *  Allocate device memory for synapse inverse map.
 *  @param  count	The number of neurons.
 */
void GPUSpikingModel::allocSynapseImap( int count )
{
	SynapseIndexMap synapseIndexMap;

	HANDLE_ERROR( cudaMalloc( ( void ** ) &synapseIndexMap.outgoingSynapse_begin, count * sizeof( int ) ) );
	HANDLE_ERROR( cudaMalloc( ( void ** ) &synapseIndexMap.synapseCount, count * sizeof( int ) ) );
	HANDLE_ERROR( cudaMemset(synapseIndexMap.outgoingSynapse_begin, 0, count * sizeof( int ) ) );
	HANDLE_ERROR( cudaMemset(synapseIndexMap.synapseCount, 0, count * sizeof( int ) ) );

	HANDLE_ERROR( cudaMalloc( ( void ** ) &synapseIndexMapDevice, sizeof( SynapseIndexMap ) ) );
	HANDLE_ERROR( cudaMemcpy( synapseIndexMapDevice, &synapseIndexMap, sizeof( SynapseIndexMap ), cudaMemcpyHostToDevice ) );
}

/*
 *  Deallocate device memory for synapse inverse map.
 */
void GPUSpikingModel::deleteSynapseImap(  )
{
	SynapseIndexMap synapseIndexMap;

	HANDLE_ERROR( cudaMemcpy ( &synapseIndexMap, synapseIndexMapDevice, sizeof( SynapseIndexMap ), cudaMemcpyDeviceToHost ) );
	HANDLE_ERROR( cudaFree( synapseIndexMap.outgoingSynapse_begin ) );
	HANDLE_ERROR( cudaFree( synapseIndexMap.synapseCount ) );
	HANDLE_ERROR( cudaFree( synapseIndexMap.forwardIndex ) );
	HANDLE_ERROR( cudaFree( synapseIndexMap.activeSynapseIndex ) );
	HANDLE_ERROR( cudaFree( synapseIndexMapDevice ) );
}

/* 
 *  Copy SynapseIndexMap in host memory to SynapseIndexMap in device memory.
 *
 *  @param  synapseIndexMapHost		Reference to the SynapseIndexMap in host memory.
 *  @param  neuron_count		The number of neurons.
 *  GETDONE: Split and correct the synapse index map for each GPU
 */
void GPUSpikingModel::copySynapseIndexMapHostToDevice(SynapseIndexMap &synapseIndexMapHost, int neuron_count)
{
   int total_synapse_counts = dynamic_cast<AllSynapses*>(m_synapses)->total_synapse_counts;

	if (total_synapse_counts == 0)
		return;

	SynapseIndexMap synapseIndexMap;

	HANDLE_ERROR( cudaMemcpy ( &synapseIndexMap  , synapseIndexMapDevice, sizeof( SynapseIndexMap ), cudaMemcpyDeviceToHost ) );
	HANDLE_ERROR( cudaMemcpy ( synapseIndexMap.outgoingSynapse_begin, synapseIndexMapHost.outgoingSynapse_begin, neuron_count * sizeof( int ), cudaMemcpyHostToDevice ) );
	HANDLE_ERROR( cudaMemcpy ( synapseIndexMap.synapseCount, synapseIndexMapHost.synapseCount, neuron_count * sizeof( int ), cudaMemcpyHostToDevice ) );
	// the number of synapses may change, so we reallocate the memory
	if (synapseIndexMap.forwardIndex != NULL) {
		HANDLE_ERROR( cudaFree( synapseIndexMap.forwardIndex ) );
	}
	HANDLE_ERROR( cudaMalloc( ( void ** ) &synapseIndexMap.forwardIndex, total_synapse_counts * sizeof( uint32_t ) ) );
	HANDLE_ERROR( cudaMemcpy ( synapseIndexMap.forwardIndex, synapseIndexMapHost.forwardIndex, total_synapse_counts * sizeof( uint32_t ), cudaMemcpyHostToDevice ) );

	if (synapseIndexMap.activeSynapseIndex != NULL) {
		HANDLE_ERROR( cudaFree( synapseIndexMap.activeSynapseIndex ) );
	}
	HANDLE_ERROR( cudaMalloc( ( void ** ) &synapseIndexMap.activeSynapseIndex, total_synapse_counts * sizeof( uint32_t ) ) );
	HANDLE_ERROR( cudaMemcpy ( synapseIndexMap.activeSynapseIndex, synapseIndexMapHost.activeSynapseIndex, total_synapse_counts * sizeof( uint32_t ), cudaMemcpyHostToDevice ) );

	HANDLE_ERROR( cudaMemcpy ( synapseIndexMapDevice, &synapseIndexMap, sizeof( SynapseIndexMap ), cudaMemcpyHostToDevice ) );
}

/*
 *  Given a normal host side SynapseIndexMap, convert so that the
 *  synapse indicies are actually a device and an index on that device.
 *  This is accomplished by defining a certain number of bits in the index
 *  data to repurpose as a device number. The index can be shifted over this
 *  certain number of bits and then combined with a bitwise AND to produce
 *
 *
 *  @param  synapse_index          Global index of the synapse.
 *  @param  allSynapsesDeviceList  List of allSynapses structs in each device's memory.
 *  @param  sim_info               SimulationInfo to refer from.
 *  @param  allSynapsesDevice      Pointer to be assigned to address of allSynapses structs
 *                                 containing synapse_index
 *  @param  synapse_index_local    Reference to an uint32_t to be filled with the index of the synapse
 *                                 in the allSynapses struct pointed to by allSynapsesDevice
 */
void GPUSpikingModel::convertSynapseIndexMap(const SynapseIndexMap &synapseIndexMapToConvert, const SimulationInfo *sim_info){
   const int bitsForDevice = 3;
   
   uint32_t global_index = 0;
   
   for(int i = 0; i < synapseIndexMapToConvert.num_synapses; i++){
      global_index = synapseIndexMapToConvert.forwardIndex[i];
      
      for(uint32_t deviceNumber = 0; deviceNumber < sim_info->numGPU; deviceNumber++){
         if(global_index < sim_info->individualGPUInfo[deviceNumber].totalNeurons){
            synapseIndexMapToConvert.forwardIndex[i] = (global_index << bitsForDevice) & deviceNumber
         }
         else{
            global_index -= sim_info->individualGPUInfo[deviceNumber].totalNeurons;
         }
      }
      
   }
}

/* ------------------*\
|* # Global Functions
\* ------------------*/

/*
 * Set the summation points in device memory
 *
 * @param[in] num_neurons        Number of neurons.
 * @param[in] allNeuronsDevice   Pointer to the Neuron structures in device memory.
 * @param[in] allSynapsesDevice  Pointer to the Synapse structures in device memory.
 * @param[in] max_synapses       Maximum number of synapses per neuron.
 * @param[in] width              Width of neuron map (assumes square).
 */
__global__ void setSynapseSummationPointDevice(int num_neurons, AllSpikingNeurons* allNeuronsDevice, AllSpikingSynapses* allSynapsesDevice, int max_synapses, int width)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if ( idx >= num_neurons )
        return;

    #define dest_neuron idx //maybe save a register
    int n_inUse = 0;
    
    //set the summationPoint for every synapse this neuron has to the destination neuron. Since each
    //neuron stores the synapses that input into it, this neuron is the destination neuron.
    for (int syn_index = 0; n_inUse < allSynapsesDevice->synapse_counts[dest_neuron]; syn_index++) {
        if (allSynapsesDevice->in_use[max_synapses * dest_neuron + syn_index] == true) {
            allSynapsesDevice->summationPoint[max_synapses * dest_neuron + syn_index] = &( allNeuronsDevice->summation_map[dest_neuron] );
            n_inUse++;
        }
    }
    #undef dest_neuron
}

/* 
 * @param[in] totalNeurons       Number of neurons.
 * @param[in] synapseIndexMap    Inverse map, which is a table indexed by an input neuron and maps to the synapses that provide input to that neuron.
 * @param[in] allSynapsesDevice  Pointer to Synapse structures in device memory.
 */
__global__ void calcSummationMapDevice( int totalNeurons, AllNeurons* allNeuronsDevice, AllSpikingSynapses* allSynapsesDevice, int max_synapses) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x; //calculate neuron index
        if ( idx >= totalNeurons ){ //don't do anything if this thread would be mapped to a non-existant neuron
           return;
		}

		size_t synapseCount = allSynapsesDevice->synapse_counts[idx];
        BGFLOAT sum = 0.0;
        int syn_index = max_synapses * idx; //get the index of this neuron's first synapse in the array of all synapses
        for (int i = 0; (synapseCount > 0) && (i < max_synapses); i++) {
           if (allSynapsesDevice->in_use[syn_index + i] == true) {
              sum += allSynapsesDevice->psr[syn_index + i];
			  synapseCount--;
           }
        }
        
        allNeuronsDevice->summation_map[idx] = sum;
/*
        uint32_t iCount = synapseIndexMapDevice->synapseCount[idx];
        if (iCount != 0) {
                int beginIndex = synapseIndexMapDevice->Synapse_begin[idx];
                uint32_t* inverseMap_begin = &( synapseIndexMapDevice->inverseIndex[beginIndex] );
                BGFLOAT sum = 0.0;
                uint32_t syn_i = inverseMap_begin[0];
                BGFLOAT &summationPoint = *( allSynapsesDevice->summationPoint[syn_i] );
                for ( uint32_t i = 0; i < iCount; i++ ) {
                        syn_i = inverseMap_begin[i];
                        sum += allSynapsesDevice->psr[syn_i];
                }
                summationPoint = sum;
        }*/
}

