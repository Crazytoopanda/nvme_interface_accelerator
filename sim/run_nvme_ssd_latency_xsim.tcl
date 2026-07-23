set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set vivado_bin [file normalize [file join [file dirname [info nameofexecutable]]]]

cd $repo_dir
file mkdir sim/xsim_nvme_ssd_latency
cd sim/xsim_nvme_ssd_latency
puts [exec $vivado_bin/xvlog -sv ../../hw/nvme_ssd_latency.v ../tb_nvme_ssd_latency.v]
puts [exec $vivado_bin/xelab tb_nvme_ssd_latency -debug typical -s tb_nvme_ssd_latency_sim]
puts [exec $vivado_bin/xsim tb_nvme_ssd_latency_sim -runall]
