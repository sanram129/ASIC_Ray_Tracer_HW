`timescale 1ns/1ps
`default_nettype none

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
  always_comb begin
    if (MAP_ZYX) addr = {z, y, x}; // (z<<10)|(y<<5)|x for 5/5/5
    else         addr = {x, y, z};
  end
endmodule


module voxel_ram #(
  parameter int ADDR_BITS   = 15,
  parameter bit SYNC_READ   = 1'b1,
  parameter bit WRITE_FIRST = 1'b1,

  // NEW: simulation init
  parameter string INIT_FILE = ""   // e.g. "voxels.mem" (0/1 per line)
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

`ifndef SYNTHESIS
  initial begin
    if (INIT_FILE != "") begin
      $display("voxel_ram: preloading '%s' with $readmemb", INIT_FILE);
      $readmemb(INIT_FILE, mem);
    end
  end
`endif

  logic [ADDR_BITS-1:0] raddr_q;

  // Write port
  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
  end

  generate
    if (SYNC_READ) begin : g_sync_read
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          raddr_q <= '0;
          rdata   <= 1'b0;
        end else begin
          raddr_q <= raddr;
          if (WRITE_FIRST && we && (waddr == raddr_q)) rdata <= wdata;
          else                                        rdata <= mem[raddr_q];
        end
      end
    end else begin : g_comb_read
      always_comb rdata = mem[raddr];
    end
  endgenerate

endmodule


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

  localparam int TOTAL_VOXELS = 1 << ADDR_BITS;

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
          end else if (we) begin
            write_count <= write_count + 1'b1;
            if (write_count == (TOTAL_VOXELS - 1)) load_complete <= 1'b1;
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
