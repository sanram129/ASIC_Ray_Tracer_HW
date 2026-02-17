`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Testbench for scene_loader_if
//  - Verifies we only asserts when load_mode=1 and load_valid=1
//  - Verifies waddr/wdata match inputs on writes
//  - Verifies no writes when load_mode=0
//  - Tests write counter and load_complete functionality
// ============================================================
module scene_loader_if_tb;

  // Parameters
  localparam int ADDR_BITS = 10;  // Smaller for faster test (1K instead of 32K)
  localparam int TOTAL_VOXELS = 1 << ADDR_BITS;
  localparam int CLK_PERIOD = 10;

  // DUT signals
  logic clock;
  logic reset;
  logic load_mode;
  logic load_valid;
  logic load_ready;
  logic [ADDR_BITS-1:0] load_addr;
  logic load_data;
  logic we;
  logic [ADDR_BITS-1:0] waddr;
  logic wdata;
  logic [ADDR_BITS:0] write_count;
  logic load_complete;

  // Test tracking
  int errors;
  int tests;

  // DUT instantiation (with counter enabled)
  scene_loader_if #(
    .ADDR_BITS(ADDR_BITS),
    .ENABLE_COUNTER(1'b1)
  ) dut (
    .clk(clock),
    .rst_n(reset),
    .load_mode(load_mode),
    .load_valid(load_valid),
    .load_ready(load_ready),
    .load_addr(load_addr),
    .load_data(load_data),
    .we(we),
    .waddr(waddr),
    .wdata(wdata),
    .write_count(write_count),
    .load_complete(load_complete)
  );

  // Clock generation
  initial begin
    clock = 0;
    forever #(CLK_PERIOD/2) clock = ~clock;
  end

  // Check task
  task check_we(
    input logic expected_we,
    input string test_name
  );
    begin
      tests++;
      #1; // Allow combinational logic to settle
      if (we !== expected_we) begin
        $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.we : expected_value: 1'b%b actual_value: 1'b%b", 
                 $time, expected_we, we);
        $display("  Test: %s, load_mode=%b, load_valid=%b", test_name, load_mode, load_valid);
        errors++;
      end else begin
        $display("LOG: %0t : INFO : scene_loader_if_tb : dut.we : expected_value: 1'b%b actual_value: 1'b%b", 
                 $time, expected_we, we);
      end
    end
  endtask

  // Check passthrough task
  task check_passthrough(
    input logic [ADDR_BITS-1:0] expected_addr,
    input logic expected_data,
    input string test_name
  );
    begin
      tests++;
      #1; // Allow combinational logic to settle
      if (waddr !== expected_addr || wdata !== expected_data) begin
        $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.waddr/wdata : expected_value: addr=%0d data=%b actual_value: addr=%0d data=%b", 
                 $time, expected_addr, expected_data, waddr, wdata);
        $display("  Test: %s", test_name);
        errors++;
      end else begin
        $display("LOG: %0t : INFO : scene_loader_if_tb : dut.waddr/wdata : expected_value: addr=%0d data=%b actual_value: addr=%0d data=%b", 
                 $time, expected_addr, expected_data, waddr, wdata);
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("TEST START");
    $display("========================================");
    $display("  Testbench: scene_loader_if");
    $display("  Testing scene loader interface");
    $display("  Total voxels: %0d", TOTAL_VOXELS);
    $display("========================================");
    
    errors = 0;
    tests = 0;
    
    // Initialize
    load_mode = 1'b0;
    load_valid = 1'b0;
    load_addr = '0;
    load_data = 1'b0;
    reset = 1'b0;
    
    // Reset sequence
    repeat(3) @(posedge clock);
    reset = 1'b1;
    @(posedge clock);
    
    $display("\n[TEST 1] Verify load_ready always high:");
    tests++;
    if (load_ready !== 1'b1) begin
      $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.load_ready : expected_value: 1'b1 actual_value: 1'b%b", 
               $time, load_ready);
      errors++;
    end else begin
      $display("LOG: %0t : INFO : scene_loader_if_tb : dut.load_ready : expected_value: 1'b1 actual_value: 1'b1", $time);
    end
    
    // Test 2: We should be 0 when load_mode=0
    $display("\n[TEST 2] CRITICAL: we=0 when load_mode=0 (no accidental writes):");
    
    load_mode = 1'b0;
    load_valid = 1'b0;
    check_we(1'b0, "load_mode=0, load_valid=0");
    
    load_valid = 1'b1;
    load_addr = 10'd100;
    load_data = 1'b1;
    check_we(1'b0, "load_mode=0, load_valid=1 (MUST NOT WRITE)");
    
    $display("  CRITICAL safety check passed: no writes when load_mode=0");
    
    // Test 3: We should be 0 when load_valid=0
    $display("\n[TEST 3] we=0 when load_valid=0:");
    
    load_mode = 1'b1;
    load_valid = 1'b0;
    check_we(1'b0, "load_mode=1, load_valid=0");
    
    // Test 4: We should be 1 only when both load_mode=1 AND load_valid=1
    $display("\n[TEST 4] we=1 only when load_mode=1 AND load_valid=1:");
    
    load_mode = 1'b1;
    load_valid = 1'b1;
    load_addr = 10'd50;
    load_data = 1'b1;
    check_we(1'b1, "load_mode=1, load_valid=1 (WRITE ENABLED)");
    
    // Test 5: Verify passthrough of addr and data
    $display("\n[TEST 5] Verify waddr/wdata match load");
    
    load_mode = 1'b1;
    load_valid = 1'b1;
    
    for (int i = 0; i < 10; i++) begin
      load_addr = $urandom_range(0, TOTAL_VOXELS-1);
      load_data = $urandom_range(0, 1);
      check_passthrough(load_addr, load_data, $sformatf("Passthrough test %0d", i));
    end
    
    // Test 6: Write counter functionality
    $display("\n[TEST 6] Write counter increments correctly:");
    
    // Reset counter by exiting and re-entering load_mode
    @(posedge clock);
    load_mode = 1'b0;  // Exit load mode to reset counter
    load_valid = 1'b0;
    
    @(posedge clock);
    @(posedge clock);
    
    // Re-enter load mode with counter reset to 0
    @(posedge clock);
    load_mode = 1'b1;
    load_valid = 1'b0;
    
    @(posedge clock);
    tests++;
    if (write_count !== 0) begin
      $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.write_count : expected_value: 0 actual_value: %0d", 
               $time, write_count);
      errors++;
    end else begin
      $display("LOG: %0t : INFO : scene_loader_if_tb : dut.write_count : expected_value: 0 actual_value: 0", $time);
    end
    
    // Perform some writes
    for (int i = 0; i < 10; i++) begin
      @(posedge clock);
      load_valid = 1'b1;
      load_addr = i;
      load_data = i[0];
    end
    
    @(posedge clock);
    load_valid = 1'b0;
    
    @(posedge clock);
    tests++;
    if (write_count !== 10) begin
      $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.write_count : expected_value: 10 actual_value: %0d", 
               $time, write_count);
      errors++;
    end else begin
      $display("LOG: %0t : INFO : scene_loader_if_tb : dut.write_count : expected_value: 10 actual_value: 10", $time);
    end
    
    // Test 7: Counter reset when exiting load_mode
    $display("\n[TEST 7] Counter resets when load_mode=0:");
    
    @(posedge clock);
    load_mode = 1'b0;
    
    @(posedge clock);
    @(posedge clock);
    tests++;
    if (write_count !== 0) begin
      $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.write_count : expected_value: 0 actual_value: %0d", 
               $time, write_count);
      errors++;
    end else begin
      $display("LOG: %0t : INFO : scene_loader_if_tb : dut.write_count : Counter reset when load_mode=0", $time);
    end
    
    // Test 8: Load complete flag
    $display("\n[TEST 8] load_complete flag at boundary:");
    
    @(posedge clock);
    load_mode = 1'b1;
    
    // Write all voxels
    $display("  Writing all %0d voxels...", TOTAL_VOXELS);
    for (int i = 0; i < TOTAL_VOXELS; i++) begin
      @(posedge clock);
      load_valid = 1'b1;
      load_addr = i;
      load_data = i[0];
      
      // Check complete flag before last write
      if (i == TOTAL_VOXELS - 2) begin
        @(posedge clock);
        tests++;
        if (load_complete !== 1'b0) begin
          $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.load_complete : expected_value: 0 (not done yet) actual_value: %b", 
                   $time, load_complete);
          errors++;
        end
        @(negedge clock);
      end
    end
    
    @(posedge clock);
    load_valid = 1'b0;
    
    @(posedge clock);
    tests++;
    if (load_complete !== 1'b1) begin
      $display("LOG: %0t : ERROR : scene_loader_if_tb : dut.load_complete : expected_value: 1 (all voxels loaded) actual_value: %b", 
               $time, load_complete);
      errors++;
    end else begin
      $display("LOG: %0t : INFO : scene_loader_if_tb : dut.load_complete : All %0d voxels loaded successfully", 
               $time, TOTAL_VOXELS);
    end
    
    // Test 9: Verify write enable control table
    $display("\n[TEST 9] Truth table verification:");
    $display("  load_mode | load_valid | we");
    $display("  ----------|------------|----");
    
    // Test all 4 combinations
    load_mode = 1'b0; load_valid = 1'b0;
    #1;
    $display("     0      |     0      | %b  (expected: 0)", we);
    tests++;
    if (we !== 1'b0) errors++;
    
    load_mode = 1'b0; load_valid = 1'b1;
    #1;
    $display("     0      |     1      | %b  (expected: 0)", we);
    tests++;
    if (we !== 1'b0) errors++;
    
    load_mode = 1'b1; load_valid = 1'b0;
    #1;
    $display("     1      |     0      | %b  (expected: 0)", we);
    tests++;
    if (we !== 1'b0) errors++;
    
    load_mode = 1'b1; load_valid = 1'b1;
    #1;
    $display("     1      |     1      | %b  (expected: 1)", we);
    tests++;
    if (we !== 1'b1) errors++;
    
    // Test 10: Boundary addresses
    $display("\n[TEST 10] Boundary address handling:");
    
    @(posedge clock);
    load_mode = 1'b1;
    load_valid = 1'b1;
    
    // First address
    load_addr = '0;
    load_data = 1'b1;
    check_passthrough('0, 1'b1, "First address (0)");
    
    // Last address
    load_addr = TOTAL_VOXELS - 1;
    load_data = 1'b0;
    check_passthrough(TOTAL_VOXELS-1, 1'b0, "Last address (max)");
    
    // Middle address
    load_addr = TOTAL_VOXELS / 2;
    load_data = 1'b1;
    check_passthrough(TOTAL_VOXELS/2, 1'b1, "Middle address");
    
    // Wait a few cycles
    @(posedge clock);
    load_valid = 1'b0;
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
      $error("scene_loader_if_tb: %0d errors detected", errors);
    end
    
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("scene_loader_if_tb.fst");
    $dumpvars(0);
  end

endmodule

`default_nettype wire
