
/*
----------------------------------------------------------------------------------
Copyright (c) 2013-2014

  Embedded and Network Computing Lab.
  Open SSD Project
  Hanyang University

All rights reserved.

----------------------------------------------------------------------------------

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  1. Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.

  2. Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.

  3. All advertising materials mentioning features or use of this source code
     must display the following acknowledgement:
     This product includes source code developed 
     by the Embedded and Network Computing Lab. and the Open SSD Project.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

----------------------------------------------------------------------------------

http://enclab.hanyang.ac.kr/
http://www.openssd-project.org/
http://www.hanyang.ac.kr/

----------------------------------------------------------------------------------
*/


`timescale 1ns / 1ps


module nvme_pcie # (
	parameter 	P_SLOT_TAG_WIDTH			=  10, //slot_modified
	parameter 	P_SLOT_WIDTH				= 1024, //slot_modified
	parameter	C_PCIE_DATA_WIDTH			= 512,
	parameter	C_PCIE_ADDR_WIDTH			= 48, //modified
	parameter	C_M_AXI_DATA_WIDTH			= 512,
	parameter	C_M_AXI_ADDR_WIDTH			= 64,
	parameter	P_SQE_DATA_WIDTH			= 128,
	parameter	P_PCIE_RX_MRD_MAX_BYTES	= 4096,
	parameter	P_PCIE_TX_MWR_MAX_BYTES	= 1024,

	parameter KEEP_WIDTH                                 = C_PCIE_DATA_WIDTH / 32, 
	parameter TCQ                                        = 1,

	parameter [1:0]  AXISTEN_IF_WIDTH               = (C_PCIE_DATA_WIDTH == 512) ? 2'b11:(C_PCIE_DATA_WIDTH == 256) ? 2'b10 : (C_PCIE_DATA_WIDTH == 128) ? 2'b01 : 2'b00, 

	parameter              AXI4_CQ_TUSER_WIDTH = 183,
	parameter              AXI4_CC_TUSER_WIDTH = 81,
	parameter              AXI4_RQ_TUSER_WIDTH = 137,
	parameter              AXI4_RC_TUSER_WIDTH = 161
)
(
//PCIe user clock
	input									pcie_user_clk,
	input									pcie_user_rst_n,

	output									dev_rx_cmd_wr_en,
	output	[C_M_AXI_ADDR_WIDTH-3:0]			dev_rx_cmd_wr_data,
	input									dev_rx_cmd_full_n,

	output									dev_tx_cmd_wr_en,
	output	[C_M_AXI_ADDR_WIDTH-3:0]			dev_tx_cmd_wr_data,
	input									dev_tx_cmd_full_n,

	input									cpu_bus_clk,
	input									cpu_bus_rst_n,

	output									bar2_reg_req,
	output									bar2_reg_wr,
	output	[17:0]									bar2_reg_addr,
	output	[31:0]									bar2_reg_wdata,
	output	[3:0]									bar2_reg_be,
	input									bar2_reg_ack,
	input	[31:0]									bar2_reg_rdata,
	input											bar2_pf0_msi_irq_req,
	input	[8:0]								bar2_pf0_msi_irq_vector,
	input											bar2_pf1_msi_irq_req,
	input	[8:0]								bar2_pf1_msi_irq_vector,

	output	[31:0]								cq_dbg_write_count,
	output	[31:0]								cq_dbg_last_dw2,
	output	[31:0]								cq_dbg_last_dw3,

	output									nvme_cc_en,
	output	[1:0]							nvme_cc_shn,

	input	[1:0]							nvme_csts_shst,
	input									nvme_csts_rdy,

	input	[8:0]							sq_rst_n,
	input	[8:0]							sq_valid,
	input	[7:0]							io_sq1_size,
	input	[7:0]							io_sq2_size,
	input	[7:0]							io_sq3_size,
	input	[7:0]							io_sq4_size,
	input	[7:0]							io_sq5_size,
	input	[7:0]							io_sq6_size,
	input	[7:0]							io_sq7_size,
	input	[7:0]							io_sq8_size,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq1_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq2_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq3_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq4_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq5_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq6_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq7_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_sq8_bs_addr,
	input	[3:0]							io_sq1_cq_vec,
	input	[3:0]							io_sq2_cq_vec,
	input	[3:0]							io_sq3_cq_vec,
	input	[3:0]							io_sq4_cq_vec,
	input	[3:0]							io_sq5_cq_vec,
	input	[3:0]							io_sq6_cq_vec,
	input	[3:0]							io_sq7_cq_vec,
	input	[3:0]							io_sq8_cq_vec,

	input	[8:0]							cq_rst_n,
	input	[8:0]							cq_valid,
	input	[7:0]							io_cq1_size,
	input	[7:0]							io_cq2_size,
	input	[7:0]							io_cq3_size,
	input	[7:0]							io_cq4_size,
	input	[7:0]							io_cq5_size,
	input	[7:0]							io_cq6_size,
	input	[7:0]							io_cq7_size,
	input	[7:0]							io_cq8_size,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq1_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq2_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq3_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq4_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq5_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq6_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq7_bs_addr,
	input	[C_PCIE_ADDR_WIDTH-1:2]			io_cq8_bs_addr,
	input	[8:0]							io_cq_irq_en,
	input	[31:0]							cq_irq_retry_cycles,
	input	[2:0]							io_cq1_iv,
	input	[2:0]							io_cq2_iv,
	input	[2:0]							io_cq3_iv,
	input	[2:0]							io_cq4_iv,
	input	[2:0]							io_cq5_iv,
	input	[2:0]							io_cq6_iv,
	input	[2:0]							io_cq7_iv,
	input	[2:0]							io_cq8_iv,

	input									hcmd_sq_rd_en,
	output	[(P_SLOT_TAG_WIDTH+12)-1:0]		hcmd_sq_rd_data, //slot_modified
	output									hcmd_sq_empty_n,

	input	[(P_SLOT_TAG_WIDTH+2)+1:0]		hcmd_table_rd_addr, //slot_modified
	output	[31:0]							hcmd_table_rd_data,
	output	[P_SQE_DATA_WIDTH-1:0]			hcmd_table_rd_data_sqe,

	input									hcmd_cq_wr1_en,
	input	[(P_SLOT_TAG_WIDTH+28)-1:0]		hcmd_cq_wr1_data0, //slot_modified
	input	[(P_SLOT_TAG_WIDTH+28)-1:0]		hcmd_cq_wr1_data1, //slot_modified
	output									hcmd_cq_wr1_rdy_n,

	input									dma_cmd_wr_en,
	input	[C_M_AXI_ADDR_WIDTH+23:0]			dma_cmd_wr_data0, //modified
	input	[C_M_AXI_ADDR_WIDTH+23:0]			dma_cmd_wr_data1, //modified
	output									dma_cmd_wr_rdy_n,

	input									model_cmd_wr_en,
	input	[63:0]						model_cmd_wr_data0,
	input	[63:0]						model_cmd_wr_data1,
	output									model_cmd_wr_rdy_n,
	input									ssd_model_enable,
	input									ssd_model_reset,
	input	[31:0]						ssd_read_lsb_cycles,
	input	[31:0]						ssd_read_msb_cycles,
	input	[31:0]						ssd_program_cycles,
	input	[31:0]						ssd_fw_read_cycles,
	input	[31:0]						ssd_fw_write_cycles,
	input	[31:0]						ssd_ch_xfer_4k_cycles,
	input	[4:0]						ssd_channel_count,
	output	[31:0]						ssd_model_status,
	output	[31:0]						ssd_model_submit_count,
	output	[31:0]						ssd_model_release_count,

	output	[7:0]							dma_rx_direct_done_cnt,
	output	[7:0]							dma_tx_direct_done_cnt,
	output	[7:0]							dma_rx_done_cnt,
	output	[7:0]							dma_tx_done_cnt,

	input									dma_bus_clk,
	input									dma_bus_rst_n,

	input									pcie_rx_fifo_rd_en,
	output	[C_M_AXI_DATA_WIDTH-1:0]		pcie_rx_fifo_rd_data,
	input									pcie_rx_fifo_free_en,
	input	[12:6]							pcie_rx_fifo_free_len, 
	output									pcie_rx_fifo_empty_n,

	input									pcie_tx_fifo_alloc_en,
	input	[10:6]							pcie_tx_fifo_alloc_len, 
	input									pcie_tx_fifo_wr_en,
	input	[C_M_AXI_DATA_WIDTH-1:0]		pcie_tx_fifo_wr_data,
	output									pcie_tx_fifo_full_n,

	input									dma_rx_done_wr_en,
	input	[(P_SLOT_TAG_WIDTH+15)-1:0]		dma_rx_done_wr_data, //slot_modified
	output									dma_rx_done_wr_rdy_n,

	output									pcie_mreq_err,
	output									pcie_cpld_err,
	output									pcie_cpld_len_err,

  
	// AXI-S Completer Competion Interface
	output wire   [C_PCIE_DATA_WIDTH-1:0]   s_axis_cc_tdata,
	output wire          [KEEP_WIDTH-1:0]   s_axis_cc_tkeep,
	output wire                             s_axis_cc_tlast,
	output wire                             s_axis_cc_tvalid,
	output wire [AXI4_CC_TUSER_WIDTH-1:0]   s_axis_cc_tuser,
	input                                   s_axis_cc_tready,

	// AXI-S Requester Request Interface
	output wire   [C_PCIE_DATA_WIDTH-1:0]   s_axis_rq_tdata,
	output wire          [KEEP_WIDTH-1:0]   s_axis_rq_tkeep,
	output wire                             s_axis_rq_tlast,
	output wire                             s_axis_rq_tvalid,
	output wire [AXI4_RQ_TUSER_WIDTH-1:0]   s_axis_rq_tuser,
	input                                   s_axis_rq_tready,

	// TX Message Interface
	input                            cfg_msg_transmit_done,
	output                       cfg_msg_transmit,
	output               [2:0]   cfg_msg_transmit_type,
	output              [31:0]   cfg_msg_transmit_data,

	//Tag availability and Flow control Information
	input                    [5:0]   pcie_rq_tag,
	input                            pcie_rq_tag_vld,
	input                    [1:0]   pcie_tfc_nph_av,
	input                    [1:0]   pcie_tfc_npd_av,
	input                            pcie_tfc_np_pl_empty,
	input                    [3:0]   pcie_rq_seq_num,
	input                            pcie_rq_seq_num_vld,

	//Cfg Flow Control Information  
	input	[11:0]							fc_cpld,
	input	[7:0]							fc_cplh,
	input	[11:0]							fc_npd,
	input	[7:0]							fc_nph,
	input	[11:0]							fc_pd,
	input	[7:0]							fc_ph,
	output	[2:0]							fc_sel,

	//PIO RX Engine

	// Completer Request Interface
	input   [C_PCIE_DATA_WIDTH-1:0]   m_axis_cq_tdata,
	input                             m_axis_cq_tlast,
	input                             m_axis_cq_tvalid,
	input [AXI4_CQ_TUSER_WIDTH-1:0]   m_axis_cq_tuser,
	input          [KEEP_WIDTH-1:0]   m_axis_cq_tkeep,
	output                            m_axis_cq_tready,

	// Requester Completion Interface
	input   [C_PCIE_DATA_WIDTH-1:0]   m_axis_rc_tdata,
	input                             m_axis_rc_tlast,
	input                             m_axis_rc_tvalid,
	input [AXI4_RC_TUSER_WIDTH-1:0]   m_axis_rc_tuser,
	input          [KEEP_WIDTH-1:0]   m_axis_rc_tkeep,
	output                            m_axis_rc_tready,

	input                     [5:0]   pcie_cq_np_req_count,
	output                            pcie_cq_np_req,

	//RX Message Interface
	input                            cfg_msg_received,
	input                    [4:0]   cfg_msg_received_type,
	input                    [7:0]   cfg_msg_data,

	// Legacy Interrupt Interface
	input                            cfg_interrupt_sent, // Core asserts this signal when it sends out a Legacy interrupt 
	output wire                      cfg_interrupt_pending,
	output wire              [3:0]   cfg_interrupt_int,  // 4 Bits for INTA, INTB, INTC, INTD (assert or deassert)

	// MSI Interrupt Interface
	input                    [3:0]   cfg_interrupt_msi_enable,
	input                            cfg_interrupt_msi_sent,
	input                            cfg_interrupt_msi_fail,
	output wire             [31:0]   cfg_interrupt_msi_int,
	output wire                      cfg_interrupt_msi_pending_status_data_enable,
	output wire             [31:0]   cfg_interrupt_msi_pending_status,
		output wire             [7:0]    cfg_interrupt_msi_function_number,
  
	//MSI-X Interrupt Interface
	input                            cfg_interrupt_msix_enable,
	input                            cfg_interrupt_msix_sent,
	input                            cfg_interrupt_msix_fail,
	output wire                      cfg_interrupt_msix_int,
	output wire             [63:0]   cfg_interrupt_msix_address,
	output wire             [31:0]   cfg_interrupt_msix_data,

	input                            cfg_power_state_change_interrupt, 
	output reg                       cfg_power_state_change_ack, 

	input	[3:0]					 cfg_command,
 	input                  [1:0]     cfg_max_payload,
	input                  [2:0]     cfg_max_read_req,
	input                            cfg_rcb_status
);

wire										w_nvme_intms_ivms;
wire										w_nvme_intmc_ivmc;
wire										w_cq_irq_status;

wire	[(P_SLOT_TAG_WIDTH+1)-1:0]			w_hcmd_prp_rd_addr;//slot_modified
wire	[53:0]								w_hcmd_prp_rd_data; //modified

wire										w_hcmd_nlb_wr1_en;
wire	[P_SLOT_TAG_WIDTH-1:0]				w_hcmd_nlb_wr1_addr; //slot_modified
wire	[18:0]								w_hcmd_nlb_wr1_data;
wire										w_hcmd_nlb_wr1_rdy_n;

wire	[P_SLOT_TAG_WIDTH-1:0]				w_hcmd_nlb_rd_addr; //slot_modified
wire	[18:0]								w_hcmd_nlb_rd_data;

wire										w_hcmd_cq_wr0_en;
wire	[(P_SLOT_TAG_WIDTH+28)-1:0]			w_hcmd_cq_wr0_data0; //slot_modified
wire	[(P_SLOT_TAG_WIDTH+28)-1:0]			w_hcmd_cq_wr0_data1; //slot_modified
wire										w_hcmd_cq_wr0_rdy_n;
wire									w_dma_hcmd_cq_wr0_en;
wire	[(P_SLOT_TAG_WIDTH+28)-1:0]		w_dma_hcmd_cq_wr0_data0;
wire	[(P_SLOT_TAG_WIDTH+28)-1:0]		w_dma_hcmd_cq_wr0_data1;
wire									w_dma_hcmd_cq_wr0_rdy_n;

wire										w_mreq_fifo_wr_en;
wire	[C_PCIE_DATA_WIDTH-1:0]				w_mreq_fifo_wr_data;

wire	[7:0]								w_cpld0_fifo_tag;
wire										w_cpld0_fifo_tag_last;
wire										w_cpld0_fifo_wr_en;
wire	[C_PCIE_DATA_WIDTH-1:0]				w_cpld0_fifo_wr_data;

wire	[7:0]								w_cpld1_fifo_tag;
wire										w_cpld1_fifo_tag_last;
wire										w_cpld1_fifo_wr_en;
wire	[C_PCIE_DATA_WIDTH-1:0]				w_cpld1_fifo_wr_data;

wire	[7:0]								w_cpld2_fifo_tag;
wire										w_cpld2_fifo_tag_last;
wire										w_cpld2_fifo_wr_en;
wire	[C_PCIE_DATA_WIDTH-1:0]				w_cpld2_fifo_wr_data;

wire										w_tx_cpld_req;
wire	[7:0]								w_tx_cpld_tag;
wire	[15:0]								w_tx_cpld_req_id;
wire	[12:2]								w_tx_cpld_len;
wire	[6:0]								w_tx_cpld_laddr;
wire	[63:0]								w_tx_cpld_data;
wire	[2:0]                               w_tx_cpld_tc;             // Memory Read TC
wire    [2:0]                               w_tx_cpld_attr;           // Memory Read Attribute
wire    [1:0]                               w_tx_cpld_at;             // Address Translation 
wire    [7:0]                               w_tx_cpld_be;
wire										w_tx_cpld_req_ack;

wire										w_tx_mrd0_req;
wire	[7:0]								w_tx_mrd0_tag;
wire	[12:2]								w_tx_mrd0_len;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_tx_mrd0_addr;
wire										w_tx_mrd0_req_ack;

wire										w_tx_mrd1_req;
wire	[7:0]								w_tx_mrd1_tag;
wire	[12:2]								w_tx_mrd1_len;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_tx_mrd1_addr;
wire										w_tx_mrd1_req_ack;

wire										w_tx_mrd2_req;
wire	[7:0]								w_tx_mrd2_tag;
wire	[12:2]								w_tx_mrd2_len;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_tx_mrd2_addr;
wire										w_tx_mrd2_req_ack;

wire										w_tx_mwr0_req;
wire	[7:0]								w_tx_mwr0_tag;
wire	[12:2]								w_tx_mwr0_len;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_tx_mwr0_addr;
wire										w_tx_mwr0_req_ack;
wire										w_tx_mwr0_rd_en;
wire	[C_PCIE_DATA_WIDTH-1 : 0]			w_tx_mwr0_rd_data;
wire										w_tx_mwr0_data_last;

wire										w_tx_mwr1_req;
wire	[7:0]								w_tx_mwr1_tag;
wire	[12:2]								w_tx_mwr1_len;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_tx_mwr1_addr;
wire										w_tx_mwr1_req_ack;
wire										w_tx_mwr1_rd_en;
wire	[C_PCIE_DATA_WIDTH-1:0]				w_tx_mwr1_rd_data;
wire										w_tx_mwr1_data_last;

wire	[C_PCIE_ADDR_WIDTH-1:2]				w_admin_sq_bs_addr;
wire	[C_PCIE_ADDR_WIDTH-1:2]				w_admin_cq_bs_addr;
wire	[7:0]								w_admin_sq_size;
wire	[7:0]								w_admin_cq_size;

wire	[7:0]								w_admin_sq_tail_ptr;
wire	[7:0]								w_io_sq1_tail_ptr;
wire	[7:0]								w_io_sq2_tail_ptr;
wire	[7:0]								w_io_sq3_tail_ptr;
wire	[7:0]								w_io_sq4_tail_ptr;
wire	[7:0]								w_io_sq5_tail_ptr;
wire	[7:0]								w_io_sq6_tail_ptr;
wire	[7:0]								w_io_sq7_tail_ptr;
wire	[7:0]								w_io_sq8_tail_ptr;

wire	[7:0]								w_admin_cq_tail_ptr;
wire	[7:0]								w_io_cq1_tail_ptr;
wire	[7:0]								w_io_cq2_tail_ptr;
wire	[7:0]								w_io_cq3_tail_ptr;
wire	[7:0]								w_io_cq4_tail_ptr;
wire	[7:0]								w_io_cq5_tail_ptr;
wire	[7:0]								w_io_cq6_tail_ptr;
wire	[7:0]								w_io_cq7_tail_ptr;
wire	[7:0]								w_io_cq8_tail_ptr;

wire	[7:0]								w_admin_cq_head_ptr;
wire	[7:0]								w_io_cq1_head_ptr;
wire	[7:0]								w_io_cq2_head_ptr;
wire	[7:0]								w_io_cq3_head_ptr;
wire	[7:0]								w_io_cq4_head_ptr;
wire	[7:0]								w_io_cq5_head_ptr;
wire	[7:0]								w_io_cq6_head_ptr;
wire	[7:0]								w_io_cq7_head_ptr;
wire	[7:0]								w_io_cq8_head_ptr;
wire	[8:0]								w_cq_head_update;

wire    [7:0]                               w_req_be;
wire										w_bar2_mreq_fifo_wr_en;
wire	[C_PCIE_DATA_WIDTH-1:0]			w_bar2_mreq_fifo_wr_data;
wire    [7:0]                               w_bar2_req_be;

wire										w_bar0_tx_cpld_req_ack;
wire										w_bar2_tx_cpld_req;
wire	[7:0]							w_bar2_tx_cpld_tag;
wire	[15:0]							w_bar2_tx_cpld_req_id;
wire	[12:2]							w_bar2_tx_cpld_len;
wire	[6:0]							w_bar2_tx_cpld_laddr;
wire	[63:0]							w_bar2_tx_cpld_data;
wire	[2:0]                               w_bar2_tx_cpld_tc;
wire    [2:0]                               w_bar2_tx_cpld_attr;
wire    [1:0]                               w_bar2_tx_cpld_at;
wire    [7:0]                               w_bar2_tx_cpld_be;
wire    [7:0]                               w_bar2_tx_cpld_func_num;
wire										w_bar2_tx_cpld_req_ack;


reg										r_tx_cpld_mux_valid;
reg										r_tx_cpld_mux_bar2;
reg										r_tx_cpld_bar0_pending;
reg										r_tx_cpld_bar2_pending;

wire										w_tx_cpld_mux_start;
wire										w_tx_cpld_mux_start_bar2;
wire										w_tx_cpld_mux_bar2;
wire	w_nvme_cmd_rst_n;
wire										w_mux_tx_cpld_req;
wire	[7:0]							w_mux_tx_cpld_tag;
wire	[15:0]							w_mux_tx_cpld_req_id;
wire	[12:2]							w_mux_tx_cpld_len;
wire	[6:0]							w_mux_tx_cpld_laddr;
wire	[63:0]							w_mux_tx_cpld_data;
wire	[2:0]                               w_mux_tx_cpld_tc;
wire    [2:0]                               w_mux_tx_cpld_attr;
wire    [1:0]                               w_mux_tx_cpld_at;
wire    [7:0]                               w_mux_tx_cpld_be;
wire    [7:0]                               w_mux_tx_cpld_func_num;

always @ (posedge pcie_user_clk) begin 
	if(!pcie_user_rst_n ) begin 
		cfg_power_state_change_ack <= 1'b0;
	end 
	else begin 
		if ( cfg_power_state_change_interrupt ) 
			cfg_power_state_change_ack <= 1'b1; 
		else 
			cfg_power_state_change_ack <= 1'b0; 
	end 
end 


assign w_tx_cpld_mux_start_bar2 = ~(r_tx_cpld_bar0_pending | w_tx_cpld_req) &
								(r_tx_cpld_bar2_pending | w_bar2_tx_cpld_req);
assign w_tx_cpld_mux_start = ~r_tx_cpld_mux_valid &
							((r_tx_cpld_bar0_pending | w_tx_cpld_req) |
							 (r_tx_cpld_bar2_pending | w_bar2_tx_cpld_req));
assign w_tx_cpld_mux_bar2 = (r_tx_cpld_mux_valid == 1) ? r_tx_cpld_mux_bar2 : w_tx_cpld_mux_start_bar2;
assign w_mux_tx_cpld_req = w_tx_cpld_mux_start;

assign w_mux_tx_cpld_tag = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_tag : w_tx_cpld_tag;
assign w_mux_tx_cpld_req_id = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_req_id : w_tx_cpld_req_id;
assign w_mux_tx_cpld_len = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_len : w_tx_cpld_len;
assign w_mux_tx_cpld_laddr = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_laddr : w_tx_cpld_laddr;
assign w_mux_tx_cpld_data = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_data : w_tx_cpld_data;
assign w_mux_tx_cpld_tc = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_tc : w_tx_cpld_tc;
assign w_mux_tx_cpld_attr = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_attr : w_tx_cpld_attr;
assign w_mux_tx_cpld_at = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_at : w_tx_cpld_at;
assign w_mux_tx_cpld_be = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_be : w_tx_cpld_be;
assign w_mux_tx_cpld_func_num = w_tx_cpld_mux_bar2 ? w_bar2_tx_cpld_func_num : 8'h00;
// Flush NVMe command-path queues across host controller reset epochs.
assign w_nvme_cmd_rst_n = pcie_user_rst_n & nvme_cc_en;

assign w_bar0_tx_cpld_req_ack = r_tx_cpld_mux_valid & ~r_tx_cpld_mux_bar2 & w_tx_cpld_req_ack;
assign w_bar2_tx_cpld_req_ack = r_tx_cpld_mux_valid & r_tx_cpld_mux_bar2 & w_tx_cpld_req_ack;

always @ (posedge pcie_user_clk or negedge pcie_user_rst_n)
begin
	if(pcie_user_rst_n == 0) begin
		r_tx_cpld_mux_valid <= 0;
		r_tx_cpld_mux_bar2 <= 0;
		r_tx_cpld_bar0_pending <= 0;
		r_tx_cpld_bar2_pending <= 0;
	end
	else begin
		if(w_tx_cpld_req == 1 && !(r_tx_cpld_mux_valid == 1 && r_tx_cpld_mux_bar2 == 0))
			r_tx_cpld_bar0_pending <= 1;
		if(w_bar2_tx_cpld_req == 1 && !(r_tx_cpld_mux_valid == 1 && r_tx_cpld_mux_bar2 == 1))
			r_tx_cpld_bar2_pending <= 1;

		if(r_tx_cpld_mux_valid == 0 && w_tx_cpld_mux_start == 1) begin
			r_tx_cpld_mux_valid <= 1;
			r_tx_cpld_mux_bar2 <= w_tx_cpld_mux_start_bar2;
			if(w_tx_cpld_mux_start_bar2 == 1)
				r_tx_cpld_bar2_pending <= 0;
			else
				r_tx_cpld_bar0_pending <= 0;
		end
		else if(r_tx_cpld_mux_valid == 1 && w_tx_cpld_req_ack == 1) begin
			r_tx_cpld_mux_valid <= 0;
		end
	end
end
pcie_cntl_slave # (
	.C_PCIE_DATA_WIDTH						(C_PCIE_DATA_WIDTH)
)
pcie_cntl_slave_inst0(

	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(pcie_user_rst_n),

	.mreq_fifo_wr_en						(w_mreq_fifo_wr_en),
	.mreq_fifo_wr_data						(w_mreq_fifo_wr_data),

	.req_be                                 (w_req_be),

	.tx_cpld_req							(w_tx_cpld_req),
	.tx_cpld_tag							(w_tx_cpld_tag),
	.tx_cpld_req_id							(w_tx_cpld_req_id),
	.tx_cpld_len							(w_tx_cpld_len),
	.tx_cpld_laddr							(w_tx_cpld_laddr),
	.tx_cpld_data							(w_tx_cpld_data),
	.tx_cpld_tc						     	(w_tx_cpld_tc),
	.tx_cpld_attr							(w_tx_cpld_attr),
	.tx_cpld_at							    (w_tx_cpld_at),
	.tx_cpld_be							    (w_tx_cpld_be),
	.tx_cpld_req_ack						(w_bar0_tx_cpld_req_ack),

	.nvme_cc_en								(nvme_cc_en),
	.nvme_cc_shn							(nvme_cc_shn),

	.nvme_csts_shst							(nvme_csts_shst),
	.nvme_csts_rdy							(nvme_csts_rdy),

	.nvme_intms_ivms						(w_nvme_intms_ivms),
	.nvme_intmc_ivmc						(w_nvme_intmc_ivmc),
	.cq_irq_status							(w_cq_irq_status),

	.sq_rst_n								(sq_rst_n),
	.cq_rst_n								(cq_rst_n),
	.admin_sq_bs_addr						(w_admin_sq_bs_addr),
	.admin_cq_bs_addr						(w_admin_cq_bs_addr),
	.admin_sq_size							(w_admin_sq_size),
	.admin_cq_size							(w_admin_cq_size),

	.admin_sq_tail_ptr						(w_admin_sq_tail_ptr),
	.io_sq1_tail_ptr						(w_io_sq1_tail_ptr),
	.io_sq2_tail_ptr						(w_io_sq2_tail_ptr),
	.io_sq3_tail_ptr						(w_io_sq3_tail_ptr),
	.io_sq4_tail_ptr						(w_io_sq4_tail_ptr),
	.io_sq5_tail_ptr						(w_io_sq5_tail_ptr),
	.io_sq6_tail_ptr						(w_io_sq6_tail_ptr),
	.io_sq7_tail_ptr						(w_io_sq7_tail_ptr),
	.io_sq8_tail_ptr						(w_io_sq8_tail_ptr),

	.admin_cq_head_ptr						(w_admin_cq_head_ptr),
	.io_cq1_head_ptr						(w_io_cq1_head_ptr),
	.io_cq2_head_ptr						(w_io_cq2_head_ptr),
	.io_cq3_head_ptr						(w_io_cq3_head_ptr),
	.io_cq4_head_ptr						(w_io_cq4_head_ptr),
	.io_cq5_head_ptr						(w_io_cq5_head_ptr),
	.io_cq6_head_ptr						(w_io_cq6_head_ptr),
	.io_cq7_head_ptr						(w_io_cq7_head_ptr),
	.io_cq8_head_ptr						(w_io_cq8_head_ptr),
	.cq_head_update							(w_cq_head_update)
);


pcie_bar2_stream #(
	.C_PCIE_DATA_WIDTH						(C_PCIE_DATA_WIDTH)
)
pcie_bar2_stream_inst0(
	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(pcie_user_rst_n),

	.mreq_fifo_wr_en						(w_bar2_mreq_fifo_wr_en),
	.mreq_fifo_wr_data					(w_bar2_mreq_fifo_wr_data),
	.req_be                                (w_bar2_req_be),

	.tx_cpld_req							(w_bar2_tx_cpld_req),
	.tx_cpld_tag							(w_bar2_tx_cpld_tag),
	.tx_cpld_req_id						(w_bar2_tx_cpld_req_id),
	.tx_cpld_len							(w_bar2_tx_cpld_len),
	.tx_cpld_laddr						(w_bar2_tx_cpld_laddr),
	.tx_cpld_data						(w_bar2_tx_cpld_data),
	.tx_cpld_tc							(w_bar2_tx_cpld_tc),
	.tx_cpld_attr						(w_bar2_tx_cpld_attr),
	.tx_cpld_at							(w_bar2_tx_cpld_at),
	.tx_cpld_be							(w_bar2_tx_cpld_be),
		.tx_cpld_func_num					(w_bar2_tx_cpld_func_num),
	.tx_cpld_req_ack					(w_bar2_tx_cpld_req_ack),

	.bar2_reg_req						(bar2_reg_req),
	.bar2_reg_wr						(bar2_reg_wr),
	.bar2_reg_addr						(bar2_reg_addr),
	.bar2_reg_wdata					(bar2_reg_wdata),
	.bar2_reg_be						(bar2_reg_be),
	.bar2_reg_ack						(bar2_reg_ack),
	.bar2_reg_rdata					(bar2_reg_rdata)
);
nvme_ssd_latency #(
	.P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
	.P_CQ_DATA_WIDTH(P_SLOT_TAG_WIDTH + 28)
)
nvme_ssd_latency_inst0 (
	.cpu_bus_clk(cpu_bus_clk),
	.cpu_bus_rst_n(cpu_bus_rst_n),
	.model_cmd_wr_en(model_cmd_wr_en),
	.model_cmd_wr_data0(model_cmd_wr_data0),
	.model_cmd_wr_data1(model_cmd_wr_data1),
	.model_cmd_wr_rdy_n(model_cmd_wr_rdy_n),

	.pcie_user_clk(pcie_user_clk),
	.pcie_user_rst_n(w_nvme_cmd_rst_n),
	.model_enable(ssd_model_enable),
	.model_reset(ssd_model_reset),
	.read_lsb_cycles(ssd_read_lsb_cycles),
	.read_msb_cycles(ssd_read_msb_cycles),
	.program_cycles(ssd_program_cycles),
	.fw_read_cycles(ssd_fw_read_cycles),
	.fw_write_cycles(ssd_fw_write_cycles),
	.ch_xfer_4k_cycles(ssd_ch_xfer_4k_cycles),
	.channel_count(ssd_channel_count),

	.in_cq_wr_en(w_dma_hcmd_cq_wr0_en),
	.in_cq_wr_data0(w_dma_hcmd_cq_wr0_data0),
	.in_cq_wr_data1(w_dma_hcmd_cq_wr0_data1),
	.in_cq_wr_rdy_n(w_dma_hcmd_cq_wr0_rdy_n),
	.out_cq_wr_en(w_hcmd_cq_wr0_en),
	.out_cq_wr_data0(w_hcmd_cq_wr0_data0),
	.out_cq_wr_data1(w_hcmd_cq_wr0_data1),
	.out_cq_wr_rdy_n(w_hcmd_cq_wr0_rdy_n),

	.model_status(ssd_model_status),
	.model_submit_count(ssd_model_submit_count),
	.model_release_count(ssd_model_release_count)
);

pcie_hcmd # (
	.P_SLOT_TAG_WIDTH						(P_SLOT_TAG_WIDTH), //slot_modified
	.P_SLOT_WIDTH							(P_SLOT_WIDTH), //slot_modified
	.C_PCIE_DATA_WIDTH						(C_PCIE_DATA_WIDTH),
	.P_SQE_DATA_WIDTH						(P_SQE_DATA_WIDTH)
)
pcie_hcmd_inst0(
	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(w_nvme_cmd_rst_n),

	.admin_sq_bs_addr						(w_admin_sq_bs_addr),
	.admin_cq_bs_addr						(w_admin_cq_bs_addr),
	.admin_sq_size							(w_admin_sq_size),
	.admin_cq_size							(w_admin_cq_size),

	.admin_sq_tail_ptr						(w_admin_sq_tail_ptr),
	.io_sq1_tail_ptr						(w_io_sq1_tail_ptr),
	.io_sq2_tail_ptr						(w_io_sq2_tail_ptr),
	.io_sq3_tail_ptr						(w_io_sq3_tail_ptr),
	.io_sq4_tail_ptr						(w_io_sq4_tail_ptr),
	.io_sq5_tail_ptr						(w_io_sq5_tail_ptr),
	.io_sq6_tail_ptr						(w_io_sq6_tail_ptr),
	.io_sq7_tail_ptr						(w_io_sq7_tail_ptr),
	.io_sq8_tail_ptr						(w_io_sq8_tail_ptr),

	.cpld_sq_fifo_tag						(w_cpld0_fifo_tag),
	.cpld_sq_fifo_wr_data					(w_cpld0_fifo_wr_data),
	.cpld_sq_fifo_wr_en						(w_cpld0_fifo_wr_en),
	.cpld_sq_fifo_tag_last					(w_cpld0_fifo_tag_last),


	.tx_mrd_req								(w_tx_mrd0_req),
	.tx_mrd_tag								(w_tx_mrd0_tag),
	.tx_mrd_len								(w_tx_mrd0_len),
	.tx_mrd_addr							(w_tx_mrd0_addr),
	.tx_mrd_req_ack							(w_tx_mrd0_req_ack),

	.admin_cq_tail_ptr						(w_admin_cq_tail_ptr),
	.io_cq1_tail_ptr						(w_io_cq1_tail_ptr),
	.io_cq2_tail_ptr						(w_io_cq2_tail_ptr),
	.io_cq3_tail_ptr						(w_io_cq3_tail_ptr),
	.io_cq4_tail_ptr						(w_io_cq4_tail_ptr),
	.io_cq5_tail_ptr						(w_io_cq5_tail_ptr),
	.io_cq6_tail_ptr						(w_io_cq6_tail_ptr),
	.io_cq7_tail_ptr						(w_io_cq7_tail_ptr),
	.io_cq8_tail_ptr						(w_io_cq8_tail_ptr),

	.tx_cq_mwr_req							(w_tx_mwr0_req),
	.tx_cq_mwr_tag							(w_tx_mwr0_tag),
	.tx_cq_mwr_len							(w_tx_mwr0_len),
	.tx_cq_mwr_addr							(w_tx_mwr0_addr),
	.tx_cq_mwr_req_ack						(w_tx_mwr0_req_ack),
	.tx_cq_mwr_rd_en						(w_tx_mwr0_rd_en),
	.tx_cq_mwr_rd_data						(w_tx_mwr0_rd_data),
	.tx_cq_mwr_data_last					(w_tx_mwr0_data_last),

	.hcmd_prp_rd_addr						(w_hcmd_prp_rd_addr),
	.hcmd_prp_rd_data						(w_hcmd_prp_rd_data),

	.hcmd_nlb_wr1_en						(w_hcmd_nlb_wr1_en),
	.hcmd_nlb_wr1_addr						(w_hcmd_nlb_wr1_addr),
	.hcmd_nlb_wr1_data						(w_hcmd_nlb_wr1_data),
	.hcmd_nlb_wr1_rdy_n						(w_hcmd_nlb_wr1_rdy_n),

	.hcmd_nlb_rd_addr						(w_hcmd_nlb_rd_addr),
	.hcmd_nlb_rd_data						(w_hcmd_nlb_rd_data),

	.hcmd_cq_wr0_en							(w_hcmd_cq_wr0_en),
	.hcmd_cq_wr0_data0						(w_hcmd_cq_wr0_data0),
	.hcmd_cq_wr0_data1						(w_hcmd_cq_wr0_data1),
	.hcmd_cq_wr0_rdy_n						(w_hcmd_cq_wr0_rdy_n),

	.cpu_bus_clk							(cpu_bus_clk),
	.cpu_bus_rst_n							(cpu_bus_rst_n),

	.sq_rst_n								(sq_rst_n),
	.sq_valid								(sq_valid),
	.io_sq1_size							(io_sq1_size),
	.io_sq2_size							(io_sq2_size),
	.io_sq3_size							(io_sq3_size),
	.io_sq4_size							(io_sq4_size),
	.io_sq5_size							(io_sq5_size),
	.io_sq6_size							(io_sq6_size),
	.io_sq7_size							(io_sq7_size),
	.io_sq8_size							(io_sq8_size),
	.io_sq1_bs_addr							(io_sq1_bs_addr),
	.io_sq2_bs_addr							(io_sq2_bs_addr),
	.io_sq3_bs_addr							(io_sq3_bs_addr),
	.io_sq4_bs_addr							(io_sq4_bs_addr),
	.io_sq5_bs_addr							(io_sq5_bs_addr),
	.io_sq6_bs_addr							(io_sq6_bs_addr),
	.io_sq7_bs_addr							(io_sq7_bs_addr),
	.io_sq8_bs_addr							(io_sq8_bs_addr),
	.io_sq1_cq_vec							(io_sq1_cq_vec),
	.io_sq2_cq_vec							(io_sq2_cq_vec),
	.io_sq3_cq_vec							(io_sq3_cq_vec),
	.io_sq4_cq_vec							(io_sq4_cq_vec),
	.io_sq5_cq_vec							(io_sq5_cq_vec),
	.io_sq6_cq_vec							(io_sq6_cq_vec),
	.io_sq7_cq_vec							(io_sq7_cq_vec),
	.io_sq8_cq_vec							(io_sq8_cq_vec),

	.cq_rst_n								(cq_rst_n),
	.cq_valid								(cq_valid),
	.io_cq1_size							(io_cq1_size),
	.io_cq2_size							(io_cq2_size),
	.io_cq3_size							(io_cq3_size),
	.io_cq4_size							(io_cq4_size),
	.io_cq5_size							(io_cq5_size),
	.io_cq6_size							(io_cq6_size),
	.io_cq7_size							(io_cq7_size),
	.io_cq8_size							(io_cq8_size),
	.io_cq1_bs_addr							(io_cq1_bs_addr),
	.io_cq2_bs_addr							(io_cq2_bs_addr),
	.io_cq3_bs_addr							(io_cq3_bs_addr),
	.io_cq4_bs_addr							(io_cq4_bs_addr),
	.io_cq5_bs_addr							(io_cq5_bs_addr),
	.io_cq6_bs_addr							(io_cq6_bs_addr),
	.io_cq7_bs_addr							(io_cq7_bs_addr),
	.io_cq8_bs_addr							(io_cq8_bs_addr),

	.hcmd_sq_rd_en							(hcmd_sq_rd_en),
	.hcmd_sq_rd_data						(hcmd_sq_rd_data),
	.hcmd_sq_empty_n						(hcmd_sq_empty_n),

	.hcmd_table_rd_addr						(hcmd_table_rd_addr),
	.hcmd_table_rd_data						(hcmd_table_rd_data),
	.hcmd_table_rd_data_sqe					(hcmd_table_rd_data_sqe),

	.hcmd_cq_wr1_en							(hcmd_cq_wr1_en),
	.hcmd_cq_wr1_data0						(hcmd_cq_wr1_data0),
	.hcmd_cq_wr1_data1						(hcmd_cq_wr1_data1),
	.hcmd_cq_wr1_rdy_n						(hcmd_cq_wr1_rdy_n),

	.cq_dbg_write_count						(cq_dbg_write_count),
	.cq_dbg_last_dw2						(cq_dbg_last_dw2),
	.cq_dbg_last_dw3						(cq_dbg_last_dw3)
);


dma_if # (
	.P_SLOT_TAG_WIDTH						(P_SLOT_TAG_WIDTH), //slot_modified
	.C_M_AXI_ADDR_WIDTH				(C_M_AXI_ADDR_WIDTH),
	.P_PCIE_RX_MRD_MAX_BYTES		(P_PCIE_RX_MRD_MAX_BYTES),
	.P_PCIE_TX_MWR_MAX_BYTES		(P_PCIE_TX_MWR_MAX_BYTES)
)
dma_if_inst0
(
	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(w_nvme_cmd_rst_n),

	.pcie_max_payload_size					(cfg_max_payload),
	.pcie_max_read_req_size					(cfg_max_read_req),
	.pcie_rcb								(cfg_rcb_status),

	.hcmd_prp_rd_addr						(w_hcmd_prp_rd_addr),
	.hcmd_prp_rd_data						(w_hcmd_prp_rd_data),

	.hcmd_nlb_wr1_en						(w_hcmd_nlb_wr1_en),
	.hcmd_nlb_wr1_addr						(w_hcmd_nlb_wr1_addr),
	.hcmd_nlb_wr1_data						(w_hcmd_nlb_wr1_data),
	.hcmd_nlb_wr1_rdy_n						(w_hcmd_nlb_wr1_rdy_n),

	.hcmd_nlb_rd_addr						(w_hcmd_nlb_rd_addr),
	.hcmd_nlb_rd_data						(w_hcmd_nlb_rd_data),

	.dev_rx_cmd_wr_en						(dev_rx_cmd_wr_en),
	.dev_rx_cmd_wr_data						(dev_rx_cmd_wr_data),
	.dev_rx_cmd_full_n						(dev_rx_cmd_full_n),

	.dev_tx_cmd_wr_en						(dev_tx_cmd_wr_en),
	.dev_tx_cmd_wr_data						(dev_tx_cmd_wr_data),
	.dev_tx_cmd_full_n						(dev_tx_cmd_full_n),

	.tx_prp_mrd_req							(w_tx_mrd1_req),
	.tx_prp_mrd_tag							(w_tx_mrd1_tag),
	.tx_prp_mrd_len							(w_tx_mrd1_len),
	.tx_prp_mrd_addr						(w_tx_mrd1_addr),
	.tx_prp_mrd_req_ack						(w_tx_mrd1_req_ack),

	.cpld_prp_fifo_tag						(w_cpld1_fifo_tag),
	.cpld_prp_fifo_wr_data					(w_cpld1_fifo_wr_data),
	.cpld_prp_fifo_wr_en					(w_cpld1_fifo_wr_en),
	.cpld_prp_fifo_tag_last					(w_cpld1_fifo_tag_last),

	.tx_dma_mrd_req							(w_tx_mrd2_req),
	.tx_dma_mrd_tag							(w_tx_mrd2_tag),
	.tx_dma_mrd_len							(w_tx_mrd2_len),
	.tx_dma_mrd_addr						(w_tx_mrd2_addr),
	.tx_dma_mrd_req_ack						(w_tx_mrd2_req_ack),

	.cpld_dma_fifo_tag						(w_cpld2_fifo_tag),
	.cpld_dma_fifo_wr_data					(w_cpld2_fifo_wr_data),
	.cpld_dma_fifo_wr_en					(w_cpld2_fifo_wr_en),
	.cpld_dma_fifo_tag_last					(w_cpld2_fifo_tag_last),

	.tx_dma_mwr_req							(w_tx_mwr1_req),
	.tx_dma_mwr_tag							(w_tx_mwr1_tag),
	.tx_dma_mwr_len							(w_tx_mwr1_len),
	.tx_dma_mwr_addr						(w_tx_mwr1_addr),
	.tx_dma_mwr_req_ack						(w_tx_mwr1_req_ack),
	.tx_dma_mwr_data_last					(w_tx_mwr1_data_last),

	.pcie_tx_dma_fifo_rd_en					(w_tx_mwr1_rd_en),
	.pcie_tx_dma_fifo_rd_data				(w_tx_mwr1_rd_data),

	.hcmd_cq_wr0_en							(w_dma_hcmd_cq_wr0_en),
		.hcmd_cq_wr0_data0						(w_dma_hcmd_cq_wr0_data0),
		.hcmd_cq_wr0_data1						(w_dma_hcmd_cq_wr0_data1),
		.hcmd_cq_wr0_rdy_n						(w_dma_hcmd_cq_wr0_rdy_n),


	.cpu_bus_clk							(cpu_bus_clk),
	.cpu_bus_rst_n							(cpu_bus_rst_n),

	.dma_cmd_wr_en							(dma_cmd_wr_en),
	.dma_cmd_wr_data0						(dma_cmd_wr_data0),
	.dma_cmd_wr_data1						(dma_cmd_wr_data1),
	.dma_cmd_wr_rdy_n						(dma_cmd_wr_rdy_n),

	.dma_rx_direct_done_cnt					(dma_rx_direct_done_cnt),
	.dma_tx_direct_done_cnt					(dma_tx_direct_done_cnt),
	.dma_rx_done_cnt						(dma_rx_done_cnt),
	.dma_tx_done_cnt						(dma_tx_done_cnt),

	.dma_bus_clk							(dma_bus_clk),
	.dma_bus_rst_n							(dma_bus_rst_n),

	.pcie_rx_fifo_rd_en						(pcie_rx_fifo_rd_en),
	.pcie_rx_fifo_rd_data					(pcie_rx_fifo_rd_data),
	.pcie_rx_fifo_free_en					(pcie_rx_fifo_free_en),
	.pcie_rx_fifo_free_len					(pcie_rx_fifo_free_len),
	.pcie_rx_fifo_empty_n					(pcie_rx_fifo_empty_n),

	.pcie_tx_fifo_alloc_en					(pcie_tx_fifo_alloc_en),
	.pcie_tx_fifo_alloc_len					(pcie_tx_fifo_alloc_len),
	.pcie_tx_fifo_wr_en						(pcie_tx_fifo_wr_en),
	.pcie_tx_fifo_wr_data					(pcie_tx_fifo_wr_data),
	.pcie_tx_fifo_full_n					(pcie_tx_fifo_full_n),

	.dma_rx_done_wr_en						(dma_rx_done_wr_en),
	.dma_rx_done_wr_data					(dma_rx_done_wr_data),
	.dma_rx_done_wr_rdy_n					(dma_rx_done_wr_rdy_n)
);

pcie_tans_if # (
	.C_PCIE_DATA_WIDTH						(C_PCIE_DATA_WIDTH)
)
pcie_tans_if_inst0(

//PCIe user clock
	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(pcie_user_rst_n),

//pcie rx signal
	.mreq_fifo_wr_en						(w_mreq_fifo_wr_en),
	.mreq_fifo_wr_data						(w_mreq_fifo_wr_data),

	.req_be                                 (w_req_be),

	.bar2_mreq_fifo_wr_en				(w_bar2_mreq_fifo_wr_en),
	.bar2_mreq_fifo_wr_data			(w_bar2_mreq_fifo_wr_data),
	.bar2_req_be                           (w_bar2_req_be),

	.cpld0_fifo_tag							(w_cpld0_fifo_tag),
	.cpld0_fifo_tag_last					(w_cpld0_fifo_tag_last),
	.cpld0_fifo_wr_en						(w_cpld0_fifo_wr_en),
	.cpld0_fifo_wr_data						(w_cpld0_fifo_wr_data),

	.cpld1_fifo_tag							(w_cpld1_fifo_tag),
	.cpld1_fifo_tag_last					(w_cpld1_fifo_tag_last),
	.cpld1_fifo_wr_en						(w_cpld1_fifo_wr_en),
	.cpld1_fifo_wr_data						(w_cpld1_fifo_wr_data),

	.cpld2_fifo_tag							(w_cpld2_fifo_tag),
	.cpld2_fifo_tag_last					(w_cpld2_fifo_tag_last),
	.cpld2_fifo_wr_en						(w_cpld2_fifo_wr_en),
	.cpld2_fifo_wr_data						(w_cpld2_fifo_wr_data),

	.tx_cpld_req							(w_mux_tx_cpld_req),
	.tx_cpld_tag							(w_mux_tx_cpld_tag),
	.tx_cpld_req_id							(w_mux_tx_cpld_req_id),
	.tx_cpld_len							(w_mux_tx_cpld_len),
	.tx_cpld_laddr							(w_mux_tx_cpld_laddr),
	.tx_cpld_data							(w_mux_tx_cpld_data),
	.tx_cpld_tc						     	(w_mux_tx_cpld_tc),
	.tx_cpld_attr							(w_mux_tx_cpld_attr),
	.tx_cpld_at							    (w_mux_tx_cpld_at),
	.tx_cpld_be							    (w_mux_tx_cpld_be),
		.tx_cpld_func_num						(w_mux_tx_cpld_func_num),
	.tx_cpld_req_ack						(w_tx_cpld_req_ack),

	.tx_mrd0_req							(w_tx_mrd0_req),
	.tx_mrd0_tag							(w_tx_mrd0_tag),
	.tx_mrd0_len							(w_tx_mrd0_len),
	.tx_mrd0_addr							(w_tx_mrd0_addr),
	.tx_mrd0_req_ack						(w_tx_mrd0_req_ack),

	.tx_mrd1_req							(w_tx_mrd1_req),
	.tx_mrd1_tag							(w_tx_mrd1_tag),
	.tx_mrd1_len							(w_tx_mrd1_len),
	.tx_mrd1_addr							(w_tx_mrd1_addr),
	.tx_mrd1_req_ack						(w_tx_mrd1_req_ack),

	.tx_mrd2_req							(w_tx_mrd2_req),
	.tx_mrd2_tag							(w_tx_mrd2_tag),
	.tx_mrd2_len							(w_tx_mrd2_len),
	.tx_mrd2_addr							(w_tx_mrd2_addr),
	.tx_mrd2_req_ack						(w_tx_mrd2_req_ack),

	.tx_mwr0_req							(w_tx_mwr0_req),
	.tx_mwr0_tag							(w_tx_mwr0_tag),
	.tx_mwr0_len							(w_tx_mwr0_len),
	.tx_mwr0_addr							(w_tx_mwr0_addr),
	.tx_mwr0_req_ack						(w_tx_mwr0_req_ack),
	.tx_mwr0_rd_en							(w_tx_mwr0_rd_en),
	.tx_mwr0_rd_data						(w_tx_mwr0_rd_data),
	.tx_mwr0_data_last						(w_tx_mwr0_data_last),

	.tx_mwr1_req							(w_tx_mwr1_req),
	.tx_mwr1_tag							(w_tx_mwr1_tag),
	.tx_mwr1_len							(w_tx_mwr1_len),
	.tx_mwr1_addr							(w_tx_mwr1_addr),
	.tx_mwr1_req_ack						(w_tx_mwr1_req_ack),
	.tx_mwr1_rd_en							(w_tx_mwr1_rd_en),
	.tx_mwr1_rd_data						(w_tx_mwr1_rd_data),
	.tx_mwr1_data_last						(w_tx_mwr1_data_last),

	.pcie_mreq_err							(pcie_mreq_err),
	.pcie_cpld_err							(pcie_cpld_err),
	.pcie_cpld_len_err						(pcie_cpld_len_err),

	.s_axis_cc_tdata                                ( s_axis_cc_tdata ),
	.s_axis_cc_tkeep                                ( s_axis_cc_tkeep ),
	.s_axis_cc_tlast                                ( s_axis_cc_tlast ),
	.s_axis_cc_tvalid                               ( s_axis_cc_tvalid ), 
	.s_axis_cc_tuser                                ( s_axis_cc_tuser ),
	.s_axis_cc_tready                               ( s_axis_cc_tready ),

	.s_axis_rq_tdata                                ( s_axis_rq_tdata ),
	.s_axis_rq_tkeep                                ( s_axis_rq_tkeep ),
	.s_axis_rq_tlast                                ( s_axis_rq_tlast ),
	.s_axis_rq_tvalid                               ( s_axis_rq_tvalid ), 
	.s_axis_rq_tuser                                ( s_axis_rq_tuser ),
	.s_axis_rq_tready                               ( s_axis_rq_tready ),

	.cfg_msg_transmit_done                          ( cfg_msg_transmit_done ), 
	.cfg_msg_transmit                               ( cfg_msg_transmit ),
	.cfg_msg_transmit_type                          ( cfg_msg_transmit_type ), 
	.cfg_msg_transmit_data                          ( cfg_msg_transmit_data ), 

	.pcie_tfc_nph_av                                ( pcie_tfc_nph_av ),
	.pcie_tfc_npd_av                                ( pcie_tfc_npd_av ),
	.pcie_rq_tag                                    ( pcie_rq_tag ),
	.pcie_rq_tag_vld                                ( pcie_rq_tag_vld ),
	.pcie_tfc_np_pl_empty                           ( 1'b0 ),
	.pcie_rq_seq_num                                ( pcie_rq_seq_num ),
	.pcie_rq_seq_num_vld                            ( pcie_rq_seq_num_vld ), 

	.fc_cpld								(fc_cpld),
	.fc_cplh								(fc_cplh),
	.fc_npd									(fc_npd),
	.fc_nph									(fc_nph),
	.fc_pd									(fc_pd),
	.fc_ph									(fc_ph),
	.fc_sel									(fc_sel),

	.m_axis_cq_tdata                                ( m_axis_cq_tdata ),
	.m_axis_cq_tlast                                ( m_axis_cq_tlast ),
	.m_axis_cq_tvalid                               ( m_axis_cq_tvalid ), 
	.m_axis_cq_tuser                                ( m_axis_cq_tuser ),
	.m_axis_cq_tkeep                                ( m_axis_cq_tkeep ),
	.m_axis_cq_tready                               ( m_axis_cq_tready ),

	.m_axis_rc_tdata                                ( m_axis_rc_tdata ),
	.m_axis_rc_tlast                                ( m_axis_rc_tlast ),
	.m_axis_rc_tvalid                               ( m_axis_rc_tvalid ), 
	.m_axis_rc_tuser                                ( m_axis_rc_tuser ),
	.m_axis_rc_tkeep                                ( m_axis_rc_tkeep ),
	.m_axis_rc_tready                               ( m_axis_rc_tready ), 

	.pcie_cq_np_req                                 ( pcie_cq_np_req ),
	.pcie_cq_np_req_count                           ( pcie_cq_np_req_count ), 

	.cfg_msg_received                               ( cfg_msg_received ), 
	.cfg_msg_received_type                          ( cfg_msg_received_type ), 
	.cfg_msg_data                                   ( cfg_msg_data )
);

nvme_irq
nvme_irq_inst0
(
	.pcie_user_clk							(pcie_user_clk),
	.pcie_user_rst_n						(pcie_user_rst_n),

	.cfg_command							 (cfg_command),

    .cfg_interrupt_sent                      ( cfg_interrupt_sent ),
    .cfg_interrupt_pending                   ( cfg_interrupt_pending ),
    .cfg_interrupt_int                       ( cfg_interrupt_int ),

    .cfg_interrupt_msi_enable                ( cfg_interrupt_msi_enable ), 
    .cfg_interrupt_msi_sent                  ( cfg_interrupt_msi_sent ),
    .cfg_interrupt_msi_fail                  ( cfg_interrupt_msi_fail ), 
    .cfg_interrupt_msi_int                   ( cfg_interrupt_msi_int ),
    .cfg_interrupt_msi_pending_status_data_enable   ( cfg_interrupt_msi_pending_status_data_enable ),
	    .cfg_interrupt_msi_function_number       ( cfg_interrupt_msi_function_number ),
    .cfg_interrupt_msi_pending_status        ( cfg_interrupt_msi_pending_status ),

    .cfg_interrupt_msix_enable               ( cfg_interrupt_msix_enable ), 
    .cfg_interrupt_msix_sent                 ( cfg_interrupt_msix_sent ),
    .cfg_interrupt_msix_fail                 ( cfg_interrupt_msix_fail ), 
    .cfg_interrupt_msix_int                  ( cfg_interrupt_msix_int ),
    .cfg_interrupt_msix_address              ( cfg_interrupt_msix_address ), 
    .cfg_interrupt_msix_data                 ( cfg_interrupt_msix_data ), 

	.nvme_intms_ivms						(w_nvme_intms_ivms),
	.nvme_intmc_ivmc						(w_nvme_intmc_ivmc),
	.cq_irq_status							(w_cq_irq_status),
		.pf0_msi_irq_req					(bar2_pf0_msi_irq_req),
		.pf0_msi_irq_vector				(bar2_pf0_msi_irq_vector),
		.pf1_msi_irq_req					(bar2_pf1_msi_irq_req),
		.pf1_msi_irq_vector				(bar2_pf1_msi_irq_vector),

	.cq_rst_n								(cq_rst_n),
	.cq_valid								(cq_valid),
	.io_cq_irq_en							(io_cq_irq_en),
	.cq_irq_retry_cycles			(cq_irq_retry_cycles),
	.io_cq1_iv								(io_cq1_iv),
	.io_cq2_iv								(io_cq2_iv),
	.io_cq3_iv								(io_cq3_iv),
	.io_cq4_iv								(io_cq4_iv),
	.io_cq5_iv								(io_cq5_iv),
	.io_cq6_iv								(io_cq6_iv),
	.io_cq7_iv								(io_cq7_iv),
	.io_cq8_iv								(io_cq8_iv),

	.admin_cq_tail_ptr						(w_admin_cq_tail_ptr),
	.io_cq1_tail_ptr						(w_io_cq1_tail_ptr),
	.io_cq2_tail_ptr						(w_io_cq2_tail_ptr),
	.io_cq3_tail_ptr						(w_io_cq3_tail_ptr),
	.io_cq4_tail_ptr						(w_io_cq4_tail_ptr),
	.io_cq5_tail_ptr						(w_io_cq5_tail_ptr),
	.io_cq6_tail_ptr						(w_io_cq6_tail_ptr),
	.io_cq7_tail_ptr						(w_io_cq7_tail_ptr),
	.io_cq8_tail_ptr						(w_io_cq8_tail_ptr),

	.admin_cq_head_ptr						(w_admin_cq_head_ptr),
	.io_cq1_head_ptr						(w_io_cq1_head_ptr),
	.io_cq2_head_ptr						(w_io_cq2_head_ptr),
	.io_cq3_head_ptr						(w_io_cq3_head_ptr),
	.io_cq4_head_ptr						(w_io_cq4_head_ptr),
	.io_cq5_head_ptr						(w_io_cq5_head_ptr),
	.io_cq6_head_ptr						(w_io_cq6_head_ptr),
	.io_cq7_head_ptr						(w_io_cq7_head_ptr),
	.io_cq8_head_ptr						(w_io_cq8_head_ptr),
	.cq_head_update							(w_cq_head_update)
);

endmodule


/*
----------------------------------------------------------------------------------
BAR2 AXI-Stream completer path register target.
BAR2 offsets map directly to the CPU register window decode.
The last 32 bytes of BAR2 are kept as local debug/status registers.
----------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps

module pcie_bar2_stream # (
	parameter	C_PCIE_DATA_WIDTH			= 512,
	parameter	C_BAR2_ADDR_WIDTH			= 18,
	parameter	P_FIFO_DEPTH_WIDTH			= 5
)
(
	input									pcie_user_clk,
	input									pcie_user_rst_n,

	input									mreq_fifo_wr_en,
	input	[C_PCIE_DATA_WIDTH-1:0]			mreq_fifo_wr_data,
	input	[7:0]							req_be,

	output									tx_cpld_req,
	output	[7:0]							tx_cpld_tag,
	output	[15:0]							tx_cpld_req_id,
	output	[12:2]							tx_cpld_len,
	output	[6:0]							tx_cpld_laddr,
	output	[63:0]							tx_cpld_data,
	output	[2:0]							tx_cpld_tc,
	output	[2:0]							tx_cpld_attr,
	output	[1:0]							tx_cpld_at,
	output	[7:0]							tx_cpld_be,
	output	[7:0]							tx_cpld_func_num,
	input									tx_cpld_req_ack,

	output									bar2_reg_req,
	output									bar2_reg_wr,
	output	[C_BAR2_ADDR_WIDTH-1:0]			bar2_reg_addr,
	output	[31:0]							bar2_reg_wdata,
	output	[3:0]							bar2_reg_be,
	input									bar2_reg_ack,
	input	[31:0]							bar2_reg_rdata
);

localparam	P_FIFO_DATA_WIDTH			= C_PCIE_DATA_WIDTH + 8;
localparam	P_FIFO_DEPTH				= (1 << P_FIFO_DEPTH_WIDTH);

// Debug/status registers live at the end of the 256 KB BAR2 aperture by default.
localparam	[2:0]	P_BAR2_DEBUG_MAGIC		= 3'h0; // 0x3ffe0: fixed magic/version
localparam	[2:0]	P_BAR2_DEBUG_COUNTS		= 3'h1; // 0x3ffe4: {write_count, read_count}
localparam	[2:0]	P_BAR2_DEBUG_LAST_ADDR	= 3'h2; // 0x3ffe8: last BAR2 request byte offset
localparam	[2:0]	P_BAR2_DEBUG_LAST_WDATA	= 3'h3; // 0x3ffec: last memory-write payload dword
localparam	[2:0]	P_BAR2_DEBUG_REQ_COUNT	= 3'h4; // 0x3fff0: total BAR2 requests
localparam	[31:0]	P_BAR2_DEBUG_MAGIC_VALUE	= 32'hb202_0002;

localparam	[3:0]	P_BAR2_FIRST_BEAT_DWORDS	= (C_PCIE_DATA_WIDTH == 512) ? 4'd12 :
										  ((C_PCIE_DATA_WIDTH == 256) ? 4'd4 : 4'd1);

localparam	S_IDLE						= 6'b000001;
localparam	S_DECODE					= 6'b000010;
localparam	S_WRITE						= 6'b000100;
localparam	S_WRITE_GAP				= 6'b001000;
localparam	S_READ						= 6'b010000;
localparam	S_CPLD_ACK					= 6'b100000;

reg		[5:0]							cur_state;
reg		[5:0]							next_state;

reg		[P_FIFO_DEPTH_WIDTH:0]			r_fifo_wr_ptr;
reg		[P_FIFO_DEPTH_WIDTH:0]			r_fifo_rd_ptr;
reg		[P_FIFO_DATA_WIDTH-1:0]			r_fifo [0:P_FIFO_DEPTH-1];

wire									w_fifo_empty;
wire									w_fifo_full;
wire	[P_FIFO_DATA_WIDTH-1:0]			w_fifo_rd_data;
wire									w_fifo_pop;

reg		[C_PCIE_DATA_WIDTH-1:0]			r_mreq_data;
reg		[7:0]							r_req_be;
reg		[31:0]							r_rd_data;
reg									r_tx_cpld_req;
reg		[15:0]							r_req_count;
reg		[15:0]							r_wr_count;
reg		[15:0]							r_rd_count;
reg		[C_BAR2_ADDR_WIDTH-1:0]			r_last_addr;
reg		[31:0]							r_last_wdata;

wire	[1:0]							w_addr_type;
wire	[10:0]							w_dword_count;
wire	[3:0]							w_req_type;
wire	[15:0]							w_req_id;
wire	[7:0]							w_tag;
wire	[2:0]							w_tc;
wire	[2:0]							w_attr;
wire	[C_BAR2_ADDR_WIDTH-1:0]			w_bar2_addr;
wire	[31:0]							w_write_data;
wire	[C_BAR2_ADDR_WIDTH-1:0]			w_write_addr;
wire	[31:0]							w_write_cur_data;
wire	[3:0]							w_write_cur_be;
wire	[3:0]							w_write_dw_count;
wire									w_bar2_debug_hit;
wire									w_write_debug_hit;
wire									w_bar2_write_done;
wire									w_bar2_read_done;
wire									w_write_more_dwords;
reg		[31:0]							r_debug_rdata;
reg		[3:0]							r_write_dw_index;
reg		[3:0]							r_write_dw_count;

function [31:0] f_bar2_payload_dw;
	input [C_PCIE_DATA_WIDTH-1:0] data;
	input [3:0] index;
	begin
		case(index)
			4'd0: f_bar2_payload_dw = data[159:128];
			4'd1: f_bar2_payload_dw = data[191:160];
			4'd2: f_bar2_payload_dw = data[223:192];
			4'd3: f_bar2_payload_dw = data[255:224];
			4'd4: f_bar2_payload_dw = data[287:256];
			4'd5: f_bar2_payload_dw = data[319:288];
			4'd6: f_bar2_payload_dw = data[351:320];
			4'd7: f_bar2_payload_dw = data[383:352];
			4'd8: f_bar2_payload_dw = data[415:384];
			4'd9: f_bar2_payload_dw = data[447:416];
			4'd10: f_bar2_payload_dw = data[479:448];
			4'd11: f_bar2_payload_dw = data[511:480];
			default: f_bar2_payload_dw = 32'h0;
		endcase
	end
endfunction

assign w_fifo_empty = (r_fifo_wr_ptr == r_fifo_rd_ptr);
assign w_fifo_full = ((r_fifo_wr_ptr[P_FIFO_DEPTH_WIDTH] ^ r_fifo_rd_ptr[P_FIFO_DEPTH_WIDTH]) &
						(r_fifo_wr_ptr[P_FIFO_DEPTH_WIDTH-1:0] == r_fifo_rd_ptr[P_FIFO_DEPTH_WIDTH-1:0]));
assign w_fifo_rd_data = r_fifo[r_fifo_rd_ptr[P_FIFO_DEPTH_WIDTH-1:0]];
assign w_fifo_pop = (cur_state == S_IDLE) & ~w_fifo_empty;

assign w_addr_type = r_mreq_data[1:0];
assign w_dword_count = r_mreq_data[74:64];
assign w_req_type = r_mreq_data[78:75];
assign w_req_id = r_mreq_data[95:80];
assign w_tag = r_mreq_data[103:96];
	assign w_target_function = r_mreq_data[111:104];
assign w_tc = r_mreq_data[123:121];
assign w_attr = r_mreq_data[126:124];
assign w_bar2_addr = r_mreq_data[C_BAR2_ADDR_WIDTH-1:0];
assign w_write_data = r_mreq_data[159:128];
assign w_write_dw_count = (w_dword_count[10:0] == 11'd0) ? P_BAR2_FIRST_BEAT_DWORDS :
							((w_dword_count[10:0] > {7'b0, P_BAR2_FIRST_BEAT_DWORDS}) ?
								P_BAR2_FIRST_BEAT_DWORDS : w_dword_count[3:0]);
assign w_write_addr = w_bar2_addr + {{(C_BAR2_ADDR_WIDTH-6){1'b0}}, r_write_dw_index, 2'b00};
assign w_write_cur_data = f_bar2_payload_dw(r_mreq_data, r_write_dw_index);
assign w_write_cur_be = (r_write_dw_count == 4'd1) ? r_req_be[3:0] :
						((r_write_dw_index == 4'd0) ? r_req_be[3:0] :
						(((r_write_dw_index + 4'd1) == r_write_dw_count) ? r_req_be[7:4] : 4'hf));
assign w_bar2_debug_hit = &w_bar2_addr[C_BAR2_ADDR_WIDTH-1:5];
assign w_write_debug_hit = &w_write_addr[C_BAR2_ADDR_WIDTH-1:5];
assign w_bar2_write_done = w_write_debug_hit | bar2_reg_ack;
assign w_bar2_read_done = w_bar2_debug_hit | bar2_reg_ack;
assign w_write_more_dwords = ((r_write_dw_index + 4'd1) < r_write_dw_count);

assign bar2_reg_req = (((cur_state == S_WRITE) && (w_write_debug_hit == 0)) ||
						((cur_state == S_READ) && (w_bar2_debug_hit == 0)));
assign bar2_reg_wr = (cur_state == S_WRITE);
assign bar2_reg_addr = (cur_state == S_WRITE) ? w_write_addr : w_bar2_addr;
assign bar2_reg_wdata = (cur_state == S_WRITE) ? w_write_cur_data : w_write_data;
assign bar2_reg_be = (cur_state == S_WRITE) ? w_write_cur_be : r_req_be[3:0];

assign tx_cpld_req = r_tx_cpld_req;
assign tx_cpld_tag = w_tag;
assign tx_cpld_req_id = w_req_id;
assign tx_cpld_len = {9'b0, (w_dword_count[1:0] == 2'b00) ? 2'b01 : w_dword_count[1:0]};
assign tx_cpld_laddr = w_bar2_addr[6:0];
assign tx_cpld_data = {32'b0, r_rd_data};
assign tx_cpld_tc = w_tc;
assign tx_cpld_attr = w_attr;
assign tx_cpld_at = w_addr_type;
assign tx_cpld_be = r_req_be;
	assign tx_cpld_func_num = w_target_function;

always @ (*)
begin
	r_debug_rdata = 32'h0;
	case(w_bar2_addr[4:2])
		P_BAR2_DEBUG_MAGIC: r_debug_rdata = P_BAR2_DEBUG_MAGIC_VALUE;
		P_BAR2_DEBUG_COUNTS: r_debug_rdata = {r_wr_count, r_rd_count};
		P_BAR2_DEBUG_LAST_ADDR: r_debug_rdata = {{(32-C_BAR2_ADDR_WIDTH){1'b0}}, r_last_addr};
		P_BAR2_DEBUG_LAST_WDATA: r_debug_rdata = r_last_wdata;
		P_BAR2_DEBUG_REQ_COUNT: r_debug_rdata = {16'b0, r_req_count};
	endcase
end

always @ (posedge pcie_user_clk or negedge pcie_user_rst_n)
begin
	if(pcie_user_rst_n == 0) begin
		r_fifo_wr_ptr <= 0;
		r_fifo_rd_ptr <= 0;
	end
	else begin
		if(mreq_fifo_wr_en == 1 && w_fifo_full == 0) begin
			r_fifo[r_fifo_wr_ptr[P_FIFO_DEPTH_WIDTH-1:0]] <= {req_be, mreq_fifo_wr_data};
			r_fifo_wr_ptr <= r_fifo_wr_ptr + 1;
		end

		if(w_fifo_pop == 1)
			r_fifo_rd_ptr <= r_fifo_rd_ptr + 1;
	end
end

always @ (posedge pcie_user_clk or negedge pcie_user_rst_n)
begin
	if(pcie_user_rst_n == 0)
		cur_state <= S_IDLE;
	else
		cur_state <= next_state;
end

always @ (*)
begin
	case(cur_state)
		S_IDLE: begin
			if(w_fifo_empty == 0)
				next_state <= S_DECODE;
			else
				next_state <= S_IDLE;
		end
		S_DECODE: begin
			if(w_req_type == 4'b0001)
				next_state <= S_WRITE;
			else if(w_req_type == 4'b0000)
				next_state <= S_READ;
			else
				next_state <= S_IDLE;
		end
		S_WRITE: begin
			if(w_bar2_write_done == 1) begin
				if(w_write_more_dwords == 1)
					next_state <= S_WRITE_GAP;
				else
					next_state <= S_IDLE;
			end
			else
				next_state <= S_WRITE;
		end
		S_WRITE_GAP: begin
			next_state <= S_WRITE;
		end
		S_READ: begin
			if(w_bar2_read_done == 1)
				next_state <= S_CPLD_ACK;
			else
				next_state <= S_READ;
		end
		S_CPLD_ACK: begin
			if(tx_cpld_req_ack == 1)
				next_state <= S_IDLE;
			else
				next_state <= S_CPLD_ACK;
		end
		default: begin
			next_state <= S_IDLE;
		end
	endcase
end

always @ (posedge pcie_user_clk or negedge pcie_user_rst_n)
begin
	if(pcie_user_rst_n == 0) begin
		r_mreq_data <= 0;
		r_req_be <= 0;
		r_rd_data <= 0;
		r_tx_cpld_req <= 0;
		r_req_count <= 0;
		r_wr_count <= 0;
		r_rd_count <= 0;
		r_last_addr <= 0;
		r_last_wdata <= 0;
		r_write_dw_index <= 0;
		r_write_dw_count <= 0;
	end
	else begin
		case(cur_state)
			S_IDLE: begin
				r_tx_cpld_req <= 0;
				if(w_fifo_empty == 0) begin
					r_mreq_data <= w_fifo_rd_data[C_PCIE_DATA_WIDTH-1:0];
					r_req_be <= w_fifo_rd_data[P_FIFO_DATA_WIDTH-1:C_PCIE_DATA_WIDTH];
				end
			end
			S_DECODE: begin
				r_req_count <= r_req_count + 1;
				r_last_addr <= w_bar2_addr;
				r_write_dw_index <= 0;
				r_write_dw_count <= w_write_dw_count;
				if(w_req_type == 4'b0001) begin
					r_wr_count <= r_wr_count + 1;
					r_last_wdata <= w_write_data;
				end
				else if(w_req_type == 4'b0000) begin
					r_rd_count <= r_rd_count + 1;
				end
			end
			S_WRITE: begin
				if((w_bar2_write_done == 1) && (w_write_more_dwords == 1))
					r_write_dw_index <= r_write_dw_index + 1;
			end
			S_READ: begin
				if(w_bar2_read_done == 1) begin
					r_rd_data <= (w_bar2_debug_hit == 1) ? r_debug_rdata : bar2_reg_rdata;
					r_tx_cpld_req <= 1;
				end
			end
			S_CPLD_ACK: begin
				if(tx_cpld_req_ack == 1)
					r_tx_cpld_req <= 0;
				else
					r_tx_cpld_req <= 1;
			end
			default: begin
				r_tx_cpld_req <= 0;
			end
		endcase
	end
end

endmodule




/*
----------------------------------------------------------------------------------
Single-outstanding BAR2 register request CDC bridge.
This is not an AXI-Lite master; it carries one direct register request at a time.
----------------------------------------------------------------------------------
*/

module bar2_reg_cdc # (
	parameter	C_BAR2_ADDR_WIDTH			= 18
)
(
	input									pcie_clk,
	input									pcie_rst_n,
	input									pcie_reg_req,
	input									pcie_reg_wr,
	input	[C_BAR2_ADDR_WIDTH-1:0]			pcie_reg_addr,
	input	[31:0]							pcie_reg_wdata,
	input	[3:0]							pcie_reg_be,
	output	reg							pcie_reg_ack,
	output	reg	[31:0]						pcie_reg_rdata,

	input									cpu_clk,
	input									cpu_rst_n,
	output	reg							cpu_reg_req,
	output									cpu_reg_wr,
	output	[C_BAR2_ADDR_WIDTH-1:0]			cpu_reg_addr,
	output	[31:0]							cpu_reg_wdata,
	output	[3:0]							cpu_reg_be,
	input									cpu_reg_ack,
	input	[31:0]							cpu_reg_rdata
);

reg										r_src_busy;
reg										r_src_req_toggle;
reg										r_src_req_d;
reg										r_src_resp_seen;
reg										r_src_wr;
reg		[C_BAR2_ADDR_WIDTH-1:0]			r_src_addr;
reg		[31:0]							r_src_wdata;
reg		[3:0]							r_src_be;

(* ASYNC_REG = "TRUE" *) reg [2:0]		r_resp_toggle_sync;
(* ASYNC_REG = "TRUE" *) reg [2:0]		r_req_toggle_sync;

reg										r_dst_busy;
reg										r_dst_req_seen;
reg										r_dst_resp_toggle;
reg										r_dst_wr;
reg		[C_BAR2_ADDR_WIDTH-1:0]			r_dst_addr;
reg		[31:0]							r_dst_wdata;
reg		[3:0]							r_dst_be;
reg		[31:0]							r_dst_rdata;

wire									w_dst_new_req;

assign w_dst_new_req = (r_req_toggle_sync[2] != r_dst_req_seen);
assign cpu_reg_wr = r_dst_wr;
assign cpu_reg_addr = r_dst_addr;
assign cpu_reg_wdata = r_dst_wdata;
assign cpu_reg_be = r_dst_be;

always @ (posedge pcie_clk or negedge pcie_rst_n)
begin
	if(pcie_rst_n == 0) begin
		r_src_busy <= 0;
		r_src_req_toggle <= 0;
		r_src_req_d <= 0;
		r_src_resp_seen <= 0;
		r_src_wr <= 0;
		r_src_addr <= 0;
		r_src_wdata <= 0;
		r_src_be <= 0;
		r_resp_toggle_sync <= 0;
		pcie_reg_ack <= 0;
		pcie_reg_rdata <= 0;
	end
	else begin
		r_resp_toggle_sync <= {r_resp_toggle_sync[1:0], r_dst_resp_toggle};
		r_src_req_d <= pcie_reg_req;
		pcie_reg_ack <= 0;

		if((r_src_busy == 1) && (r_resp_toggle_sync[2] != r_src_resp_seen)) begin
			r_src_busy <= 0;
			r_src_resp_seen <= r_resp_toggle_sync[2];
			pcie_reg_rdata <= r_dst_rdata;
			pcie_reg_ack <= 1;
		end
		else if((r_src_busy == 0) && (pcie_reg_req == 1) && (r_src_req_d == 0)) begin
			r_src_busy <= 1;
			r_src_wr <= pcie_reg_wr;
			r_src_addr <= pcie_reg_addr;
			r_src_wdata <= pcie_reg_wdata;
			r_src_be <= pcie_reg_be;
			r_src_req_toggle <= ~r_src_req_toggle;
		end
	end
end

always @ (posedge cpu_clk or negedge cpu_rst_n)
begin
	if(cpu_rst_n == 0) begin
		r_req_toggle_sync <= 0;
		r_dst_busy <= 0;
		r_dst_req_seen <= 0;
		r_dst_resp_toggle <= 0;
		r_dst_wr <= 0;
		r_dst_addr <= 0;
		r_dst_wdata <= 0;
		r_dst_be <= 0;
		r_dst_rdata <= 0;
		cpu_reg_req <= 0;
	end
	else begin
		r_req_toggle_sync <= {r_req_toggle_sync[1:0], r_src_req_toggle};
		cpu_reg_req <= 0;

		if((r_dst_busy == 0) && (w_dst_new_req == 1)) begin
			r_dst_busy <= 1;
			r_dst_req_seen <= r_req_toggle_sync[2];
			r_dst_wr <= r_src_wr;
			r_dst_addr <= r_src_addr;
			r_dst_wdata <= r_src_wdata;
			r_dst_be <= r_src_be;
			cpu_reg_req <= 1;
		end
		else if((r_dst_busy == 1) && (cpu_reg_ack == 1)) begin
			r_dst_busy <= 0;
			r_dst_rdata <= cpu_reg_rdata;
			r_dst_resp_toggle <= ~r_dst_resp_toggle;
		end
	end
end

endmodule


/*
----------------------------------------------------------------------------------
Toggle-based BAR2 MSI event CDC. The CPU side updates vector before toggling req.
----------------------------------------------------------------------------------
*/

module bar2_msi_cdc
(
	input									cpu_clk,
	input									cpu_rst_n,
	input									cpu_req_toggle,
	input	[8:0]							cpu_vector,
	input									pcie_clk,
	input									pcie_rst_n,
	output	reg							pcie_req,
	output	[8:0]						pcie_vector
);

(* ASYNC_REG = "TRUE" *) reg [2:0]	r_req_toggle_sync;
(* ASYNC_REG = "TRUE" *) reg [8:0]	r_vector_meta;
(* ASYNC_REG = "TRUE" *) reg [8:0]	r_vector_sync;
reg									r_req_toggle_seen;

assign pcie_vector = r_vector_sync;

always @ (posedge pcie_clk or negedge pcie_rst_n)
begin
	if(pcie_rst_n == 0) begin
		r_req_toggle_sync <= 0;
		r_vector_meta <= 9'b000000001;
		r_vector_sync <= 9'b000000001;
		r_req_toggle_seen <= 0;
		pcie_req <= 0;
	end
	else begin
		r_req_toggle_sync <= {r_req_toggle_sync[1:0], cpu_req_toggle};
		r_vector_meta <= cpu_vector;
		r_vector_sync <= r_vector_meta;
		pcie_req <= 0;

		if(r_req_toggle_sync[2] != r_req_toggle_seen) begin
			r_req_toggle_seen <= r_req_toggle_sync[2];
			pcie_req <= 1;
		end
	end
end

endmodule
