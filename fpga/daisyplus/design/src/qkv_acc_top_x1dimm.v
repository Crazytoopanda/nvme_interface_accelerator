`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 10:28:12 AM
// Design Name: 
// Module Name: qkv_acc_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module qkv_acc_top(
    ddr4_rtl_0_act_n,
    ddr4_rtl_0_adr,
    ddr4_rtl_0_ba,
    ddr4_rtl_0_bg,
    ddr4_rtl_0_ck_c,
    ddr4_rtl_0_ck_t,
    ddr4_rtl_0_cke,
    ddr4_rtl_0_cs_n,
    ddr4_rtl_0_dq,
    ddr4_rtl_0_dqs_c,
    ddr4_rtl_0_dqs_t,
    ddr4_rtl_0_odt,
    ddr4_rtl_0_par,
    ddr4_rtl_0_reset_n,
    diff_clock_rtl_0_clk_n,
    diff_clock_rtl_0_clk_p,
    diff_clock_rtl_1_clk_n,
    diff_clock_rtl_1_clk_p,
    diff_clock_rtl_2_clk_n,
    diff_clock_rtl_2_clk_p,
    pcie_mgt_0_rxn,
    pcie_mgt_0_rxp,
    pcie_mgt_0_txn,
    pcie_mgt_0_txp,
//    init_calib_complete,
    user_link_up_0,
//    gtr_ref_clk2_clk_p,
//    gtr_ref_clk2_clk_n,
    sys_rst_n_0
    );
    
    output ddr4_rtl_0_act_n;
    output [16:0]ddr4_rtl_0_adr;
    output [1:0]ddr4_rtl_0_ba;
    output [1:0]ddr4_rtl_0_bg;
    output [0:0]ddr4_rtl_0_ck_c;
    output [0:0]ddr4_rtl_0_ck_t;
    output [1:0]ddr4_rtl_0_cke;
    output [1:0]ddr4_rtl_0_cs_n;
    inout [71:0]ddr4_rtl_0_dq;
    inout [17:0]ddr4_rtl_0_dqs_c;
    inout [17:0]ddr4_rtl_0_dqs_t;
    output [1:0]ddr4_rtl_0_odt;
    output ddr4_rtl_0_par;
    output ddr4_rtl_0_reset_n;
    input diff_clock_rtl_0_clk_n;
    input diff_clock_rtl_0_clk_p;
    input [0:0]diff_clock_rtl_1_clk_n;
    input [0:0]diff_clock_rtl_1_clk_p;
    input [0:0]diff_clock_rtl_2_clk_n;
    input [0:0]diff_clock_rtl_2_clk_p;
    input [15:0]pcie_mgt_0_rxn;
    input [15:0]pcie_mgt_0_rxp;
    output [15:0]pcie_mgt_0_txn;
    output [15:0]pcie_mgt_0_txp;
//    output wire init_calib_complete;
    input sys_rst_n_0;
    output user_link_up_0;
//    input wire gtr_ref_clk2_clk_p;
//    input wire gtr_ref_clk2_clk_n;

    wire ddr4_rtl_0_act_n;
    wire [16:0]ddr4_rtl_0_adr;
    wire [1:0]ddr4_rtl_0_ba;
    wire [1:0]ddr4_rtl_0_bg;
    wire [0:0]ddr4_rtl_0_ck_c;
    wire [0:0]ddr4_rtl_0_ck_t;
    wire [1:0]ddr4_rtl_0_cke;
    wire [1:0]ddr4_rtl_0_cs_n;
    wire [71:0]ddr4_rtl_0_dq;
    wire [17:0]ddr4_rtl_0_dqs_c;
    wire [17:0]ddr4_rtl_0_dqs_t;
    wire [1:0]ddr4_rtl_0_odt;
    wire ddr4_rtl_0_par;
    wire ddr4_rtl_0_reset_n;
    wire diff_clock_rtl_0_clk_n;
    wire diff_clock_rtl_0_clk_p;
    wire [0:0]diff_clock_rtl_1_clk_n;
    wire [0:0]diff_clock_rtl_1_clk_p;
    wire [0:0]diff_clock_rtl_2_clk_n;
    wire [0:0]diff_clock_rtl_2_clk_p;
    wire [15:0]pcie_mgt_0_rxn;
    wire [15:0]pcie_mgt_0_rxp;
    wire [15:0]pcie_mgt_0_txn;
    wire [15:0]pcie_mgt_0_txp;
    wire sys_rst_n_0;
    wire user_link_up_0;
    
//    wire [63:0]pcie_axi4_m_araddr;
//    wire [1:0]pcie_axi4_m_arburst;
//    wire [3:0]pcie_axi4_m_arcache;
//    wire [3:0]pcie_axi4_m_arid;
//    wire [7:0]pcie_axi4_m_arlen;
//    wire [0:0]pcie_axi4_m_arlock;
//    wire [2:0]pcie_axi4_m_arprot;
//    wire [3:0]pcie_axi4_m_arqos;
//    wire pcie_axi4_m_arready;
//    wire [3:0]pcie_axi4_m_arregion;
//    wire [2:0]pcie_axi4_m_arsize;
//    wire [31:0]pcie_axi4_m_aruser;
//    wire pcie_axi4_m_arvalid;
//    wire [63:0]pcie_axi4_m_awaddr;
//    wire [1:0]pcie_axi4_m_awburst;
//    wire [3:0]pcie_axi4_m_awcache;
//    wire [3:0]pcie_axi4_m_awid;
//    wire [7:0]pcie_axi4_m_awlen;
//    wire [0:0]pcie_axi4_m_awlock;
//    wire [2:0]pcie_axi4_m_awprot;
//    wire [3:0]pcie_axi4_m_awqos;
//    wire pcie_axi4_m_awready;
//    wire [3:0]pcie_axi4_m_awregion;
//    wire [2:0]pcie_axi4_m_awsize;
//    wire [31:0]pcie_axi4_m_awuser;
//    wire pcie_axi4_m_awvalid;
//    wire [3:0]pcie_axi4_m_bid;
//    wire pcie_axi4_m_bready;
//    wire [1:0]pcie_axi4_m_bresp;
//    wire pcie_axi4_m_bvalid;
//    wire [511:0]pcie_axi4_m_rdata;
//    wire [3:0]pcie_axi4_m_rid;
//    wire pcie_axi4_m_rlast;
//    wire pcie_axi4_m_rready;
//    wire [1:0]pcie_axi4_m_rresp;
//    wire pcie_axi4_m_rvalid;
//    wire [511:0]pcie_axi4_m_wdata;
//    wire pcie_axi4_m_wlast;
//    wire pcie_axi4_m_wready;
//    wire [63:0]pcie_axi4_m_wstrb;
//    wire [63:0]pcie_axi4_m_wuser;
//    wire pcie_axi4_m_wvalid;
//    wire [63:0]pcie_axi4_s_araddr;
//    wire [1:0]pcie_axi4_s_arburst;
//    wire [3:0]pcie_axi4_s_arcache;
//    wire [7:0]pcie_axi4_s_arlen;
//    wire [0:0]pcie_axi4_s_arlock;
//    wire [2:0]pcie_axi4_s_arprot;
//    wire [3:0]pcie_axi4_s_arqos;
//    wire pcie_axi4_s_arready;
//    wire [2:0]pcie_axi4_s_arsize;
//    wire pcie_axi4_s_arvalid;
//    wire [63:0]pcie_axi4_s_awaddr;
//    wire [1:0]pcie_axi4_s_awburst;
//    wire [3:0]pcie_axi4_s_awcache;
//    wire [7:0]pcie_axi4_s_awlen;
//    wire [0:0]pcie_axi4_s_awlock;
//    wire [2:0]pcie_axi4_s_awprot;
//    wire [3:0]pcie_axi4_s_awqos;
//    wire pcie_axi4_s_awready;
//    wire [2:0]pcie_axi4_s_awsize;
//    wire pcie_axi4_s_awvalid;
//    wire pcie_axi4_s_bready;
//    wire [1:0]pcie_axi4_s_bresp;
//    wire pcie_axi4_s_bvalid;
//    wire [511:0]pcie_axi4_s_rdata;
//    wire pcie_axi4_s_rlast;
//    wire pcie_axi4_s_rready;
//    wire [1:0]pcie_axi4_s_rresp;
//    wire pcie_axi4_s_rvalid;
//    wire [511:0]pcie_axi4_s_wdata;
//    wire pcie_axi4_s_wlast;
//    wire pcie_axi4_s_wready;
//    wire [63:0]pcie_axi4_s_wstrb;
//    wire pcie_axi4_s_wvalid;
    
//    wire [39:0]cpu_axi4_m_araddr;
//    wire [1:0]cpu_axi4_m_arburst;
//    wire [3:0]cpu_axi4_m_arcache;
//    wire [7:0]cpu_axi4_m_arlen;
//    wire [0:0]cpu_axi4_m_arlock;
//    wire [2:0]cpu_axi4_m_arprot;
//    wire [3:0]cpu_axi4_m_arqos;
//    wire cpu_axi4_m_arready;
//    wire [3:0]cpu_axi4_m_arregion;
//    wire [2:0]cpu_axi4_m_arsize;
//    wire cpu_axi4_m_arvalid;
//    wire [39:0]cpu_axi4_m_awaddr;
//    wire [1:0]cpu_axi4_m_awburst;
//    wire [3:0]cpu_axi4_m_awcache;
//    wire [7:0]cpu_axi4_m_awlen;
//    wire [0:0]cpu_axi4_m_awlock;
//    wire [2:0]cpu_axi4_m_awprot;
//    wire [3:0]cpu_axi4_m_awqos;
//    wire cpu_axi4_m_awready;
//    wire [3:0]cpu_axi4_m_awregion;
//    wire [2:0]cpu_axi4_m_awsize;
//    wire cpu_axi4_m_awvalid;
//    wire cpu_axi4_m_bready;
//    wire [1:0]cpu_axi4_m_bresp;
//    wire cpu_axi4_m_bvalid;
//    wire [511:0]cpu_axi4_m_rdata;
//    wire cpu_axi4_m_rlast;
//    wire cpu_axi4_m_rready;
//    wire [1:0]cpu_axi4_m_rresp;
//    wire cpu_axi4_m_rvalid;
//    wire [511:0]cpu_axi4_m_wdata;
//    wire cpu_axi4_m_wlast;
//    wire cpu_axi4_m_wready;
//    wire [63:0]cpu_axi4_m_wstrb;
//    wire cpu_axi4_m_wvalid;
      
//    wire [39:0]cpu_axi4_s_araddr;
//    wire [1:0]cpu_axi4_s_arburst;
//    wire [3:0]cpu_axi4_s_arcache;
//    wire [7:0]cpu_axi4_s_arlen;
//    wire [0:0]cpu_axi4_s_arlock;
//    wire [2:0]cpu_axi4_s_arprot;
//    wire [3:0]cpu_axi4_s_arqos;
//    wire cpu_axi4_s_arready;
//    wire [2:0]cpu_axi4_s_arsize;
//    wire [31:0]cpu_axi4_s_aruser;
//    wire cpu_axi4_s_arvalid;
//    wire [39:0]cpu_axi4_s_awaddr;
//    wire [1:0]cpu_axi4_s_awburst;
//    wire [3:0]cpu_axi4_s_awcache;
//    wire [7:0]cpu_axi4_s_awlen;
//    wire [0:0]cpu_axi4_s_awlock;
//    wire [2:0]cpu_axi4_s_awprot;
//    wire [3:0]cpu_axi4_s_awqos;
//    wire cpu_axi4_s_awready;
//    wire [2:0]cpu_axi4_s_awsize;
//    wire [31:0]cpu_axi4_s_awuser;
//    wire cpu_axi4_s_awvalid;
//    wire cpu_axi4_s_bready;
//    wire [1:0]cpu_axi4_s_bresp;
//    wire cpu_axi4_s_bvalid;
//    wire [511:0]cpu_axi4_s_rdata;
//    wire cpu_axi4_s_rlast;
//    wire cpu_axi4_s_rready;
//    wire [1:0]cpu_axi4_s_rresp;
//    wire cpu_axi4_s_rvalid;
//    wire [511:0]cpu_axi4_s_wdata;
//    wire cpu_axi4_s_wlast;
//    wire cpu_axi4_s_wready;
//    wire [63:0]cpu_axi4_s_wstrb;
//    wire [63:0]cpu_axi4_s_wuser;
//    wire cpu_axi4_s_wvalid;

    qkv_accelerator_wrapper qkv_accelerator_i
        (   
          .user_lnk_up_0(user_link_up_0),
//        .cpu_axi4_m_araddr(cpu_axi4_m_araddr),
//        .cpu_axi4_m_arburst(cpu_axi4_m_arburst),
//        .cpu_axi4_m_arcache(cpu_axi4_m_arcache),
//        .cpu_axi4_m_arlen(cpu_axi4_m_arlen),
//        .cpu_axi4_m_arlock(cpu_axi4_m_arlock),
//        .cpu_axi4_m_arprot(cpu_axi4_m_arprot),
//        .cpu_axi4_m_arqos(cpu_axi4_m_arqos),
//        .cpu_axi4_m_arready(cpu_axi4_m_arready),
//        .cpu_axi4_m_arregion(cpu_axi4_m_arregion),
//        .cpu_axi4_m_arsize(cpu_axi4_m_arsize),
//        .cpu_axi4_m_arvalid(cpu_axi4_m_arvalid),
//        .cpu_axi4_m_awaddr(cpu_axi4_m_awaddr),
//        .cpu_axi4_m_awburst(cpu_axi4_m_awburst),
//        .cpu_axi4_m_awcache(cpu_axi4_m_awcache),
//        .cpu_axi4_m_awlen(cpu_axi4_m_awlen),
//        .cpu_axi4_m_awlock(cpu_axi4_m_awlock),
//        .cpu_axi4_m_awprot(cpu_axi4_m_awprot),
//        .cpu_axi4_m_awqos(cpu_axi4_m_awqos),
//        .cpu_axi4_m_awready(cpu_axi4_m_awready),
//        .cpu_axi4_m_awregion(cpu_axi4_m_awregion),
//        .cpu_axi4_m_awsize(cpu_axi4_m_awsize),
//        .cpu_axi4_m_awvalid(cpu_axi4_m_awvalid),
//        .cpu_axi4_m_bready(cpu_axi4_m_bready),
//        .cpu_axi4_m_bresp(cpu_axi4_m_bresp),
//        .cpu_axi4_m_bvalid(cpu_axi4_m_bvalid),
//        .cpu_axi4_m_rdata(cpu_axi4_m_rdata),
//        .cpu_axi4_m_rlast(cpu_axi4_m_rlast),
//        .cpu_axi4_m_rready(cpu_axi4_m_rready),
//        .cpu_axi4_m_rresp(cpu_axi4_m_rresp),
//        .cpu_axi4_m_rvalid(cpu_axi4_m_rvalid),
//        .cpu_axi4_m_wdata(cpu_axi4_m_wdata),
//        .cpu_axi4_m_wlast(cpu_axi4_m_wlast),
//        .cpu_axi4_m_wready(cpu_axi4_m_wready),
//        .cpu_axi4_m_wstrb(cpu_axi4_m_wstrb),
//        .cpu_axi4_m_wvalid(cpu_axi4_m_wvalid),
        
//        .pcie_axi4_m_araddr(pcie_axi4_m_araddr),
//        .pcie_axi4_m_arburst(pcie_axi4_m_arburst),
//        .pcie_axi4_m_arcache(pcie_axi4_m_arcache),
//        .pcie_axi4_m_arid(pcie_axi4_m_arid),
//        .pcie_axi4_m_arlen(pcie_axi4_m_arlen),
//        .pcie_axi4_m_arlock(pcie_axi4_m_arlock),
//        .pcie_axi4_m_arprot(pcie_axi4_m_arprot),
//        .pcie_axi4_m_arqos(pcie_axi4_m_arqos),
//        .pcie_axi4_m_arready(pcie_axi4_m_arready),
//        .pcie_axi4_m_arregion(pcie_axi4_m_arregion),
//        .pcie_axi4_m_arsize(pcie_axi4_m_arsize),
//        .pcie_axi4_m_aruser(pcie_axi4_m_aruser),
//        .pcie_axi4_m_arvalid(pcie_axi4_m_arvalid),
//        .pcie_axi4_m_awaddr(pcie_axi4_m_awaddr),
//        .pcie_axi4_m_awburst(pcie_axi4_m_awburst),
//        .pcie_axi4_m_awcache(pcie_axi4_m_awcache),
//        .pcie_axi4_m_awid(pcie_axi4_m_awid),
//        .pcie_axi4_m_awlen(pcie_axi4_m_awlen),
//        .pcie_axi4_m_awlock(pcie_axi4_m_awlock),
//        .pcie_axi4_m_awprot(pcie_axi4_m_awprot),
//        .pcie_axi4_m_awqos(pcie_axi4_m_awqos),
//        .pcie_axi4_m_awready(pcie_axi4_m_awready),
//        .pcie_axi4_m_awregion(pcie_axi4_m_awregion),
//        .pcie_axi4_m_awsize(pcie_axi4_m_awsize),
//        .pcie_axi4_m_awuser(pcie_axi4_m_awuser),
//        .pcie_axi4_m_awvalid(pcie_axi4_m_awvalid),
//        .pcie_axi4_m_bid(pcie_axi4_m_bid),
//        .pcie_axi4_m_bready(pcie_axi4_m_bready),
//        .pcie_axi4_m_bresp(pcie_axi4_m_bresp),
//        .pcie_axi4_m_bvalid(pcie_axi4_m_bvalid),
//        .pcie_axi4_m_rdata(pcie_axi4_m_rdata),
//        .pcie_axi4_m_rid(pcie_axi4_m_rid),
//        .pcie_axi4_m_rlast(pcie_axi4_m_rlast),
//        .pcie_axi4_m_rready(pcie_axi4_m_rready),
//        .pcie_axi4_m_rresp(pcie_axi4_m_rresp),
//        .pcie_axi4_m_rvalid(pcie_axi4_m_rvalid),
//        .pcie_axi4_m_wdata(pcie_axi4_m_wdata),
//        .pcie_axi4_m_wlast(pcie_axi4_m_wlast),
//        .pcie_axi4_m_wready(pcie_axi4_m_wready),
//        .pcie_axi4_m_wstrb(pcie_axi4_m_wstrb),
//        .pcie_axi4_m_wuser(pcie_axi4_m_wuser),
//        .pcie_axi4_m_wvalid(pcie_axi4_m_wvalid),
        
        
//        .cpu_axi4_s_araddr(cpu_axi4_m_araddr & {36{1'b1}}),
//        .cpu_axi4_s_arburst(cpu_axi4_m_arburst),
//        .cpu_axi4_s_arcache(cpu_axi4_m_arcache),
//        .cpu_axi4_s_arlen(cpu_axi4_m_arlen),
//        .cpu_axi4_s_arlock(cpu_axi4_m_arlock),
//        .cpu_axi4_s_arprot(cpu_axi4_m_arprot),
//        .cpu_axi4_s_arqos(cpu_axi4_m_arqos),
//        .cpu_axi4_s_arready(cpu_axi4_m_arready),
//        .cpu_axi4_s_arsize(cpu_axi4_m_arsize),
//        .cpu_axi4_s_aruser(cpu_axi4_m_aruser),
//        .cpu_axi4_s_arvalid(cpu_axi4_m_arvalid),
//        .cpu_axi4_s_awaddr(cpu_axi4_m_awaddr & {36{1'b1}}),
//        .cpu_axi4_s_awburst(cpu_axi4_m_awburst),
//        .cpu_axi4_s_awcache(cpu_axi4_m_awcache),
//        .cpu_axi4_s_awlen(cpu_axi4_m_awlen),
//        .cpu_axi4_s_awlock(cpu_axi4_m_awlock),
//        .cpu_axi4_s_awprot(cpu_axi4_m_awprot),
//        .cpu_axi4_s_awqos(cpu_axi4_m_awqos),
//        .cpu_axi4_s_awready(cpu_axi4_m_awready),
//        .cpu_axi4_s_awsize(cpu_axi4_m_awsize),
//        .cpu_axi4_s_awuser(cpu_axi4_m_awuser),
//        .cpu_axi4_s_awvalid(cpu_axi4_m_awvalid),
//        .cpu_axi4_s_bready(cpu_axi4_m_bready),
//        .cpu_axi4_s_bresp(cpu_axi4_m_bresp),
//        .cpu_axi4_s_bvalid(cpu_axi4_m_bvalid),
//        .cpu_axi4_s_rdata(cpu_axi4_m_rdata),
//        .cpu_axi4_s_rlast(cpu_axi4_m_rlast),
//        .cpu_axi4_s_rready(cpu_axi4_m_rready),
//        .cpu_axi4_s_rresp(cpu_axi4_m_rresp),
//        .cpu_axi4_s_rvalid(cpu_axi4_m_rvalid),
//        .cpu_axi4_s_wdata(cpu_axi4_m_wdata),
//        .cpu_axi4_s_wlast(cpu_axi4_m_wlast),
//        .cpu_axi4_s_wready(cpu_axi4_m_wready),
//        .cpu_axi4_s_wstrb(cpu_axi4_m_wstrb),
//        .cpu_axi4_s_wuser(cpu_axi4_m_wuser),
//        .cpu_axi4_s_wvalid(cpu_axi4_m_wvalid),
        
        
        
//        .pcie_axi4_s_araddr(pcie_axi4_m_araddr & {36{1'b1}}),
//        .pcie_axi4_s_arburst(pcie_axi4_m_arburst),
//        .pcie_axi4_s_arcache(pcie_axi4_m_arcache),
//        .pcie_axi4_s_arlen(pcie_axi4_m_arlen),
//        .pcie_axi4_s_arlock(pcie_axi4_m_arlock),
//        .pcie_axi4_s_arprot(pcie_axi4_m_arprot),
//        .pcie_axi4_s_arqos(pcie_axi4_m_arqos),
//        .pcie_axi4_s_arready(pcie_axi4_m_arready),
//        .pcie_axi4_s_arsize(pcie_axi4_m_arsize),
//        .pcie_axi4_s_arvalid(pcie_axi4_m_arvalid),
//        .pcie_axi4_s_awaddr(pcie_axi4_m_awaddr & {36{1'b1}}),
//        .pcie_axi4_s_awburst(pcie_axi4_m_awburst),
//        .pcie_axi4_s_awcache(pcie_axi4_m_awcache),
//        .pcie_axi4_s_awlen(pcie_axi4_m_awlen),
//        .pcie_axi4_s_awlock(pcie_axi4_m_awlock),
//        .pcie_axi4_s_awprot(pcie_axi4_m_awprot),
//        .pcie_axi4_s_awqos(pcie_axi4_m_awqos),
//        .pcie_axi4_s_awready(pcie_axi4_m_awready),
//        .pcie_axi4_s_awsize(pcie_axi4_m_awsize),
//        .pcie_axi4_s_awvalid(pcie_axi4_m_awvalid),
//        .pcie_axi4_s_bready(pcie_axi4_m_bready),
//        .pcie_axi4_s_bresp(pcie_axi4_m_bresp),
//        .pcie_axi4_s_bvalid(pcie_axi4_m_bvalid),
//        .pcie_axi4_s_rdata(pcie_axi4_m_rdata),
//        .pcie_axi4_s_rlast(pcie_axi4_m_rlast),
//        .pcie_axi4_s_rready(pcie_axi4_m_rready),
//        .pcie_axi4_s_rresp(pcie_axi4_m_rresp),
//        .pcie_axi4_s_rvalid(pcie_axi4_m_rvalid),
//        .pcie_axi4_s_wdata(pcie_axi4_m_wdata),
//        .pcie_axi4_s_wlast(pcie_axi4_m_wlast),
//        .pcie_axi4_s_wready(pcie_axi4_m_wready),
//        .pcie_axi4_s_wstrb(pcie_axi4_m_wstrb),
//        .pcie_axi4_s_wvalid(pcie_axi4_m_wvalid),
        
        .ddr4_rtl_0_act_n(ddr4_rtl_0_act_n),
        .ddr4_rtl_0_adr(ddr4_rtl_0_adr),
        .ddr4_rtl_0_ba(ddr4_rtl_0_ba),
        .ddr4_rtl_0_bg(ddr4_rtl_0_bg),
        .ddr4_rtl_0_ck_c(ddr4_rtl_0_ck_c),
        .ddr4_rtl_0_ck_t(ddr4_rtl_0_ck_t),
        .ddr4_rtl_0_cke(ddr4_rtl_0_cke),
        .ddr4_rtl_0_cs_n(ddr4_rtl_0_cs_n),
        .ddr4_rtl_0_dq(ddr4_rtl_0_dq),
        .ddr4_rtl_0_dqs_c(ddr4_rtl_0_dqs_c),
        .ddr4_rtl_0_dqs_t(ddr4_rtl_0_dqs_t),
        .ddr4_rtl_0_odt(ddr4_rtl_0_odt),
        .ddr4_rtl_0_par(ddr4_rtl_0_par),
        .ddr4_rtl_0_reset_n(ddr4_rtl_0_reset_n),
        .diff_clock_rtl_0_clk_n(diff_clock_rtl_0_clk_n),
        .diff_clock_rtl_0_clk_p(diff_clock_rtl_0_clk_p),
        .diff_clock_rtl_1_clk_n(diff_clock_rtl_1_clk_n),
        .diff_clock_rtl_1_clk_p(diff_clock_rtl_1_clk_p),
        .diff_clock_rtl_2_clk_n(diff_clock_rtl_2_clk_n),
        .diff_clock_rtl_2_clk_p(diff_clock_rtl_2_clk_p),
        .pcie_mgt_0_rxn(pcie_mgt_0_rxn),
        .pcie_mgt_0_rxp(pcie_mgt_0_rxp),
        .pcie_mgt_0_txn(pcie_mgt_0_txn),
        .pcie_mgt_0_txp(pcie_mgt_0_txp),
//        .gtr_ref_clk2_clk_p(gtr_ref_clk2_clk_p),
//        .gtr_ref_clk2_clk_n(gtr_ref_clk2_clk_n),
//        .init_calib_complete(init_calib_complete),
        .sys_rst_n_0(sys_rst_n_0)
    );


endmodule
