set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]

file mkdir [file join $script_dir ooc_nvme_ssd_latency]
read_verilog [file join $repo_dir hw nvme_ssd_latency.v]
synth_design -top nvme_ssd_latency -part xczu17eg-ffvc1760-2-e -mode out_of_context

create_clock -name pcie_user_clk -period 4.000 [get_ports pcie_user_clk]
create_clock -name cpu_bus_clk -period 10.000 [get_ports cpu_bus_clk]
set_clock_groups -asynchronous -group [get_clocks pcie_user_clk] -group [get_clocks cpu_bus_clk]

opt_design
report_utilization -hierarchical -file [file join $script_dir ooc_nvme_ssd_latency utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $script_dir ooc_nvme_ssd_latency timing.rpt]
report_drc -file [file join $script_dir ooc_nvme_ssd_latency drc.rpt]
write_checkpoint -force [file join $script_dir ooc_nvme_ssd_latency nvme_ssd_latency.dcp]
