/**
 * $Id: red_pitaya_top.v 1271 2014-02-25 12:32:34Z matej.oblak $
 *
 * @brief Red Pitaya TOP module. It connects external pins and PS part with 
 *        other application modules. 
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
 * Added infrastructure for ADC data transfer to DDR3 RAM through AXI HP bus
 */


/**
 * GENERAL DESCRIPTION:
 *
 * Top module connects PS part with rest of Red Pitaya applications.  
 *
 *
 *          AXI     /---------\
 *      +---------- | AXI2DDR | <-+
 *      |           \---------/   |
 *      |                         |
 *      v            /-------\    |   AXI <->
 *   PS DDR <------> |  PS   |    |   custom bus
 *   PS MIO <------> |   /   | <------------+
 *   PS CLK -------> |  ARM  |    |         |
 *                   \-------/    |         |
 *                                |         |
 *                                |         |
 *                            /-------\     |
 *                         -> | SCOPE | <---+
 *                         |  \-------/     |
 *                         |                |
 *                         |                |
 *            /--------\   |   /-----\      |
 *   ADC ---> |        | --+-> |     |      |
 *            | ANALOG |       | PID | <----+
 *   DAC <--- |        | <---- |     |      |
 *            \--------/   ^   \-----/      |
 *                         |                |
 *                         |                |
 *                         |  /-------\     |
 *                         -- |  ASG  | <---+ 
 *                            \-------/     |
 *                                          |
 *                                          |
 *             /--------\                   |
 *    RX ----> |        |                   |
 *   SATA      | DAISY  | <-----------------+
 *    TX <---- |        | 
 *             \--------/ 
 *               |    |
 *               |    |
 *               (FREE)
 *
 *
 *
 * Inside analog module, ADC data is translated from unsigned neg-slope into
 * two's complement. Similar is done on DAC data.
 *
 * Scope module stores data from ADC into RAM, arbitrary signal generator (ASG)
 * sends data from RAM to DAC. MIMO PID uses ADC ADC as input and DAC as its output.
 *
 * Daisy chain connects with other boards with fast serial link. Data which is
 * send and received is at the moment undefined. This is left for the user.
 * 
 */


module red_pitaya_top
(
   // PS connections
   inout  [54-1: 0] FIXED_IO_mio       ,
   inout            FIXED_IO_ps_clk    ,
   inout            FIXED_IO_ps_porb   ,
   inout            FIXED_IO_ps_srstb  ,
   inout            FIXED_IO_ddr_vrn   ,
   inout            FIXED_IO_ddr_vrp   ,
   inout  [15-1: 0] DDR_addr           ,
   inout  [ 3-1: 0] DDR_ba             ,
   inout            DDR_cas_n          ,
   inout            DDR_ck_n           ,
   inout            DDR_ck_p           ,
   inout            DDR_cke            ,
   inout            DDR_cs_n           ,
   inout  [ 4-1: 0] DDR_dm             ,
   inout  [32-1: 0] DDR_dq             ,
   inout  [ 4-1: 0] DDR_dqs_n          ,
   inout  [ 4-1: 0] DDR_dqs_p          ,
   inout            DDR_odt            ,
   inout            DDR_ras_n          ,
   inout            DDR_reset_n        ,
   inout            DDR_we_n           ,

   // Red Pitaya periphery
  
   // ADC
   input  [16-1: 2] adc_dat_a_i        ,  // ADC CH1
   input  [16-1: 2] adc_dat_b_i        ,  // ADC CH2
   input            adc_clk_p_i        ,  // ADC data clock
   input            adc_clk_n_i        ,  // ADC data clock
   output [ 2-1: 0] adc_clk_o          ,  // optional ADC clock source
   output           adc_cdcs_o         ,  // ADC clock duty cycle stabilizer
  
   // DAC
   output [14-1: 0] dac_dat_o          ,  // DAC combined data
   output           dac_wrt_o          ,  // DAC write
   output           dac_sel_o          ,  // DAC channel select
   output           dac_clk_o          ,  // DAC clock
   output           dac_rst_o          ,  // DAC reset
  
   // PWM DAC
   output [ 4-1: 0] dac_pwm_o          ,  // serial PWM DAC

   // XADC
   input  [ 5-1: 0] vinp_i             ,  // voltages p
   input  [ 5-1: 0] vinn_i             ,  // voltages n

   // Expansion connector
   inout  [ 8-1: 0] exp_p_io           ,
   inout  [ 8-1: 0] exp_n_io           ,


   // SATA connector
   output [ 2-1: 0] daisy_p_o          ,  // line 1 is clock capable
   output [ 2-1: 0] daisy_n_o          ,
   input  [ 2-1: 0] daisy_p_i          ,  // line 1 is clock capable
   input  [ 2-1: 0] daisy_n_i          ,

   // LED
   output [ 8-1: 0] led_o       

);

