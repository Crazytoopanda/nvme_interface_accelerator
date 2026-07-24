`timescale 1ns / 1ps

module tb_nvme_ssd_latency;
localparam SLOT_W = 10;
localparam CQ_W = SLOT_W + 28;

reg cpu_clk = 0;
reg pcie_clk = 0;
reg cpu_rst_n = 0;
reg pcie_rst_n = 0;
reg model_enable = 0;
reg model_reset = 0;
reg [4:0] channel_count = 5'd8;
reg meta_en = 0;
reg [63:0] meta0 = 0;
reg [63:0] meta1 = 0;
wire meta_rdy_n;
reg in_en = 0;
reg [CQ_W-1:0] in_data0 = 0;
reg [CQ_W-1:0] in_data1 = 0;
wire in_rdy_n;
wire out_en;
wire [CQ_W-1:0] out_data0;
wire [CQ_W-1:0] out_data1;
reg out_rdy_n = 0;
wire [31:0] status;
wire [31:0] submit_count;
wire [31:0] release_count;

integer pcie_cycles = 0;
integer submit_cycle = 0;
integer release_cycle = 0;
integer first_release_latency = 0;
integer buffered_write_submit_cycle = 0;
integer buffered_write_release_latency = 0;
integer write_submit_cycle = 0;
integer write_release_latency = 0;
integer page_read_submit_cycle = 0;
integer page_read_release_latency = 0;
reg [63:0] first_due;
reg [63:0] parallel_due0;
reg [63:0] parallel_due1;
reg [63:0] channel16_due0;
reg [63:0] channel16_due8;

always #5 cpu_clk = ~cpu_clk;
always #2 pcie_clk = ~pcie_clk;
always @(posedge pcie_clk) begin
	pcie_cycles <= pcie_cycles + 1;
	if(out_en && !out_rdy_n)
		release_cycle <= pcie_cycles;
end

nvme_ssd_latency #(.P_SLOT_TAG_WIDTH(SLOT_W)) dut (
	.cpu_bus_clk(cpu_clk), .cpu_bus_rst_n(cpu_rst_n),
	.model_cmd_wr_en(meta_en), .model_cmd_wr_data0(meta0),
	.model_cmd_wr_data1(meta1), .model_cmd_wr_rdy_n(meta_rdy_n),
	.pcie_user_clk(pcie_clk), .pcie_user_rst_n(pcie_rst_n),
	.model_enable(model_enable), .model_reset(model_reset),
	.read_lsb_cycles(32'd7440), .read_msb_cycles(32'd10440),
	.program_cycles(32'd46250), .fw_read_cycles(32'd100),
	.fw_write_cycles(32'd200), .ch_xfer_4k_cycles(32'd808),
	.channel_count(channel_count),
	.in_cq_wr_en(in_en), .in_cq_wr_data0(in_data0),
	.in_cq_wr_data1(in_data1), .in_cq_wr_rdy_n(in_rdy_n),
	.out_cq_wr_en(out_en), .out_cq_wr_data0(out_data0),
	.out_cq_wr_data1(out_data1), .out_cq_wr_rdy_n(out_rdy_n),
	.model_status(status), .model_submit_count(submit_count),
	.model_release_count(release_count)
);

task send_meta_segments;
	input [SLOT_W-1:0] slot;
	input [63:0] slba;
	input write_cmd;
	input [8:0] segments;
	begin
		@(posedge cpu_clk);
		while(meta_rdy_n) @(posedge cpu_clk);
		meta0 <= slba;
		meta1 <= {44'b0, write_cmd, segments, slot};
		meta_en <= 1;
		@(posedge cpu_clk);
		meta_en <= 0;
	end
endtask

task send_meta;
	input [SLOT_W-1:0] slot;
	input [63:0] slba;
	input write_cmd;
	begin
		send_meta_segments(slot, slba, write_cmd, 9'd1);
	end
endtask

task send_done;
	input [SLOT_W-1:0] slot;
	begin
		@(posedge pcie_clk);
		while(in_rdy_n) @(posedge pcie_clk);
		in_data0 <= {{(CQ_W-SLOT_W-2){1'b0}}, slot, 2'b01};
		in_data1 <= 0;
		in_en <= 1;
		@(posedge pcie_clk);
		in_en <= 0;
	end
endtask

initial begin
	repeat(40) @(posedge pcie_clk);
	cpu_rst_n = 1;
	pcie_rst_n = 1;

	/* Disabled mode is a combinational, throughput-neutral bypass. */
	in_data0 = {{(CQ_W-SLOT_W-2){1'b0}}, 10'd3, 2'b01};
	in_en = 1;
	#1;
	if(!out_en || out_data0 != in_data0 || in_rdy_n != out_rdy_n)
		$fatal(1, "disabled bypass failed");
	@(posedge pcie_clk);
	in_en = 0;

	model_enable = 1;
	send_meta(10'd5, 64'd0, 1'b0);
	submit_cycle = pcie_cycles;
	send_done(10'd5);
	if(in_rdy_n)
		$fatal(1, "DMA completion was not decoupled");

	send_meta(10'd6, 64'd0, 1'b0);
	send_done(10'd6);
	wait(submit_count == 2);
	first_due = dut.r_due_bank5[0];
	if(dut.r_due_bank6[0] - first_due != 64'd8248)
		$fatal(1, "same-LUN nvmevirt serialization mismatch: %0d cycles",
		       dut.r_due_bank6[0] - first_due);

	wait(release_count == 1);
	first_release_latency = release_cycle - submit_cycle;
	if(out_data0[SLOT_W+1:2] != 10'd5)
		$fatal(1, "wrong released slot");
	if(release_cycle - submit_cycle < 8200 || release_cycle - submit_cycle > 8700)
		$fatal(1, "Samsung 4K LSB read latency mismatch: %0d cycles",
		       release_cycle - submit_cycle);
	if(submit_count != 2)
		$fatal(1, "metadata submit count mismatch");
	wait(release_count == 2);

	/*
	 * SLBA 4 and 8 map to separate NAND channels. Their deadlines must
	 * overlap instead of inheriting the same-LUN serialization interval.
	 */
	send_meta(10'd13, 64'd4, 1'b0);
	send_done(10'd13);
	send_meta(10'd14, 64'd8, 1'b0);
	send_done(10'd14);
	wait(submit_count == 4);
	parallel_due0 = dut.r_due_bank5[1];
	parallel_due1 = dut.r_due_bank6[1];
	if(parallel_due1 < parallel_due0 ||
	   parallel_due1 - parallel_due0 > 64'd32)
		$fatal(1, "different-channel commands serialized: due delta=%0d cycles",
		       parallel_due1 - parallel_due0);
	wait(release_count == 4);

	/* The first three 4 KiB units remain in the 16 KiB write buffer. */
	send_meta(10'd20, 64'd12, 1'b1);
	buffered_write_submit_cycle = pcie_cycles;
	send_done(10'd20);
	wait(release_count == 5);
	buffered_write_release_latency = release_cycle - buffered_write_submit_cycle;
	if(out_data0[SLOT_W+1:2] != 10'd20)
		$fatal(1, "wrong released buffered-write slot");
	if(buffered_write_release_latency < 150 || buffered_write_release_latency > 700)
		$fatal(1, "buffered 4K write latency mismatch: %0d cycles",
		       buffered_write_release_latency);

	/* The fourth unit transfers and programs the complete 16 KiB flash page. */
	send_meta(10'd21, 64'd15, 1'b1);
	write_submit_cycle = pcie_cycles;
	send_done(10'd21);
	wait(release_count == 6);
	write_release_latency = release_cycle - write_submit_cycle;
	if(out_data0[SLOT_W+1:2] != 10'd21)
		$fatal(1, "wrong released write slot");
	if(write_release_latency < 49600 || write_release_latency > 50200)
		$fatal(1, "Samsung 16K program latency mismatch: %0d cycles",
		       write_release_latency);

	/*
	 * NVMeVirt aggregates the four 4 KiB units in one 16 KiB flash page:
	 * one NAND sensing delay followed by a 16 KiB channel transfer.
	 */
	send_meta_segments(10'd30, 64'd64, 1'b0, 9'd4);
	page_read_submit_cycle = pcie_cycles;
	send_done(10'd30);
	wait(release_count == 7);
	page_read_release_latency = release_cycle - page_read_submit_cycle;
	if(out_data0[SLOT_W+1:2] != 10'd30)
		$fatal(1, "wrong released 16K read slot");
	if(page_read_release_latency < 10500 || page_read_release_latency > 11200)
		$fatal(1, "16K page read was not aggregated: %0d cycles",
		       page_read_release_latency);

	channel_count = 5'd16;
	model_reset = 1;
	repeat(4) @(posedge pcie_clk);
	model_reset = 0;
	repeat(4) @(posedge pcie_clk);
	if(dut.r_channel_count_s2 != 5'd16)
		$fatal(1, "16-channel configuration did not cross clock domains");
	send_meta(10'd40, 64'd0, 1'b0);
	send_done(10'd40);
	send_meta(10'd41, 64'd32, 1'b0);
	send_done(10'd41);
	wait(submit_count == 2);
	channel16_due0 = dut.r_due_bank0[5];
	channel16_due8 = dut.r_due_bank1[5];
	if(channel16_due8 < channel16_due0 ||
	   channel16_due8 - channel16_due0 > 64'd32)
		$fatal(1, "16-channel mapping serialized channels 0 and 8: delta=%0d",
		       channel16_due8 - channel16_due0);
	wait(release_count == 2);

	$display("PASS: Samsung 970 PRO 4K read=%0d cycles, 16K page read=%0d cycles, buffered-write=%0d cycles, 16K program-write=%0d cycles, same-LUN spacing=8248 cycles, different-channel delta=%0d cycles, 16-channel delta=%0d cycles, bypass and CQ decoupling OK",
		 first_release_latency, page_read_release_latency,
		 buffered_write_release_latency, write_release_latency,
		 parallel_due1 - parallel_due0, channel16_due8 - channel16_due0);
	$finish;
end

initial begin
	#1000000;
	$display("TIMEOUT status=%h submit=%0d release=%0d meta_rdy=%b in_rdy=%b state=%0d empty=%b pending=%b due_valid=%b segs=%h seg=%h slot=%h meta=%h", status, submit_count, release_count, meta_rdy_n, in_rdy_n, dut.r_model_state, dut.w_meta_empty_n, dut.r_dma_pending[5], dut.r_due_valid[5], dut.r_cmd_segments, dut.r_segment, dut.r_cmd_slot, dut.w_meta_data);
	$fatal(1, "timeout");
end
endmodule
