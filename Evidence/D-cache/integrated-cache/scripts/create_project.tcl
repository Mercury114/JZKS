# Vivado 2023.2 Tcl Console: source Cache/scripts/create_project.tcl
# 先运行 python Cache/scripts/prepare_vivado.py --exp 9。
# 仅创建新工程；不覆盖已有工程，不自动综合或连接FPGA。
set cache_dir [file normalize [file join [file dirname [info script]] ..]]
set repo_dir [file dirname $cache_dir]
set output_dir [file join $cache_dir build vivado_project]
set part_name xc7a200tfbg676-1
if {[info exists ::env(CACHE_PART)]} {set part_name $::env(CACHE_PART)}
set input_dir [file join $cache_dir build vivado_input]
if {![file exists [file join $input_dir program.hex]]} {
    error "Missing program.hex: run prepare_vivado.py first"
}
if {[file exists [file join $output_dir cache_course.xpr]]} {
    error "Project already exists; open it instead of overwriting: $output_dir/cache_course.xpr"
}
source [file join $input_dir settings.tcl]
create_project cache_course $output_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files [glob [file join $cache_dir rtl *.v]]
add_files [glob [file join $cache_dir rtl cpu *.v]]
add_files [file join $repo_dir Exp9_源码_v文件 rtl confreg.v]
add_files [file join $repo_dir Exp9_源码_v文件 rtl remote2local.v]
set_property include_dirs [list [file join $cache_dir rtl cpu]] [get_filesets sources_1]
file copy -force [file join $input_dir program.hex] [file join $output_dir program.hex]
add_files [file join $output_dir program.hex]
set_property top cache_remote_top [get_filesets sources_1]
set_property generic {INST_INIT_FILE="program.hex"} [get_filesets sources_1]
add_files -fileset sim_1 [file join $cache_dir tb teacher_cache_tb.v]
set_property top teacher_cache_tb [get_filesets sim_1]
set_property generic [list TARGET_POINTS=$cache_points] [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
add_files -fileset constrs_1 [file join $cache_dir constraints cdp_remote.xdc]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Prepared cache_course for $part_name, teacher ex$cache_exp ($cache_points points)."
puts "CDP remote-board XDC added. Confirm that the actual board/device matches before implementation."
