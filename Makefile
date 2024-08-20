# Makefile

# Define variables
JEKYLL_BUILD_CMD = jekyll build
JEKYLL_SERVE_CMD = jekyll serve
TAGGEN_CMD = python3 taggenerator.py

# Targets
all: build

# Run taggenerator before building the site
build: taggenerator
	$(JEKYLL_BUILD_CMD)

# Run taggenerator
taggenerator:
	$(TAGGEN_CMD)

# Serve the site locally
serve: taggenerator
	$(JEKYLL_SERVE_CMD)

# Clean the generated files
clean:
	rm -rf _site

.PHONY: all build taggenerator serve clean
