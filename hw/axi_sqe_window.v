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
	input	[C_S_AXI_DATA_WIDTH-1:0]		hcmd_table_rd_data_sqe,

	output								dma_cmd_wr_en,
	output	[87:0]							dma_cmd_wr_data0,
	output	[87:0]							dma_cmd_wr_data1,
	input								dma_cmd_wr_rdy_n
);

localparam LP_WORDS_PER_BEAT = (C_S_AXI_DATA_WIDTH == 128) ? 4 :
							   (C_S_AXI_DATA_WIDTH == 64)  ? 2 : 1;
localparam LP_BEAT_BYTES = C_S_AXI_DATA_WIDTH / 8;
localparam LP_PACKED_DMA_ADDR_BIT = 17;
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
reg	[2:0]							r_capture_index;
reg	[2:0]							r_words_per_beat;
reg	[7:0]							r_beat_bytes;
reg	[C_S_AXI_DATA_WIDTH-1:0]			r_rdata;

reg	[C_S_AXI_ID_WIDTH-1:0]			r_awid;
reg	[1:0]							r_bresp;
reg								r_dma_cmd_wr_en;
reg	[87:0]							r_dma_cmd_wr_data0;
reg	[87:0]							r_dma_cmd_wr_data1;
reg								r_wr_packed_dma;
reg								r_dma_cmd_sent;
reg	[127:0]						r_dma_payload;
reg	[15:0]							r_dma_payload_valid;
reg	[3:0]							r_wr_addr_low;
reg	[1:0]							r_awburst;
reg	[127:0]							r_dma_payload_next;
reg	[15:0]							r_dma_payload_valid_next;

wire								w_rd_last_beat;
wire	[(P_SLOT_TAG_WIDTH+2)+1:0]	w_table_word_addr;
wire	[2:0]							w_ar_words_per_beat;
wire	[7:0]							w_ar_beat_bytes;
wire	[2:0]							w_lane_base;
wire	[2:0]							w_lane_index;
wire								w_aw_packed_dma;
wire								w_wr_accept;
wire								w_dma_payload_complete;
wire	[3:0]							w_wr_byte_base;

assign s_axi_arready = (r_rd_state == LP_RD_IDLE);
assign s_axi_rvalid = (r_rd_state == LP_RD_SEND);
assign s_axi_rid = r_arid;
assign s_axi_rdata = r_rdata;
assign s_axi_rresp = 2'b00;
assign s_axi_rlast = w_rd_last_beat;

assign s_axi_awready = (r_wr_state == LP_WR_IDLE);
assign s_axi_wready = (r_wr_state == LP_WR_DATA) &&
					  ((r_wr_packed_dma == 0) || (r_dma_cmd_sent == 1) ||
					   (w_dma_payload_complete == 0) || (dma_cmd_wr_rdy_n == 0));
assign s_axi_bid = r_awid;
assign s_axi_bresp = r_bresp;
assign s_axi_bvalid = (r_wr_state == LP_WR_RESP);

assign dma_cmd_wr_en = r_dma_cmd_wr_en;
assign dma_cmd_wr_data0 = r_dma_cmd_wr_data0;
assign dma_cmd_wr_data1 = r_dma_cmd_wr_data1;

