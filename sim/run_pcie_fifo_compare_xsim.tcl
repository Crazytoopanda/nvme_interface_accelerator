set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set vivado_bin "/tools/Xilinx/Vivado/2023.2/bin"

proc rename_module_in_file {path old_name new_name} {
	set fp [open $path r]
	set text [read $fp]
	close $fp

	regsub -all "module\[ \t\r\n\]\+$old_name" $text "module $new_name" text

	set fp [open $path w]
	puts -nonewline $fp $text
	close $fp
}

cd $repo_dir
file mkdir sim/xsim_pcie_fifo_compare
cd sim/xsim_pcie_fifo_compare

file copy -force ../../hw_temp/pcie_tx_fifo.v pcie_tx_fifo_old.v
file copy -force ../../hw/pcie_tx_fifo.v pcie_tx_fifo_new.v
file copy -force ../../hw_temp/pcie_rx_fifo.v pcie_rx_fifo_old.v
file copy -force ../../hw/pcie_rx_fifo.v pcie_rx_fifo_new.v

rename_module_in_file pcie_tx_fifo_old.v pcie_tx_fifo pcie_tx_fifo_old
rename_module_in_file pcie_tx_fifo_new.v pcie_tx_fifo pcie_tx_fifo_new
rename_module_in_file pcie_rx_fifo_old.v pcie_rx_fifo pcie_rx_fifo_old
rename_module_in_file pcie_rx_fifo_new.v pcie_rx_fifo pcie_rx_fifo_new

puts [exec $vivado_bin/xvlog -sv pcie_tx_fifo_old.v pcie_tx_fifo_new.v pcie_rx_fifo_old.v pcie_rx_fifo_new.v ../tb_pcie_fifo_compare.v]
puts [exec $vivado_bin/xelab tb_pcie_fifo_compare -debug typical -s tb_pcie_fifo_compare_sim]
puts [exec $vivado_bin/xsim tb_pcie_fifo_compare_sim -runall]
