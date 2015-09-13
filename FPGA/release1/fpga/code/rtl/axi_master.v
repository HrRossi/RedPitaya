//////////////////////////////////////////////////////////////////////////////////
// Engineer: Nils Roos <doctor@smart.ms>
// Create Date: 16.07.2014 22:57:49
// 
// Module Name: axi_dummy_read_master
// Description: 
// todo
// 
// Module Name: axi_dump2ddr_master
// Description: 
// AXI HP master that transfers data from two BRAM buffers A/B (not part of the
// module) to two DDR RAM based ringbuffers via the memory interconnect. Transfers
// are organized in half-buffer blocks and interleaved A1 B1 A2 B2. Transfers are
// queued as soon as each half-buffer signals readiness.
// The AXI master uses maximum sized bursts and can employ the full outstanding
// write capabilities of the memory interconnect. 
// 
// Known issues:
// - the first four samples on each channel are corrupted when enabling the DDR
//   Dump functionality; not likely to get fixed because this made it easier to
//   not loose samples during buffer wrap-arounds
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: designed for use with the RedPitaya hardware
// 
//////////////////////////////////////////////////////////////////////////////////

// --------------------------------------------------------------------------------------------------
//
//                   AXI DDR read dummy
//
// --------------------------------------------------------------------------------------------------
module axi_dummy_read_master #(
    parameter   AXI_DW  =  64,  // data width (8,16,...,1024)
    parameter   AXI_AW  =  32,  // AXI address width
    parameter   AXI_IW  =   6   // AXI ID width
)(
    // AXI master read channel
    output [    AXI_AW-1:0] axi_araddr_o,
    output [           1:0] axi_arburst_o,
    output [           3:0] axi_arcache_o,
    output [    AXI_IW-1:0] axi_arid_o,
    output [           3:0] axi_arlen_o,
    output [           1:0] axi_arlock_o,
    output [           2:0] axi_arprot_o,
    output [           3:0] axi_arqos_o,
    input                   axi_arready_i,
    output [           2:0] axi_arsize_o,
    output                  axi_arvalid_o,
    input  [    AXI_DW-1:0] axi_rdata_i,
    input  [    AXI_IW-1:0] axi_rid_i,
    input                   axi_rlast_i,
    output                  axi_rready_o,
    input  [           1:0] axi_rresp_i,
    input                   axi_rvalid_i,
    // AXI clock & reset
    input                   axi_clk_i,
    input                   axi_rstn_i
);


// --------------------------------------------------------------------------------------------------
// set fixed transfer settings
// --------------------------------------------------------------------------------------------------
assign  axi_arsize_o  = 3'b011;         // 8 bytes
assign  axi_arlen_o   = 4'b1111;        // 16 transfers
assign  axi_arburst_o = 2'b01;          // INCR
assign  axi_arcache_o = 4'b0001;        // bufferable, not cacheable
assign  axi_arprot_o  = 3'b000;         // normal, secure, data
assign  axi_arqos_o   = 4'd0;           // priority 0
assign  axi_arlock_o  = 2'b00;          // normal access


