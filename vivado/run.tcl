set scripts_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $scripts_dir]
set mode [lindex $argv 0]
if {$mode eq ""} {set mode create}
set project_path [file join $scripts_dir console_build uart_console.xpr]
proc audit_sources {repo_dir scripts_dir} {
    set channel [open [file join $scripts_dir console_build source_paths.txt] w]
    fconfigure $channel -encoding utf-8
    set prefix "[string tolower [file normalize $repo_dir]]/"
    foreach object [get_files -all] {
        set path [file normalize $object]
        puts $channel $path
        if {![string match "${prefix}*" [string tolower $path]]} {
            close $channel
            error "Source outside clone: $path"
        }
    }
    close $channel
    puts "UART_CONSOLE_SOURCE_AUDIT_PASS"
}
if {[catch {
    if {$mode ni {create simulate simulate_hw fifo stopwatch stopwatch_hw irq irq_hw bitstream}} {error "Unknown mode: $mode"}
    if {![file exists $project_path]} {
        source -notrace [file join $scripts_dir create_project.tcl]
    } else {open_project $project_path}
    # Track both firmware files. Regenerate RAM products when a build changes them.
    set stamp {}
    foreach name {inst_ram data_ram} {
        set coe [file normalize [file join $repo_dir innovation_uart sw obj ${name}.coe]]
        lappend stamp $name [file mtime $coe] [file size $coe]
        set_property -dict [list CONFIG.Load_Init_File true CONFIG.Coe_File $coe] [get_ips $name]
    }
    set stamp_path [file join $scripts_dir console_build firmware_stamp.txt]
    set old_stamp ""
    if {[file exists $stamp_path]} {set channel [open $stamp_path r]; set old_stamp [read $channel]; close $channel}
    if {$old_stamp ne $stamp} {
        reset_target all [get_ips]
        generate_target all [get_ips]
        set channel [open $stamp_path w]; puts -nonewline $channel $stamp; close $channel
    }
    set stopwatch_tb [file join $repo_dir innovation_uart sim tb_uart_stopwatch.v]
    if {[llength [get_files -quiet $stopwatch_tb]] == 0} {
        add_files -fileset sim_1 -norecurse $stopwatch_tb
    }
    set irq_tb [file join $repo_dir innovation_uart sim tb_uart_irq.v]
    if {[llength [get_files -quiet $irq_tb]] == 0} {
        add_files -fileset sim_1 -norecurse $irq_tb
    }
    audit_sources $repo_dir $scripts_dir
    foreach ip [get_ips] {
        set name [get_property NAME $ip]
        if {[llength [get_runs -quiet ${name}_synth_1]] == 0} {create_ip_run [get_ips $name]}
    }
    if {$mode in {simulate simulate_hw fifo stopwatch stopwatch_hw irq irq_hw}} {
        switch $mode {
            simulate {set top tb_uart_console; set path /tb_uart_console}
            simulate_hw {set top tb_uart_console_hwclk; set path /tb_uart_console_hwclk/test}
            fifo {set top tb_uart_fifo; set path /tb_uart_fifo}
            irq {set top tb_uart_irq; set path /tb_uart_irq}
            irq_hw {set top tb_uart_irq_hwclk; set path /tb_uart_irq_hwclk/test}
            stopwatch {set top tb_uart_stopwatch; set path /tb_uart_stopwatch}
            stopwatch_hw {set top tb_uart_stopwatch_hwclk; set path /tb_uart_stopwatch_hwclk/test}
        }
        set_property top $top [get_filesets sim_1]
        update_compile_order -fileset sim_1
        set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
        launch_simulation -simset sim_1 -mode behavioral
        run all
        set ended [get_value -radix unsigned $path/test_end]
        set failed [get_value -radix unsigned $path/global_err]
        set checks [get_value -radix unsigned $path/checks]
        if {$ended ne "1" || $failed ne "0" || $checks < 20} {
            error "UART test failed: end=$ended error=$failed checks=$checks"
        }
        if {$mode ne "fifo"} {
            set cases [get_value -radix unsigned $path/cases]
            if {$cases < 8} {error "Too few command cases: $cases"}
            if {$mode in {irq irq_hw}} {
                puts "UART_IRQ_VERIFIED: mode=$mode cases=$cases checks=$checks"
            } elseif {$mode in {stopwatch stopwatch_hw}} {
                puts "UART_STOPWATCH_VERIFIED: mode=$mode cases=$cases checks=$checks"
            } else {puts "UART_CONSOLE_VERIFIED: mode=$mode cases=$cases checks=$checks"}
        } else {puts "UART_FIFO_VERIFIED: checks=$checks"}
        close_sim
        set_property top tb_uart_console [get_filesets sim_1]
        set_property xsim.simulate.runtime 1000ns [get_filesets sim_1]
    }
    if {$mode eq "bitstream"} {
        launch_runs impl_1 -to_step write_bitstream -jobs 4
        wait_on_run impl_1
        if {![string match {*write_bitstream Complete*} [get_property STATUS [get_runs impl_1]]]} {
            error "Bitstream failed: [get_property STATUS [get_runs impl_1]]"
        }
        puts "UART_CONSOLE_BITSTREAM_COMPLETE"
    }
    close_project
} message options]} {
    puts stderr "UART_CONSOLE_ERROR: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
