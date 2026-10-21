set root [file normalize [file dirname [info script]]]
set build [file join $root build dcache_project]
file mkdir $build
create_project -force dcache_extension $build -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
add_files -norecurse [file join $root rtl dcache.v]
add_files -fileset sim_1 -norecurse [file join $root tb dcache_tb.v]
set_property top dcache_tb [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
exit
