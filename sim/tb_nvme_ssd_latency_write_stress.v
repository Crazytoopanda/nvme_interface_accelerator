`timescale 1ns / 1ps

module tb_nvme_ssd_latency_write_stress;
localparam SLOT_W = 10;
localparam CQ_W = SLOT_W + 28;
localparam ROUND_SLOTS = 1024;
localparam ROUNDS = 2;

reg cpu_clk = 0;
reg pcie_clk = 0;
reg cpu_rst_n = 0;
reg pcie_rst_n = 0;
reg model_enable = 0;
reg model_reset = 0;
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

integer round;
integer slot;
integer target_release;
integer inspect_slot;
integer pending_count;
integer due_count;

always #5 cpu_clk = ~cpu_clk;
always #2 pcie_clk = ~pcie_clk;

nvme_ssd_latency #(.P_SLOT_TAG_WIDTH(SLOT_W)) dut (
	.cpu_bus_clk(cpu_clk), .cpu_bus_rst_n(cpu_rst_n),
	.model_cmd_wr_en(meta_en), .model_cmd_wr_data0(meta0),
	.model_cmd_wr_data1(meta1), .model_cmd_wr_rdy_n(meta_rdy_n),
	.pcie_user_clk(pcie_clk), .pcie_user_rst_n(pcie_rst_n),
	.model_enable(model_enable), .model_reset(model_reset),
	.read_lsb_cycles(32'd7440), .read_msb_cycles(32'd10440),
	.program_cycles(32'd46250), .fw_read_cycles(32'd100),
	.fw_write_cycles(32'd200), .ch_xfer_4k_cycles(32'd808),
	.channel_count(5'd8),
	.in_cq_wr_en(in_en), .in_cq_wr_data0(in_data0),
	.in_cq_wr_data1(in_data1), .in_cq_wr_rdy_n(in_rdy_n),
	.out_cq_wr_en(out_en), .out_cq_wr_data0(out_data0),
	.out_cq_wr_data1(out_data1), .out_cq_wr_rdy_n(out_rdy_n),
	.model_status(status), .model_submit_count(submit_count),
	.model_release_count(release_count)
);

task send_meta;
	input [SLOT_W-1:0] cmd_slot;
	input [63:0] slba;
	begin
		@(posedge cpu_clk);
		while(meta_rdy_n) @(posedge cpu_clk);
		meta0 <= slba;
		meta1 <= {44'b0, 1'b1, 9'd32, cmd_slot};
		meta_en <= 1;
		@(posedge cpu_clk);
		meta_en <= 0;
	end
endtask

task send_done;
	input [SLOT_W-1:0] cmd_slot;
	begin
		@(negedge pcie_clk);
		in_data0 = {{(CQ_W-SLOT_W-2){1'b0}}, cmd_slot, 2'b01};
		in_data1 = 0;
		while(in_rdy_n) @(negedge pcie_clk);
		in_en = 1;
		@(negedge pcie_clk);
		in_en = 0;
	end
endtask

initial begin
	repeat(40) @(posedge pcie_clk);
	cpu_rst_n = 1;
	pcie_rst_n = 1;
	model_enable = 1;

	for(round = 0; round < ROUNDS; round = round + 1) begin
		for(slot = 0; slot < ROUND_SLOTS; slot = slot + 1) begin
			send_meta(slot[SLOT_W-1:0],
				  ((round * ROUND_SLOTS) + slot) * 64'd32);
			send_done(slot[SLOT_W-1:0]);
		end
		target_release = (round + 1) * ROUND_SLOTS;
		wait(release_count == target_release);
		if(submit_count != target_release)
			$fatal(1, "round %0d release passed metadata submit: submit=%0d release=%0d",
			       round, submit_count, release_count);
	end

	if(|dut.r_dma_pending || |dut.r_due_valid || dut.r_out_valid)
		$fatal(1, "pending state remained after stress: status=%h", status);
	$display("PASS: %0d sequential 128 KiB writes completed across %0d slot-reuse rounds",
		 ROUNDS * ROUND_SLOTS, ROUNDS);
	$finish;
end

initial begin
	#100000000;
	pending_count = 0;
	due_count = 0;
	for(inspect_slot = 0; inspect_slot < 1024; inspect_slot = inspect_slot + 1) begin
		if(dut.r_dma_pending[inspect_slot]) begin
			pending_count = pending_count + 1;
			$display("pending slot=%0d due_valid=%b", inspect_slot, dut.r_due_valid[inspect_slot]);
		end
		if(dut.r_due_valid[inspect_slot])
			due_count = due_count + 1;
	end
	$display("TIMEOUT status=%h submit=%0d release=%0d state=%0d loop_slot=%0d pending=%0d due=%0d wr_bin=%0d rd_bin=%0d wr_gray=%h rd_gray=%h",
		 status, submit_count, release_count, dut.r_model_state, slot, pending_count, due_count,
		 dut.model_metadata_fifo.wr_bin, dut.model_metadata_fifo.rd_bin,
		 dut.model_metadata_fifo.wr_gray, dut.model_metadata_fifo.rd_gray);
	$fatal(1, "write stress timeout");
end
endmodule
