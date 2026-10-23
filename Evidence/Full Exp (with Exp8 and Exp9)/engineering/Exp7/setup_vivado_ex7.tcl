set project_root [file normalize [file dirname [info script]]]
set project_dir [file join $project_root vivado_ex7]
file mkdir $project_dir

create_project loongson_ex7 $project_dir -part xc7a200tfbg676-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

set rtl_files [list \
    [file join $project_root rtl mycpu_head.v] \
    [file join $project_root rtl tools.v] \
    [file join $project_root rtl alu.v] \
    [file join $project_root rtl regfile.v] \
    [file join $project_root rtl IF_stage.v] \
    [file join $project_root rtl ID_stage.v] \
    [file join $project_root rtl EXE_stage.v] \
    [file join $project_root rtl MEM_stage.v] \
    [file join $project_root rtl WB_stage.v] \
    [file join $project_root rtl mycpu_top.v] \
    [file join $project_root rtl bridge_1x2.v] \
    [file join $project_root rtl soc_lite_top.v] \
    [file join $project_root rtl remote2local.v] \
    [file join $project_root rtl loongson_remote_top.v] \
    [file join $project_root rtl confreg.v]]
add_files -norecurse $rtl_files

set ip_files [list \
    [file join $project_root ip_ascii clk_pll clk_pll.xci] \
    [file join $project_root ip_ascii data_ram data_ram.xci] \
    [file join $project_root ip_ascii inst_ram inst_ram.xci]]
add_files -norecurse $ip_files
generate_target all [get_files $ip_files]

add_files -fileset constrs_1 -norecurse [file join $project_root rtl loongson_remote.xdc]
add_files -fileset sim_1 -norecurse [file join $project_root local_sim_ex7 tb_top_ex6.v]

set_property top looongson_remote_top [get_filesets sources_1]
set_property top tb_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
close_project
exit
