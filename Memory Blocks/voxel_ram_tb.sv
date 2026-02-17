`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Testbench for voxel_ram (FIXED CLOCKING)
//  - Drives inputs on NEGEDGE so DUT samples cleanly on POSEDGE
//  - SYNC_READ=1: rdata corresponds to raddr sampled on the previous posedge
//    (with this RAM implementation: set raddr before posedge N -> data valid after posedge N+1)
//  - Tests SYNC_READ=1 timing, SYNC_READ=0 combinational read,
//    WRITE_FIRST forwarding, random patterns, boundaries.
// ============================================================
module voxel_ram_tb;

  // Parameters
  localparam int ADDR_BITS   = 10;  // Smaller for faster sim (1K instead of 32K)
  localparam int DEPTH       = 1 << ADDR_BITS;
  localparam int CLK_PERIOD  = 10;

  // Common signals (shared for both DUTs)
  logic clock;
  logic rst_n;
  logic [ADDR_BITS-1:0] raddr;
  logic [ADDR_BITS-1:0] waddr;
  logic we;
  logic wdata;

  // SYNC_READ=1 DUT
  logic rdata_sync;
  voxel_ram #(
    .ADDR_BITS(ADDR_BITS),
    .SYNC_READ(1'b1),
    .WRITE_FIRST(1'b1)
  ) dut_sync (
    .clk  (clock),
    .rst_n(rst_n),
    .raddr(raddr),
    .rdata(rdata_sync),
    .we   (we),
    .waddr(waddr),
    .wdata(wdata)
  );

  // SYNC_READ=0 DUT
  logic rdata_comb;
  voxel_ram #(
    .ADDR_BITS(ADDR_BITS),
    .SYNC_READ(1'b0),
    .WRITE_FIRST(1'b0)  // Don't care for comb read in this TB
  ) dut_comb (
    .clk  (clock),
    .rst_n(rst_n),
    .raddr(raddr),
    .rdata(rdata_comb),
    .we   (we),
    .waddr(waddr),
    .wdata(wdata)
  );

  // Test tracking
  int errors;
  int tests;

  // Random test arrays
  logic [ADDR_BITS-1:0] test_addrs [20];
  logic                 test_data  [20];

  // Clock generation
  initial begin
    clock = 1'b0;
    forever #(CLK_PERIOD/2) clock = ~clock;
  end

  // -----------------------------------------
  // Logging-style check tasks (unchanged style)
  // -----------------------------------------
  task check_sync_read(
    input logic [ADDR_BITS-1:0] addr,
    input logic expected,
    input string test_name
  );
    begin
      tests++;
      if (rdata_sync !== expected) begin
        $display("LOG: %0t : ERROR : voxel_ram_tb : dut_sync.rdata : expected_value: 1'b%b actual_value: 1'b%b",
                 $time, expected, rdata_sync);
        $display("  Test: %s, Addr: %0d", test_name, addr);
        errors++;
      end else begin
        $display("LOG: %0t : INFO : voxel_ram_tb : dut_sync.rdata : expected_value: 1'b%b actual_value: 1'b%b",
                 $time, expected, rdata_sync);
      end
    end
  endtask

  task check_comb_read(
    input logic [ADDR_BITS-1:0] addr,
    input logic expected,
    input string test_name
  );
    begin
      tests++;
      #1; // Allow combinational logic to settle
      if (rdata_comb !== expected) begin
        $display("LOG: %0t : ERROR : voxel_ram_tb : dut_comb.rdata : expected_value: 1'b%b actual_value: 1'b%b",
                 $time, expected, rdata_comb);
        $display("  Test: %s, Addr: %0d", test_name, addr);
        errors++;
      end else begin
        $display("LOG: %0t : INFO : voxel_ram_tb : dut_comb.rdata : expected_value: 1'b%b actual_value: 1'b%b",
                 $time, expected, rdata_comb);
      end
    end
  endtask

  // -----------------------------------------
  // Helper: write one entry (drive on negedge)
  // -----------------------------------------
  task automatic do_write(input logic [ADDR_BITS-1:0] addr, input logic data);
    begin
      @(negedge clock);
      we    = 1'b1;
      waddr = addr;
      wdata = data;
      // write occurs at next posedge
      @(negedge clock);
      we    = 1'b0;
    end
  endtask

  // -----------------------------------------
  // Helper: sync read expectation (1-cycle after sampling)
  // For this DUT: set raddr before posedge N -> data valid after posedge N+1
  // With negedge driving:
  //   negedge: set raddr
  //   posedge: DUT samples raddr
  //   next posedge: DUT outputs corresponding rdata
  // -----------------------------------------
  task automatic do_sync_read_check(
    input logic [ADDR_BITS-1:0] addr,
    input logic expected,
    input string test_name
  );
    begin
      @(negedge clock);
      raddr = addr;

      @(posedge clock); // raddr sampled internally
      @(posedge clock); // rdata becomes valid for that sampled address

      check_sync_read(addr, expected, test_name);
    end
  endtask

  // -----------------------------------------
  // Main test sequence
  // -----------------------------------------
  initial begin
    $display("TEST START");
    $display("========================================");
    $display("  Testbench: voxel_ram");
    $display("  Testing memory read/write operations");
    $display("  Depth: %0d words", DEPTH);
    $display("========================================");

    errors = 0;
    tests  = 0;

    // Initialize
    raddr = '0;
    waddr = '0;
    we    = 1'b0;
    wdata = 1'b0;
    rst_n = 1'b0; // active-low reset asserted

    // Reset sequence
    repeat(3) @(posedge clock);
    rst_n = 1'b1; // deassert reset
    @(posedge clock);

    $display("\n[TEST 1] Reset behavior - check initial rdata=0:");
    // rdata_sync is reset to 0 in DUT; check after reset deasserted
    check_sync_read('0, 1'b0, "Reset check sync");

    // ------------------------------------------------------------
    // Test 2: Basic write and sync read timing
    // ------------------------------------------------------------
    $display("\n[TEST 2] SYNC_READ=1 timing test:");
    $display("  Write pattern to addresses 0-9...");

    // Write pattern: alternating 0,1,0,1... (drive on negedge)
    for (int i = 0; i < 10; i++) begin
      @(negedge clock);
      we    = 1'b1;
      waddr = logic'(i[ADDR_BITS-1:0]);
      wdata = i[0];
    end
    @(negedge clock);
    we = 1'b0;

    $display("  Read back with 1-cycle latency (sampled at posedge, valid after next posedge)...");
    for (int i = 0; i < 10; i++) begin
      do_sync_read_check(logic'(i[ADDR_BITS-1:0]), i[0], $sformatf("Sync read addr %0d", i));
    end

    // ------------------------------------------------------------
    // Test 3: Combinational read (SYNC_READ=0)
    // ------------------------------------------------------------
    $display("\n[TEST 3] SYNC_READ=0 combinational read:");
    $display("  Reading immediately (no latency)...");

    we = 1'b0;
    for (int i = 0; i < 10; i++) begin
      raddr = logic'(i[ADDR_BITS-1:0]);
      check_comb_read(logic'(i[ADDR_BITS-1:0]), i[0], $sformatf("Comb read addr %0d", i));
    end

    // ------------------------------------------------------------
    // Test 4: WRITE_FIRST behavior (sync)
    // ------------------------------------------------------------
    $display("\n[TEST 4] WRITE_FIRST forwarding test:");
    $display("  Testing simultaneous write and read to same address...");

    // Setup: write 0 to address 100
    do_write(10'd100, 1'b0);

    // Prime sync read pipeline: read addr 100 -> expect 0
    do_sync_read_check(10'd100, 1'b0, "Read old value from addr 100");

    // Now do collision: ensure raddr_q is already 100 when we write.
    // Sequence:
    //   negedge: set raddr=100
    //   posedge: captures raddr_q=100
    //   negedge: assert we to write addr 100 data=1 while still reading 100
    //   posedge: rdata should forward new wdata (WRITE_FIRST)
    @(negedge clock);
    raddr = 10'd100;
    @(posedge clock); // raddr_q becomes 100 inside sync RAM

    @(negedge clock);
    we    = 1'b1;
    waddr = 10'd100;
    wdata = 1'b1;
    // keep raddr at 100
    @(posedge clock); // forwarding happens here

    // Deassert write
    @(negedge clock);
    we = 1'b0;

    // With WRITE_FIRST=1, rdata_sync should now be 1 (immediately after that posedge)
    check_sync_read(10'd100, 1'b1, "WRITE_FIRST forwarding");

    // ------------------------------------------------------------
    // Test 5: Random write/read pattern
    // ------------------------------------------------------------
    $display("\n[TEST 5] Random access pattern:");

    // Generate random test pattern
    for (int i = 0; i < 20; i++) begin
      test_addrs[i] = $urandom_range(0, DEPTH-1);
      test_data[i]  = $urandom_range(0, 1);
    end

    // Write pattern
    for (int i = 0; i < 20; i++) begin
      @(negedge clock);
      we    = 1'b1;
      waddr = test_addrs[i];
      wdata = test_data[i];
    end
    @(negedge clock);
    we = 1'b0;

    // Read back and verify (sync read)
    for (int i = 0; i < 20; i++) begin
      do_sync_read_check(test_addrs[i], test_data[i], $sformatf("Random access %0d", i));
    end

    // ------------------------------------------------------------
    // Test 6: Address boundary checks
    // ------------------------------------------------------------
    $display("\n[TEST 6] Boundary address tests:");

    // Write to first address = 0
    @(negedge clock);
    we    = 1'b1;
    waddr = '0;
    wdata = 1'b1;

    // Write to last address = all 1s
    @(negedge clock);
    waddr = {ADDR_BITS{1'b1}};
    wdata = 1'b0;

    @(negedge clock);
    we = 1'b0;

    // Read first
    do_sync_read_check('0, 1'b1, "First address");

    // Read last
    do_sync_read_check({ADDR_BITS{1'b1}}, 1'b0, "Last address");

    // ------------------------------------------------------------
    // Test 7: Both RAM variants match expected at same address
    // (Note: they share the same stimulus, so this validates both behave correctly.)
    // ------------------------------------------------------------
    $display("\n[TEST 7] Verify sync and comb RAMs match expected behavior:");

    // Write 1 to address 50
    do_write(10'd50, 1'b1);

    // Set raddr=50 and wait for sync to become valid, then check both
    @(negedge clock);
    raddr = 10'd50;
    @(posedge clock); // sample
    @(posedge clock); // sync valid

    tests++;
    #1; // allow comb settle too
    if (rdata_sync === 1'b1 && rdata_comb === 1'b1) begin
      $display("LOG: %0t : INFO : voxel_ram_tb : both_rams : Both RAMs correctly store data", $time);
    end else begin
      $display("LOG: %0t : ERROR : voxel_ram_tb : both_rams : expected_value: sync=1 comb=1 actual_value: sync=%b comb=%b",
               $time, rdata_sync, rdata_comb);
      errors++;
    end

    // Wait a few cycles
    repeat(5) @(posedge clock);

    // Final report
    $display("\n========================================");
    $display("  Test Summary:");
    $display("    Total tests: %0d", tests);
    $display("    Passed:      %0d", tests - errors);
    $display("    Failed:      %0d", errors);
    $display("========================================");

    if (errors == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED");
      $error("voxel_ram_tb: %0d errors detected", errors);
    end

    $finish;
  end

  // Waveform dump (more widely compatible)
  initial begin
    $dumpfile("voxel_ram_tb.vcd");
    $dumpvars(0, voxel_ram_tb);
  end

endmodule

`default_nettype wire
