/**
 * $Id: red_pitaya_asg.v 961 2014-01-21 11:40:39Z matej.oblak $
 *
 * @brief Red Pitaya arbitrary signal generator (ASG).
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
  * 2014-10-29 Nils Roos <doctor@smart.ms>
  * Replaced connection of BRAM to (slow) sys_bus with high performance AXI
  * connection to DDR controller. Added control registers for the DDR buffer
  * operation and location. 
  */


/**
 * GENERAL DESCRIPTION:
 *
 * Arbitrary signal generator takes data stored in buffer and sends them to DAC.
 *
 *
 *                /-----\         /--------\
 *   SW --------> | BUF | ------> | kx + o | ---> DAC CHA
 *                \-----/         \--------/
 *                   ^
 *                   |
 *                /-----\
 *   SW --------> |     |
 *                | FSM | ------> trigger notification
 *   trigger ---> |     |
 *                \-----/
 *                   |
 *                   v
 *                /-----\         /--------\
 *   SW --------> | BUF | ------> | kx + o | ---> DAC CHB
 *                \-----/         \--------/ 
 *
 *
 * Buffers are filed with SW. It also sets finite state machine which take control
 * over read pointer. All registers regarding reading from buffer has additional 
 * 16 bits used as decimal points. In this way we can make better ratio betwen 
 * clock cycle and frequency of output signal. 
 *
 * Finite state machine can be set for one time sequence or continously wrapping.
 * Starting trigger can come from outside, notification trigger used to synchronize
 * with other applications (scope) is also available. Both channels are independant.
 *
 * Output data is scaled with linear transmormation.
 * 
 */



module red_pitaya_asg
(
   // DAC
   output     [ 14-1: 0] dac_a_o         ,  //!< DAC data CHA
   output     [ 14-1: 0] dac_b_o         ,  //!< DAC data CHB
   input                 dac_clk_i       ,  //!< DAC clock
   input                 dac_rstn_i      ,  //!< DAC reset - active low
   input                 trig_a_i        ,  //!< starting trigger CHA
   input                 trig_b_i        ,  //!< starting trigger CHB
   output                trig_out_o      ,  //!< notification trigger

   // System bus
   input                 sys_clk_i       ,  //!< bus clock
   input                 sys_rstn_i      ,  //!< bus reset - active low
   input      [ 32-1: 0] sys_addr_i      ,  //!< bus address
   input      [ 32-1: 0] sys_wdata_i     ,  //!< bus write data
   input      [  4-1: 0] sys_sel_i       ,  //!< bus write byte select
   input                 sys_wen_i       ,  //!< bus write enable
   input                 sys_ren_i       ,  //!< bus read enable
   output     [ 32-1: 0] sys_rdata_o     ,  //!< bus read data
   output                sys_err_o       ,  //!< bus error indicator
   output                sys_ack_o       ,  //!< bus acknowledge signal

    // DDR Slurp parameter export
    output  [   32-1:0] ddr_a_base_o    ,   // DDR Slurp ChA buffer base address
    output  [   32-1:0] ddr_a_end_o     ,   // DDR Slurp ChA buffer end address + 1
    output  [   32-1:0] ddr_b_base_o    ,   // DDR Slurp ChB buffer base address
    output  [   32-1:0] ddr_b_end_o     ,   // DDR Slurp ChB buffer end address + 1
    output  [    4-1:0] ddr_control_o   ,   // DDR Slurp control

    // DAC data buffer
    input               dacbuf_clk_i    ,   // clock
    input               dacbuf_rstn_i   ,   // reset
    input   [      1:0] dacbuf_select_i ,   // channel buffer select
    output  [    4-1:0] dacbuf_ready_o  ,   // buffer ready [0]: ChA 0k-8k, [1]: ChA 8k-16k, [2]: ChB 0k-8k, [3]: ChB 8k-16k
    input   [   12-1:0] dacbuf_waddr_i  ,   // buffer read address
    input   [   64-1:0] dacbuf_wdata_i  ,   // buffer read data
    input               dacbuf_valid_i      // buffer data valid
);

/* ID values to be read by the device driver, mapped at 40200ff0 - 40200fff */
localparam SYS_ID = 32'h00300001; // ID: 32'hcccvvvvv, c=rp-deviceclass, v=versionnr
localparam SYS_1 = 32'h00000000;
localparam SYS_2 = 32'h00000000;
localparam SYS_3 = 32'h00000000;


