set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set vivado_bin [file normalize [file join [file dirname [info nameofexecutable]]]]

cd $repo_dir
file mkdir sim/xsim_s_axi_reg_bar2_ring
cd sim/xsim_s_axi_reg_bar2_ring

puts [exec $vivado_bin/xvlog -sv -i ../../hw ../../hw/s_axi_reg.v ../tb_s_axi_reg_bar2_ring.v]
puts [exec $vivado_bin/xelab tb_s_axi_reg_bar2_ring -debug typical -s tb_s_axi_reg_bar2_ring_sim]
puts [exec $vivado_bin/xsim tb_s_axi_reg_bar2_ring_sim -runall]
