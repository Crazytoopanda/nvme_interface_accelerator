/*
----------------------------------------------------------------------------------
Copyright (c) 2013-2014

  Embedded and Network Computing Lab.
  Open SSD Project
  Hanyang University

All rights reserved.
----------------------------------------------------------------------------------
*/

`timescale 1ns / 1ps

module pcie_rx_fifo_old # (
	parameter	P_FIFO_WR_DATA_WIDTH		= 512,
	parameter	P_FIFO_RD_DATA_WIDTH		= 512,
	parameter	P_FIFO_DEPTH_WIDTH			= 9
)
(
	input									wr_clk,
	input									wr_rst_n,

	input									wr_en,
	input	[P_FIFO_DEPTH_WIDTH-1:0]		wr_addr,
	input	[P_FIFO_WR_DATA_WIDTH-1:0]		wr_data,
	input	[P_FIFO_DEPTH_WIDTH:0]			rear_full_addr,
	input	[P_FIFO_DEPTH_WIDTH:0]			rear_addr,
	input	[10:6]							alloc_len,
	output									full_n,

	input									rd_clk,
	input									rd_rst_n,

	input									rd_en,
	output	[P_FIFO_RD_DATA_WIDTH-1:0]		rd_data,
	input									free_en,
	input	[10:6]							free_len,
	output									empty_n
);

localparam integer LP_RATIO = P_FIFO_WR_DATA_WIDTH / P_FIFO_RD_DATA_WIDTH;
localparam integer LP_RATIO_BITS = (LP_RATIO <= 1) ? 1 :
								  (LP_RATIO <= 2) ? 1 :
								  (LP_RATIO <= 4) ? 2 : 3;

(* ram_style = "block" *) reg [P_FIFO_WR_DATA_WIDTH-1:0] r_mem [0:(1<<P_FIFO_DEPTH_WIDTH)-1];

reg [P_FIFO_DEPTH_WIDTH:0] r_front_line;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_empty_addr;
reg [LP_RATIO_BITS-1:0] r_front_beat;
reg [P_FIFO_DEPTH_WIDTH:0] r_rear_sync_addr;
reg [P_FIFO_DEPTH_WIDTH:0] r_rear_sync_addr_d1;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_sync_addr;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_sync_addr_d1;

wire [P_FIFO_DEPTH_WIDTH:0] w_valid_space;
wire [P_FIFO_DEPTH_WIDTH:0] w_invalid_space;
wire [P_FIFO_WR_DATA_WIDTH-1:0] w_line_data;
wire [LP_RATIO_BITS-1:0] w_rd_sel;

assign w_invalid_space = r_front_sync_addr - rear_full_addr;
assign full_n = (w_invalid_space >= alloc_len);

assign w_valid_space = r_rear_sync_addr - r_front_empty_addr;
assign empty_n = (w_valid_space >= free_len);

assign w_line_data = r_mem[r_front_line[P_FIFO_DEPTH_WIDTH-1:0]];
assign w_rd_sel = r_front_beat;
assign rd_data = w_line_data[w_rd_sel*P_FIFO_RD_DATA_WIDTH +: P_FIFO_RD_DATA_WIDTH];

always @(posedge wr_clk)
begin
	if(wr_en == 1'b1)
		r_mem[wr_addr] <= wr_data;
end

always @(posedge rd_clk or negedge rd_rst_n)
begin
	if(rd_rst_n == 1'b0) begin
		r_front_line <= 0;
		r_front_empty_addr <= 0;
		r_front_beat <= 0;
		r_rear_sync_addr <= 0;
		r_rear_sync_addr_d1 <= 0;
	end
	else begin
		r_rear_sync_addr_d1 <= rear_addr;
		r_rear_sync_addr <= r_rear_sync_addr_d1;

		if(rd_en == 1'b1) begin
			if((LP_RATIO == 1) || (r_front_beat == LP_RATIO-1)) begin
				r_front_beat <= 0;
				r_front_line <= r_front_line + 1'b1;
			end
			else begin
				r_front_beat <= r_front_beat + 1'b1;
			end
		end

		if(free_en == 1'b1)
			r_front_empty_addr <= r_front_empty_addr + free_len;
	end
end

always @(posedge wr_clk or negedge wr_rst_n)
begin
	if(wr_rst_n == 1'b0) begin
		r_front_sync_addr[P_FIFO_DEPTH_WIDTH] <= 1'b1;
		r_front_sync_addr[P_FIFO_DEPTH_WIDTH-1:0] <= 0;
		r_front_sync_addr_d1 <= 0;
	end
	else begin
		r_front_sync_addr_d1 <= r_front_empty_addr;
		r_front_sync_addr <= r_front_sync_addr_d1;
	end
end

endmodule
