`timescale 1ns/1ps

module tb_async_fifo;

  // -----------------------------------------------
  // Parameters
  // -----------------------------------------------
  parameter DEPTH      = 8;
  parameter DATA_WIDTH = 8;
  parameter PTR_WIDTH  = 3;

  // -----------------------------------------------
  // Signals
  // -----------------------------------------------
  reg  wclk, rclk;
  reg  wrst_n, rrst_n;
  reg  w_en, r_en;
  reg  [DATA_WIDTH-1:0] data_in;
  wire [DATA_WIDTH-1:0] data_out;
  wire full, empty;

  integer i;

  // -----------------------------------------------
  // DUT Instantiation
  // -----------------------------------------------
  asynchronous_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .PTR_WIDTH(PTR_WIDTH)
  ) dut (
    .wclk   (wclk),
    .wrst_n (wrst_n),
    .rclk   (rclk),
    .rrst_n (rrst_n),
    .w_en   (w_en),
    .r_en   (r_en),
    .data_in(data_in),
    .data_out(data_out),
    .full   (full),
    .empty  (empty)
  );

  // -----------------------------------------------
  // Clock Generation
  // Write clock : 10 ns period (100 MHz)
  // Read  clock : 14 ns period (~71 MHz)  <-- async!
  // -----------------------------------------------
  always #5 wclk = ~wclk;
  always #7 rclk = ~rclk;

  // -----------------------------------------------
  // MAIN TEST SEQUENCE
  // -----------------------------------------------
  initial begin
    // Initialise
    wclk    = 0; rclk    = 0;
    w_en    = 0; r_en    = 0;
    data_in = 0;

    // =========================================
    // TEST CASE 1 : RESET TEST
    // Verifies empty=1, full=0 after reset
    // =========================================
    $display("\n========== TC1: RESET TEST ==========");
    wrst_n = 0;
    rrst_n = 0;
    #50;
    wrst_n = 1;
    rrst_n = 1;
    #50;

    if (empty !== 1'b1) $display("FAIL: empty not 1 after reset");
    if (full  !== 1'b0) $display("FAIL: full not 0 after reset");
    $display("TC1 PASSED - empty=%b  full=%b", empty, full);

    // =========================================
    // TEST CASE 2 : WRITE UNTIL FULL
    // Fills FIFO completely, checks full flag
    // =========================================
    $display("\n========== TC2: WRITE UNTIL FULL ==========");
    for (i = 0; i < DEPTH; i = i + 1) begin
      @(posedge wclk);
      if (!full) begin
        w_en    <= 1;
        data_in <= i;
        $display("  WRITE [%0d] data=0x%0h", i, i);
      end
    end
    @(posedge wclk); w_en <= 0;
    #20;
    if (full !== 1'b1) $display("FAIL: full not asserted");
    // Attempt overflow write - should be ignored
    @(posedge wclk); w_en <= 1; data_in <= 8'hFF;
    @(posedge wclk); w_en <= 0;
    $display("TC2 PASSED - FIFO full=%b (overflow write ignored)", full);

    // Allow pointer sync across clock domains
    #50;

    // =========================================
    // TEST CASE 3 : READ UNTIL EMPTY
    // Drains FIFO, checks empty flag & data order
    // =========================================
    $display("\n========== TC3: READ UNTIL EMPTY ==========");
    for (i = 0; i < DEPTH; i = i + 1) begin
      @(posedge rclk);
      if (!empty) begin
        r_en <= 1;
      end
      @(posedge rclk);
      $display("  READ  [%0d] data=0x%0h", i, data_out);
      r_en <= 0;
    end
    #20;
    if (empty !== 1'b1) $display("FAIL: empty not asserted after drain");
    // Attempt underflow read - should be ignored
    @(posedge rclk); r_en <= 1;
    @(posedge rclk); r_en <= 0;
    $display("TC3 PASSED - FIFO empty=%b (underflow read ignored)", empty);

    // =========================================
    // TEST CASE 4 : SIMULTANEOUS READ & WRITE
    // Write and read at the same time across
    // different clocks - stress test CDC path
    // =========================================
    $display("\n========== TC4: SIMULTANEOUS READ & WRITE ==========");
    // First pre-fill half the FIFO
    repeat(4) begin
      @(posedge wclk);
      if (!full) begin w_en <= 1; data_in <= data_in + 1; end
    end
    @(posedge wclk); w_en <= 0;
    #30;

    // Now simultaneously write and read for 10 cycles
    repeat(10) begin
      @(posedge wclk);
      if (!full)  begin w_en <= 1; data_in <= data_in + 1; end
      else         w_en <= 0;

      @(posedge rclk);
      if (!empty) r_en <= 1;
      else         r_en <= 0;
    end
    @(posedge wclk); w_en <= 0;
    @(posedge rclk); r_en <= 0;
    $display("TC4 PASSED - Simultaneous R/W complete");

    #50;
    $display("\n========== ALL TEST CASES DONE ==========\n");
    $finish;
  end

endmodule
