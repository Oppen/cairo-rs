.PHONY: deps build run check test clippy coverage benchmark flamegraph \
	compare_benchmarks_deps compare_benchmarks docs clean \
	compare_vm_output compare_trace_memory compare_trace compare_memory \
	compare_trace_memory_proof compare_trace_proof compare_memory_proof \
	cairo_bench_programs cairo_proof_programs cairo_test_programs \
	cairo_trace cairo-rs_trace

# ===================
# Run with proof mode
# ===================

TEST_PROOF_DIR=cairo_programs/proof_programs
TEST_PROOF_FILES:=$(wildcard $(TEST_PROOF_DIR)/*.cairo)
COMPILED_PROOF_TESTS:=$(patsubst $(TEST_PROOF_DIR)/%.cairo, $(TEST_PROOF_DIR)/%.json, $(TEST_PROOF_FILES))
CAIRO_MEM_PROOF:=$(patsubst $(TEST_PROOF_DIR)/%.json, $(TEST_PROOF_DIR)/%.memory, $(COMPILED_PROOF_TESTS))
CAIRO_TRACE_PROOF:=$(patsubst $(TEST_PROOF_DIR)/%.json, $(TEST_PROOF_DIR)/%.trace, $(COMPILED_PROOF_TESTS))
CAIRO_RS_MEM_PROOF:=$(patsubst $(TEST_PROOF_DIR)/%.json, $(TEST_PROOF_DIR)/%.rs.memory, $(COMPILED_PROOF_TESTS))
CAIRO_RS_TRACE_PROOF:=$(patsubst $(TEST_PROOF_DIR)/%.json, $(TEST_PROOF_DIR)/%.rs.trace, $(COMPILED_PROOF_TESTS))

PROOF_BENCH_DIR=cairo_programs/benchmarks
PROOF_BENCH_FILES:=$(wildcard $(PROOF_BENCH_DIR)/*.cairo)
PROOF_COMPILED_BENCHES:=$(patsubst $(PROOF_BENCH_DIR)/%.cairo, $(PROOF_BENCH_DIR)/%.json, $(PROOF_BENCH_FILES))

$(TEST_PROOF_DIR)/%.json: $(TEST_PROOF_DIR)/%.cairo
	cairo-compile --cairo_path="$(TEST_PROOF_DIR):$(PROOF_BENCH_DIR)" $< --output $@ --proof_mode

$(TEST_PROOF_DIR)/%.rs.trace $(TEST_PROOF_DIR)/%.rs.memory: $(TEST_PROOF_DIR)/%.json build
	./target/release/cairo-rs-run --layout all --proof_mode $< --trace_file $@ --memory_file $(@D)/$(*F).rs.memory

$(TEST_PROOF_DIR)/%.trace $(TEST_PROOF_DIR)/%.memory: $(TEST_PROOF_DIR)/%.json
	cairo-run --layout all --proof_mode --program $< --trace_file $@ --memory_file $(@D)/$(*F).memory

$(PROOF_BENCH_DIR)/%.json: $(PROOF_BENCH_DIR)/%.cairo
	cairo-compile --cairo_path="$(TEST_PROOF_DIR):$(PROOF_BENCH_DIR)" $< --output $@ --proof_mode

# ======================
# Run without proof mode
# ======================

TEST_DIR=cairo_programs
TEST_FILES:=$(wildcard $(TEST_DIR)/*.cairo)
COMPILED_TESTS:=$(patsubst $(TEST_DIR)/%.cairo, $(TEST_DIR)/%.json, $(TEST_FILES))
CAIRO_MEM:=$(patsubst $(TEST_DIR)/%.json, $(TEST_DIR)/%.memory, $(COMPILED_TESTS))
CAIRO_TRACE:=$(patsubst $(TEST_DIR)/%.json, $(TEST_DIR)/%.trace, $(COMPILED_TESTS))
CAIRO_RS_MEM:=$(patsubst $(TEST_DIR)/%.json, $(TEST_DIR)/%.rs.memory, $(COMPILED_TESTS))
CAIRO_RS_TRACE:=$(patsubst $(TEST_DIR)/%.json, $(TEST_DIR)/%.rs.trace, $(COMPILED_TESTS))

BENCH_DIR=cairo_programs/benchmarks
BENCH_FILES:=$(wildcard $(BENCH_DIR)/*.cairo)
COMPILED_BENCHES:=$(patsubst $(BENCH_DIR)/%.cairo, $(BENCH_DIR)/%.json, $(BENCH_FILES))

BAD_TEST_DIR=cairo_programs/bad_programs
BAD_TEST_FILES:=$(wildcard $(BAD_TEST_DIR)/*.cairo)
COMPILED_BAD_TESTS:=$(patsubst $(BAD_TEST_DIR)/%.cairo, $(BAD_TEST_DIR)/%.json, $(BAD_TEST_FILES))

$(TEST_DIR)/%.json: $(TEST_DIR)/%.cairo
	cairo-compile --cairo_path="$(TEST_DIR):$(BENCH_DIR)" $< --output $@

$(TEST_DIR)/%.rs.trace $(TEST_DIR)/%.rs.memory: $(TEST_DIR)/%.json build
	target/release/cairo-rs-run --layout all $< --trace_file $@ --memory_file $(@D)/$(*F).rs.memory

$(TEST_DIR)/%.trace $(TEST_DIR)/%.memory: $(TEST_DIR)/%.json
	cairo-run --layout all --program $< --trace_file $@ --memory_file $(@D)/$(*F).memory

$(BENCH_DIR)/%.json: $(BENCH_DIR)/%.cairo
	cairo-compile --cairo_path="$(TEST_DIR):$(BENCH_DIR)" $< --output $@


BAD_TEST_DIR=cairo_programs/bad_programs
BAD_TEST_FILES:=$(wildcard $(BAD_TEST_DIR)/*.cairo)
COMPILED_BAD_TESTS:=$(patsubst $(BAD_TEST_DIR)/%.cairo, $(BAD_TEST_DIR)/%.json, $(BAD_TEST_FILES))


$(BAD_TEST_DIR)/%.json: $(BAD_TEST_DIR)/%.cairo
	cairo-compile $< --output $@

deps:
	cargo install --version 1.1.0 cargo-criterion
	cargo install --version 0.6.1 flamegraph
	cargo install --version 1.14.0 hyperfine
	cargo install cargo-nextest
	cargo install cargo-llvm-cov
	pyenv install pypy3.7-7.3.9
	pyenv global pypy3.7-7.3.9
	pip install cairo_lang
	pyenv install 3.7.12
	pyenv global 3.7.12
	pip install cairo_lang

build:
	cargo build --release

run:
	cargo run

check:
	cargo check

cairo_test_programs: $(COMPILED_TESTS) $(COMPILED_BAD_TESTS)
cairo_proof_programs: $(COMPILED_PROOF_TESTS)
cairo_bench_programs: $(COMPILED_BENCHES)

cairo_trace: $(CAIRO_TRACE) $(CAIRO_MEM)
cairo-rs_trace: $(CAIRO_RS_TRACE) $(CAIRO_RS_MEM)

test: $(COMPILED_PROOF_TESTS) $(COMPILED_TESTS) $(COMPILED_BAD_TESTS)
	cargo nextest

clippy:
	cargo clippy --no-deps -- -D warnings

coverage: $(COMPILED_PROOF_TESTS) $(COMPILED_TESTS) $(COMPILED_BAD_TESTS)
	cargo llvm-cov nextest --lcov --output-path target/codecov-report

benchmark: $(COMPILED_BENCHES)
	cargo criterion --bench criterion_benchmark
	@echo 'Report: target/criterion/reports/index.html'

benchmark-action: $(COMPILED_BENCHES)
	cargo bench --bench criterion_benchmark -- --output-format bencher |sed 1d | tee output.txt

iai-benchmark-action: $(COMPILED_BENCHES)
	cargo bench --bench iai_benchmark

flamegraph:
	cargo flamegraph --root --bench criterion_benchmark -- --bench

compare_benchmarks: $(COMPILED_BENCHES)
	cd bench && ./run_benchmarks.sh

compare_trace_memory: $(CAIRO_RS_TRACE) $(CAIRO_TRACE) $(CAIRO_RS_MEM) $(CAIRO_MEM)
	cd tests; ./compare_vm_state.sh trace memory

compare_trace: $(CAIRO_RS_TRACE) $(CAIRO_TRACE)
	cd tests; ./compare_vm_state.sh trace

compare_memory: $(CAIRO_RS_MEM) $(CAIRO_MEM)
	cd tests; ./compare_vm_state.sh memory

compare_trace_memory_proof: $(COMPILED_PROOF_TESTS) $(CAIRO_RS_TRACE_PROOF) $(CAIRO_TRACE_PROOF) $(CAIRO_RS_MEM_PROOF) $(CAIRO_MEM_PROOF)
	cd tests; ./compare_vm_state.sh trace memory proof_mode

compare_trace_proof: $(CAIRO_RS_TRACE_PROOF) $(CAIRO_TRACE_PROOF)
	cd tests; ./compare_vm_state.sh trace proof_mode

compare_memory_proof: $(CAIRO_RS_MEM_PROOF) $(CAIRO_MEM_PROOF)
	cd tests; ./compare_vm_state.sh memory proof_mode

docs:
	cargo doc --verbose --release --locked --no-deps

clean:
	rm -f $(TEST_DIR)/*.json
	rm -f $(TEST_DIR)/*.memory
	rm -f $(TEST_DIR)/*.trace
	rm -f $(BENCH_DIR)/*.json
	rm -f $(BAD_TEST_DIR)/*.json
	rm -f $(TEST_PROOF_DIR)/*.json
	rm -f $(TEST_PROOF_DIR)/*.memory
	rm -f $(TEST_PROOF_DIR)/*.trace