wire [ 32-1: 0] addr         ;
wire [ 32-1: 0] wdata        ;
wire            wen          ;
wire            ren          ;
reg  [ 32-1: 0] rdata        ;
reg             err          ;
reg             ack          ;


//---------------------------------------------------------------------------------
//
// generating signal from DAC table 

localparam RSZ = 14 ;  // RAM size 2^RSZ

reg   [RSZ+15: 0] set_a_size       ;
reg   [RSZ+15: 0] set_a_step       ;
reg   [RSZ+15: 0] set_a_ofs        ;
reg               set_a_rst        ;
reg               set_a_once       ;
reg               set_a_wrap       ;
reg   [  14-1: 0] set_a_amp        ;
reg   [  14-1: 0] set_a_dc         ;
reg               set_a_zero       ;
reg               trig_a_sw        ;
reg   [   3-1: 0] trig_a_src       ;
wire              trig_a_done      ;


reg   [RSZ+15: 0] set_b_size       ;
reg   [RSZ+15: 0] set_b_step       ;
reg   [RSZ+15: 0] set_b_ofs        ;
reg               set_b_rst        ;
reg               set_b_once       ;
reg               set_b_wrap       ;
reg   [  14-1: 0] set_b_amp        ;
reg   [  14-1: 0] set_b_dc         ;
reg               set_b_zero       ;
reg               trig_b_sw        ;
reg   [   3-1: 0] trig_b_src       ;
wire              trig_b_done      ;


red_pitaya_asg_ch  #(.RSZ ( RSZ ))  i_cha
(
   // DAC
  .dac_o           (  dac_a_o          ),  // dac data output
  .dac_clk_i       (  dac_clk_i        ),  // dac clock
  .dac_rstn_i      (  dac_rstn_i       ),  // dac reset - active low

   // trigger
  .trig_sw_i       (  trig_a_sw        ),  // software trigger
  .trig_ext_i      (  trig_a_i         ),  // external trigger
  .trig_src_i      (  trig_a_src       ),  // trigger source selector
  .trig_done_o     (  trig_a_done      ),  // trigger event

   // configuration
  .set_size_i      (  set_a_size       ),  // set table data size
  .set_step_i      (  set_a_step       ),  // set pointer step
  .set_ofs_i       (  set_a_ofs        ),  // set reset offset
  .set_rst_i       (  set_a_rst        ),  // set FMS to reset
  .set_once_i      (  set_a_once       ),  // set only once
  .set_wrap_i      (  set_a_wrap       ),  // set wrap pointer
  .set_amp_i       (  set_a_amp        ),  // set amplitude scale
  .set_dc_i        (  set_a_dc         ),  // set output offset
  .set_zero_i      (  set_a_zero       ),  // set output to zero

    // DAC data buffer
    .dacbuf_clk_i       (dacbuf_clk_i           ),  // clock
    .dacbuf_rstn_i      (dacbuf_rstn_i          ),  // reset
    .dacbuf_select_i    (dacbuf_select_i[0]     ),  // channel buffer select
    .dacbuf_ready_o     (dacbuf_ready_o[1:0]    ),  // buffer ready [0]: ChA 0k-8k, [1]: ChA 8k-16k, [2]: ChB 0k-8k, [3]: ChB 8k-16k
    .dacbuf_waddr_i     (dacbuf_waddr_i         ),  // buffer read address
    .dacbuf_wdata_i     (dacbuf_wdata_i         ),  // buffer read data
    .dacbuf_valid_i     (dacbuf_valid_i         )   // buffer data valid
);


