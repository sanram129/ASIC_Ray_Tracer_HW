`timescale 1ns/1ps

// Professional ASIC Verification Testbench for voxel_ram
// Features: Scoreboard, Assertions, Coverage, Self-checking

module tb_voxel_ram;

`include "tb_utils.svh"

// Parameters
localparam int ADDR_BITS = 15;  // 32K voxels
localparam bit SYNC_READ = 1'b1;
localparam bit WRITE_FIRST = 1'b1;
localparam int DEPTH = 1 << ADDR_BITS;

// Clock and Reset
logic clk;
logic rst_n;

// DUT Signals
logic [ADDR_BITS-1:0] raddr;
logic rdata;
logic we;
logic [ADDR_BITS-1:0] waddr;
logic wdata;

// Reference Model
logic ref_mem [0:DEPTH-1];
logic [ADDR_BITS-1:0] ref_raddr_q;
logic ref_rdata;

// DUT Instantiation
voxel_ram #(
    .ADDR_BITS(ADDR_BITS),
    .SYNC_READ(SYNC_READ),
    .WRITE_FIRST(WRITE_FIRST)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .raddr(raddr),
    .rdata(rdata),
    .we(we),
    .waddr(waddr),
    .wdata(wdata)
);

// ============================================================================
// REFERENCE MODEL
// ============================================================================

// Reference memory behavior (sync read, write-first)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ref_raddr_q <= '0;
        ref_rdata <= 1'b0;
        // Don't need to clear ref_mem, just track writes
    end else begin
        // Write
        if (we) begin
            ref_mem[waddr] <= wdata;
        end
        
        // Read address pipeline
        ref_raddr_q <= raddr;
        
        // Read data (with write-first check)
        if (WRITE_FIRST && we && (waddr == ref_raddr_q)) begin
            ref_rdata <= wdata;  // Write-first: forward written data
        end else begin
            ref_rdata <= ref_mem[ref_raddr_q];
        end
    end
end

// Scoreboard checking
int check_count = 0;
int mismatch_count = 0;

always @(posedge clk) begin
    if (rst_n) begin
        check_count++;
        
        // Check read data (account for pipeline delay)
        if (rdata !== ref_rdata) begin
            mismatch_count++;
            $error("[MISMATCH #%0d] @%0t: rdata=%b, expected=%b (raddr_q=%h)", 
                mismatch_count, $time, rdata, ref_rdata, ref_raddr_q);
        end
    end
end

// ============================================================================
// ASSERTIONS
// ============================================================================

// Assertion: No X/Z after reset
property p_no_x_after_reset;
    @(posedge clk) rst_n |-> !$isunknown(rdata);
endproperty
assert property (p_no_x_after_reset)
    else $fatal(1, "rdata has X/Z after reset");

// Assertion: Write only when we=1
property p_write_enable;
    @(posedge clk) disable iff (!rst_n)
    we |-> $stable(waddr) && $stable(wdata);
endproperty
// Note: This checks stability during write

// ============================================================================
// COVERAGE
// ============================================================================

covergroup cg_voxel_ram @(posedge clk);
    option.per_instance = 1;
    
    cp_we: coverpoint we {
        bins write = {1};
        bins no_write = {0};
    }
    
    cp_waddr: coverpoint waddr {
        bins zero = {0};
        bins low = {[1:100]};
        bins mid = {[DEPTH/2-50:DEPTH/2+50]};
        bins high = {[DEPTH-100:DEPTH-1]};
    }
    
    cp_raddr: coverpoint raddr {
        bins zero = {0};
        bins low = {[1:100]};
        bins mid = {[DEPTH/2-50:DEPTH/2+50]};
        bins high = {[DEPTH-100:DEPTH-1]};
    }
    point wdata;
    cp;
    
    // Collision coverage
    cp_collision: coverpoint (we && (waddr == raddr)) {
        bins collision = {1};
        bins no_collision = {0};
    }
    
    cx_write_pattern: cross cp_we, cp_wdata;
    cx_collision_case: cross cp_we, cp_collision;
    
endgroup

cg_voxel_ram cov_inst;

