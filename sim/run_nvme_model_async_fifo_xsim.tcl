set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set vivado_bin [file normalize [file join [file dirname [info nameofexecutable]]]]

cd $repo_dir
file mkdir sim/xsim_nvme_model_async_fifo
cd sim/xsim_nvme_model_async_fifo
puts [exec $vivado_bin/xvlog -sv ../../hw/nvme_ssd_latency.v ../tb_nvme_model_async_fifo.v]
puts [exec $vivado_bin/xelab tb_nvme_model_async_fifo -debug typical -s tb_nvme_model_async_fifo_sim]
puts [exec $vivado_bin/xsim tb_nvme_model_async_fifo_sim -runall]
