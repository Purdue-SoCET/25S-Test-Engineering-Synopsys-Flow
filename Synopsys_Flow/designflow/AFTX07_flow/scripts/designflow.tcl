#### Sourcing common setup script
source -echo ../../setup/fc_common_setup.tcl

#### Sourcing flow setup script
source -echo ../../setup/fc_flow_setup.tcl

#### Creating Design Library
if {[string equal frame_only ${REF_NDM}]} {
	#### Specify the link libraries
	set_app_var link_library "${DB_FF} ${DB_TT} ${DB_SS}"
	
	create_lib ${RESULTS_PATH}/${DESIGN_LIBRARY} -technology $TECH_FILE -ref_libs ${REFERENCE_LIBRARY}
} elseif {[string equal frame_timing ${REF_NDM}]} {
	if {[string equal ndm ${TECH_BASED}]} {
		lappend REFERENCE_LIBRARY ${TECH_NDM}
		create_lib ${RESULTS_PATH}/${DESIGN_LIBRARY} -use_technology_lib ${TECH_NDM} -ref_libs ${REFERENCE_LIBRARY} 
	} elseif {[string equal tf ${TECH_BASED}]} {
		create_lib ${RESULTS_PATH}/${DESIGN_LIBRARY} -technology $TECH_FILE -ref_libs ${REFERENCE_LIBRARY}
	} else {
		echo "Error: TECH_BASED variable's value is not ndm or tf. Please fix the value."
	}
} else {
	echo "Error: REF_NDM variable's value is frame_only ndm or frame_timing. Please fix the value."
}

#### Report reference libraries
report_ref_libs

#### Reading RTL

# Analyze the HDL
# Suppress known warnings 
suppress_message VER-130
set VERILOG_PATH "/home/asicfab/a/socet238/Synopsys_Flow/common/rtl/verilog/src_uart"
analyze -format sverilog [glob ${VERILOG_PATH}/*.sv]

#if {[string equal verilog ${HDL}]} { 
	#analyze -format verilog [glob ${VERILOG_PATH}/*.v]
#} elseif {[string equal vhdl ${HDL}]} {
#	analyze -format vhdl [glob ${VHDL_PATH}/*.vhd]
# else {
#	echo "Error: HDL variable's value is not verilog or vhdl. Please fix the value."
#}
# Unsuppress after analyze stage
unsuppress_message VER-130

# Elaborate
elaborate ${DESIGN_NAME}

# Set top module in the design
set_top_module ${DESIGN_NAME}

# Save block after RTL setup
save_block -as ${DESIGN_NAME}/rtl_read

source -echo ../../setup/tech_setup.tcl
read_sdc -echo ${SDC_FILE}
# MCMM setup
source -echo ../../setup/mcmm_setup.tcl
# Setup application options
set_lib_cell_purpose -include none {*/*_AO21* */*V2LP*}
set_app_options -name place.coarse.continue_on_missing_scandef -value true

# Check the design before compile_fusion
compile_fusion -check_only
# initial_map stage
compile_fusion -to initial_map
save_block -as after_initila_map
#### Initialize the floorplan
initialize_floorplan  \
	-control_type core \
	-core_utilization 1 \
	-core_offset 1 \
	-side_length {37 37} \
	-flip_first_row true
# logic_opto stage
compile_fusion -from logic_opto -to logic_opto
save_block -as after_logic_opto

# scan_insertion goes here
create_port -direction in scandata_in1
create_port -direction in scandata_in2
create_port -direction in scandata_in3
create_port -direction in scandata_in4
create_port -direction out scandata_out1
create_port -direction out scandata_out2
create_port -direction out scandata_out3
create_port -direction out scandata_out4
create_port -direction in scandata_enable

# Scan in, scan out, scan enable
set_dft_signal -view spec -type ScanDataIn -port scandata_in1
set_dft_signal -view spec -type ScanDataIn -port scandata_in2
set_dft_signal -view spec -type ScanDataIn -port scandata_in3
set_dft_signal -view spec -type ScanDataIn -port scandata_in4

set_dft_signal -view spec -type ScanDataout -port scandata_out1
set_dft_signal -view spec -type ScanDataout -port scandata_out2
set_dft_signal -view spec -type ScanDataout -port scandata_out3
set_dft_signal -view spec -type ScanDataout -port scandata_out4

set_dft_signal -view spec -type ScanEnable -port scandata_enable

set_scan_configuration -chain_count 4
set_dft_signal -type ScanClock -port clk

set_dft_signal -view existing -type ScanClock \
   -port ATEclk -timing [list 45 55]

## might have to change if Design flow team says they have slow frequency clock (ATE) clk->"name"

set_dft_signal -view existing -type Reset \
   -port reset_n -active_state 0
## active states resets and sets

create_test_protocol
dft_drc
preview_dft 
##error
insert_dft
return

# initial_place stage
compile_fusion -from initial_place -to initial_place
save_block -as after_initila_place
# initial_drc stage
compile_fusion -from initial_drc -to initial_drc
save_block -as after_initila_drc
# initial_opto stage
compile_fusion -from initial_opto -to initial_opto
save_block -as after_initila_opto
# final_place stage
compile_fusion -from final_place -to final_place
save_block -as after_final_place
# final_opto stage
compile_fusion -from final_opto -to final_opto
check_legality
save_block -as final_opto
# write_output
write_verilog -hierarchy design ${DESIGN_NAME}.v

source -echo /home/asicfab/a/socet238/Synopsys_Flow/designflow/AFTX07_flow/scripts/clock_constraint.tcl
# List the stages of clock_opt command
clock_opt -list_only
# Synthesize and optimize the clock tree
clock_opt -to build_clock
# Detail routing of clock
clock_opt -from build_clock -to route_clock 
# Optimization and legalization
clock_opt -to final_opto
# Remove global routes to review the clock tree
remove_routes -global_route 
#### Clock shielding with VSS
###set clock_nets [get_nets \ 
###	-hierarchical -filter "net_type == clock"]
####create_shields -nets ${clock_nets} -with_ground VSS -preferred_direction_only true -align_to_shape_end true
save_block -as after_clock_opto


source -echo /home/asicfab/a/socet238/Synopsys_Flow/designflow/AFTX07_flow/scripts/route_constraint.tcl

# Check the design
check_routability
# Global routing
route_global
# Track assignment and net routing
route_track
# Detail routing and DRC fixing
route_detail 
# route_auto command will run above 3 steps
#### Routing optimization
route_opt
#### Add redundant VIAs
add_redundant_vias 
#### ECO routing fix
route_eco
#### Check the routing
check_routes
check_lvs

# Analyze the design
save_block -as after_route_opt
report_qor

## Here goes ATPG part // gotta update to Github
dft_drc -coverage_estimate -test_mode Internal_scan 
dft_drc -coverage_estimate -test_mode ScanCompression_mode 
# For ATPG: 
write_test_protocol -output scan_compressed.spf -test_mode ScanCompression_mode 
write_test_protocol -output scan_internal.spf -test_mode Internal_scan
