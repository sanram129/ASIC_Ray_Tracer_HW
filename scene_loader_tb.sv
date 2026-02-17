`timescale 1ns/1ps
`default_nettype none

module scene_loader_if_tb;

  localparam int ADDR_BITS   = 15;          // 32^3 = 32768
  localparam int DEPTH       = 1 << ADDR_BITS;
  localparam int CLK_PERIOD  = 10;

  // Clock/reset
  logic clk;
  logic rst_n;

  // Loader interface
  logic load_mode;
  logic load_valid;
  logic load_ready;
  logic [ADDR_BITS-1:0] load_addr;
  logic load_data;

  // Loader -> RAM wires
  logic we;
  logic [ADDR_BITS-1:0] waddr;
  logic wdata;

  // RAM readback
  logic [ADDR_BITS-1:0] raddr;
  logic rdata;

  // Status
  logic [ADDR_BITS:0] write_count;
  logic load_complete;

  int errors;

  // Holds expected bits loaded from file
  logic expected [0:DEPTH-1];

  // DUT: loader
  scene_loader_if #(
    .ADDR_BITS(ADDR_BITS),
    .ENABLE_COUNTER(1'b1)
  ) u_loader (
    .clk(clk),
    .rst_n(rst_n),
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

  // DUT: RAM (no init preload here; we want to test the streaming path)
  voxel_ram #(
    .ADDR_BITS(ADDR_BITS),
    .SYNC_READ(1'b1),
    .WRITE_FIRST(1'b1),
    .INIT_FILE("") // keep empty so we ONLY load through scene_loader_if
  ) u_ram (
    .clk(clk),
    .rst_n(rst_n),
    .raddr(raddr),
    .rdata(rdata),
    .we(we),
    .waddr(waddr),
    .wdata(wdata)
  );

  // Clock
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Load expected[] from voxels.mem (0/1 per line, 32768 lines)
  initial begin
    $display("TB: reading voxels.mem into expected[]...");
    $readmemb("voxels.mem", expected);
  end

  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      $display("ERROR @%0t: %s", $time, msg);
      errors++;
    end
  endtask

  // Main
  initial begin
    errors = 0;

    // Init signals
    rst_n      = 1'b0;
    load_mode  = 1'b0;
    load_valid = 1'b0;
    load_addr  = '0;
    load_data  = 1'b0;
    raddr      = '0;

    // Reset
    repeat (3) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    // Safety check: no writes when load_mode=0
    load_mode  <= 1'b0;
    load_valid <= 1'b1;
    load_addr  <= 'd123;
    load_data  <= 1'b1;
    @(negedge clk);
    check(we == 1'b0, "we must be 0 when load_mode=0");
    @(posedge clk);

    // Start streaming load
    $display("TB: streaming %0d voxels into RAM via scene_loader_if...", DEPTH);
    load_mode <= 1'b1;

    for (int i = 0; i < DEPTH; i++) begin
      @(posedge clk);
      load_valid <= 1'b1;
      load_addr  <= i[ADDR_BITS-1:0];
      load_data  <= expected[i];
    end

    @(posedge clk);
    load_valid <= 1'b0;
    load_mode  <= 1'b0;

    // Check completion flag/counter
    @(posedge clk);
    check(write_count == DEPTH, $sformatf("write_count expected %0d, got %0d", DEPTH, write_count));
    check(load_complete == 1'b1, "load_complete should be 1 after full load");

    // Random readback verification (SYNC_READ needs a couple cycles in this implementation)
    $display("TB: readback spot-check...");
    for (int k = 0; k < 50; k++) begin
      int a = $urandom_range(0, DEPTH-1);

      // Apply raddr
      raddr <= a[ADDR_BITS-1:0];
      // Give pipeline time (conservative)
      @(posedge clk);
      @(posedge clk);

      check(rdata === expected[a], $sformatf("read mismatch at addr %0d: exp=%0d got=%0d", a, expected[a], rdata));
    end

    if (errors == 0) $display("TB PASS");
    else begin
      $display("TB FAIL: %0d errors", errors);
      $fatal(1);
    end

    $finish;
  end

  initial begin
    $dumpfile("scene_loader_if_tb.fst");
    $dumpvars(0, scene_loader_if_tb);
  end

endmodule

`default_nettype wire
