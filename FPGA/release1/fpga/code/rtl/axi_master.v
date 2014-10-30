//////////////////////////////////////////////////////////////////////////////////
// Engineer: Nils Roos <doctor@smart.ms>
// 
// Create Date: 16.07.2014 22:57:49
// Module Name: axi_dump2ddr_master
// Description: 
// AXI HP master that transfers data from two BRAM buffers A/B (not part of the
// module) to two DDR RAM based ringbuffers via the memory interconnect. Transfers
// are organized in half-buffer blocks and interleaved A1 B1 A2 B2. Transfers are
// queued as soon as each half-buffer signals readiness.
// The AXI master uses maximum sized bursts and can employ the full outstanding
// write capabilities of the memory interconnect. 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: designed for use with the RedPitaya hardware
// 
// Known issues:
// - the first four samples on each channel are corrupted when enabling the DDR
//   dump functionality; not likely to get fixed because this made it easier to
//   not loose samples during buffer wrap-arounds
// 
//////////////////////////////////////////////////////////////////////////////////


module axi_dump2ddr_master #(
    parameter   AXI_DW  =  64           , // data width (8,16,...,1024)
    parameter   AXI_AW  =  32           , // AXI address width
    parameter   AXI_IW  =   6           , // AXI ID width
    parameter   AXI_SW  = AXI_DW >> 3   , // AXI strobe width - 1 bit for every data byte
    parameter   DBF_AW  =   9           , // DDR Dump buffer address width
    parameter   SBF_AW  =  12           , // DDR Slurp buffer address width
    parameter   BUF_CH  =   2             // number of buffered channels
)(
    // AXI HP master interface
    output [AXI_AW-1:0] axi_araddr_o    ,
    output [       1:0] axi_arburst_o   ,
    output [       3:0] axi_arcache_o   ,
    output [AXI_IW-1:0] axi_arid_o      ,
    output [       3:0] axi_arlen_o     ,
    output [       1:0] axi_arlock_o    ,
    output [       2:0] axi_arprot_o    ,
    output [       3:0] axi_arqos_o     ,
    input               axi_arready_i   ,
    output [       2:0] axi_arsize_o    ,
    output              axi_arvalid_o   ,
    output [AXI_AW-1:0] axi_awaddr_o    ,
    output [       1:0] axi_awburst_o   ,
    output [       3:0] axi_awcache_o   ,
    output [AXI_IW-1:0] axi_awid_o      ,
    output [       3:0] axi_awlen_o     ,
    output [       1:0] axi_awlock_o    ,
    output [       2:0] axi_awprot_o    ,
    output [       3:0] axi_awqos_o     ,
    input               axi_awready_i   ,
    output [       2:0] axi_awsize_o    ,
    output              axi_awvalid_o   ,
    input  [AXI_IW-1:0] axi_bid_i       ,
    output              axi_bready_o    ,
    input  [       1:0] axi_bresp_i     ,
    input               axi_bvalid_i    ,
    input  [AXI_DW-1:0] axi_rdata_i     ,
    input  [AXI_IW-1:0] axi_rid_i       ,
    input               axi_rlast_i     ,
    output              axi_rready_o    ,
    input  [       1:0] axi_rresp_i     ,
    input               axi_rvalid_i    ,
    output [AXI_DW-1:0] axi_wdata_o     ,
    output [AXI_IW-1:0] axi_wid_o       ,
    output              axi_wlast_o     ,
    input               axi_wready_i    ,
    output [AXI_SW-1:0] axi_wstrb_o     ,
    output              axi_wvalid_o    ,

    // ADC/DAC clock & reset
    input                   buf_clk_i,
    input                   buf_rstn_i,

    // ADC connection
    output [    BUF_CH-1:0] dbuf_select_o,
    input  [  2*BUF_CH-1:0] dbuf_ready_i,   // [0]: ChA 0-1k, [1]: ChA 1k-2k, [2]: ChB 0-1k, [3]: ChB 1k-2k
    output [    DBF_AW-1:0] dbuf_raddr_o,
    input  [    AXI_DW-1:0] dbuf_rdata_i,

    // DDR Dump parameter export
    input       [   32-1:0] ddrd_a_base_i,  // DDR Dump ChA buffer base address
    input       [   32-1:0] ddrd_a_end_i,   // DDR Dump ChA buffer end address + 1
    output      [   32-1:0] ddrd_a_curr_o,  // DDR Dump ChA current write address
    input       [   32-1:0] ddrd_b_base_i,  // DDR Dump ChB buffer base address
    input       [   32-1:0] ddrd_b_end_i,   // DDR Dump ChB buffer end address + 1
    output      [   32-1:0] ddrd_b_curr_o,  // DDR Dump ChB current write address
    input       [    4-1:0] ddrd_control_i, // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B

    // DAC connection
    output [    BUF_CH-1:0] sbuf_select_o,  //
    input  [  2*BUF_CH-1:0] sbuf_ready_i,   // [0]: ChA 0k-8k, [1]: ChA 8k-16k, [2]: ChB 0k-8k, [3]: ChB 8k-16k
    output [    SBF_AW-1:0] sbuf_waddr_o,   //
    output [    AXI_DW-1:0] sbuf_wdata_o,   //
    output                  sbuf_valid_o,   //

    // DDR Slurp parameter export
    input       [   32-1:0] ddrs_a_base_i,  // DDR Slurp ChA buffer base address
    input       [   32-1:0] ddrs_a_end_i,   // DDR Slurp ChA buffer end address + 1
    input       [   32-1:0] ddrs_b_base_i,  // DDR Slurp ChB buffer base address
    input       [   32-1:0] ddrs_b_end_i,   // DDR Slurp ChB buffer end address + 1
    input       [    4-1:0] ddrs_control_i  // DDR Slurp control
);

