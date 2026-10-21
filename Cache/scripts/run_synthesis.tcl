# 已打开cache_course工程后手动运行；只综合与生成报告，不实现/写bitstream。
if {[current_project -quiet] eq ""} {error "Open cache_course.xpr first"}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis did not complete"}
open_run synth_1
set report_dir [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $report_dir
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing.rpt]
puts "Reports written to $report_dir; post-synthesis timing is not routed timing."
