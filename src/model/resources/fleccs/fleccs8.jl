"""
GenX: An Configurable Capacity Expansion Model
Copyright (C) 2021,  Massachusetts Institute of Technology
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
A complete copy of the GNU General Public License v2 (GPLv2) is available
in LICENSE.txt.  Users uncompressing this from an archive may not have
received this license file.  If not, see <http://www.gnu.org/licenses/>.
"""

@doc raw"""
	FLECCS2(EP::Model, inputs::Dict, UCommit::Int, Reserves::Int)

The FLECCS2 module creates decision variables, expressions, and constraints related to NGCC-CCS coupled with solvent storage systems. In this module, we will write up all the constraints formulations associated with the power plant.

This module uses the following 'helper' functions in separate files: FLECCS2_commit() for FLECCS subcompoents subject to unit commitment decisions and constraints (if any) and FLECCS2_no_commit() for FLECCS subcompoents not subject to unit commitment (if any).
"""

function fleccs8(EP::Model, inputs::Dict, FLECCS::Int, UCommit::Int, Reserves::Int)

	println("FLECCS8, Allam cycle with LOX storage")

	T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones
    G_F = inputs["G_F"] # Number of FLECCS generator
	FLECCS_ALL = inputs["FLECCS_ALL"] # set of FLECCS generator
	dfGen_ccs = inputs["dfGen_ccs"] # FLECCS general data
	FLECCS_parameters = inputs["FLECCS_parameters"] # FLECCS specific parameters
	# get number of flexible subcompoents
	N_F = inputs["N_F"]
 


	NEW_CAP_ccs = inputs["NEW_CAP_FLECCS"] #allow for new capcity build
	RET_CAP_ccs = inputs["RET_CAP_FLECCS"] #allow for retirement

	START_SUBPERIODS = inputs["START_SUBPERIODS"] #start
    INTERIOR_SUBPERIODS = inputs["INTERIOR_SUBPERIODS"] #interiors

    hours_per_subperiod = inputs["hours_per_subperiod"]

	fuel_type = collect(skipmissing(dfGen_ccs[!,:Fuel]))

	fuel_CO2 = inputs["fuel_CO2"]
	fuel_costs = inputs["fuel_costs"]



	STARTS = 1:inputs["H"]:T
    # Then we record all time periods that do not begin a sub period
    # (these will be subject to normal time couping constraints, looking back one period)
    INTERIORS = setdiff(1:T,STARTS)

	# capacity decision variables


	# variales related to power generation/consumption
    @variables(EP, begin
        # Continuous decision variables
        vP_oxy[y in FLECCS_ALL, 1:T]  >= 0 # generation from combustion TURBINE (gas TURBINE)
        vP_ccs_net[y in FLECCS_ALL, 1:T]  >= 0 # net generation from NGCC-CCS coupled with solvent storage
    end)

	# variales related to CO2 and solvent
	@variables(EP, begin
        vLOX_store[y in FLECCS_ALL,1:T] >= 0 # lox generated by ASU
        vSTORE_lox[y in FLECCS_ALL,1:T] >= 0 # lox stored in the lox storage tank
	end)

	# the order of those variables must follow the order of subcomponents in the "FLECCS_data.csv"
	# 1. oxy fuel cycle
	# 2. air separation unit (ASU) 
	# 3. LOX storage tank


	# get the ID of each subcompoents 
	# gas turbine 
	OXY_id = inputs["OXY_id"]
	# steam turbine
	ASU_id = inputs["ASU_id"]
	# absorber 
	LOX_id = inputs["LOX_id"]
	#BOP ID
	BOP_id = inputs["BOP_id"]


	# Specific constraints for FLECCS system
    # Thermal Energy input of combustion TURBINE (or oxyfuel power cycle) at hour "t" [MMBTU]
    @expression(EP, eFuel[y in FLECCS_ALL,t=1:T], FLECCS_parameters[!,:slope][y] * vP_oxy[y,t] +  EP[:vCOMMIT_FLECCS][y,OXY_id,t]* FLECCS_parameters[!,:intercept][y])
    # CO2 generated by combustion TURBINE (or oxyfuel power cycle) at hour "t" [tonne]
    @expression(EP, eCO2_flue[y in FLECCS_ALL,t=1:T], inputs["CO2_per_MMBTU_FLECCS"][y,OXY_id] * eFuel[y,t])
    # CO2 vent
	@expression(EP, eCO2_vent[y in FLECCS_ALL,t=1:T],(1-FLECCS_parameters[!,:pCO2Cap][y])  *eCO2_flue[y,t])
    
	
	
	
	# power consumption is a function of gnerated LOX
    @expression(EP, ePower_asu[y in FLECCS_ALL,t=1:T],  FLECCS_parameters[!,:pPowerUseRate_lox][y] * vLOX_store[y,t])
    # auxillary load 
	@expression(EP, ePower_other[y in FLECCS_ALL,t=1:T],  FLECCS_parameters[!,:pPowerUseRate_other][y] * vP_oxy[y,t])
	# the amount of LOX feed into oxyfuel cycle should be propotional to the power generated by oxyfuel cycle
	@expression(EP, eLOX_use[y in FLECCS_ALL,t=1:T],  FLECCS_parameters[!,:pO2UseRate][y] * vP_oxy[y,t])
	# net power output = vP_gt + ePower_st - ePower_use_comp - ePower_use_pcc
	@expression(EP, eCCS_net[y in FLECCS_ALL,t=1:T], vP_oxy[y,t] - ePower_asu[y,t] - ePower_other[y,t])

	@expression(EP, ePowerBalanceFLECCS[t=1:T, z=1:Z], sum(eCCS_net[y,t] for y in unique(dfGen_ccs[(dfGen_ccs[!,:Zone].==z),:R_ID])))

	#solvent storage mass balance
	# dynamic of rich solvent storage system, normal [tonne solvent/sorbent]
	@constraint(EP, cStore_lox[y in FLECCS_ALL, t in INTERIOR_SUBPERIODS],vSTORE_lox[y, t] == vSTORE_lox[y, t-1] + vLOX_store[y,t] - eLOX_use[y,t])
	# dynamic of rich solvent system, wrapping [tonne solvent/sorbent]
	@constraint(EP, cStore_loxwrap[y in FLECCS_ALL, t in START_SUBPERIODS],vSTORE_lox[y, t] == vSTORE_lox[y,t+hours_per_subperiod-1] + + vLOX_store[y,t] - eLOX_use[y,t])


	## Power Balance##
	EP[:ePowerBalance] += ePowerBalanceFLECCS


	# create a container for FLECCS output.
	@constraints(EP, begin
	    [y in FLECCS_ALL, i in OXY_id, t = 1:T],EP[:vFLECCS_output][y,i,t] == vP_oxy[y,t]
		[y in FLECCS_ALL, i in ASU_id,t = 1:T],EP[:vFLECCS_output][y,i,t] == ePower_asu[y,t]	
		[y in FLECCS_ALL, i in LOX_id,t = 1:T],EP[:vFLECCS_output][y,i,t] == vSTORE_lox[y,t]
		[y in FLECCS_ALL, i in BOP_id, t =1:T],EP[:vFLECCS_output][y,i,t] == eCCS_net[y,t]			
	end)

	@constraint(EP, [y in FLECCS_ALL], EP[:eTotalCapFLECCS][y, BOP_id] == EP[:eTotalCapFLECCS][y, OXY_id])



	###########variable cost
	#fuel
	@expression(EP, eCVar_fuel[y in FLECCS_ALL, t = 1:T],(inputs["omega"][t]*fuel_costs[fuel_type[1]][t]*eFuel[y,t]))

	# CO2 sequestration cost applied to sequestrated CO2
	@expression(EP, eCVar_CO2_sequestration[y in FLECCS_ALL, t = 1:T],(inputs["omega"][t]*eCO2_flue[y,t]*FLECCS_parameters[!,:pCO2_sequestration][y]))


	# start variable O&M
	# variable O&M for oxyfuel cycle
	@expression(EP,eCVar_oxy[y in FLECCS_ALL, t = 1:T], inputs["omega"][t]*(dfGen_ccs[(dfGen_ccs[!,:FLECCS_NO].==OXY_id) .& (dfGen_ccs[!,:R_ID].==y),:Var_OM_Cost_per_Unit][1])*vP_oxy[y,t])
	# variable O&M for ASU
	@expression(EP,eCVar_asu[y in FLECCS_ALL, t = 1:T], inputs["omega"][t]*(dfGen_ccs[(dfGen_ccs[!,:FLECCS_NO].==ASU_id) .& (dfGen_ccs[!,:R_ID].==y),:Var_OM_Cost_per_Unit][1])*ePower_asu[y,t])
	 # variable O&M for LOX
	@expression(EP,eCVar_lox[y in FLECCS_ALL, t = 1:T], inputs["omega"][t]*(dfGen_ccs[(dfGen_ccs[!,:FLECCS_NO].== LOX_id) .& (dfGen_ccs[!,:R_ID].==y),:Var_OM_Cost_per_Unit][1])*(vSTORE_lox[y,t]))


	#adding up variable cost

	@expression(EP,eVar_FLECCS[t = 1:T], sum(eCVar_fuel[y,t] + eCVar_CO2_sequestration[y,t] + eCVar_oxy[y,t] + eCVar_asu[y,t] + eCVar_lox[y,t] for y in FLECCS_ALL))

	@expression(EP,eTotalCVar_FLECCS, sum(eVar_FLECCS[t] for t in 1:T))


	EP[:eObj] += eTotalCVar_FLECCS



	return EP
end
