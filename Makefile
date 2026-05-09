.PHONY: test test-unit test-integration

LUA_PATH_EXTRA := ./lua/?.lua;./lua/?/init.lua;./tests/?.lua;./tests/?/init.lua

test: test-unit test-integration

test-unit:
	@export LUA_PATH="$(LUA_PATH_EXTRA);$$LUA_PATH"; \
	TEST_FILES=$$(find tests/unit -type f -name "*_spec.lua" | sort); \
	if [ -n "$$TEST_FILES" ]; then \
		busted -v $$TEST_FILES; \
	else \
		echo "No test files in tests/unit (expected during Phase 0)"; \
	fi

test-integration:
	@export LUA_PATH="$(LUA_PATH_EXTRA);$$LUA_PATH"; \
	TEST_FILES=$$(find tests/integration -type f -name "*_spec.lua" | sort); \
	if [ -n "$$TEST_FILES" ]; then \
		busted -v $$TEST_FILES; \
	else \
		echo "No test files in tests/integration (expected during Phase 0)"; \
	fi
