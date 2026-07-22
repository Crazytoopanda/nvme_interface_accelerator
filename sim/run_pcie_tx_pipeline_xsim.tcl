set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
cd $repo_dir
file mkdir sim/xsim_pcie_tx_pipeline
cd sim/xsim_pcie_tx_pipeline
puts [exec xvlog -sv -i ../../hw ../../hw/pcie_tx_tran.v ../tb_pcie_tx_pipeline.v]
puts [exec xelab tb_pcie_tx_pipeline -debug typical -s tb_pcie_tx_pipeline_sim]
puts [exec xsim tb_pcie_tx_pipeline_sim -runall]