red_pitaya_asg_ch  #(.RSZ ( RSZ ))  i_chb
(
   // DAC
  .dac_o           (  dac_b_o          ),  // dac data output
  .dac_clk_i       (  dac_clk_i        ),  // dac clock
  .dac_rstn_i      (  dac_rstn_i       ),  // dac reset - active low

   // trigger
  .trig_sw_i       (  trig_b_sw        ),  // software trigger
  .trig_ext_i      (  trig_b_i         ),  // external trigger
  .trig_src_i      (  trig_b_src       ),  // trigger source selector
  .trig_done_o     (  trig_b_done      ),  // trigger event

   // configuration
  .set_size_i      (  set_b_size       ),  // set table data size
  .set_step_i      (  set_b_step       ),  // set pointer step
  .set_ofs_i       (  set_b_ofs        ),  // set reset offset
  .set_rst_i       (  set_b_rst        ),  // set FMS to reset
  .set_once_i      (  set_b_once       ),  // set only once
  .set_wrap_i      (  set_b_wrap       ),  // set wrap pointer
  .set_amp_i       (  set_b_amp        ),  // set amplitude scale
  .set_dc_i        (  set_b_dc         ),  // set output offset
  .set_zero_i      (  set_b_zero       ),  // set output to zero

    // DAC data buffer
    .dacbuf_clk_i       (dacbuf_clk_i           ),  // clock
    .dacbuf_rstn_i      (dacbuf_rstn_i          ),  // reset
    .dacbuf_select_i    (dacbuf_select_i[1]     ),  // channel buffer select
    .dacbuf_ready_o     (dacbuf_ready_o[3:2]    ),  // buffer ready [0]: ChA 0k-8k, [1]: ChA 8k-16k, [2]: ChB 0k-8k, [3]: ChB 8k-16k
    .dacbuf_waddr_i     (dacbuf_waddr_i         ),  // buffer read address
    .dacbuf_wdata_i     (dacbuf_wdata_i         ),  // buffer read data
    .dacbuf_valid_i     (dacbuf_valid_i         )   // buffer data valid
);

assign trig_out_o = trig_a_done ;

//---------------------------------------------------------------------------------
//
//  System bus connection

reg  [  32-1:0] ddr_a_base;     // DDR Slurp ChA buffer base address
reg  [  32-1:0] ddr_a_end;      // DDR Slurp ChA buffer end address + 1
reg  [  32-1:0] ddr_b_base;     // DDR Slurp ChB buffer base address
reg  [  32-1:0] ddr_b_end;      // DDR Slurp ChB buffer end address + 1
reg  [   4-1:0] ddr_control;    // DDR Slurp control

assign ddr_a_base_o  = ddr_a_base;
assign ddr_a_end_o   = ddr_a_end;
assign ddr_b_base_o  = ddr_b_base;
assign ddr_b_end_o   = ddr_b_end;
assign ddr_control_o = ddr_control;

