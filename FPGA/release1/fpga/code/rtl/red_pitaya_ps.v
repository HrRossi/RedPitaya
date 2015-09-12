/**
 * $Id: red_pitaya_ps.v 961 2014-01-21 11:40:39Z matej.oblak $
 *
 * @brief Red Pitaya Processing System (PS) wrapper. Including simple AXI slave.
 *
 * @Author Matej Oblak
 *
 * (c) Red Pitaya  http://www.redpitaya.com
 *
 * This part of code is written in Verilog hardware description language (HDL).
 * Please visit http://en.wikipedia.org/wiki/Verilog
 * for more details on the language used herein.
 */
/*
 * 2014-10-15 Nils Roos <doctor@smart.ms>
 * Added infrastructure for ADC data transfer to DDR2 RAM through AXI HP bus
 */


/**
 * GENERAL DESCRIPTION:
 *
 * Wrapper of block design.  
 *
 *
 *
 *                   /-------\
 *   PS CLK -------> |       | <---------------------> SPI master & slave
 *   PS RST -------> |  PS   |
 *                   |       | ------------+-------+-> FCLK & reset 
 *                   |       |             |       |
 *   PS MIO <------> |  ARM  |   AXI   /-------\   |
 *   PS DDR <------> |       | <-----> |  AXI  | <---> system bus
 *      ^            \-------/         | SLAVE |   |
 *      |                              \-------/   |
 *  /------\   AXI   /---------\                   |
 *  | DDRC | <-----> | AXI2DDR | <-----------------+-> ADC
 *  \------/         | MASTER  |
 *                   \---------/
 *
 *
 * Module wrappes PS module (BD design from Vivado or EDK from PlanAhead).
 * There is also included simple AXI slave which serves as master for custom
 * system bus. With this simpler bus it is more easy for newbies to develop 
 * their own module communication with ARM.
 * 
 */




module red_pitaya_ps
(
   // PS peripherals
   inout   [ 54-1: 0] FIXED_IO_mio       ,
   inout              FIXED_IO_ps_clk    ,
   inout              FIXED_IO_ps_porb   ,
   inout              FIXED_IO_ps_srstb  ,
   inout              FIXED_IO_ddr_vrn   ,
   inout              FIXED_IO_ddr_vrp   ,
   inout   [ 15-1: 0] DDR_addr           ,
   inout   [  3-1: 0] DDR_ba             ,
   inout              DDR_cas_n          ,
   inout              DDR_ck_n           ,
   inout              DDR_ck_p           ,
   inout              DDR_cke            ,
   inout              DDR_cs_n           ,
   inout   [  4-1: 0] DDR_dm             ,
   inout   [ 32-1: 0] DDR_dq             ,
   inout   [  4-1: 0] DDR_dqs_n          ,
   inout   [  4-1: 0] DDR_dqs_p          ,
   inout              DDR_odt            ,
   inout              DDR_ras_n          ,
   inout              DDR_reset_n        ,
   inout              DDR_we_n           ,

   output  [  4-1: 0] fclk_clk_o         ,
   output  [  4-1: 0] fclk_rstn_o        ,

   // system read/write channel
   output             sys_clk_o          ,  // system clock
   output             sys_rstn_o         ,  // system reset - active low
   output  [ 32-1: 0] sys_addr_o         ,  // system read/write address
   output  [ 32-1: 0] sys_wdata_o        ,  // system write data
   output  [  4-1: 0] sys_sel_o          ,  // system write byte select
   output             sys_wen_o          ,  // system write enable
   output             sys_ren_o          ,  // system read enable
   input   [ 32-1: 0] sys_rdata_i        ,  // system read data
   input              sys_err_i          ,  // system error indicator
   input              sys_ack_i          ,  // system acknowledge signal

   // SPI master
   output             spi_ss_o           ,  // select slave 0
   output             spi_ss1_o          ,  // select slave 1
   output             spi_ss2_o          ,  // select slave 2
   output             spi_sclk_o         ,  // serial clock
   output             spi_mosi_o         ,  // master out slave in
   input              spi_miso_i         ,  // master in slave out
   // SPI slave
   input              spi_ss_i           ,  // slave selected
   input              spi_sclk_i         ,  // serial clock
   input              spi_mosi_i         ,  // master out slave in
   output             spi_miso_o         ,  // master in slave out

    // ADC data buffer
    output [   1:0] adcbuf_select_o ,
    input  [ 4-1:0] adcbuf_ready_i  ,   // [0]: ChA 0-1k, [1]: ChA 1k-2k, [2]: ChB 0-1k, [3]: ChB 1k-2k
    output [ 9-1:0] adcbuf_raddr_o  ,
    input  [64-1:0] adcbuf_rdata_i  ,

    // DDR Dump parameters and signals
    input   [   32-1:0] ddrd_a_base_i , // DDR Dump ChA buffer base address
    input   [   32-1:0] ddrd_a_end_i  , // DDR Dump ChA buffer end address + 1
    output  [   32-1:0] ddrd_a_curr_o , // DDR Dump ChA current write address
    input   [   32-1:0] ddrd_b_base_i , // DDR Dump ChB buffer base address
    input   [   32-1:0] ddrd_b_end_i  , // DDR Dump ChB buffer end address + 1
    output  [   32-1:0] ddrd_b_curr_o , // DDR Dump ChB current write address
    output  [    2-1:0] ddrd_status_o , // DDR Dump [0,1]: INT pending A/B
    input               ddrd_stat_rd_i, // DDR Dump INT pending was read
    input   [    6-1:0] ddrd_control_i, // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B, [4,5]: INT enable A/B
    output              ddrd_irq0_o   , // DDR Dump interrupt request 0

    // PL-PS Interrupt lines
    input   [     15:0] irq_f2p         // ARM GIC ID 91-84,68-61
);


