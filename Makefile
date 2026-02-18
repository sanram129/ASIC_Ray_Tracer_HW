# Cocotb Makefile for Raytracing Accelerator Testbench

# Simulator selection (icarus is default, you can use verilator or others)
SIM ?= icarus

# Top-level module for simulation
TOPLEVEL_LANG ?= verilog
TOPLEVEL = tb_raytracer_cocotb

# SystemVerilog source files
VERILOG_SOURCES = $(PWD)/ray_job_if.sv \
                  $(PWD)/new_mem_blocks.sv \
                  $(PWD)/tb_raytracer_cocotb.sv

# Python testbench module
MODULE = test_raytracer

# Compile arguments
COMPILE_ARGS += -g2012  # SystemVerilog support

# Simulation arguments
SIM_ARGS += 

# Optional: Pass file paths via environment variables
# These can be overridden on command line: make VOXEL_FILE=my_voxels.txt
export VOXEL_FILE ?= voxels_load.txt
export RAY_FILE ?= ray_jobs.txt
export STL_FILE ?=
export MAX_JOBS ?= 50

# Cocotb configuration
COCOTB_REDUCED_LOG_FMT = True
COCOTB_LOG_LEVEL ?= INFO

# Waveform dumping (optional)
# For Icarus Verilog, waveforms are generated via $dumpfile/$dumpvars in TB
WAVES ?= 1

# Include cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim

# Help target
.PHONY: help
help:
	@echo "Cocotb Makefile for Raytracing Accelerator"
	@echo ""
	@echo "Usage:"
	@echo "  make                    - Run all tests with default simulator (icarus)"
	@echo "  make SIM=verilator      - Run with Verilator simulator"
	@echo "  make WAVES=1            - Enable waveform generation"
	@echo "  make TESTCASE=test_name - Run specific test"
	@echo ""
	@echo "Environment variables:"
	@echo "  VOXEL_FILE=<path>       - Path to voxels file (default: voxels_load.txt)"
	@echo "  RAY_FILE=<path>         - Path to ray jobs file (default: ray_jobs.txt)"
	@echo "  STL_FILE=<path>         - Path to STL file for end-to-end tests"
	@echo "  MAX_JOBS=<num>          - Max ray jobs to test (default: 50)"
	@echo "  COCOTB_LOG_LEVEL=<lvl>  - Set log level (DEBUG, INFO, WARNING, ERROR)"
	@echo ""
	@echo "Examples:"
	@echo "  make VOXEL_FILE=out/voxels_load.txt RAY_FILE=out/ray_jobs.txt"
	@echo "  make TESTCASE=test_single_ray_job"
	@echo "  make SIM=verilator WAVES=1"
	@echo ""
	@echo "Available tests:"
	@echo "  test_voxel_loading_from_file    - Test loading voxels from file"
	@echo "  test_voxel_loading_from_array   - Test loading voxels from numpy array"
	@echo "  test_ray_job_feeding_from_file  - Test feeding ray jobs from file"
	@echo "  test_single_ray_job             - Test sending a single ray job"
	@echo "  test_full_integration           - Full integration test"
	@echo ""
	@echo "End-to-end tests (complete workflow):"
	@echo "  test_e2e                        - Complete workflow with pre-generated data"
	@echo "  test_e2e_with_stl               - Run stl_to_voxels.py + rays_to_scene.py + test"
	@echo "  test_all_e2e                    - Run all end-to-end tests"
	@echo ""
	@echo "End-to-end test with STL file:"
	@echo "  make test_e2e_with_stl STL_FILE=model.stl"

# Clean up generated files
.PHONY: clean_all
clean_all: clean
	rm -rf __pycache__
	rm -rf .pytest_cache
	rm -f *.fst *.vcd *.ghw
	rm -f results.xml
	rm -f *.log

# Run specific test
.PHONY: test_voxels
test_voxels:
	$(MAKE) TESTCASE=test_voxel_loading_from_file

.PHONY: test_rays
test_rays:
	$(MAKE) TESTCASE=test_ray_job_feeding_from_file

.PHONY: test_single
test_single:
	$(MAKE) TESTCASE=test_single_ray_job

.PHONY: test_integration
test_integration:
	$(MAKE) TESTCASE=test_full_integration

# End-to-end tests (with Python data generation)
.PHONY: test_e2e
test_e2e:
	$(MAKE) MODULE=test_end_to_end TESTCASE=test_complete_workflow_from_generated_data

.PHONY: test_e2e_with_stl
test_e2e_with_stl:
	$(MAKE) MODULE=test_end_to_end TESTCASE=test_end_to_end_with_python_scripts

.PHONY: test_all_e2e
test_all_e2e:
	$(MAKE) MODULE=test_end_to_end
