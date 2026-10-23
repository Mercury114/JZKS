set scripts_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $scripts_dir]
set mode [lindex $argv 0]
if {$mode eq ""} {set mode create}
set firmware [lindex $argv 1]
if {$firmware eq "" || $firmware eq "auto"} {
    set firmware [expr {$mode in {create bitstream} ? "ex9" : "uart"}]
}
if {$firmware ni {uart ex9}} {error "Unknown firmware: $firmware"}
set build_dir [file join $scripts_dir [expr {$firmware eq "uart" ? "console_build_uart" : "console_build"}]]
# Separate board builds from interactive/source simulation projects.
if {$mode eq "bitstream" && $firmware eq "uart"} {set build_dir [file join $scripts_dir console_build_uart_board]}
set project_path [file join $build_dir pipeline_uart.xpr]
proc audit_sources {repo_dir build_dir} {
    set channel [open [file join $build_dir source_paths.txt] w]
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
    # The checked-in XCI files already carry their initialization settings.
    set stopwatch_tb [file join $repo_dir innovation_uart sim tb_uart_stopwatch.v]
    if {[llength [get_files -quiet $stopwatch_tb]] == 0} {
        add_files -fileset sim_1 -norecurse $stopwatch_tb
    }
    set irq_tb [file join $repo_dir innovation_uart sim tb_uart_irq.v]
    if {[llength [get_files -quiet $irq_tb]] == 0} {
        add_files -fileset sim_1 -norecurse $irq_tb
    }
    # UART board fix: also update existing projects with the hardware smoke test.
    set board_tb [file join $repo_dir innovation_uart sim tb_uart_board_boot.v]
    if {[llength [get_files -quiet $board_tb]] == 0} {
        add_files -fileset sim_1 -norecurse $board_tb
    }
    audit_sources $repo_dir $build_dir
    # Locked course IPs are imported as board-provided generated sources; no
    # out-of-context IP run is needed for the source-level integration build.
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
        # Rebuild from the in-place RTL so a previously interrupted run cannot
        # reuse an out-of-date synthesized control path.
        reset_run synth_1
        reset_run impl_1
        launch_runs synth_1 -jobs 4
        wait_on_run synth_1
        if {![string match {*synth_design Complete*} [get_property STATUS [get_runs synth_1]]]} {
            error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
        }
        if {$firmware eq "uart"} {
            # RTL simulation cannot detect an empty synthesized instruction ROM.
            # Observe the actual top-level TX start and startup LEDs from the netlist.
            set saved_top [get_property top [get_filesets sim_1]]
            set_property top tb_uart_board_boot [get_filesets sim_1]
            launch_simulation -simset sim_1 -mode post-synthesis -type functional
            run all
            set boot_end [get_value -radix unsigned /tb_uart_board_boot/test_end]
            set boot_err [get_value -radix unsigned /tb_uart_board_boot/global_err]
            set boot_checks [get_value -radix unsigned /tb_uart_board_boot/checks]
            close_sim
            set_property top $saved_top [get_filesets sim_1]
            if {$boot_end ne "1" || $boot_err ne "0" || $boot_checks != 3} {
                error "Synthesized UART boot failed: end=$boot_end error=$boot_err checks=$boot_checks"
            }
            puts "UART_BOARD_BOOT_VERIFIED: checks=$boot_checks"
        }
        launch_runs impl_1 -to_step write_bitstream -jobs 4
        wait_on_run impl_1
        if {![string match {*write_bitstream Complete*} [get_property STATUS [get_runs impl_1]]]} {
            error "Bitstream failed: [get_property STATUS [get_runs impl_1]]"
        }
        open_run impl_1
        if {[llength [get_clocks -quiet cpu_clk]] != 1} {
            error "CPU generated clock is unconstrained"
        }
        foreach kind {max min} {
            set worst [get_timing_paths -delay_type $kind -max_paths 1]
            if {[llength $worst] == 0 || [get_property SLACK $worst] < 0} {
                error "Routed timing failed ($kind); inspect the timing report"
            }
        }
        puts "UART_CPU_ROUTED_TIMING_VERIFIED"
        puts "UART_CONSOLE_BITSTREAM_COMPLETE"
    }
    close_project
} message options]} {
    puts stderr "UART_CONSOLE_ERROR: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
