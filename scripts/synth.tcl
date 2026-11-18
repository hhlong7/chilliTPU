# Vivado CLI entry point, also usable without Bash:
# vivado -mode batch -source scripts/synth.tcl -tclargs all xc7z020clg400-1 10
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set target all
set part xc7z020clg400-1
set period_ns 10
if {$argc > 3} {
    puts stderr "Usage: synth.tcl ?all|pe|systolic_array? ?part? ?clock_period_ns?"
    exit 2
}
if {$argc >= 1} { set target [lindex $argv 0] }
if {$argc >= 2} { set part [lindex $argv 1] }
if {$argc >= 3} { set period_ns [lindex $argv 2] }
if {$target ni {all pe systolic_array}} {
    puts stderr "ERROR: top must be all, pe, or systolic_array"
    exit 2
}
if {![string is double -strict $period_ns] || !($period_ns > 0 && $period_ns < Inf)} {
    puts stderr "ERROR: clock_period_ns must be a finite positive number"
    exit 2
}
set tops [list $target]
if {$target eq "all"} { set tops {pe systolic_array} }

if {[catch {
    if {[llength [get_parts -quiet $part]] == 0} {
        error "Device '$part' is not installed. Add its device family (Zynq-7000 for the Zybo Z7-20) using the Vivado installer, or choose an installed part with FPGA_PART / the second Tcl argument."
    }
    foreach top $tops {
        set out_dir [file join $repo_root build synth $top]
        file mkdir $out_dir
        create_project -in_memory -part $part
        read_verilog -sv [list \
            [file join $repo_root rtl pkg dnn_pkg.sv] \
            [file join $repo_root rtl pe.sv]]
        if {$top eq "systolic_array"} {
            read_verilog -sv [file join $repo_root rtl systolic_array.sv]
        }

        # Read the clock constraint before synthesis so it guides optimization.
        set clock_xdc [file join $out_dir ${top}_clock.xdc]
        set clock_file [open $clock_xdc w]
        puts $clock_file [format {create_clock -name clk -period %s [get_ports clk]} $period_ns]
        close $clock_file
        read_xdc $clock_xdc

        # OOC avoids treating the core's array buses as physical package pins.
        synth_design -top $top -part $part -mode out_of_context
        report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
        report_timing_summary -file [file join $out_dir timing_synth.rpt]
        write_checkpoint -force [file join $out_dir ${top}_synth.dcp]
        write_verilog -force -mode funcsim [file join $out_dir ${top}_synth.v]
        write_xdc -force [file join $out_dir ${top}_synth.xdc]
        close_project
        puts "PASS synthesis.$top"
    }
} message]} {
    puts stderr "SYNTHESIS FAILED: $message"
    exit 1
}
exit 0
