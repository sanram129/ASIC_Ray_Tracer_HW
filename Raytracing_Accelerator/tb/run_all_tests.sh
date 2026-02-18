#!/bin/bash
# Run all ASIC verification testbenches

set -e  # Exit on first error

echo "========================================"
echo "Running All Verification Testbenches"
echo "========================================"
echo ""

SEED=${SEED:-42}  # Default seed
PASSED=0
FAILED=0

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

run_test() {
    local test_name=$1
    local rtl_files=$2
    local tb_file=$3
    
    echo "----------------------------------------"
    echo "Running: $test_name"
    echo "----------------------------------------"
    
    # Compile
    if iverilog -g2012 -o sim_$test_name -Icommon $rtl_files $tb_file; then
        echo "[OK] Compilation successful"
    else
        echo -e "${RED}[FAIL] Compilation failed${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # Run simulation
    if vvp sim_$test_name +SEED=$SEED > ${test_name}_log.txt 2>&1; then
        if grep -q "ALL TESTS PASSED" ${test_name}_log.txt; then
            echo -e "${GREEN}[PASS] $test_name${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}[FAIL] $test_name - No PASS message${NC}"
            FAILED=$((FAILED + 1))
            cat ${test_name}_log.txt
        fi
    else
        echo -e "${RED}[FAIL] $test_name - Simulation error${NC}"
        FAILED=$((FAILED + 1))
        cat ${test_name}_log.txt
    fi
    
    echo ""
}

# Run each testbench
cd "$(dirname "$0")"

run_test "ray_job_if" \
    "../ray_job_if.sv" \
    "tb_ray_job_if.sv"

run_test "voxel_ram" \
    "../new_mem_blocks.sv" \
    "tb_voxel_ram.sv"

# Add more tests as they are created:
# run_test "voxel_addr_map" \
#     "../new_mem_blocks.sv" \
#     "tb_voxel_addr_map.sv"

# run_test "scene_loader_if" \
#     "../new_mem_blocks.sv" \
#     "tb_scene_loader_if.sv"

# Final summary
echo "========================================"
echo "VERIFICATION SUMMARY"
echo "========================================"
echo "Seed used: $SEED"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo "========================================"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}ALL VERIFICATIONS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}SOME VERIFICATIONS FAILED!${NC}"
    exit 1
fi
