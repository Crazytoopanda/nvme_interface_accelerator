`timescale 1ns / 1ps

module tb_s_axi_reg_bar2_ring;
    localparam integer P_SLOT_TAG_WIDTH = 10;
    localparam integer C_S_AXI_ADDR_WIDTH = 32;
    localparam integer C_S_AXI_DATA_WIDTH = 32;
    localparam integer C_PCIE_ADDR_WIDTH = 48;
    localparam integer C_M_AXI_ADDR_WIDTH = 64;
    localparam integer DMA_CMD_WIDTH = C_M_AXI_ADDR_WIDTH + 24;

    localparam [17:0] BAR2_NVME_STATUS     = 18'h00200;
    localparam [17:0] BAR2_AUTO_BASE       = 18'h00400;
    localparam [17:0] BAR2_AUTO_MAGIC      = BAR2_AUTO_BASE + 18'h000;
    localparam [17:0] BAR2_AUTO_CTRL       = BAR2_AUTO_BASE + 18'h004;
    localparam [17:0] BAR2_AUTO_STATUS     = BAR2_AUTO_BASE + 18'h008;
    localparam [17:0] BAR2_AUTO_ERROR      = BAR2_AUTO_BASE + 18'h00c;
    localparam [17:0] BAR2_AUTO_DDR_BASE_L = BAR2_AUTO_BASE + 18'h010;
    localparam [17:0] BAR2_AUTO_DDR_BASE_H = BAR2_AUTO_BASE + 18'h014;
    localparam [17:0] BAR2_AUTO_DDR_LIM_L  = BAR2_AUTO_BASE + 18'h018;
    localparam [17:0] BAR2_AUTO_DDR_LIM_H  = BAR2_AUTO_BASE + 18'h01c;
    localparam [17:0] BAR2_AUTO_IO_MASK    = BAR2_AUTO_BASE + 18'h020;
    localparam [17:0] BAR2_AUTO_PF0_MSI    = BAR2_AUTO_BASE + 18'h024;
    localparam [17:0] BAR2_AUTO_CQ_MODE    = BAR2_AUTO_BASE + 18'h028;
    localparam [17:0] BAR2_AUTO_CMD_CNT    = BAR2_AUTO_BASE + 18'h030;
    localparam [17:0] BAR2_AUTO_DMA_CNT    = BAR2_AUTO_BASE + 18'h034;
    localparam [17:0] BAR2_AUTO_UNSUP_CNT  = BAR2_AUTO_BASE + 18'h044;
    localparam [17:0] BAR2_AUTO_LAST_QS    = BAR2_AUTO_BASE + 18'h048;
    localparam [17:0] BAR2_AUTO_LAST_OP    = BAR2_AUTO_BASE + 18'h04c;
    localparam [17:0] BAR2_AUTO_LAST_ERR   = BAR2_AUTO_BASE + 18'h050;
    localparam [17:0] BAR2_RING_DESC_BASE  = 18'h20000;
    localparam [17:0] BAR2_RING_CTRL_BASE  = 18'h22000;
    localparam [17:0] BAR2_RING_MAGIC      = BAR2_RING_CTRL_BASE + 18'h000;
    localparam [17:0] BAR2_RING_STATUS     = BAR2_RING_CTRL_BASE + 18'h004;
    localparam [17:0] BAR2_RING_INFO       = BAR2_RING_CTRL_BASE + 18'h008;
    localparam [17:0] BAR2_RING_SUBMIT     = BAR2_RING_CTRL_BASE + 18'h00c;
    localparam [17:0] BAR2_RING_DOORBELL   = BAR2_RING_CTRL_BASE + 18'h010;
    localparam [17:0] BAR2_RING_PID_SUBMIT = BAR2_RING_CTRL_BASE + 18'h018;
    localparam [17:0] BAR2_RING_PID_DONE   = BAR2_RING_CTRL_BASE + 18'h01c;
    localparam [17:0] BAR2_RING_LAST_SUB   = BAR2_RING_CTRL_BASE + 18'h020;
    localparam [17:0] BAR2_RING_LAST_DONE  = BAR2_RING_CTRL_BASE + 18'h024;
    localparam [17:0] BAR2_RING_PF1_CTRL   = BAR2_RING_CTRL_BASE + 18'h028;
    localparam [17:0] BAR2_RING_PF1_THRESH = BAR2_RING_CTRL_BASE + 18'h02c;
    localparam [17:0] BAR2_RING_PF1_COUNT  = BAR2_RING_CTRL_BASE + 18'h030;
    localparam [17:0] BAR2_RING_DONE_COUNT = BAR2_RING_CTRL_BASE + 18'h034;
    localparam [17:0] BAR2_RING_INFLIGHT   = BAR2_RING_CTRL_BASE + 18'h038;
    localparam [17:0] BAR2_RING_PF0_CTRL   = BAR2_RING_CTRL_BASE + 18'h040;
    localparam [17:0] BAR2_RING_PF0_COUNT  = BAR2_RING_CTRL_BASE + 18'h044;

    localparam [63:0] DEV_ADDR = 64'h0000_0001_2345_6000;
    localparam [47:0] PCIE_ADDR = 48'h0000_0abc_d000;
    localparam [9:0] SLOT_TAG = 10'h155;
    localparam [15:0] CID = 16'h40a5;
    localparam [8:0] OFFSET_4K = 9'h015;
    localparam [31:0] DMA_CTRL = 32'hc005_7000;
    localparam [DMA_CMD_WIDTH-1:0] EXP_DMA0 = {3'b000, 1'b1, 1'b1, SLOT_TAG, 11'h400, DEV_ADDR[63:2]};
    localparam [DMA_CMD_WIDTH-1:0] EXP_DMA1 = {32'd0, 1'b1, OFFSET_4K, PCIE_ADDR[47:2]};

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg bar2_reg_req = 1'b0;
    reg bar2_reg_wr = 1'b0;
    reg [17:0] bar2_reg_addr = 18'd0;
    reg [31:0] bar2_reg_wdata = 32'd0;
    reg [3:0] bar2_reg_be = 4'h0;
    wire bar2_reg_ack;
    wire [31:0] bar2_reg_rdata;
    wire bar2_msi_req_toggle;
    wire [8:0] bar2_msi_vector;
    wire bar2_pf0_msi_req_toggle;
    wire [8:0] bar2_pf0_msi_vector;

    wire nvme_csts_rdy;
    wire dma_cmd_wr_en;
    wire [DMA_CMD_WIDTH-1:0] dma_cmd_wr_data0;
    wire [DMA_CMD_WIDTH-1:0] dma_cmd_wr_data1;
    reg dma_cmd_wr_rdy_n = 1'b0;
    reg [7:0] dma_rx_direct_done_cnt = 8'd0;
    reg [7:0] dma_tx_direct_done_cnt = 8'd0;
    reg [7:0] dma_rx_done_cnt = 8'd0;
    reg [7:0] dma_tx_done_cnt = 8'd0;

    wire auto_enable;
    wire auto_reset;
    wire auto_io_read_enable;
    wire auto_io_write_enable;
    wire auto_cq_enable;
    wire auto_msi_enable;
    wire [31:0] auto_cq_mode;
    wire [C_M_AXI_ADDR_WIDTH-1:0] auto_ddr_base;
    wire [C_M_AXI_ADDR_WIDTH-1:0] auto_ddr_limit;
    wire [8:0] auto_io_enable_mask;
    wire [31:0] auto_error_clear;
    reg [31:0] auto_status = 32'h0012_0304;
    reg [31:0] auto_error = 32'h0000_0028;
    reg [31:0] auto_cmd_count = 32'h0000_0011;
    reg [31:0] auto_dma_submit_count = 32'h0000_0022;
    reg [31:0] auto_unsupported_count = 32'h0000_0033;
    reg [31:0] auto_last_qid_slot = 32'h0004_0552;
    reg [31:0] auto_last_opcode = 32'h0000_0002;
    reg [31:0] auto_last_error_info = 32'h0204_0052;
    integer saw_auto_reset = 0;
    reg [31:0] captured_auto_error_clear = 32'h0;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (auto_reset)
            saw_auto_reset <= 1;
        if (auto_error_clear != 32'h0)
            captured_auto_error_clear <= auto_error_clear;
    end

    s_axi_reg #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH)
    ) dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awvalid(1'b0),
        .s_axi_awready(),
        .s_axi_awaddr({C_S_AXI_ADDR_WIDTH{1'b0}}),
        .s_axi_awprot(3'b0),
        .s_axi_wvalid(1'b0),
        .s_axi_wready(),
        .s_axi_wdata({C_S_AXI_DATA_WIDTH{1'b0}}),
        .s_axi_wstrb({(C_S_AXI_DATA_WIDTH/8){1'b0}}),
        .s_axi_bvalid(),
        .s_axi_bready(1'b0),
        .s_axi_bresp(),
        .s_axi_arvalid(1'b0),
        .s_axi_arready(),
        .s_axi_araddr({C_S_AXI_ADDR_WIDTH{1'b0}}),
        .s_axi_arprot(3'b0),
        .s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .s_axi_rdata(),
        .s_axi_rresp(),
        .pcie_mreq_err(1'b0),
        .pcie_cpld_err(1'b0),
        .pcie_cpld_len_err(1'b0),
        .m0_axi_bresp_err(1'b0),
        .m0_axi_rresp_err(1'b0),
        .dev_irq_assert(),
        .pcie_user_logic_rst(),
        .nvme_cc_en(1'b0),
        .nvme_cc_shn(2'b0),
        .nvme_csts_shst(),
        .nvme_csts_rdy(nvme_csts_rdy),
        .sq_valid(),
        .io_sq1_size(), .io_sq2_size(), .io_sq3_size(), .io_sq4_size(),
        .io_sq5_size(), .io_sq6_size(), .io_sq7_size(), .io_sq8_size(),
        .io_sq1_bs_addr(), .io_sq2_bs_addr(), .io_sq3_bs_addr(), .io_sq4_bs_addr(),
        .io_sq5_bs_addr(), .io_sq6_bs_addr(), .io_sq7_bs_addr(), .io_sq8_bs_addr(),
        .io_sq1_cq_vec(), .io_sq2_cq_vec(), .io_sq3_cq_vec(), .io_sq4_cq_vec(),
        .io_sq5_cq_vec(), .io_sq6_cq_vec(), .io_sq7_cq_vec(), .io_sq8_cq_vec(),
        .cq_valid(),
        .io_cq1_size(), .io_cq2_size(), .io_cq3_size(), .io_cq4_size(),
        .io_cq5_size(), .io_cq6_size(), .io_cq7_size(), .io_cq8_size(),
        .io_cq1_bs_addr(), .io_cq2_bs_addr(), .io_cq3_bs_addr(), .io_cq4_bs_addr(),
        .io_cq5_bs_addr(), .io_cq6_bs_addr(), .io_cq7_bs_addr(), .io_cq8_bs_addr(),
        .io_cq_irq_en(),
        .io_cq1_iv(), .io_cq2_iv(), .io_cq3_iv(), .io_cq4_iv(),
        .io_cq5_iv(), .io_cq6_iv(), .io_cq7_iv(), .io_cq8_iv(),
        .hcmd_sq_rd_en(),
        .hcmd_sq_rd_data({(P_SLOT_TAG_WIDTH+12){1'b0}}),
        .hcmd_sq_empty_n(1'b0),
        .hcmd_table_rd_addr(),
        .hcmd_table_rd_data(32'h5a5a_a5a5),
        .hcmd_cq_wr1_en(),
        .hcmd_cq_wr1_data0(),
        .hcmd_cq_wr1_data1(),
        .hcmd_cq_wr1_rdy_n(1'b0),
        .dma_cmd_wr_en(dma_cmd_wr_en),
        .dma_cmd_wr_data0(dma_cmd_wr_data0),
        .dma_cmd_wr_data1(dma_cmd_wr_data1),
        .dma_cmd_wr_rdy_n(dma_cmd_wr_rdy_n),
        .bar2_reg_req(bar2_reg_req),
        .bar2_reg_wr(bar2_reg_wr),
        .bar2_reg_addr(bar2_reg_addr),
        .bar2_reg_wdata(bar2_reg_wdata),
        .bar2_reg_be(bar2_reg_be),
        .bar2_reg_ack(bar2_reg_ack),
        .bar2_reg_rdata(bar2_reg_rdata),
        .bar2_msi_req_toggle(bar2_msi_req_toggle),
        .bar2_msi_vector(bar2_msi_vector),
        .bar2_pf0_msi_req_toggle(bar2_pf0_msi_req_toggle),
        .bar2_pf0_msi_vector(bar2_pf0_msi_vector),
        .dma_rx_direct_done_cnt(dma_rx_direct_done_cnt),
        .dma_tx_direct_done_cnt(dma_tx_direct_done_cnt),
        .dma_rx_done_cnt(dma_rx_done_cnt),
        .dma_tx_done_cnt(dma_tx_done_cnt),
        .pcie_link_up(1'b1),
        .pl_ltssm_state(6'd0),
        .cfg_command(4'd0),
        .cfg_interrupt_mmenable(3'd0),
        .cfg_interrupt_msienable(1'b0),
        .cfg_interrupt_msixenable(1'b0),
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
        .auto_status(auto_status),
        .auto_error(auto_error),
        .auto_cmd_count(auto_cmd_count),
        .auto_dma_submit_count(auto_dma_submit_count),
        .auto_unsupported_count(auto_unsupported_count),
        .auto_last_qid_slot(auto_last_qid_slot),
        .auto_last_opcode(auto_last_opcode),
        .auto_last_error_info(auto_last_error_info),
        .reset_count()
    );

    task fail;
        input [1023:0] msg;
        begin
            $display("FAIL: %0s", msg);
            $finish(1);
        end
    endtask

    task expect32;
        input [1023:0] name;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=0x%08x expected=0x%08x", name, got, exp);
                $finish(1);
            end
        end
    endtask

    task expect_dma;
        input [1023:0] name;
        input [DMA_CMD_WIDTH-1:0] got;
        input [DMA_CMD_WIDTH-1:0] exp;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=0x%022x expected=0x%022x", name, got, exp);
                $finish(1);
            end
        end
    endtask

    task bar2_write;
        input [17:0] addr;
        input [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            bar2_reg_addr <= addr;
            bar2_reg_wdata <= data;
            bar2_reg_be <= 4'hf;
            bar2_reg_wr <= 1'b1;
            bar2_reg_req <= 1'b1;

            timeout = 0;
            while (bar2_reg_ack !== 1'b1) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (timeout > 20)
                    fail("BAR2 write timeout");
            end

            @(negedge clk);
            bar2_reg_req <= 1'b0;
            bar2_reg_wr <= 1'b0;
            bar2_reg_addr <= 18'd0;
            bar2_reg_wdata <= 32'd0;
            bar2_reg_be <= 4'h0;
            @(posedge clk);
            #1;
        end
    endtask

    task bar2_read;
        input [17:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            @(negedge clk);
            bar2_reg_addr <= addr;
            bar2_reg_wdata <= 32'd0;
            bar2_reg_be <= 4'hf;
            bar2_reg_wr <= 1'b0;
            bar2_reg_req <= 1'b1;

            timeout = 0;
            while (bar2_reg_ack !== 1'b1) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (timeout > 20)
                    fail("BAR2 read timeout");
            end
            data = bar2_reg_rdata;

            @(negedge clk);
            bar2_reg_req <= 1'b0;
            bar2_reg_addr <= 18'd0;
            bar2_reg_be <= 4'h0;
            @(posedge clk);
            #1;
        end
    endtask

    task wait_dma_cmd;
        integer i;
        integer found;
        begin
            found = 0;
            for (i = 0; i < 32; i = i + 1) begin
                @(posedge clk);
                #1;
                if (dma_cmd_wr_en == 1'b1) begin
                    found = 1;
                    expect_dma("dma_cmd_wr_data0", dma_cmd_wr_data0, EXP_DMA0);
                    expect_dma("dma_cmd_wr_data1", dma_cmd_wr_data1, EXP_DMA1);
                    i = 32;
                end
            end
            if (found == 0)
                fail("DMA command was not submitted from BAR2 ring");
        end
    endtask

    task wait_toggle;
        input [1023:0] name;
        input old_value;
        input pf0;
        integer i;
        integer found;
        begin
            found = 0;
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                #1;
                if ((pf0 && (bar2_pf0_msi_req_toggle != old_value)) ||
                    (!pf0 && (bar2_msi_req_toggle != old_value))) begin
                    found = 1;
                    i = 16;
                end
            end
            if (found == 0)
                fail(name);
        end
    endtask

    reg [31:0] rd;
    reg old_pf1_toggle;
    reg old_pf0_toggle;

    initial begin
        $dumpfile("tb_s_axi_reg_bar2_ring.vcd");
        $dumpvars(0, tb_s_axi_reg_bar2_ring);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        bar2_read(BAR2_RING_MAGIC, rd);
        expect32("ring magic", rd, 32'hd2c0_0002);
        bar2_read(BAR2_RING_STATUS, rd);
        expect32("initial ring status", rd, 32'h0001_0000);
        bar2_read(BAR2_RING_INFO, rd);
        expect32("initial ring info", rd, 32'h0020_0000);

        bar2_write(BAR2_NVME_STATUS, 32'h0000_0010);
        repeat (2) @(posedge clk);
        if (nvme_csts_rdy !== 1'b1)
            fail("BAR2 write to NVMe status did not reach direct register path");
        bar2_read(BAR2_NVME_STATUS, rd);
        expect32("BAR2 NVMe status readback", rd, 32'h0000_0010);

        bar2_read(BAR2_AUTO_MAGIC, rd);
        expect32("auto magic", rd, 32'ha710_f001);
        bar2_write(BAR2_AUTO_DDR_BASE_L, 32'h0020_0000);
        bar2_write(BAR2_AUTO_DDR_BASE_H, 32'h0000_0050);
        bar2_write(BAR2_AUTO_DDR_LIM_L, 32'h0fff_ffff);
        bar2_write(BAR2_AUTO_DDR_LIM_H, 32'h0000_0050);
        bar2_write(BAR2_AUTO_IO_MASK, 32'h0000_01fe);
        bar2_write(BAR2_AUTO_PF0_MSI, 32'h0000_0101);
        bar2_write(BAR2_AUTO_CQ_MODE, 32'h0000_0000);
        bar2_write(BAR2_AUTO_CTRL, 32'h0000_0f03);
        repeat (2) @(posedge clk);
        if (saw_auto_reset == 0)
            fail("auto reset pulse was not observed");
        if (auto_enable !== 1'b1 || auto_io_read_enable !== 1'b1 || auto_io_write_enable !== 1'b1 ||
            auto_cq_enable !== 1'b1 || auto_msi_enable !== 1'b1)
            fail("auto ctrl outputs were not decoded");
        if (auto_ddr_base !== 64'h0000_0050_0020_0000)
            fail("auto DDR base output mismatch");
        if (auto_ddr_limit !== 64'h0000_0050_0fff_ffff)
            fail("auto DDR limit output mismatch");
        if (auto_io_enable_mask !== 9'h1fe)
            fail("auto IO mask output mismatch");
        bar2_read(BAR2_AUTO_CTRL, rd);
        expect32("auto ctrl readback clears reset bit", rd, 32'h0000_0f01);
        bar2_read(BAR2_AUTO_STATUS, rd);
        expect32("auto status mirror", rd, auto_status);
        bar2_read(BAR2_AUTO_ERROR, rd);
        expect32("auto error mirror", rd, auto_error);
        bar2_read(BAR2_AUTO_CMD_CNT, rd);
        expect32("auto cmd count mirror", rd, auto_cmd_count);
        bar2_read(BAR2_AUTO_DMA_CNT, rd);
        expect32("auto DMA count mirror", rd, auto_dma_submit_count);
        bar2_read(BAR2_AUTO_UNSUP_CNT, rd);
        expect32("auto unsupported count mirror", rd, auto_unsupported_count);
        bar2_read(BAR2_AUTO_LAST_QS, rd);
        expect32("auto last qid/slot mirror", rd, auto_last_qid_slot);
        bar2_read(BAR2_AUTO_LAST_OP, rd);
        expect32("auto last opcode mirror", rd, auto_last_opcode);
        bar2_read(BAR2_AUTO_LAST_ERR, rd);
        expect32("auto last error mirror", rd, auto_last_error_info);
        bar2_write(BAR2_AUTO_ERROR, 32'h0000_0028);
        repeat (2) @(posedge clk);
        expect32("auto error clear pulse", captured_auto_error_clear, 32'h0000_0028);

        bar2_write(BAR2_RING_PF1_CTRL, 32'h0000_0101);
        bar2_write(BAR2_RING_PF1_THRESH, 32'h0000_0001);
        bar2_write(BAR2_RING_PF0_CTRL, 32'h0000_0101);
        bar2_read(BAR2_RING_PF1_CTRL, rd);
        expect32("PF1 MSI control", rd, 32'h0000_0101);
        bar2_read(BAR2_RING_PF0_CTRL, rd);
        expect32("PF0 MSI control", rd, 32'h0000_0101);
        if (bar2_msi_vector !== 9'b000000001)
            fail("PF1 MSI vector was not vector 0");
        if (bar2_pf0_msi_vector !== 9'b000000001)
            fail("PF0 MSI vector was not vector 0");

        bar2_write(BAR2_RING_DESC_BASE + 18'h000, {DEV_ADDR[31:2], 2'b0});
        bar2_write(BAR2_RING_DESC_BASE + 18'h004, DEV_ADDR[63:32]);
        bar2_write(BAR2_RING_DESC_BASE + 18'h008, {PCIE_ADDR[31:2], 2'b0});
        bar2_write(BAR2_RING_DESC_BASE + 18'h00c, {16'd0, PCIE_ADDR[47:32]});
        bar2_write(BAR2_RING_DESC_BASE + 18'h010, DMA_CTRL);
        bar2_write(BAR2_RING_DESC_BASE + 18'h014, {22'd0, SLOT_TAG});
        bar2_write(BAR2_RING_DESC_BASE + 18'h018, {16'd0, CID});
        bar2_read(BAR2_RING_DESC_BASE + 18'h010, rd);
        expect32("descriptor ctrl readback", rd, DMA_CTRL);

        bar2_write(BAR2_RING_MAGIC, 32'h0000_0001);
        wait_dma_cmd();
        repeat (2) @(posedge clk);
        bar2_read(BAR2_RING_SUBMIT, rd);
        expect32("submit count", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_DOORBELL, rd);
        expect32("doorbell count", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_PID_SUBMIT, rd);
        expect32("pid submit", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_INFLIGHT, rd);
        expect32("inflight before done", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_LAST_SUB, rd);
        expect32("last submit pid/cid", rd, {16'h0000, CID});

        old_pf1_toggle = bar2_msi_req_toggle;
        @(negedge clk);
        dma_tx_direct_done_cnt <= dma_tx_direct_done_cnt + 8'd1;
        wait_toggle("PF1 MSI did not toggle after DMA done", old_pf1_toggle, 1'b0);
        repeat (2) @(posedge clk);
        bar2_read(BAR2_RING_PID_DONE, rd);
        expect32("pid done", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_DONE_COUNT, rd);
        expect32("done count", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_PF1_COUNT, rd);
        expect32("PF1 MSI count", rd, 32'h0000_0001);
        bar2_read(BAR2_RING_LAST_DONE, rd);
        expect32("last done pid/cid", rd, {16'h0000, CID});

        old_pf0_toggle = bar2_pf0_msi_req_toggle;
        bar2_write(BAR2_RING_PF0_COUNT, 32'h0000_0001);
        wait_toggle("PF0 manual MSI did not toggle", old_pf0_toggle, 1'b1);
        bar2_read(BAR2_RING_PF0_COUNT, rd);
        expect32("PF0 MSI count", rd, 32'h0000_0001);

        $display("PASS: BAR2 direct register, auto register bank, DMA ring, PF1 auto MSI, and PF0 manual MSI behavior");
        $finish;
    end
endmodule
