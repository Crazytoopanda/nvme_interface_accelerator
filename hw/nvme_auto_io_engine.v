/*
----------------------------------------------------------------------------------
Copyright (c) 2013-2014

  Embedded and Network Computing Lab.
  Hanyang University

All rights reserved.

----------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps

module nvme_auto_io_engine # (
	parameter	P_SLOT_TAG_WIDTH			= 10,
	parameter	C_M_AXI_ADDR_WIDTH			= 64,
	parameter	C_PCIE_ADDR_WIDTH			= 48
)
(
	input									clk,
	input									rst_n,

	input									auto_enable,
	input									auto_reset,
	input									auto_io_read_enable,
	input									auto_io_write_enable,
	input									auto_cq_enable,
	input									auto_msi_enable,
	input	[31:0]							auto_cq_mode,
	input	[C_M_AXI_ADDR_WIDTH-1:0]		auto_ddr_base,
	input	[C_M_AXI_ADDR_WIDTH-1:0]		auto_ddr_limit,
	input	[8:0]							auto_io_enable_mask,
	input	[31:0]							auto_error_clear,
	input									model_enable,

	output									hcmd_sq_rd_en,
	input	[(P_SLOT_TAG_WIDTH+12)-1:0]		hcmd_sq_rd_data,
	input									hcmd_sq_empty_n,

	output									hcmd_table_rd_active,
	output	[(P_SLOT_TAG_WIDTH+2)+1:0]		hcmd_table_rd_addr,
	input	[31:0]							hcmd_table_rd_data,

	output									dma_cmd_wr_en,
	output	[C_M_AXI_ADDR_WIDTH+23:0]		dma_cmd_wr_data0,
	output	[C_M_AXI_ADDR_WIDTH+23:0]		dma_cmd_wr_data1,
	input									dma_cmd_wr_rdy_n,

	output									model_cmd_wr_en,
	output	[63:0]						model_cmd_wr_data0,
	output	[63:0]						model_cmd_wr_data1,
	input									model_cmd_wr_rdy_n,

	output	[31:0]							auto_status,
	output	[31:0]							auto_error,
	output	[31:0]							auto_cmd_count,
	output	[31:0]							auto_dma_submit_count,
	output	[31:0]							auto_unsupported_count,
	output	[31:0]							auto_last_qid_slot,
	output	[31:0]							auto_last_opcode,
	output	[31:0]							auto_last_error_info
);

localparam	S_IDLE							= 5'd0;
localparam	S_POP							= 5'd1;
localparam	S_OPCODE_ADDR					= 5'd2;
localparam	S_OPCODE_WAIT					= 5'd3;
localparam	S_OPCODE_DECODE				= 5'd4;
localparam	S_NLB_ADDR						= 5'd5;
localparam	S_NLB_WAIT						= 5'd6;
localparam	S_NLB_DECODE					= 5'd7;
localparam	S_SLBA_LO_ADDR				= 5'd8;
localparam	S_SLBA_LO_WAIT				= 5'd9;
localparam	S_SLBA_LO_CAPTURE			= 5'd10;
localparam	S_SLBA_HI_ADDR				= 5'd11;
localparam	S_SLBA_HI_WAIT				= 5'd12;
localparam	S_SLBA_HI_CAPTURE			= 5'd13;
localparam	S_RANGE_CHECK				= 5'd14;
localparam	S_SUBMIT						= 5'd15;
localparam	S_NEXT_SEG					= 5'd16;
localparam	S_ERROR							= 5'd17;

localparam	DMA_TYPE_AUTO				= 1'b0;
localparam	DMA_DIR_RX					= 1'b0;
localparam	DMA_DIR_TX					= 1'b1;
localparam	[12:2] DMA_LEN_4K			= 11'h400;
localparam	[31:0] AUTO_CQ_MODE_HW		= 32'h00000000;
localparam	LP_LBA_WIDTH				= C_M_AXI_ADDR_WIDTH - 12;

localparam	ERR_ADMIN_OR_MASKED_QID		= 32'h00000001;
localparam	ERR_UNSUPPORTED_OPCODE		= 32'h00000002;
localparam	ERR_DISABLED_OPCODE			= 32'h00000004;
localparam	ERR_DDR_RANGE				= 32'h00000008;
localparam	ERR_AUTO_CQ_DISABLED		= 32'h00000010;
localparam	ERR_CQ_MODE_UNSUPPORTED		= 32'h00000020;
localparam	ERR_NLB_TOO_LARGE			= 32'h00000040;

reg		[4:0]							cur_state;
reg		[4:0]							next_state;

reg		[3:0]							r_sq_qid;
reg		[P_SLOT_TAG_WIDTH-1:0]			r_hcmd_slot_tag;
reg		[7:0]							r_hcmd_seq;
reg		[7:0]							r_opcode;
reg		[8:0]							r_total_segments;
reg		[8:0]							r_segment_index;
reg		[31:0]							r_slba_lo;
reg		[31:0]							r_slba_hi;
reg									r_dma_dir;
reg		[31:0]							r_decode_error;
reg									r_dma_stalled;
reg									r_unsupported_pending;
reg									r_last_segment;

reg		[31:0]							r_auto_error;
reg		[31:0]							r_cmd_count;
reg		[31:0]							r_dma_submit_count;
reg		[31:0]							r_unsupported_count;
reg		[31:0]							r_last_qid_slot;
reg		[31:0]							r_last_opcode;
reg		[31:0]							r_last_error_info;

wire									w_reset;
wire									w_idle;
wire									w_busy;
wire	[7:0]							w_table_opcode;
wire	[15:0]						w_table_nlb;
wire	[8:0]							w_table_segments;
wire									w_qid_enabled;
wire									w_read_cmd;
wire									w_write_cmd;
wire									w_opcode_enabled;
wire									w_nlb_supported;
wire									w_cq_mode_supported;
wire									w_cmd_range_ok;
wire	[31:0]						w_opcode_decode_error;
wire	[31:0]						w_nlb_decode_error;
wire	[31:0]						w_range_decode_error;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]		w_opcode_rd_addr;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]		w_nlb_rd_addr;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]		w_slba_lo_rd_addr;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]		w_slba_hi_rd_addr;
wire	[63:0]						w_start_lba;
wire	[63:0]						w_segment_lba;
wire	[63:0]						w_last_lba;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_start_byte_offset;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_last_byte_offset;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_segment_byte_offset;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_start_dev_addr;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_last_dev_addr;
wire	[C_M_AXI_ADDR_WIDTH-1:0]		w_segment_dev_addr;
wire									w_lba_fits;
wire									w_submit_fire;
wire									w_model_first;
wire									w_submit_blocked;
wire									w_final_auto_cpl;
wire	[3:0]								w_head_sq_qid;
wire									w_head_qid_enabled;
wire									w_opcode_addr_phase;
wire									w_nlb_addr_phase;
wire									w_slba_lo_addr_phase;
wire									w_slba_hi_addr_phase;

assign w_reset = (rst_n == 1'b0) | auto_reset;
assign w_idle = (cur_state == S_IDLE);
assign w_busy = (cur_state != S_IDLE) && (cur_state != S_ERROR);
assign w_table_opcode = hcmd_table_rd_data[7:0];
assign w_table_nlb = hcmd_table_rd_data[15:0];
assign w_table_segments = {1'b0, w_table_nlb[7:0]} + 9'd1;
assign w_qid_enabled = (r_sq_qid != 4'h0) && (r_sq_qid <= 4'h8) && auto_io_enable_mask[r_sq_qid];
assign w_read_cmd = (w_table_opcode == 8'h02);
assign w_write_cmd = (w_table_opcode == 8'h01);
assign w_opcode_enabled = (w_read_cmd & auto_io_read_enable) | (w_write_cmd & auto_io_write_enable);
assign w_nlb_supported = (w_table_nlb[15:8] == 8'h00);
assign w_cq_mode_supported = (auto_cq_mode == AUTO_CQ_MODE_HW);
assign w_start_lba = {r_slba_hi, r_slba_lo};
assign w_segment_lba = w_start_lba + {55'b0, r_segment_index};
assign w_last_lba = w_start_lba + {55'b0, r_total_segments} - 64'd1;
assign w_lba_fits = (w_start_lba[63:LP_LBA_WIDTH] == 0) && (w_last_lba[63:LP_LBA_WIDTH] == 0);
assign w_start_byte_offset = {w_start_lba[LP_LBA_WIDTH-1:0], 12'b0};
assign w_last_byte_offset = {w_last_lba[LP_LBA_WIDTH-1:0], 12'hfff};
assign w_segment_byte_offset = {w_segment_lba[LP_LBA_WIDTH-1:0], 12'b0};
assign w_start_dev_addr = auto_ddr_base + w_start_byte_offset;
assign w_last_dev_addr = auto_ddr_base + w_last_byte_offset;
assign w_segment_dev_addr = auto_ddr_base + w_segment_byte_offset;
assign w_cmd_range_ok = (auto_ddr_limit >= auto_ddr_base) && w_lba_fits &&
						(w_start_dev_addr >= auto_ddr_base) &&
						(w_last_dev_addr >= w_start_dev_addr) &&
						(w_last_dev_addr <= auto_ddr_limit);
assign w_opcode_decode_error = (w_qid_enabled == 1'b0) ? ERR_ADMIN_OR_MASKED_QID :
								((w_read_cmd | w_write_cmd) == 1'b0) ? ERR_UNSUPPORTED_OPCODE :
								(w_opcode_enabled == 1'b0) ? ERR_DISABLED_OPCODE :
								(auto_cq_enable == 1'b0) ? ERR_AUTO_CQ_DISABLED :
								(w_cq_mode_supported == 1'b0) ? ERR_CQ_MODE_UNSUPPORTED :
								32'h00000000;
assign w_nlb_decode_error = (w_nlb_supported == 1'b0) ? ERR_NLB_TOO_LARGE : 32'h00000000;
assign w_range_decode_error = (w_cmd_range_ok == 1'b0) ? ERR_DDR_RANGE : 32'h00000000;
assign w_opcode_rd_addr = {r_hcmd_slot_tag, 4'h0};
assign w_slba_lo_rd_addr = {r_hcmd_slot_tag, 4'ha};
assign w_slba_hi_rd_addr = {r_hcmd_slot_tag, 4'hb};
assign w_nlb_rd_addr = {r_hcmd_slot_tag, 4'hc};
assign w_model_first = model_enable & (r_segment_index == 0);
assign w_submit_blocked = dma_cmd_wr_rdy_n | (w_model_first & model_cmd_wr_rdy_n);
assign w_submit_fire = (cur_state == S_SUBMIT) & ~w_submit_blocked;
assign w_final_auto_cpl = r_last_segment & auto_cq_enable & (auto_cq_mode == AUTO_CQ_MODE_HW);
assign w_head_sq_qid = hcmd_sq_rd_data[3:0];
assign w_head_qid_enabled = (w_head_sq_qid != 4'h0) && (w_head_sq_qid <= 4'h8) &&
								auto_io_enable_mask[w_head_sq_qid];
assign w_opcode_addr_phase = (cur_state == S_OPCODE_ADDR) | (cur_state == S_OPCODE_WAIT) | (cur_state == S_OPCODE_DECODE);
assign w_nlb_addr_phase = (cur_state == S_NLB_ADDR) | (cur_state == S_NLB_WAIT) | (cur_state == S_NLB_DECODE);
assign w_slba_lo_addr_phase = (cur_state == S_SLBA_LO_ADDR) | (cur_state == S_SLBA_LO_WAIT) | (cur_state == S_SLBA_LO_CAPTURE);
assign w_slba_hi_addr_phase = (cur_state == S_SLBA_HI_ADDR) | (cur_state == S_SLBA_HI_WAIT) | (cur_state == S_SLBA_HI_CAPTURE);

assign hcmd_sq_rd_en = (cur_state == S_POP);
assign hcmd_table_rd_active = w_opcode_addr_phase | w_nlb_addr_phase | w_slba_lo_addr_phase | w_slba_hi_addr_phase;
assign hcmd_table_rd_addr = (w_nlb_addr_phase == 1'b1) ? w_nlb_rd_addr :
							(w_slba_lo_addr_phase == 1'b1) ? w_slba_lo_rd_addr :
							(w_slba_hi_addr_phase == 1'b1) ? w_slba_hi_rd_addr : w_opcode_rd_addr;

assign dma_cmd_wr_en = w_submit_fire;
assign dma_cmd_wr_data0 = {{(13-P_SLOT_TAG_WIDTH){1'b0}}, DMA_TYPE_AUTO, r_dma_dir,
						   r_hcmd_slot_tag, DMA_LEN_4K, w_segment_dev_addr[C_M_AXI_ADDR_WIDTH-1:2]};
assign dma_cmd_wr_data1 = {{(C_M_AXI_ADDR_WIDTH-32){1'b0}}, w_final_auto_cpl, r_segment_index,
						   {C_PCIE_ADDR_WIDTH-2{1'b0}}};
assign model_cmd_wr_en = w_submit_fire & w_model_first;
assign model_cmd_wr_data0 = w_start_lba;
assign model_cmd_wr_data1 = {44'b0, (r_dma_dir == DMA_DIR_RX), r_total_segments, r_hcmd_slot_tag};

assign auto_status = {7'b0, cur_state, 2'b0, auto_msi_enable, w_busy, 5'b0,
					 r_dma_stalled, r_unsupported_pending, (r_auto_error != 32'h0),
					 6'b0, w_idle, auto_enable};
assign auto_error = r_auto_error;
assign auto_cmd_count = r_cmd_count;
assign auto_dma_submit_count = r_dma_submit_count;
assign auto_unsupported_count = r_unsupported_count;
assign auto_last_qid_slot = r_last_qid_slot;
assign auto_last_opcode = r_last_opcode;
assign auto_last_error_info = r_last_error_info;

always @ (posedge clk or negedge rst_n)
begin
	if(rst_n == 1'b0)
		cur_state <= S_IDLE;
	else if(auto_reset == 1'b1)
		cur_state <= S_IDLE;
	else
		cur_state <= next_state;
end

always @ (*)
begin
	case(cur_state)
		S_IDLE: begin
			if((auto_enable == 1'b1) && (r_unsupported_pending == 1'b0) &&
			   (hcmd_sq_empty_n == 1'b1) && (w_head_qid_enabled == 1'b1))
				next_state <= S_POP;
			else
				next_state <= S_IDLE;
		end
		S_POP: begin
			next_state <= S_OPCODE_ADDR;
		end
		S_OPCODE_ADDR: begin
			next_state <= S_OPCODE_WAIT;
		end
		S_OPCODE_WAIT: begin
			next_state <= S_OPCODE_DECODE;
		end
		S_OPCODE_DECODE: begin
			if(w_opcode_decode_error == 32'h0)
				next_state <= S_NLB_ADDR;
			else
				next_state <= S_ERROR;
		end
		S_NLB_ADDR: begin
			next_state <= S_NLB_WAIT;
		end
		S_NLB_WAIT: begin
			next_state <= S_NLB_DECODE;
		end
		S_NLB_DECODE: begin
			if(w_nlb_decode_error == 32'h0)
				next_state <= S_SLBA_LO_ADDR;
			else
				next_state <= S_ERROR;
		end
		S_SLBA_LO_ADDR: begin
			next_state <= S_SLBA_LO_WAIT;
		end
		S_SLBA_LO_WAIT: begin
			next_state <= S_SLBA_LO_CAPTURE;
		end
		S_SLBA_LO_CAPTURE: begin
			next_state <= S_SLBA_HI_ADDR;
		end
		S_SLBA_HI_ADDR: begin
			next_state <= S_SLBA_HI_WAIT;
		end
		S_SLBA_HI_WAIT: begin
			next_state <= S_SLBA_HI_CAPTURE;
		end
		S_SLBA_HI_CAPTURE: begin
			next_state <= S_RANGE_CHECK;
		end
		S_RANGE_CHECK: begin
			if(w_range_decode_error == 32'h0)
				next_state <= S_SUBMIT;
			else
				next_state <= S_ERROR;
		end
		S_SUBMIT: begin
			if(w_submit_blocked == 1'b1)
				next_state <= S_SUBMIT;
			else if(r_last_segment == 1'b1)
				next_state <= S_IDLE;
			else
				next_state <= S_NEXT_SEG;
		end
		S_NEXT_SEG: begin
			next_state <= S_SUBMIT;
		end
		S_ERROR: begin
			next_state <= S_IDLE;
		end
		default: begin
			next_state <= S_IDLE;
		end
	endcase
end

always @ (posedge clk)
begin
	if(w_reset == 1'b1) begin
		r_sq_qid <= 0;
		r_hcmd_slot_tag <= 0;
		r_hcmd_seq <= 0;
		r_opcode <= 0;
		r_total_segments <= 0;
		r_segment_index <= 0;
		r_slba_lo <= 0;
		r_slba_hi <= 0;
		r_dma_dir <= DMA_DIR_TX;
		r_decode_error <= 0;
		r_dma_stalled <= 0;
		r_unsupported_pending <= 0;
		r_last_segment <= 0;
		r_auto_error <= 0;
		r_cmd_count <= 0;
		r_dma_submit_count <= 0;
		r_unsupported_count <= 0;
		r_last_qid_slot <= 0;
		r_last_opcode <= 0;
		r_last_error_info <= 0;
	end
	else begin
		r_auto_error <= r_auto_error & ~auto_error_clear;
		r_dma_stalled <= 1'b0;

		if((auto_error_clear & (ERR_ADMIN_OR_MASKED_QID | ERR_UNSUPPORTED_OPCODE |
								ERR_DISABLED_OPCODE | ERR_DDR_RANGE |
								ERR_AUTO_CQ_DISABLED | ERR_CQ_MODE_UNSUPPORTED |
								ERR_NLB_TOO_LARGE)) != 32'h0)
			r_unsupported_pending <= 1'b0;

		case(cur_state)
			S_POP: begin
				r_sq_qid <= hcmd_sq_rd_data[3:0];
				r_hcmd_slot_tag <= hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+4)-1:4];
				r_hcmd_seq <= hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+12)-1:(P_SLOT_TAG_WIDTH+4)];
				r_last_qid_slot <= {{(20-P_SLOT_TAG_WIDTH){1'b0}},
									hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+12)-1:(P_SLOT_TAG_WIDTH+4)],
									hcmd_sq_rd_data[(P_SLOT_TAG_WIDTH+4)-1:4],
									hcmd_sq_rd_data[3:0]};
				r_cmd_count <= r_cmd_count + 1;
			end
			S_OPCODE_DECODE: begin
				r_opcode <= hcmd_table_rd_data[7:0];
				r_dma_dir <= (hcmd_table_rd_data[7:0] == 8'h02) ? DMA_DIR_TX : DMA_DIR_RX;
				r_decode_error <= w_opcode_decode_error;
				r_last_opcode <= {24'h0, hcmd_table_rd_data[7:0]};
			end
			S_NLB_DECODE: begin
				r_total_segments <= w_table_segments;
				r_segment_index <= 0;
				r_last_segment <= (w_table_segments == 9'd1);
				r_decode_error <= w_nlb_decode_error;
			end
			S_SLBA_LO_CAPTURE: begin
				r_slba_lo <= hcmd_table_rd_data;
			end
			S_SLBA_HI_CAPTURE: begin
				r_slba_hi <= hcmd_table_rd_data;
			end
			S_RANGE_CHECK: begin
				r_decode_error <= w_range_decode_error;
			end
			S_SUBMIT: begin
				r_dma_stalled <= w_submit_blocked;
				if(w_submit_fire)
					r_dma_submit_count <= r_dma_submit_count + 1;
			end
			S_NEXT_SEG: begin
				r_segment_index <= r_segment_index + 9'd1;
				r_last_segment <= ((r_segment_index + 9'd2) == r_total_segments);
			end
			S_ERROR: begin
				r_auto_error <= (r_auto_error & ~auto_error_clear) | r_decode_error;
				r_unsupported_pending <= 1'b1;
				r_unsupported_count <= r_unsupported_count + 1;
				r_last_error_info <= {r_opcode, r_sq_qid, {(18-P_SLOT_TAG_WIDTH){1'b0}}, r_hcmd_slot_tag};
			end
			default: begin

			end
		endcase
	end
end

endmodule