localparam AXI_CW = 4;      // width of the ID expiry counters
localparam AXI_CI = 4'hf;   // initial countdown value for the ID expiry counters
genvar CNT;


// --------------------------------------------------------------------------------------------------
// set unused outputs to 0 - when we implement scatter gather capability, we'll be needing these anyway
assign  axi_araddr_o  = 32'd0;
assign  axi_arid_o    = 6'd0;
assign  axi_arvalid_o = 1'd0;
assign  axi_rready_o  = 1'd0;

assign  sbuf_valid_o  = 1'b1;


// --------------------------------------------------------------------------------------------------
// set fixed transfer settings
assign  axi_arsize_o  = 3'b011;         // 8 bytes
assign  axi_arlen_o   = 4'b1111;        // 16 transfers
assign  axi_arburst_o = 2'b01;          // INCR
assign  axi_arcache_o = 4'b0001;        // bufferable, not cacheable
assign  axi_arprot_o  = 3'b000;         // normal, secure, data
assign  axi_arqos_o   = 4'd0;           // priority 0
assign  axi_arlock_o  = 2'b00;          // normal access

assign  axi_awsize_o  = 3'b011;         // 8 bytes
assign  axi_awlen_o   = 4'b1111;        // 16 transfers
assign  axi_awburst_o = 2'b01;          // INCR
assign  axi_awcache_o = 4'b0001;        // bufferable, not cacheable
assign  axi_awprot_o  = 3'b000;         // normal, secure, data
assign  axi_awqos_o   = 4'd0;           // priority 0
assign  axi_awlock_o  = 2'b00;          // normal access
assign  axi_wstrb_o   = 8'b11111111;    // write all bytes


// --------------------------------------------------------------------------------------------------
//
//                   AXI DDR Slurp
//
// --------------------------------------------------------------------------------------------------
// process ready latches from asg
reg  [   4-1:0] sbuf_ready;     // asg buffer ready registers Al,Ah,Bl,Bh
wire [   4-1:0] sbuf_finished;  // signals end of buffer processing Al,Ah,Bl,Bh

