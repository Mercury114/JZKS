set root [file normalize [file dirname [info script]]]
set out  [file join $root build]
file mkdir $out
create_project -force dcache_verify $out -part xc7a200tfbg676-1
set_property target_language Verilog [current_project]
add_files -norecurse [file join $root rtl cache.v]
add_files -fileset sim_1 -norecurse [file join $root tb cache_top.v]
add_files -fileset sim_1 -norecurse [file join $root tb testbench.v]
add_files -fileset sim_1 -norecurse [file join $root tb clk_pll_stub.v]
set_property top tb_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
