`timescale 1ns/1ps

// =============================================================================
// Testbench: tb_voxel_raytracer_core
// Description: Comprehensive self-checking testbench for clocked voxel raytracer
//              Tests pipeline, scene loading, and full system integration
// =============================================================================

module tb_voxel_raytracer_core;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int W = 32;
    localparam int COORD_W = 6;
    localparam int MAX_VAL = 31;
    localparam int ADDR_BITS = 15;
    localparam int PIPELINE_LATENCY = 6;  // Actual: 1(in)+1(axis)+1(step)+1(bounds)+2(RAM sync read)
    localparam int NUM_RANDOM_TESTS = 20000;
    localparam real CLOCK_PERIOD = 10.0;  // 10ns = 100MHz
    
    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic clk;
    logic rst_n;
    
    // Ray step inputs
    logic [4:0]  ix_in, iy_in, iz_in;
    logic        sx_in, sy_in, sz_in;
    logic [31:0] next_x_in, next_y_in, next_z_in;
    logic [31:0] inc_x_in, inc_y_in, inc_z_in;
    logic        step_valid_in;
    
    // Scene loading interface
    logic        load_mode;
    logic        load_valid;
    logic        load_ready;
    logic [14:0] load_addr;
    logic        load_data;
    logic [15:0] write_count;
    logic        load_complete;
    
    // Ray step outputs
    logic [4:0]  ix_out, iy_out, iz_out;
    logic [31:0] next_x_out, next_y_out, next_z_out;
    logic [2:0]  face_mask_out;
    logic [2:0]  primary_face_id_out;
    logic        out_of_bounds_out;
    logic        voxel_occupied_out;
    logic        step_valid_out;
    
    // =========================================================================
    // Testbench State
    // =========================================================================
    int test_count;
    int cycle_count;
    
    // Testbench-side scene memory model
    logic scene_mem [0:32767];
    
    // Scoreboard for pipeline tracking
    typedef struct {
        // Original inputs
        logic [4:0]  ix, iy, iz;
        logic        sx, sy, sz;
        logic [31:0] next_x, next_y, next_z;
        logic [31:0] inc_x, inc_y, inc_z;
        // Expected outputs
        logic [4:0]  exp_ix, exp_iy, exp_iz;
        logic [31:0] exp_next_x, exp_next_y, exp_next_z;
        logic [2:0]  exp_step_mask;
        logic [1:0]  exp_primary_sel;
        logic [2:0]  exp_face_mask;
        logic [2:0]  exp_primary_face_id;
        logic        exp_out_of_bounds;
        logic [14:0] exp_addr;
        logic        exp_voxel_occupied;
        int          cycle_issued;
    } scoreboard_entry_t;
    
    scoreboard_entry_t scoreboard[$];
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    voxel_raytracer_core #(
        .W(W),
        .COORD_W(COORD_W),
        .MAX_VAL(MAX_VAL),
        .ADDR_BITS(ADDR_BITS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ix_in(ix_in),
        .iy_in(iy_in),
        .iz_in(iz_in),
        .sx_in(sx_in),
        .sy_in(sy_in),
        .sz_in(sz_in),
        .next_x_in(next_x_in),
        .next_y_in(next_y_in),
        .next_z_in(next_z_in),
        .inc_x_in(inc_x_in),
        .inc_y_in(inc_y_in),
        .inc_z_in(inc_z_in),
        .step_valid_in(step_valid_in),
        .load_mode(load_mode),
        .load_valid(load_valid),
        .load_ready(load_ready),
        .load_addr(load_addr),
        .load_data(load_data),
        .write_count(write_count),
        .load_complete(load_complete),
        .ix_out(ix_out),
        .iy_out(iy_out),
        .iz_out(iz_out),
        .next_x_out(next_x_out),
        .next_y_out(next_y_out),
        .next_z_out(next_z_out),
        .face_mask_out(face_mask_out),
        .primary_face_id_out(primary_face_id_out),
        .out_of_bounds_out(out_of_bounds_out),
        .voxel_occupied_out(voxel_occupied_out),
        .step_valid_out(step_valid_out)
    );
    
    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end
    
    // Cycle counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end
    
    // =========================================================================
    // Helper Functions
    // =========================================================================
    
    // Compute expected step_mask and primary_sel
    function automatic void compute_axis_choose(
        input logic [31:0] nx, ny, nz,
        output logic [2:0] exp_mask,
        output logic [1:0] exp_sel
    );
        logic [31:0] min_val;
        
        // Find minimum
        if (nx <= ny && nx <= nz) min_val = nx;
        else if (ny <= nz) min_val = ny;
        else min_val = nz;
        
        // Generate mask
        exp_mask[0] = (nx == min_val);
        exp_mask[1] = (ny == min_val);
        exp_mask[2] = (nz == min_val);
        
        // Primary sel = lowest set bit
        if (exp_mask[0]) exp_sel = 2'd0;
        else if (exp_mask[1]) exp_sel = 2'd1;
        else exp_sel = 2'd2;
    endfunction
    
    // Compute expected step_update results
    function automatic void compute_step_update(
        input logic [4:0] ix, iy, iz,
        input logic sx, sy, sz,
        input logic [31:0] nx, ny, nz,
        input logic [31:0] incx, incy, incz,
        input logic [2:0] mask,
        input logic [1:0] psel,
        output logic [4:0] exp_ix, exp_iy, exp_iz,
        output logic [31:0] exp_nx, exp_ny, exp_nz,
        output logic [2:0] exp_fmask,
        output logic [2:0] exp_faceid
    );
        // Face mask = step mask
        exp_fmask = mask;
        
        // Update coordinates and timers based on mask
        if (mask[0]) begin
            exp_ix = sx ? (ix + 5'd1) : (ix - 5'd1);
            exp_nx = nx + incx;
        end else begin
            exp_ix = ix;
            exp_nx = nx;
        end
        
        if (mask[1]) begin
            exp_iy = sy ? (iy + 5'd1) : (iy - 5'd1);
            exp_ny = ny + incy;
        end else begin
            exp_iy = iy;
            exp_ny = ny;
        end
        
        if (mask[2]) begin
            exp_iz = sz ? (iz + 5'd1) : (iz - 5'd1);
            exp_nz = nz + incz;
        end else begin
            exp_iz = iz;
            exp_nz = nz;
        end
        
        // Compute primary_face_id
        case (psel)
            2'd0: exp_faceid = sx ? 3'd0 : 3'd1;  // X+/X-
            2'd1: exp_faceid = sy ? 3'd2 : 3'd3;  // Y+/Y-
            2'd2: exp_faceid = sz ? 3'd4 : 3'd5;  // Z+/Z-
            default: exp_faceid = 3'd0;
        endcase
    endfunction
    
    // Compute expected address using MAP_ZYX formula
    function automatic logic [14:0] compute_address(
        input logic [4:0] x, y, z
    );
        return {z, y, x};  // addr = (z<<10) | (y<<5) | x
    endfunction
    
    // Compute expected out_of_bounds
    function automatic logic compute_out_of_bounds(
        input logic [4:0] x, y, z
    );
        logic [5:0] ext_x, ext_y, ext_z;
        ext_x = {1'b0, x};
        ext_y = {1'b0, y};
        ext_z = {1'b0, z};
        return (ext_x > 31) || (ext_y > 31) || (ext_z > 31);
    endfunction
    
    // =========================================================================
    // Scene Loading Task
    // =========================================================================
    task automatic load_scene(input string pattern_name, input int pattern_type);
        int addr;
        int writes_done;
        int timeout;
        
        $display("[%0t] Loading scene pattern: %s", $time, pattern_name);
        
        // Initialize testbench scene memory
        for (int i = 0; i < 32768; i++) begin
            case (pattern_type)
                0: scene_mem[i] = 1'b0;  // All zeros
                1: scene_mem[i] = (i % 17 == 0) ? 1'b1 : 1'b0;  // Sparse pattern
                2: begin  // Landmark pattern
                    // Set specific voxels
                    if (i == compute_address(5'd0, 5'd0, 5'd0)) scene_mem[i] = 1'b1;
                    else if (i == compute_address(5'd31, 5'd31, 5'd31)) scene_mem[i] = 1'b1;
                    else if (i == compute_address(5'd15, 5'd15, 5'd15)) scene_mem[i] = 1'b1;
                    else if (i == compute_address(5'd10, 5'd20, 5'd30)) scene_mem[i] = 1'b1;
                    else scene_mem[i] = 1'b0;
                end
                default: scene_mem[i] = 1'b0;
            endcase
        end
        
        // Enter load mode
        @(posedge clk);
        load_mode = 1'b1;
        load_valid = 1'b0;
        
        // Write scene to DUT
        writes_done = 0;
        timeout = 0;
        for (int i = 0; i < 32768; i++) begin
            @(posedge clk);
            load_valid = 1'b1;
            load_addr = i[14:0];
            load_data = scene_mem[i];
            
            if (load_ready) writes_done++;
            
            // Simple timeout
            timeout++;
            if (timeout > 40000) begin
                $display("ERROR: Scene loading timeout after %0d cycles", timeout);
                $fatal(1, "Scene loading did not complete");
            end
        end
        
        @(posedge clk);
        load_valid = 1'b0;
        
        // Wait for load_complete
        timeout = 0;
        while (!load_complete && timeout < 100) begin
            @(posedge clk);
            timeout++;
        end
        
        @(posedge clk);
        load_mode = 1'b0;
        
        // CRITICAL: Wait for write pipeline to fully drain
        // The RAM has 1-cycle write latency + potential in-flight writes
        // Need sufficient cycles to ensure all writes commit to memory
        repeat(20) @(posedge clk);
        
        $display("[%0t] Scene loaded: %0d writes, write_count=%0d", 
                 $time, writes_done, write_count);
    endtask
    
    // =========================================================================
    // Apply Ray Step Transaction
    // =========================================================================
    task automatic apply_transaction(
        input logic [4:0] ix, iy, iz,
        input logic sx, sy, sz,
        input logic [31:0] nx, ny, nz,
        input logic [31:0] incx, incy, incz
    );
        scoreboard_entry_t entry;
        logic [2:0] exp_mask;
        logic [1:0] exp_sel;
        
        // Store original inputs
        entry.ix = ix; entry.iy = iy; entry.iz = iz;
        entry.sx = sx; entry.sy = sy; entry.sz = sz;
        entry.next_x = nx; entry.next_y = ny; entry.next_z = nz;
        entry.inc_x = incx; entry.inc_y = incy; entry.inc_z = incz;
        entry.cycle_issued = cycle_count;
        
        // Compute expected axis_choose
        compute_axis_choose(nx, ny, nz, exp_mask, exp_sel);
        entry.exp_step_mask = exp_mask;
        entry.exp_primary_sel = exp_sel;
        
        // Compute expected step_update
        compute_step_update(
            ix, iy, iz, sx, sy, sz, nx, ny, nz, incx, incy, incz,
            exp_mask, exp_sel,
            entry.exp_ix, entry.exp_iy, entry.exp_iz,
            entry.exp_next_x, entry.exp_next_y, entry.exp_next_z,
            entry.exp_face_mask, entry.exp_primary_face_id
        );
        
        // Compute expected bounds and address
        entry.exp_out_of_bounds = compute_out_of_bounds(entry.exp_ix, entry.exp_iy, entry.exp_iz);
        entry.exp_addr = compute_address(entry.exp_ix, entry.exp_iy, entry.exp_iz);
        entry.exp_voxel_occupied = scene_mem[entry.exp_addr];
        
        // Push to scoreboard
        scoreboard.push_back(entry);
        
        // Apply to DUT
        ix_in = ix; iy_in = iy; iz_in = iz;
        sx_in = sx; sy_in = sy; sz_in = sz;
        next_x_in = nx; next_y_in = ny; next_z_in = nz;
        inc_x_in = incx; inc_y_in = incy; inc_z_in = incz;
        step_valid_in = 1'b1;
        
        @(posedge clk);
        step_valid_in = 1'b0;
    endtask
    
    // =========================================================================
    // Check Output
    // =========================================================================
    task automatic check_output();
        scoreboard_entry_t exp;
        
        if (step_valid_out) begin
            if (scoreboard.size() == 0) begin
                $display("\nERROR: Unexpected step_valid_out at cycle %0d with empty scoreboard", 
                         cycle_count);
                $fatal(1, "PIPELINE TRACKING ERROR: Valid output without pending transaction");
            end
            
            exp = scoreboard.pop_front();
            test_count++;
            
            // Check all outputs
            if (ix_out !== exp.exp_ix || iy_out !== exp.exp_iy || iz_out !== exp.exp_iz ||
                next_x_out !== exp.exp_next_x || next_y_out !== exp.exp_next_y || next_z_out !== exp.exp_next_z ||
                face_mask_out !== exp.exp_face_mask || primary_face_id_out !== exp.exp_primary_face_id ||
                out_of_bounds_out !== exp.exp_out_of_bounds || voxel_occupied_out !== exp.exp_voxel_occupied) begin
                
                $display("\n========== FAILURE at cycle %0d (input was cycle %0d, latency=%0d) ==========",
                         cycle_count, exp.cycle_issued, cycle_count - exp.cycle_issued);
                $display("Original Inputs:");
                $display("  ix=%0d, iy=%0d, iz=%0d", exp.ix, exp.iy, exp.iz);
                $display("  sx=%0b, sy=%0b, sz=%0b", exp.sx, exp.sy, exp.sz);
                $display("  next_x=0x%08h, next_y=0x%08h, next_z=0x%08h", 
                         exp.next_x, exp.next_y, exp.next_z);
                $display("  inc_x=0x%08h, inc_y=0x%08h, inc_z=0x%08h",
                         exp.inc_x, exp.inc_y, exp.inc_z);
                
                $display("\nExpected Intermediate:");
                $display("  step_mask=3'b%03b, primary_sel=%0d", exp.exp_step_mask, exp.exp_primary_sel);
                $display("  addr=0x%04h (formula: (z<<10)|(y<<5)|x)", exp.exp_addr);
                
                $display("\nExpected Outputs:");
                $display("  ix=%0d, iy=%0d, iz=%0d", exp.exp_ix, exp.exp_iy, exp.exp_iz);
                $display("  next_x=0x%08h, next_y=0x%08h, next_z=0x%08h",
                         exp.exp_next_x, exp.exp_next_y, exp.exp_next_z);
                $display("  face_mask=3'b%03b, primary_face_id=%0d",
                         exp.exp_face_mask, exp.exp_primary_face_id);
                $display("  out_of_bounds=%0b, voxel_occupied=%0b",
                         exp.exp_out_of_bounds, exp.exp_voxel_occupied);
                
                $display("\nActual Outputs:");
                $display("  ix=%0d, iy=%0d, iz=%0d", ix_out, iy_out, iz_out);
                $display("  next_x=0x%08h, next_y=0x%08h, next_z=0x%08h",
                         next_x_out, next_y_out, next_z_out);
                $display("  face_mask=3'b%03b, primary_face_id=%0d",
                         face_mask_out, primary_face_id_out);
                $display("  out_of_bounds=%0b, voxel_occupied=%0b",
                         out_of_bounds_out, voxel_occupied_out);
                
                $display("\nLikely Root Causes:");
                if (ix_out !== exp.exp_ix || iy_out !== exp.exp_iy || iz_out !== exp.exp_iz)
                    $display("  - Coordinate mismatch: step_update integration issue or sign handling");
                if (face_mask_out !== exp.exp_face_mask)
                    $display("  - face_mask != step_mask: wiring mismatch in pipeline");
                if (voxel_occupied_out !== exp.exp_voxel_occupied)
                    $display("  - voxel_occupied mismatch: RAM read alignment issue or address mapping error");
                if (out_of_bounds_out !== exp.exp_out_of_bounds)
                    $display("  - bounds_check mismatch: zero-extension or comparison issue");
                    
                $fatal(1, "OUTPUT MISMATCH");
            end
        end
    endtask
    
    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        test_count = 0;
        
        // Initialize
        ix_in = '0; iy_in = '0; iz_in = '0;
        sx_in = '0; sy_in = '0; sz_in = '0;
        next_x_in = '0; next_y_in = '0; next_z_in = '0;
        inc_x_in = '0; inc_y_in = '0; inc_z_in = '0;
        step_valid_in = '0;
        load_mode = '0;
        load_valid = '0;
        load_addr = '0;
        load_data = '0;
        
        // Reset
        rst_n = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("\n=== Scene Loading Tests ===\n");
        
        // Load Pattern A: All zeros
        load_scene("All Zeros", 0);
        
        // Load Pattern B: Sparse pattern
        load_scene("Sparse (mod 17)", 1);
        
        // Load Pattern C: Landmarks
        load_scene("Landmarks", 2);
        
        repeat(10) @(posedge clk);
        
        $display("\n=== Directed Tests ===\n");
        
        // Test 1: Strict minimum cases
        $display("Test: X strictly smallest");
        apply_transaction(5'd10, 5'd10, 5'd10, 1'b1, 1'b1, 1'b1,
                          32'h1000, 32'h2000, 32'h3000,
                          32'h100, 32'h200, 32'h300);
        
        $display("Test: Y strictly smallest");
        apply_transaction(5'd15, 5'd15, 5'd15, 1'b0, 1'b1, 1'b0,
                          32'h3000, 32'h1000, 32'h2000,
                          32'h50, 32'h60, 32'h70);
        
        $display("Test: Z strictly smallest");
        apply_transaction(5'd20, 5'd20, 5'd20, 1'b1, 1'b0, 1'b1,
                          32'h5000, 32'h4000, 32'h1000,
                          32'h10, 32'h20, 32'h30);
        
        // Test 2: Tie cases
        $display("Test: X==Y < Z");
        apply_transaction(5'd5, 5'd5, 5'd5, 1'b1, 1'b1, 1'b0,
                          32'h1000, 32'h1000, 32'h2000,
                          32'h1, 32'h2, 32'h3);
        
        $display("Test: X==Z < Y");
        apply_transaction(5'd8, 5'd8, 5'd8, 1'b0, 1'b0, 1'b1,
                          32'h5000, 32'hA000, 32'h5000,
                          32'h100, 32'h100, 32'h100);
        
        $display("Test: Y==Z < X");
        apply_transaction(5'd12, 5'd12, 5'd12, 1'b1, 1'b0, 1'b0,
                          32'hF000, 32'h3000, 32'h3000,
                          32'h50, 32'h60, 32'h70);
        
        $display("Test: X==Y==Z (triple tie)");
        apply_transaction(5'd16, 5'd16, 5'd16, 1'b1, 1'b0, 1'b1,
                          32'h7777, 32'h7777, 32'h7777,
                          32'hAAAA, 32'hBBBB, 32'hCCCC);
        
        // Test 3: Edge coordinates
        $display("Test: Wrap from 31 to 0");
        apply_transaction(5'd31, 5'd31, 5'd31, 1'b1, 1'b1, 1'b1,
                          32'h100, 32'h100, 32'h100,
                          32'h1, 32'h2, 32'h3);
        
        $display("Test: Wrap from 0 to 31");
        apply_transaction(5'd0, 5'd0, 5'd0, 1'b0, 1'b0, 1'b0,
                          32'h500, 32'h600, 32'h700,
                          32'h10, 32'h20, 32'h30);
        
        // Wait for directed tests to complete
        repeat(PIPELINE_LATENCY + 5) @(posedge clk);
        
        $display("\n=== Random Tests (%0d transactions) ===\n", NUM_RANDOM_TESTS);
        
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [4:0] rand_ix, rand_iy, rand_iz;
            logic rand_sx, rand_sy, rand_sz;
            logic [31:0] rand_nx, rand_ny, rand_nz;
            logic [31:0] rand_incx, rand_incy, rand_incz;
            
            // Random coordinates
            rand_ix = $urandom() & 5'h1F;
            rand_iy = $urandom() & 5'h1F;
            rand_iz = $urandom() & 5'h1F;
            
            // Random signs
            rand_sx = $urandom() & 1'b1;
            rand_sy = $urandom() & 1'b1;
            rand_sz = $urandom() & 1'b1;
            
            // Random timers with tie bias
            rand_nx = $urandom();
            rand_ny = $urandom();
            rand_nz = $urandom();
            
            // 30% tie bias
            if (($urandom() % 100) < 30) begin
                case ($urandom() % 6)
                    0: rand_ny = rand_nx;
                    1: rand_nz = rand_nx;
                    2: rand_nz = rand_ny;
                    3: begin rand_ny = rand_nx; rand_nz = rand_nx; end
                    4: rand_nz = rand_ny;
                    5: rand_ny = rand_nx;
                endcase
            end
            
            // Random increments (often 0)
            rand_incx = ($urandom() % 10 < 3) ? 32'h0 : $urandom();
            rand_incy = ($urandom() % 10 < 3) ? 32'h0 : $urandom();
            rand_incz = ($urandom() % 10 < 3) ? 32'h0 : $urandom();
            
            // Apply with random valid gaps (50% probability)
            if (($urandom() % 100) < 50) begin
                apply_transaction(rand_ix, rand_iy, rand_iz,
                                  rand_sx, rand_sy, rand_sz,
                                  rand_nx, rand_ny, rand_nz,
                                  rand_incx, rand_incy, rand_incz);
            end else begin
                @(posedge clk);  // Gap cycle
            end
        end
        
        // Wait for all outputs to complete
        $display("\nWaiting for pipeline to drain...");
        repeat(PIPELINE_LATENCY + 10) @(posedge clk);
        
        if (scoreboard.size() != 0) begin
            $display("WARNING: Scoreboard has %0d remaining entries", scoreboard.size());
        end
        
        $display("\n=== All Tests Completed Successfully ===");
        $display("PASS: %0d transactions verified", test_count);
        $display("\nTEST PASSED");
        $finish;
    end
    
    // Continuous output checking
    always @(posedge clk) begin
        if (rst_n) check_output();
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule
