# PCIe refclk
set_property PACKAGE_PIN AH12 [get_ports diff_clock_rtl_1_clk_p]
set_property PACKAGE_PIN AH11 [get_ports diff_clock_rtl_1_clk_n]

# Reset
set_property PACKAGE_PIN D9 [get_ports sys_rst_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n_0]
set_property PACKAGE_PIN E1 [get_ports user_link_up_0]
set_property IOSTANDARD LVCMOS33 [get_ports user_link_up_0]



create_clock -period 10.000 -name sys_clk [get_ports diff_clock_rtl_1_clk_p]
#
set_false_path -from [get_ports sys_rst_n_0]
set_property PULLUP true [get_ports sys_rst_n_0]


# BITFILE/BITSTREAM compress options
# ##############################################################################
# Flash Programming Example Settings: These should be modified to match the target board.
# ##############################################################################
#
#
# sys_clk vs TXOUTCLK
set_clock_groups -name async18 -asynchronous -group [get_clocks sys_clk] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gthe4_channel_inst[*].GTHE4_CHANNEL_PRIM_INST/TXOUTCLK}]]
set_clock_groups -name async19 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gthe4_channel_inst[*].GTHE4_CHANNEL_PRIM_INST/TXOUTCLK}]] -group [get_clocks sys_clk]
#
#
# ASYNC CLOCK GROUPINGS
# sys_clk vs user_clk
set_clock_groups -name async5 -asynchronous -group [get_clocks sys_clk] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O}]]
set_clock_groups -name async6 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O}]] -group [get_clocks sys_clk]
# sys_clk vs pclk
set_clock_groups -name async1 -asynchronous -group [get_clocks sys_clk] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O}]]
set_clock_groups -name async2 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O}]] -group [get_clocks sys_clk]
#
#
#
# Add/Edit Pblock slice constraints for 512b soft logic to improve timing

# Keep This Logic Left/Right Side Of The PCIe Block (Whichever is near to the FPGA Boundary)
#set_property EXCLUDE_PLACEMENT 1 [get_pblocks soft_512b]
#
set_clock_groups -name async24 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_intclk/O}]] -group [get_clocks sys_clk]
#


# =========================
# TX lanes
# =========================
set_property PACKAGE_PIN AD8 [get_ports pcie_mgt_0_txp[0]]
set_property PACKAGE_PIN AD7 [get_ports pcie_mgt_0_txn[0]]

set_property PACKAGE_PIN AE6 [get_ports pcie_mgt_0_txp[1]]
set_property PACKAGE_PIN AE5 [get_ports pcie_mgt_0_txn[1]]

set_property PACKAGE_PIN AF8 [get_ports pcie_mgt_0_txp[2]]
set_property PACKAGE_PIN AF7 [get_ports pcie_mgt_0_txn[2]]

set_property PACKAGE_PIN AG6 [get_ports pcie_mgt_0_txp[3]]
set_property PACKAGE_PIN AG5 [get_ports pcie_mgt_0_txn[3]]

set_property PACKAGE_PIN AH8 [get_ports pcie_mgt_0_txp[4]]
set_property PACKAGE_PIN AH7 [get_ports pcie_mgt_0_txn[4]]

set_property PACKAGE_PIN AJ6 [get_ports pcie_mgt_0_txp[5]]
set_property PACKAGE_PIN AJ5 [get_ports pcie_mgt_0_txn[5]]

set_property PACKAGE_PIN AK8 [get_ports pcie_mgt_0_txp[6]]
set_property PACKAGE_PIN AK7 [get_ports pcie_mgt_0_txn[6]]

# Lane 7 polarity swapped
# reversal in trm???
set_property PACKAGE_PIN AL6 [get_ports pcie_mgt_0_txp[7]] 
set_property PACKAGE_PIN AL5 [get_ports pcie_mgt_0_txn[7]]

set_property PACKAGE_PIN AM8 [get_ports pcie_mgt_0_txp[8]]
set_property PACKAGE_PIN AM7 [get_ports pcie_mgt_0_txn[8]]

set_property PACKAGE_PIN AN6 [get_ports pcie_mgt_0_txp[9]]
set_property PACKAGE_PIN AN5 [get_ports pcie_mgt_0_txn[9]]

set_property PACKAGE_PIN AP8 [get_ports pcie_mgt_0_txp[10]]
set_property PACKAGE_PIN AP7 [get_ports pcie_mgt_0_txn[10]]