wire [  32-1:0] hp0_saxi_araddr;
wire [     1:0] hp0_saxi_arburst;
wire [     3:0] hp0_saxi_arcache;
wire [   6-1:0] hp0_saxi_arid;
wire [   4-1:0] hp0_saxi_arlen;
wire [     1:0] hp0_saxi_arlock;
wire [     2:0] hp0_saxi_arprot;
wire [     3:0] hp0_saxi_arqos;
wire            hp0_saxi_arready;
wire [     2:0] hp0_saxi_arsize;
wire            hp0_saxi_arvalid;
wire [  32-1:0] hp0_saxi_awaddr;
wire [     1:0] hp0_saxi_awburst;
wire [     3:0] hp0_saxi_awcache;
wire [   6-1:0] hp0_saxi_awid;
wire [   4-1:0] hp0_saxi_awlen;
wire [     1:0] hp0_saxi_awlock;
wire [     2:0] hp0_saxi_awprot;
wire [     3:0] hp0_saxi_awqos;
wire            hp0_saxi_awready;
wire [     2:0] hp0_saxi_awsize;
wire            hp0_saxi_awvalid;
wire [   6-1:0] hp0_saxi_bid;
wire            hp0_saxi_bready;
wire [     1:0] hp0_saxi_bresp;
wire            hp0_saxi_bvalid;
wire [  64-1:0] hp0_saxi_rdata;
wire [   6-1:0] hp0_saxi_rid;
wire            hp0_saxi_rlast;
wire            hp0_saxi_rready;
wire [     1:0] hp0_saxi_rresp;
wire            hp0_saxi_rvalid;
wire [  64-1:0] hp0_saxi_wdata;
wire [   6-1:0] hp0_saxi_wid;
wire            hp0_saxi_wlast;
wire            hp0_saxi_wready;
wire [   8-1:0] hp0_saxi_wstrb;
wire            hp0_saxi_wvalid;
wire            hp0_saxi_arstn;
wire            hp0_saxi_aclk;

