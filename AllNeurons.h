
#pragma once

#ifndef _ALLNEURONS_H_
#define _ALLNEURONS_H_

struct AllNeurons
{
public:

	//! A boolean which tracks whether the neuron has fired
	bool hasFired[];

	//! The length of the absolute refractory period. [units=sec; range=(0,1);]
	FLOAT Trefract[];

	//! If \f$V_m\f$ exceeds \f$V_{thresh}\f$ a spike is emmited. [units=V; range=(-10,100);]
	FLOAT Vthresh[];

	//! The resting membrane voltage. [units=V; range=(-1,1);]
	FLOAT Vrest[];

	//! The voltage to reset \f$V_m\f$ to after a spike. [units=V; range=(-1,1);]
	FLOAT Vreset[];

	//! The initial condition for \f$V_m\f$ at time \f$t=0\f$. [units=V; range=(-1,1);]
	FLOAT Vinit[];
	//! The simulation time step size.
	FLOAT deltaT[];

	//! The membrane capacitance \f$C_m\f$ [range=(0,1); units=F;]
	FLOAT Cm[];

	//! The membrane resistance \f$R_m\f$ [units=Ohm; range=(0,1e30)]
	FLOAT Rm[];

	//! The standard deviation of the noise to be added each integration time constant. [range=(0,1); units=A;]
	FLOAT Inoise[];

	//! A constant current to be injected into the LIF neuron. [units=A; range=(-1,1);]
	FLOAT Iinject[];

	// What the hell is this used for???
	//! The synaptic input current.
	FLOAT Isyn[];

	//! The remaining number of time steps for the absolute refractory period.
	int nStepsInRefr[];

	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT C1[];
	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT C2[];
	//! Internal constant for the exponential Euler integration of \f$V_m\f$.
	FLOAT I0[];

	//! The membrane voltage \f$V_m\f$ [readonly; units=V;]
	FLOAT Vm[];

	//! The membrane time constant \f$(R_m \cdot C_m)\f$
	FLOAT Tau[];

	//! The number of spikes since the last growth cycle
	int spikeCount[];
};

#endif