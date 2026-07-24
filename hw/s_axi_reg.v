
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

`include	"def_axi.vh"

module s_axi_reg # (
	parameter 	P_SLOT_TAG_WIDTH			=  10, //slot_modified
	parameter	C_S_AXI_ADDR_WIDTH			= 32,
	parameter	C_S_AXI_DATA_WIDTH			= 32,
	parameter	C_S_AXI_BASEADDR			= 32'hA0000000,
	parameter	C_S_AXI_HIGHADDR			= 32'hA001FFFF,
	parameter	C_PCIE_ADDR_WIDTH			= 48, //modified
	parameter	C_M_AXI_ADDR_WIDTH			= 64
)
(
////////////////////////////////////////////////////////////////
//AXI4-lite slave interface signals
	input									s_axi_aclk,
	input									s_axi_aresetn,

//Write address channel
	input									s_axi_awvalid,
	output									s_axi_awready,
	input	[C_S_AXI_ADDR_WIDTH-1:0]		s_axi_awaddr,
	input	[2:0]							s_axi_awprot,

//Write data channel
	input									s_axi_wvalid,
	output									s_axi_wready,
	input	[C_S_AXI_DATA_WIDTH-1:0]		s_axi_wdata,
	input	[(C_S_AXI_DATA_WIDTH/8)-1:0]	s_axi_wstrb,

//Write response channel
	output									s_axi_bvalid,
	input									s_axi_bready,
	output	[1:0]							s_axi_bresp,

//Read address channel
	input									s_axi_arvalid,
	output									s_axi_arready,
 	input	[C_S_AXI_ADDR_WIDTH-1:0]		s_axi_araddr,
	input	[2:0]							s_axi_arprot,

//Read data channel
	output									s_axi_rvalid,
	input									s_axi_rready,
 	output	[C_S_AXI_DATA_WIDTH-1:0]		s_axi_rdata,
	output	[1:0]							s_axi_rresp,

	input									pcie_mreq_err,
	input									pcie_cpld_err,
	input									pcie_cpld_len_err,

	input									m0_axi_bresp_err,
	input									m0_axi_rresp_err,

	output									dev_irq_assert,

	output									pcie_user_logic_rst,

	input									nvme_cc_en,
	input	[1:0]							nvme_cc_shn,

	output	[1:0]							nvme_csts_shst,
	output									nvme_csts_rdy,

	output	[8:0]							sq_valid,
	output	[7:0]							io_sq1_size,
	output	[7:0]							io_sq2_size,
	output	[7:0]							io_sq3_size,
	output	[7:0]							io_sq4_size,
	output	[7:0]							io_sq5_size,
	output	[7:0]							io_sq6_size,
	output	[7:0]							io_sq7_size,
	output	[7:0]							io_sq8_size,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq1_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq2_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq3_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq4_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq5_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq6_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq7_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_sq8_bs_addr,
	output	[3:0]							io_sq1_cq_vec,
	output	[3:0]							io_sq2_cq_vec,
	output	[3:0]							io_sq3_cq_vec,
	output	[3:0]							io_sq4_cq_vec,
	output	[3:0]							io_sq5_cq_vec,
	output	[3:0]							io_sq6_cq_vec,
	output	[3:0]							io_sq7_cq_vec,
	output	[3:0]							io_sq8_cq_vec,

	output	[8:0]							cq_valid,
	output	[7:0]							io_cq1_size,
	output	[7:0]							io_cq2_size,
	output	[7:0]							io_cq3_size,
	output	[7:0]							io_cq4_size,
	output	[7:0]							io_cq5_size,
	output	[7:0]							io_cq6_size,
	output	[7:0]							io_cq7_size,
	output	[7:0]							io_cq8_size,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq1_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq2_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq3_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq4_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq5_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq6_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq7_bs_addr,
	output	[C_PCIE_ADDR_WIDTH-1:2]			io_cq8_bs_addr,
	output	[8:0]							io_cq_irq_en,
	output	[2:0]							io_cq1_iv,
	output	[2:0]							io_cq2_iv,
	output	[2:0]							io_cq3_iv,
	output	[2:0]							io_cq4_iv,
	output	[2:0]							io_cq5_iv,
	output	[2:0]							io_cq6_iv,
	output	[2:0]							io_cq7_iv,
	output	[2:0]							io_cq8_iv,

	output									hcmd_sq_rd_en,
	input	[(P_SLOT_TAG_WIDTH+12)-1:0]		hcmd_sq_rd_data, //slot_modified
	input									hcmd_sq_empty_n,

	output	[(P_SLOT_TAG_WIDTH+2)+1:0]		hcmd_table_rd_addr, //slot_modified
	input	[31:0]							hcmd_table_rd_data,

	output									hcmd_cq_wr1_en,
	output	[(P_SLOT_TAG_WIDTH+28)-1:0]		hcmd_cq_wr1_data0, //slot_modified
	output	[(P_SLOT_TAG_WIDTH+28)-1:0]		hcmd_cq_wr1_data1, //slot_modified
	input									hcmd_cq_wr1_rdy_n,

	output									dma_cmd_wr_en,
	output	[C_M_AXI_ADDR_WIDTH+23:0]			dma_cmd_wr_data0, //slot_modified
	output	[C_M_AXI_ADDR_WIDTH+23:0]			dma_cmd_wr_data1, //slot_modified
	input									dma_cmd_wr_rdy_n,

	input									bar2_reg_req,
	input									bar2_reg_wr,
	input	[17:0]									bar2_reg_addr,
	input	[31:0]									bar2_reg_wdata,
	input	[3:0]									bar2_reg_be,
	output	reg								bar2_reg_ack,
	output	reg [31:0]							bar2_reg_rdata,
	output									bar2_msi_req_toggle,
	output	[8:0]							bar2_msi_vector,
		output									bar2_pf0_msi_req_toggle,
		output	[8:0]							bar2_pf0_msi_vector,

	input	[7:0]							dma_rx_direct_done_cnt,
	input	[7:0]							dma_tx_direct_done_cnt,
	input	[7:0]							dma_rx_done_cnt,
	input	[7:0]							dma_tx_done_cnt,

	input									pcie_link_up,
	input	[5:0]							pl_ltssm_state,
	input	[3:0]							cfg_command,
	input	[2:0]							cfg_interrupt_mmenable,
	input									cfg_interrupt_msienable,
	input										cfg_interrupt_msixenable,

	output										auto_enable,
	output										auto_reset,
	output										auto_io_read_enable,
	output										auto_io_write_enable,
	output										auto_cq_enable,
	output										auto_msi_enable,
	output	[31:0]							auto_cq_mode,
	output	[C_M_AXI_ADDR_WIDTH-1:0]			auto_ddr_base,
	output	[C_M_AXI_ADDR_WIDTH-1:0]			auto_ddr_limit,
	output	[8:0]								auto_io_enable_mask,
	output	[31:0]							auto_cq_irq_retry_cycles,
	output	[31:0]							auto_error_clear,
	output									ssd_model_enable,
	output									ssd_model_reset,
	output	[31:0]						ssd_read_lsb_cycles,
	output	[31:0]						ssd_read_msb_cycles,
	output	[31:0]						ssd_program_cycles,
	output	[31:0]						ssd_fw_read_cycles,
	output	[31:0]						ssd_fw_write_cycles,
	output	[31:0]						ssd_ch_xfer_4k_cycles,
	output	[4:0]						ssd_channel_count,
	input	[31:0]						ssd_model_status,
	input	[31:0]						ssd_model_submit_count,
	input	[31:0]						ssd_model_release_count,
	input	[31:0]							auto_status,
	input	[31:0]							auto_error,
	input	[31:0]							auto_cmd_count,
	input	[31:0]							auto_dma_submit_count,
	input	[31:0]							auto_unsupported_count,
	input	[31:0]							auto_last_qid_slot,
	input	[31:0]							auto_last_opcode,
	input	[31:0]							auto_last_error_info,
	input	[31:0]							cq_dbg_write_count,
	input	[31:0]							cq_dbg_last_dw2,
	input	[31:0]							cq_dbg_last_dw3,

	output [3:0]									reset_count
);

localparam	S_WR_IDLE						= 8'b00000001;
localparam	S_AW_VAILD						= 8'b00000010;
localparam	S_W_READY						= 8'b00000100;
localparam	S_B_VALID						= 8'b00001000;
localparam	S_WAIT_CQ_RDY					= 8'b00010000;
localparam	S_WR_CQ							= 8'b00100000;
localparam	S_WAIT_DMA_RDY					= 8'b01000000;
localparam	S_WR_DMA						= 8'b10000000;

    reg		[7:0]								cur_wr_state;
    reg		[7:0]								next_wr_state;

localparam	S_RD_IDLE						= 5'b00001;
localparam	S_AR_VAILD						= 5'b00010;
localparam	S_AR_REG						= 5'b00100;
localparam	S_BRAM_READ						= 5'b01000;
localparam	S_R_READY						= 5'b10000;

localparam	S_BAR2_IDLE					= 4'd0;
localparam	S_BAR2_WRITE				= 4'd1;
localparam	S_BAR2_WAIT_CQ_RDY		= 4'd2;
localparam	S_BAR2_WR_CQ				= 4'd3;
localparam	S_BAR2_WAIT_DMA_RDY		= 4'd4;
localparam	S_BAR2_WR_DMA				= 4'd5;
localparam	S_BAR2_READ					= 4'd6;
localparam	S_BAR2_BRAM_READ			= 4'd7;

localparam	P_BAR2_DMA_RING_DESC_WIDTH	= 8;
localparam	S_DMA_RING_IDLE				= 2'd0;
localparam	S_DMA_RING_WAIT_RDY		= 2'd1;

reg		[4:0]								cur_rd_state;
reg		[4:0]								next_rd_state;

reg											r_s_axi_awready;
reg		[15:2]								r_s_axi_awaddr;
reg											r_s_axi_wready;
reg											r_s_axi_bvalid;
reg		[1:0]								r_s_axi_bresp;
reg											r_s_axi_arready;
 reg		[16:2]								r_s_axi_araddr; //slot_modified
reg											r_s_axi_rvalid;
reg		[C_S_AXI_DATA_WIDTH-1:0]			r_s_axi_rdata;
reg		[1:0]								r_s_axi_rresp;

reg											r_irq_assert;
reg		[11:0]								r_irq_req;
reg		[11:0]								r_irq_mask;
reg		[11:0]								r_irq_clear;
reg		[11:0]								r_irq_set;

reg											r_pcie_user_logic_rst;

reg		[1:0]								r_nvme_csts_shst;
reg											r_nvme_csts_rdy;

reg		[8:0]								r_sq_valid;
reg		[7:0]								r_io_sq1_size;
reg		[7:0]								r_io_sq2_size;
reg		[7:0]								r_io_sq3_size;
reg		[7:0]								r_io_sq4_size;
reg		[7:0]								r_io_sq5_size;
reg		[7:0]								r_io_sq6_size;
reg		[7:0]								r_io_sq7_size;
reg		[7:0]								r_io_sq8_size;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq1_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq2_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq3_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq4_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq5_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq6_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq7_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_sq8_bs_addr;
reg		[3:0]								r_io_sq1_cq_vec;
reg		[3:0]								r_io_sq2_cq_vec;
reg		[3:0]								r_io_sq3_cq_vec;
reg		[3:0]								r_io_sq4_cq_vec;
reg		[3:0]								r_io_sq5_cq_vec;
reg		[3:0]								r_io_sq6_cq_vec;
reg		[3:0]								r_io_sq7_cq_vec;
reg		[3:0]								r_io_sq8_cq_vec;

reg		[8:0]								r_cq_valid;
reg		[7:0]								r_io_cq1_size;
reg		[7:0]								r_io_cq2_size;
reg		[7:0]								r_io_cq3_size;
reg		[7:0]								r_io_cq4_size;
reg		[7:0]								r_io_cq5_size;
reg		[7:0]								r_io_cq6_size;
reg		[7:0]								r_io_cq7_size;
reg		[7:0]								r_io_cq8_size;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq1_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq2_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq3_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq4_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq5_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq6_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq7_bs_addr;
reg		[C_PCIE_ADDR_WIDTH-1:2]				r_io_cq8_bs_addr;
reg		[8:0]								r_io_cq_irq_en;
reg		[2:0]								r_io_cq1_iv;
reg		[2:0]								r_io_cq2_iv;
reg		[2:0]								r_io_cq3_iv;
reg		[2:0]								r_io_cq4_iv;
reg		[2:0]								r_io_cq5_iv;
reg		[2:0]								r_io_cq6_iv;
reg		[2:0]								r_io_cq7_iv;
reg		[2:0]								r_io_cq8_iv;

    reg		[1:0]								r_cql_type;
    reg		[3:0]								r_cpl_sq_qid;
    reg		[15:0]								r_cpl_cid;
    reg		[P_SLOT_TAG_WIDTH-1:0]				r_hcmd_slot_tag; //slot_modified
    reg		[14:0]								r_cpl_status;
    reg		[31:0]								r_cpl_specific;

    reg											r_dma_cmd_type;
    reg											r_dma_cmd_auto_cpl;
    reg											r_dma_cmd_dir;
    reg		[P_SLOT_TAG_WIDTH-1:0]				r_dma_cmd_hcmd_slot_tag; //slot_modified
    reg		[C_M_AXI_ADDR_WIDTH-1:2]				r_dma_cmd_dev_addr;
    reg		[12:2]								r_dma_cmd_dev_len;
    reg		[8:0]								r_dma_cmd_4k_offset;
    reg		[C_PCIE_ADDR_WIDTH-1:2]				r_dma_cmd_pcie_addr;

reg											r_hcmd_cq_wr1_en;
reg											r_dma_cmd_wr_en;
reg											r_hcmd_sq_rd_en;

reg		[31:0]								r_wdata;
reg											r_awaddr_cntl_reg_en;
//reg											r_awaddr_pcie_reg_en;
reg											r_awaddr_nvme_reg_en;
reg										r_awaddr_nvme_fifo_en;
reg										r_awaddr_auto_reg_en;
reg										r_awaddr_hcmd_cq_wr1_en;
reg											r_awaddr_dma_cmd_wr_en;
reg											r_cntl_reg_en;
//reg											r_pcie_reg_en;
reg											r_nvme_reg_en;
reg										r_nvme_fifo_en;
reg										r_auto_reg_en;


reg		[31:0]								r_rdata;
    reg											r_araddr_cntl_reg_en;
    reg											r_araddr_pcie_reg_en;
    reg											r_araddr_nvme_reg_en;
        reg										r_araddr_nvme_fifo_en;
    reg										r_araddr_auto_reg_en;
    reg										r_araddr_hcmd_table_rd_en;
    reg											r_araddr_hcmd_sq_rd_en;
reg		[31:0]								r_cntl_reg_rdata;
reg		[31:0]								r_pcie_reg_rdata;
reg		[31:0]								r_nvme_reg_rdata;
reg		[31:0]								r_nvme_fifo_rdata;
reg		[31:0]								r_auto_reg_rdata;

reg											r_pcie_link_up;
reg		[3:0]								r_cfg_command;
reg		[2:0]								r_cfg_interrupt_mmenable;
reg											r_cfg_interrupt_msienable;
reg											r_cfg_interrupt_msixenable;

reg											r_nvme_cc_en;
reg		[1:0]								r_nvme_cc_shn;

(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_bresp_err;
(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_bresp_err_d1;
(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_bresp_err_d2;

(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_rresp_err;
(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_rresp_err_d1;
(* KEEP = "TRUE", SHIFT_EXTRACT = "NO" *)	reg										r_m0_axi_rresp_err_d2;

reg											r_pcie_mreq_err;
reg											r_pcie_cpld_err;
reg											r_pcie_cpld_len_err;
reg		[3:0]								r_reset_count;

reg		[3:0]								r_bar2_state;
reg										r_bar2_wr;
reg		[17:2]								r_bar2_addr;
reg		[31:0]								r_bar2_wdata;
reg		[3:0]								r_bar2_be;
reg										r_bar2_hcmd_table_rd_pending;
reg										r_bar2_hcmd_sq_rd_pending;

wire										w_bar2_addr_in_range;
wire										w_bar2_hcmd_cq_addr;
wire										w_bar2_dma_cmd_addr;
wire										w_bar2_rd_active;
wire										w_bar2_hcmd_table_rd_active;
wire										w_bar2_hcmd_sq_rd_en;
wire										w_bar2_write_reg_active;
wire										w_bar2_cntl_reg_en;
wire										w_bar2_nvme_reg_en;
wire										w_bar2_nvme_fifo_en;
wire										w_bar2_auto_reg_en;
wire										w_bar2_hcmd_cq_wr1_en;
wire										w_bar2_dma_cmd_wr_en;
wire	[15:2]								w_reg_wr_addr;
wire	[16:2]								w_reg_rd_addr;
wire	[31:0]								w_reg_wdata;
wire										w_cntl_reg_en;
wire										w_nvme_reg_en;
wire										w_nvme_fifo_en;
wire										w_auto_reg_en;
wire	[31:0]								w_bar2_reg_read_data;
wire	[31:0]								w_bar2_bram_read_data;

(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw0 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw1 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw2 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw3 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw4 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw5 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_dw6 [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];
(* ram_style = "distributed" *) reg [31:0]	r_dma_ring_pid_cid [0:(1<<P_BAR2_DMA_RING_DESC_WIDTH)-1];

reg		[1:0]								r_dma_ring_state;
reg		[P_BAR2_DMA_RING_DESC_WIDTH-1:0]	r_dma_ring_head;
reg		[P_BAR2_DMA_RING_DESC_WIDTH-1:0]	r_dma_ring_tail;
reg										r_dma_ring_cmd_wr_en;
reg		[C_M_AXI_ADDR_WIDTH+23:0]			r_dma_ring_cmd_wr_data0;
reg		[C_M_AXI_ADDR_WIDTH+23:0]			r_dma_ring_cmd_wr_data1;
reg		[31:0]								r_dma_ring_submit_count;
reg		[31:0]								r_dma_ring_doorbell_count;
reg		[31:0]								r_dma_ring_backpressure_count;
reg		[31:0]								r_dma_ring_pid_submit;
reg		[31:0]								r_dma_ring_pid_done;
reg		[15:0]							r_dma_ring_last_submit_pid;
reg		[15:0]							r_dma_ring_last_submit_cid;
reg		[15:0]							r_dma_ring_last_done_pid;
reg		[15:0]							r_dma_ring_last_done_cid;
reg		[31:0]								r_dma_ring_done_count;
reg		[15:0]							r_dma_ring_done_pending;
reg		[31:0]								r_dma_ring_msi_count;
reg		[15:0]							r_dma_ring_msi_threshold;
reg		[15:0]							r_dma_ring_msi_since_irq;
reg									r_dma_ring_msi_enable;
reg		[8:0]							r_dma_ring_msi_vector;
reg									r_dma_ring_msi_req_toggle;
reg		[31:0]							r_bar2_pf0_msi_count;
reg									r_bar2_pf0_msi_enable;
reg		[8:0]							r_bar2_pf0_msi_vector;
reg									r_bar2_pf0_msi_req_toggle;
reg		[7:0]							r_dma_rx_direct_done_cnt_d;
reg		[7:0]							r_dma_tx_direct_done_cnt_d;
reg		[7:0]							r_dma_rx_done_cnt_d;
reg		[7:0]							r_dma_tx_done_cnt_d;

reg		[31:0]								r_auto_ctrl;
reg		[C_M_AXI_ADDR_WIDTH-1:0]			r_auto_ddr_base;
reg		[C_M_AXI_ADDR_WIDTH-1:0]			r_auto_ddr_limit;
reg		[8:0]								r_auto_io_enable_mask;
reg		[31:0]								r_auto_pf0_msi_ctrl;
reg		[31:0]								r_auto_cq_mode;
reg		[31:0]								r_auto_cq_irq_retry_cycles;
reg		[31:0]								r_ssd_model_ctrl;
reg		[31:0]								r_ssd_read_lsb_cycles;
reg		[31:0]								r_ssd_read_msb_cycles;
reg		[31:0]								r_ssd_program_cycles;
reg		[31:0]								r_ssd_fw_read_cycles;
reg		[31:0]								r_ssd_fw_write_cycles;
reg		[31:0]								r_ssd_ch_xfer_4k_cycles;
reg		[4:0]								r_ssd_channel_count;
reg										r_ssd_model_reset_pulse;
reg		[31:0]								r_auto_error_clear;
reg										r_auto_reset_pulse;
reg		[31:0]								r_auto_cq_irq_retry_count;
reg		[3:0]								r_auto_cq_irq_retry_last_cqid;
reg		[8:0]								w_auto_cq_irq_retry_vector;
wire	[3:0]								w_auto_cq_irq_retry_cqid;
wire										w_auto_cq_irq_retry_wr;

wire	[P_BAR2_DMA_RING_DESC_WIDTH-1:0]	w_bar2_dma_ring_desc_idx;
wire	[2:0]								w_bar2_dma_ring_desc_dw;
wire										w_bar2_dma_ring_hit;
wire										w_bar2_dma_ring_ctrl_hit;
wire										w_bar2_dma_ring_wr_en;
wire										w_bar2_dma_ring_ctrl_wr_en;
wire										w_dma_ring_empty;
wire										w_dma_ring_manual_submit;
wire										w_dma_ring_can_submit;
wire	[31:0]								w_bar2_dma_ring_read_data;
reg		[31:0]								w_bar2_dma_ring_ctrl_rdata;
wire	[7:0]								w_dma_ring_used;
wire	[31:0]								w_dma_ring_inflight;
wire									w_dma_ring_pid_full;
wire										w_dma_ring_type;
wire										w_dma_ring_dir;
wire										w_dma_ring_auto_cpl;
wire	[P_SLOT_TAG_WIDTH-1:0]				w_dma_ring_slot_tag;
wire	[15:0]							w_dma_ring_cid;
wire	[12:2]								w_dma_ring_dev_len;
wire	[8:0]								w_dma_ring_4k_offset;
wire	[C_M_AXI_ADDR_WIDTH-1:2]			w_dma_ring_dev_addr;
wire	[C_PCIE_ADDR_WIDTH-1:2]			w_dma_ring_pcie_addr;
wire	[7:0]								w_dma_rx_direct_done_delta;
wire	[7:0]								w_dma_tx_direct_done_delta;
wire	[7:0]								w_dma_rx_done_delta;
wire	[7:0]								w_dma_tx_done_delta;
wire	[9:0]								w_dma_done_delta_sum;
wire	[15:0]							w_dma_done_pending_next;
wire									w_dma_ring_retire;
wire									w_dma_ring_msi_fire;
wire	[15:0]							w_dma_ring_msi_threshold;
wire	[C_M_AXI_ADDR_WIDTH+23:0]			w_reg_dma_cmd_wr_data0;
wire	[C_M_AXI_ADDR_WIDTH+23:0]			w_reg_dma_cmd_wr_data1;

function [31:0] f_bar2_apply_be;
	input [31:0] old_data;
	input [31:0] new_data;
	input [3:0] be;
	begin
		f_bar2_apply_be = old_data;
		if(be[0] == 1'b1) f_bar2_apply_be[7:0] = new_data[7:0];
		if(be[1] == 1'b1) f_bar2_apply_be[15:8] = new_data[15:8];
		if(be[2] == 1'b1) f_bar2_apply_be[23:16] = new_data[23:16];
		if(be[3] == 1'b1) f_bar2_apply_be[31:24] = new_data[31:24];
	end
endfunction

assign s_axi_awready = r_s_axi_awready;
assign s_axi_wready = r_s_axi_wready;
assign s_axi_bvalid = r_s_axi_bvalid;
assign s_axi_bresp = r_s_axi_bresp;
assign s_axi_arready = r_s_axi_arready;
assign s_axi_rvalid = r_s_axi_rvalid;
assign s_axi_rdata = r_s_axi_rdata;
assign s_axi_rresp = r_s_axi_rresp;

assign dev_irq_assert = r_irq_assert;
assign bar2_msi_req_toggle = r_dma_ring_msi_req_toggle;
assign bar2_msi_vector = r_dma_ring_msi_vector;
assign bar2_pf0_msi_req_toggle = r_bar2_pf0_msi_req_toggle;
assign bar2_pf0_msi_vector = r_bar2_pf0_msi_vector;

assign sq_valid = r_sq_valid;
assign io_sq1_size = r_io_sq1_size;
assign io_sq2_size = r_io_sq2_size;
assign io_sq3_size = r_io_sq3_size;
assign io_sq4_size = r_io_sq4_size;
assign io_sq5_size = r_io_sq5_size;
assign io_sq6_size = r_io_sq6_size;
assign io_sq7_size = r_io_sq7_size;
assign io_sq8_size = r_io_sq8_size;
assign io_sq1_bs_addr = r_io_sq1_bs_addr;
assign io_sq2_bs_addr = r_io_sq2_bs_addr;
assign io_sq3_bs_addr = r_io_sq3_bs_addr;
assign io_sq4_bs_addr = r_io_sq4_bs_addr;
assign io_sq5_bs_addr = r_io_sq5_bs_addr;
assign io_sq6_bs_addr = r_io_sq6_bs_addr;
assign io_sq7_bs_addr = r_io_sq7_bs_addr;
assign io_sq8_bs_addr = r_io_sq8_bs_addr;
assign io_sq1_cq_vec = r_io_sq1_cq_vec;
assign io_sq2_cq_vec = r_io_sq2_cq_vec;
assign io_sq3_cq_vec = r_io_sq3_cq_vec;
assign io_sq4_cq_vec = r_io_sq4_cq_vec;
assign io_sq5_cq_vec = r_io_sq5_cq_vec;
assign io_sq6_cq_vec = r_io_sq6_cq_vec;
assign io_sq7_cq_vec = r_io_sq7_cq_vec;
assign io_sq8_cq_vec = r_io_sq8_cq_vec;

assign cq_valid = r_cq_valid;
assign io_cq1_size = r_io_cq1_size;
assign io_cq2_size = r_io_cq2_size;
assign io_cq3_size = r_io_cq3_size;
assign io_cq4_size = r_io_cq4_size;
assign io_cq5_size = r_io_cq5_size;
assign io_cq6_size = r_io_cq6_size;
assign io_cq7_size = r_io_cq7_size;
assign io_cq8_size = r_io_cq8_size;
assign io_cq1_bs_addr = r_io_cq1_bs_addr;
assign io_cq2_bs_addr = r_io_cq2_bs_addr;
assign io_cq3_bs_addr = r_io_cq3_bs_addr;
assign io_cq4_bs_addr = r_io_cq4_bs_addr;
assign io_cq5_bs_addr = r_io_cq5_bs_addr;
assign io_cq6_bs_addr = r_io_cq6_bs_addr;
assign io_cq7_bs_addr = r_io_cq7_bs_addr;
assign io_cq8_bs_addr = r_io_cq8_bs_addr;
assign io_cq_irq_en = r_io_cq_irq_en;
assign io_cq1_iv = r_io_cq1_iv;
assign io_cq2_iv = r_io_cq2_iv;
assign io_cq3_iv = r_io_cq3_iv;
assign io_cq4_iv = r_io_cq4_iv;
assign io_cq5_iv = r_io_cq5_iv;
assign io_cq6_iv = r_io_cq6_iv;
assign io_cq7_iv = r_io_cq7_iv;
assign io_cq8_iv = r_io_cq8_iv;

assign pcie_user_logic_rst = r_pcie_user_logic_rst;
assign nvme_csts_shst = r_nvme_csts_shst;
assign nvme_csts_rdy = r_nvme_csts_rdy;

assign hcmd_table_rd_addr = (w_bar2_hcmd_table_rd_active == 1) ? r_bar2_addr[(P_SLOT_TAG_WIDTH+2)+3:2] :
								 r_s_axi_araddr[(P_SLOT_TAG_WIDTH+2)+3:2];
assign hcmd_sq_rd_en = r_hcmd_sq_rd_en | w_bar2_hcmd_sq_rd_en;

assign hcmd_cq_wr1_en = r_hcmd_cq_wr1_en | w_bar2_hcmd_cq_wr1_en;
assign hcmd_cq_wr1_data0 = ((r_cql_type[1] | r_cql_type[0]) == 1) ? {r_cpl_status[12:0], r_cpl_sq_qid, r_cpl_cid[15:7], r_hcmd_slot_tag, r_cql_type}//slot_modified
												: {{P_SLOT_TAG_WIDTH-7{1'b0}},r_cpl_status[12:0], r_cpl_sq_qid, r_cpl_cid, r_cql_type};//slot_modified
assign hcmd_cq_wr1_data1 = {{(P_SLOT_TAG_WIDTH-6){1'b0}}, r_cpl_specific[31:0], r_cpl_status[14:13]}; //slot_modified


assign dma_cmd_wr_en = r_dma_cmd_wr_en | w_bar2_dma_cmd_wr_en | r_dma_ring_cmd_wr_en;
assign w_reg_dma_cmd_wr_data0 = {{(13-P_SLOT_TAG_WIDTH){1'b0}}, r_dma_cmd_type, r_dma_cmd_dir, r_dma_cmd_hcmd_slot_tag, r_dma_cmd_dev_len, r_dma_cmd_dev_addr}; //slot_modified
assign w_reg_dma_cmd_wr_data1 = {{(C_M_AXI_ADDR_WIDTH-32){1'b0}}, r_dma_cmd_auto_cpl, r_dma_cmd_4k_offset ,r_dma_cmd_pcie_addr};
assign dma_cmd_wr_data0 = (r_dma_ring_cmd_wr_en == 1'b1) ? r_dma_ring_cmd_wr_data0 : w_reg_dma_cmd_wr_data0;
assign dma_cmd_wr_data1 = (r_dma_ring_cmd_wr_en == 1'b1) ? r_dma_ring_cmd_wr_data1 : w_reg_dma_cmd_wr_data1;
assign reset_count = r_reset_count;
assign auto_enable = r_auto_ctrl[0];
assign auto_reset = r_auto_reset_pulse;
assign auto_io_read_enable = r_auto_ctrl[8];
assign auto_io_write_enable = r_auto_ctrl[9];
assign auto_cq_enable = r_auto_ctrl[10];
assign auto_msi_enable = r_auto_ctrl[11];
assign auto_cq_mode = r_auto_cq_mode;
assign auto_ddr_base = r_auto_ddr_base;
assign auto_ddr_limit = r_auto_ddr_limit;
assign auto_io_enable_mask = r_auto_io_enable_mask;
assign auto_cq_irq_retry_cycles = r_auto_cq_irq_retry_cycles;
assign ssd_model_enable = r_ssd_model_ctrl[0];
assign ssd_model_reset = r_ssd_model_reset_pulse;
assign ssd_read_lsb_cycles = r_ssd_read_lsb_cycles;
assign ssd_read_msb_cycles = r_ssd_read_msb_cycles;
assign ssd_program_cycles = r_ssd_program_cycles;
assign ssd_fw_read_cycles = r_ssd_fw_read_cycles;
assign ssd_fw_write_cycles = r_ssd_fw_write_cycles;
assign ssd_ch_xfer_4k_cycles = r_ssd_ch_xfer_4k_cycles;
assign ssd_channel_count = r_ssd_channel_count;
assign auto_error_clear = r_auto_error_clear;
assign w_auto_cq_irq_retry_cqid = w_reg_wdata[7:4];
assign w_auto_cq_irq_retry_wr = w_auto_reg_en & (w_reg_wr_addr[7:2] == 6'h16) &
									 w_reg_wdata[0] & (w_auto_cq_irq_retry_cqid <= 4'h8);


assign w_bar2_addr_in_range = (r_bar2_addr[17] == 1'b0);
assign w_bar2_hcmd_cq_addr = (r_bar2_addr[15:2] == 14'hD0);
assign w_bar2_dma_cmd_addr = (r_bar2_addr[15:2] == 14'hCC);
assign w_bar2_rd_active = (r_bar2_state == S_BAR2_READ) | (r_bar2_state == S_BAR2_BRAM_READ);
assign w_bar2_hcmd_table_rd_active = w_bar2_rd_active & r_bar2_hcmd_table_rd_pending;
assign w_bar2_hcmd_sq_rd_en = (r_bar2_state == S_BAR2_BRAM_READ) & r_bar2_hcmd_sq_rd_pending;
assign w_bar2_write_reg_active = (r_bar2_state == S_BAR2_WRITE) & r_bar2_wr & w_bar2_addr_in_range &
								~w_bar2_hcmd_cq_addr & ~w_bar2_dma_cmd_addr;
assign w_bar2_cntl_reg_en = w_bar2_write_reg_active & (r_bar2_addr[15:8] == 8'h0);
assign w_bar2_nvme_reg_en = w_bar2_write_reg_active & (r_bar2_addr[15:8] == 8'h2);
assign w_bar2_nvme_fifo_en = w_bar2_write_reg_active & (r_bar2_addr[15:8] == 8'h3);
assign w_bar2_auto_reg_en = w_bar2_write_reg_active & (r_bar2_addr[15:8] == 8'h4);
assign w_bar2_hcmd_cq_wr1_en = (r_bar2_state == S_BAR2_WR_CQ);
assign w_bar2_dma_cmd_wr_en = (r_bar2_state == S_BAR2_WR_DMA);

assign w_reg_wr_addr = (w_bar2_write_reg_active == 1) ? r_bar2_addr[15:2] : r_s_axi_awaddr;
assign w_reg_rd_addr = (w_bar2_rd_active == 1) ? r_bar2_addr[16:2] : r_s_axi_araddr;
assign w_reg_wdata = (w_bar2_write_reg_active == 1) ? r_bar2_wdata : r_wdata;
assign w_cntl_reg_en = r_cntl_reg_en | w_bar2_cntl_reg_en;
assign w_nvme_reg_en = r_nvme_reg_en | w_bar2_nvme_reg_en;
assign w_nvme_fifo_en = r_nvme_fifo_en | w_bar2_nvme_fifo_en;
assign w_auto_reg_en = r_auto_reg_en | w_bar2_auto_reg_en;

assign w_bar2_dma_ring_hit = (r_bar2_addr[17:13] == 5'b10000);
assign w_bar2_dma_ring_ctrl_hit = (r_bar2_addr[17:12] == 6'h22);
assign w_bar2_dma_ring_wr_en = (r_bar2_state == S_BAR2_WRITE) & r_bar2_wr & w_bar2_dma_ring_hit;
assign w_bar2_dma_ring_ctrl_wr_en = (r_bar2_state == S_BAR2_WRITE) & r_bar2_wr & w_bar2_dma_ring_ctrl_hit;
assign w_bar2_dma_ring_desc_idx = r_bar2_addr[12:5];
assign w_bar2_dma_ring_desc_dw = r_bar2_addr[4:2];
assign w_dma_ring_empty = (r_dma_ring_head == r_dma_ring_tail);
assign w_dma_ring_manual_submit = r_dma_cmd_wr_en | w_bar2_dma_cmd_wr_en;
assign w_dma_ring_can_submit = (dma_cmd_wr_rdy_n == 0) & (w_dma_ring_manual_submit == 0) & (w_dma_ring_pid_full == 0);
assign w_dma_ring_used = r_dma_ring_tail - r_dma_ring_head;
assign w_dma_ring_inflight = r_dma_ring_pid_submit - r_dma_ring_pid_done;
assign w_dma_ring_pid_full = (w_dma_ring_inflight >= (32'd1 << P_BAR2_DMA_RING_DESC_WIDTH));

assign w_dma_ring_type = r_dma_ring_dw4[r_dma_ring_head][31];
assign w_dma_ring_dir = r_dma_ring_dw4[r_dma_ring_head][30];
assign w_dma_ring_4k_offset = r_dma_ring_dw4[r_dma_ring_head][22:14];
assign w_dma_ring_auto_cpl = r_dma_ring_dw4[r_dma_ring_head][13];
assign w_dma_ring_dev_len = r_dma_ring_dw4[r_dma_ring_head][12:2];
assign w_dma_ring_slot_tag = r_dma_ring_dw5[r_dma_ring_head][P_SLOT_TAG_WIDTH-1:0];
assign w_dma_ring_cid = r_dma_ring_dw6[r_dma_ring_head][15:0];
assign w_dma_ring_dev_addr = {r_dma_ring_dw1[r_dma_ring_head][C_M_AXI_ADDR_WIDTH-33:0], r_dma_ring_dw0[r_dma_ring_head][31:2]};
assign w_dma_ring_pcie_addr = {r_dma_ring_dw3[r_dma_ring_head][C_PCIE_ADDR_WIDTH-33:0], r_dma_ring_dw2[r_dma_ring_head][31:2]};
assign w_dma_rx_direct_done_delta = dma_rx_direct_done_cnt - r_dma_rx_direct_done_cnt_d;
assign w_dma_tx_direct_done_delta = dma_tx_direct_done_cnt - r_dma_tx_direct_done_cnt_d;
assign w_dma_rx_done_delta = dma_rx_done_cnt - r_dma_rx_done_cnt_d;
assign w_dma_tx_done_delta = dma_tx_done_cnt - r_dma_tx_done_cnt_d;
assign w_dma_done_delta_sum = {2'b0, w_dma_rx_direct_done_delta} + {2'b0, w_dma_tx_direct_done_delta} +
							  {2'b0, w_dma_rx_done_delta} + {2'b0, w_dma_tx_done_delta};
assign w_dma_ring_retire = ((r_dma_ring_done_pending != 0) || (w_dma_done_delta_sum != 0)) &
							   (r_dma_ring_pid_done != r_dma_ring_pid_submit);
assign w_dma_done_pending_next = r_dma_ring_done_pending + {6'b0, w_dma_done_delta_sum} -
									(w_dma_ring_retire ? 16'd1 : 16'd0);
assign w_dma_ring_msi_threshold = (r_dma_ring_msi_threshold == 16'd0) ? 16'd1 : r_dma_ring_msi_threshold;
assign w_dma_ring_msi_fire = w_dma_ring_retire & r_dma_ring_msi_enable &
								(((r_dma_ring_msi_since_irq + 16'd1) >= w_dma_ring_msi_threshold) |
								 (w_dma_ring_inflight == 32'd1));

assign w_bar2_dma_ring_read_data = (w_bar2_dma_ring_desc_dw == 3'd0) ? r_dma_ring_dw0[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd1) ? r_dma_ring_dw1[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd2) ? r_dma_ring_dw2[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd3) ? r_dma_ring_dw3[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd4) ? r_dma_ring_dw4[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd5) ? r_dma_ring_dw5[w_bar2_dma_ring_desc_idx] :
								 ((w_bar2_dma_ring_desc_dw == 3'd6) ? r_dma_ring_dw6[w_bar2_dma_ring_desc_idx] : 32'h0))))));

always @ (*)
begin
	w_bar2_dma_ring_ctrl_rdata = 32'h0;
	case(r_bar2_addr[7:2])
		6'h00: w_bar2_dma_ring_ctrl_rdata = 32'hd2c0_0002;
		6'h01: w_bar2_dma_ring_ctrl_rdata = {13'b0, w_dma_ring_pid_full, (r_dma_ring_state != S_DMA_RING_IDLE), w_dma_ring_empty, r_dma_ring_tail, r_dma_ring_head};
		6'h02: w_bar2_dma_ring_ctrl_rdata = {16'h0020, 8'h00, w_dma_ring_used};
		6'h03: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_submit_count;
		6'h04: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_doorbell_count;
		6'h05: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_backpressure_count;
		6'h06: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_pid_submit;
		6'h07: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_pid_done;
		6'h08: w_bar2_dma_ring_ctrl_rdata = {r_dma_ring_last_submit_pid, r_dma_ring_last_submit_cid};
		6'h09: w_bar2_dma_ring_ctrl_rdata = {r_dma_ring_last_done_pid, r_dma_ring_last_done_cid};
		6'h0A: w_bar2_dma_ring_ctrl_rdata = {15'b0, r_dma_ring_msi_vector, 7'b0, r_dma_ring_msi_enable};
		6'h0B: w_bar2_dma_ring_ctrl_rdata = {16'b0, r_dma_ring_msi_threshold};
		6'h0C: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_msi_count;
		6'h0D: w_bar2_dma_ring_ctrl_rdata = r_dma_ring_done_count;
		6'h0E: w_bar2_dma_ring_ctrl_rdata = w_dma_ring_inflight;
		6'h0F: w_bar2_dma_ring_ctrl_rdata = {16'b0, r_dma_ring_done_pending};
		6'h10: w_bar2_dma_ring_ctrl_rdata = {15'b0, r_bar2_pf0_msi_vector, 7'b0, r_bar2_pf0_msi_enable};
		6'h11: w_bar2_dma_ring_ctrl_rdata = r_bar2_pf0_msi_count;
	endcase
end

always @ (*)
begin
	case(w_auto_cq_irq_retry_cqid)
		4'h0: w_auto_cq_irq_retry_vector = 9'b000000001;
		4'h1: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq1_iv;
		4'h2: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq2_iv;
		4'h3: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq3_iv;
		4'h4: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq4_iv;
		4'h5: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq5_iv;
		4'h6: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq6_iv;
		4'h7: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq7_iv;
		4'h8: w_auto_cq_irq_retry_vector = 9'b000000001 << r_io_cq8_iv;
		default: w_auto_cq_irq_retry_vector = 9'b000000001;
	endcase
end

assign w_bar2_reg_read_data = (r_bar2_addr[17] == 1'b1) ? 32'h0 :
								((r_bar2_addr[16:8] == 9'h0) ? r_cntl_reg_rdata :
								((r_bar2_addr[16:8] == 9'h1) ? r_pcie_reg_rdata :
								((r_bar2_addr[16:8] == 9'h2) ? r_nvme_reg_rdata :
								((r_bar2_addr[16:8] == 9'h3) ? r_nvme_fifo_rdata :
								((r_bar2_addr[16:8] == 9'h4) ? r_auto_reg_rdata : 32'h0)))));
assign w_bar2_bram_read_data = (r_bar2_hcmd_sq_rd_pending == 1) ?
								{1'b1, {(17-P_SLOT_TAG_WIDTH){1'b0}}, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+12)-1:(P_SLOT_TAG_WIDTH+4)], 1'b0, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+4)-1:4], 1'b0, hcmd_sq_rd_data[3:0]} :
								((r_bar2_hcmd_table_rd_pending == 1) ? hcmd_table_rd_data : 32'h0);

always @ (posedge s_axi_aclk)
begin

	r_pcie_link_up <= pcie_link_up;
	r_cfg_command <= cfg_command;
	r_cfg_interrupt_mmenable <= cfg_interrupt_mmenable;
	r_cfg_interrupt_msienable <= cfg_interrupt_msienable;
	r_cfg_interrupt_msixenable <= cfg_interrupt_msixenable;

	r_nvme_cc_en <= nvme_cc_en;
	r_nvme_cc_shn <= nvme_cc_shn;

	r_m0_axi_bresp_err <= m0_axi_bresp_err;
	r_m0_axi_bresp_err_d1 <= r_m0_axi_bresp_err;
	r_m0_axi_bresp_err_d2 <= r_m0_axi_bresp_err_d1;
	r_m0_axi_rresp_err <= m0_axi_rresp_err;
	r_m0_axi_rresp_err_d1 <= r_m0_axi_rresp_err;
	r_m0_axi_rresp_err_d2 <= r_m0_axi_rresp_err_d1;

	r_pcie_mreq_err <= pcie_mreq_err;
	r_pcie_cpld_err <= pcie_cpld_err;
	r_pcie_cpld_len_err <= pcie_cpld_len_err;
end


always @ (posedge s_axi_aclk)
begin
	r_irq_req[0] <= (pcie_link_up ^ r_pcie_link_up);
	r_irq_req[1] <= (cfg_command[2] ^ r_cfg_command[2]);
	r_irq_req[2] <= (cfg_command[3] ^ r_cfg_command[3]);
	r_irq_req[3] <= (cfg_interrupt_msienable ^ r_cfg_interrupt_msienable);
	r_irq_req[4] <= (cfg_interrupt_msixenable ^ r_cfg_interrupt_msixenable);
	r_irq_req[5] <= (nvme_cc_en ^ r_nvme_cc_en);
	r_irq_req[6] <= (nvme_cc_shn != r_nvme_cc_shn);

	r_irq_req[7] <= (r_m0_axi_bresp_err_d1 ^ r_m0_axi_bresp_err_d2);
	r_irq_req[8] <= (r_m0_axi_rresp_err_d1 ^ r_m0_axi_rresp_err_d2);

	r_irq_req[9] <= (pcie_mreq_err ^ r_pcie_mreq_err);
	r_irq_req[10] <= (pcie_cpld_err ^ r_pcie_cpld_err);
	r_irq_req[11] <= (pcie_cpld_len_err ^ r_pcie_cpld_len_err);
	r_irq_assert <= (r_irq_set != 0);
end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0)
		cur_wr_state <= S_WR_IDLE;
	else
		cur_wr_state <= next_wr_state;
end

always @ (*)
begin
	case(cur_wr_state)
		S_WR_IDLE: begin
			if(s_axi_awvalid == 1)
				next_wr_state <= S_AW_VAILD;
			else
				next_wr_state <= S_WR_IDLE;
		end
		S_AW_VAILD: begin
			next_wr_state <= S_W_READY;
		end
		S_W_READY: begin
			if(s_axi_wvalid == 1)
				next_wr_state <= S_B_VALID;
			else
				next_wr_state <= S_W_READY;
		end
		S_B_VALID: begin
			if(s_axi_bready == 1) begin
				if(r_awaddr_hcmd_cq_wr1_en == 1)
					next_wr_state <= S_WAIT_CQ_RDY;
				else if(r_awaddr_dma_cmd_wr_en == 1)
					next_wr_state <= S_WAIT_DMA_RDY;
				else
					next_wr_state <= S_WR_IDLE;
			end
			else
				next_wr_state <= S_B_VALID;
		end
		S_WAIT_CQ_RDY: begin
			if(hcmd_cq_wr1_rdy_n == 1)
				next_wr_state <= S_WAIT_CQ_RDY;
			else
				next_wr_state <= S_WR_CQ;
		end
		S_WR_CQ: begin
			next_wr_state <= S_WR_IDLE;
		end
		S_WAIT_DMA_RDY: begin
			if(dma_cmd_wr_rdy_n == 1)
				next_wr_state <= S_WAIT_DMA_RDY;
			else
				next_wr_state <= S_WR_DMA;
		end
		S_WR_DMA: begin
			if(dma_cmd_wr_rdy_n == 1)
				next_wr_state <= S_WR_DMA;
			else
				next_wr_state <= S_WR_IDLE;
		end
		default: begin
			next_wr_state <= S_WR_IDLE;
		end
	endcase
end

always @ (posedge s_axi_aclk)
begin
	case(cur_wr_state)
		S_WR_IDLE: begin
			r_s_axi_awaddr[15:2] <= s_axi_awaddr[15:2];
		end
		S_AW_VAILD: begin
			r_awaddr_cntl_reg_en <= (r_s_axi_awaddr[15:8] == 8'h0);
//			r_awaddr_pcie_reg_en <= (r_s_axi_awaddr[15:8] == 8'h1);
			r_awaddr_nvme_reg_en <= (r_s_axi_awaddr[15:8] == 8'h2);
			r_awaddr_nvme_fifo_en <= (r_s_axi_awaddr[15:8] == 8'h3);
			r_awaddr_auto_reg_en <= (r_s_axi_awaddr[15:8] == 8'h4);
			r_awaddr_hcmd_cq_wr1_en <= (r_s_axi_awaddr[15:2] == 14'hD0);
			r_awaddr_dma_cmd_wr_en <= (r_s_axi_awaddr[15:2] == 14'hCC); //slot_modified
		end
		S_W_READY: begin
			r_wdata <= s_axi_wdata;
		end
		S_B_VALID: begin

		end
		S_WAIT_CQ_RDY: begin

		end
		S_WR_CQ: begin

		end
		S_WAIT_DMA_RDY: begin

		end
		S_WR_DMA: begin

		end
		default: begin

		end
	endcase
end

always @ (*)
begin
	case(cur_wr_state)
		S_WR_IDLE: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_AW_VAILD: begin
			r_s_axi_awready <= 1;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_W_READY: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 1;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_B_VALID: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 1;
			r_s_axi_bresp <= `D_AXI_RESP_OKAY;
			r_cntl_reg_en <= r_awaddr_cntl_reg_en;
