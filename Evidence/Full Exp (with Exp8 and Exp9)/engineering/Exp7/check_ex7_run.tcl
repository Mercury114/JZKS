set project_root [file normalize [file dirname [info script]]]
open_project [file join $project_root vivado_ex7 loongson_ex7.xpr]
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS=[get_property PROGRESS [get_runs impl_1]]"
close_project
exit
