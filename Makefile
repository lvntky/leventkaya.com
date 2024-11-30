# Makefile

# Define variables
JEKYLL_BUILD_CMD = bundle exec jekyll build
JEKYLL_SERVE_CMD = bundle exec jekyll serve
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

# Ensure gems are installed before building or serving
check_dependencies:
	bundle install

# Composite target for building with dependency check
build_with_dependencies: check_dependencies build

# Composite target for serving with dependency check
serve_with_dependencies: check_dependencies serve

.PHONY: all build taggenerator serve clean check_dependencies build_with_dependencies serve_with_dependencies