axi_dummy_read_master #(
    .AXI_DW     (  64     ), // data width (8,16,...,1024)
    .AXI_AW     (  32     ), // AXI address width
    .AXI_IW     (   6     )  // AXI ID width
) i_hp0_rmaster (
    // AXI master read channel
    .axi_araddr_o   (hp0_saxi_araddr    ),
    .axi_arburst_o  (hp0_saxi_arburst   ),
    .axi_arcache_o  (hp0_saxi_arcache   ),
    .axi_arid_o     (hp0_saxi_arid      ),
    .axi_arlen_o    (hp0_saxi_arlen     ),
    .axi_arlock_o   (hp0_saxi_arlock    ),
    .axi_arprot_o   (hp0_saxi_arprot    ),
    .axi_arqos_o    (hp0_saxi_arqos     ),
    .axi_arready_i  (hp0_saxi_arready   ),
    .axi_arsize_o   (hp0_saxi_arsize    ),
    .axi_arvalid_o  (hp0_saxi_arvalid   ),
    .axi_rdata_i    (hp0_saxi_rdata     ),
    .axi_rid_i      (hp0_saxi_rid       ),
    .axi_rlast_i    (hp0_saxi_rlast     ),
    .axi_rready_o   (hp0_saxi_rready    ),
    .axi_rresp_i    (hp0_saxi_rresp     ),
    .axi_rvalid_i   (hp0_saxi_rvalid    ),
    // AXI clock / reset
    .axi_clk_i      (hp0_saxi_aclk      ),  //
    .axi_rstn_i     (hp0_saxi_arstn     )   //
);

axi_dump2ddr_master #(
    .AXI_DW     (  64     ), // data width (8,16,...,1024)
    .AXI_AW     (  32     ), // AXI address width
    .AXI_IW     (   6     ), // AXI ID width
    .BUF_AW     (   9     ), // Dump buffer address width
    .BUF_CH     (   2     )  // number of buffered channels
) i_hp0_dmaster (
    // AXI master write channel
    .axi_awaddr_o   (hp0_saxi_awaddr    ),
    .axi_awburst_o  (hp0_saxi_awburst   ),
    .axi_awcache_o  (hp0_saxi_awcache   ),
    .axi_awid_o     (hp0_saxi_awid      ),
    .axi_awlen_o    (hp0_saxi_awlen     ),
    .axi_awlock_o   (hp0_saxi_awlock    ),
    .axi_awprot_o   (hp0_saxi_awprot    ),
    .axi_awqos_o    (hp0_saxi_awqos     ),
    .axi_awready_i  (hp0_saxi_awready   ),
    .axi_awsize_o   (hp0_saxi_awsize    ),
    .axi_awvalid_o  (hp0_saxi_awvalid   ),
    .axi_bid_i      (hp0_saxi_bid       ),
    .axi_bready_o   (hp0_saxi_bready    ),
    .axi_bresp_i    (hp0_saxi_bresp     ),
    .axi_bvalid_i   (hp0_saxi_bvalid    ),
    .axi_wdata_o    (hp0_saxi_wdata     ),
    .axi_wid_o      (hp0_saxi_wid       ),
    .axi_wlast_o    (hp0_saxi_wlast     ),
    .axi_wready_i   (hp0_saxi_wready    ),
    .axi_wstrb_o    (hp0_saxi_wstrb     ),
    .axi_wvalid_o   (hp0_saxi_wvalid    ),
    // AXI clock / reset
    .axi_clk_i      (hp0_saxi_aclk      ),  //
    .axi_rstn_i     (hp0_saxi_arstn     ),  //

    // ADC buffer interface
    .buf_select_o   (adcbuf_select_o    ),  //
    .buf_ready_i    (adcbuf_ready_i     ),  //
    .buf_raddr_o    (adcbuf_raddr_o     ),  //
    .buf_rdata_i    (adcbuf_rdata_i     ),  //

    // DDR Dump parameters and signals
    .ddr_a_base_i   (ddrd_a_base_i      ),
    .ddr_a_end_i    (ddrd_a_end_i       ),
    .ddr_a_curr_o   (ddrd_a_curr_o      ),
    .ddr_b_base_i   (ddrd_b_base_i      ),
    .ddr_b_end_i    (ddrd_b_end_i       ),
    .ddr_b_curr_o   (ddrd_b_curr_o      ),
    .ddr_status_o   (ddrd_status_o      ),
    .ddr_stat_rd_i  (ddrd_stat_rd_i     ),
    .ddr_control_i  (ddrd_control_i     ),
    .ddr_irq0_o     (ddrd_irq0_o        )
);





