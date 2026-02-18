`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Module 5: voxel_addr_map
// ============================================================
module voxel_addr_map #(
  parameter int X_BITS = 5,
  parameter int Y_BITS = 5,
  parameter int Z_BITS = 5,
  parameter bit MAP_ZYX = 1'b1
)(
  input  logic [X_BITS-1:0] x,
  input  logic [Y_BITS-1:0] y,
  input  logic [Z_BITS-1:0] z,
  output logic [X_BITS+Y_BITS+Z_BITS-1:0] addr
);

  localparam int ADDR_BITS = X_BITS + Y_BITS + Z_BITS;

  initial begin
    if (X_BITS < 1 || X_BITS > 16) $error("voxel_addr_map: X_BITS=%0d out of range [1:16]", X_BITS);
    if (Y_BITS < 1 || Y_BITS > 16) $error("voxel_addr_map: Y_BITS=%0d out of range [1:16]", Y_BITS);
    if (Z_BITS < 1 || Z_BITS > 16) $error("voxel_addr_map: Z_BITS=%0d out of range [1:16]", Z_BITS);
    if (ADDR_BITS > 32)            $error("voxel_addr_map: ADDR_BITS=%0d exceeds 32", ADDR_BITS);
  end

  always_comb begin
    if (MAP_ZYX) addr = {z, y, x};  // default: (z<<10)|(y<<5)|x for 5/5/5
    else         addr = {x, y, z};
  end

endmodule


// ============================================================
// Module 6: voxel_ram
//  FIXED: sync read now actually uses raddr_q, and WRITE_FIRST compares waddr==raddr_q.
// ============================================================
module voxel_ram #(
  parameter int ADDR_BITS = 15,
  parameter bit SYNC_READ = 1'b1,
  parameter bit WRITE_FIRST = 1'b1
)(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic [ADDR_BITS-1:0] raddr,
  output logic                 rdata,

  input  logic                 we,
  input  logic [ADDR_BITS-1:0] waddr,
  input  logic                 wdata
);

  localparam int DEPTH = 1 << ADDR_BITS;
  logic mem [0:DEPTH-1];

  logic [ADDR_BITS-1:0] raddr_q;

  // Write (sync)
  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
  end

  generate
    if (SYNC_READ) begin : g_sync_read
      // Register the address
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) raddr_q <= '0;
        else        raddr_q <= raddr;
      end

      // Register the output (1-cycle latency from raddr -> rdata)
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          rdata <= 1'b0;
        end else begin
          if (WRITE_FIRST && we && (waddr == raddr_q)) rdata <= wdata;
          else                                         rdata <= mem[raddr_q];
        end
      end
    end else begin : g_comb_read
      always_comb rdata = mem[raddr];
    end
  endgenerate

endmodule


// ============================================================
// Module 7: scene_loader_if
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

  localparam int TOTAL_VOXELS = (1 << ADDR_BITS);

  always_comb begin
    load_ready = 1'b1;
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
          if (!load_mode) begin
            write_count   <= '0;
            load_complete <= 1'b0;
          end else if (we && !load_complete) begin
            if (write_count == (TOTAL_VOXELS - 1)) load_complete <= 1'b1;
            write_count <= write_count + 1'b1;
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


// ============================================================
// SIMULATION-ONLY MODULE: sim_scene_file_loader
//
// Purpose: Let your CPU/Python "load the scene" in simulation by generating
// a file and having SV stream it into scene_loader_if at runtime.
//
// Supported formats:
//   - FORMAT=0: voxels_load.txt with lines: "<addr> <bit>"
//   - FORMAT=1: voxels.mem with lines: "0" or "1" per address (addr = line index)
//
// Usage:
//   - Python writes out/voxels_load.txt (recommended)
//   - Run sim with: +VOXELS_FILE=out/voxels_load.txt +VOXELS_FORMAT=0
//     or:           +VOXELS_FILE=out/voxels.mem      +VOXELS_FORMAT=1
//
// This module drives: load_mode/load_valid/load_addr/load_data until EOF.
// ============================================================
`ifndef SYNTHESIS
module sim_scene_file_loader #(
  parameter int ADDR_BITS = 15
)(
  input  logic                 clk,
  input  logic                 rst_n,

  // Start pulse (or tie high after reset)
  input  logic                 start,

  // To scene_loader_if
  output logic                 load_mode,
  output logic                 load_valid,
  input  logic                 load_ready,
  output logic [ADDR_BITS-1:0] load_addr,
  output logic                 load_data,

  // Status
  output logic                 done,
  output logic [31:0]          lines_loaded
);

  // runtime-configurable file + format
  string voxels_file;
  int    voxels_format; // 0=addr bit, 1=mem lines
  int    fd;
  int    rc;

  // temp parse vars
  int addr_i;
  int bit_i;
  int line_addr;

  typedef enum logic [2:0] {S_IDLE, S_OPEN, S_READ, S_DRIVE, S_DONE, S_FAIL} state_t;
  state_t st;

  // defaults
  initial begin
    voxels_file   = "voxels_load.txt";
    voxels_format = 0;
    void'($value$plusargs("VOXELS_FILE=%s", voxels_file));
    void'($value$plusargs("VOXELS_FORMAT=%d", voxels_format));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st           <= S_IDLE;
      load_mode    <= 1'b0;
      load_valid   <= 1'b0;
      load_addr    <= '0;
      load_data    <= 1'b0;
      done         <= 1'b0;
      lines_loaded <= 32'd0;
      line_addr    <= 0;
      fd           <= 0;
    end else begin
      case (st)
        S_IDLE: begin
          done       <= 1'b0;
          load_mode  <= 1'b0;
          load_valid <= 1'b0;
          if (start) st <= S_OPEN;
        end

        S_OPEN: begin
          fd = $fopen(voxels_file, "r");
          if (fd == 0) begin
            $display("sim_scene_file_loader: ERROR opening '%s'", voxels_file);
            st <= S_FAIL;
          end else begin
            $display("sim_scene_file_loader: loading '%s' format=%0d", voxels_file, voxels_format);
            load_mode <= 1'b1;
            st <= S_READ;
          end
        end

        S_READ: begin
          // Read next record from file
          if (voxels_format == 0) begin
            // addr bit
            rc = $fscanf(fd, "%d %d\n", addr_i, bit_i);
            if (rc == 2) begin
              load_addr  <= addr_i[ADDR_BITS-1:0];
              load_data  <= (bit_i != 0);
              st <= S_DRIVE;
            end else begin
              st <= S_DONE; // EOF or parse failure -> stop
            end
          end else begin
            // mem lines: bit per line, addr = line index
            rc = $fscanf(fd, "%d\n", bit_i);
            if (rc == 1) begin
              load_addr <= line_addr[ADDR_BITS-1:0];
              load_data <= (bit_i != 0);
              line_addr <= line_addr + 1;
              st <= S_DRIVE;
            end else begin
              st <= S_DONE;
            end
          end
        end

        S_DRIVE: begin
          // One-beat write when ready
          if (load_ready) begin
            load_valid <= 1'b1;
            lines_loaded <= lines_loaded + 1;
            st <= S_READ;
          end else begin
            load_valid <= 1'b0;
          end
        end

        S_DONE: begin
          load_valid <= 1'b0;
          load_mode  <= 1'b0;
          done       <= 1'b1;
          if (fd != 0) begin
            $fclose(fd);
            fd <= 0;
          end
          // stay done
        end

        S_FAIL: begin
          load_valid <= 1'b0;
          load_mode  <= 1'b0;
          done       <= 1'b1;
        end
      endcase
    end
  end

endmodule
`endif


`default_nettype wire