// --------------------------------------------------------------------------------------------------
// set dummy signals
// --------------------------------------------------------------------------------------------------
assign  axi_rready_o  = 1'b1;
assign  axi_araddr_o  = {AXI_AW{1'b0}};
assign  axi_arvalid_o = 1'b0;
assign  axi_arid_o    = {AXI_IW{1'b0}};


endmodule


// --------------------------------------------------------------------------------------------------
//
//                   AXI DDR Dump
//
// --------------------------------------------------------------------------------------------------
/*
 * + version 00001 (scope)
 * Initial design
 *
 * + version 00002 (scope)
 * 2014-11-26 Nils Roos <doctor@smart.ms>
 * Interrupt support
 *
 */
module axi_dump2ddr_master #(
    parameter   AXI_DW  =  64,          // data width (8,16,...,1024)
    parameter   AXI_AW  =  32,          // AXI address width
    parameter   AXI_IW  =   6,          // AXI ID width
    parameter   AXI_SW  = AXI_DW >> 3,  // AXI strobe width - 1 bit for every data byte
    parameter   BUF_AW  =   9,          // DDR Dump buffer address width
    parameter   BUF_CH  =   2           // number of buffered channels
)(
    // AXI master write channel
    output [    AXI_AW-1:0] axi_awaddr_o,
    output [           1:0] axi_awburst_o,
    output [           3:0] axi_awcache_o,
    output [    AXI_IW-1:0] axi_awid_o,
    output [           3:0] axi_awlen_o,
    output [           1:0] axi_awlock_o,
    output [           2:0] axi_awprot_o,
    output [           3:0] axi_awqos_o,
    input                   axi_awready_i,
    output [           2:0] axi_awsize_o,
    output                  axi_awvalid_o,
    input  [    AXI_IW-1:0] axi_bid_i,
    output                  axi_bready_o,
    input  [           1:0] axi_bresp_i,
    input                   axi_bvalid_i,
    output [    AXI_DW-1:0] axi_wdata_o,
    output [    AXI_IW-1:0] axi_wid_o,
    output                  axi_wlast_o,
    input                   axi_wready_i,
    output [    AXI_SW-1:0] axi_wstrb_o,
    output                  axi_wvalid_o,
    // AXI clock & reset
    input                   axi_clk_i,
    input                   axi_rstn_i,

    // ADC connection
    output [    BUF_CH-1:0] buf_select_o,
    input  [  2*BUF_CH-1:0] buf_ready_i,    // [0]: ChA 0-1k, [1]: ChA 1k-2k, [2]: ChB 0-1k, [3]: ChB 1k-2k
    output [    BUF_AW-1:0] buf_raddr_o,
    input  [    AXI_DW-1:0] buf_rdata_i,

    // DDR Dump parameter
    input       [   32-1:0] ddr_a_base_i,   // DDR Dump ChA buffer base address
    input       [   32-1:0] ddr_a_end_i,    // DDR Dump ChA buffer end address + 1
    output      [   32-1:0] ddr_a_curr_o,   // DDR Dump ChA current write address
    input       [   32-1:0] ddr_b_base_i,   // DDR Dump ChB buffer base address
    input       [   32-1:0] ddr_b_end_i,    // DDR Dump ChB buffer end address + 1
    output      [   32-1:0] ddr_b_curr_o,   // DDR Dump ChB current write address
    output      [    2-1:0] ddr_status_o,   // DDR Dump [0,1]: INT pending A/B
    input                   ddr_stat_rd_i,  // DDR Dump INT pending was read
    input       [    6-1:0] ddr_control_i,  // DDR Dump [0,1]: dump enable flag A/B, [2,3]: reload curr A/B, [4,5]: INT enable A/B
    output                  ddr_irq0_o      // DDR Dump interrupt request 0
);

localparam AXI_CW = 6;      // width of the ID expiry counters
localparam AXI_CI = 6'h1f;  // initial countdown value for the ID expiry counters
genvar CNT;


// --------------------------------------------------------------------------------------------------
// set fixed transfer settings
// --------------------------------------------------------------------------------------------------
assign  axi_awsize_o  = 3'b011;         // 8 bytes
assign  axi_awlen_o   = 4'b1111;        // 16 transfers
assign  axi_awburst_o = 2'b01;          // INCR
assign  axi_awcache_o = 4'b0001;        // bufferable, not cacheable
assign  axi_awprot_o  = 3'b000;         // normal, secure, data
assign  axi_awqos_o   = 4'd0;           // priority 0
assign  axi_awlock_o  = 2'b00;          // normal access
assign  axi_wstrb_o   = 8'b11111111;    // write all bytes


// --------------------------------------------------------------------------------------------------
// process ready latches from scope
// --------------------------------------------------------------------------------------------------
reg  [   4-1:0] buf_ready;      // scope buffer ready registers Al,Ah,Bl,Bh
wire [   4-1:0] buf_finished;   // signals end of buffer processing Al,Ah,Bl,Bh

always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        buf_ready <= 4'b0000;
    end else begin
        if (buf_ready_i[0]) begin
            buf_ready[0] <= ddr_control_i[0];
        end else if (buf_finished[0]) begin
            buf_ready[0] <= 1'b0;
        end else begin
            buf_ready[0] <= buf_ready[0];
        end

        if (buf_ready_i[1]) begin
            buf_ready[1] <= ddr_control_i[0];
        end else if (buf_finished[1]) begin
            buf_ready[1] <= 1'b0;
        end else begin
            buf_ready[1] <= buf_ready[1];
        end

        if (buf_ready_i[2]) begin
            buf_ready[2] <= ddr_control_i[1];
        end else if (buf_finished[2]) begin
            buf_ready[2] <= 1'b0;
        end else begin
            buf_ready[2] <= buf_ready[2];
        end

        if (buf_ready_i[3]) begin
            buf_ready[3] <= ddr_control_i[1];
        end else if (buf_finished[3]) begin
            buf_ready[3] <= 1'b0;
        end else begin
            buf_ready[3] <= buf_ready[3];
        end
    end
end


// --------------------------------------------------------------------------------------------------
// transfer BRAM data to AXI
// --------------------------------------------------------------------------------------------------
reg  [       2-1:0] buf_sel;        // select signals for Cha / ChB
reg                 buf_sel_ab;     // stores the currently active channel
reg  [  BUF_AW-1:0] buf_rp;         // BRAM read pointer
reg  [      32-1:0] ddr_wp;         // DDR write pointer
reg  [      32-1:0] ddr_a_curr;     // DDR ChA current write address
reg  [      32-1:0] ddr_b_curr;     // DDR ChB current write address
reg                 ddr_aw_valid;   // flag next write address valid
reg  [       2-1:0] ddr_status;     // [0,1] INT pending A/B
reg  [  AXI_CW-1:0] id_cnt[8-1:0];  // write ID expiry counters ID0-7
reg                 tx_in_pr;       // flag buffer transmission in progress
reg                 burst_in_pr;    // flag burst in progress
reg  [  AXI_IW-1:0] curr_id;        // current write ID

assign ddr_a_curr_o = ddr_a_curr;
assign ddr_b_curr_o = ddr_b_curr;
assign ddr_status_o = ddr_status;

// internal auxiliary signals
wire [       8-1:0] id_busy         = {|id_cnt[7],|id_cnt[6],|id_cnt[5],|id_cnt[4],|id_cnt[3],|id_cnt[2],|id_cnt[1],|id_cnt[0]};
wire                id_free         = (id_busy != 8'b11111111);
wire [      32-1:0] ddr_a_next      = ddr_a_curr + (2**(BUF_AW-1))*8;
wire [      32-1:0] ddr_b_next      = ddr_b_curr + (2**(BUF_AW-1))*8;
wire                burst_end       = axi_wready_i & (buf_rp[3:0] == 4'b1111);
wire                buf_end         = burst_end & (buf_rp[BUF_AW-1-1:4] == {BUF_AW-1-4{1'b1}});
wire [       4-1:0] buf_newready;
wire                buf_pending     = |buf_newready;
wire                start_new_tx    = (!tx_in_pr | buf_end) & id_free & buf_pending;
wire                start_new_burst = (start_new_tx | tx_in_pr) & (!burst_in_pr | (burst_end & buf_pending)) & id_free;
wire                hold_next_burst = burst_end & (!id_free | (buf_end & !buf_pending));

// --------------------------------------------------------------------------------------------------
// transaction and burst control
// --------------------------------------------------------------------------------------------------
always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        tx_in_pr    <= 1'b0;
        burst_in_pr <= 1'b0;
    end else begin
        if (start_new_tx) begin
            tx_in_pr <= 1'b1;
        end else if (tx_in_pr & buf_end & (!id_free | !buf_pending)) begin
            tx_in_pr <= 1'b0;
        end else begin
            tx_in_pr <= tx_in_pr;
        end

        if (start_new_tx | start_new_burst) begin
            burst_in_pr <= 1'b1;
        end else if (burst_in_pr & hold_next_burst) begin
            burst_in_pr <= 1'b0;
        end else begin
            burst_in_pr <= burst_in_pr;
        end
    end
end

assign  buf_finished[0] = tx_in_pr & buf_end & !buf_sel_ab & !buf_rp[BUF_AW-1];
assign  buf_finished[1] = tx_in_pr & buf_end & !buf_sel_ab &  buf_rp[BUF_AW-1];
assign  buf_finished[2] = tx_in_pr & buf_end &  buf_sel_ab & !buf_rp[BUF_AW-1];
assign  buf_finished[3] = tx_in_pr & buf_end &  buf_sel_ab &  buf_rp[BUF_AW-1];
assign  buf_newready[0] = buf_ready[0] & !buf_finished[0];
assign  buf_newready[1] = buf_ready[1] & !buf_finished[1];
assign  buf_newready[2] = buf_ready[2] & !buf_finished[2];
assign  buf_newready[3] = buf_ready[3] & !buf_finished[3];


// --------------------------------------------------------------------------------------------------
// BRAM control
// --------------------------------------------------------------------------------------------------
always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        buf_sel    <= 2'b00;
        buf_sel_ab <= 1'b0;
        buf_rp     <= {BUF_AW{1'b0}};
    end else begin
        if (start_new_tx | start_new_burst) begin
            buf_sel <= (buf_newready[0] | buf_newready[1]) ? 2'b01 : 2'b10;
        end else if (burst_in_pr & axi_wready_i & !hold_next_burst) begin
            buf_sel <= buf_sel_ab ? 2'b10 : 2'b01;
        end else begin
            buf_sel <= 2'b00;
        end

        if (start_new_tx) begin
            buf_rp <= {!(buf_newready[0] | (!buf_newready[1] & buf_newready[2])),{BUF_AW-1{1'b0}}};
        end else if ((burst_in_pr & axi_wready_i & !hold_next_burst) | start_new_burst) begin
            buf_rp <= buf_rp + 1;
        end else begin
            buf_rp <= buf_rp;
        end

        if (start_new_tx) begin
            buf_sel_ab <= !(buf_newready[0] | buf_newready[1]);
        end else begin
            buf_sel_ab <= buf_sel_ab;
        end
    end
end

assign  buf_select_o = buf_sel;
assign  buf_raddr_o  = buf_rp;


// --------------------------------------------------------------------------------------------------
// AXI address control
// --------------------------------------------------------------------------------------------------
always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        ddr_wp       <= 32'h00000000;
        ddr_a_curr   <= 32'h00000000;
        ddr_b_curr   <= 32'h00000000;
        ddr_aw_valid <= 1'b0;
    end else begin
        if (start_new_tx) begin
            ddr_wp <= (buf_newready[0] | buf_newready[1]) ? ddr_a_curr : ddr_b_curr;
        end else if ((burst_in_pr & burst_end & !hold_next_burst) | start_new_burst) begin
            ddr_wp <= ddr_wp + 32'h80; // 128 bytes (16 qwords) per burst
        end else begin
            ddr_wp <= ddr_wp;
        end

        if (start_new_tx & (buf_newready[0] | buf_newready[1])) begin
            if (ddr_a_next >= ddr_a_end_i) begin
                ddr_a_curr <= ddr_a_base_i;
            end else begin
                ddr_a_curr <= ddr_a_next;
            end
        end else if (ddr_control_i[2]) begin
            ddr_a_curr <= ddr_a_base_i;
        end else begin
            ddr_a_curr <= ddr_a_curr;
        end

        if (start_new_tx & !(buf_newready[0] | buf_newready[1])) begin
            if (ddr_b_next >= ddr_b_end_i) begin
                ddr_b_curr <= ddr_b_base_i;
            end else begin
                ddr_b_curr <= ddr_b_next;
            end
        end else if (ddr_control_i[3]) begin
            ddr_b_curr <= ddr_b_base_i;
        end else begin
            ddr_b_curr <= ddr_b_curr;
        end

        if (start_new_tx | (burst_in_pr & burst_end & !hold_next_burst) | start_new_burst) begin
            ddr_aw_valid <= 1'b1;
        end else if (ddr_aw_valid & axi_awready_i) begin
            ddr_aw_valid <= 1'b0;
        end else begin
            ddr_aw_valid <= ddr_aw_valid;
        end
    end
end

assign  axi_awaddr_o  = ddr_wp;
assign  axi_awvalid_o = ddr_aw_valid;
assign  axi_wdata_o   = buf_rdata_i;
assign  axi_wlast_o   = (buf_rp[3:0] == 4'b1111); // fixed 16 beat burst
assign  axi_wvalid_o  = burst_in_pr;
assign  axi_bready_o  = 1'd1;


// --------------------------------------------------------------------------------------------------
// AXI ID / outstanding writes control
// --------------------------------------------------------------------------------------------------
always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        curr_id <= 0;
    end else begin
        if (start_new_tx | (burst_in_pr & burst_end & !hold_next_burst) | start_new_burst) begin
            casex (id_busy)
            8'b???????0:    curr_id <= 0;
            8'b??????01:    curr_id <= 1;
            8'b?????011:    curr_id <= 2;
            8'b????0111:    curr_id <= 3;
            8'b???01111:    curr_id <= 4;
            8'b??011111:    curr_id <= 5;
            8'b?0111111:    curr_id <= 6;
            8'b01111111:    curr_id <= 7;
            8'b11111111:    curr_id <= curr_id;
            endcase
        end else begin
            curr_id <= curr_id;
        end
    end
end

assign  axi_awid_o = curr_id;
assign  axi_wid_o  = curr_id;

// generate expiry counter logic
generate for (CNT=0; CNT<8; CNT=CNT+1) begin
always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        id_cnt[CNT] <= 0;
    end else begin
        if ((start_new_tx | (burst_in_pr & burst_end & !hold_next_burst) | start_new_burst) & (CNT == 0 || &id_busy[CNT-1:0]) & !id_busy[CNT]) begin
            id_cnt[CNT] <= AXI_CI;
        end else if (axi_bvalid_i & (axi_bid_i == CNT)) begin
            id_cnt[CNT] <= 0;
        end else if (id_busy[CNT]) begin
            if (burst_in_pr & (curr_id == CNT)) begin
                id_cnt[CNT] <= AXI_CI;
            end else begin
                id_cnt[CNT] <= id_cnt[CNT] - 1;
            end
        end else begin
            id_cnt[CNT] <= id_cnt[CNT];
        end
    end
end
end endgenerate


// --------------------------------------------------------------------------------------------------
// Interrupt control
// --------------------------------------------------------------------------------------------------
reg     ddr_irq0;
reg     ddr_a_prev;
reg     ddr_b_prev;
wire    irq_cond_a = ddr_a_curr[12] ^ ddr_a_prev;
wire    irq_cond_b = ddr_b_curr[12] ^ ddr_b_prev;
(* ASYNC_REG="true" *)  reg  [2:0] ddr_r_sync;

always @(posedge axi_clk_i) begin
    if (!axi_rstn_i) begin
        ddr_status <= 2'b00;
        ddr_irq0   <= 1'b0;
        ddr_a_prev <= 1'b0;
        ddr_b_prev <= 1'b0;
        ddr_r_sync <= 3'b000;
    end else begin
        ddr_r_sync <= {ddr_r_sync[1:0],ddr_stat_rd_i};

        if (irq_cond_a) begin
            ddr_status[0] <= 1'b1;
        end else if (ddr_r_sync[2]) begin
            ddr_status[0] <= 1'b0;
        end else begin
            ddr_status[0] <= ddr_status[0];
        end

        if (irq_cond_b) begin
            ddr_status[1] <= 1'b1;
        end else if (ddr_r_sync[2]) begin
            ddr_status[1] <= 1'b0;
        end else begin
            ddr_status[1] <= ddr_status[1];
        end

        if ((ddr_control_i[4] & !ddr_status[0] & irq_cond_a) |
            (ddr_control_i[5] & !ddr_status[1] & irq_cond_b)) begin
            ddr_irq0 <= 1'b1;
        end else if (ddr_r_sync[2]) begin
            ddr_irq0 <= 1'b0;
        end else begin
            ddr_irq0 <= ddr_irq0;
        end
        ddr_a_prev <= ddr_a_curr[12];
        ddr_b_prev <= ddr_b_curr[12];
    end
end

assign ddr_irq0_o = ddr_irq0;


endmodule