//------------------------------------------------------------------------------
// AXI SLAVE

wire [  4-1: 0] fclk_clk             ;
wire [  4-1: 0] fclk_rstn            ;

wire            gp0_maxi_arvalid     ;
wire            gp0_maxi_awvalid     ;
wire            gp0_maxi_bready      ;
wire            gp0_maxi_rready      ;
wire            gp0_maxi_wlast       ;
wire            gp0_maxi_wvalid      ;
wire [ 12-1: 0] gp0_maxi_arid        ;
wire [ 12-1: 0] gp0_maxi_awid        ;
wire [ 12-1: 0] gp0_maxi_wid         ;
wire [  2-1: 0] gp0_maxi_arburst     ;
wire [  2-1: 0] gp0_maxi_arlock      ;
wire [  3-1: 0] gp0_maxi_arsize      ;
wire [  2-1: 0] gp0_maxi_awburst     ;
wire [  2-1: 0] gp0_maxi_awlock      ;
wire [  3-1: 0] gp0_maxi_awsize      ;
wire [  3-1: 0] gp0_maxi_arprot      ;
wire [  3-1: 0] gp0_maxi_awprot      ;
wire [ 32-1: 0] gp0_maxi_araddr      ;
wire [ 32-1: 0] gp0_maxi_awaddr      ;
wire [ 32-1: 0] gp0_maxi_wdata       ;
wire [  4-1: 0] gp0_maxi_arcache     ;
wire [  4-1: 0] gp0_maxi_arlen       ;
wire [  4-1: 0] gp0_maxi_arqos       ;
wire [  4-1: 0] gp0_maxi_awcache     ;
wire [  4-1: 0] gp0_maxi_awlen       ;
wire [  4-1: 0] gp0_maxi_awqos       ;
wire [  4-1: 0] gp0_maxi_wstrb       ;
wire            gp0_maxi_aclk        ;
wire            gp0_maxi_arready     ;
wire            gp0_maxi_awready     ;
wire            gp0_maxi_bvalid      ;
wire            gp0_maxi_rlast       ;
wire            gp0_maxi_rvalid      ;
wire            gp0_maxi_wready      ;
wire [ 12-1: 0] gp0_maxi_bid         ;
wire [ 12-1: 0] gp0_maxi_rid         ;
wire [  2-1: 0] gp0_maxi_bresp       ;
wire [  2-1: 0] gp0_maxi_rresp       ;
wire [ 32-1: 0] gp0_maxi_rdata       ;
wire            gp0_maxi_arstn       ;