localparam SYSCONF_ID      = 32'hfff00002; // ID: 32'hcccvvvvv, c=rp-deviceclass, v=versionnr
localparam SYSCONF_REGIONS = 8; // number of regions supported by the sysbus
localparam FIRST_FREE      = 6; // index of first region not mapped to a functional block
localparam SYSR = SYSCONF_REGIONS;
genvar GV,CNT;





//---------------------------------------------------------------------------------
//
//  Connections to PS

wire  [  4-1: 0] fclk               ; //[0]-125MHz, [1]-250MHz, [2]-50MHz, [3]-200MHz
wire  [  4-1: 0] frstn              ;

wire             ps_sys_clk         ;
wire             ps_sys_rstn        ;
wire  [ 32-1: 0] ps_sys_addr        ;
wire  [ 32-1: 0] ps_sys_wdata       ;
wire  [  4-1: 0] ps_sys_sel         ;
wire             ps_sys_wen         ;
wire             ps_sys_ren         ;
wire  [ 32-1: 0] ps_sys_rdata       ;
wire             ps_sys_err         ;
wire             ps_sys_ack         ;

// Housekeeping GPIO
wire            gpio_irq0;      // GPIO pin change interrupt request 0

// ADC buffer
wire [   2-1:0] adcbuf_select;  // channel buffer select
wire [   4-1:0] adcbuf_ready;   // buffer ready [0]: ChA 0-1k, [1]: ChA 1k-2k, [2]: ChB 0-1k, [3]: ChB 1k-2k
wire [   9-1:0] adcbuf_raddr;   // buffer read address
wire [  64-1:0] adcbuf_rdata;   // buffer read data

// DDR Dump parameters and signals
wire [  32-1:0] ddrd_a_base;    // DDR Dump ChA buffer base address
wire [  32-1:0] ddrd_a_end;     // DDR Dump ChA buffer end address + 1
wire [  32-1:0] ddrd_a_curr;    // DDR Dump ChA current write address
wire [  32-1:0] ddrd_b_base;    // DDR Dump ChB buffer base address
wire [  32-1:0] ddrd_b_end;     // DDR Dump ChB buffer end address + 1
wire [  32-1:0] ddrd_b_curr;    // DDR Dump ChB current write address
wire [   2-1:0] ddrd_status;    // DDR Dump [0,1]: INT pending A/B
wire            ddrd_stat_rd;   // DDR Dump INT pending was read
wire [   6-1:0] ddrd_control;   // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B, [4,5]: INT enable A/B
wire            ddrd_irq0;      // DDR Dump interrupt request 0

// PL-PS Interrupt lines
wire [    15:0] irq_f2p;        // ARM GIC ID 91-84,68-61


//---------------------------------------------------------------------------------
//
//  system bus decoder & multiplexer
//  it breaks memory addresses into SYSR regions

wire                sys_clk    = ps_sys_clk      ;
wire                sys_rstn   = ps_sys_rstn     ;
wire  [    32-1: 0] sys_addr   = ps_sys_addr     ;
wire  [    32-1: 0] sys_wdata  = ps_sys_wdata    ;
wire  [     4-1: 0] sys_sel    = ps_sys_sel      ;
wire  [     SYSR-1: 0] sys_wen    ;
wire  [     SYSR-1: 0] sys_ren    ;
wire  [(SYSR*32)-1: 0] sys_rdata  ;
wire  [ (SYSR*1)-1: 0] sys_err    ;
wire  [ (SYSR*1)-1: 0] sys_ack    ;
reg   [     SYSR-1: 0] sys_cs     ;

reg  [  32-1:0] sysconf_rdata;
reg             sysconf_err;
reg             sysconf_ack;
reg             sysconf_cs;

