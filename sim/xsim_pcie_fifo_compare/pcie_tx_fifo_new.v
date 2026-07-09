
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

module pcie_tx_fifo_new # (
	parameter	P_FIFO_WR_DATA_WIDTH		= 512,
	parameter	P_FIFO_RD_DATA_WIDTH		= 512,
	parameter	P_FIFO_DEPTH_WIDTH			= 9
)
(
	input									wr_clk,
	input									wr_rst_n,

	input									alloc_en,
	input	[10:6]							alloc_len,
	input									wr_en,
	input	[P_FIFO_WR_DATA_WIDTH-1:0]		wr_data,
	output									full_n,

	input									rd_clk,
	input									rd_rst_n,

	input									rd_en,
	output	[P_FIFO_RD_DATA_WIDTH-1:0]		rd_data,
	input									free_en,
	input	[10:6]							free_len,
	output									empty_n
);

localparam integer LP_RATIO = P_FIFO_RD_DATA_WIDTH / P_FIFO_WR_DATA_WIDTH;
localparam integer LP_RATIO_BITS = (LP_RATIO <= 1) ? 1 :
								  (LP_RATIO <= 2) ? 1 :
								  (LP_RATIO <= 4) ? 2 : 3;

(* ram_style = "block" *) reg [P_FIFO_RD_DATA_WIDTH-1:0] r_mem [0:(1<<P_FIFO_DEPTH_WIDTH)-1];

reg [P_FIFO_DEPTH_WIDTH:0] r_rear_line;
reg [P_FIFO_DEPTH_WIDTH:0] r_rear_full_addr;
reg [LP_RATIO_BITS-1:0] r_rear_beat;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_line;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_empty_addr;
reg [P_FIFO_RD_DATA_WIDTH-1:0] r_rd_data;
reg [P_FIFO_DEPTH_WIDTH:0] r_rear_sync_addr;
reg [P_FIFO_DEPTH_WIDTH:0] r_rear_sync_data;
reg r_rear_sync_req;
reg r_rear_sync_ack;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_rear_sync_req_d1;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_rear_sync_req_d2;
reg r_rear_sync_req_last;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_rear_sync_ack_d1;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_rear_sync_ack_d2;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_sync_addr;
reg [P_FIFO_DEPTH_WIDTH:0] r_front_sync_data;
reg r_front_sync_req;
reg r_front_sync_ack;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_front_sync_req_d1;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_front_sync_req_d2;
reg r_front_sync_req_last;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_front_sync_ack_d1;
(* ASYNC_REG = "TRUE", SHIFT_EXTRACT = "NO" *) reg r_front_sync_ack_d2;

wire [P_FIFO_DEPTH_WIDTH:0] w_valid_space;
wire [P_FIFO_DEPTH_WIDTH:0] w_invalid_space;
wire [P_FIFO_DEPTH_WIDTH:0] w_rear_line_next;
wire [P_FIFO_DEPTH_WIDTH:0] w_front_empty_addr_next;
wire [P_FIFO_DEPTH_WIDTH:0] w_front_sync_addr_next;
wire [P_FIFO_DEPTH_WIDTH:0] w_front_line_next;
wire [LP_RATIO_BITS-1:0] w_wr_sel;
wire w_rear_line_advance;

assign w_invalid_space = r_front_sync_addr - r_rear_full_addr;
assign full_n = (w_invalid_space >= alloc_len);

assign w_valid_space = r_rear_sync_addr - r_front_empty_addr;
assign empty_n = (w_valid_space >= free_len);

assign rd_data = r_rd_data;
assign w_wr_sel = r_rear_beat;
assign w_rear_line_advance = wr_en & ((LP_RATIO == 1) || (r_rear_beat == LP_RATIO-1));
assign w_rear_line_next = r_rear_line + w_rear_line_advance;
assign w_front_empty_addr_next = r_front_empty_addr + (free_en ? free_len : 0);
assign w_front_sync_addr_next = {~w_front_empty_addr_next[P_FIFO_DEPTH_WIDTH],
								  w_front_empty_addr_next[P_FIFO_DEPTH_WIDTH-1:0]};
assign w_front_line_next = r_front_line + rd_en;

