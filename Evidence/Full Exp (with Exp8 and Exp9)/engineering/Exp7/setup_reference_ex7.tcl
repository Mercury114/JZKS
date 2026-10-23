set project_root [file normalize [file dirname [info script]]]
set build_dir [file join $project_root local_gettrace_ex7 build]
file mkdir $build_dir

create_project ex7_reference $build_dir -part xc7a200tfbg676-1 -force

add_files -norecurse [list \
    [file join $project_root local_gettrace_ex7 SimpleLACoreWrapRAM.v] \
    [file join $project_root local_gettrace_ex7 reference_soc_lite_top.v] \
    [file join $project_root external reference_bridge_1x2.v] \
    [file join $project_root external confreg.v]]
add_files -fileset sim_1 -norecurse [file join $project_root local_gettrace_ex7 reference_tb_top.v]

set_property top tb_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
exit
