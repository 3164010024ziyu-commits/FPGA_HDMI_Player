# Run after run_td_storage.tcl. Builds a candidate bitstream, never downloads it.
set repo [file dirname [file dirname [file normalize [info script]]]]
set out [file join $repo build td storage]
if {[catch {
    cd $out
    import_device eagle_s20.db -package EG4S20BG256
    import_db Storage_Bringup_gate.db
    place
    update_timing -mode manhattan
    report_timing_summary -file Storage_Bringup_place.timing
    export_db Storage_Bringup_place.db
    route
    update_timing -mode final
    report_area -io_info -file Storage_Bringup_phy.area
    report_timing_status -file Storage_Bringup_phy.ts
    report_timing_summary -file Storage_Bringup_pr.timing
    report_clock_utilization -file Storage_Bringup_clocks.txt
    export_db Storage_Bringup_pr.db
    set f [open Storage_Bringup_phy.ts r]
    set status [read $f]
    close $f
    if {![regexp {SWNS:\s*([-+0-9.]+)ns} $status unused setup]} {
        error "Could not parse setup timing status"
    }
    if {![regexp {HWNS:\s*([-+0-9.]+)ns} $status unused hold]} {
        error "Could not parse hold timing status"
    }
    if {$setup < 0 || $hold < 0} {
        error "Internal timing failed: setup=$setup ns, hold=$hold ns"
    }
    bitgen -bit Storage_Bringup.bit
    puts "PASS_TD_PNR: setup=$setup ns hold=$hold ns; external SD timing still requires validation"
} problem]} {
    puts stderr "FAIL_TD_PNR: $problem"
    puts stderr $::errorInfo
    exit 1
}
exit 0
