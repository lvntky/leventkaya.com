SHELL := /bin/bash

# --- Paths ---
SITE_DIR   := blog
BUILD_DIR  := $(SITE_DIR)/_site
PORT       := 4000

# --- Defaults for rsync (override via env) ---
RSYNC_OPTS ?= -avz --delete

.PHONY: help install clean build serve check deploy-gh deploy-rsync

help:
	@echo "make install       # bundle install in $(SITE_DIR)"
	@echo "make clean         # remove $(BUILD_DIR) and cache"
	@echo "make build         # build Jekyll site from $(SITE_DIR) -> $(BUILD_DIR)"
	@echo "make serve         # serve from $(SITE_DIR) on :$(PORT)"
	@echo "make deploy-gh     # push-to-deploy (handled by GitHub Actions)"
	@echo "make deploy-rsync  # rsync $(BUILD_DIR) to RSYNC_DEST (set env)"

install:
	cd $(SITE_DIR) && bundle install

clean:
	rm -rf $(BUILD_DIR) $(SITE_DIR)/.jekyll-cache

build: install
	cd $(SITE_DIR) && bundle exec jekyll build --source . --destination _site --trace

serve: install
	cd $(SITE_DIR) && bundle exec jekyll serve --livereload --port $(PORT)

check: build
	@echo "Tip: add 'html-proofer' to $(SITE_DIR)/Gemfile for full checks."

deploy-gh:
	@echo "Push to main; GitHub Actions will build & deploy from $(SITE_DIR)."

deploy-rsync: build
	@if [ -z "$$RSYNC_DEST" ]; then echo "Set RSYNC_DEST=user@host:/path (e.g. /var/www/leventkaya.com)"; exit 1; fi
	rsync $(RSYNC_OPTS) $(BUILD_DIR)/ $$RSYNC_DEST
