.PHONY: compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_%: compile
	iverilog -o build/sim.vvp -s rt -g2012 build/rt.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp
	python -c "import xml.etree.ElementTree as E; r=E.parse('results.xml'); assert r.findall('.//testcase') and not r.findall('.//failure'), 'cocotb test failed'"

compile:
	mkdir -p build
	sv2v -w build/rt.v src/*.sv
	printf '\140timescale 1ns/1ns\n' > build/temp.v
	cat build/rt.v >> build/temp.v
	mv build/temp.v build/rt.v
