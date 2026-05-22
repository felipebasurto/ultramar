.PHONY: bootstrap build test test-run test-integration test-all clean generate cli-build cli qwen-server chat batch FORCE

PROJECT := UltramarAI
XCPROJECT := $(PROJECT).xcodeproj
SCHEME := UltramarAI
DEFAULT_SIMULATOR := iPhone 17
SIMULATOR ?= $(shell python3 Scripts/detect_simulator.py "$(DEFAULT_SIMULATOR)")

BOOTSTRAP := bootstrap
BUILD_DIR := .build
DERIVED_DATA := $(BUILD_DIR)/DerivedData

bootstrap: generate
	@echo "Bootstrap complete (Xcode project generated)."

generate:
	python3 Scripts/generate_xcode_project.py

build: generate
	xcodebuild \
		-project $(XCPROJECT) \
		-scheme $(SCHEME) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR)" \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet \
		build

test:
	@echo "Tests skipped (manual only)."
	@echo "  make test-run          unit tests (fast, no GPU, no network)"
	@echo "  make test-integration  Qwen GGUF inference (needs local model)"
	@echo "  make test-all          unit + network + integration"

test-run:
	@set -e; \
	for pkg in Packages/*/; do \
		echo "==> swift test in $$pkg"; \
		( cd "$$pkg" && swift test ); \
	done

test-integration:
	@set -e; \
	export ULTRAMAR_INTEGRATION_TESTS=1; \
	for pkg in Packages/*/; do \
		echo "==> swift test (integration) in $$pkg"; \
		( cd "$$pkg" && swift test ); \
	done

test-all:
	@set -e; \
	export ULTRAMAR_INTEGRATION_TESTS=1 ULTRAMAR_NETWORK_TESTS=1; \
	for pkg in Packages/*/; do \
		echo "==> swift test (all) in $$pkg"; \
		( cd "$$pkg" && swift test ); \
	done

CLI := Packages/UltramarCLI/.build/release/ultramar
ENGINE ?= qwen
PROMPT ?=
PROMPTS_FILE ?=
FORMAT ?= json
BASE_URL ?= http://127.0.0.1:8080/v1
QWEN_MODEL ?= $(HOME)/Library/Application Support/UltramarAI/models/Qwen.Qwen3.5-4B.Q4_K_M.gguf

$(CLI): FORCE
	cd Packages/UltramarCLI && swift build -c release

cli-build: $(CLI)
	@mkdir -p bin
	@ln -sf ../$(CLI) bin/ultramar

cli: cli-build
	@$(CLI) $(ARGS)

# Foreground local server: load Qwen once, then serve OpenAI-compatible chat completions.
qwen-server:
	@command -v llama-server >/dev/null || (echo "llama-server not found. Install llama.cpp and ensure llama-server is on PATH." >&2; exit 1)
	@if curl -fsS "$(BASE_URL)/models" >/dev/null 2>&1; then \
		echo "llama-server already responds at $(BASE_URL)"; \
	else \
		test -f "$(QWEN_MODEL)" || (echo "Qwen GGUF not found: $(QWEN_MODEL)" >&2; echo "Run: ultramar models download --engine qwen" >&2; exit 1); \
		GGML_LOG_LEVEL=error llama-server \
			-m "$(QWEN_MODEL)" \
			--host 127.0.0.1 \
			--port 8080 \
			--ctx-size 4096 \
			--temp 0.7 \
			--top-p 0.8 \
			--top-k 20 \
			--presence-penalty 1.5 \
			--repeat-penalty 1.0; \
	fi

# Interactive REPL: connect to local llama-server; start `make qwen-server` first.
chat: $(CLI)
	@mkdir -p bin && ln -sf ../$(CLI) bin/ultramar
ifeq ($(PROMPT),)
	@$(CLI) chat --backend server --base-url "$(BASE_URL)" --engine $(ENGINE) --interactive
else
	@$(CLI) chat --backend server --base-url "$(BASE_URL)" --engine $(ENGINE) --prompt "$(PROMPT)"
endif

# Batch: server-backed prompts (# = comment). Ideal for 100s of test prompts.
batch: $(CLI)
	@mkdir -p bin && ln -sf ../$(CLI) bin/ultramar
	@test -n "$(PROMPTS_FILE)" || (echo "Usage: make batch PROMPTS_FILE=./prompts.txt [ENGINE=qwen] [FORMAT=json]" >&2; exit 1)
	@$(CLI) chat --backend server --base-url "$(BASE_URL)" --engine $(ENGINE) --prompts-file "$(PROMPTS_FILE)" --format $(FORMAT)

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(XCPROJECT)/project.xcworkspace/xcuserdata
	find Packages -name '.build' -type d -prune -exec rm -rf {} + 2>/dev/null || true
