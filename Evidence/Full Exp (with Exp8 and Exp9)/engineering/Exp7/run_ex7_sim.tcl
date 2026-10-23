set project_root [file normalize [file dirname [info script]]]
open_project [file join $project_root vivado_ex7 loongson_ex7.xpr]
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
exit
