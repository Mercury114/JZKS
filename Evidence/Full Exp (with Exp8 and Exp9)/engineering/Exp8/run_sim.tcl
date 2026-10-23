if {$argc != 1} { error "Usage: vivado -mode batch -source run_sim.tcl -tclargs ex8|ex9" }
set project_root [file normalize [file dirname [info script]]]
open_project [file join $project_root vivado_ex8 loongson_ex8.xpr]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
exit
