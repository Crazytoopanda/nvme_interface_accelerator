`timescale 1ns / 1ps

module tb_nvme_auto_io_engine;
    localparam P_SLOT_TAG_WIDTH = 10;
    localparam C_M_AXI_ADDR_WIDTH = 64;
    localparam C_PCIE_ADDR_WIDTH = 48;
    localparam S_IDLE = 5'd0;
    localparam S_SUBMIT = 5'd15;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg auto_enable = 1'b0;
    reg auto_reset = 1'b0;
    reg auto_io_read_enable = 1'b1;
    reg auto_io_write_enable = 1'b1;
    reg auto_cq_enable = 1'b1;
    reg auto_msi_enable = 1'b1;
    reg [31:0] auto_cq_mode = 32'h0;
    reg [C_M_AXI_ADDR_WIDTH-1:0] auto_ddr_base = 64'h00000050_00200000;
    reg [C_M_AXI_ADDR_WIDTH-1:0] auto_ddr_limit = 64'h00000050_002fffff;
    reg [8:0] auto_io_enable_mask = 9'h1fe;
    reg [31:0] auto_error_clear = 32'h0;

    wire hcmd_sq_rd_en;
    reg [(P_SLOT_TAG_WIDTH+12)-1:0] hcmd_sq_rd_data = 22'h0;
    reg hcmd_sq_empty_n = 1'b0;

    wire hcmd_table_rd_active;
    wire [(P_SLOT_TAG_WIDTH+2)+1:0] hcmd_table_rd_addr;
    reg [31:0] hcmd_table_rd_data;

    wire dma_cmd_wr_en;
    wire [C_M_AXI_ADDR_WIDTH+23:0] dma_cmd_wr_data0;
    wire [C_M_AXI_ADDR_WIDTH+23:0] dma_cmd_wr_data1;
    wire dma_cmd_wr_rdy_n;

    wire [31:0] auto_status;
    wire [31:0] auto_error;
    wire [31:0] auto_cmd_count;
    wire [31:0] auto_dma_submit_count;
    wire [31:0] auto_unsupported_count;
    wire [31:0] auto_last_qid_slot;
    wire [31:0] auto_last_opcode;
    wire [31:0] auto_last_error_info;

    reg [7:0] cmd_opcode = 8'h02;
    reg [15:0] cmd_nlb = 16'h0;
    reg [63:0] cmd_slba = 64'h0;
    reg [7:0] cmd_seq = 8'h0;
    reg [P_SLOT_TAG_WIDTH-1:0] cmd_slot = 10'h0;
    reg [3:0] cmd_qid = 4'h0;
    reg [7:0] stall_remaining = 8'h0;

    integer dma_count = 0;
    reg [C_M_AXI_ADDR_WIDTH+23:0] got_data0 [0:15];
    reg [C_M_AXI_ADDR_WIDTH+23:0] got_data1 [0:15];

    assign dma_cmd_wr_rdy_n = (stall_remaining != 0 && auto_status[24:20] == S_SUBMIT);

    always #5 clk = ~clk;

    nvme_auto_io_engine #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .auto_enable(auto_enable),
        .auto_reset(auto_reset),
        .auto_io_read_enable(auto_io_read_enable),
        .auto_io_write_enable(auto_io_write_enable),
        .auto_cq_enable(auto_cq_enable),
        .auto_msi_enable(auto_msi_enable),
        .auto_cq_mode(auto_cq_mode),
        .auto_ddr_base(auto_ddr_base),
        .auto_ddr_limit(auto_ddr_limit),
        .auto_io_enable_mask(auto_io_enable_mask),
        .auto_error_clear(auto_error_clear),
        .hcmd_sq_rd_en(hcmd_sq_rd_en),
        .hcmd_sq_rd_data(hcmd_sq_rd_data),
        .hcmd_sq_empty_n(hcmd_sq_empty_n),
        .hcmd_table_rd_active(hcmd_table_rd_active),
        .hcmd_table_rd_addr(hcmd_table_rd_addr),
        .hcmd_table_rd_data(hcmd_table_rd_data),
        .dma_cmd_wr_en(dma_cmd_wr_en),
        .dma_cmd_wr_data0(dma_cmd_wr_data0),
        .dma_cmd_wr_data1(dma_cmd_wr_data1),
        .dma_cmd_wr_rdy_n(dma_cmd_wr_rdy_n),
        .auto_status(auto_status),
        .auto_error(auto_error),
        .auto_cmd_count(auto_cmd_count),
        .auto_dma_submit_count(auto_dma_submit_count),
        .auto_unsupported_count(auto_unsupported_count),
        .auto_last_qid_slot(auto_last_qid_slot),
        .auto_last_opcode(auto_last_opcode),
        .auto_last_error_info(auto_last_error_info)
    );

    always @(*) begin
        case (hcmd_table_rd_addr[3:0])
            4'h0: hcmd_table_rd_data = {16'h1234, 8'h00, cmd_opcode};
            4'ha: hcmd_table_rd_data = cmd_slba[31:0];
            4'hb: hcmd_table_rd_data = cmd_slba[63:32];
            4'hc: hcmd_table_rd_data = {16'h0, cmd_nlb};
            default: hcmd_table_rd_data = 32'h0;
        endcase
    end

    always @(posedge clk) begin
        auto_error_clear <= 32'h0;
        if (hcmd_sq_rd_en)
            hcmd_sq_empty_n <= 1'b0;
        if (dma_cmd_wr_en) begin
            got_data0[dma_count] <= dma_cmd_wr_data0;
            got_data1[dma_count] <= dma_cmd_wr_data1;
            $display("DMA %0d type=%0d dir=%0d slot=%0d len4B=%0d dev=%016h auto_cpl=%0d off=%0d",
                     dma_count,
                     dma_cmd_wr_data0[C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+10],
                     dma_cmd_wr_data0[C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+9],
                     dma_cmd_wr_data0[(C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+9)-1:C_M_AXI_ADDR_WIDTH+9],
                     dma_cmd_wr_data0[C_M_AXI_ADDR_WIDTH+8:C_M_AXI_ADDR_WIDTH-2],
                     {dma_cmd_wr_data0[C_M_AXI_ADDR_WIDTH-3:0], 2'b0},
                     dma_cmd_wr_data1[55],
                     dma_cmd_wr_data1[54:46]);
            dma_count <= dma_count + 1;
        end
        if (stall_remaining != 0 && auto_status[24:20] == S_SUBMIT)
            stall_remaining <= stall_remaining - 1'b1;
    end

    task fail;
        input [1023:0] msg;
        begin
            $display("FAIL: %0s", msg);
            $finish(1);
        end
    endtask

    task clear_engine_error;
        begin
            @(negedge clk);
            auto_error_clear = 32'hffffffff;
            @(negedge clk);
            auto_error_clear = 32'h0;
            repeat (3) @(posedge clk);
        end
    endtask

    task start_cmd;
        input [3:0] qid;
        input [P_SLOT_TAG_WIDTH-1:0] slot;
        input [7:0] opcode;
        input [15:0] nlb;
        input [63:0] slba;
        input [7:0] stall_cycles;
        begin
            cmd_qid = qid;
            cmd_slot = slot;
            cmd_opcode = opcode;
            cmd_nlb = nlb;
            cmd_slba = slba;
            cmd_seq = cmd_seq + 1'b1;
            dma_count = 0;
            stall_remaining = stall_cycles;
            hcmd_sq_rd_data = {cmd_seq, slot, qid};
            hcmd_sq_empty_n = 1'b1;
        end
    endtask

    task wait_idle;
        integer i;
        begin
            for (i = 0; i < 200; i = i + 1) begin
                @(posedge clk);
                if (hcmd_sq_empty_n == 1'b0 && auto_status[24:20] == S_IDLE)
                    i = 200;
            end
            if (auto_status[24:20] != S_IDLE)
                fail("engine did not return idle");
        end
    endtask

    task expect_dma;
        input integer idx;
        input dir;
        input [P_SLOT_TAG_WIDTH-1:0] slot;
        input [63:0] dev_addr;
        input [8:0] offset;
        input auto_cpl;
        begin
            if (got_data0[idx][C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+10] !== 1'b0)
                fail("bad auto DMA type");
            if (got_data0[idx][C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+9] !== dir)
                fail("bad DMA direction");
            if (got_data0[idx][(C_M_AXI_ADDR_WIDTH+P_SLOT_TAG_WIDTH+9)-1:C_M_AXI_ADDR_WIDTH+9] !== slot)
                fail("bad slot tag");
            if (got_data0[idx][C_M_AXI_ADDR_WIDTH+8:C_M_AXI_ADDR_WIDTH-2] !== 11'h400)
                fail("bad DMA length");
            if ({got_data0[idx][C_M_AXI_ADDR_WIDTH-3:0], 2'b0} !== dev_addr)
                fail("bad device address");
            if (got_data1[idx][55] !== auto_cpl)
                fail("bad auto completion bit");
            if (got_data1[idx][54:46] !== offset)
                fail("bad 4K offset");
        end
    endtask

    initial begin
        $dumpfile("tb_nvme_auto_io_engine.vcd");
        $dumpvars(0, tb_nvme_auto_io_engine);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        auto_enable = 1'b1;
        repeat (2) @(posedge clk);

        start_cmd(4'd0, 10'd3, 8'h06, 16'd0, 64'd0, 8'd0);
        repeat (10) @(posedge clk);
        if (hcmd_sq_rd_en !== 1'b0)
            fail("admin qid0 was consumed by auto engine");
        if (auto_cmd_count != 0)
            fail("admin qid0 changed auto command count");
        hcmd_sq_empty_n = 1'b0;
        repeat (2) @(posedge clk);

        start_cmd(4'd2, 10'd7, 8'h02, 16'd1, 64'd3, 8'd0);
        wait_idle();
        if (dma_count != 2)
            fail("read command did not emit two DMA segments");
        expect_dma(0, 1'b1, 10'd7, 64'h00000050_00203000, 9'd0, 1'b0);
        expect_dma(1, 1'b1, 10'd7, 64'h00000050_00204000, 9'd1, 1'b1);
        if (auto_error != 32'h0)
            fail("unexpected error after read command");

        start_cmd(4'd1, 10'd8, 8'h01, 16'd0, 64'd10, 8'd3);
        wait_idle();
        if (dma_count != 1)
            fail("write command did not emit one DMA segment");
        expect_dma(0, 1'b0, 10'd8, 64'h00000050_0020a000, 9'd0, 1'b1);
        if (auto_status[10] !== 1'b0)
            fail("DMA stalled bit remained set after backpressure cleared");

        start_cmd(4'd2, 10'd9, 8'h09, 16'd0, 64'd0, 8'd0);
        wait_idle();
        if (dma_count != 0)
            fail("unsupported opcode emitted DMA");
        if ((auto_error & 32'h00000002) == 32'h0)
            fail("unsupported opcode did not set error bit");
        if (auto_status[9] !== 1'b1)
            fail("unsupported pending bit not set");
        clear_engine_error();
        if (auto_error != 32'h0 || auto_status[9] != 1'b0)
            fail("error clear did not clear unsupported state");

        start_cmd(4'd2, 10'd10, 8'h02, 16'd0, 64'h00000100_00000000, 8'd0);
        wait_idle();
        if (dma_count != 0)
            fail("out-of-range command emitted DMA");
        if ((auto_error & 32'h00000008) == 32'h0)
            fail("out-of-range command did not set DDR range error");

        $display("PASS: nvme_auto_io_engine SQ decode, SLBA address, DMA packing, final auto_cpl, backpressure, and error paths verified");
        $finish;
    end
endmodule
