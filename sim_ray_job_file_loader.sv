`timescale 1ns/1ps
`default_nettype none

// Simulation-only: read ray_jobs.txt and feed ray_job_if via valid/ready.
//
// Expected file format (from your Python):
//   # px py valid ix0 iy0 iz0 sx sy sz next_x next_y next_z inc_x inc_y inc_z max_steps
//   <px> <py> <valid> <ix0> <iy0> <iz0> <sx> <sy> <sz> <next_x> <next_y> <next_z> <inc_x> <inc_y> <inc_z> <max_steps>
//
// Run with plusarg:
//   +RAY_JOBS_FILE=out/ray_jobs.txt
//
// Notes:
// - This module reads lines with $fgets, then parses with $sscanf.
// - It skips comment lines starting with '#' and blank lines.
// - If SKIP_INVALID=1, it ignores lines where valid==0.
//
`ifndef SYNTHESIS
module sim_ray_job_file_loader #(
  parameter int X_BITS         = 5,
  parameter int Y_BITS         = 5,
  parameter int Z_BITS         = 5,
  parameter int W              = 24,
  parameter int MAX_STEPS_BITS = 10,
  parameter bit SKIP_INVALID   = 1'b1
)(
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   start,     // pulse or tie high after reset
  input  logic                   load_mode, // optional gate (don’t feed while loading)

  // To ray_job_if
  output logic                   job_valid,
  input  logic                   job_ready,

  output logic [X_BITS-1:0]      ix0,
  output logic [Y_BITS-1:0]      iy0,
  output logic [Z_BITS-1:0]      iz0,
  output logic                   sx,
  output logic                   sy,
  output logic                   sz,
  output logic [W-1:0]           next_x,
  output logic [W-1:0]           next_y,
  output logic [W-1:0]           next_z,
  output logic [W-1:0]           inc_x,
  output logic [W-1:0]           inc_y,
  output logic [W-1:0]           inc_z,
  output logic [MAX_STEPS_BITS-1:0] max_steps,

  // Debug / status
  output logic                   done,
  output logic [31:0]            jobs_sent,
  output logic [15:0]            px_q,
  output logic [15:0]            py_q
);

  string ray_jobs_file;
  int fd;

  string line;
  int n;

  // parsed ints
  int px_i, py_i, valid_i;
  int ix0_i, iy0_i, iz0_i;
  int sx_i, sy_i, sz_i;
  int nx_i, ny_i, nz_i;
  int incx_i, incy_i, incz_i;
  int ms_i;

  typedef enum logic [2:0] {S_IDLE, S_OPEN, S_READLINE, S_WAITREADY, S_PULSE, S_DONE, S_FAIL} state_t;
  state_t st;

  task automatic clear_fields();
    ix0 = '0; iy0 = '0; iz0 = '0;
    sx = 1'b0; sy = 1'b0; sz = 1'b0;
    next_x = '0; next_y = '0; next_z = '0;
    inc_x  = '0; inc_y  = '0; inc_z  = '0;
    max_steps = '0;
    px_q = '0; py_q = '0;
  endtask

  initial begin
    ray_jobs_file = "ray_jobs.txt";
    void'($value$plusargs("RAY_JOBS_FILE=%s", ray_jobs_file));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st        <= S_IDLE;
      fd        <= 0;
      job_valid <= 1'b0;
      done      <= 1'b0;
      jobs_sent <= 32'd0;
      clear_fields();
    end else begin
      job_valid <= 1'b0; // pulse style

      case (st)
        S_IDLE: begin
          done      <= 1'b0;
          jobs_sent <= 32'd0;
          clear_fields();
          if (start) st <= S_OPEN;
        end

        S_OPEN: begin
          fd = $fopen(ray_jobs_file, "r");
          if (fd == 0) begin
            $display("sim_ray_job_file_loader: ERROR opening '%s'", ray_jobs_file);
            st <= S_FAIL;
          end else begin
            $display("sim_ray_job_file_loader: Reading '%s'", ray_jobs_file);
            st <= S_READLINE;
          end
        end

        S_READLINE: begin
          if ($feof(fd)) begin
            st <= S_DONE;
          end else begin
            void'($fgets(line, fd));

            // Skip blank lines
            if (line.len() == 0) begin
              st <= S_READLINE;
            end else if (line.substr(0,0) == "#") begin
              // Skip comment/header lines
              st <= S_READLINE;
            end else begin
              // Parse numeric line
              n = $sscanf(line,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
                px_i, py_i, valid_i,
                ix0_i, iy0_i, iz0_i,
                sx_i, sy_i, sz_i,
                nx_i, ny_i, nz_i,
                incx_i, incy_i, incz_i,
                ms_i
              );

              if (n != 16) begin
                // If formatting differs, skip line (or fail hard—your choice)
                $display("sim_ray_job_file_loader: WARN could not parse line: %s", line);
                st <= S_READLINE;
              end else if (SKIP_INVALID && (valid_i == 0)) begin
                st <= S_READLINE;
              end else begin
                // Latch outputs (hold stable while waiting for ready)
                px_q <= px_i[15:0];
                py_q <= py_i[15:0];

                ix0 <= ix0_i[X_BITS-1:0];
                iy0 <= iy0_i[Y_BITS-1:0];
                iz0 <= iz0_i[Z_BITS-1:0];

                sx  <= (sx_i != 0);
                sy  <= (sy_i != 0);
                sz  <= (sz_i != 0);

                next_x <= nx_i[W-1:0];
                next_y <= ny_i[W-1:0];
                next_z <= nz_i[W-1:0];

                inc_x  <= incx_i[W-1:0];
                inc_y  <= incy_i[W-1:0];
                inc_z  <= incz_i[W-1:0];

                max_steps <= ms_i[MAX_STEPS_BITS-1:0];

                st <= S_WAITREADY;
              end
            end
          end
        end

        S_WAITREADY: begin
          if (load_mode) begin
            // don’t feed jobs while scene is loading
            st <= S_WAITREADY;
          end else if (job_ready) begin
            st <= S_PULSE;
          end
        end

        S_PULSE: begin
          job_valid <= 1'b1;        // one-cycle pulse
          jobs_sent <= jobs_sent + 1;
          st <= S_READLINE;
        end

        S_DONE: begin
          job_valid <= 1'b0;
          done <= 1'b1;
          if (fd != 0) begin
            $fclose(fd);
            fd <= 0;
          end
        end

        S_FAIL: begin
          job_valid <= 1'b0;
          done <= 1'b1;
        end

        default: st <= S_FAIL;
      endcase
    end
  end

endmodule
`endif

`default_nettype wire
