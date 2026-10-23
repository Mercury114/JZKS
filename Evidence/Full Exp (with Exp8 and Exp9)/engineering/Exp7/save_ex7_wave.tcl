set project_root [file normalize [file dirname [info script]]]
set project_file [file join $project_root vivado_ex7 loongson_ex7.xpr]
set wave_file [file join $project_root vivado_ex7 loongson_ex7.sim sim_1 behav xsim tb_top_behav.wcfg]

open_project $project_file
launch_simulation -simset sim_1 -mode behavioral
if {[string length [current_wave_config]] > 0} {
    save_wave_config $wave_file
}
close_sim
close_project
exit