// ============================================================================
// TEST STIMULUS
// ============================================================================

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Main test sequence
initial begin
    // Initialize coverage
    cov_inst = new();
    
    // Handle +SEED plusarg
    if ($value$plusargs("SEED=%d", global_seed)) begin
        $display("[INFO] Using seed from plusarg: %0d", global_seed);
    end
    
    // Initialize signals
    raddr = 0;
    we = 0;
    waddr = 0;
    wdata = 0;
    
    // Initialize reference memory
    for (int i = 0; i < DEPTH; i++) begin
        ref_mem[i] = 0;
    end
    
    // Reset
    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    
    $display("========================================");
    $display("Starting voxel_ram Verification");
    $display("Parameters: ADDR_BITS=%0d, SYNC_READ=%0d, WRITE_FIRST=%0d", 
        ADDR_BITS, SYNC_READ, WRITE_FIRST);
    $display("========================================");
    
    // ========================================================================
    // DIRECTED TESTS
    // ========================================================================
    
    test_single_write_read();
    test_write_read_same_addr();
    test_multiple_overwrites();
    test_collision_scenarios();
    test_address_sweep();
    
    // ========================================================================
    // RANDOM TESTS
    // ========================================================================
    
    test_random_read_write(10000);
    
    // ========================================================================
    // FINAL REPORT
    // ========================================================================
    
    repeat(10) @(posedge clk);
    
    $display("========================================");
    $display("Verification Complete");
    $display("Checks: %0d, Mismatches: %0d", check_count, mismatch_count);
    $display("Coverage: %.2f%%", cov_inst.get_coverage());
    $display("========================================");
    
    if (mismatch_count > 0) begin
        $fatal(1, "VERIFICATION FAILED with %0d mismatches", mismatch_count);
    end
    
    final_report();
    $finish;
end

// ============================================================================
// DIRECTED TEST TASKS
// ============================================================================

task test_single_write_read();
    $display("[TEST] Single write-read");
    
    // Write to address 100
    @(posedge clk);
    we = 1;
    waddr = 100;
    wdata = 1;
    @(posedge clk);
    we = 0;
    
    // Read from address 100 (need to account for pipeline)
    @(posedge clk);
    raddr = 100;
    @(posedge clk);  // Pipeline delay
    @(posedge clk);  // Check on next cycle
    
    if (rdata !== 1'b1) $fatal(1, "Single write-read failed");
    
    report_pass("Single write-read");
endtask

task test_write_read_same_addr();
    $display("[TEST] Write-read same address");
    
    // Write to multiple addresses
    for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        we = 1;
        waddr = i * 100;
        wdata = i[0];  // Alternate 0/1
    end
    
    @(posedge clk);
    we = 0;
    
    // Read back and verify
    for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        raddr = i * 100;
        @(posedge clk);
        @(posedge clk);
        if (rdata !== i[0]) $fatal(1, "Write-read mismatch at addr %0d", i*100);
    end
    
    report_pass("Write-read same address");
endtask

task test_multiple_overwrites();
    $display("[TEST] Multiple overwrites");
    
    // Write same address multiple times
    for (int i = 0; i < 5; i++) begin
        @(posedge clk);
        we = 1;
        waddr = 500;
        wdata = i[0];
    end
    
    @(posedge clk);
    we = 0;
    
    // Read final value
    raddr = 500;
    @(posedge clk);
    @(posedge clk);
    
    // Should have last written value (4[0] = 0)
    if (rdata !== 1'b0) $fatal(1, "Overwrite test failed");
    
    report_pass("Multiple overwrites");
endtask

task test_collision_scenarios();
    $display("[TEST] Collision scenarios (write-first)");
    
    // Setup: Write known value
    @(posedge clk);
    we = 1;
    waddr = 1000;
    wdata = 0;
    @(posedge clk);
    we = 0;
    @(posedge clk);
    
    // Test write-first behavior
    // Set up read address in pipeline
    raddr = 1000;
    @(posedge clk);  // raddr now in pipeline (ref_raddr_q)
    
    // Write to same address
    we = 1;
    waddr = 1000;
    wdata = 1;
    @(posedge clk);
    
    // On next cycle, rdata should reflect write-first behavior
    we = 0;
    @(posedge clk);
    
    if (WRITE_FIRST) begin
        if (rdata !== 1'b1) $fatal(1, "Write-first not working");
    end
    
    report_pass("Collision scenarios");
endtask

task test_address_sweep();
    $display("[TEST] Address sweep");
    
    // Write pattern across address space
    for (int i = 0; i < 1024; i++) begin
        @(posedge clk);
        we = 1;
        waddr = i;
        wdata = i[0];  // Alternate pattern
    end
    
    @(posedge clk);
    we = 0;
    
    // Read back and verify
    for (int i = 0; i < 1024; i++) begin
        @(posedge clk);
        raddr = i;
        @(posedge clk);
        @(posedge clk);
        if (rdata !== i[0]) begin
            $fatal(1, "Address sweep mismatch at %0d", i);
        end
    end
    
    report_pass("Address sweep");
endtask

task test_random_read_write(int num_ops);
    $display("[TEST] Random read/write for %0d operations", num_ops);
    
    for (int i = 0; i < num_ops; i++) begin
        @(posedge clk);
        
        // Random write
        we = ($urandom % 4) == 0;  // 25% write rate
        waddr = $urandom % DEPTH;
        wdata = $urandom % 2;
        
        // Random read
        raddr = $urandom % DEPTH;
    end
    
    // Drain pipeline
    we = 0;
    repeat(5) @(posedge clk);
    
    report_pass("Random read/write");
endtask

// Dump waveforms
initial begin
    $dumpfile("tb_voxel_ram.fst");
    $dumpvars(0, tb_voxel_ram);
end

endmodule