always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        sbuf_ready <= 4'b0000;
    end else begin
        if (sbuf_ready_i[0]) begin
            sbuf_ready[0] <= ddrs_control_i[0];
        end else if (dbuf_finished[0]) begin
            sbuf_ready[0] <= 1'b0;
        end else begin
            sbuf_ready[0] <= sbuf_ready[0];
        end

        if (sbuf_ready_i[1]) begin
            sbuf_ready[1] <= ddrs_control_i[0];
        end else if (sbuf_finished[1]) begin
            sbuf_ready[1] <= 1'b0;
        end else begin
            sbuf_ready[1] <= sbuf_ready[1];
        end

        if (sbuf_ready_i[2]) begin
            sbuf_ready[2] <= ddrs_control_i[1];
        end else if (sbuf_finished[2]) begin
            sbuf_ready[2] <= 1'b0;
        end else begin
            sbuf_ready[2] <= sbuf_ready[2];
        end

        if (sbuf_ready_i[3]) begin
            sbuf_ready[3] <= ddrs_control_i[1];
        end else if (sbuf_finished[3]) begin
            sbuf_ready[3] <= 1'b0;
        end else begin
            sbuf_ready[3] <= sbuf_ready[3];
        end
    end
end


// --------------------------------------------------------------------------------------------------
// transfer AXI data to BRAM
reg  [       2-1:0] sbuf_sel;       // select signals for Cha / ChB
reg                 sbuf_sel_ab;    // stores the currently active channel
reg  [  SBF_AW-1:0] sbuf_wp;        // BRAM write pointer
reg  [      32-1:0] s_rp;           // DDR read pointer
reg  [      32-1:0] s_a_curr;       // DDR ChA current read address
reg  [      32-1:0] s_b_curr;       // DDR ChB current read address
reg  [8*AXI_CW-1:0] s_id_cnt;       // read ID expiry counters ID0-7
reg                 s_tx_in_pr;     // flag buffer transmission in progress
reg                 s_burst_in_pr;  // flag burst in progress
reg  [  AXI_IW-1:0] s_curr_id;      // current read ID
reg                 s_ar_valid;     // flag next read address valid

//assign ddrd_a_curr_o = d_a_curr;
//assign ddrd_b_curr_o = d_b_curr;

// internal auxiliary signals
wire [       8-1:0] s_id_busy         = {|s_id_cnt[7*AXI_CW+:AXI_CW],|s_id_cnt[6*AXI_CW+:AXI_CW],|s_id_cnt[5*AXI_CW+:AXI_CW],|s_id_cnt[4*AXI_CW+:AXI_CW],
                                         |s_id_cnt[3*AXI_CW+:AXI_CW],|s_id_cnt[2*AXI_CW+:AXI_CW],|s_id_cnt[1*AXI_CW+:AXI_CW],|s_id_cnt[0*AXI_CW+:AXI_CW]};
