.PHONY: help build-swift run-swift clean-swift build-rust run-rust clean-rust build-all run-swift-only run-rust-only clean-all

# Default target
help:
	@echo "Black Hole Simulation - Build & Run Targets"
	@echo ""
	@echo "Swift + Metal (macOS):"
	@echo "  make build-swift    - Build Swift/Metal version"
	@echo "  make run-swift      - Build and run Swift/Metal version"
	@echo "  make clean-swift    - Clean Swift build artifacts"
	@echo ""
	@echo "Rust + wgpu (cross-platform):"
	@echo "  make build-rust     - Build Rust/wgpu version"
	@echo "  make run-rust       - Build and run Rust/wgpu version"
	@echo "  make clean-rust     - Clean Rust build artifacts"
	@echo ""
	@echo "Combined:"
	@echo "  make build-all      - Build both versions"
	@echo "  make clean-all      - Clean both versions"

# Swift + Metal targets
build-swift:
	@echo "Building Swift + Metal version..."
	cd blackHoleMetal && swift build

run-swift: build-swift
	@echo "Running Swift + Metal version..."
	cd blackHoleMetal && swift run

clean-swift:
	@echo "Cleaning Swift build artifacts..."
	cd blackHoleMetal && swift package clean

# Rust + wgpu targets
build-rust:
	@echo "Building Rust + wgpu version..."
	cd blackHoleRs && cargo build --release

run-rust:
	@echo "Running Rust + wgpu version..."
	cd blackHoleRs && cargo run --release

clean-rust:
	@echo "Cleaning Rust build artifacts..."
	cd blackHoleRs && cargo clean

# Combined targets
build-all: build-swift build-rust

clean-all: clean-swift clean-rust
