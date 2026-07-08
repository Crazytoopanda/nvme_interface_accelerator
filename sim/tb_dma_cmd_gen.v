`timescale 1ns / 1ps

module tb_dma_cmd_gen;
    localparam integer P_SLOT_TAG_WIDTH = 10;
    localparam integer C_PCIE_ADDR_WIDTH = 48;
    localparam integer C_M_AXI_ADDR_WIDTH = 64;
    localparam integer DMA_CMD_WIDTH = C_M_AXI_ADDR_WIDTH + 24;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    wire dma_cmd_rd_en;
    reg  [DMA_CMD_WIDTH-1:0] dma_cmd_rd_data = {DMA_CMD_WIDTH{1'b0}};
    reg  dma_cmd_empty_n = 1'b0;

    wire [(P_SLOT_TAG_WIDTH+1)-1:0] hcmd_prp_rd_addr;
    reg  [53:0] hcmd_prp_rd_data = 54'd0;

    wire dev_rx_cmd_wr_en;
    wire [C_M_AXI_ADDR_WIDTH-3:0] dev_rx_cmd_wr_data;
    reg  dev_rx_cmd_full_n = 1'b1;

    wire dev_tx_cmd_wr_en;
    wire [C_M_AXI_ADDR_WIDTH-3:0] dev_tx_cmd_wr_data;
    reg  dev_tx_cmd_full_n = 1'b1;

    wire pcie_cmd_wr_en;
    wire [45:0] pcie_cmd_wr_data;
    reg  pcie_cmd_full_n = 1'b1;

    wire prp_pcie_alloc;
    wire [7:0] prp_pcie_alloc_tag;
    wire [7:6] prp_pcie_tag_alloc_len;
    reg  pcie_tag_full_n = 1'b1;
    reg  prp_fifo_full_n = 1'b1;

    wire tx_prp_mrd_req;
    wire [7:0] tx_prp_mrd_tag;
    wire [12:2] tx_prp_mrd_len;
    wire [C_PCIE_ADDR_WIDTH-1:2] tx_prp_mrd_addr;
    reg  tx_prp_mrd_req_ack = 1'b0;

    reg [DMA_CMD_WIDTH-1:0] cmd_mem [0:1];
    integer rd_ptr = 0;
    integer tx_count = 0;
    integer rx_count = 0;

    always #5 clk = ~clk;

    dma_cmd_gen #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH)
    ) dut (
        .pcie_user_clk(clk),
        .pcie_user_rst_n(rst_n),
        .pcie_rcb(1'b0),
        .dma_cmd_rd_en(dma_cmd_rd_en),
        .dma_cmd_rd_data(dma_cmd_rd_data),
        .dma_cmd_empty_n(dma_cmd_empty_n),
        .hcmd_prp_rd_addr(hcmd_prp_rd_addr),
        .hcmd_prp_rd_data(hcmd_prp_rd_data),
        .dev_rx_cmd_wr_en(dev_rx_cmd_wr_en),
        .dev_rx_cmd_wr_data(dev_rx_cmd_wr_data),
        .dev_rx_cmd_full_n(dev_rx_cmd_full_n),
        .dev_tx_cmd_wr_en(dev_tx_cmd_wr_en),
        .dev_tx_cmd_wr_data(dev_tx_cmd_wr_data),
        .dev_tx_cmd_full_n(dev_tx_cmd_full_n),
        .pcie_cmd_wr_en(pcie_cmd_wr_en),
        .pcie_cmd_wr_data(pcie_cmd_wr_data),
        .pcie_cmd_full_n(pcie_cmd_full_n),
        .prp_pcie_alloc(prp_pcie_alloc),
        .prp_pcie_alloc_tag(prp_pcie_alloc_tag),
        .prp_pcie_tag_alloc_len(prp_pcie_tag_alloc_len),
        .pcie_tag_full_n(pcie_tag_full_n),
        .prp_fifo_full_n(prp_fifo_full_n),
        .tx_prp_mrd_req(tx_prp_mrd_req),
        .tx_prp_mrd_tag(tx_prp_mrd_tag),
        .tx_prp_mrd_len(tx_prp_mrd_len),
        .tx_prp_mrd_addr(tx_prp_mrd_addr),
        .tx_prp_mrd_req_ack(tx_prp_mrd_req_ack)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            dma_cmd_rd_data <= cmd_mem[0];
        end else if (dma_cmd_rd_en) begin
            if (rd_ptr == 0) begin
                rd_ptr <= 1;
                dma_cmd_rd_data <= cmd_mem[1];
            end else begin
                rd_ptr <= 2;
                dma_cmd_empty_n <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (dev_rx_cmd_wr_en) begin
            rx_count <= rx_count + 1;
            $display("%0t DEV_RX wr_data=%016h", $time, {dev_rx_cmd_wr_data, 2'b0});
        end
        if (dev_tx_cmd_wr_en) begin
            tx_count <= tx_count + 1;
            $display("%0t DEV_TX wr_data=%016h", $time, {dev_tx_cmd_wr_data, 2'b0});
        end
        if (pcie_cmd_wr_en)
            $display("%0t PCIE_CMD wr_data=%012h", $time, pcie_cmd_wr_data);
    end

    initial begin
        $dumpfile("tb_dma_cmd_gen.vcd");
        $dumpvars(0, tb_dma_cmd_gen);

        // Matches firmware print:
        // dev=00000050_00200000 pcie=00000000_FFFFD000 len=1000
        // type=1, dir=1, tag=0, len[12:2]=0x400, dev_addr[63:2]=0x140008000.
        cmd_mem[0] = {3'b000, 1'b1, 1'b1, 10'd0, 11'h400, 62'h000000140008000};
        cmd_mem[1] = {32'd0, 1'b1, 9'd0, 46'h00000ffffd000};
        dma_cmd_rd_data = cmd_mem[0];

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        dma_cmd_empty_n = 1'b1;

        repeat (80) @(posedge clk);

        $display("SUMMARY tx_count=%0d rx_count=%0d", tx_count, rx_count);
        if (tx_count == 0 || rx_count != 0) begin
            $display("FAIL: dir=1 command did not route exclusively to DEV_TX");
            $finish(1);
        end

        $display("PASS: dir=1 command routes to DEV_TX");
        $finish;
    end
endmodule