axi_slave #(
  .AXI_DW     (  32     ), // data width (8,16,...,1024)
  .AXI_AW     (  32     ), // address width
  .AXI_IW     (  12     )  // ID width
)
i_gp0_slave
(
 // global signals
  .axi_clk_i        (  gp0_maxi_aclk           ),  // global clock
  .axi_rstn_i       (  gp0_maxi_arstn          ),  // global reset

 // axi write address channel
  .axi_awid_i       (  gp0_maxi_awid           ),  // write address ID
  .axi_awaddr_i     (  gp0_maxi_awaddr         ),  // write address
  .axi_awlen_i      (  gp0_maxi_awlen          ),  // write burst length
  .axi_awsize_i     (  gp0_maxi_awsize         ),  // write burst size
  .axi_awburst_i    (  gp0_maxi_awburst        ),  // write burst type
  .axi_awlock_i     (  gp0_maxi_awlock         ),  // write lock type
  .axi_awcache_i    (  gp0_maxi_awcache        ),  // write cache type
  .axi_awprot_i     (  gp0_maxi_awprot         ),  // write protection type
  .axi_awvalid_i    (  gp0_maxi_awvalid        ),  // write address valid
  .axi_awready_o    (  gp0_maxi_awready        ),  // write ready

 // axi write data channel
  .axi_wid_i        (  gp0_maxi_wid            ),  // write data ID
  .axi_wdata_i      (  gp0_maxi_wdata          ),  // write data
  .axi_wstrb_i      (  gp0_maxi_wstrb          ),  // write strobes
  .axi_wlast_i      (  gp0_maxi_wlast          ),  // write last
  .axi_wvalid_i     (  gp0_maxi_wvalid         ),  // write valid
  .axi_wready_o     (  gp0_maxi_wready         ),  // write ready

 // axi write response channel
  .axi_bid_o        (  gp0_maxi_bid            ),  // write response ID
  .axi_bresp_o      (  gp0_maxi_bresp          ),  // write response
  .axi_bvalid_o     (  gp0_maxi_bvalid         ),  // write response valid
  .axi_bready_i     (  gp0_maxi_bready         ),  // write response ready

 // axi read address channel
  .axi_arid_i       (  gp0_maxi_arid           ),  // read address ID
  .axi_araddr_i     (  gp0_maxi_araddr         ),  // read address
  .axi_arlen_i      (  gp0_maxi_arlen          ),  // read burst length
  .axi_arsize_i     (  gp0_maxi_arsize         ),  // read burst size
  .axi_arburst_i    (  gp0_maxi_arburst        ),  // read burst type
  .axi_arlock_i     (  gp0_maxi_arlock         ),  // read lock type
  .axi_arcache_i    (  gp0_maxi_arcache        ),  // read cache type
  .axi_arprot_i     (  gp0_maxi_arprot         ),  // read protection type
  .axi_arvalid_i    (  gp0_maxi_arvalid        ),  // read address valid
  .axi_arready_o    (  gp0_maxi_arready        ),  // read address ready
    
 // axi read data channel
  .axi_rid_o        (  gp0_maxi_rid            ),  // read response ID
  .axi_rdata_o      (  gp0_maxi_rdata          ),  // read data
  .axi_rresp_o      (  gp0_maxi_rresp          ),  // read response
  .axi_rlast_o      (  gp0_maxi_rlast          ),  // read last
  .axi_rvalid_o     (  gp0_maxi_rvalid         ),  // read response valid
  .axi_rready_i     (  gp0_maxi_rready         ),  // read response ready

 // system read/write channel
  .sys_addr_o       (  sys_addr_o              ),  // system read/write address
  .sys_wdata_o      (  sys_wdata_o             ),  // system write data
  .sys_sel_o        (  sys_sel_o               ),  // system write byte select
  .sys_wen_o        (  sys_wen_o               ),  // system write enable
  .sys_ren_o        (  sys_ren_o               ),  // system read enable
  .sys_rdata_i      (  sys_rdata_i             ),  // system read data
  .sys_err_i        (  sys_err_i               ),  // system error indicator
  .sys_ack_i        (  sys_ack_i               )   // system acknowledge signal
);

assign sys_clk_o  = gp0_maxi_aclk   ;
assign sys_rstn_o = gp0_maxi_arstn  ;





//------------------------------------------------------------------------------
// PS STUB

assign fclk_rstn_o    = fclk_rstn      ;
assign gp0_maxi_aclk  = fclk_clk_o[0]  ;
assign hp0_saxi_aclk  = fclk_clk_o[0]  ;

BUFG i_fclk0_buf  (.O(fclk_clk_o[0]), .I(fclk_clk[0]));
BUFG i_fclk1_buf  (.O(fclk_clk_o[1]), .I(fclk_clk[1]));
BUFG i_fclk2_buf  (.O(fclk_clk_o[2]), .I(fclk_clk[2]));
BUFG i_fclk3_buf  (.O(fclk_clk_o[3]), .I(fclk_clk[3]));