always @(posedge wr_clk)
begin
	if(wr_en == 1'b1)
		r_mem[r_rear_line[P_FIFO_DEPTH_WIDTH-1:0]] <= wr_data[P_FIFO_RD_DATA_WIDTH-1:0];
end

always @(posedge rd_clk)
begin
	r_rd_data <= r_mem[w_front_line_next[P_FIFO_DEPTH_WIDTH-1:0]];
end

always @(posedge wr_clk or negedge wr_rst_n)
begin
	if(wr_rst_n == 1'b0) begin
		r_rear_line <= 0;
		r_rear_full_addr <= 0;
		r_rear_beat <= 0;
		r_rear_sync_data <= 0;
		r_rear_sync_req <= 0;
		r_rear_sync_ack_d1 <= 0;
		r_rear_sync_ack_d2 <= 0;
		r_front_sync_addr[P_FIFO_DEPTH_WIDTH] <= 1'b1;
		r_front_sync_addr[P_FIFO_DEPTH_WIDTH-1:0] <= 0;
		r_front_sync_req_d1 <= 0;
		r_front_sync_req_d2 <= 0;
		r_front_sync_req_last <= 0;
		r_front_sync_ack <= 0;
	end
	else begin
		r_front_sync_req_d1 <= r_front_sync_req;
		r_front_sync_req_d2 <= r_front_sync_req_d1;
		if(r_front_sync_req_d2 != r_front_sync_req_last) begin
			r_front_sync_req_last <= r_front_sync_req_d2;
			r_front_sync_addr <= r_front_sync_data;
			r_front_sync_ack <= r_front_sync_req_d2;
		end

		r_rear_sync_ack_d1 <= r_rear_sync_ack;
		r_rear_sync_ack_d2 <= r_rear_sync_ack_d1;
		if(r_rear_sync_req == r_rear_sync_ack_d2) begin
			if(r_rear_sync_data != w_rear_line_next) begin
				r_rear_sync_data <= w_rear_line_next;
				r_rear_sync_req <= ~r_rear_sync_req;
			end
		end

		if(alloc_en == 1'b1)
			r_rear_full_addr <= r_rear_full_addr + alloc_len;

		if(wr_en == 1'b1) begin
			if((LP_RATIO == 1) || (r_rear_beat == LP_RATIO-1)) begin
				r_rear_beat <= 0;
				r_rear_line <= r_rear_line + 1'b1;
			end
			else begin
				r_rear_beat <= r_rear_beat + 1'b1;
			end
		end
	end
end

always @(posedge rd_clk or negedge rd_rst_n)
begin
	if(rd_rst_n == 1'b0) begin
		r_front_line <= 0;
		r_front_empty_addr <= 0;
		r_rear_sync_addr <= 0;
		r_rear_sync_req_d1 <= 0;
		r_rear_sync_req_d2 <= 0;
		r_rear_sync_req_last <= 0;
		r_rear_sync_ack <= 0;
		r_front_sync_data[P_FIFO_DEPTH_WIDTH] <= 1'b1;
		r_front_sync_data[P_FIFO_DEPTH_WIDTH-1:0] <= 0;
		r_front_sync_req <= 0;
		r_front_sync_ack_d1 <= 0;
		r_front_sync_ack_d2 <= 0;
	end
	else begin
		r_rear_sync_req_d1 <= r_rear_sync_req;
		r_rear_sync_req_d2 <= r_rear_sync_req_d1;
		if(r_rear_sync_req_d2 != r_rear_sync_req_last) begin
			r_rear_sync_req_last <= r_rear_sync_req_d2;
			r_rear_sync_addr <= r_rear_sync_data;
			r_rear_sync_ack <= r_rear_sync_req_d2;
		end

		r_front_sync_ack_d1 <= r_front_sync_ack;
		r_front_sync_ack_d2 <= r_front_sync_ack_d1;
		if(r_front_sync_req == r_front_sync_ack_d2) begin
			if(r_front_sync_data != w_front_sync_addr_next) begin
				r_front_sync_data <= w_front_sync_addr_next;
				r_front_sync_req <= ~r_front_sync_req;
			end
		end

		if(rd_en == 1'b1)
			r_front_line <= r_front_line + 1'b1;

		if(free_en == 1'b1)
			r_front_empty_addr <= r_front_empty_addr + free_len;
	end
end

endmodule
