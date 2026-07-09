`timescale 1ns / 1ps

module tb_pcie_fifo_compare;
	localparam integer DATA_W = 512;
	localparam integer DEPTH_W = 4;
	localparam integer NUM_WORDS = 8;

	reg wr_clk = 1'b0;
	reg rd_clk = 1'b0;
	reg wr_rst_n = 1'b0;
	reg rd_rst_n = 1'b0;

	always #2.000 wr_clk = ~wr_clk;
	initial begin
		#0.700;
		forever #2.000 rd_clk = ~rd_clk;
	end

	reg tx_alloc_en = 1'b0;
	reg [DEPTH_W:0] tx_alloc_len = 1;
	reg tx_wr_en = 1'b0;
	reg [DATA_W-1:0] tx_wr_data = 0;
	wire tx_full_old;
	wire tx_full_new;
	reg tx_rd_en = 1'b0;
	wire [DATA_W-1:0] tx_rd_data_old;
	wire [DATA_W-1:0] tx_rd_data_new;
	reg tx_free_en = 1'b0;
	reg [DEPTH_W:0] tx_free_len = 1;
	wire tx_empty_old;
	wire tx_empty_new;

	reg rx_wr_en = 1'b0;
	reg [DEPTH_W-1:0] rx_wr_addr = 0;
	reg [DATA_W-1:0] rx_wr_data = 0;
	reg [DEPTH_W:0] rx_rear_full_addr = 0;
	reg [DEPTH_W:0] rx_rear_addr = 0;
	reg [DEPTH_W:0] rx_alloc_len = 1;
	wire rx_full_old;
	wire rx_full_new;
	reg rx_rd_en = 1'b0;
	wire [DATA_W-1:0] rx_rd_data_old;
	wire [DATA_W-1:0] rx_rd_data_new;
	reg rx_free_en = 1'b0;
	reg [DEPTH_W:0] rx_free_len = 1;
	wire rx_empty_old;
	wire rx_empty_new;

	integer errors = 0;
	integer rd_cycle = 0;
	integer tx_old_first_empty = -1;
	integer tx_new_first_empty = -1;
	integer rx_old_first_empty = -1;
	integer rx_new_first_empty = -1;

	pcie_tx_fifo_old #(
		.P_FIFO_WR_DATA_WIDTH(DATA_W),
		.P_FIFO_RD_DATA_WIDTH(DATA_W),
		.P_FIFO_DEPTH_WIDTH(DEPTH_W)
	) tx_old (
		.wr_clk(wr_clk),
		.wr_rst_n(wr_rst_n),
		.alloc_en(tx_alloc_en),
		.alloc_len(tx_alloc_len),
		.wr_en(tx_wr_en),
		.wr_data(tx_wr_data),
		.full_n(tx_full_old),
		.rd_clk(rd_clk),
		.rd_rst_n(rd_rst_n),
		.rd_en(tx_rd_en),
		.rd_data(tx_rd_data_old),
		.free_en(tx_free_en),
		.free_len(tx_free_len),
		.empty_n(tx_empty_old)
	);

	pcie_tx_fifo_new #(
		.P_FIFO_WR_DATA_WIDTH(DATA_W),
		.P_FIFO_RD_DATA_WIDTH(DATA_W),
		.P_FIFO_DEPTH_WIDTH(DEPTH_W)
	) tx_new (
		.wr_clk(wr_clk),
		.wr_rst_n(wr_rst_n),
		.alloc_en(tx_alloc_en),
		.alloc_len(tx_alloc_len),
		.wr_en(tx_wr_en),
		.wr_data(tx_wr_data),
		.full_n(tx_full_new),
		.rd_clk(rd_clk),
		.rd_rst_n(rd_rst_n),
		.rd_en(tx_rd_en),
		.rd_data(tx_rd_data_new),
		.free_en(tx_free_en),
		.free_len(tx_free_len),
		.empty_n(tx_empty_new)
	);

	pcie_rx_fifo_old #(
		.P_FIFO_WR_DATA_WIDTH(DATA_W),
		.P_FIFO_RD_DATA_WIDTH(DATA_W),
		.P_FIFO_DEPTH_WIDTH(DEPTH_W)
	) rx_old (
		.wr_clk(wr_clk),
		.wr_rst_n(wr_rst_n),
		.wr_en(rx_wr_en),
		.wr_addr(rx_wr_addr),
		.wr_data(rx_wr_data),
		.rear_full_addr(rx_rear_full_addr),
		.rear_addr(rx_rear_addr),
		.alloc_len(rx_alloc_len),
		.full_n(rx_full_old),
		.rd_clk(rd_clk),
		.rd_rst_n(rd_rst_n),
		.rd_en(rx_rd_en),
		.rd_data(rx_rd_data_old),
		.free_en(rx_free_en),
		.free_len(rx_free_len),
		.empty_n(rx_empty_old)
	);

	pcie_rx_fifo_new #(
		.P_FIFO_WR_DATA_WIDTH(DATA_W),
		.P_FIFO_RD_DATA_WIDTH(DATA_W),
		.P_FIFO_DEPTH_WIDTH(DEPTH_W)
	) rx_new (
		.wr_clk(wr_clk),
		.wr_rst_n(wr_rst_n),
		.wr_en(rx_wr_en),
		.wr_addr(rx_wr_addr),
		.wr_data(rx_wr_data),
		.rear_full_addr(rx_rear_full_addr),
		.rear_addr(rx_rear_addr),
		.alloc_len(rx_alloc_len),
		.full_n(rx_full_new),
		.rd_clk(rd_clk),
		.rd_rst_n(rd_rst_n),
		.rd_en(rx_rd_en),
		.rd_data(rx_rd_data_new),
		.free_en(rx_free_en),
		.free_len(rx_free_len),
		.empty_n(rx_empty_new)
	);

	function [DATA_W-1:0] pat;
		input integer idx;
		reg [31:0] base;
		integer lane;
		begin
			base = 32'hCAFE0000 + idx;
			pat = {DATA_W{1'b0}};
			for(lane = 0; lane < DATA_W/32; lane = lane + 1)
				pat[lane*32 +: 32] = base ^ lane;
		end
	endfunction

	always @(posedge rd_clk) begin
		rd_cycle <= rd_cycle + 1;
		if(tx_empty_old && tx_old_first_empty < 0)
			tx_old_first_empty <= rd_cycle;
		if(tx_empty_new && tx_new_first_empty < 0)
			tx_new_first_empty <= rd_cycle;
		if(rx_empty_old && rx_old_first_empty < 0)
			rx_old_first_empty <= rd_cycle;
		if(rx_empty_new && rx_new_first_empty < 0)
			rx_new_first_empty <= rd_cycle;
	end

	task check_word;
		input [8*8-1:0] name;
		input integer idx;
		input [DATA_W-1:0] got_old;
		input [DATA_W-1:0] got_new;
		reg [DATA_W-1:0] exp;
		begin
			exp = pat(idx);
			if(got_old !== exp) begin
				$display("ERROR: %0s old idx %0d mismatch got=%h exp=%h",
					name, idx, got_old[63:0], exp[63:0]);
				errors = errors + 1;
			end
			if(got_new !== exp) begin
				$display("ERROR: %0s new idx %0d mismatch got=%h exp=%h",
					name, idx, got_new[63:0], exp[63:0]);
				errors = errors + 1;
			end
			if(got_old !== got_new) begin
				$display("ERROR: %0s old/new idx %0d differ old=%h new=%h",
					name, idx, got_old[63:0], got_new[63:0]);
				errors = errors + 1;
			end
		end
	endtask

	task wait_both_tx_empty;
		integer guard;
		begin
			guard = 0;
			while(!(tx_empty_old && tx_empty_new) && guard < 200) begin
				@(negedge rd_clk);
				guard = guard + 1;
			end
			if(guard >= 200) begin
				$display("ERROR: timeout waiting TX empty_n old=%0b new=%0b", tx_empty_old, tx_empty_new);
				errors = errors + 1;
			end
		end
	endtask

	task wait_both_rx_empty;
		integer guard;
		begin
			guard = 0;
			while(!(rx_empty_old && rx_empty_new) && guard < 200) begin
				@(negedge rd_clk);
				guard = guard + 1;
			end
			if(guard >= 200) begin
				$display("ERROR: timeout waiting RX empty_n old=%0b new=%0b", rx_empty_old, rx_empty_new);
				errors = errors + 1;
			end
		end
	endtask

	integer i;

	initial begin
		$display("Starting pcie_tx_fifo/pcie_rx_fifo old-vs-new compare");

		repeat(8) @(posedge wr_clk);
		wr_rst_n = 1'b1;
		rd_rst_n = 1'b1;
		repeat(8) @(posedge wr_clk);

		for(i = 0; i < NUM_WORDS; i = i + 1) begin
			@(negedge wr_clk);
			tx_alloc_en = 1'b1;
			tx_wr_en = 1'b1;
			tx_wr_data = pat(i);
			@(negedge wr_clk);
			tx_alloc_en = 1'b0;
			tx_wr_en = 1'b0;
		end

		for(i = 0; i < NUM_WORDS; i = i + 1) begin
			wait_both_tx_empty();
			@(negedge rd_clk);
			check_word("TX", i, tx_rd_data_old, tx_rd_data_new);
			tx_rd_en = 1'b1;
			tx_free_en = 1'b1;
			@(negedge rd_clk);
			tx_rd_en = 1'b0;
			tx_free_en = 1'b0;
		end

		for(i = 0; i < NUM_WORDS; i = i + 1) begin
			@(negedge wr_clk);
			rx_wr_en = 1'b1;
			rx_wr_addr = i[DEPTH_W-1:0];
			rx_wr_data = pat(i);
			rx_rear_addr = i + 1;
			rx_rear_full_addr = i + 1;
			@(negedge wr_clk);
			rx_wr_en = 1'b0;
		end

		for(i = 0; i < NUM_WORDS; i = i + 1) begin
			wait_both_rx_empty();
			@(negedge rd_clk);
			check_word("RX", i, rx_rd_data_old, rx_rd_data_new);
			rx_rd_en = 1'b1;
			rx_free_en = 1'b1;
			@(negedge rd_clk);
			rx_rd_en = 1'b0;
			rx_free_en = 1'b0;
		end

		$display("TX first empty_n old cycle=%0d new cycle=%0d", tx_old_first_empty, tx_new_first_empty);
		$display("RX first empty_n old cycle=%0d new cycle=%0d", rx_old_first_empty, rx_new_first_empty);

		if(errors == 0)
			$display("PASS: FIFO old/new data order matched");
		else
			$display("FAIL: errors=%0d", errors);

		$finish;
	end
endmodule
