# 在create_project.tcl创建/打开工程后运行。
if {[current_project -quiet] eq ""} {error "Open cache_course.xpr first"}
set project_dir [get_property DIRECTORY [current_project]]
set rom [file join $project_dir program.hex]
if {![file exists $rom]} {error "Missing program.hex in project directory"}
set sim_dir [file join $project_dir cache_course.sim sim_1 behav xsim]
file mkdir $sim_dir
file copy -force $rom [file join $sim_dir program.hex]
launch_simulation
run all
# 成功须检查原教师 PASS teacher cache SoC 和全部功能点，不能只看编译通过。
