# chilliTPU top-level Makefile.  `make help` lists the targets.

SHELL := /bin/bash

# ---------------------------------------------------------------- tools
PYTHON    ?= python3
VERILATOR ?= verilator
UVM_HOME  ?= third_party/uvm-core/src

# ---------------------------------------------------------------- testbenches
# TBS: envs in the regression (`make sim`). Add an env here once its first test passes.
TBS ?= smoke
# TB: run a single env, e.g. `make sim TB=pe`
TB  ?=
ALL_TBS := $(patsubst tb/%/files.f,%,$(wildcard tb/*/files.f))
RUN_TBS := $(if $(TB),$(TB),$(TBS))

UVM_DEFS := +define+UVM_NO_DPI +define+UVM_REPORT_DISABLE_FILE_LINE
VFLAGS   := --binary --timing --assert -j 0 -Wno-fatal -Wno-lint -Wno-style \
            $(UVM_DEFS) +incdir+$(UVM_HOME) +incdir+tb/common
# Source files listed in a files.f (comments and +options stripped), used as make dependencies
tb_srcs = $(shell sed -e 's://.*::' -e 's:\#.*::' tb/$(1)/files.f | grep -v '^+' | xargs)

# ---------------------------------------------------------------- RTL lint
RTL_PKG  := rtl/pkg/dnn_pkg.sv
RTL_SRCS := $(filter-out $(RTL_PKG),$(wildcard rtl/*.sv))
# UNUSED* waivers are only for the skeleton stubs; remove them once modules are implemented.
LINT_FLAGS ?= -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

.PHONY: help hooks vectors regs sim sim-xsim lint bitstream fw report clean

help:
	@echo "make hooks            install git hooks (blocks direct pushes to main); run once per clone"
	@echo "make vectors          generate .hex test vectors (sw/py/vecgen.py)"
	@echo "make regs             generate register files from spec/regmap.yaml"
	@echo "make sim              run the UVM regression in Verilator (envs in TBS: $(TBS))"
	@echo "make sim TB=<name>    run one env, e.g. make sim TB=smoke"
	@echo "make sim-xsim TB=<n>  run one env in xsim (Vivado PC, needs bash)"
	@echo "make lint             Verilator lint of every RTL module"
	@echo "make bitstream        (Vivado PC) vivado -mode batch -source fpga/build.tcl"
	@echo "make fw               (Vivado PC) build the Vitis app"
	@echo "make report           build tables/plots from results (sw/py/analyze.py)"
	@echo "make clean            remove build/ and vectors/"
	@echo "envs with a files.f:  $(ALL_TBS)"

hooks:
	git config core.hooksPath scripts/hooks
	@echo "git hooks installed from scripts/hooks"

vectors:
	$(PYTHON) sw/py/vecgen.py

regs:
	$(PYTHON) scripts/gen_regs.py

# ---- Verilator: one build rule per env
define TB_RULE
build/$(1)/simv: tb/$(1)/files.f $(call tb_srcs,$(1)) $(wildcard tb/common/*)
	@mkdir -p build/$(1)
	@echo "== building $(1) (UVM build takes ~45 s)"
	@$(VERILATOR) $(VFLAGS) $(UVM_HOME)/uvm_pkg.sv -f tb/$(1)/files.f \
	   --top-module tb_top -Mdir build/$(1)/obj -o ../simv > build/$(1)/build.log 2>&1 \
	   || { grep -E '%Error' build/$(1)/build.log | head -20; echo "BUILD FAILED: $(1) (see build/$(1)/build.log)"; exit 1; }
endef
$(foreach t,$(ALL_TBS),$(eval $(call TB_RULE,$(t))))

sim: $(foreach t,$(RUN_TBS),build/$(t)/simv)
	@status=0; for t in $(RUN_TBS); do scripts/run_tests.sh $$t build/$$t/simv verilator || status=1; done; \
	 if [ $$status -eq 0 ]; then echo "== SIM PASS"; else echo "== SIM FAIL"; fi; exit $$status

# ---- xsim (Vivado PC). Not yet tested: confirm in Milestone 0.
sim-xsim:
	@test -n "$(TB)" || { echo "usage: make sim-xsim TB=<name>"; exit 1; }
	@mkdir -p build/$(TB)/xsim
	cd build/$(TB)/xsim && xvlog -sv -i ../../../$(UVM_HOME) -i ../../../tb/common \
	   -d UVM_NO_DPI -d UVM_REPORT_DISABLE_FILE_LINE ../../../$(UVM_HOME)/uvm_pkg.sv \
	   $(addprefix ../../../,$(call tb_srcs,$(TB))) \
	 && xelab tb_top -s simv -timescale 1ns/1ps
	scripts/run_tests.sh $(TB) simv xsim

lint:
	@status=0; for f in $(RTL_SRCS); do \
	   $(VERILATOR) --lint-only --quiet $(LINT_FLAGS) $(RTL_PKG) $$f --top-module $$(basename $$f .sv) \
	     && echo "lint ok   $$f" || { echo "lint FAIL $$f"; status=1; }; \
	 done; exit $$status

bitstream:
	@echo "Run on the Vivado PC:  vivado -mode batch -source fpga/build.tcl"

fw:
	@echo "Run on the Vivado PC:  build fw/ in Vitis from the XSA (see fw/README.md)"

report:
	$(PYTHON) sw/py/analyze.py

clean:
	rm -rf build vectors
