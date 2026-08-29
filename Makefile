SHELL := /bin/sh
CC ?= cc
TOUCH_DIR := touchscreen-control-center
BUILD_DIR := build
UNAME_S := $(shell uname -s)
TOUCH_LIBS := -pthread
TOUCH_LDFLAGS :=
ifeq ($(UNAME_S),Linux)
TOUCH_LIBS += -ldl
TOUCH_LDFLAGS += -Wl,-soname,touchui-hook.so
endif

.PHONY: check shell-check shellcheck node-check touchui-check clean

check: shell-check shellcheck node-check touchui-check

shell-check:
	@find mihomo-manager mihomo-netns touchscreen-control-center -type f \
		\( -name '*.sh' -o -name '*.init' -o -name '*.api' \) \
		-exec sh -n {} \;

shellcheck:
	@command -v shellcheck >/dev/null
	@find mihomo-manager mihomo-netns touchscreen-control-center -type f \
		\( -name '*.sh' -o -name '*.init' -o -name '*.api' \) \
		-print0 | xargs -0 shellcheck -S warning

node-check:
	@node --check mihomo-manager/patch-webui.mjs
	@node --test mihomo-manager/tests/*.test.mjs

touchui-check:
	@mkdir -p $(BUILD_DIR)
	$(CC) -shared -fPIC -Os -Wall -Wextra -Werror \
		$(TOUCH_LDFLAGS) \
		-o $(BUILD_DIR)/touchui-hook.so $(TOUCH_DIR)/touchui-hook.c $(TOUCH_LIBS)

clean:
	@find $(BUILD_DIR) -type f -delete 2>/dev/null || true