//---------------------------------------------------------------------------------
// control signals sys_cs[], sys_wen[], sys_ren[], sysconf_cs
//---------------------------------------------------------------------------------
always @(sys_addr) begin
    sys_cs <= {SYSR{1'b0}};
    if (sys_addr[29:20] < SYSR) begin
        sys_cs[sys_addr[29:20]] <= 1'b1;
    end
    sysconf_cs <= 1'b0;
    if (sys_addr[29:20] == 10'h3ff) begin
        sysconf_cs <= 1'b1;
    end
end

assign sys_wen = sys_cs & {SYSR{ps_sys_wen}}  ;
assign sys_ren = sys_cs & {SYSR{ps_sys_ren}}  ;

//---------------------------------------------------------------------------------
// multiplex outputs of sysregion blocks onto PS sysbus by cs + sysconf_cs
//---------------------------------------------------------------------------------
assign ps_sys_err = |(sys_cs & sys_err) | sysconf_cs & sysconf_err;
assign ps_sys_ack = |(sys_cs & sys_ack) | sysconf_cs & sysconf_ack;

wire [SYSR*32-1:0] sys_rdata_s;
generate for (GV=0; GV<32; GV=GV+1) begin
    for (CNT=0; CNT<SYSR; CNT=CNT+1) begin
        assign sys_rdata_s[GV*SYSR+CNT] = sys_rdata[CNT*32+GV]; // reshuffle to align with sys_cs per bitline
    end
    assign ps_sys_rdata[GV] = |(sys_cs & sys_rdata_s[GV*SYSR+:SYSR]) | sysconf_cs & sysconf_rdata[GV];
end endgenerate

//---------------------------------------------------------------------------------
// generate sane signals for unused regions
//---------------------------------------------------------------------------------
generate for (GV=FIRST_FREE; GV<SYSR; GV=GV+1) begin
assign sys_rdata[GV*32+:32] = 32'h0;
assign sys_err[GV] = 1'b0;
assign sys_ack[GV] = 1'b1;
end endgenerate

//---------------------------------------------------------------------------------
// PL-PS interrupt assignments
//---------------------------------------------------------------------------------
// 1. assign interrupts from your child modules here 
// 2. create an interrupt configuration value for your sysbus region number below

assign irq_f2p[ 0] = 0;             // IRQ0, GIC ID 61
assign irq_f2p[ 1] = 0;             // IRQ1, GIC ID 62
assign irq_f2p[ 2] = 0;             // IRQ2, GIC ID 63
assign irq_f2p[ 3] = 0;             // IRQ3, GIC ID 64
assign irq_f2p[ 4] = ddrd_irq0;     // DDR Dump interrupt 0 on behalf of scope on IRQ4, GIC ID 65
assign irq_f2p[ 5] = 0;             // IRQ5, GIC ID 66
assign irq_f2p[ 6] = 0;             // IRQ6, GIC ID 67
assign irq_f2p[ 7] = 0;             // IRQ7, GIC ID 68
assign irq_f2p[ 8] = 0;             // IRQ8, GIC ID 84
assign irq_f2p[ 9] = 0;             // IRQ9, GIC ID 85
assign irq_f2p[10] = gpio_irq0;     // GPIO change interrupt 0 on behalf of hk on IRQ10, GIC ID 86
assign irq_f2p[11] = 0;             // IRQ11, GIC ID 87
assign irq_f2p[12] = 0;             // IRQ12, GIC ID 88
assign irq_f2p[13] = 0;             // IRQ13, GIC ID 89
assign irq_f2p[14] = 0;             // IRQ14, GIC ID 90
assign irq_f2p[15] = 0;             // IRQ15, GIC ID 91

// static configuration values of the sysbus that will be queried by the rpad driver
always @(*) begin
    sysconf_ack <= 1'b1;
    sysconf_err <= 1'b0;

    case (sys_addr[19:0])
    20'hf0000:  sysconf_rdata <= SYSCONF_ID;
    20'hf0004:  sysconf_rdata <= SYSCONF_REGIONS;

    // sysbus region interrupt config: up to 4 interrupt lines per region, 0xf0100: region 0, 0xf0104: region 1, ...
    //                               31              15             0 | w,x,y,z: enable interrupt line 0,1,2,3
    //                               000000000000wxyzaaaabbbbccccdddd | a,b,c,d: interrupt number (0-15) for line 0,1,2,3
    20'hf0100:  sysconf_rdata <= 32'b00000000000010001010000000000000; // hk: IRQ10 on line 0
    20'hf0104:  sysconf_rdata <= 32'b00000000000010000100000000000000; // scope: IRQ4 on line 0
    //20'hf0108:  sysconf_rdata <= ; ...

    default:    sysconf_rdata <= 32'h0;
    endcase
end


red_pitaya_ps i_ps
(
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

  .fclk_clk_o      (  fclk               ),
  .fclk_rstn_o     (  frstn              ),

   // system read/write channel
  .sys_clk_o       (  ps_sys_clk         ),  // system clock
  .sys_rstn_o      (  ps_sys_rstn        ),  // system reset - active low
  .sys_addr_o      (  ps_sys_addr        ),  // system read/write address
  .sys_wdata_o     (  ps_sys_wdata       ),  // system write data
  .sys_sel_o       (  ps_sys_sel         ),  // system write byte select
  .sys_wen_o       (  ps_sys_wen         ),  // system write enable
  .sys_ren_o       (  ps_sys_ren         ),  // system read enable
  .sys_rdata_i     (  ps_sys_rdata       ),  // system read data
  .sys_err_i       (  ps_sys_err         ),  // system error indicator
  .sys_ack_i       (  ps_sys_ack         ),  // system acknowledge signal

   // SPI master
  .spi_ss_o        (                     ),  // select slave 0
  .spi_ss1_o       (                     ),  // select slave 1
  .spi_ss2_o       (                     ),  // select slave 2
  .spi_sclk_o      (                     ),  // serial clock
  .spi_mosi_o      (                     ),  // master out slave in
  .spi_miso_i      (  1'b0               ),  // master in slave out

   // SPI slave
  .spi_ss_i        (  1'b1               ),  // slave selected
  .spi_sclk_i      (  1'b0               ),  // serial clock
  .spi_mosi_i      (  1'b0               ),  // master out slave in
  .spi_miso_o      (                     ),  // master in slave out

    // ADC data buffer
    .adcbuf_select_o    (adcbuf_select          ),  // buffer select ChA [0] / ChB [1]
    .adcbuf_ready_i     (adcbuf_ready           ),  // buffer ready [0]: ChA 0k-8k, [1]: ChA 8k-16k, [2]: ChB 0k-8k, [3]: ChB 8k-16k
    .adcbuf_raddr_o     (adcbuf_raddr           ),  //
    .adcbuf_rdata_i     (adcbuf_rdata           ),  //

    // DDR Dump parameter
    .ddrd_a_base_i  (ddrd_a_base                ),  // DDR Dump ChA buffer base address
    .ddrd_a_end_i   (ddrd_a_end                 ),  // DDR Dump ChA buffer end address + 1
    .ddrd_a_curr_o  (ddrd_a_curr                ),  // DDR Dump ChA current write address
    .ddrd_b_base_i  (ddrd_b_base                ),  // DDR Dump ChB buffer base address
    .ddrd_b_end_i   (ddrd_b_end                 ),  // DDR Dump ChB buffer end address + 1
    .ddrd_b_curr_o  (ddrd_b_curr                ),  // DDR Dump ChB current write address
    .ddrd_status_o  (ddrd_status                ),  // DDR Dump [0,1]: INT pending A/B
    .ddrd_stat_rd_i (ddrd_stat_rd               ),  // DDR Dump INT pending was read
    .ddrd_control_i (ddrd_control               ),  // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B, [4,5]: INT enable A/B
    .ddrd_irq0_o    (ddrd_irq0                  ),  // DDR Dump interrupt request 0

    // PL-PS Interrupt lines
    .irq_f2p        (irq_f2p                    )   // ARM GIC ID 91-84,68-61
);





//---------------------------------------------------------------------------------
//
//  Analog peripherials 

// ADC clock duty cycle stabilizer is enabled
assign adc_cdcs_o = 1'b1 ;

// generating ADC clock is disabled
assign adc_clk_o = 2'b10;
//ODDR i_adc_clk_p ( .Q(adc_clk_o[0]), .D1(1'b1), .D2(1'b0), .C(fclk[0]), .CE(1'b1), .R(1'b0), .S(1'b0));
//ODDR i_adc_clk_n ( .Q(adc_clk_o[1]), .D1(1'b0), .D2(1'b1), .C(fclk[0]), .CE(1'b1), .R(1'b0), .S(1'b0));


wire             ser_clk     ;
wire             adc_clk     ;
reg              adc_rstn    ;
wire  [ 14-1: 0] adc_a       ;
wire  [ 14-1: 0] adc_b       ;
reg   [ 14-1: 0] dac_a       ;
reg   [ 14-1: 0] dac_b       ;
wire  [ 24-1: 0] dac_pwm_a   ;
wire  [ 24-1: 0] dac_pwm_b   ;
wire  [ 24-1: 0] dac_pwm_c   ;
wire  [ 24-1: 0] dac_pwm_d   ;

red_pitaya_analog i_analog
(
  // ADC IC
  .adc_dat_a_i        (  adc_dat_a_i      ),  // CH 1
  .adc_dat_b_i        (  adc_dat_b_i      ),  // CH 2
  .adc_clk_p_i        (  adc_clk_p_i      ),  // data clock
  .adc_clk_n_i        (  adc_clk_n_i      ),  // data clock
  
  // DAC IC
  .dac_dat_o          (  dac_dat_o        ),  // combined data
  .dac_wrt_o          (  dac_wrt_o        ),  // write enable
  .dac_sel_o          (  dac_sel_o        ),  // channel select
  .dac_clk_o          (  dac_clk_o        ),  // clock
  .dac_rst_o          (  dac_rst_o        ),  // reset
  
  // PWM DAC
  .dac_pwm_o          (  dac_pwm_o        ),  // serial PWM DAC
  
  
  // user interface
  .adc_dat_a_o        (  adc_a            ),  // ADC CH1
  .adc_dat_b_o        (  adc_b            ),  // ADC CH2
  .adc_clk_o          (  adc_clk          ),  // ADC received clock
  .adc_rst_i          (  adc_rstn         ),  // reset - active low
  .ser_clk_o          (  ser_clk          ),  // fast serial clock

  .dac_dat_a_i        (  dac_a            ),  // DAC CH1
  .dac_dat_b_i        (  dac_b            ),  // DAC CH2

  .dac_pwm_a_i        (  dac_pwm_a        ),  // slow DAC CH1
  .dac_pwm_b_i        (  dac_pwm_b        ),  // slow DAC CH2
  .dac_pwm_c_i        (  dac_pwm_c        ),  // slow DAC CH3
  .dac_pwm_d_i        (  dac_pwm_d        ),  // slow DAC CH4
  .dac_pwm_sync_o     (                   )   // slow DAC sync
);

always @(posedge adc_clk) begin
   adc_rstn <= frstn[0] ;
end





//---------------------------------------------------------------------------------
//
//  House Keeping

wire  [  8-1: 0] exp_p_in     ;
wire  [  8-1: 0] exp_p_out    ;
wire  [  8-1: 0] exp_p_dir    ;
wire  [  8-1: 0] exp_n_in     ;
wire  [  8-1: 0] exp_n_out    ;
wire  [  8-1: 0] exp_n_dir    ;

red_pitaya_hk i_hk
(
  .clk_i           (  adc_clk                    ),  // clock
  .rstn_i          (  adc_rstn                   ),  // reset - active low

  // LED
  .led_o           (  led_o                      ),  // LED output
   // Expansion connector
  .exp_p_dat_i     (  exp_p_in                   ),  // input data
  .exp_p_dat_o     (  exp_p_out                  ),  // output data
  .exp_p_dir_o     (  exp_p_dir                  ),  // 1-output enable
  .exp_n_dat_i     (  exp_n_in                   ),
  .exp_n_dat_o     (  exp_n_out                  ),
  .exp_n_dir_o     (  exp_n_dir                  ),
    .gpio_irq0_o    (gpio_irq0                  ),  // GPIO pin change interrupt request 0

   // System bus region 0
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[0]                 ),  // write enable
  .sys_ren_i       (  sys_ren[0]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 0*32+31: 0*32]  ),  // read data
  .sys_err_o       (  sys_err[0]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[0]                 )   // acknowledge signal
);


generate
for( GV = 0 ; GV < 8 ; GV = GV + 1)
begin : exp_iobuf
  IOBUF i_iobufp (.O(exp_p_in[GV]), .IO(exp_p_io[GV]), .I(exp_p_out[GV]), .T(!exp_p_dir[GV]) );
  IOBUF i_iobufn (.O(exp_n_in[GV]), .IO(exp_n_io[GV]), .I(exp_n_out[GV]), .T(!exp_n_dir[GV]) );
end
endgenerate





//---------------------------------------------------------------------------------
//
//  Oscilloscope application

wire trig_asg_out ;

red_pitaya_scope i_scope
(
  // ADC
  .adc_a_i         (  adc_a                      ),  // CH 1
  .adc_b_i         (  adc_b                      ),  // CH 2
  .adc_clk_i       (  adc_clk                    ),  // clock
  .adc_rstn_i      (  adc_rstn                   ),  // reset - active low
  .trig_ext_i      (  exp_p_in[0]                ),  // external trigger
  .trig_asg_i      (  trig_asg_out               ),  // ASG trigger

   // System bus region 1
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[1]                 ),  // write enable
  .sys_ren_i       (  sys_ren[1]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 1*32+31: 1*32]  ),  // read data
  .sys_err_o       (  sys_err[1]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[1]                 ),  // acknowledge signal

    // DDR Dump parameter
    .ddr_a_base_o       (ddrd_a_base        ),  // DDR Dump ChA buffer base address
    .ddr_a_end_o        (ddrd_a_end         ),  // DDR Dump ChA buffer end address + 1
    .ddr_a_curr_i       (ddrd_a_curr        ),  // DDR Dump ChA current write address
    .ddr_b_base_o       (ddrd_b_base        ),  // DDR Dump ChB buffer base address
    .ddr_b_end_o        (ddrd_b_end         ),  // DDR Dump ChB buffer end address + 1
    .ddr_b_curr_i       (ddrd_b_curr        ),  // DDR Dump ChB current write address
    .ddr_status_i       (ddrd_status        ),  // DDR Dump [0,1]: INT pending A/B
    .ddr_stat_rd_o      (ddrd_stat_rd       ),  // DDR Dump INT pending was read
    .ddr_control_o      (ddrd_control       ),  // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B, [4,5]: INT enable A/B

    // ADC data buffer
    .adcbuf_clk_i       (fclk[0]            ),  // clock
    .adcbuf_rstn_i      (frstn[0]           ),  // reset
    .adcbuf_select_i    (adcbuf_select      ),  // channel buffer select
    .adcbuf_ready_o     (adcbuf_ready       ),  // buffer ready
    .adcbuf_raddr_i     (adcbuf_raddr       ),  // buffer read address
    .adcbuf_rdata_o     (adcbuf_rdata       )   // buffer read data
);





//---------------------------------------------------------------------------------
//
//  DAC arbitrary signal generator

wire  [ 14-1: 0] asg_a       ;
wire  [ 14-1: 0] asg_b       ;

red_pitaya_asg i_asg
(
   // DAC
  .dac_a_o         (  asg_a                      ),  // CH 1
  .dac_b_o         (  asg_b                      ),  // CH 2
  .dac_clk_i       (  adc_clk                    ),  // clock
  .dac_rstn_i      (  adc_rstn                   ),  // reset - active low
  .trig_a_i        (  exp_p_in[0]                ),
  .trig_b_i        (  exp_p_in[0]                ),
  .trig_out_o      (  trig_asg_out               ),

  // System bus region 2
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[2]                 ),  // write enable
  .sys_ren_i       (  sys_ren[2]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 2*32+31: 2*32]  ),  // read data
  .sys_err_o       (  sys_err[2]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[2]                 )   // acknowledge signal
);





//---------------------------------------------------------------------------------
//
//  MIMO PID controller

wire  [ 14-1: 0] pid_a       ;
wire  [ 14-1: 0] pid_b       ;

red_pitaya_pid i_pid
(
   // signals
  .clk_i           (  adc_clk                    ),  // clock
  .rstn_i          (  adc_rstn                   ),  // reset - active low
  .dat_a_i         (  adc_a                      ),  // in 1
  .dat_b_i         (  adc_b                      ),  // in 2
  .dat_a_o         (  pid_a                      ),  // out 1
  .dat_b_o         (  pid_b                      ),  // out 2

  // System bus region 3
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[3]                 ),  // write enable
  .sys_ren_i       (  sys_ren[3]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 3*32+31: 3*32]  ),  // read data
  .sys_err_o       (  sys_err[3]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[3]                 )   // acknowledge signal
);





