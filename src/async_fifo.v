module synchronizer#
(parameter Width=3)
(
input [Width:0]in,
output reg [Width:0]q2,
input clk,
input rstn);
reg [Width:0]q1;

always@(posedge clk or negedge rstn)
begin
if(~rstn)
begin
q1<={(Width+1){1'b0}};
q2<={(Width+1){1'b0}};
end
else 
begin
q1<=in;
q2<=q1;
end
end
endmodule


module wptr_handler#
(
 parameter PTR_WIDTH = 3,
 parameter DEPTH = 6
)
(
 input wclk,
 input w_rstn,
 input w_enable,
 input [PTR_WIDTH:0] g_rptr_sync,
 output reg [PTR_WIDTH:0] b_wptr,
 output reg [PTR_WIDTH:0] g_wptr,
 output reg full
);

localparam START = (1 << PTR_WIDTH)/2 - DEPTH/2;
localparam END   = START + DEPTH - 1;

wire [PTR_WIDTH:0] b_wptr_next;
wire [PTR_WIDTH:0] g_wptr_next;
wire wfull;

assign b_wptr_next =
   (!full && w_enable) ?
      (b_wptr == END ? START : b_wptr + 1): b_wptr;

assign g_wptr_next = (b_wptr_next >> 1) ^ b_wptr_next;

assign wfull =
   (g_wptr_next ==
    {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1],
      g_rptr_sync[PTR_WIDTH-2:0]});

always @(posedge wclk or negedge w_rstn)
begin
   if (!w_rstn) begin
      b_wptr <= START;
      g_wptr <= (START >> 1) ^ START;
   end
   else begin
      b_wptr <= b_wptr_next;
      g_wptr <= g_wptr_next;
   end
end

always @(posedge wclk or negedge w_rstn)
begin
   if (!w_rstn)
      full <= 0;
   else
      full <= wfull;
end
endmodule


module rptr_handler#
(
 parameter PTR_WIDTH = 3,
 parameter DEPTH = 6
)
(
 input rclk,
 input r_rstn,
 input r_enable,
 input [PTR_WIDTH:0] g_wptr_sync,
 output reg [PTR_WIDTH:0] b_rptr,
 output reg [PTR_WIDTH:0] g_rptr,
 output reg empty
);

localparam START = (1 << PTR_WIDTH)/2 - DEPTH/2;
localparam END   = START + DEPTH - 1;

wire [PTR_WIDTH:0] b_rptr_next;
wire [PTR_WIDTH:0] g_rptr_next;
wire r_empty;

assign b_rptr_next =
   (!empty && r_enable) ?
      (b_rptr == END ? START : b_rptr + 1)
      : b_rptr;

assign g_rptr_next = (b_rptr_next >> 1) ^ b_rptr_next;
assign r_empty = (g_wptr_sync == g_rptr_next);

always @(posedge rclk or negedge r_rstn)
begin
   if (!r_rstn) begin
      b_rptr <= START;
      g_rptr <= (START >> 1) ^ START;
   end
   else begin
      b_rptr <= b_rptr_next;
      g_rptr <= g_rptr_next;
   end
end

always @(posedge rclk or negedge r_rstn)
begin
   if (!r_rstn)
      empty <= 1'b1;
   else
      empty <= r_empty;
end
endmodule


module fifo_mem #
(
    parameter DEPTH      = 6,
    parameter DATA_WIDTH = 8,
    parameter PTR_WIDTH  = 3
)
(
    input  wire                    wclk,
    input  wire                    rclk,
    input  wire                    w_en,
    input  wire                    r_en,
    input  wire                    full,
    input  wire                    empty,
    input  wire                    rrst_n,
    input  wire [PTR_WIDTH:0]      b_wptr,
    input  wire [PTR_WIDTH:0]      b_rptr,
    input  wire [DATA_WIDTH-1:0]   data_in,
    output reg  [DATA_WIDTH-1:0]   data_out
);

localparam START = (1 << PTR_WIDTH)/2 - DEPTH/2;
reg [DATA_WIDTH-1:0] fifo [0:DEPTH-1];

always @(posedge wclk)
begin
    if (w_en && !full)
        fifo[b_wptr - START] <= data_in;
end

always @(posedge rclk or negedge rrst_n)
begin
    if (!rrst_n)
        data_out <= {DATA_WIDTH{1'b0}};
    else if (r_en && !empty)
        data_out <= fifo[b_rptr - START];
end
endmodule


module asynchronous_fifo #
(
    parameter DEPTH      = 6,
    parameter DATA_WIDTH = 8,
    parameter PTR_WIDTH  = 3
)
(
    input  wire                    wclk,
    input  wire                    wrst_n,
    input  wire                    rclk,
    input  wire                    rrst_n,
    input  wire                    w_en,
    input  wire                    r_en,
    input  wire [DATA_WIDTH-1:0]   data_in,
    output wire [DATA_WIDTH-1:0]   data_out,
    output wire                    full,
    output wire                    empty
);

wire [PTR_WIDTH:0] g_wptr, g_rptr;
wire [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;
wire [PTR_WIDTH:0] b_wptr, b_rptr;

synchronizer #(PTR_WIDTH) sync_wptr (
    .clk   (rclk),
    .rstn  (rrst_n),
    .in    (g_wptr),
    .q2    (g_wptr_sync)
);

synchronizer #(PTR_WIDTH) sync_rptr (
    .clk   (wclk),
    .rstn  (wrst_n),
    .in    (g_rptr),
    .q2    (g_rptr_sync)
);

wptr_handler #(
    .PTR_WIDTH(PTR_WIDTH),
    .DEPTH(DEPTH)
) wptr_inst (
    .wclk        (wclk),
    .w_rstn      (wrst_n),
    .w_enable    (w_en),
    .g_rptr_sync (g_rptr_sync),
    .b_wptr      (b_wptr),
    .g_wptr      (g_wptr),
    .full        (full)
);

rptr_handler #(
    .PTR_WIDTH(PTR_WIDTH),
    .DEPTH(DEPTH)
) rptr_inst (
    .rclk        (rclk),
    .r_rstn      (rrst_n),
    .r_enable    (r_en),
    .g_wptr_sync (g_wptr_sync),
    .b_rptr      (b_rptr),
    .g_rptr      (g_rptr),
    .empty       (empty)
);

fifo_mem #(
    .DEPTH      (DEPTH),
    .DATA_WIDTH (DATA_WIDTH),
    .PTR_WIDTH  (PTR_WIDTH)
) mem_inst (
    .wclk     (wclk),
    .rclk     (rclk),
    .w_en     (w_en),
    .r_en     (r_en),
    .full     (full),
    .empty    (empty),
    .rrst_n   (rrst_n),
    .b_wptr   (b_wptr),
    .b_rptr   (b_rptr),
    .data_in  (data_in),
    .data_out (data_out)
);
endmodule
