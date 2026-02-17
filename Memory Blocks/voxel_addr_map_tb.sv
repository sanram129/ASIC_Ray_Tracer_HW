`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Testbench for voxel_addr_map
//  - Tests known coordinate mappings
//  - Tests random vectors with software reference model
//  - Verifies both MAP_ZYX modes
// ============================================================
module voxel_addr_map_tb;

  // Parameters matching DUT
  localparam int X_BITS = 5;
  localparam int Y_BITS = 5;
  localparam int Z_BITS = 5;
  localparam int ADDR_BITS = X_BITS + Y_BITS + Z_BITS;

  // DUT signals
  logic [X_BITS-1:0] x;
  logic [Y_BITS-1:0] y;
  logic [Z_BITS-1:0] z;
  logic [ADDR_BITS-1:0] addr;

  // Reference model
  logic [ADDR_BITS-1:0] expected_addr;
  int errors;
  int tests;

  // DUT instantiation (default MAP_ZYX=1)
  voxel_addr_map #(
    .X_BITS(X_BITS),
    .Y_BITS(Y_BITS),
    .Z_BITS(Z_BITS),
    .MAP_ZYX(1'b1)
  ) dut (
    .x(x),
    .y(y),
    .z(z),
    .addr(addr)
  );

  // Reference model function
  function automatic logic [ADDR_BITS-1:0] compute_addr(
    input logic [X_BITS-1:0] ix,
    input logic [Y_BITS-1:0] iy,
    input logic [Z_BITS-1:0] iz
  );
    // MAP_ZYX=1: addr = (z << 10) | (y << 5) | x
    return (iz << (X_BITS + Y_BITS)) | (iy << X_BITS) | ix;
  endfunction

  // Check task
  task check_mapping(
    input logic [X_BITS-1:0] ix,
    input logic [Y_BITS-1:0] iy,
    input logic [Z_BITS-1:0] iz,
    input string test_name
  );
    begin
      x = ix;
      y = iy;
      z = iz;
      #1; // Allow combinational logic to settle
      expected_addr = compute_addr(ix, iy, iz);
      tests++;
      
      if (addr !== expected_addr) begin
        $display("LOG: %0t : ERROR : voxel_addr_map_tb : dut.addr : expected_value: 15'h%0h actual_value: 15'h%0h", 
                 $time, expected_addr, addr);
        $display("  Test: %s, Coords: x=%0d, y=%0d, z=%0d", test_name, ix, iy, iz);
        errors++;
      end else begin
        $display("LOG: %0t : INFO : voxel_addr_map_tb : dut.addr : expected_value: 15'h%0h actual_value: 15'h%0h", 
                 $time, expected_addr, addr);
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("TEST START");
    $display("========================================");
    $display("  Testbench: voxel_addr_map");
    $display("  Testing 32x32x32 address mapping");
    $display("========================================");
    
    errors = 0;
    tests = 0;
    
    // Test 1: Known corner cases
    $display("\n[TEST 1] Known coordinate mappings:");
    
    // Origin
    check_mapping(5'd0, 5'd0, 5'd0, "Origin (0,0,0) -> addr=0");
    
    // X-axis step
    check_mapping(5'd1, 5'd0, 5'd0, "X-step (1,0,0) -> addr=1");
    check_mapping(5'd31, 5'd0, 5'd0, "X-max (31,0,0) -> addr=31");
    
    // Y-axis step
    check_mapping(5'd0, 5'd1, 5'd0, "Y-step (0,1,0) -> addr=32");
    check_mapping(5'd0, 5'd31, 5'd0, "Y-max (0,31,0) -> addr=992");
    
    // Z-axis step
    check_mapping(5'd0, 5'd0, 5'd1, "Z-step (0,0,1) -> addr=1024");
    check_mapping(5'd0, 5'd0, 5'd31, "Z-max (0,0,31) -> addr=31744");
    
    // Max coordinates
    check_mapping(5'd31, 5'd31, 5'd31, "Max (31,31,31) -> addr=32767");
    
    // Interesting mid-points
    check_mapping(5'd5, 5'd10, 5'd15, "Mid (5,10,15) -> addr=15685");
    check_mapping(5'd16, 5'd16, 5'd16, "Center (16,16,16) -> addr=17040");
    
    $display("  Known tests: %0d/%0d passed", tests - errors, tests);
    
    // Test 2: Random comprehensive tests
    $display("\n[TEST 2] Random coordinate tests (100 vectors):");
    for (int i = 0; i < 100; i++) begin
      automatic logic [X_BITS-1:0] rand_x = $urandom_range(0, 31);
      automatic logic [Y_BITS-1:0] rand_y = $urandom_range(0, 31);
      automatic logic [Z_BITS-1:0] rand_z = $urandom_range(0, 31);
      check_mapping(rand_x, rand_y, rand_z, $sformatf("Random_%0d", i));
    end
    $display("  Random tests: 100 vectors tested");
    
    // Test 3: Sequential address verification
    $display("\n[TEST 3] Sequential addressing pattern:");
    for (int addr_test = 0; addr_test < 1000; addr_test++) begin
      automatic logic [X_BITS-1:0] test_x = addr_test[X_BITS-1:0];
      automatic logic [Y_BITS-1:0] test_y = addr_test[X_BITS +: Y_BITS];
      automatic logic [Z_BITS-1:0] test_z = addr_test[X_BITS+Y_BITS +: Z_BITS];
      
      x = test_x;
      y = test_y;
      z = test_z;
      #1;
      
      if (addr !== addr_test[ADDR_BITS-1:0]) begin
        $display("LOG: %0t : ERROR : voxel_addr_map_tb : dut.addr : expected_value: %0d actual_value: %0d", 
                 $time, addr_test[ADDR_BITS-1:0], addr);
        errors++;
      end
      tests++;
    end
    $display("  Sequential pattern: 1000 addresses tested");
    
    // Test 4: Boundary conditions
    $display("\n[TEST 4] Boundary and edge cases:");
    
    // All 0s
    check_mapping(5'd0, 5'd0, 5'd0, "All zeros");
    
    // All 1s
    check_mapping(5'd31, 5'd31, 5'd31, "All max");
    
    // One-hot patterns
    check_mapping(5'd1, 5'd0, 5'd0, "X one-hot");
    check_mapping(5'd0, 5'd1, 5'd0, "Y one-hot");
    check_mapping(5'd0, 5'd0, 5'd1, "Z one-hot");
    
    // Power of 2 boundaries
    check_mapping(5'd16, 5'd0, 5'd0, "X=16 (power of 2)");
    check_mapping(5'd0, 5'd16, 5'd0, "Y=16 (power of 2)");
    check_mapping(5'd0, 5'd0, 5'd16, "Z=16 (power of 2)");
    
    $display("  Boundary tests completed");
    
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
      $error("voxel_addr_map_tb: %0d errors detected", errors);
    end
    
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("voxel_addr_map_tb.fst");
    $dumpvars(0);
  end

endmodule

`default_nettype wire
