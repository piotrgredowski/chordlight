PLUGIN_ID := $(shell jq -er '.id' manifest.json)
PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
REPO_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PLUGIN_REPOSITORY := https://github.com/zaremb/chordlight.git

.PHONY: reload

# Sync this checkout into the Git-managed Omarchy install, then rescan plugins.
reload:
	@test -d "$(PLUGIN_DIR)" && test ! -L "$(PLUGIN_DIR)" || { \
		echo "Chordlight is not installed at $(PLUGIN_DIR)."; \
		exit 1; \
	}
	@test "$$(jq -er '.id' "$(PLUGIN_DIR)/manifest.json")" = "$(PLUGIN_ID)" || { \
		echo "The installed plugin ID does not match $(PLUGIN_ID)."; \
		exit 1; \
	}
	@test "$$(git -C "$(PLUGIN_DIR)" config --get remote.origin.url)" = "$(PLUGIN_REPOSITORY)" || { \
		echo "The installed plugin is not linked to $(PLUGIN_REPOSITORY)."; \
		exit 1; \
	}
	@rsync -a --delete --exclude='/.git/' --exclude='/Makefile' "$(REPO_DIR)/" "$(PLUGIN_DIR)/"
	@omarchy-shell shell rescanPlugins
