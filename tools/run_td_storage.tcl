# Run with: <TD>/bin/td_commands_prompt.exe tools/run_td_storage.tcl
# Sources the .al project, then builds into build/td/storage. No board download.
set repo [file dirname [file dirname [file normalize [info script]]]]
set out [file join $repo build td storage]
file mkdir $out
set project [file join $repo project td Storage_Bringup.al]
if {[catch {
    cd [file dirname $project]
    import_device eagle_s20.db -package EG4S20BG256
    open_project $project -single_run
    load_run_param -run syn_1
    cd $out
    elaborate -top hx4s20c_storage_bringup
    read_adc [file join $repo constraints hx4s20c_storage_bringup.adc]
    read_sdc [file join $repo constraints hx4s20c_storage_bringup.sdc]
    export_db Storage_Bringup_elaborate.db
    optimize_rtl
    report_area -file Storage_Bringup_rtl.area
    export_db Storage_Bringup_rtl.db
    optimize_gate -packarea Storage_Bringup_gate.area
    legalize_phy_inst
    update_timing
    report_timing_status -file Storage_Bringup_gate.ts
    report_timing_summary -file Storage_Bringup_gate.timing
    export_db Storage_Bringup_gate.db
    puts "PASS_TD_SYNTHESIS"
} problem]} {
    puts stderr "FAIL_TD_SYNTHESIS: $problem"
    puts stderr $::errorInfo
    exit 1
}
exit 0