always @(posedge dac_clk_i) begin
   if (dac_rstn_i == 1'b0) begin
      trig_a_sw  <=  1'b0    ;
      trig_a_src <=  3'h0    ;
      set_a_amp  <= 14'h2000 ;
      set_a_dc   <= 14'h0    ;
      set_a_zero <=  1'b0    ;
      set_a_rst  <=  1'b0    ;
      set_a_once <=  1'b0    ;
      set_a_wrap <=  1'b0    ;
      set_a_size <= {RSZ+16{1'b1}} ;
      set_a_ofs  <= {RSZ+16{1'b0}} ;
      set_a_step <={{RSZ+15{1'b0}},1'b0} ;
      trig_b_sw  <=  1'b0    ;
      trig_b_src <=  3'h0    ;
      set_b_amp  <= 14'h2000 ;
      set_b_dc   <= 14'h0    ;
      set_b_zero <=  1'b0    ;
      set_b_rst  <=  1'b0    ;
      set_b_once <=  1'b0    ;
      set_b_wrap <=  1'b0    ;
      set_b_size <= {RSZ+16{1'b1}} ;
      set_b_ofs  <= {RSZ+16{1'b0}} ;
      set_b_step <={{RSZ+15{1'b0}},1'b0} ;
        ddr_a_base  <= 32'h00000000;
        ddr_a_end   <= 32'h00000000;
        ddr_b_base  <= 32'h00000000;
        ddr_b_end   <= 32'h00000000;
        ddr_control <= 4'b0000;
   end
   else begin

      trig_a_sw  <= wen && (addr[19:0]==20'h0) && wdata[0]  ;
      if (wen && (addr[19:0]==20'h0))
         trig_a_src <= wdata[2:0] ;

      trig_b_sw  <= wen && (addr[19:0]==20'h0) && wdata[16]  ;
      if (wen && (addr[19:0]==20'h0))
         trig_b_src <= wdata[19:16] ;



      if (wen) begin
         if (addr[19:0]==20'h0)   {set_a_zero, set_a_rst, set_a_once, set_a_wrap} <= wdata[ 7: 4] ;
         if (addr[19:0]==20'h0)   {set_b_zero, set_b_rst, set_b_once, set_b_wrap} <= wdata[23:20] ;

         if (addr[19:0]==20'h4)   set_a_amp  <= wdata[  0+13: 0] ;
         if (addr[19:0]==20'h4)   set_a_dc   <= wdata[ 16+13:16] ;
         if (addr[19:0]==20'h8)   set_a_size <= wdata[RSZ+15: 0] ;
         if (addr[19:0]==20'hC)   set_a_ofs  <= wdata[RSZ+15: 0] ;
         if (addr[19:0]==20'h10)  set_a_step <= wdata[RSZ+15: 0] ;

         if (addr[19:0]==20'h24)  set_b_amp  <= wdata[  0+13: 0] ;
         if (addr[19:0]==20'h24)  set_b_dc   <= wdata[ 16+13:16] ;
         if (addr[19:0]==20'h28)  set_b_size <= wdata[RSZ+15: 0] ;
         if (addr[19:0]==20'h2C)  set_b_ofs  <= wdata[RSZ+15: 0] ;
         if (addr[19:0]==20'h30)  set_b_step <= wdata[RSZ+15: 0] ;

            if (addr[19:0] == 20'h100)  ddr_control <= wdata[4-1:0];
            if (addr[19:0] == 20'h104)  ddr_a_base  <= wdata;
            if (addr[19:0] == 20'h108)  ddr_a_end   <= wdata;
            if (addr[19:0] == 20'h10c)  ddr_b_base  <= wdata;
            if (addr[19:0] == 20'h110)  ddr_b_end   <= wdata;
      end
   end
end

wire [32-1: 0] r0_rd = {8'h0,set_b_zero,set_b_rst,set_b_once,set_b_wrap, 1'b0,trig_b_src,
                        8'h0,set_a_zero,set_a_rst,set_a_once,set_a_wrap, 1'b0,trig_a_src };


always @(*) begin
   err <= 1'b0 ;

   casez (addr[19:0])
     20'h00000 : begin ack <= 1'b1;          rdata <= r0_rd                              ; end

     20'h00004 : begin ack <= 1'b1;          rdata <= {2'h0, set_a_dc, 2'h0, set_a_amp}  ; end
     20'h00008 : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_a_size}     ; end
     20'h0000C : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_a_ofs}      ; end
     20'h00010 : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_a_step}     ; end

     20'h00024 : begin ack <= 1'b1;          rdata <= {2'h0, set_b_dc, 2'h0, set_b_amp}  ; end
     20'h00028 : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_b_size}     ; end
     20'h0002C : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_b_ofs}      ; end
     20'h00030 : begin ack <= 1'b1;          rdata <= {{32-RSZ-16{1'b0}},set_b_step}     ; end

    20'h00104:  begin   ack <= 1'b1; rdata <= ddr_a_base;   end
    20'h00108:  begin   ack <= 1'b1; rdata <= ddr_a_end;    end
    20'h0010c:  begin   ack <= 1'b1; rdata <= ddr_b_base;   end
    20'h00110:  begin   ack <= 1'b1; rdata <= ddr_b_end;    end

    20'h00ff0:  begin   ack <= 1'b1; rdata <= SYS_ID;       end
    20'h00ff4:  begin   ack <= 1'b1; rdata <= SYS_1;        end
    20'h00ff8:  begin   ack <= 1'b1; rdata <= SYS_2;        end
    20'h00ffc:  begin   ack <= 1'b1; rdata <= SYS_3;        end

       default : begin ack <= 1'b1;          rdata <=  32'h0                             ; end
   endcase
end




// bridge between DAC and sys clock
bus_clk_bridge i_bridge_asg
(
   .sys_clk_i     (  sys_clk_i      ),
   .sys_rstn_i    (  sys_rstn_i     ),
   .sys_addr_i    (  sys_addr_i     ),
   .sys_wdata_i   (  sys_wdata_i    ),
   .sys_sel_i     (  sys_sel_i      ),
   .sys_wen_i     (  sys_wen_i      ),
   .sys_ren_i     (  sys_ren_i      ),
   .sys_rdata_o   (  sys_rdata_o    ),
   .sys_err_o     (  sys_err_o      ),
   .sys_ack_o     (  sys_ack_o      ),

   .clk_i         (  dac_clk_i      ),
   .rstn_i        (  dac_rstn_i     ),
   .addr_o        (  addr           ),
   .wdata_o       (  wdata          ),
   .wen_o         (  wen            ),
   .ren_o         (  ren            ),
   .rdata_i       (  rdata          ),
   .err_i         (  err            ),
   .ack_i         (  ack            )
);







endmodule

