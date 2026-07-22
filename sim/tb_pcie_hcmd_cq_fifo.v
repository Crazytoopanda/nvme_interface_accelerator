`timescale 1ns / 1ps

module tb_pcie_hcmd_cq_fifo;
	localparam P_SLOT_TAG_WIDTH = 10;
	localparam P_FIFO_DATA_WIDTH = P_SLOT_TAG_WIDTH + 28;
	localparam P_CQE_COUNT = 2048;

	reg clk = 1'b0;
	reg rst_n = 1'b0;
	reg wr0_en = 1'b0;
	reg [P_FIFO_DATA_WIDTH-1:0] wr0_data0 = 0;
	reg [P_FIFO_DATA_WIDTH-1:0] wr0_data1 = 0;
	wire wr0_rdy_n;
	wire full_n;
	reg rd_en = 1'b0;
	wire [P_FIFO_DATA_WIDTH-1:0] rd_data;
	wire empty_n;
	reg wr1_clk = 1'b0;
	reg wr1_rst_n = 1'b0;
	wire wr1_rdy_n;
	integer i;
	reg [P_FIFO_DATA_WIDTH-1:0] got0;
	reg [P_FIFO_DATA_WIDTH-1:0] got1;

	always #5 clk = ~clk;
	always #7 wr1_clk = ~wr1_clk;

	pcie_hcmd_cq_fifo dut (
		.clk(clk),
		.rst_n(rst_n),
		.wr0_en(wr0_en),
		.wr0_data0(wr0_data0),
		.wr0_data1(wr0_data1),
		.wr0_rdy_n(wr0_rdy_n),
		.full_n(full_n),
		.rd_en(rd_en),
		.rd_data(rd_data),
		.empty_n(empty_n),
		.wr1_clk(wr1_clk),
		.wr1_rst_n(wr1_rst_n),
		.wr1_en(1'b0),
		.wr1_data0({P_FIFO_DATA_WIDTH{1'b0}}),
		.wr1_data1({P_FIFO_DATA_WIDTH{1'b0}}),
		.wr1_rdy_n(wr1_rdy_n)
	);

	task push_cqe;
		input integer seq;
		begin
			while(wr0_rdy_n != 1'b0)
				@(negedge clk);
			wr0_data0 = (seq << 1);
			wr0_data1 = (seq << 1) | 1;
			wr0_en = 1'b1;
			@(negedge clk);
			wr0_en = 1'b0;
		end
	endtask

	task pop_and_check_cqe;
		input integer seq;
		begin
			while(empty_n != 1'b1)
				@(negedge clk);
			@(negedge clk);
			rd_en = 1'b1;
			@(posedge clk);
			got0 = rd_data;
			@(posedge clk);
			got1 = rd_data;
			@(negedge clk);
			rd_en = 1'b0;
			if(got0 !== (seq << 1) || got1 !== ((seq << 1) | 1)) begin
				$display("FAIL: seq=%0d got0=0x%0h got1=0x%0h", seq, got0, got1);
				$finish;
			end
		end
	endtask

	initial begin
		repeat(5) @(posedge clk);
		rst_n = 1'b1;
		wr1_rst_n = 1'b1;
		repeat(3) @(posedge clk);

		for(i = 0; i < P_CQE_COUNT; i = i + 1)
			push_cqe(i);
		repeat(8) @(posedge clk);
		if(full_n !== 1'b0 || wr0_rdy_n !== 1'b1) begin
			$display("FAIL: 2048-CQE FIFO did not assert full backpressure");
			$finish;
		end

		pop_and_check_cqe(0);
		push_cqe(P_CQE_COUNT);
		for(i = 1; i <= P_CQE_COUNT; i = i + 1)
			pop_and_check_cqe(i);

		repeat(4) @(posedge clk);
		if(empty_n !== 1'b0) begin
			$display("FAIL: FIFO not empty after ordered drain");
			$finish;
		end
		$display("PASS: 2048 CQEs retained in order across full backpressure and pointer wrap");
		$finish;
	end
endmodule
