set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]

cd $repo_dir
file mkdir sim/xsim_dma_cmd_gen
cd sim/xsim_dma_cmd_gen

xvlog -sv ../../hw/dma_cmd_gen.v ../tb_dma_cmd_gen.v
xelab tb_dma_cmd_gen -debug typical -s tb_dma_cmd_gen_sim
xsim tb_dma_cmd_gen_sim -runall
