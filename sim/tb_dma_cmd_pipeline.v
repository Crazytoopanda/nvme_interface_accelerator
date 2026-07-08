`timescale 1ns / 1ps

module tb_dma_cmd_pipeline;
    localparam integer P_SLOT_TAG_WIDTH = 10;
    localparam integer C_PCIE_ADDR_WIDTH = 48;
    localparam integer C_M_AXI_ADDR_WIDTH = 64;
    localparam integer C_PCIE_DATA_WIDTH = 512;
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
    wire dev_tx_cmd_wr_en;
    wire [C_M_AXI_ADDR_WIDTH-3:0] dev_tx_cmd_wr_data;

    wire pcie_cmd_wr_en;
    wire [45:0] pcie_cmd_wr_data;
    wire pcie_cmd_rd_en;
    wire [45:0] pcie_cmd_rd_data;
    wire pcie_cmd_empty_n;

    wire pcie_rx_cmd_wr_en;
    wire [45:0] pcie_rx_cmd_wr_data;
    wire pcie_tx_cmd_wr_en;
    wire [45:0] pcie_tx_cmd_wr_data;

    wire prp_fifo_rd_en;
    wire prp_fifo_free_en;
    wire [7:6] prp_fifo_free_len;

    wire prp_pcie_alloc;
    wire [7:0] prp_pcie_alloc_tag;
    wire [7:6] prp_pcie_tag_alloc_len;
    wire tx_prp_mrd_req;
    wire [7:0] tx_prp_mrd_tag;
    wire [12:2] tx_prp_mrd_len;
    wire [C_PCIE_ADDR_WIDTH-1:2] tx_prp_mrd_addr;

    reg [DMA_CMD_WIDTH-1:0] dma_mem [0:1];
    integer dma_rd_ptr = 0;

    reg [45:0] pcie_fifo [0:7];
    integer pcie_wr_ptr = 0;
    integer pcie_rd_ptr = 0;
    integer pcie_count = 0;

    integer dev_tx_count = 0;
    integer dev_rx_count = 0;
    integer pcie_tx_count = 0;
    integer pcie_rx_count = 0;

    always #5 clk = ~clk;

    assign pcie_cmd_empty_n = (pcie_count != 0);
    assign pcie_cmd_rd_data = pcie_fifo[pcie_rd_ptr];

    dma_cmd_gen #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH)
    ) u_dma_cmd_gen (
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
        .dev_rx_cmd_full_n(1'b1),
        .dev_tx_cmd_wr_en(dev_tx_cmd_wr_en),
        .dev_tx_cmd_wr_data(dev_tx_cmd_wr_data),
        .dev_tx_cmd_full_n(1'b1),
        .pcie_cmd_wr_en(pcie_cmd_wr_en),
        .pcie_cmd_wr_data(pcie_cmd_wr_data),
        .pcie_cmd_full_n(1'b1),
        .prp_pcie_alloc(prp_pcie_alloc),
        .prp_pcie_alloc_tag(prp_pcie_alloc_tag),
        .prp_pcie_tag_alloc_len(prp_pcie_tag_alloc_len),
        .pcie_tag_full_n(1'b1),
        .prp_fifo_full_n(1'b1),
        .tx_prp_mrd_req(tx_prp_mrd_req),
        .tx_prp_mrd_tag(tx_prp_mrd_tag),
        .tx_prp_mrd_len(tx_prp_mrd_len),
        .tx_prp_mrd_addr(tx_prp_mrd_addr),
        .tx_prp_mrd_req_ack(1'b0)
    );

    pcie_dma_cmd_gen #(
        .P_SLOT_TAG_WIDTH(P_SLOT_TAG_WIDTH),
        .C_PCIE_DATA_WIDTH(C_PCIE_DATA_WIDTH),
        .C_PCIE_ADDR_WIDTH(C_PCIE_ADDR_WIDTH)
    ) u_pcie_dma_cmd_gen (
        .pcie_user_clk(clk),
        .pcie_user_rst_n(rst_n),
        .pcie_cmd_rd_en(pcie_cmd_rd_en),
        .pcie_cmd_rd_data(pcie_cmd_rd_data),
        .pcie_cmd_empty_n(pcie_cmd_empty_n),
        .prp_fifo_rd_en(prp_fifo_rd_en),
        .prp_fifo_rd_data({C_PCIE_DATA_WIDTH{1'b0}}),
        .prp_fifo_free_en(prp_fifo_free_en),
        .prp_fifo_free_len(prp_fifo_free_len),
        .prp_fifo_empty_n(1'b0),
        .pcie_rx_cmd_wr_en(pcie_rx_cmd_wr_en),
        .pcie_rx_cmd_wr_data(pcie_rx_cmd_wr_data),
        .pcie_rx_cmd_full_n(1'b1),
        .pcie_tx_cmd_wr_en(pcie_tx_cmd_wr_en),
        .pcie_tx_cmd_wr_data(pcie_tx_cmd_wr_data),
        .pcie_tx_cmd_full_n(1'b1)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            dma_rd_ptr <= 0;
            dma_cmd_rd_data <= dma_mem[0];
        end else if (dma_cmd_rd_en) begin
            if (dma_rd_ptr == 0) begin
                dma_rd_ptr <= 1;
                dma_cmd_rd_data <= dma_mem[1];
            end else begin
                dma_rd_ptr <= 2;
                dma_cmd_empty_n <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pcie_wr_ptr <= 0;
            pcie_rd_ptr <= 0;
            pcie_count <= 0;
        end else begin
            if (pcie_cmd_wr_en) begin
                pcie_fifo[pcie_wr_ptr] <= pcie_cmd_wr_data;
                pcie_wr_ptr <= (pcie_wr_ptr + 1) & 7;
                pcie_count <= pcie_count + 1;
                $display("%0t PCIE_FIFO_PUSH data=%012h", $time, pcie_cmd_wr_data);
            end
            if (pcie_cmd_rd_en && pcie_count != 0) begin
                pcie_rd_ptr <= (pcie_rd_ptr + 1) & 7;
                pcie_count <= pcie_count - 1;
                $display("%0t PCIE_FIFO_POP  data=%012h", $time, pcie_cmd_rd_data);
            end
        end
    end

    always @(posedge clk) begin
        if (dev_rx_cmd_wr_en) begin
            dev_rx_count <= dev_rx_count + 1;
            $display("%0t DEV_RX   data=%016h", $time, {dev_rx_cmd_wr_data, 2'b0});
        end
        if (dev_tx_cmd_wr_en) begin
            dev_tx_count <= dev_tx_count + 1;
            $display("%0t DEV_TX   data=%016h", $time, {dev_tx_cmd_wr_data, 2'b0});
        end
        if (pcie_rx_cmd_wr_en) begin
            pcie_rx_count <= pcie_rx_count + 1;
            $display("%0t PCIE_RX  data=%012h", $time, pcie_rx_cmd_wr_data);
        end
        if (pcie_tx_cmd_wr_en) begin
            pcie_tx_count <= pcie_tx_count + 1;
            $display("%0t PCIE_TX  data=%012h", $time, pcie_tx_cmd_wr_data);
        end
    end

    initial begin
        $dumpfile("tb_dma_cmd_pipeline.vcd");
        $dumpvars(0, tb_dma_cmd_pipeline);

        dma_mem[0] = {3'b000, 1'b1, 1'b1, 10'd0, 11'h400, 62'h000000140008000};
        dma_mem[1] = {32'd0, 1'b1, 9'd0, 46'h00000ffffd000};
        dma_cmd_rd_data = dma_mem[0];

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        dma_cmd_empty_n = 1'b1;

        repeat (160) @(posedge clk);

        $display("SUMMARY dev_tx=%0d dev_rx=%0d pcie_tx=%0d pcie_rx=%0d",
                 dev_tx_count, dev_rx_count, pcie_tx_count, pcie_rx_count);

        if (dev_tx_count == 0 || dev_rx_count != 0 || pcie_rx_count != 0) begin
            $display("FAIL: dir=1 command was not consistently routed to TX-side queues");
            $finish(1);
        end

        $display("PASS: dir=1 command routes to TX-side queues");
        $finish;
    end
endmodule
