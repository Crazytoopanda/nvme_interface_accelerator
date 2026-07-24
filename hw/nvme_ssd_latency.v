/*
 * NVMe SSD latency timeline and CQE publication gate.
 *
 * Command metadata crosses from the CPU register clock through the existing
 * dma_cmd_fifo primitive.  The model runs in the PCIe user-clock domain and
 * tracks 8 NAND channels and 32 LUNs/channel.  DMA completion is accepted as
 * soon as it arrives; CQE publication waits until both DMA and the modeled
 * NAND deadline are complete.
 */
`timescale 1ns / 1ps

module nvme_ssd_latency #(
	parameter P_SLOT_TAG_WIDTH = 10,
	parameter P_CQ_DATA_WIDTH = P_SLOT_TAG_WIDTH + 28
)(
	input                              cpu_bus_clk,
	input                              cpu_bus_rst_n,
	input                              model_cmd_wr_en,
	input      [63:0]                  model_cmd_wr_data0,
	input      [63:0]                  model_cmd_wr_data1,
	output                             model_cmd_wr_rdy_n,

	input                              pcie_user_clk,
	input                              pcie_user_rst_n,
	input                              model_enable,
	input                              model_reset,
	input      [31:0]                  read_lsb_cycles,
	input      [31:0]                  read_msb_cycles,
	input      [31:0]                  program_cycles,
	input      [31:0]                  fw_read_cycles,
	input      [31:0]                  fw_write_cycles,
	input      [31:0]                  ch_xfer_4k_cycles,
	input      [4:0]                   channel_count,

	input                              in_cq_wr_en,
	input      [P_CQ_DATA_WIDTH-1:0]   in_cq_wr_data0,
	input      [P_CQ_DATA_WIDTH-1:0]   in_cq_wr_data1,
	output                             in_cq_wr_rdy_n,

	output                             out_cq_wr_en,
	output     [P_CQ_DATA_WIDTH-1:0]   out_cq_wr_data0,
	output     [P_CQ_DATA_WIDTH-1:0]   out_cq_wr_data1,
	input                              out_cq_wr_rdy_n,

	output     [31:0]                  model_status,
	output     [31:0]                  model_submit_count,
	output     [31:0]                  model_release_count
);

localparam M_IDLE    = 3'd0;
localparam M_LOAD    = 3'd1;
localparam M_NAND    = 3'd2;
localparam M_CHANNEL = 3'd3;
localparam M_SEG     = 3'd4;
localparam M_COMMIT  = 3'd5;
localparam P_SCAN_ROW_WIDTH = P_SLOT_TAG_WIDTH - 3;

wire [127:0] w_meta_data;
wire        w_meta_empty_n;
reg         r_meta_rd_en;

reg  [2:0]  r_model_state;
reg  [63:0] r_time;
reg  [63:0] r_cmd_slba;
reg  [8:0]  r_cmd_segments;
reg  [8:0]  r_segment;
reg         r_cmd_write;
reg  [P_SLOT_TAG_WIDTH-1:0] r_cmd_slot;
reg  [63:0] r_cmd_due;
reg  [63:0] r_channel_start_q;
reg  [63:0] r_channel_done_q;
reg  [63:0] r_segment_done_q;

(* ram_style = "block" *) reg [63:0] r_lane_avail [0:511];
reg  [63:0] r_ch_avail [0:15];
(* ram_style = "block" *) reg [63:0] r_due_bank0 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank1 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank2 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank3 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank4 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank5 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank6 [0:(1<<P_SCAN_ROW_WIDTH)-1];
(* ram_style = "block" *) reg [63:0] r_due_bank7 [0:(1<<P_SCAN_ROW_WIDTH)-1];
reg  [511:0] r_lane_valid;
reg  [(1<<P_SLOT_TAG_WIDTH)-1:0] r_due_valid;
reg  [(1<<P_SLOT_TAG_WIDTH)-1:0] r_dma_pending;

reg  [63:0] r_lane_avail_q;
reg  [63:0] r_ch_avail_q;
reg         r_lane_valid_q;
reg  [P_SCAN_ROW_WIDTH-1:0] r_scan_index;
reg  [P_SCAN_ROW_WIDTH-1:0] r_scan_row_q;
reg  [63:0] r_scan_due_q [0:7];
reg  [7:0]  r_scan_armed_q;
reg         r_scan_found;
reg  [2:0]  r_scan_bank;
reg        r_out_valid;
reg  [P_SLOT_TAG_WIDTH-1:0] r_out_slot;
reg  [31:0] r_submit_count;
reg  [31:0] r_release_count;
reg         r_model_enable_s1, r_model_enable_s2;
reg         r_model_reset_s1, r_model_reset_s2;
reg [31:0]  r_read_lsb_s1, r_read_lsb_s2;
reg [31:0]  r_read_msb_s1, r_read_msb_s2;
reg [31:0]  r_program_s1, r_program_s2;
reg [31:0]  r_fw_read_s1, r_fw_read_s2;
reg [31:0]  r_fw_write_s1, r_fw_write_s2;
reg [31:0]  r_ch_xfer_s1, r_ch_xfer_s2;
reg [4:0]   r_channel_count_s1, r_channel_count_s2;

wire [P_SLOT_TAG_WIDTH-1:0] w_in_slot;
wire [63:0] w_seg_lba;
wire [63:0] w_page;
reg  [3:0]  r_channel;
reg  [4:0]  r_lun;
wire [3:0]  w_channel;
wire [4:0]  w_lun;
wire [8:0]  w_lane;
wire        w_msb;
wire        w_program_ready;
wire        w_lane_commit;
wire [63:0] w_fw_start;
wire [63:0] w_nand_start;
wire [63:0] w_nand_done;
wire [63:0] w_channel_start;
wire [63:0] w_channel_done;
wire [63:0] w_program_done;
wire [63:0] w_segment_done;
wire [8:0]  w_segments_remaining;
wire [2:0]  w_read_page_remaining;
wire [2:0]  w_read_group_segments;
wire [8:0]  w_segment_advance;
wire [63:0] w_ch_xfer_4k;
wire [63:0] w_read_xfer_cycles;
wire        w_last_segment;

integer bank;
integer idx;

assign w_in_slot = in_cq_wr_data0[P_SLOT_TAG_WIDTH+1:2];
assign w_seg_lba = r_cmd_slba + r_segment;
/* The current namespace and DMA engine use 4 KiB logical blocks. */
assign w_page = w_seg_lba >> 2;
always @(*) begin
	case(r_channel_count_s2)
	5'd1: begin r_channel = 4'd0; r_lun = w_page[4:0]; end
	5'd2: begin r_channel = {3'b0, w_page[0]}; r_lun = w_page[5:1]; end
	5'd4: begin r_channel = {2'b0, w_page[1:0]}; r_lun = w_page[6:2]; end
	5'd16: begin r_channel = w_page[3:0]; r_lun = w_page[8:4]; end
	default: begin r_channel = {1'b0, w_page[2:0]}; r_lun = w_page[7:3]; end
	endcase
end
assign w_channel = r_channel;
assign w_lun = r_lun;
assign w_lane = {w_lun, w_channel};
assign w_msb = w_seg_lba[0];
assign w_program_ready = (w_seg_lba[1:0] == 2'b11);
assign w_lane_commit = !r_cmd_write || w_program_ready;
assign w_segments_remaining = r_cmd_segments - r_segment;
assign w_read_page_remaining = 3'd4 - {1'b0, w_seg_lba[1:0]};
assign w_read_group_segments =
	(w_segments_remaining < {6'b0, w_read_page_remaining}) ?
	w_segments_remaining[2:0] : w_read_page_remaining;
assign w_segment_advance = r_cmd_write ? 9'd1 :
			    {6'b0, w_read_group_segments};
assign w_ch_xfer_4k = {32'b0, r_ch_xfer_s2};
assign w_read_xfer_cycles =
	(w_read_group_segments == 3'd4) ? (w_ch_xfer_4k << 2) :
	(w_read_group_segments == 3'd3) ? ((w_ch_xfer_4k << 1) + w_ch_xfer_4k) :
	(w_read_group_segments == 3'd2) ? (w_ch_xfer_4k << 1) :
					 w_ch_xfer_4k;
assign w_fw_start = r_time + (r_cmd_write ? r_fw_write_s2 : r_fw_read_s2);
assign w_nand_start = (r_lane_valid_q && (r_lane_avail_q > w_fw_start)) ?
			      r_lane_avail_q : w_fw_start;
assign w_nand_done = w_nand_start + (w_msb ? r_read_msb_s2 : r_read_lsb_s2);
assign w_channel_start = r_cmd_write ? w_nand_start : w_nand_done;
assign w_channel_done = ((r_ch_avail_q > r_channel_start_q) ?
			 r_ch_avail_q : r_channel_start_q) +
			(r_cmd_write ? (w_ch_xfer_4k << 2) :
				       w_read_xfer_cycles);
assign w_program_done = r_channel_done_q + r_program_s2;
assign w_segment_done = r_cmd_write ?
			(w_program_ready ? w_program_done : w_fw_start) :
			r_channel_done_q;
assign w_last_segment = (r_segment + w_segment_advance) >= r_cmd_segments;

nvme_model_async_fifo model_metadata_fifo (
	.wr_clk(cpu_bus_clk),
	.wr_rst_n(cpu_bus_rst_n & ~model_reset),
	.wr_en(model_cmd_wr_en),
	.wr_data({model_cmd_wr_data1, model_cmd_wr_data0}),
	.wr_rdy_n(model_cmd_wr_rdy_n),
	.rd_clk(pcie_user_clk),
	.rd_rst_n(pcie_user_rst_n & ~model_reset),
	.rd_en(r_meta_rd_en),
	.rd_data(w_meta_data),
	.empty_n(w_meta_empty_n)
);

wire [63:0] w_cmd_due_final = (r_segment_done_q > r_cmd_due) ?
				     r_segment_done_q : r_cmd_due;

always @(*) begin
	r_scan_found = 1'b0;
	r_scan_bank = 3'b0;
	for(bank = 0; bank < 8; bank = bank + 1) begin
		if(!r_scan_found &&
		   r_scan_armed_q[bank] &&
		   ($signed(r_time - r_scan_due_q[bank]) >= 0)) begin
			r_scan_found = 1'b1;
			r_scan_bank = bank[2:0];
		end
	end
end

/* Synchronous reads and no array reset are required for block RAM inference. */
always @(posedge pcie_user_clk) begin
	if(r_model_state == M_LOAD)
		r_lane_avail_q <= r_lane_avail[w_lane];
	if(!r_model_reset_s2 && (r_model_state == M_COMMIT) && w_lane_commit)
		r_lane_avail[w_lane] <= r_segment_done_q;

	r_scan_due_q[0] <= r_due_bank0[r_scan_index];
	r_scan_due_q[1] <= r_due_bank1[r_scan_index];
	r_scan_due_q[2] <= r_due_bank2[r_scan_index];
	r_scan_due_q[3] <= r_due_bank3[r_scan_index];
	r_scan_due_q[4] <= r_due_bank4[r_scan_index];
	r_scan_due_q[5] <= r_due_bank5[r_scan_index];
	r_scan_due_q[6] <= r_due_bank6[r_scan_index];
	r_scan_due_q[7] <= r_due_bank7[r_scan_index];
	if(!r_model_reset_s2 && (r_model_state == M_COMMIT) && w_last_segment) begin
		case(r_cmd_slot[2:0])
		3'd0: r_due_bank0[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd1: r_due_bank1[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd2: r_due_bank2[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd3: r_due_bank3[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd4: r_due_bank4[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd5: r_due_bank5[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd6: r_due_bank6[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		3'd7: r_due_bank7[r_cmd_slot[P_SLOT_TAG_WIDTH-1:3]] <= w_cmd_due_final;
		default: ;
		endcase
	end
end

assign in_cq_wr_rdy_n = r_model_enable_s2 ? r_dma_pending[w_in_slot] : out_cq_wr_rdy_n;
assign out_cq_wr_en = r_model_enable_s2 ? r_out_valid : in_cq_wr_en;
assign out_cq_wr_data0 = r_model_enable_s2 ?
		{{(P_CQ_DATA_WIDTH-P_SLOT_TAG_WIDTH-2){1'b0}}, r_out_slot, 2'b01} :
		in_cq_wr_data0;
assign out_cq_wr_data1 = r_model_enable_s2 ? {P_CQ_DATA_WIDTH{1'b0}} : in_cq_wr_data1;
assign model_status = {16'b0, 5'b0, r_out_valid, 4'b0, r_model_state,
			       w_meta_empty_n, |r_dma_pending, r_model_enable_s2};
assign model_submit_count = r_submit_count;
assign model_release_count = r_release_count;

always @(posedge pcie_user_clk or negedge pcie_user_rst_n) begin
	if(!pcie_user_rst_n) begin
		r_model_enable_s1 <= 0;
		r_model_enable_s2 <= 0;
		r_model_reset_s1 <= 0;
		r_model_reset_s2 <= 0;
		r_read_lsb_s1 <= 0;
		r_read_lsb_s2 <= 0;
		r_read_msb_s1 <= 0;
		r_read_msb_s2 <= 0;
		r_program_s1 <= 0;
		r_program_s2 <= 0;
		r_fw_read_s1 <= 0;
		r_fw_read_s2 <= 0;
		r_fw_write_s1 <= 0;
		r_fw_write_s2 <= 0;
		r_ch_xfer_s1 <= 0;
		r_ch_xfer_s2 <= 0;
		r_channel_count_s1 <= 5'd8;
		r_channel_count_s2 <= 5'd8;
	end else begin
		r_model_enable_s1 <= model_enable;
		r_model_enable_s2 <= r_model_enable_s1;
		r_model_reset_s1 <= model_reset;
		r_model_reset_s2 <= r_model_reset_s1;
		r_read_lsb_s1 <= read_lsb_cycles;
		r_read_lsb_s2 <= r_read_lsb_s1;
		r_read_msb_s1 <= read_msb_cycles;
		r_read_msb_s2 <= r_read_msb_s1;
		r_program_s1 <= program_cycles;
		r_program_s2 <= r_program_s1;
		r_fw_read_s1 <= fw_read_cycles;
		r_fw_read_s2 <= r_fw_read_s1;
		r_fw_write_s1 <= fw_write_cycles;
		r_fw_write_s2 <= r_fw_write_s1;
		r_ch_xfer_s1 <= ch_xfer_4k_cycles;
		r_ch_xfer_s2 <= r_ch_xfer_s1;
		r_channel_count_s1 <= channel_count;
		r_channel_count_s2 <= r_channel_count_s1;
	end
end

always @(posedge pcie_user_clk or negedge pcie_user_rst_n) begin
	if(!pcie_user_rst_n) begin
		r_time <= 0;
		r_model_state <= M_IDLE;
		r_meta_rd_en <= 0;
		r_cmd_slba <= 0;
		r_cmd_segments <= 0;
		r_segment <= 0;
		r_cmd_write <= 0;
		r_cmd_slot <= 0;
		r_cmd_due <= 0;
		r_channel_start_q <= 0;
		r_channel_done_q <= 0;
		r_segment_done_q <= 0;
		r_ch_avail_q <= 0;
		r_lane_valid_q <= 0;
		r_lane_valid <= 0;
		r_due_valid <= 0;
		r_dma_pending <= 0;
		r_scan_index <= 0;
		r_scan_row_q <= 0;
		r_scan_armed_q <= 0;
		r_out_valid <= 0;
		r_out_slot <= 0;
		r_submit_count <= 0;
		r_release_count <= 0;
		for(idx = 0; idx < 16; idx = idx + 1)
			r_ch_avail[idx] <= 0;
	end else begin
		r_time <= r_time + 1;
		r_meta_rd_en <= 0;
		r_scan_index <= r_scan_index + 1'b1;
		r_scan_row_q <= r_scan_index;
		r_scan_armed_q <= {
			r_dma_pending[{r_scan_index, 3'd7}] && r_due_valid[{r_scan_index, 3'd7}],
			r_dma_pending[{r_scan_index, 3'd6}] && r_due_valid[{r_scan_index, 3'd6}],
			r_dma_pending[{r_scan_index, 3'd5}] && r_due_valid[{r_scan_index, 3'd5}],
			r_dma_pending[{r_scan_index, 3'd4}] && r_due_valid[{r_scan_index, 3'd4}],
			r_dma_pending[{r_scan_index, 3'd3}] && r_due_valid[{r_scan_index, 3'd3}],
			r_dma_pending[{r_scan_index, 3'd2}] && r_due_valid[{r_scan_index, 3'd2}],
			r_dma_pending[{r_scan_index, 3'd1}] && r_due_valid[{r_scan_index, 3'd1}],
			r_dma_pending[{r_scan_index, 3'd0}] && r_due_valid[{r_scan_index, 3'd0}]};

		if(r_model_reset_s2) begin
			r_model_state <= M_IDLE;
			r_lane_valid <= 0;
			r_due_valid <= 0;
			r_dma_pending <= 0;
			r_scan_armed_q <= 0;
			r_out_valid <= 0;
			r_submit_count <= 0;
			r_release_count <= 0;
			for(idx = 0; idx < 16; idx = idx + 1)
				r_ch_avail[idx] <= 0;
		end else begin
			if(r_model_enable_s2 && in_cq_wr_en && !in_cq_wr_rdy_n)
				r_dma_pending[w_in_slot] <= 1'b1;

			if(r_out_valid && !out_cq_wr_rdy_n) begin
				r_out_valid <= 1'b0;
				r_due_valid[r_out_slot] <= 1'b0;
				r_release_count <= r_release_count + 1'b1;
			end
			if(!r_out_valid && r_scan_found) begin
				r_out_valid <= 1'b1;
				r_out_slot <= {r_scan_row_q, r_scan_bank};
				r_dma_pending[{r_scan_row_q, r_scan_bank}] <= 1'b0;
			end

			case(r_model_state)
			M_IDLE: begin
				if(r_model_enable_s2 && w_meta_empty_n) begin
					r_cmd_slba <= w_meta_data[63:0];
					r_cmd_slot <= w_meta_data[64+P_SLOT_TAG_WIDTH-1:64];
					r_cmd_segments <= w_meta_data[82:74];
					r_cmd_write <= w_meta_data[83];
					r_segment <= 0;
					r_cmd_due <= r_time;
					r_meta_rd_en <= 1'b1;
					r_model_state <= M_LOAD;
				end
			end
			M_LOAD: begin
				r_lane_valid_q <= r_lane_valid[w_lane];
				r_ch_avail_q <= r_ch_avail[w_channel];
				r_model_state <= M_NAND;
			end
			M_NAND: begin
				r_channel_start_q <= w_channel_start;
				r_model_state <= M_CHANNEL;
			end
			M_CHANNEL: begin
				r_channel_done_q <= w_channel_done;
				r_model_state <= M_SEG;
			end
			M_SEG: begin
				r_segment_done_q <= w_segment_done;
				r_model_state <= M_COMMIT;
			end
			M_COMMIT: begin
				if(w_lane_commit) begin
					r_ch_avail[w_channel] <= r_channel_done_q;
					r_lane_valid[w_lane] <= 1'b1;
				end
				r_cmd_due <= w_cmd_due_final;
				if(w_last_segment) begin
					r_due_valid[r_cmd_slot] <= 1'b1;
					r_submit_count <= r_submit_count + 1'b1;
					r_model_state <= M_IDLE;
				end else begin
					r_segment <= r_segment + w_segment_advance;
					r_model_state <= M_LOAD;
				end
			end
			default: r_model_state <= M_IDLE;
			endcase
		end
	end
end

endmodule

module nvme_model_async_fifo #(
	parameter WIDTH = 128,
	parameter ADDR_WIDTH = 9
)(
	input                  wr_clk,
	input                  wr_rst_n,
	input                  wr_en,
	input      [WIDTH-1:0] wr_data,
	output                 wr_rdy_n,
	input                  rd_clk,
	input                  rd_rst_n,
	input                  rd_en,
	output     [WIDTH-1:0] rd_data,
	output                 empty_n
);

(* ram_style = "block" *) reg [WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
reg [ADDR_WIDTH:0] wr_bin, wr_gray;
reg [ADDR_WIDTH:0] rd_bin, rd_gray;
reg [ADDR_WIDTH:0] rd_gray_w1, rd_gray_w2;
reg [ADDR_WIDTH:0] wr_gray_r1, wr_gray_r2;
reg [WIDTH-1:0] rd_data_reg;
reg rd_valid;
wire full = (wr_gray == {~rd_gray_w2[ADDR_WIDTH:ADDR_WIDTH-1],
			       rd_gray_w2[ADDR_WIDTH-2:0]});
wire wr_push = wr_en && !full;
wire mem_not_empty = (rd_gray != wr_gray_r2);
wire rd_pop = rd_en && rd_valid;
wire rd_fetch = (!rd_valid || rd_pop) && mem_not_empty;
wire [ADDR_WIDTH:0] wr_bin_next = wr_bin + wr_push;
wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
wire [ADDR_WIDTH:0] rd_bin_next = rd_bin + rd_fetch;
wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

assign wr_rdy_n = full;
assign empty_n = rd_valid;
assign rd_data = rd_data_reg;

always @(posedge wr_clk) begin
	if(wr_push)
		mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
end

always @(posedge rd_clk) begin
	if(rd_fetch)
		rd_data_reg <= mem[rd_bin[ADDR_WIDTH-1:0]];
end

always @(posedge wr_clk or negedge wr_rst_n) begin
	if(!wr_rst_n) begin
		wr_bin <= 0;
		wr_gray <= 0;
		rd_gray_w1 <= 0;
		rd_gray_w2 <= 0;
	end else begin
		rd_gray_w1 <= rd_gray;
		rd_gray_w2 <= rd_gray_w1;
		wr_bin <= wr_bin_next;
		wr_gray <= wr_gray_next;
	end
end

always @(posedge rd_clk or negedge rd_rst_n) begin
	if(!rd_rst_n) begin
		rd_bin <= 0;
		rd_gray <= 0;
		wr_gray_r1 <= 0;
		wr_gray_r2 <= 0;
		rd_valid <= 0;
	end else begin
		wr_gray_r1 <= wr_gray;
		wr_gray_r2 <= wr_gray_r1;
		rd_bin <= rd_bin_next;
		rd_gray <= rd_gray_next;
		if(rd_fetch)
			rd_valid <= 1'b1;
		else if(rd_pop)
			rd_valid <= 1'b0;
	end
end
endmodule
