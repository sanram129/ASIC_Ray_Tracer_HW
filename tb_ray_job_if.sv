`timescale 1ns/1ps
`default_nettype none

module tb_ray_job_if;

  localparam int X_BITS = 5;
  localparam int Y_BITS = 5;
  localparam int Z_BITS = 5;
  localparam int W      = 24;
  localparam int MSB    = 10;

  // clock/reset
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // load_mode gating (tie low for this TB)
  logic load_mode = 1'b0;

  // ray_job_if handshake + fields
  logic job_valid;
  logic job_ready;

  logic [X_BITS-1:0] ix0, iy0, iz0;
  logic sx, sy, sz;
  logic [W-1:0] next_x, next_y, next_z;
  logic [W-1:0] inc_x, inc_y, inc_z;
  logic [MSB-1:0] max_steps;

  logic job_done;

  // ray_job_if outputs
  logic job_loaded, job_active;
  logic [X_BITS-1:0] ix0_q, iy0_q, iz0_q;
  logic sx_q, sy_q, sz_q;
  logic [W-1:0] next_x_q, next_y_q, next_z_q;
  logic [W-1:0] inc_x_q, inc_y_q, inc_z_q;
  logic [MSB-1:0] max_steps_q;

  // sim loader status
  logic loader_done;
  logic [31:0] jobs_sent;
  logic [15:0] px_q, py_q;

  logic start_jobs;

  // ----------------------------------------
  // Instantiate ray_job_if (your RTL)
  // ----------------------------------------
  ray_job_if #(
    .X_BITS(X_BITS),
    .Y_BITS(Y_BITS),
    .Z_BITS(Z_BITS),
    .W(W),
    .MAX_STEPS_BITS(MSB)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .load_mode(load_mode),

    .job_valid(job_valid),
    .job_ready(job_ready),

    .ix0(ix0), .iy0(iy0), .iz0(iz0),
    .sx(sx), .sy(sy), .sz(sz),
    .next_x(next_x), .next_y(next_y), .next_z(next_z),
    .inc_x(inc_x), .inc_y(inc_y), .inc_z(inc_z),
    .max_steps(max_steps),

    .job_done(job_done),

    .job_loaded(job_loaded),
    .job_active(job_active),

    .ix0_q(ix0_q), .iy0_q(iy0_q), .iz0_q(iz0_q),
    .sx_q(sx_q), .sy_q(sy_q), .sz_q(sz_q),
    .next_x_q(next_x_q), .next_y_q(next_y_q), .next_z_q(next_z_q),
    .inc_x_q(inc_x_q), .inc_y_q(inc_y_q), .inc_z_q(inc_z_q),
    .max_steps_q(max_steps_q)
  );

`ifndef SYNTHESIS
  // ----------------------------------------
  // Instantiate sim job file loader
  // ----------------------------------------
  sim_ray_job_file_loader #(
    .X_BITS(X_BITS),
    .Y_BITS(Y_BITS),
    .Z_BITS(Z_BITS),
    .W(W),
    .MAX_STEPS_BITS(MSB),
    .SKIP_INVALID(1'b1)
  ) u_jobs (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_jobs),
    .load_mode(load_mode),

    .job_valid(job_valid),
    .job_ready(job_ready),

    .ix0(ix0), .iy0(iy0), .iz0(iz0),
    .sx(sx), .sy(sy), .sz(sz),
    .next_x(next_x), .next_y(next_y), .next_z(next_z),
    .inc_x(inc_x), .inc_y(inc_y), .inc_z(inc_z),
    .max_steps(max_steps),

    .done(loader_done),
    .jobs_sent(jobs_sent),
    .px_q(px_q),
    .py_q(py_q)
  );
`else
  // Synthesis build: tie off
  assign job_valid = 1'b0;
  assign ix0 = '0; assign iy0 = '0; assign iz0 = '0;
  assign sx = 1'b0; assign sy = 1'b0; assign sz = 1'b0;
  assign next_x = '0; assign next_y = '0; assign next_z = '0;
  assign inc_x  = '0; assign inc_y  = '0; assign inc_z  = '0;
  assign max_steps = '0;
  assign loader_done = 1'b1;
  assign jobs_sent = 32'd0;
  assign px_q = '0;
  assign py_q = '0;
`endif

  // ----------------------------------------
  // Fake "downstream" completion:
  // after a job is accepted (job_loaded pulse),
  // wait a few cycles and then pulse job_done.
  // ----------------------------------------
  int countdown;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      countdown <= 0;
      job_done  <= 1'b0;
    end else begin
      job_done <= 1'b0;

      if (job_loaded) begin
        countdown <= 6; // pretend the stepper takes 6 cycles
        $display("[TB] Accepted job for pixel (%0d,%0d) start=(%0d,%0d,%0d) s=(%0d,%0d,%0d) max_steps=%0d",
                 px_q, py_q, ix0_q, iy0_q, iz0_q, sx_q, sy_q, sz_q, max_steps_q);
      end else if (countdown > 0) begin
        countdown <= countdown - 1;
        if (countdown == 1) begin
          job_done <= 1'b1;
          $display("[TB] job_done pulse");
        end
      end
    end
  end

  // ----------------------------------------
  // TB control
  // ----------------------------------------
  initial begin
    start_jobs = 1'b0;

    @(posedge rst_n);
    @(posedge clk);

    // Kick job feeding
    start_jobs = 1'b1;
    @(posedge clk);
    start_jobs = 1'b0;

    // Wait until EOF
    wait (loader_done);
    $display("[TB] All jobs sent. jobs_sent=%0d", jobs_sent);

    // Let last job_done happen
    repeat (20) @(posedge clk);

    $finish;
  end

  initial begin
    $dumpfile("tb_ray_job_if.fst");
    $dumpvars(0, tb_ray_job_if);
  end

endmodule

`default_nettype wire
