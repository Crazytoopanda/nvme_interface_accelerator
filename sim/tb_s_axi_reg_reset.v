`timescale 1ns / 1ps

module tb_s_axi_reg_reset;
    localparam integer P_SLOT_TAG_WIDTH = 10;
    localparam integer C_S_AXI_ADDR_WIDTH = 32;
    localparam integer C_S_AXI_DATA_WIDTH = 32;
    localparam integer C_PCIE_ADDR_WIDTH = 48;
    localparam integer C_M_AXI_ADDR_WIDTH = 64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg  s_axi_awvalid = 1'b0;
    wire s_axi_awready;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr = 0;
    reg  [2:0] s_axi_awprot = 0;

    reg  s_axi_wvalid = 1'b0;
    wire s_axi_wready;
    reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata = 0;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb = 4'hf;

    wire s_axi_bvalid;
    reg  s_axi_bready = 1'b0;
    wire [1:0] s_axi_bresp;

    reg  s_axi_arvalid = 1'b0;
    wire s_axi_arready;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr = 0;
    reg  [2:0] s_axi_arprot = 0;

    wire s_axi_rvalid;
    reg  s_axi_rready = 1'b0;
    wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;

    wire dev_irq_assert;
    wire pcie_user_logic_rst;
    reg  nvme_cc_en = 1'b0;
    reg  [1:0] nvme_cc_shn = 2'b00;
    wire [1:0] nvme_csts_shst;
    wire nvme_csts_rdy;
    wire [8:0] sq_valid;
    wire [8:0] cq_valid;
    wire [8:0] io_cq_irq_en;
    wire [3:0] reset_count;
    wire [31:0] auto_cq_irq_retry_cycles;
    wire ssd_model_enable;
    wire ssd_model_reset;
    wire [31:0] ssd_read_lsb_cycles;
    wire [31:0] ssd_read_msb_cycles;
    wire [31:0] ssd_program_cycles;
    wire [31:0] ssd_fw_read_cycles;
    wire [31:0] ssd_fw_write_cycles;
    wire [31:0] ssd_ch_xfer_4k_cycles;

    wire [7:0] io_sq1_size, io_sq2_size, io_sq3_size, io_sq4_size;
    wire [7:0] io_sq5_size, io_sq6_size, io_sq7_size, io_sq8_size;
    wire [C_PCIE_ADDR_WIDTH-1:2] io_sq1_bs_addr, io_sq2_bs_addr, io_sq3_bs_addr, io_sq4_bs_addr;
    wire [C_PCIE_ADDR_WIDTH-1:2] io_sq5_bs_addr, io_sq6_bs_addr, io_sq7_bs_addr, io_sq8_bs_addr;
    wire [3:0] io_sq1_cq_vec, io_sq2_cq_vec, io_sq3_cq_vec, io_sq4_cq_vec;
    wire [3:0] io_sq5_cq_vec, io_sq6_cq_vec, io_sq7_cq_vec, io_sq8_cq_vec;
    wire [7:0] io_cq1_size, io_cq2_size, io_cq3_size, io_cq4_size;
    wire [7:0] io_cq5_size, io_cq6_size, io_cq7_size, io_cq8_size;
    wire [C_PCIE_ADDR_WIDTH-1:2] io_cq1_bs_addr, io_cq2_bs_addr, io_cq3_bs_addr, io_cq4_bs_addr;
    wire [C_PCIE_ADDR_WIDTH-1:2] io_cq5_bs_addr, io_cq6_bs_addr, io_cq7_bs_addr, io_cq8_bs_addr;
    wire [2:0] io_cq1_iv, io_cq2_iv, io_cq3_iv, io_cq4_iv;
    wire [2:0] io_cq5_iv, io_cq6_iv, io_cq7_iv, io_cq8_iv;
    wire hcmd_sq_rd_en;
    wire [(P_SLOT_TAG_WIDTH+2)+1:0] hcmd_table_rd_addr;
    wire hcmd_cq_wr1_en;
    wire [(P_SLOT_TAG_WIDTH+28)-1:0] hcmd_cq_wr1_data0;
    wire [(P_SLOT_TAG_WIDTH+28)-1:0] hcmd_cq_wr1_data1;
    wire dma_cmd_wr_en;
    wire [C_M_AXI_ADDR_WIDTH+23:0] dma_cmd_wr_data0;
    wire [C_M_AXI_ADDR_WIDTH+23:0] dma_cmd_wr_data1;

    always #5 clk = ~clk;

    s_axi_reg #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH)
    ) dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .pcie_mreq_err(1'b0),
        .pcie_cpld_err(1'b0),
        .pcie_cpld_len_err(1'b0),
        .m0_axi_bresp_err(1'b0),
        .m0_axi_rresp_err(1'b0),
        .dev_irq_assert(dev_irq_assert),
        .pcie_user_logic_rst(pcie_user_logic_rst),
        .nvme_cc_en(nvme_cc_en),
        .nvme_cc_shn(nvme_cc_shn),
        .nvme_csts_shst(nvme_csts_shst),
        .nvme_csts_rdy(nvme_csts_rdy),
        .sq_valid(sq_valid),
        .io_sq1_size(io_sq1_size), .io_sq2_size(io_sq2_size), .io_sq3_size(io_sq3_size), .io_sq4_size(io_sq4_size),
        .io_sq5_size(io_sq5_size), .io_sq6_size(io_sq6_size), .io_sq7_size(io_sq7_size), .io_sq8_size(io_sq8_size),
        .io_sq1_bs_addr(io_sq1_bs_addr), .io_sq2_bs_addr(io_sq2_bs_addr), .io_sq3_bs_addr(io_sq3_bs_addr), .io_sq4_bs_addr(io_sq4_bs_addr),
        .io_sq5_bs_addr(io_sq5_bs_addr), .io_sq6_bs_addr(io_sq6_bs_addr), .io_sq7_bs_addr(io_sq7_bs_addr), .io_sq8_bs_addr(io_sq8_bs_addr),
        .io_sq1_cq_vec(io_sq1_cq_vec), .io_sq2_cq_vec(io_sq2_cq_vec), .io_sq3_cq_vec(io_sq3_cq_vec), .io_sq4_cq_vec(io_sq4_cq_vec),
        .io_sq5_cq_vec(io_sq5_cq_vec), .io_sq6_cq_vec(io_sq6_cq_vec), .io_sq7_cq_vec(io_sq7_cq_vec), .io_sq8_cq_vec(io_sq8_cq_vec),
        .cq_valid(cq_valid),
        .io_cq1_size(io_cq1_size), .io_cq2_size(io_cq2_size), .io_cq3_size(io_cq3_size), .io_cq4_size(io_cq4_size),
        .io_cq5_size(io_cq5_size), .io_cq6_size(io_cq6_size), .io_cq7_size(io_cq7_size), .io_cq8_size(io_cq8_size),
        .io_cq1_bs_addr(io_cq1_bs_addr), .io_cq2_bs_addr(io_cq2_bs_addr), .io_cq3_bs_addr(io_cq3_bs_addr), .io_cq4_bs_addr(io_cq4_bs_addr),
        .io_cq5_bs_addr(io_cq5_bs_addr), .io_cq6_bs_addr(io_cq6_bs_addr), .io_cq7_bs_addr(io_cq7_bs_addr), .io_cq8_bs_addr(io_cq8_bs_addr),
        .io_cq_irq_en(io_cq_irq_en),
        .io_cq1_iv(io_cq1_iv), .io_cq2_iv(io_cq2_iv), .io_cq3_iv(io_cq3_iv), .io_cq4_iv(io_cq4_iv),
        .io_cq5_iv(io_cq5_iv), .io_cq6_iv(io_cq6_iv), .io_cq7_iv(io_cq7_iv), .io_cq8_iv(io_cq8_iv),
        .hcmd_sq_rd_en(hcmd_sq_rd_en),
        .hcmd_sq_rd_data({(P_SLOT_TAG_WIDTH+12){1'b0}}),
        .hcmd_sq_empty_n(1'b0),
        .hcmd_table_rd_addr(hcmd_table_rd_addr),
        .hcmd_table_rd_data(32'd0),
        .hcmd_cq_wr1_en(hcmd_cq_wr1_en),
        .hcmd_cq_wr1_data0(hcmd_cq_wr1_data0),
        .hcmd_cq_wr1_data1(hcmd_cq_wr1_data1),
        .hcmd_cq_wr1_rdy_n(1'b0),
        .dma_cmd_wr_en(dma_cmd_wr_en),
        .dma_cmd_wr_data0(dma_cmd_wr_data0),
        .dma_cmd_wr_data1(dma_cmd_wr_data1),
        .dma_cmd_wr_rdy_n(1'b0),
        .bar2_reg_req(1'b0),
        .bar2_reg_wr(1'b0),
        .bar2_reg_addr(18'd0),
        .bar2_reg_wdata(32'd0),
        .bar2_reg_be(4'h0),
        .bar2_reg_ack(),
        .bar2_reg_rdata(),
        .bar2_msi_req_toggle(),
        .bar2_msi_vector(),
        .bar2_pf0_msi_req_toggle(),
        .bar2_pf0_msi_vector(),
        .dma_rx_direct_done_cnt(8'd0),
        .dma_tx_direct_done_cnt(8'd0),
        .dma_rx_done_cnt(8'd0),
        .dma_tx_done_cnt(8'd0),
        .pcie_link_up(1'b1),
        .pl_ltssm_state(6'd0),
        .cfg_command(4'd0),
        .cfg_interrupt_mmenable(3'd0),
        .cfg_interrupt_msienable(1'b0),
        .cfg_interrupt_msixenable(1'b0),
        .auto_enable(),
        .auto_reset(),
        .auto_io_read_enable(),
        .auto_io_write_enable(),
        .auto_cq_enable(),
        .auto_msi_enable(),
        .auto_cq_mode(),
        .auto_ddr_base(),
        .auto_ddr_limit(),
        .auto_io_enable_mask(),
        .auto_cq_irq_retry_cycles(auto_cq_irq_retry_cycles),
        .auto_error_clear(),
        .ssd_model_enable(ssd_model_enable),
        .ssd_model_reset(ssd_model_reset),
        .ssd_read_lsb_cycles(ssd_read_lsb_cycles),
        .ssd_read_msb_cycles(ssd_read_msb_cycles),
        .ssd_program_cycles(ssd_program_cycles),
        .ssd_fw_read_cycles(ssd_fw_read_cycles),
        .ssd_fw_write_cycles(ssd_fw_write_cycles),
        .ssd_ch_xfer_4k_cycles(ssd_ch_xfer_4k_cycles),
        .ssd_model_status(32'd0),
        .ssd_model_submit_count(32'd0),
        .ssd_model_release_count(32'd0),
        .cq_dbg_write_count(32'd0),
        .cq_dbg_last_dw2(32'd0),
        .cq_dbg_last_dw3(32'd0),
        .auto_status(32'd0),
        .auto_error(32'd0),
        .auto_cmd_count(32'd0),
        .auto_dma_submit_count(32'd0),
        .auto_unsupported_count(32'd0),
        .auto_last_qid_slot(32'd0),
        .auto_last_opcode(32'd0),
        .auto_last_error_info(32'd0),
        .reset_count(reset_count)
    );

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr <= addr;
            s_axi_awvalid <= 1'b1;
            wait (s_axi_awready == 1'b1);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wdata <= data;
            s_axi_wvalid <= 1'b1;
            wait (s_axi_wready == 1'b1);
            @(posedge clk);
            s_axi_wvalid <= 1'b0;
            s_axi_bready <= 1'b1;
            wait (s_axi_bvalid == 1'b1);
            @(posedge clk);
            s_axi_bready <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task expect_equal;
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

    integer saw_logic_rst;

    initial begin
        $dumpfile("tb_s_axi_reg_reset.vcd");
        $dumpvars(0, tb_s_axi_reg_reset);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        expect_equal("CQ IRQ retry reset default", auto_cq_irq_retry_cycles, 32'h0000_1000);
        expect_equal("SSD read LSB reset default", ssd_read_lsb_cycles, 32'd7440);
        expect_equal("SSD read MSB reset default", ssd_read_msb_cycles, 32'd10440);
        expect_equal("SSD program reset default", ssd_program_cycles, 32'd46250);
        expect_equal("SSD FW read reset default", ssd_fw_read_cycles, 32'd100);
        expect_equal("SSD FW write reset default", ssd_fw_write_cycles, 32'd200);
        expect_equal("SSD channel 4K reset default", ssd_ch_xfer_4k_cycles, 32'd808);
        expect_equal("SSD model disabled after reset", {31'd0, ssd_model_enable}, 32'd0);
        axi_write(32'h0000_0460, 32'h0003_d090);
        expect_equal("CQ IRQ retry firmware value", auto_cq_irq_retry_cycles, 32'h0003_d090);

        axi_write(32'h0000_021c, 32'h0000_0007);
        axi_write(32'h0000_0224, 32'h0001_0000);
        axi_write(32'h0000_0264, 32'h0011_0000);
        expect_equal("sq_valid after queue create", {23'd0, sq_valid}, 32'h0000_0003);
        expect_equal("cq_valid after queue create", {23'd0, cq_valid}, 32'h0000_0003);
        expect_equal("io_cq_irq_en after queue create", {23'd0, io_cq_irq_en}, 32'h0000_0003);

        @(negedge clk);
        nvme_cc_en = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        nvme_cc_en = 1'b0;
        repeat (3) @(posedge clk);
        expect_equal("sq_valid after CC.EN fall", {23'd0, sq_valid}, 32'h0000_0000);
        expect_equal("cq_valid after CC.EN fall", {23'd0, cq_valid}, 32'h0000_0000);
        expect_equal("io_cq_irq_en after CC.EN fall", {23'd0, io_cq_irq_en}, 32'h0000_0000);

        axi_write(32'h0000_021c, 32'h0000_0007);
        axi_write(32'h0000_0224, 32'h0001_0000);
        axi_write(32'h0000_0264, 32'h0011_0000);
        saw_logic_rst = 0;
        fork
            begin
                repeat (16) begin
                    @(posedge clk);
                    if (pcie_user_logic_rst) saw_logic_rst = 1;
                end
            end
            begin
                axi_write(32'h0000_0000, 32'h0000_0001);
            end
        join
        if (saw_logic_rst == 0) begin
            $display("FAIL: pcie_user_logic_rst did not pulse on control reset");
            $finish(1);
        end

        axi_write(32'h0000_0200, 32'h0000_0000);
        expect_equal("sq_valid after status clear", {23'd0, sq_valid}, 32'h0000_0000);
        expect_equal("cq_valid after status clear", {23'd0, cq_valid}, 32'h0000_0000);
        expect_equal("io_cq_irq_en after status clear", {23'd0, io_cq_irq_en}, 32'h0000_0000);
        $display("PASS: s_axi_reg reset/shutdown queue clear behavior");
        $finish;
    end
endmodule
