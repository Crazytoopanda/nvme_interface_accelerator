`timescale 1ns / 1ps

module tb_nvme_model_async_fifo;
localparam WIDTH = 16;
localparam ADDR_WIDTH = 2;

reg wr_clk = 0;
reg rd_clk = 0;
reg wr_rst_n = 0;
reg rd_rst_n = 0;
reg wr_en = 0;
reg [WIDTH-1:0] wr_data = 0;
wire wr_rdy_n;
reg rd_en = 0;
wire [WIDTH-1:0] rd_data;
wire empty_n;
integer i;

always #5 wr_clk = ~wr_clk;
always #7 rd_clk = ~rd_clk;

nvme_model_async_fifo #(
	.WIDTH(WIDTH),
	.ADDR_WIDTH(ADDR_WIDTH)
) dut (
	.wr_clk(wr_clk),
	.wr_rst_n(wr_rst_n),
	.wr_en(wr_en),
	.wr_data(wr_data),
	.wr_rdy_n(wr_rdy_n),
	.rd_clk(rd_clk),
	.rd_rst_n(rd_rst_n),
	.rd_en(rd_en),
	.rd_data(rd_data),
	.empty_n(empty_n)
);

task push;
	input [WIDTH-1:0] value;
	begin
		@(negedge wr_clk);
		while(wr_rdy_n)
			@(negedge wr_clk);
		wr_data = value;
		wr_en = 1;
		@(negedge wr_clk);
		wr_en = 0;
	end
endtask

task pop_expect;
	input [WIDTH-1:0] expected;
	begin
		@(negedge rd_clk);
		while(!empty_n)
			@(negedge rd_clk);
		if(rd_data !== expected) begin
			$display("FAIL: got 0x%04x expected 0x%04x", rd_data, expected);
			$finish(1);
		end
		rd_en = 1;
		@(negedge rd_clk);
		rd_en = 0;
	end
endtask

initial begin
	repeat(3) @(posedge wr_clk);
	wr_rst_n = 1;

	/* Hold the read side reset while filling all four RAM entries. */
	for(i = 0; i < 4; i = i + 1)
		push(16'h1000 + i);
	@(negedge wr_clk);
	if(!wr_rdy_n) begin
		$display("FAIL: FIFO did not assert full");
		$finish(1);
	end

	/* A write while full must not change the RAM or write pointer. */
	wr_data = 16'hdead;
	wr_en = 1;
	@(negedge wr_clk);
	wr_en = 0;

	rd_rst_n = 1;
	for(i = 0; i < 4; i = i + 1)
		pop_expect(16'h1000 + i);

	repeat(3) @(posedge rd_clk);
	if(empty_n) begin
		$display("FAIL: FIFO did not become empty");
		$finish(1);
	end

	/* Exercise pointer wrap and independent-clock concurrent traffic. */
	fork
		begin
			for(i = 0; i < 8; i = i + 1)
				push(16'h2000 + i);
		end
		begin : reader
			integer j;
			for(j = 0; j < 8; j = j + 1)
				pop_expect(16'h2000 + j);
		end
	join

	$display("PASS: async FIFO full protection, ordering, wrap and concurrent clocks");
	$finish;
end
endmodule
