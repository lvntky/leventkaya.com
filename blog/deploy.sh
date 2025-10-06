#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/var/www/blog"
SITE_OUT="/var/www/leventkaya.com"

# Ruby/Bundler ortamı (rbenv kullanıyorsan .bashrc/.bash_profile'ı yükle)
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" || true

umask 002  # group write

echo "---- $(date '+%F %T') : Deploy started ----" 

cd "$WORK_DIR"

# Gem'ler (vendor/bundle içine)
bundle config set path 'vendor/bundle'
bundle install --quiet

# Jekyll build
bundle exec jekyll build -d "$SITE_OUT"

# İzinler (nginx:www-data)
chgrp -R www-data "$SITE_OUT"
find "$SITE_OUT" -type d -exec chmod 2755 {} \;
find "$SITE_OUT" -type f -exec chmod 0644 {} \;

echo "Deploy OK: $(date '+%F %T')" 
