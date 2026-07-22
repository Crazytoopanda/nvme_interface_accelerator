set vivado_bin [file normalize [file join [file dirname [info nameofexecutable]]]]
file mkdir sim/xsim_nvme_auto_io_engine
cd sim/xsim_nvme_auto_io_engine
puts [exec $vivado_bin/xvlog -sv ../../hw/nvme_auto_io_engine.v ../tb_nvme_auto_io_engine.v]
puts [exec $vivado_bin/xelab tb_nvme_auto_io_engine -debug typical -s tb_nvme_auto_io_engine_sim]
puts [exec $vivado_bin/xsim tb_nvme_auto_io_engine_sim -runall]
