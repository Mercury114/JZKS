if {$argc != 1} { error "Usage: vivado -mode batch -source select_test.tcl -tclargs ex8|ex9" }
set image [lindex $argv 0]
if {$image ni {ex8 ex9}} { error "Test image must be ex8 or ex9" }
set project_root [file normalize [file dirname [info script]]]
set image_root [file join $project_root tests $image]
file copy -force [file join $image_root inst_ram.coe] [file join $project_root ip_ascii inst_ram inst_ram.coe]
file copy -force [file join $image_root inst_ram.mif] [file join $project_root ip_ascii inst_ram inst_ram.mif]
file copy -force [file join $image_root data_ram.coe] [file join $project_root ip_ascii data_ram data_ram.coe]
file copy -force [file join $image_root data_ram.mif] [file join $project_root ip_ascii data_ram data_ram.mif]
open_project [file join $project_root vivado_ex9 loongson_ex9.xpr]
set_property -dict [list CONFIG.Coe_File inst_ram.coe CONFIG.Load_Init_File true] [get_ips inst_ram]
set_property -dict [list CONFIG.Coe_File data_ram.coe CONFIG.Load_Init_File true] [get_ips data_ram]
generate_target all [get_ips]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
exit
