set project_root [file normalize [file dirname [info script]]]
open_project [file join $project_root vivado_ex7 loongson_ex7.xpr]
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Synthesis is not complete"
}
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation or bitstream generation failed"
}
close_project
exit