system_wrapper system_i
(
// MIO
  .FIXED_IO_mio       (  FIXED_IO_mio                ),
  .FIXED_IO_ps_clk    (  FIXED_IO_ps_clk             ),
  .FIXED_IO_ps_porb   (  FIXED_IO_ps_porb            ),
  .FIXED_IO_ps_srstb  (  FIXED_IO_ps_srstb           ),
  .FIXED_IO_ddr_vrn   (  FIXED_IO_ddr_vrn            ),
  .FIXED_IO_ddr_vrp   (  FIXED_IO_ddr_vrp            ),
  .DDR_addr           (  DDR_addr                    ),
  .DDR_ba             (  DDR_ba                      ),
  .DDR_cas_n          (  DDR_cas_n                   ),
  .DDR_ck_n           (  DDR_ck_n                    ),
  .DDR_ck_p           (  DDR_ck_p                    ),
  .DDR_cke            (  DDR_cke                     ),
  .DDR_cs_n           (  DDR_cs_n                    ),
  .DDR_dm             (  DDR_dm                      ),
  .DDR_dq             (  DDR_dq                      ),
  .DDR_dqs_n          (  DDR_dqs_n                   ),
  .DDR_dqs_p          (  DDR_dqs_p                   ),
  .DDR_odt            (  DDR_odt                     ),
  .DDR_ras_n          (  DDR_ras_n                   ),
  .DDR_reset_n        (  DDR_reset_n                 ),
  .DDR_we_n           (  DDR_we_n                    ),

// FCLKs
  .FCLK_CLK0          (  fclk_clk[0]                 ),  // out
  .FCLK_CLK1          (  fclk_clk[1]                 ),  // out
  .FCLK_CLK2          (  fclk_clk[2]                 ),  // out
  .FCLK_CLK3          (  fclk_clk[3]                 ),  // out
  .FCLK_RESET0_N      (  fclk_rstn[0]                ),  // out
  .FCLK_RESET1_N      (  fclk_rstn[1]                ),  // out
  .FCLK_RESET2_N      (  fclk_rstn[2]                ),  // out
  .FCLK_RESET3_N      (  fclk_rstn[3]                ),  // out

// GP0
  .M_AXI_GP0_arvalid  (  gp0_maxi_arvalid            ),  // out
  .M_AXI_GP0_awvalid  (  gp0_maxi_awvalid            ),  // out
  .M_AXI_GP0_bready   (  gp0_maxi_bready             ),  // out
  .M_AXI_GP0_rready   (  gp0_maxi_rready             ),  // out
  .M_AXI_GP0_wlast    (  gp0_maxi_wlast              ),  // out
  .M_AXI_GP0_wvalid   (  gp0_maxi_wvalid             ),  // out
  .M_AXI_GP0_arid     (  gp0_maxi_arid               ),  // out 12
  .M_AXI_GP0_awid     (  gp0_maxi_awid               ),  // out 12
  .M_AXI_GP0_wid      (  gp0_maxi_wid                ),  // out 12
  .M_AXI_GP0_arburst  (  gp0_maxi_arburst            ),  // out 2
  .M_AXI_GP0_arlock   (  gp0_maxi_arlock             ),  // out 2
  .M_AXI_GP0_arsize   (  gp0_maxi_arsize             ),  // out 3
  .M_AXI_GP0_awburst  (  gp0_maxi_awburst            ),  // out 2
  .M_AXI_GP0_awlock   (  gp0_maxi_awlock             ),  // out 2
  .M_AXI_GP0_awsize   (  gp0_maxi_awsize             ),  // out 3
  .M_AXI_GP0_arprot   (  gp0_maxi_arprot             ),  // out 3
  .M_AXI_GP0_awprot   (  gp0_maxi_awprot             ),  // out 3
  .M_AXI_GP0_araddr   (  gp0_maxi_araddr             ),  // out 32
  .M_AXI_GP0_awaddr   (  gp0_maxi_awaddr             ),  // out 32
  .M_AXI_GP0_wdata    (  gp0_maxi_wdata              ),  // out 32
  .M_AXI_GP0_arcache  (  gp0_maxi_arcache            ),  // out 4
  .M_AXI_GP0_arlen    (  gp0_maxi_arlen              ),  // out 4
  .M_AXI_GP0_arqos    (  gp0_maxi_arqos              ),  // out 4
  .M_AXI_GP0_awcache  (  gp0_maxi_awcache            ),  // out 4
  .M_AXI_GP0_awlen    (  gp0_maxi_awlen              ),  // out 4
  .M_AXI_GP0_awqos    (  gp0_maxi_awqos              ),  // out 4
  .M_AXI_GP0_wstrb    (  gp0_maxi_wstrb              ),  // out 4
  .M_AXI_GP0_arready  (  gp0_maxi_arready            ),  // in
  .M_AXI_GP0_awready  (  gp0_maxi_awready            ),  // in
  .M_AXI_GP0_bvalid   (  gp0_maxi_bvalid             ),  // in
  .M_AXI_GP0_rlast    (  gp0_maxi_rlast              ),  // in
  .M_AXI_GP0_rvalid   (  gp0_maxi_rvalid             ),  // in
  .M_AXI_GP0_wready   (  gp0_maxi_wready             ),  // in
  .M_AXI_GP0_bid      (  gp0_maxi_bid                ),  // in 12
  .M_AXI_GP0_rid      (  gp0_maxi_rid                ),  // in 12
  .M_AXI_GP0_bresp    (  gp0_maxi_bresp              ),  // in 2
  .M_AXI_GP0_rresp    (  gp0_maxi_rresp              ),  // in 2
  .M_AXI_GP0_rdata    (  gp0_maxi_rdata              ),  // in 32

 // HP0
  .S_AXI_HP0_arready  (  hp0_saxi_arready            ), // out
  .S_AXI_HP0_awready  (  hp0_saxi_awready            ), // out
  .S_AXI_HP0_bvalid   (  hp0_saxi_bvalid             ), // out
  .S_AXI_HP0_rlast    (  hp0_saxi_rlast              ), // out
  .S_AXI_HP0_rvalid   (  hp0_saxi_rvalid             ), // out
  .S_AXI_HP0_wready   (  hp0_saxi_wready             ), // out
  .S_AXI_HP0_bresp    (  hp0_saxi_bresp              ), // out 2
  .S_AXI_HP0_rresp    (  hp0_saxi_rresp              ), // out 2
  .S_AXI_HP0_bid      (  hp0_saxi_bid                ), // out 6
  .S_AXI_HP0_rid      (  hp0_saxi_rid                ), // out 6
  .S_AXI_HP0_rdata    (  hp0_saxi_rdata              ), // out 64
  .S_AXI_HP0_arvalid  (  hp0_saxi_arvalid            ), // in
  .S_AXI_HP0_awvalid  (  hp0_saxi_awvalid            ), // in
  .S_AXI_HP0_bready   (  hp0_saxi_bready             ), // in
  .S_AXI_HP0_rready   (  hp0_saxi_rready             ), // in
  .S_AXI_HP0_wlast    (  hp0_saxi_wlast              ), // in
  .S_AXI_HP0_wvalid   (  hp0_saxi_wvalid             ), // in
  .S_AXI_HP0_arburst  (  hp0_saxi_arburst            ), // in 2
  .S_AXI_HP0_arlock   (  hp0_saxi_arlock             ), // in 2
  .S_AXI_HP0_arsize   (  hp0_saxi_arsize             ), // in 3
  .S_AXI_HP0_awburst  (  hp0_saxi_awburst            ), // in 2
  .S_AXI_HP0_awlock   (  hp0_saxi_awlock             ), // in 2
  .S_AXI_HP0_awsize   (  hp0_saxi_awsize             ), // in 3
  .S_AXI_HP0_arprot   (  hp0_saxi_arprot             ), // in 3
  .S_AXI_HP0_awprot   (  hp0_saxi_awprot             ), // in 3
  .S_AXI_HP0_araddr   (  hp0_saxi_araddr             ), // in 32
  .S_AXI_HP0_awaddr   (  hp0_saxi_awaddr             ), // in 32
  .S_AXI_HP0_arcache  (  hp0_saxi_arcache            ), // in 4
  .S_AXI_HP0_arlen    (  hp0_saxi_arlen              ), // in 4
  .S_AXI_HP0_arqos    (  hp0_saxi_arqos              ), // in 4
  .S_AXI_HP0_awcache  (  hp0_saxi_awcache            ), // in 4
  .S_AXI_HP0_awlen    (  hp0_saxi_awlen              ), // in 4
  .S_AXI_HP0_awqos    (  hp0_saxi_awqos              ), // in 4
  .S_AXI_HP0_arid     (  hp0_saxi_arid               ), // in 6
  .S_AXI_HP0_awid     (  hp0_saxi_awid               ), // in 6
  .S_AXI_HP0_wid      (  hp0_saxi_wid                ), // in 6
  .S_AXI_HP0_wdata    (  hp0_saxi_wdata              ), // in 64
  .S_AXI_HP0_wstrb    (  hp0_saxi_wstrb              ), // in 8

 // SPI0
  .SPI0_SS_I          (  spi_ss_i                    ),  // in
  .SPI0_SS_O          (  spi_ss_o                    ),  // out
  .SPI0_SS1_O         (  spi_ss1_o                   ),  // out
  .SPI0_SS2_O         (  spi_ss2_o                   ),  // out
  .SPI0_SCLK_I        (  spi_sclk_i                  ),  // in
  .SPI0_SCLK_O        (  spi_sclk_o                  ),  // out
  .SPI0_MOSI_I        (  spi_mosi_i                  ),  // in
  .SPI0_MOSI_O        (  spi_mosi_o                  ),  // out
  .SPI0_MISO_I        (  spi_miso_i                  ),  // in
  .SPI0_MISO_O        (  spi_miso_o                  ),  // out
  .SPI0_SS_T          (                              ),  // out
  .SPI0_SCLK_T        (                              ),  // out
  .SPI0_MOSI_T        (                              ),  // out
  .SPI0_MISO_T        (                              ),  // out

    // PL-PS Interrupts
    .ARM_GIC_ID_61      (irq_f2p[ 0]        ),
    .ARM_GIC_ID_62      (irq_f2p[ 1]        ),
    .ARM_GIC_ID_63      (irq_f2p[ 2]        ),
    .ARM_GIC_ID_64      (irq_f2p[ 3]        ),
    .ARM_GIC_ID_65      (irq_f2p[ 4]        ),
    .ARM_GIC_ID_66      (irq_f2p[ 5]        ),
    .ARM_GIC_ID_67      (irq_f2p[ 6]        ),
    .ARM_GIC_ID_68      (irq_f2p[ 7]        ),
    .ARM_GIC_ID_84      (irq_f2p[ 8]        ),
    .ARM_GIC_ID_85      (irq_f2p[ 9]        ),
    .ARM_GIC_ID_86      (irq_f2p[10]        ),
    .ARM_GIC_ID_87      (irq_f2p[11]        ),
    .ARM_GIC_ID_88      (irq_f2p[12]        ),
    .ARM_GIC_ID_89      (irq_f2p[13]        ),
    .ARM_GIC_ID_90      (irq_f2p[14]        ),
    .ARM_GIC_ID_91      (irq_f2p[15]        )
);

assign gp0_maxi_arstn = fclk_rstn_o[0] ;
assign hp0_saxi_arstn = fclk_rstn_o[0] ;





endmodule