//			r_pcie_reg_en <= r_awaddr_pcie_reg_en;
			r_nvme_reg_en <= r_awaddr_nvme_reg_en;
			r_nvme_fifo_en <= r_awaddr_nvme_fifo_en;
			r_auto_reg_en <= r_awaddr_auto_reg_en;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_WAIT_CQ_RDY: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_WR_CQ: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 1;
			r_dma_cmd_wr_en <= 0;
		end
		S_WAIT_DMA_RDY: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
		S_WR_DMA: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 1;
		end
		default: begin
			r_s_axi_awready <= 0;
			r_s_axi_wready <= 0;
			r_s_axi_bvalid <= 0;
			r_s_axi_bresp <= 0;
			r_cntl_reg_en <= 0;
//			r_pcie_reg_en <= 0;
			r_nvme_reg_en <= 0;
			r_nvme_fifo_en <= 0;
			r_auto_reg_en <= 0;
			r_hcmd_cq_wr1_en <= 0;
			r_dma_cmd_wr_en <= 0;
		end
	endcase
end
always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_dma_ring_state <= S_DMA_RING_IDLE;
		r_dma_ring_head <= 0;
		r_dma_ring_tail <= 0;
		r_dma_ring_cmd_wr_en <= 0;
		r_dma_ring_cmd_wr_data0 <= 0;
		r_dma_ring_cmd_wr_data1 <= 0;
		r_dma_ring_submit_count <= 0;
		r_dma_ring_doorbell_count <= 0;
		r_dma_ring_backpressure_count <= 0;
		r_dma_ring_pid_submit <= 0;
		r_dma_ring_pid_done <= 0;
		r_dma_ring_last_submit_pid <= 0;
		r_dma_ring_last_submit_cid <= 0;
		r_dma_ring_last_done_pid <= 0;
		r_dma_ring_last_done_cid <= 0;
		r_dma_ring_done_count <= 0;
		r_dma_ring_done_pending <= 0;
		r_dma_ring_msi_count <= 0;
		r_dma_ring_msi_threshold <= 1;
		r_dma_ring_msi_since_irq <= 0;
		r_dma_ring_msi_enable <= 0;
		r_dma_ring_msi_vector <= 9'b000000001;
		r_dma_ring_msi_req_toggle <= 0;
		r_bar2_pf0_msi_count <= 0;
		r_bar2_pf0_msi_enable <= 0;
		r_bar2_pf0_msi_vector <= 9'b000000001;
		r_bar2_pf0_msi_req_toggle <= 0;
		r_auto_cq_irq_retry_count <= 0;
		r_auto_cq_irq_retry_last_cqid <= 0;
		r_dma_rx_direct_done_cnt_d <= 0;
		r_dma_tx_direct_done_cnt_d <= 0;
		r_dma_rx_done_cnt_d <= 0;
		r_dma_tx_done_cnt_d <= 0;
	end
	else begin
		r_dma_ring_cmd_wr_en <= 0;
		r_dma_rx_direct_done_cnt_d <= dma_rx_direct_done_cnt;
		r_dma_tx_direct_done_cnt_d <= dma_tx_direct_done_cnt;
		r_dma_rx_done_cnt_d <= dma_rx_done_cnt;
		r_dma_tx_done_cnt_d <= dma_tx_done_cnt;
		r_dma_ring_done_pending <= w_dma_done_pending_next;

		if(w_bar2_dma_ring_wr_en == 1'b1) begin
			case(w_bar2_dma_ring_desc_dw)
				3'd0: r_dma_ring_dw0[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw0[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd1: r_dma_ring_dw1[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw1[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd2: r_dma_ring_dw2[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw2[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd3: r_dma_ring_dw3[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw3[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd4: r_dma_ring_dw4[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw4[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd5: r_dma_ring_dw5[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw5[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
				3'd6: r_dma_ring_dw6[w_bar2_dma_ring_desc_idx] <= f_bar2_apply_be(r_dma_ring_dw6[w_bar2_dma_ring_desc_idx], r_bar2_wdata, r_bar2_be);
			endcase
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h00)) begin
			r_dma_ring_tail <= r_bar2_wdata[P_BAR2_DMA_RING_DESC_WIDTH-1:0];
			r_dma_ring_doorbell_count <= r_dma_ring_doorbell_count + 1;
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h0A)) begin
			r_dma_ring_msi_enable <= r_bar2_wdata[0];
			r_dma_ring_msi_vector <= (r_bar2_wdata[16:8] == 9'b0) ? 9'b000000001 : r_bar2_wdata[16:8];
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h0B)) begin
			r_dma_ring_msi_threshold <= (r_bar2_wdata[15:0] == 16'd0) ? 16'd1 : r_bar2_wdata[15:0];
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h0C) && (r_bar2_wdata[0] == 1'b1) &&
			(r_dma_ring_msi_enable == 1'b1)) begin
			r_dma_ring_msi_req_toggle <= ~r_dma_ring_msi_req_toggle;
			r_dma_ring_msi_count <= r_dma_ring_msi_count + 1;
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h10)) begin
			r_bar2_pf0_msi_enable <= r_bar2_wdata[0];
			r_bar2_pf0_msi_vector <= (r_bar2_wdata[16:8] == 9'b0) ? 9'b000000001 : r_bar2_wdata[16:8];
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h11) && (r_bar2_wdata[0] == 1'b1) &&
			(r_bar2_pf0_msi_enable == 1'b1)) begin
			r_bar2_pf0_msi_req_toggle <= ~r_bar2_pf0_msi_req_toggle;
			r_bar2_pf0_msi_count <= r_bar2_pf0_msi_count + 1;
		end

		if(((r_nvme_cc_en == 1'b1) && (nvme_cc_en == 1'b0)) ||
			((w_auto_reg_en == 1'b1) && (w_reg_wr_addr[7:2] == 6'h01) && (w_reg_wdata[1] == 1'b1))) begin
			r_auto_cq_irq_retry_count <= 0;
			r_auto_cq_irq_retry_last_cqid <= 0;
		end
		else if(w_auto_cq_irq_retry_wr == 1'b1) begin
			r_bar2_pf0_msi_vector <= w_auto_cq_irq_retry_vector;
			r_bar2_pf0_msi_req_toggle <= ~r_bar2_pf0_msi_req_toggle;
			r_auto_cq_irq_retry_count <= r_auto_cq_irq_retry_count + 1;
			r_auto_cq_irq_retry_last_cqid <= w_auto_cq_irq_retry_cqid;
		end

		if((w_bar2_dma_ring_ctrl_wr_en == 1'b1) && (r_bar2_addr[7:2] == 6'h01) && (r_bar2_wdata[0] == 1'b1) &&
			(r_dma_ring_state == S_DMA_RING_IDLE) && (w_dma_ring_inflight == 32'd0)) begin
			r_dma_ring_head <= 0;
			r_dma_ring_tail <= 0;
			r_dma_ring_submit_count <= 0;
			r_dma_ring_doorbell_count <= 0;
			r_dma_ring_backpressure_count <= 0;
			r_dma_ring_pid_submit <= 0;
			r_dma_ring_pid_done <= 0;
			r_dma_ring_last_submit_pid <= 0;
			r_dma_ring_last_submit_cid <= 0;
			r_dma_ring_last_done_pid <= 0;
			r_dma_ring_last_done_cid <= 0;
			r_dma_ring_done_count <= 0;
			r_dma_ring_done_pending <= 0;
			r_dma_ring_msi_count <= 0;
			r_dma_ring_msi_since_irq <= 0;
			r_bar2_pf0_msi_count <= 0;
			r_dma_ring_state <= S_DMA_RING_IDLE;
		end
		else begin
			case(r_dma_ring_state)
				S_DMA_RING_IDLE: begin
					if(w_dma_ring_empty == 1'b0)
						r_dma_ring_state <= S_DMA_RING_WAIT_RDY;
				end
				S_DMA_RING_WAIT_RDY: begin
					if(w_dma_ring_can_submit == 1'b1) begin
						r_dma_ring_cmd_wr_data0 <= {{(13-P_SLOT_TAG_WIDTH){1'b0}}, w_dma_ring_type, w_dma_ring_dir, w_dma_ring_slot_tag, w_dma_ring_dev_len, w_dma_ring_dev_addr};
						r_dma_ring_cmd_wr_data1 <= {{(C_M_AXI_ADDR_WIDTH-32){1'b0}}, w_dma_ring_auto_cpl, w_dma_ring_4k_offset, w_dma_ring_pcie_addr};
						r_dma_ring_cmd_wr_en <= 1;
						r_dma_ring_head <= r_dma_ring_head + 1;
						r_dma_ring_submit_count <= r_dma_ring_submit_count + 1;
						r_dma_ring_pid_cid[r_dma_ring_pid_submit[P_BAR2_DMA_RING_DESC_WIDTH-1:0]] <= {16'b0, w_dma_ring_cid};
						r_dma_ring_last_submit_pid <= r_dma_ring_pid_submit[15:0];
						r_dma_ring_last_submit_cid <= w_dma_ring_cid;
						r_dma_ring_pid_submit <= r_dma_ring_pid_submit + 1;
						r_dma_ring_state <= S_DMA_RING_IDLE;
					end
					else begin
						r_dma_ring_backpressure_count <= r_dma_ring_backpressure_count + 1;
					end
				end
				default: begin
					r_dma_ring_state <= S_DMA_RING_IDLE;
				end
			endcase

			if(w_dma_ring_retire == 1'b1) begin
				r_dma_ring_last_done_pid <= r_dma_ring_pid_done[15:0];
				r_dma_ring_last_done_cid <= r_dma_ring_pid_cid[r_dma_ring_pid_done[P_BAR2_DMA_RING_DESC_WIDTH-1:0]][15:0];
				r_dma_ring_pid_done <= r_dma_ring_pid_done + 1;
				r_dma_ring_done_count <= r_dma_ring_done_count + 1;
				if(w_dma_ring_msi_fire == 1'b1) begin
					r_dma_ring_msi_since_irq <= 0;
					r_dma_ring_msi_req_toggle <= ~r_dma_ring_msi_req_toggle;
					r_dma_ring_msi_count <= r_dma_ring_msi_count + 1;
				end
				else begin
					r_dma_ring_msi_since_irq <= r_dma_ring_msi_since_irq + 1;
				end
			end
		end
	end
end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_bar2_state <= S_BAR2_IDLE;
		r_bar2_wr <= 0;
		r_bar2_addr <= 0;
		r_bar2_wdata <= 0;
		r_bar2_be <= 0;
		r_bar2_hcmd_table_rd_pending <= 0;
		r_bar2_hcmd_sq_rd_pending <= 0;
		bar2_reg_ack <= 0;
		bar2_reg_rdata <= 0;
	end
	else begin
		bar2_reg_ack <= 0;

		case(r_bar2_state)
			S_BAR2_IDLE: begin
				if(bar2_reg_req == 1) begin
					r_bar2_wr <= bar2_reg_wr;
					r_bar2_addr <= bar2_reg_addr[17:2];
					r_bar2_wdata <= bar2_reg_wdata;
					r_bar2_be <= bar2_reg_be;
					r_bar2_hcmd_table_rd_pending <= (bar2_reg_wr == 0) & (bar2_reg_addr[17] == 0) & (bar2_reg_addr[16] == 1'b1);
					r_bar2_hcmd_sq_rd_pending <= (bar2_reg_wr == 0) & (bar2_reg_addr[17] == 0) & (bar2_reg_addr[16:2] == 15'h0C0) & hcmd_sq_empty_n;
					if(bar2_reg_wr == 1)
						r_bar2_state <= S_BAR2_WRITE;
					else
						r_bar2_state <= S_BAR2_READ;
				end
			end
			S_BAR2_WRITE: begin
				if((w_bar2_dma_ring_hit == 1) || (w_bar2_dma_ring_ctrl_hit == 1)) begin
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
				else if(w_bar2_addr_in_range == 0) begin
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
				else if(w_bar2_hcmd_cq_addr == 1) begin
					r_bar2_state <= S_BAR2_WAIT_CQ_RDY;
				end
				else if(w_bar2_dma_cmd_addr == 1) begin
					r_bar2_state <= S_BAR2_WAIT_DMA_RDY;
				end
				else begin
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
			end
			S_BAR2_WAIT_CQ_RDY: begin
				if(hcmd_cq_wr1_rdy_n == 0)
					r_bar2_state <= S_BAR2_WR_CQ;
			end
			S_BAR2_WR_CQ: begin
				bar2_reg_ack <= 1;
				r_bar2_state <= S_BAR2_IDLE;
			end
			S_BAR2_WAIT_DMA_RDY: begin
				if(dma_cmd_wr_rdy_n == 0)
					r_bar2_state <= S_BAR2_WR_DMA;
			end
			S_BAR2_WR_DMA: begin
				bar2_reg_ack <= 1;
				r_bar2_state <= S_BAR2_IDLE;
			end
			S_BAR2_READ: begin
				if(w_bar2_dma_ring_hit == 1) begin
					bar2_reg_rdata <= w_bar2_dma_ring_read_data;
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
				else if(w_bar2_dma_ring_ctrl_hit == 1) begin
					bar2_reg_rdata <= w_bar2_dma_ring_ctrl_rdata;
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
				else if(w_bar2_addr_in_range == 0) begin
					bar2_reg_rdata <= 32'h0;
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
				else if((r_bar2_hcmd_table_rd_pending == 1) || (r_bar2_hcmd_sq_rd_pending == 1)) begin
					r_bar2_state <= S_BAR2_BRAM_READ;
				end
				else begin
					bar2_reg_rdata <= w_bar2_reg_read_data;
					bar2_reg_ack <= 1;
					r_bar2_state <= S_BAR2_IDLE;
				end
			end
			S_BAR2_BRAM_READ: begin
				bar2_reg_rdata <= w_bar2_bram_read_data;
				bar2_reg_ack <= 1;
				r_bar2_state <= S_BAR2_IDLE;
			end
			default: begin
				r_bar2_state <= S_BAR2_IDLE;
			end
		endcase
	end
end



always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_irq_mask <= 0;
	end
	else begin
		if(w_cntl_reg_en == 1) begin
			case(w_reg_wr_addr[7:2]) // synthesis parallel_case
				6'h01: r_irq_mask <= w_reg_wdata[11:0];
			endcase
		end
	end
end

always @ (posedge s_axi_aclk)
begin
	if(w_cntl_reg_en == 1) begin
		case(w_reg_wr_addr[7:2]) // synthesis parallel_case
			6'h00: begin
				r_pcie_user_logic_rst <= w_reg_wdata[0];
				r_irq_clear <= 0;
			end
			6'h02: begin
				r_pcie_user_logic_rst <= 0;
				r_irq_clear <= w_reg_wdata[11:0];
			end
			default: begin
				r_pcie_user_logic_rst <= 0;
				r_irq_clear <= 0;
			end
		endcase
	end
	else begin
		r_pcie_user_logic_rst <= 0;
		r_irq_clear <= 0;
	end

end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_irq_set <= 0;
	end
	else begin
		r_irq_set <= (r_irq_set | r_irq_req) & (~r_irq_clear & r_irq_mask);
	end
end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn) //modified all
begin
	if(s_axi_aresetn == 0) begin
		r_sq_valid <= 0;
		r_cq_valid <= 0;
		r_io_cq_irq_en <= 0;
		r_nvme_csts_shst <= 0;
		r_nvme_csts_rdy <= 0;
	    r_reset_count <= 0;
	end
	else begin
		if((r_nvme_cc_en == 1'b1) && (nvme_cc_en == 1'b0)) begin
			r_sq_valid <= 0;
			r_cq_valid <= 0;
			r_io_cq_irq_en <= 0;
			r_nvme_csts_shst <= 0;
			r_nvme_csts_rdy <= 0;
		end
		else if((w_nvme_reg_en == 1'b1) && (w_reg_wr_addr[7:2] == 6'h00) && (w_reg_wdata[4] == 1'b0)) begin
			r_sq_valid <= 0;
			r_cq_valid <= 0;
			r_io_cq_irq_en <= 0;
			r_reset_count <= w_reg_wdata[10:7];
			r_nvme_csts_shst <= w_reg_wdata[6:5];
			r_nvme_csts_rdy <= w_reg_wdata[4];
		end
		else if(w_nvme_reg_en == 1) begin
			case(w_reg_wr_addr[7:2])
				6'h00: begin
				    r_reset_count <= w_reg_wdata[10:7];
					r_nvme_csts_shst <= w_reg_wdata[6:5];
					r_nvme_csts_rdy <= w_reg_wdata[4];
				end
				6'h07: begin
					r_io_cq_irq_en[0] <= w_reg_wdata[2];
					r_sq_valid[0] <= w_reg_wdata[1];
					r_cq_valid[0] <= w_reg_wdata[0];
				end
				6'h09: begin
					r_sq_valid[1] <= w_reg_wdata[16];
				end
				6'h0B: begin
					r_sq_valid[2] <= w_reg_wdata[16];
				end
				6'h0D: begin
					r_sq_valid[3] <= w_reg_wdata[16];
				end
				6'h0F: begin
					r_sq_valid[4] <= w_reg_wdata[16];
				end
				6'h11: begin
					r_sq_valid[5] <= w_reg_wdata[16];
				end
				6'h13: begin
					r_sq_valid[6] <= w_reg_wdata[16];
				end
				6'h15: begin
					r_sq_valid[7] <= w_reg_wdata[16];
				end
				6'h17: begin
					r_sq_valid[8] <= w_reg_wdata[16];
				end
				6'h19: begin
					r_io_cq_irq_en[1] <= w_reg_wdata[20];
					r_cq_valid[1] <= w_reg_wdata[16];
				end
				6'h1B: begin
					r_io_cq_irq_en[2] <= w_reg_wdata[20];
					r_cq_valid[2] <= w_reg_wdata[16];
				end
				6'h1D: begin
					r_io_cq_irq_en[3] <= w_reg_wdata[20];
					r_cq_valid[3] <= w_reg_wdata[16];
				end
				6'h1F: begin
					r_io_cq_irq_en[4] <= w_reg_wdata[20];
					r_cq_valid[4] <= w_reg_wdata[16];
				end
				6'h21: begin
					r_io_cq_irq_en[5] <= w_reg_wdata[20];
					r_cq_valid[5] <= w_reg_wdata[16];
				end
				6'h23: begin
					r_io_cq_irq_en[6] <= w_reg_wdata[20];
					r_cq_valid[6] <= w_reg_wdata[16];
				end
				6'h25: begin
					r_io_cq_irq_en[7] <= w_reg_wdata[20];
					r_cq_valid[7] <= w_reg_wdata[16];
				end
				6'h27: begin
					r_io_cq_irq_en[8] <= w_reg_wdata[20];
					r_cq_valid[8] <= w_reg_wdata[16];
				end
			endcase
		end
	end
end

always @ (posedge s_axi_aclk) //modified all
begin
	if(w_nvme_reg_en == 1) begin
		case(w_reg_wr_addr[7:2]) // synthesis parallel_case
			6'h08: begin
				r_io_sq1_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h09: begin
				r_io_sq1_size <= w_reg_wdata[31:24];
				r_io_sq1_cq_vec <= w_reg_wdata[20:17];
				r_io_sq1_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h0A: begin
				r_io_sq2_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h0B: begin
				r_io_sq2_size <= w_reg_wdata[31:24];
				r_io_sq2_cq_vec <= w_reg_wdata[20:17];
				r_io_sq2_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h0C: begin
				r_io_sq3_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h0D: begin
				r_io_sq3_size <= w_reg_wdata[31:24];
				r_io_sq3_cq_vec <= w_reg_wdata[20:17];
				r_io_sq3_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h0E: begin
				r_io_sq4_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h0F: begin
				r_io_sq4_size <= w_reg_wdata[31:24];
				r_io_sq4_cq_vec <= w_reg_wdata[20:17];
				r_io_sq4_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h10: begin
				r_io_sq5_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h11: begin
				r_io_sq5_size <= w_reg_wdata[31:24];
				r_io_sq5_cq_vec <= w_reg_wdata[20:17];
				r_io_sq5_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h12: begin
				r_io_sq6_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h13: begin
				r_io_sq6_size <= w_reg_wdata[31:24];
				r_io_sq6_cq_vec <= w_reg_wdata[20:17];
				r_io_sq6_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h14: begin
				r_io_sq7_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h15: begin
				r_io_sq7_size <= w_reg_wdata[31:24];
				r_io_sq7_cq_vec <= w_reg_wdata[20:17];
				r_io_sq7_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h16: begin
				r_io_sq8_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h17: begin
				r_io_sq8_size <= w_reg_wdata[31:24];
				r_io_sq8_cq_vec <= w_reg_wdata[20:17];
				r_io_sq8_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h18: begin
				r_io_cq1_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h19: begin
				r_io_cq1_size <= w_reg_wdata[31:24];
				r_io_cq1_iv <= w_reg_wdata[19:17];
				r_io_cq1_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h1A: begin
				r_io_cq2_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h1B: begin
				r_io_cq2_size <= w_reg_wdata[31:24];
				r_io_cq2_iv <= w_reg_wdata[19:17];
				r_io_cq2_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h1C: begin
				r_io_cq3_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h1D: begin
				r_io_cq3_size <= w_reg_wdata[31:24];
				r_io_cq3_iv <= w_reg_wdata[19:17];
				r_io_cq3_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h1E: begin
				r_io_cq4_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h1F: begin
				r_io_cq4_size <= w_reg_wdata[31:24];
				r_io_cq4_iv <= w_reg_wdata[19:17];
				r_io_cq4_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h20: begin
				r_io_cq5_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h21: begin
				r_io_cq5_size <= w_reg_wdata[31:24];
				r_io_cq5_iv <= w_reg_wdata[19:17];
				r_io_cq5_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h22: begin
				r_io_cq6_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h23: begin
				r_io_cq6_size <= w_reg_wdata[31:24];
				r_io_cq6_iv <= w_reg_wdata[19:17];
				r_io_cq6_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h24: begin
				r_io_cq7_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h25: begin
				r_io_cq7_size <= w_reg_wdata[31:24];
				r_io_cq7_iv <= w_reg_wdata[19:17];
				r_io_cq7_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
			6'h26: begin
				r_io_cq8_bs_addr[31:2] <= w_reg_wdata[31:2];
			end
			6'h27: begin
				r_io_cq8_size <= w_reg_wdata[31:24];
				r_io_cq8_iv <= w_reg_wdata[19:17];
				r_io_cq8_bs_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[15:0];
			end
		endcase
	end
end




always @ (posedge s_axi_aclk)
begin
	if(w_nvme_fifo_en == 1) begin
		case(w_reg_wr_addr[7:2]) // synthesis parallel_case
			6'h01: {r_cpl_sq_qid, r_cpl_cid} <= w_reg_wdata[19:0];
			6'h02: r_cpl_specific <= w_reg_wdata;
			6'h03: {r_cpl_status, r_cql_type, r_hcmd_slot_tag} <= {w_reg_wdata[31:17], w_reg_wdata[15:14], w_reg_wdata[P_SLOT_TAG_WIDTH-1:0]};//slot_modified
			6'h04: r_dma_cmd_dev_addr[31:2] <= w_reg_wdata[31:2];
			6'h05: r_dma_cmd_pcie_addr[C_PCIE_ADDR_WIDTH-1:32] <= w_reg_wdata[C_PCIE_ADDR_WIDTH-1-32:0];
			6'h06: r_dma_cmd_pcie_addr[31:2] <= w_reg_wdata[31:2];
			6'h07: begin //slot_modified
				r_dma_cmd_type <= w_reg_wdata[31];
				r_dma_cmd_dir <= w_reg_wdata[30];
				r_dma_cmd_4k_offset <= w_reg_wdata[22:14];
				r_dma_cmd_auto_cpl <= w_reg_wdata[13];
				r_dma_cmd_dev_len <= w_reg_wdata[12:2];
			end
			6'h08: r_dma_cmd_hcmd_slot_tag <= w_reg_wdata[P_SLOT_TAG_WIDTH-1:0]; //slot_modified
			6'h09: r_dma_cmd_dev_addr[C_M_AXI_ADDR_WIDTH-1:32] <= w_reg_wdata[C_M_AXI_ADDR_WIDTH-1-32:0];
		endcase
	end
end



//////////////////////////////////////////////////////////////////////////////////////

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_auto_ctrl <= 0;
		r_auto_ddr_base <= 0;
		r_auto_ddr_limit <= 0;
		r_auto_io_enable_mask <= 9'h1fe;
		r_auto_pf0_msi_ctrl <= 0;
		r_auto_cq_mode <= 0;
		r_auto_cq_irq_retry_cycles <= 32'h0000_1000;
			r_ssd_model_ctrl <= 0;
			r_ssd_read_lsb_cycles <= 32'd7440;
			r_ssd_read_msb_cycles <= 32'd10440;
			r_ssd_program_cycles <= 32'd46250;
			r_ssd_fw_read_cycles <= 32'd100;
			r_ssd_fw_write_cycles <= 32'd200;
			r_ssd_ch_xfer_4k_cycles <= 32'd808;
			r_ssd_channel_count <= 5'd8;
			r_ssd_model_reset_pulse <= 0;
		r_auto_error_clear <= 0;
		r_auto_reset_pulse <= 0;
	end
	else begin
		r_auto_error_clear <= 0;
		r_auto_reset_pulse <= 0;
		r_ssd_model_reset_pulse <= 0;

		if((r_nvme_cc_en == 1'b1) && (nvme_cc_en == 1'b0)) begin
			r_auto_ctrl <= 0;
			r_auto_error_clear <= 32'hffff_ffff;
			r_auto_reset_pulse <= 1'b1;
				r_ssd_model_reset_pulse <= 1'b1;
		end
		else if(w_auto_reg_en == 1) begin
			case(w_reg_wr_addr[7:2])
				6'h01: begin
					r_auto_ctrl <= w_reg_wdata & 32'hffff_fffd;
					r_auto_reset_pulse <= w_reg_wdata[1];
				end
				6'h03: r_auto_error_clear <= w_reg_wdata;
				6'h04: r_auto_ddr_base[31:0] <= w_reg_wdata;
				6'h05: r_auto_ddr_base[C_M_AXI_ADDR_WIDTH-1:32] <= w_reg_wdata[C_M_AXI_ADDR_WIDTH-33:0];
				6'h06: r_auto_ddr_limit[31:0] <= w_reg_wdata;
				6'h07: r_auto_ddr_limit[C_M_AXI_ADDR_WIDTH-1:32] <= w_reg_wdata[C_M_AXI_ADDR_WIDTH-33:0];
				6'h08: r_auto_io_enable_mask <= w_reg_wdata[8:0];
				6'h09: r_auto_pf0_msi_ctrl <= w_reg_wdata;
				6'h0A: r_auto_cq_mode <= w_reg_wdata;
				6'h18: r_auto_cq_irq_retry_cycles <= w_reg_wdata;
					6'h19: begin r_ssd_model_ctrl <= w_reg_wdata & 32'hffff_fffd; r_ssd_model_reset_pulse <= w_reg_wdata[1]; end
					6'h1A: r_ssd_read_lsb_cycles <= w_reg_wdata;
					6'h1B: r_ssd_read_msb_cycles <= w_reg_wdata;
					6'h1C: r_ssd_program_cycles <= w_reg_wdata;
					6'h1D: r_ssd_fw_read_cycles <= w_reg_wdata;
					6'h1E: r_ssd_fw_write_cycles <= w_reg_wdata;
					6'h1F: r_ssd_ch_xfer_4k_cycles <= w_reg_wdata;
					6'h23: begin
						case(w_reg_wdata[4:0])
						5'd1, 5'd2, 5'd4, 5'd8, 5'd16:
							r_ssd_channel_count <= w_reg_wdata[4:0];
						default: r_ssd_channel_count <= 5'd8;
						endcase
					end
			endcase
		end
	end
end


always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0)
		cur_rd_state <= S_RD_IDLE;
	else
		cur_rd_state <= next_rd_state;
end

always @ (*)
begin
	case(cur_rd_state)
		S_RD_IDLE: begin
			if(s_axi_arvalid == 1)
				next_rd_state <= S_AR_VAILD;
			else
				next_rd_state <= S_RD_IDLE;
		end
		S_AR_VAILD: begin
			next_rd_state <= S_AR_REG;
		end
		S_AR_REG: begin
			if(r_araddr_hcmd_sq_rd_en == 1 || r_araddr_hcmd_table_rd_en == 1)
				next_rd_state <= S_BRAM_READ;
			else
				next_rd_state <= S_R_READY;
		end
		S_BRAM_READ: begin
			next_rd_state <= S_R_READY;
		end
		S_R_READY: begin
			if(s_axi_rready == 1)
				next_rd_state <= S_RD_IDLE;
			else
				next_rd_state <= S_R_READY;
		end
		default: begin
			next_rd_state <= S_RD_IDLE;
		end
	endcase
end

always @ (posedge s_axi_aclk)
begin
	case(cur_rd_state)
		S_RD_IDLE: begin
			r_s_axi_araddr <= s_axi_araddr[16:2];
		end
		S_AR_VAILD: begin
			r_araddr_cntl_reg_en <= (r_s_axi_araddr[16:8] == 9'h0);
			r_araddr_pcie_reg_en <= (r_s_axi_araddr[16:8] == 9'h1);
			r_araddr_nvme_reg_en <= (r_s_axi_araddr[16:8] == 9'h2);
			r_araddr_nvme_fifo_en <= (r_s_axi_araddr[16:8] == 9'h3);
			r_araddr_auto_reg_en <= (r_s_axi_araddr[16:8] == 9'h4);
			r_araddr_hcmd_table_rd_en <= (r_s_axi_araddr[16] == 1'b1); //slot_modified
			r_araddr_hcmd_sq_rd_en <= (r_s_axi_araddr[16:2] == 15'hC0) & hcmd_sq_empty_n;
		end
		S_AR_REG: begin
			case({r_araddr_auto_reg_en, r_araddr_nvme_fifo_en, r_araddr_nvme_reg_en, r_araddr_pcie_reg_en, r_araddr_cntl_reg_en}) // synthesis parallel_case full_case
				5'b00001: r_rdata <= r_cntl_reg_rdata;
				5'b00010: r_rdata <= r_pcie_reg_rdata;
				5'b00100: r_rdata <= r_nvme_reg_rdata;
				5'b01000: r_rdata <= r_nvme_fifo_rdata;
				5'b10000: r_rdata <= r_auto_reg_rdata;
			endcase
		end
		S_BRAM_READ: begin
			case({r_araddr_hcmd_table_rd_en, r_araddr_hcmd_sq_rd_en})  // synthesis parallel_case full_case
				2'b01: r_rdata <= {1'b1, {(17-P_SLOT_TAG_WIDTH){1'b0}}, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+12)-1:(P_SLOT_TAG_WIDTH+4)], 1'b0, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+4)-1:4], 1'b0, hcmd_sq_rd_data[3:0]};//slot_modified
				2'b10: r_rdata <= hcmd_table_rd_data;
			endcase
		end
		S_R_READY: begin

		end
		default: begin

		end
	endcase
end

always @ (*)
begin
	case(cur_rd_state)
		S_RD_IDLE: begin
			r_s_axi_arready <= 0;
			r_s_axi_rvalid <= 0;
			r_s_axi_rdata <= 0;
			r_s_axi_rresp <= 0;
			r_hcmd_sq_rd_en <= 0;
		end
		S_AR_VAILD: begin
			r_s_axi_arready <= 1;
			r_s_axi_rvalid <= 0;
			r_s_axi_rdata <= 0;
			r_s_axi_rresp <= 0;
			r_hcmd_sq_rd_en <= 0;
		end
		S_AR_REG: begin
			r_s_axi_arready <= 0;
			r_s_axi_rvalid <= 0;
			r_s_axi_rdata <= 0;
			r_s_axi_rresp <= 0;
			r_hcmd_sq_rd_en <= 0;
		end
		S_BRAM_READ: begin
			r_s_axi_arready <= 0;
			r_s_axi_rvalid <= 0;
			r_s_axi_rdata <= 0;
			r_s_axi_rresp <= 0;
			r_hcmd_sq_rd_en <= r_araddr_hcmd_sq_rd_en;
		end
		S_R_READY: begin
			r_s_axi_arready <= 0;
			r_s_axi_rvalid <= 1;
			r_s_axi_rdata <= r_rdata;
			r_s_axi_rresp <= `D_AXI_RESP_OKAY;
			r_hcmd_sq_rd_en <= 0;
		end
		default: begin
			r_s_axi_arready <= 0;
			r_s_axi_rvalid <= 0;
			r_s_axi_rdata <= 0;
			r_s_axi_rresp <= 0;
			r_hcmd_sq_rd_en <= 0;
		end
	endcase
end

always @ (*)
begin
	r_cntl_reg_rdata = 32'h0;
	case(w_reg_rd_addr[7:2]) // synthesis parallel_case full_case
		6'h01: r_cntl_reg_rdata = {20'b0, r_irq_mask};
		6'h03: r_cntl_reg_rdata = {20'b0, r_irq_set};
	endcase
end

always @ (*)
begin
	r_pcie_reg_rdata = 32'h0;
	case(w_reg_rd_addr[7:2]) // synthesis parallel_case full_case
		6'h00: r_pcie_reg_rdata = {23'b0, r_pcie_link_up, 2'b0, pl_ltssm_state};
		6'h01: r_pcie_reg_rdata = {25'b0, r_cfg_interrupt_mmenable, ~r_cfg_command[3], r_cfg_interrupt_msixenable, r_cfg_interrupt_msienable, r_cfg_command[2]};
	endcase
end

always @ (*)
begin
	r_nvme_reg_rdata = 32'h0;
	case(w_reg_rd_addr[7:2]) //modified all
		6'h00: r_nvme_reg_rdata = {25'b0, r_nvme_csts_shst, r_nvme_csts_rdy, 1'b0, r_nvme_cc_shn, r_nvme_cc_en};
		6'h01: r_nvme_reg_rdata = {dma_tx_done_cnt, dma_rx_done_cnt, dma_tx_direct_done_cnt, dma_rx_direct_done_cnt};
		6'h07: r_nvme_reg_rdata = {19'b0, r_io_cq_irq_en[0], r_sq_valid[0], r_cq_valid[0]};
		6'h08: r_nvme_reg_rdata = {r_io_sq1_bs_addr[31:2], 2'b0};
		6'h09: r_nvme_reg_rdata = {r_io_sq1_size, 3'b0, r_io_sq1_cq_vec, r_sq_valid[1], r_io_sq1_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h0A: r_nvme_reg_rdata = {r_io_sq2_bs_addr[31:2], 2'b0};
		6'h0B: r_nvme_reg_rdata = {r_io_sq2_size, 3'b0, r_io_sq2_cq_vec, r_sq_valid[2], r_io_sq2_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h0C: r_nvme_reg_rdata = {r_io_sq3_bs_addr[31:2], 2'b0};
		6'h0D: r_nvme_reg_rdata = {r_io_sq3_size, 3'b0, r_io_sq3_cq_vec, r_sq_valid[3], r_io_sq3_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h0E: r_nvme_reg_rdata = {r_io_sq4_bs_addr[31:2], 2'b0};
		6'h0F: r_nvme_reg_rdata = {r_io_sq4_size, 3'b0, r_io_sq4_cq_vec, r_sq_valid[4], r_io_sq4_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h10: r_nvme_reg_rdata = {r_io_sq5_bs_addr[31:2], 2'b0};
		6'h11: r_nvme_reg_rdata = {r_io_sq5_size, 3'b0, r_io_sq5_cq_vec, r_sq_valid[5], r_io_sq5_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h12: r_nvme_reg_rdata = {r_io_sq6_bs_addr[31:2], 2'b0};
		6'h13: r_nvme_reg_rdata = {r_io_sq6_size, 3'b0, r_io_sq6_cq_vec, r_sq_valid[6], r_io_sq6_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h14: r_nvme_reg_rdata = {r_io_sq7_bs_addr[31:2], 2'b0};
		6'h15: r_nvme_reg_rdata = {r_io_sq7_size, 3'b0, r_io_sq7_cq_vec, r_sq_valid[7], r_io_sq7_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h16: r_nvme_reg_rdata = {r_io_sq8_bs_addr[31:2], 2'b0};
		6'h17: r_nvme_reg_rdata = {r_io_sq8_size, 3'b0, r_io_sq8_cq_vec, r_sq_valid[8], r_io_sq8_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h18: r_nvme_reg_rdata = {r_io_cq1_bs_addr[31:2], 2'b0};
		6'h19: r_nvme_reg_rdata = {r_io_cq1_size, 3'b0, r_io_cq_irq_en[1], r_io_cq1_iv, r_cq_valid[1], r_io_cq1_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h1A: r_nvme_reg_rdata = {r_io_cq2_bs_addr[31:2], 2'b0};
		6'h1B: r_nvme_reg_rdata = {r_io_cq2_size, 3'b0, r_io_cq_irq_en[2], r_io_cq2_iv, r_cq_valid[2], r_io_cq2_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h1C: r_nvme_reg_rdata = {r_io_cq3_bs_addr[31:2], 2'b0};
		6'h1D: r_nvme_reg_rdata = {r_io_cq3_size, 3'b0, r_io_cq_irq_en[3], r_io_cq3_iv, r_cq_valid[3], r_io_cq3_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h1E: r_nvme_reg_rdata = {r_io_cq4_bs_addr[31:2], 2'b0};
		6'h1F: r_nvme_reg_rdata = {r_io_cq4_size, 3'b0, r_io_cq_irq_en[4], r_io_cq4_iv, r_cq_valid[4], r_io_cq4_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h20: r_nvme_reg_rdata = {r_io_cq5_bs_addr[31:2], 2'b0};
		6'h21: r_nvme_reg_rdata = {r_io_cq5_size, 3'b0, r_io_cq_irq_en[5], r_io_cq5_iv, r_cq_valid[5], r_io_cq5_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h22: r_nvme_reg_rdata = {r_io_cq6_bs_addr[31:2], 2'b0};
		6'h23: r_nvme_reg_rdata = {r_io_cq6_size, 3'b0, r_io_cq_irq_en[6], r_io_cq6_iv, r_cq_valid[6], r_io_cq6_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h24: r_nvme_reg_rdata = {r_io_cq7_bs_addr[31:2], 2'b0};
		6'h25: r_nvme_reg_rdata = {r_io_cq7_size, 3'b0, r_io_cq_irq_en[7], r_io_cq7_iv, r_cq_valid[7], r_io_cq7_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
		6'h26: r_nvme_reg_rdata = {r_io_cq8_bs_addr[31:2], 2'b0};
		6'h27: r_nvme_reg_rdata = {r_io_cq8_size, 3'b0, r_io_cq_irq_en[8], r_io_cq8_iv, r_cq_valid[8], r_io_cq8_bs_addr[C_PCIE_ADDR_WIDTH-1:32]};
	endcase
end

always @ (*)
begin
	r_nvme_fifo_rdata = 32'h0;
	case(w_reg_rd_addr[7:2]) // synthesis parallel_case full_case
		6'h00: r_nvme_fifo_rdata = 0;
		6'h01: r_nvme_fifo_rdata = {12'b0, r_cpl_sq_qid, r_cpl_cid};
		6'h02: r_nvme_fifo_rdata = r_cpl_specific;
		6'h03: r_nvme_fifo_rdata = {r_cpl_status, 1'b0, r_cql_type, {(14-P_SLOT_TAG_WIDTH){1'b0}}, r_hcmd_slot_tag};
		6'h04: r_nvme_fifo_rdata = {r_dma_cmd_dev_addr[31:2], 2'b0};
		6'h05: r_nvme_fifo_rdata = {16'b0, r_dma_cmd_pcie_addr[C_PCIE_ADDR_WIDTH-1:32]}; //modified
		6'h06: r_nvme_fifo_rdata = {r_dma_cmd_pcie_addr[31:2], 2'b0};
		6'h07: r_nvme_fifo_rdata = {r_dma_cmd_type, r_dma_cmd_dir, 7'b0, r_dma_cmd_4k_offset, r_dma_cmd_auto_cpl, r_dma_cmd_dev_len, 2'b0};
		6'h08: r_nvme_fifo_rdata = {{(32-P_SLOT_TAG_WIDTH){1'b0}}, r_dma_cmd_hcmd_slot_tag}; //slot_modified
		6'h09: r_nvme_fifo_rdata = {{(64-C_M_AXI_ADDR_WIDTH){1'b0}}, r_dma_cmd_dev_addr[C_M_AXI_ADDR_WIDTH-1:32]};
		6'h11: r_nvme_fifo_rdata = {hcmd_sq_empty_n, {(17-P_SLOT_TAG_WIDTH){1'b0}}, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+12)-1:(P_SLOT_TAG_WIDTH+4)], 1'b0, hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+4)-1:4], 1'b0, hcmd_sq_rd_data[3:0]};
	endcase
end

always @ (*)
begin
	r_auto_reg_rdata = 32'h0;
	case(w_reg_rd_addr[7:2]) // synthesis parallel_case full_case
		6'h00: r_auto_reg_rdata = 32'ha710_f001;
		6'h01: r_auto_reg_rdata = r_auto_ctrl;
		6'h02: r_auto_reg_rdata = auto_status;
		6'h03: r_auto_reg_rdata = auto_error;
		6'h04: r_auto_reg_rdata = r_auto_ddr_base[31:0];
		6'h05: r_auto_reg_rdata = {{(64-C_M_AXI_ADDR_WIDTH){1'b0}}, r_auto_ddr_base[C_M_AXI_ADDR_WIDTH-1:32]};
		6'h06: r_auto_reg_rdata = r_auto_ddr_limit[31:0];
		6'h07: r_auto_reg_rdata = {{(64-C_M_AXI_ADDR_WIDTH){1'b0}}, r_auto_ddr_limit[C_M_AXI_ADDR_WIDTH-1:32]};
		6'h08: r_auto_reg_rdata = {23'b0, r_auto_io_enable_mask};
		6'h09: r_auto_reg_rdata = r_auto_pf0_msi_ctrl;
		6'h0A: r_auto_reg_rdata = r_auto_cq_mode;
		6'h0C: r_auto_reg_rdata = auto_cmd_count;
		6'h0D: r_auto_reg_rdata = auto_dma_submit_count;
		6'h0E: r_auto_reg_rdata = {16'h0, dma_tx_done_cnt, dma_rx_done_cnt};
		6'h0F: r_auto_reg_rdata = cq_dbg_write_count;
		6'h10: r_auto_reg_rdata = cq_dbg_last_dw3;
		6'h11: r_auto_reg_rdata = auto_unsupported_count;
		6'h12: r_auto_reg_rdata = auto_last_qid_slot;
		6'h13: r_auto_reg_rdata = auto_last_opcode;
		6'h14: r_auto_reg_rdata = auto_last_error_info;
		6'h15: r_auto_reg_rdata = cq_dbg_last_dw2;
		6'h16: r_auto_reg_rdata = {r_auto_cq_irq_retry_count[15:0], 12'b0, r_auto_cq_irq_retry_last_cqid};
		6'h18: r_auto_reg_rdata = r_auto_cq_irq_retry_cycles;
			6'h19: r_auto_reg_rdata = r_ssd_model_ctrl;
			6'h1A: r_auto_reg_rdata = r_ssd_read_lsb_cycles;
			6'h1B: r_auto_reg_rdata = r_ssd_read_msb_cycles;
			6'h1C: r_auto_reg_rdata = r_ssd_program_cycles;
			6'h1D: r_auto_reg_rdata = r_ssd_fw_read_cycles;
			6'h1E: r_auto_reg_rdata = r_ssd_fw_write_cycles;
			6'h1F: r_auto_reg_rdata = r_ssd_ch_xfer_4k_cycles;
			6'h20: r_auto_reg_rdata = ssd_model_status;
			6'h21: r_auto_reg_rdata = ssd_model_submit_count;
			6'h22: r_auto_reg_rdata = ssd_model_release_count;
			6'h23: r_auto_reg_rdata = {27'b0, r_ssd_channel_count};
	endcase
end

endmodule