set_property PACKAGE_PIN AR6 [get_ports pcie_mgt_0_txp[11]]
set_property PACKAGE_PIN AR5 [get_ports pcie_mgt_0_txn[11]]

set_property PACKAGE_PIN AT8 [get_ports pcie_mgt_0_txp[12]]
set_property PACKAGE_PIN AT7 [get_ports pcie_mgt_0_txn[12]]

set_property PACKAGE_PIN AU6 [get_ports pcie_mgt_0_txp[13]]
set_property PACKAGE_PIN AU5 [get_ports pcie_mgt_0_txn[13]]

set_property PACKAGE_PIN AW6 [get_ports pcie_mgt_0_txp[14]]
set_property PACKAGE_PIN AW5 [get_ports pcie_mgt_0_txn[14]]

set_property PACKAGE_PIN AY4 [get_ports pcie_mgt_0_txp[15]]
set_property PACKAGE_PIN AY3 [get_ports pcie_mgt_0_txn[15]]

# =========================
# RX lanes
# =========================
set_property PACKAGE_PIN AF4 [get_ports pcie_mgt_0_rxp[0]]
set_property PACKAGE_PIN AF3 [get_ports pcie_mgt_0_rxn[0]]

set_property PACKAGE_PIN AE2 [get_ports pcie_mgt_0_rxp[1]]
set_property PACKAGE_PIN AE1 [get_ports pcie_mgt_0_rxn[1]]

set_property PACKAGE_PIN AG2 [get_ports pcie_mgt_0_rxp[2]]
set_property PACKAGE_PIN AG1 [get_ports pcie_mgt_0_rxn[2]]

set_property PACKAGE_PIN AH4 [get_ports pcie_mgt_0_rxp[3]]
set_property PACKAGE_PIN AH3 [get_ports pcie_mgt_0_rxn[3]]

set_property PACKAGE_PIN AJ2 [get_ports pcie_mgt_0_rxp[4]]
set_property PACKAGE_PIN AJ1 [get_ports pcie_mgt_0_rxn[4]]

set_property PACKAGE_PIN AK4 [get_ports pcie_mgt_0_rxp[5]]
set_property PACKAGE_PIN AK3 [get_ports pcie_mgt_0_rxn[5]]

set_property PACKAGE_PIN AL2 [get_ports pcie_mgt_0_rxp[6]]
set_property PACKAGE_PIN AL1 [get_ports pcie_mgt_0_rxn[6]]

set_property PACKAGE_PIN AM4 [get_ports pcie_mgt_0_rxp[7]]
set_property PACKAGE_PIN AM3 [get_ports pcie_mgt_0_rxn[7]]

set_property PACKAGE_PIN AN2 [get_ports pcie_mgt_0_rxp[8]]
set_property PACKAGE_PIN AN1 [get_ports pcie_mgt_0_rxn[8]]

set_property PACKAGE_PIN AP4 [get_ports pcie_mgt_0_rxp[9]]
set_property PACKAGE_PIN AP3 [get_ports pcie_mgt_0_rxn[9]]

set_property PACKAGE_PIN AR2 [get_ports pcie_mgt_0_rxp[10]]
set_property PACKAGE_PIN AR1 [get_ports pcie_mgt_0_rxn[10]]

set_property PACKAGE_PIN AT4 [get_ports pcie_mgt_0_rxp[11]]
set_property PACKAGE_PIN AT3 [get_ports pcie_mgt_0_rxn[11]]

set_property PACKAGE_PIN AU2 [get_ports pcie_mgt_0_rxp[12]]
set_property PACKAGE_PIN AU1 [get_ports pcie_mgt_0_rxn[12]]

set_property PACKAGE_PIN AV4 [get_ports pcie_mgt_0_rxp[13]]
set_property PACKAGE_PIN AV3 [get_ports pcie_mgt_0_rxn[13]]

set_property PACKAGE_PIN AW2 [get_ports pcie_mgt_0_rxp[14]]
set_property PACKAGE_PIN AW1 [get_ports pcie_mgt_0_rxn[14]]

set_property PACKAGE_PIN BA2 [get_ports pcie_mgt_0_rxp[15]]
set_property PACKAGE_PIN BA1 [get_ports pcie_mgt_0_rxn[15]]