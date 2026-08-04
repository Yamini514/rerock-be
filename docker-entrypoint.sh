#!/bin/sh
set -e

bundle exec rake db:migrate

exec "$@"