wire                s_id_free         = (s_id_busy != 8'b11111111);
wire [      32-1:0] s_a_next          = s_a_curr + (2**SBF_AW)*8;
wire [      32-1:0] s_b_next          = s_b_curr + (2**SBF_AW)*8;
wire                s_burst_end       = axi_arready_i & (sbuf_wp[3:0] == 4'b1111);
wire                sbuf_end          = axi_arready_i & (sbuf_wp[SBF_AW-1:0] == {SBF_AW{1'b1}});
wire [       4-1:0] sbuf_newready;
wire                sbuf_pending      = |sbuf_newready;
wire                s_start_new_tx    = (!s_tx_in_pr | sbuf_end) & s_id_free & sbuf_pending;
wire                s_start_new_burst = (s_start_new_tx | s_tx_in_pr) & (!s_burst_in_pr | (s_burst_end & sbuf_pending)) & s_id_free;
wire                s_hold_next_burst = s_burst_end & (!s_id_free | (sbuf_end & !sbuf_pending));


// --------------------------------------------------------------------------------------------------
// AXI ID / outstanding reads control
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        s_curr_id <= 0;
    end else begin
        if (s_start_new_tx | (s_burst_in_pr & axi_arready_i & s_burst_end & !s_hold_next_burst) | s_start_new_burst) begin
            casex (s_id_busy)
            8'b???????0:    begin   s_curr_id <= 0;         end
            8'b??????01:    begin   s_curr_id <= 1;         end
            8'b?????011:    begin   s_curr_id <= 2;         end
            8'b????0111:    begin   s_curr_id <= 3;         end
            8'b???01111:    begin   s_curr_id <= 4;         end
            8'b??011111:    begin   s_curr_id <= 5;         end
            8'b?0111111:    begin   s_curr_id <= 6;         end
            8'b01111111:    begin   s_curr_id <= 7;         end
            8'b11111111:    begin   s_curr_id <= s_curr_id; end
            endcase
        end else begin
            s_curr_id <= s_curr_id;
        end
    end
end

assign  axi_arid_o = s_curr_id;

// generate expiry counter logic
generate for (CNT=0; CNT<8; CNT=CNT+1) begin: s_expiry_counter if (CNT == 0) begin

// counter 0
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        s_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
    end else begin
        if (!s_id_busy[CNT] & (s_start_new_tx | (s_burst_in_pr & axi_arready_i & s_burst_end & !s_hold_next_burst) | s_start_new_burst)) begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
        end else if (axi_rvalid_i & (axi_rid_i == CNT)) begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
        end else if (s_id_busy[CNT]) begin
            if (s_burst_in_pr & (s_curr_id == CNT)) begin
                s_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
            end else begin
                s_id_cnt[CNT*AXI_CW+:AXI_CW] <= s_id_cnt[CNT*AXI_CW+:AXI_CW] - 1;
            end
        end else begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= s_id_cnt[CNT*AXI_CW+:AXI_CW];
        end
    end
end

end else begin // elsegenerate

// counter x
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        s_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
    end else begin
        if (&s_id_busy[CNT-1:0] & !s_id_busy[CNT] & (s_start_new_tx | (s_burst_in_pr & axi_arready_i & s_burst_end & !s_hold_next_burst) | s_start_new_burst)) begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
        end else if (axi_rvalid_i & (axi_rid_i == CNT)) begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
        end else if (s_id_busy[CNT]) begin
            if (s_burst_in_pr & (s_curr_id == CNT)) begin
                s_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
            end else begin
                s_id_cnt[CNT*AXI_CW+:AXI_CW] <= s_id_cnt[CNT*AXI_CW+:AXI_CW] - 1;
            end
        end else begin
            s_id_cnt[CNT*AXI_CW+:AXI_CW] <= s_id_cnt[CNT*AXI_CW+:AXI_CW];
        end
    end
end

end end endgenerate


// --------------------------------------------------------------------------------------------------
//
//                   AXI DDR Dump
//
// --------------------------------------------------------------------------------------------------
// process ready latches from scope
reg  [   4-1:0] dbuf_ready;     // scope buffer ready registers Al,Ah,Bl,Bh
wire [   4-1:0] dbuf_finished;  // signals end of buffer processing Al,Ah,Bl,Bh

always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        dbuf_ready <= 4'b0000;
    end else begin
        if (dbuf_ready_i[0]) begin
            dbuf_ready[0] <= ddrd_control_i[0];
        end else if (dbuf_finished[0]) begin
            dbuf_ready[0] <= 1'b0;
        end else begin
            dbuf_ready[0] <= dbuf_ready[0];
        end

        if (dbuf_ready_i[1]) begin
            dbuf_ready[1] <= ddrd_control_i[0];
        end else if (dbuf_finished[1]) begin
            dbuf_ready[1] <= 1'b0;
        end else begin
            dbuf_ready[1] <= dbuf_ready[1];
        end

        if (dbuf_ready_i[2]) begin
            dbuf_ready[2] <= ddrd_control_i[1];
        end else if (dbuf_finished[2]) begin
            dbuf_ready[2] <= 1'b0;
        end else begin
            dbuf_ready[2] <= dbuf_ready[2];
        end

        if (dbuf_ready_i[3]) begin
            dbuf_ready[3] <= ddrd_control_i[1];
        end else if (dbuf_finished[3]) begin
            dbuf_ready[3] <= 1'b0;
        end else begin
            dbuf_ready[3] <= dbuf_ready[3];
        end
    end
end


// --------------------------------------------------------------------------------------------------
// transfer BRAM data to AXI
reg  [       2-1:0] dbuf_sel;       // select signals for Cha / ChB
reg                 dbuf_sel_ab;    // stores the currently active channel
reg  [  DBF_AW-1:0] dbuf_rp;        // BRAM read pointer
reg  [      32-1:0] d_wp;           // DDR write pointer
reg  [      32-1:0] d_a_curr;       // DDR ChA current write address
reg  [      32-1:0] d_b_curr;       // DDR ChB current write address
reg  [8*AXI_CW-1:0] d_id_cnt;       // write ID expiry counters ID0-7
reg                 d_tx_in_pr;     // flag buffer transmission in progress
reg                 d_burst_in_pr;  // flag burst in progress
reg  [  AXI_IW-1:0] d_curr_id;      // current write ID
reg                 d_aw_valid;     // flag next write address valid

assign ddrd_a_curr_o = d_a_curr;
assign ddrd_b_curr_o = d_b_curr;

// internal auxiliary signals
wire [       8-1:0] d_id_busy         = {|d_id_cnt[7*AXI_CW+:AXI_CW],|d_id_cnt[6*AXI_CW+:AXI_CW],|d_id_cnt[5*AXI_CW+:AXI_CW],|d_id_cnt[4*AXI_CW+:AXI_CW],
                                         |d_id_cnt[3*AXI_CW+:AXI_CW],|d_id_cnt[2*AXI_CW+:AXI_CW],|d_id_cnt[1*AXI_CW+:AXI_CW],|d_id_cnt[0*AXI_CW+:AXI_CW]};
wire                d_id_free         = (d_id_busy != 8'b11111111);
wire [      32-1:0] d_a_next          = d_a_curr + (2**DBF_AW)*8;
wire [      32-1:0] d_b_next          = d_b_curr + (2**DBF_AW)*8;
wire                d_burst_end       = axi_wready_i & (dbuf_rp[3:0] == 4'b1111);
wire                dbuf_end          = axi_wready_i & (dbuf_rp[DBF_AW-1:0] == {DBF_AW{1'b1}});
wire [       4-1:0] dbuf_newready;
wire                dbuf_pending      = |dbuf_newready;
wire                d_start_new_tx    = (!d_tx_in_pr | dbuf_end) & d_id_free & dbuf_pending;
wire                d_start_new_burst = (d_start_new_tx | d_tx_in_pr) & (!d_burst_in_pr | (d_burst_end & dbuf_pending)) & d_id_free;
wire                d_hold_next_burst = d_burst_end & (!d_id_free | (dbuf_end & !dbuf_pending));

// --------------------------------------------------------------------------------------------------
// transaction and burst control
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        d_tx_in_pr    <= 1'b0;
        d_burst_in_pr <= 1'b0;
    end else begin
        if (d_start_new_tx) begin
            d_tx_in_pr <= 1'b1;
        end else if (d_tx_in_pr & dbuf_end & (!d_id_free | !dbuf_pending)) begin
            d_tx_in_pr <= 1'b0;
        end else begin
            d_tx_in_pr <= d_tx_in_pr;
        end

        if (d_start_new_tx | d_start_new_burst) begin
            d_burst_in_pr <= 1'b1;
        end else if (d_burst_in_pr & d_hold_next_burst) begin
            d_burst_in_pr <= 1'b0;
        end else begin
            d_burst_in_pr <= d_burst_in_pr;
        end
    end
end

assign  dbuf_finished[0] = d_tx_in_pr & dbuf_end & ({dbuf_sel_ab,dbuf_rp[11]} == 2'b00);
assign  dbuf_finished[1] = d_tx_in_pr & dbuf_end & ({dbuf_sel_ab,dbuf_rp[11]} == 2'b01);
assign  dbuf_finished[2] = d_tx_in_pr & dbuf_end & ({dbuf_sel_ab,dbuf_rp[11]} == 2'b10);
assign  dbuf_finished[3] = d_tx_in_pr & dbuf_end & ({dbuf_sel_ab,dbuf_rp[11]} == 2'b11);
assign  dbuf_newready[0] = dbuf_ready[0] & !dbuf_finished[0];
assign  dbuf_newready[1] = dbuf_ready[1] & !dbuf_finished[1];
assign  dbuf_newready[2] = dbuf_ready[2] & !dbuf_finished[2];
assign  dbuf_newready[3] = dbuf_ready[3] & !dbuf_finished[3];


// --------------------------------------------------------------------------------------------------
// BRAM control
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        dbuf_sel    <= 2'b00;
        dbuf_sel_ab <= 1'b0;
        dbuf_rp     <= {DBF_AW{1'b0}};
    end else begin
        if (d_start_new_tx | d_start_new_burst) begin
            dbuf_sel <= (dbuf_newready[0] | dbuf_newready[1]) ? 2'b01 : 2'b10;
        end else if (d_burst_in_pr & axi_wready_i & !d_hold_next_burst) begin
            dbuf_sel <= dbuf_sel_ab ? 2'b10 : 2'b01;
        end else begin
            dbuf_sel <= 2'b00;
        end

        if (d_start_new_tx) begin
            dbuf_rp <= (dbuf_newready[0] | (!dbuf_newready[1] & dbuf_newready[2])) ? {1'b0,{DBF_AW-1{1'b0}}} : {1'b1,{DBF_AW-1{1'b0}}};
        end else if ((d_burst_in_pr & axi_wready_i & !d_hold_next_burst) | d_start_new_burst) begin
            dbuf_rp <= dbuf_rp + 1;
        end else begin
            dbuf_rp <= dbuf_rp;
        end

        if (d_start_new_tx) begin
            dbuf_sel_ab <= !(dbuf_newready[0] | dbuf_newready[1]);
        end else begin
            dbuf_sel_ab <= dbuf_sel_ab;
        end
    end
end

assign  dbuf_select_o = dbuf_sel;
assign  dbuf_raddr_o  = dbuf_rp;


// --------------------------------------------------------------------------------------------------
// AXI address control
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        d_wp       <= 32'h00000000;
        d_a_curr   <= 32'h00000000;
        d_b_curr   <= 32'h00000000;
        d_aw_valid <= 1'b0;
    end else begin
        if (d_start_new_tx) begin
            d_wp <= (dbuf_newready[0] | dbuf_newready[1]) ? d_a_curr : d_b_curr;
        end else if ((d_burst_in_pr & axi_wready_i & d_burst_end & !d_hold_next_burst) | d_start_new_burst) begin
            d_wp <= d_wp + 32'h80; // 128 bytes (16 qwords) per burst
        end else begin
            d_wp <= d_wp;
        end

        if (d_start_new_tx & (dbuf_newready[0] | dbuf_newready[1])) begin
            if (d_a_next >= ddrd_a_end_i) begin
                d_a_curr <= ddrd_a_base_i;
            end else begin
                d_a_curr <= d_a_next;
            end
        end else if (ddrd_control_i[2]) begin
            d_a_curr <= ddrd_a_base_i;
        end else begin
            d_a_curr <= d_a_curr;
        end

        if (d_start_new_tx & !(dbuf_newready[0] | dbuf_newready[1])) begin
            if (d_b_next >= ddrd_b_end_i) begin
                d_b_curr <= ddrd_b_base_i;
            end else begin
                d_b_curr <= d_b_next;
            end
        end else if (ddrd_control_i[3]) begin
            d_b_curr <= ddrd_b_base_i;
        end else begin
            d_b_curr <= d_b_curr;
        end

        if (d_start_new_tx | (d_burst_in_pr & axi_wready_i & d_burst_end & !d_hold_next_burst) | d_start_new_burst) begin
            d_aw_valid <= 1'b1;
        end else if (d_aw_valid & axi_awready_i) begin
            d_aw_valid <= 1'b0;
        end else begin
            d_aw_valid <= d_aw_valid;
        end
    end
end

assign  axi_awaddr_o  = d_wp;
assign  axi_awvalid_o = d_aw_valid;
assign  axi_wdata_o   = dbuf_rdata_i;
assign  axi_wlast_o   = (dbuf_rp[3:0] == 4'b1111); // fixed 16 beat burst
assign  axi_wvalid_o  = d_burst_in_pr;
assign  axi_bready_o  = 1'd1;


// --------------------------------------------------------------------------------------------------
// AXI ID / outstanding writes control
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        d_curr_id <= 0;
    end else begin
        if (d_start_new_tx | (d_burst_in_pr & axi_wready_i & d_burst_end & !d_hold_next_burst) | d_start_new_burst) begin
            casex (d_id_busy)
            8'b???????0:    begin   d_curr_id <= 0;         end
            8'b??????01:    begin   d_curr_id <= 1;         end
            8'b?????011:    begin   d_curr_id <= 2;         end
            8'b????0111:    begin   d_curr_id <= 3;         end
            8'b???01111:    begin   d_curr_id <= 4;         end
            8'b??011111:    begin   d_curr_id <= 5;         end
            8'b?0111111:    begin   d_curr_id <= 6;         end
            8'b01111111:    begin   d_curr_id <= 7;         end
            8'b11111111:    begin   d_curr_id <= d_curr_id; end
            endcase
        end else begin
            d_curr_id <= d_curr_id;
        end
    end
end

assign  axi_awid_o = d_curr_id;
assign  axi_wid_o  = d_curr_id;

// generate expiry counter logic
generate for (CNT=0; CNT<8; CNT=CNT+1) begin: d_expiry_counter if (CNT == 0) begin

// counter 0
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        d_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
    end else begin
        if (!d_id_busy[CNT] & (d_start_new_tx | (d_burst_in_pr & axi_wready_i & d_burst_end & !d_hold_next_burst) | d_start_new_burst)) begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
        end else if (axi_bvalid_i & (axi_bid_i == CNT)) begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
        end else if (d_id_busy[CNT]) begin
            if (d_burst_in_pr & (d_curr_id == CNT)) begin
                d_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
            end else begin
                d_id_cnt[CNT*AXI_CW+:AXI_CW] <= d_id_cnt[CNT*AXI_CW+:AXI_CW] - 1;
            end
        end else begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= d_id_cnt[CNT*AXI_CW+:AXI_CW];
        end
    end
end

end else begin // elsegenerate

// counter x
always @(posedge buf_clk_i) begin
    if (!buf_rstn_i) begin
        d_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
    end else begin
        if (&d_id_busy[CNT-1:0] & !d_id_busy[CNT] & (d_start_new_tx | (d_burst_in_pr & axi_wready_i & d_burst_end & !d_hold_next_burst) | d_start_new_burst)) begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
        end else if (axi_bvalid_i & (axi_bid_i == CNT)) begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= 0;
        end else if (d_id_busy[CNT]) begin
            if (d_burst_in_pr & (d_curr_id == CNT)) begin
                d_id_cnt[CNT*AXI_CW+:AXI_CW] <= AXI_CI;
            end else begin
                d_id_cnt[CNT*AXI_CW+:AXI_CW] <= d_id_cnt[CNT*AXI_CW+:AXI_CW] - 1;
            end
        end else begin
            d_id_cnt[CNT*AXI_CW+:AXI_CW] <= d_id_cnt[CNT*AXI_CW+:AXI_CW];
        end
    end
end

end end endgenerate


endmodule
