`timescale 1ns / 1ps

module axi_sqe_window # (
	parameter P_SLOT_TAG_WIDTH = 10,
	parameter C_S_AXI_ID_WIDTH = 1,
	parameter C_S_AXI_ADDR_WIDTH = 32,
	parameter C_S_AXI_DATA_WIDTH = 128
)
(
	input									s_axi_aclk,
	input									s_axi_aresetn,

	input	[C_S_AXI_ID_WIDTH-1:0]			s_axi_awid,
	input	[C_S_AXI_ADDR_WIDTH-1:0]		s_axi_awaddr,
	input	[7:0]							s_axi_awlen,
	input	[2:0]							s_axi_awsize,
	input	[1:0]							s_axi_awburst,
	input	[1:0]							s_axi_awlock,
	input	[3:0]							s_axi_awcache,
	input	[2:0]							s_axi_awprot,
	input	[3:0]							s_axi_awregion,
	input	[3:0]							s_axi_awqos,
	input									s_axi_awvalid,
	output									s_axi_awready,

	input	[C_S_AXI_DATA_WIDTH-1:0]		s_axi_wdata,
	input	[(C_S_AXI_DATA_WIDTH/8)-1:0]	s_axi_wstrb,
	input									s_axi_wlast,
	input									s_axi_wvalid,
	output									s_axi_wready,

	output	[C_S_AXI_ID_WIDTH-1:0]			s_axi_bid,
	output	[1:0]							s_axi_bresp,
	output									s_axi_bvalid,
	input									s_axi_bready,

	input	[C_S_AXI_ID_WIDTH-1:0]			s_axi_arid,
	input	[C_S_AXI_ADDR_WIDTH-1:0]		s_axi_araddr,
	input	[7:0]							s_axi_arlen,
	input	[2:0]							s_axi_arsize,
	input	[1:0]							s_axi_arburst,
	input	[1:0]							s_axi_arlock,
	input	[3:0]							s_axi_arcache,
	input	[2:0]							s_axi_arprot,
	input	[3:0]							s_axi_arregion,
	input	[3:0]							s_axi_arqos,
	input									s_axi_arvalid,
	output									s_axi_arready,

	output	[C_S_AXI_ID_WIDTH-1:0]			s_axi_rid,
	output	[C_S_AXI_DATA_WIDTH-1:0]		s_axi_rdata,
	output	[1:0]							s_axi_rresp,
	output									s_axi_rlast,
	output									s_axi_rvalid,
	input									s_axi_rready,

	output									hcmd_table_rd_active,
	output	[(P_SLOT_TAG_WIDTH+2)+1:0]		hcmd_table_rd_addr,
	input	[31:0]							hcmd_table_rd_data
);

localparam LP_WORDS_PER_BEAT = (C_S_AXI_DATA_WIDTH == 128) ? 4 :
							   (C_S_AXI_DATA_WIDTH == 64)  ? 2 : 1;
localparam LP_BEAT_BYTES = C_S_AXI_DATA_WIDTH / 8;
localparam LP_RD_IDLE = 3'd0;
localparam LP_RD_SET_ADDR = 3'd1;
localparam LP_RD_CAPTURE = 3'd2;
localparam LP_RD_SEND = 3'd3;

localparam LP_WR_IDLE = 2'd0;
localparam LP_WR_DATA = 2'd1;
localparam LP_WR_RESP = 2'd2;

reg	[2:0]							r_rd_state;
reg	[1:0]							r_wr_state;

reg	[C_S_AXI_ID_WIDTH-1:0]			r_arid;
reg	[C_S_AXI_ADDR_WIDTH-1:0]			r_rd_addr;
reg	[7:0]							r_rd_beats_left;
reg	[1:0]							r_arburst;
reg	[2:0]							r_word_index;
reg	[2:0]							r_words_per_beat;
reg	[7:0]							r_beat_bytes;
reg	[C_S_AXI_DATA_WIDTH-1:0]			r_rdata;

reg	[C_S_AXI_ID_WIDTH-1:0]			r_awid;

wire								w_rd_last_beat;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]	w_table_word_addr;
wire	[2:0]							w_ar_words_per_beat;
wire	[7:0]							w_ar_beat_bytes;
wire	[2:0]							w_lane_base;
wire	[2:0]							w_lane_index;

assign s_axi_arready = (r_rd_state == LP_RD_IDLE);
assign s_axi_rvalid = (r_rd_state == LP_RD_SEND);
assign s_axi_rid = r_arid;
assign s_axi_rdata = r_rdata;
assign s_axi_rresp = 2'b00;
assign s_axi_rlast = w_rd_last_beat;

assign s_axi_awready = (r_wr_state == LP_WR_IDLE);
assign s_axi_wready = (r_wr_state == LP_WR_DATA);
assign s_axi_bid = r_awid;
assign s_axi_bresp = 2'b10;
assign s_axi_bvalid = (r_wr_state == LP_WR_RESP);

assign w_rd_last_beat = (r_rd_beats_left == 8'd0);
assign w_ar_beat_bytes = (s_axi_arsize <= 3'd2) ? 8'd4 :
                         (s_axi_arsize == 3'd3) ? ((LP_BEAT_BYTES < 8) ? LP_BEAT_BYTES : 8'd8) :
                         LP_BEAT_BYTES;
assign w_ar_words_per_beat = (s_axi_arsize <= 3'd2) ? 3'd1 :
                             (s_axi_arsize == 3'd3) ? ((LP_WORDS_PER_BEAT < 2) ? LP_WORDS_PER_BEAT : 3'd2) :
                             LP_WORDS_PER_BEAT;
assign w_lane_base = (C_S_AXI_DATA_WIDTH == 128) ? {1'b0, r_rd_addr[3:2]} :
                     (C_S_AXI_DATA_WIDTH == 64)  ? {2'b0, r_rd_addr[2]} : 3'd0;
assign w_lane_index = w_lane_base + r_word_index;
assign w_table_word_addr = r_rd_addr[(P_SLOT_TAG_WIDTH+2)+3:2] + r_word_index;
assign hcmd_table_rd_active = (r_rd_state != LP_RD_IDLE);
assign hcmd_table_rd_addr = w_table_word_addr;

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_rd_state <= LP_RD_IDLE;
		r_arid <= 0;
		r_rd_addr <= 0;
		r_rd_beats_left <= 0;
		r_arburst <= 0;
		r_word_index <= 0;
		r_words_per_beat <= 0;
		r_beat_bytes <= 0;
		r_rdata <= 0;
	end
	else begin
		case(r_rd_state)
			LP_RD_IDLE: begin
				if(s_axi_arvalid == 1) begin
					r_arid <= s_axi_arid;
					r_rd_addr <= s_axi_araddr;
					r_rd_beats_left <= s_axi_arlen;
					r_arburst <= s_axi_arburst;
					r_word_index <= 0;
					r_words_per_beat <= w_ar_words_per_beat;
					r_beat_bytes <= w_ar_beat_bytes;
					r_rdata <= 0;
					r_rd_state <= LP_RD_SET_ADDR;
				end
			end
			LP_RD_SET_ADDR: begin
				r_rd_state <= LP_RD_CAPTURE;
			end
			LP_RD_CAPTURE: begin
				r_rdata[(w_lane_index * 32) +: 32] <= hcmd_table_rd_data;
				if(r_word_index == (r_words_per_beat - 1)) begin
					r_word_index <= 0;
					r_rd_state <= LP_RD_SEND;
				end
				else begin
					r_word_index <= r_word_index + 1;
					r_rd_state <= LP_RD_SET_ADDR;
				end
			end
			LP_RD_SEND: begin
				if(s_axi_rready == 1) begin
					if(w_rd_last_beat == 1) begin
						r_rd_state <= LP_RD_IDLE;
					end
					else begin
						if(r_arburst != 2'b00)
							r_rd_addr <= r_rd_addr + r_beat_bytes;
						r_rd_beats_left <= r_rd_beats_left - 1;
						r_word_index <= 0;
						r_rdata <= 0;
						r_rd_state <= LP_RD_SET_ADDR;
					end
				end
			end
			default: begin
				r_rd_state <= LP_RD_IDLE;
			end
		endcase
	end
end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_wr_state <= LP_WR_IDLE;
		r_awid <= 0;
	end
	else begin
		case(r_wr_state)
			LP_WR_IDLE: begin
				if(s_axi_awvalid == 1) begin
					r_awid <= s_axi_awid;
					r_wr_state <= LP_WR_DATA;
				end
			end
			LP_WR_DATA: begin
				if(s_axi_wvalid == 1 && s_axi_wlast == 1)
					r_wr_state <= LP_WR_RESP;
			end
			LP_WR_RESP: begin
				if(s_axi_bready == 1)
					r_wr_state <= LP_WR_IDLE;
			end
			default: begin
				r_wr_state <= LP_WR_IDLE;
			end
		endcase
	end
end

endmodule
