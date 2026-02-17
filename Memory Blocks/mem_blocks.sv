`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Module 5: voxel_addr_map
//  - Pure combinational mapping from (x,y,z) -> linear addr
//  - Default mapping: addr = (z << 10) | (y << 5) | x
//                  = {z[4:0], y[4:0], x[4:0]} for 32^3 world
//
// *** CRITICAL: CPU SOFTWARE MUST USE IDENTICAL MAPPING ***
//     For default 5-5-5 layout: addr = (z << 10) | (y << 5) | x
// ============================================================
module voxel_addr_map #(
  parameter int X_BITS = 5,
  parameter int Y_BITS = 5,
  parameter int Z_BITS = 5,
  parameter bit MAP_ZYX = 1'b1  // 1: {z,y,x} (default), 0: {x,y,z} etc. (extend if needed)
)(
  input  logic [X_BITS-1:0] x,
  input  logic [Y_BITS-1:0] y,
  input  logic [Z_BITS-1:0] z,
  output logic [X_BITS+Y_BITS+Z_BITS-1:0] addr
);

  localparam int ADDR_BITS = X_BITS + Y_BITS + Z_BITS;

  // Compile-time sanity checks
  initial begin
    if (X_BITS < 1 || X_BITS > 16) begin
      $error("voxel_addr_map: X_BITS=%0d out of reasonable range [1:16]", X_BITS);
    end
    if (Y_BITS < 1 || Y_BITS > 16) begin
      $error("voxel_addr_map: Y_BITS=%0d out of reasonable range [1:16]", Y_BITS);
    end
    if (Z_BITS < 1 || Z_BITS > 16) begin
      $error("voxel_addr_map: Z_BITS=%0d out of reasonable range [1:16]", Z_BITS);
    end
    if (ADDR_BITS > 32) begin
      $error("voxel_addr_map: ADDR_BITS=%0d exceeds 32-bit addressing limit", ADDR_BITS);
    end
  end

  always_comb begin
    if (MAP_ZYX) begin
      // Default mapping: addr = (z << (X_BITS+Y_BITS)) | (y << X_BITS) | x
      // For 5-5-5: addr = (z << 10) | (y << 5) | x
      addr = {z, y, x};
    end else begin
      // Alternate mapping (not recommended unless CPU matches)
      addr = {x, y, z};
    end
  end

endmodule


// ============================================================
// Module 6: voxel_ram
//  - 1-bit occupancy RAM for 32^3 voxels (DEPTH = 2^ADDR_BITS)
//  - 1 read port (sync by default) + 1 write port (sync)
//  - Wrapper-friendly: can later replace internals with an SRAM macro.
//
// SYNC_READ TIMING (default=1):
//   Cycle N:   raddr = A
//   Cycle N+1: rdata valid (data from address A)
//
// *** If SYNC_READ=1, downstream step_control MUST insert a wait state ***
//     to allow rdata to become valid before checking occupancy.
//
// WRITE_FIRST behavior (when SYNC_READ=1):
//   If write and read target the same address in the same cycle,
//   WRITE_FIRST=1 forwards new wdata to rdata output.
//
// EXTENSIBILITY:
//   To add material/color data later, change mem element width
//   from 1-bit to N-bits without changing port structure.
// ============================================================
module voxel_ram #(
  parameter int ADDR_BITS = 15,   // 32^3 -> 15 bits
  parameter bit SYNC_READ = 1'b1, // 1: rdata valid 1 cycle after raddr (matches SRAM macros)
  parameter bit WRITE_FIRST = 1'b1 // if read+write same addr in same cycle (sync read), define behavior
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // Read port
  input  logic [ADDR_BITS-1:0] raddr,
  output logic                 rdata,

  // Write port (scene load)
  input  logic                 we,
  input  logic [ADDR_BITS-1:0] waddr,
  input  logic                 wdata
);

  localparam int DEPTH = 1 << ADDR_BITS;

  // 1-bit memory array (extendable to wider data for material/color)
  logic mem [0:DEPTH-1];

  // Optional: Initialize memory from file in simulation
  `ifdef SIM
  initial begin
    // Uncomment and provide file if needed for pre-loading test scenes
    // $readmemh("voxel_init.hex", mem);
  end
  `endif

  // Registered read address for sync read
  logic [ADDR_BITS-1:0] raddr_q;

  // Write (sync)
  always_ff @(posedge clk) begin
    if (we) begin
      mem[waddr] <= wdata;
    end
  end

  generate
    if (SYNC_READ) begin : g_sync_read
      // True 1-cycle read latency: register address, then combinationally read, then register output
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          raddr_q <= '0;
        end else begin
          raddr_q <= raddr;
        end
      end
      
      // Output register with WRITE_FIRST forwarding
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          rdata <= 1'b0;
        end else begin
          // WRITE_FIRST forwarding: if writing to same addr being read,
          // forward new wdata to output (matches typical SRAM behavior)
          if (WRITE_FIRST && we && (waddr == raddr)) begin
            rdata <= wdata;
          end else begin
            rdata <= mem[raddr];
          end
        end
      end
    end else begin : g_comb_read
      // Combinational read (NOT typical SRAM behavior, but useful for quick sim)
      always_comb begin
        rdata = mem[raddr];
      end
    end
  endgenerate

endmodule


// ============================================================
// Module 7: scene_loader_if
//  - Thin interface that converts CPU/harness "load" stream into RAM writes.
//  - Only enables writes during load_mode.
//  - Handshake is minimal (ready always 1 in this basic implementation).
//
// CRITICAL GUARANTEE:
//   When load_mode=0, we is ALWAYS 0 (no accidental RAM corruption)
//
// OPTIONAL FEATURES (enabled by parameter):
//   - Write counter tracks number of voxels loaded
//   - load_complete flag indicates all 32768 voxels written
// ============================================================
module scene_loader_if #(
  parameter int ADDR_BITS = 15,
  parameter bit ENABLE_COUNTER = 1'b1
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 load_mode,
  input  logic                 load_valid,
  output logic                 load_ready,
  input  logic [ADDR_BITS-1:0] load_addr,
  input  logic                 load_data,

  output logic                 we,
  output logic [ADDR_BITS-1:0] waddr,
  output logic                 wdata,

  output logic [ADDR_BITS:0]   write_count,
  output logic                 load_complete
);

  // unsigned avoids sign surprises; 1u ensures the shift is unsigned
  localparam int TOTAL_VOXELS = (1 << ADDR_BITS);

  // Always-ready
  always_comb begin
    load_ready = 1'b1;

    // Only write in load_mode
    we    = load_mode && load_valid && load_ready;
    waddr = load_addr;
    wdata = load_data;
  end

  generate
    if (ENABLE_COUNTER) begin : g_counter
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          write_count   <= '0;
          load_complete <= 1'b0;
        end else begin
          // Reset when not in load mode
          if (!load_mode) begin
            write_count   <= '0;
            load_complete <= 1'b0;
          end else begin
            // Count ONLY until complete (prevents overflow / wrap confusion)
            if (we && !load_complete) begin
              // complete on the last write (same as your intent)
              if (write_count == (TOTAL_VOXELS - 1)) begin
                load_complete <= 1'b1;
              end
              write_count <= write_count + 1'b1;
            end
          end
        end
      end
    end else begin : g_no_counter
      always_comb begin
        write_count   = '0;
        load_complete = 1'b0;
      end
    end
  endgenerate

endmodule


`default_nettype wire
