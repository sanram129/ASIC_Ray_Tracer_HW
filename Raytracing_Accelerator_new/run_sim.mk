# Makefile for simulating the raytracer with Icarus Verilog
# Usage: make -f run_sim.mk

# Compiler
IVERILOG = iverilog
VVP = vvp

# Source files (in compilation order)
SRCS = axis_choose.sv \
       bounds_check.sv \
       step_update.sv \
       voxel_addr_map.sv \
       voxel_ram.sv \
       scene_loader_if.sv \
       voxel_raytracer_core.sv \
       ray_job_if.sv \
       step_control_fsm.sv \
       raytracer_top.sv \
       tb_raytracer_top.sv

# Output files
COMP_OUT = tb_raytracer_top.vvp
WAVE_OUT = dumpfile.fst

# Simulation target
.PHONY: sim
sim: $(COMP_OUT)
	@echo "Running simulation..."
	$(VVP) $(COMP_OUT)
	@echo "Simulation complete!"

# Compilation target
$(COMP_OUT): $(SRCS)
	@echo "Compiling with Icarus Verilog..."
	$(IVERILOG) -g2012 -o $(COMP_OUT) $(SRCS)
	@echo "Compilation successful!"

# Clean target
.PHONY: clean
clean:
	rm -f $(COMP_OUT) $(WAVE_OUT)
	@echo "Cleaned build artifacts"

# View waveforms (if GTKWave is installed)
.PHONY: waves
waves:
	@if [ -f $(WAVE_OUT) ]; then \
		gtkwave $(WAVE_OUT); \
	else \
		echo "No waveform file found. Run 'make sim' first."; \
	fi
