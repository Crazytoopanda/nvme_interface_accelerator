set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set vivado_bin /tools/Xilinx/Vivado/2023.2/bin

file mkdir [file join $script_dir xsim_nvme_ssd_latency_write_stress]
cd [file join $script_dir xsim_nvme_ssd_latency_write_stress]
puts [exec $vivado_bin/xvlog -sv \
	[file join $repo_dir hw nvme_ssd_latency.v] \
	[file join $script_dir tb_nvme_ssd_latency_write_stress.v]]
puts [exec $vivado_bin/xelab tb_nvme_ssd_latency_write_stress \
	-debug typical -s tb_nvme_ssd_latency_write_stress_sim]
puts [exec $vivado_bin/xsim tb_nvme_ssd_latency_write_stress_sim -runall]