//---------------------------------------------------------------------------------
//
//  Sumation of ASG and PID signal
//  perform saturation before sending to DAC 

wire  [ 15-1: 0] dac_a_sum       ;
wire  [ 15-1: 0] dac_b_sum       ;

assign dac_a_sum = $signed(asg_a) + $signed(pid_a);
assign dac_b_sum = $signed(asg_b) + $signed(pid_b);

always @(*) begin
   if (dac_a_sum[15-1:15-2] == 2'b01) // pos. overflow
      dac_a <= 14'h1FFF ;
   else if (dac_a_sum[15-1:15-2] == 2'b10) // neg. overflow
      dac_a <= 14'h2000 ;
   else
      dac_a <= dac_a_sum[14-1:0] ;


   if (dac_b_sum[15-1:15-2] == 2'b01) // pos. overflow
      dac_b <= 14'h1FFF ;
   else if (dac_b_sum[15-1:15-2] == 2'b10) // neg. overflow
      dac_b <= 14'h2000 ;
   else
      dac_b <= dac_b_sum[14-1:0] ;
end





//---------------------------------------------------------------------------------
//
//  Analog mixed signals
//  XADC and slow PWM DAC control

red_pitaya_ams i_ams
(
   // power test
  .clk_i           (  adc_clk                    ),  // clock
  .rstn_i          (  adc_rstn                   ),  // reset - active low

  .vinp_i          (  vinp_i                     ),  // voltages p
  .vinn_i          (  vinn_i                     ),  // voltages n

  .dac_a_o         (  dac_pwm_a                  ),  // values used for
  .dac_b_o         (  dac_pwm_b                  ),  // conversion into PWM signal
  .dac_c_o         (  dac_pwm_c                  ),
  .dac_d_o         (  dac_pwm_d                  ),

   // System bus region 4
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[4]                 ),  // write enable
  .sys_ren_i       (  sys_ren[4]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 4*32+31: 4*32]  ),  // read data
  .sys_err_o       (  sys_err[4]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[4]                 )   // acknowledge signal
);





//---------------------------------------------------------------------------------
//
//  Daisy chain
//  simple communication module

wire daisy_rx_rdy ;
wire dly_clk = fclk[3]; // 200MHz clock from PS - used for IDELAY (optionaly)

red_pitaya_daisy i_daisy
(
   // SATA connector
  .daisy_p_o       (  daisy_p_o                  ),  // line 1 is clock capable
  .daisy_n_o       (  daisy_n_o                  ),
  .daisy_p_i       (  daisy_p_i                  ),  // line 1 is clock capable
  .daisy_n_i       (  daisy_n_i                  ),

   // Data
  .ser_clk_i       (  ser_clk                    ),  // high speed serial
  .dly_clk_i       (  dly_clk                    ),  // delay clock
   // TX
  .par_clk_i       (  adc_clk                    ),  // data paralel clock
  .par_rstn_i      (  adc_rstn                   ),  // reset - active low
  .par_rdy_o       (  daisy_rx_rdy               ),
  .par_dv_i        (  daisy_rx_rdy               ),
  .par_dat_i       (  16'h1234                   ),
   // RX
  .par_clk_o       (                             ),
  .par_rstn_o      (                             ),
  .par_dv_o        (                             ),
  .par_dat_o       (                             ),

  .debug_o         (/*led_o*/                    ),

   // System bus region 5
  .sys_clk_i       (  sys_clk                    ),  // clock
  .sys_rstn_i      (  sys_rstn                   ),  // reset - active low
  .sys_addr_i      (  sys_addr                   ),  // address
  .sys_wdata_i     (  sys_wdata                  ),  // write data
  .sys_sel_i       (  sys_sel                    ),  // write byte select
  .sys_wen_i       (  sys_wen[5]                 ),  // write enable
  .sys_ren_i       (  sys_ren[5]                 ),  // read enable
  .sys_rdata_o     (  sys_rdata[ 5*32+31: 5*32]  ),  // read data
  .sys_err_o       (  sys_err[5]                 ),  // error indicator
  .sys_ack_o       (  sys_ack[5]                 )   // acknowledge signal
);





endmodule
