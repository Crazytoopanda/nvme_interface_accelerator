`timescale 1ns / 1ps
module tb_pcie_tx_pipeline;
    localparam integer W=512, K=W/32, N=8;
    localparam [12:2] LEN=11'd128;
    reg clk=0, rst_n=0;
    wire [W-1:0] cc_data, rq_data;
    wire [K-1:0] cc_keep, rq_keep;
    wire cc_last, cc_valid, rq_last, rq_valid;
    wire [80:0] cc_user;
    wire [136:0] rq_user;
    wire arb_rdy, mwr0_rd, mwr0_last, mwr1_rd, mwr1_last;
    reg [W-1:0] mwr1_data={W{1'b0}};
    integer offered=0, word_no=0, reads=0, beats=0, tlps=0, gaps=0, span=0;
    reg started=0;
    wire arb_valid=rst_n && offered<N;
    wire [127:0] head={32'h0,32'h00010080,32'h0,offered[31:0]};

    always #2 clk=~clk;

    pcie_tx_tran #(.C_PCIE_DATA_WIDTH(W)) dut (
        .pcie_user_clk(clk), .pcie_user_rst_n(rst_n),
        .s_axis_cc_tdata(cc_data), .s_axis_cc_tkeep(cc_keep),
        .s_axis_cc_tlast(cc_last), .s_axis_cc_tvalid(cc_valid),
        .s_axis_cc_tuser(cc_user), .s_axis_cc_tready(1'b1),
        .s_axis_rq_tdata(rq_data), .s_axis_rq_tkeep(rq_keep),
        .s_axis_rq_tlast(rq_last), .s_axis_rq_tvalid(rq_valid),
        .s_axis_rq_tuser(rq_user), .s_axis_rq_tready(1'b1),
        .cfg_msg_transmit_done(1'b0), .cfg_msg_transmit(),
        .cfg_msg_transmit_type(), .cfg_msg_transmit_data(),
        .pcie_rq_tag(6'd0), .pcie_rq_tag_vld(1'b0),
        .pcie_tfc_nph_av(2'b11), .pcie_tfc_npd_av(2'b11),
        .pcie_tfc_np_pl_empty(1'b1), .pcie_rq_seq_num(4'd0),
        .pcie_rq_seq_num_vld(1'b0),
        .tx_arb_valid(arb_valid), .tx_arb_gnt(6'b100000),
        .tx_arb_type(3'b100), .tx_pcie_len(LEN),
        .tx_pcie_head(head), .tx_cpld_udata(32'd0), .tx_arb_rdy(arb_rdy),
        .tx_mwr0_rd_en(mwr0_rd), .tx_mwr0_rd_data({W{1'b0}}),
        .tx_mwr0_data_last(mwr0_last),
        .tx_mwr1_rd_en(mwr1_rd), .tx_mwr1_rd_data(mwr1_data),
        .tx_mwr1_data_last(mwr1_last)
    );

    always @(posedge clk) begin
        if(!rst_n) begin
            offered<=0; word_no<=0; reads<=0;
            mwr1_data<={16{32'h10000000}};
        end else begin
            if(arb_valid && arb_rdy) offered<=offered+1;
            if(mwr1_rd) begin
                reads<=reads+1; word_no<=word_no+1;
                mwr1_data<={16{32'h10000000+word_no+1}};
            end
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            beats<=0; tlps<=0; gaps<=0; span<=0; started<=0;
        end else begin
            if(started && tlps<N) span<=span+1;
            if(started && tlps<N && !rq_valid) gaps<=gaps+1;
            if(rq_valid) begin
                if(!started) begin started<=1; span<=1; end
                beats<=beats+1;
                if(rq_last) begin
                    tlps<=tlps+1;
                    if(rq_keep!=16'h000f) begin
                        $display("FAIL: final keep=%h",rq_keep); $finish(1);
                    end
                end
            end
        end
    end

    initial begin
        $dumpfile("tb_pcie_tx_pipeline.vcd");
        $dumpvars(0,tb_pcie_tx_pipeline);
        repeat(5) @(posedge clk); @(negedge clk); rst_n=1;
        repeat(120) @(posedge clk);
        $display("SUMMARY offered=%0d tlps=%0d beats=%0d reads=%0d gaps=%0d span=%0d",
                 offered,tlps,beats,reads,gaps,span);
        if(offered!=N || tlps!=N) begin
            $display("FAIL: incomplete descriptor stream"); $finish(1);
        end
        if(beats!=N*9 || reads!=N*8) begin
            $display("FAIL: expected beats=%0d reads=%0d",N*9,N*8); $finish(1);
        end
        if(gaps!=0 || span!=N*9) begin
            $display("FAIL: avoidable MWr prefetch bubble"); $finish(1);
        end
        if(mwr0_rd || mwr0_last) begin
            $display("FAIL: MWr1 traffic activated MWr0"); $finish(1);
        end
        $display("PASS: eight 512-byte MWr TLPs stream in 72 consecutive RQ cycles");
        $finish;
    end
endmodule