assign w_rd_last_beat = (r_rd_beats_left == 8'd0);
assign w_ar_beat_bytes = (s_axi_arsize <= 3'd2) ? 8'd4 :
                         (s_axi_arsize == 3'd3) ? ((LP_BEAT_BYTES < 8) ? LP_BEAT_BYTES : 8'd8) :
                         LP_BEAT_BYTES;
assign w_ar_words_per_beat = (s_axi_arsize <= 3'd2) ? 3'd1 :
                             (s_axi_arsize == 3'd3) ? ((LP_WORDS_PER_BEAT < 2) ? LP_WORDS_PER_BEAT : 3'd2) :
                             LP_WORDS_PER_BEAT;
assign w_lane_base = (C_S_AXI_DATA_WIDTH == 128) ? {1'b0, r_rd_addr[3:2]} :
                     (C_S_AXI_DATA_WIDTH == 64)  ? {2'b0, r_rd_addr[2]} : 3'd0;
assign w_lane_index = w_lane_base + r_capture_index;
assign w_table_word_addr = r_rd_addr[(P_SLOT_TAG_WIDTH+2)+3:2];
assign hcmd_table_rd_active = (r_rd_state == LP_RD_SET_ADDR) || (r_rd_state == LP_RD_CAPTURE);
assign hcmd_table_rd_addr = w_table_word_addr;
assign w_aw_packed_dma = (s_axi_awaddr[LP_PACKED_DMA_ADDR_BIT] == 1'b1);
assign w_wr_accept = (s_axi_wvalid == 1) && (s_axi_wready == 1);
assign w_wr_byte_base = (C_S_AXI_DATA_WIDTH == 128) ? 4'd0 :
						(C_S_AXI_DATA_WIDTH == 64)  ? {r_wr_addr_low[3], 3'b000} :
												 {r_wr_addr_low[3:2], 2'b00};
assign w_dma_payload_complete = (r_dma_payload_valid_next == 16'hFFFF);

integer w_byte_idx;
integer w_payload_idx;

always @ (*)
begin
	r_dma_payload_next = r_dma_payload;
	r_dma_payload_valid_next = r_dma_payload_valid;
	for(w_byte_idx = 0; w_byte_idx < LP_BEAT_BYTES; w_byte_idx = w_byte_idx + 1) begin
		w_payload_idx = w_wr_byte_base + w_byte_idx;
		if(s_axi_wstrb[w_byte_idx] == 1'b1 && w_payload_idx < 16) begin
			r_dma_payload_next[(w_payload_idx * 8) +: 8] = s_axi_wdata[(w_byte_idx * 8) +: 8];
			r_dma_payload_valid_next[w_payload_idx] = 1'b1;
		end
	end
end

always @ (posedge s_axi_aclk or negedge s_axi_aresetn)
begin
	if(s_axi_aresetn == 0) begin
		r_rd_state <= LP_RD_IDLE;
		r_arid <= 0;
		r_rd_addr <= 0;
		r_rd_beats_left <= 0;
		r_arburst <= 0;
		r_word_index <= 0;
		r_capture_index <= 0;
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
					r_capture_index <= 0;
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
				r_rdata <= hcmd_table_rd_data_sqe;
				r_rd_state <= LP_RD_SEND;
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
						r_capture_index <= 0;
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
		r_bresp <= 0;
		r_dma_cmd_wr_en <= 0;
		r_dma_cmd_wr_data0 <= 0;
		r_dma_cmd_wr_data1 <= 0;
		r_wr_packed_dma <= 0;
		r_dma_cmd_sent <= 0;
		r_dma_payload <= 0;
		r_dma_payload_valid <= 0;
		r_wr_addr_low <= 0;
		r_awburst <= 0;
	end
	else begin
		r_dma_cmd_wr_en <= 0;
		case(r_wr_state)
			LP_WR_IDLE: begin
				if(s_axi_awvalid == 1) begin
					r_awid <= s_axi_awid;
					r_bresp <= 2'b00;
					r_wr_packed_dma <= w_aw_packed_dma;
					if(w_aw_packed_dma == 1 && s_axi_awaddr[3:0] == 4'd0) begin
						r_dma_payload <= 0;
						r_dma_payload_valid <= 0;
					end
					r_wr_addr_low <= s_axi_awaddr[3:0];
					r_awburst <= s_axi_awburst;
					r_dma_cmd_sent <= 0;
					r_wr_state <= LP_WR_DATA;
				end
			end
			LP_WR_DATA: begin
				if(w_wr_accept == 1) begin
					if(r_wr_packed_dma == 1) begin
						r_dma_payload <= r_dma_payload_next;
						r_dma_payload_valid <= r_dma_payload_valid_next;
						if(w_dma_payload_complete == 1 && r_dma_cmd_sent == 0) begin
							r_dma_cmd_wr_data0 <= {{(13-P_SLOT_TAG_WIDTH){1'b0}},
									r_dma_payload_next[95], r_dma_payload_next[94],
									r_dma_payload_next[105:96], r_dma_payload_next[76:66],
									r_dma_payload_next[63:2]};
							r_dma_cmd_wr_data1 <= {{32{1'b0}}, r_dma_payload_next[77],
									r_dma_payload_next[86:78], {46{1'b0}}};
							r_dma_cmd_wr_en <= 1;
							r_dma_cmd_sent <= 1;
						end
						if(r_awburst != 2'b00)
							r_wr_addr_low <= r_wr_addr_low + LP_BEAT_BYTES[3:0];
					end
					else begin
						r_bresp <= 2'b10;
					end

					if(s_axi_wlast == 1)
						r_wr_state <= LP_WR_RESP;
				end
			end
			LP_WR_RESP: begin
				if(s_axi_bready == 1) begin
					r_wr_packed_dma <= 0;
					r_wr_state <= LP_WR_IDLE;
				end
			end
			default: begin
				r_wr_state <= LP_WR_IDLE;
			end
		endcase
	end
end

endmodule
