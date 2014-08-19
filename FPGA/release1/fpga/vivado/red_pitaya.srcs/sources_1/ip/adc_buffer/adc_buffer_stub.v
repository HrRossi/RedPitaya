// Copyright 1986-2014 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2014.2 (win64) Build 928826 Thu Jun  5 18:17:50 MDT 2014
// Date        : Tue Aug 19 21:25:17 2014
// Host        : Zock0r running 64-bit Service Pack 1  (build 7601)
// Command     : write_verilog -force -mode synth_stub
//               C:/Users/Nils/Documents/Programmieren/RedPitaya/Sources/FPGA/release1/fpga/vivado/red_pitaya.srcs/sources_1/ip/adc_buffer/adc_buffer_stub.v
// Design      : adc_buffer
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_2,Vivado 2014.2" *)
module adc_buffer(clka, ena, wea, addra, dina, clkb, rstb, enb, addrb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,wea[0:0],addra[13:0],dina[15:0],clkb,rstb,enb,addrb[11:0],doutb[63:0]" */;
  input clka;
  input ena;
  input [0:0]wea;
  input [13:0]addra;
  input [15:0]dina;
  input clkb;
  input rstb;
  input enb;
  input [11:0]addrb;
  output [63:0]doutb;
endmodule
