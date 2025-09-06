#!/bin/bash

# Simple FlexGet Movie Manager
# Simplified version without complex path detection

set -e # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find docker-compose.yml
find_compose_file() {
  local locations=(
    "$SCRIPT_DIR/../../../docker-compose.yml"
    "$SCRIPT_DIR/../../docker-compose.yml"
    "$SCRIPT_DIR/../docker-compose.yml"
    "$SCRIPT_DIR/docker-compose.yml"
  )

  for location in "${locations[@]}"; do
    if [[ -f "$location" ]]; then
      echo "$location"
      return 0
    fi
  done

  return 1
}

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Main function to add movie
add_movie() {
  local movie_title="$1"
  local imdb_id="${2:-}"

  # Find compose file
  local compose_file
  if ! compose_file=$(find_compose_file); then
    log_error "Could not find docker-compose.yml file"
    log_info "Looking in these locations:"
    log_info "  - $SCRIPT_DIR/../../../docker-compose.yml"
    log_info "  - $SCRIPT_DIR/../../docker-compose.yml"
    log_info "  - $SCRIPT_DIR/../docker-compose.yml"
    log_info "  - $SCRIPT_DIR/docker-compose.yml"
    return 1
  fi

  log_info "Using compose file: $compose_file"
  log_info "Adding movie: '$movie_title'"

  # Check if Docker is running
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    return 1
  fi

  # Check FlexGet container status
  local status
  status=$(docker compose -f "$compose_file" ps flexget --format "table {{.State}}" 2>/dev/null | tail -1)

  if [[ "$status" != "running" ]]; then
    log_warning "FlexGet container is not running, attempting to start..."
    if ! docker compose -f "$compose_file" start flexget >/dev/null 2>&1; then
      log_error "Failed to start FlexGet container"
      return 1
    fi
    sleep 3
    log_success "FlexGet container started"
  fi

  local success=false

  if [[ -n "$imdb_id" ]]; then
    log_info "Trying to add with IMDb ID: $imdb_id"
    if docker compose -f "$compose_file" exec -T flexget flexget movie-list add manual_movies imdb_id="$imdb_id" >/dev/null 2>&1; then
      success=true
    fi
  else
    log_info "Trying add movie"
    if docker compose -f "$compose_file" exec -T flexget bash -c "flexget movie-list add manual_movies '$movie_title'" >/dev/null 2>&1; then
      success=true
    fi
  fi

  # Check if it was actually added
  sleep 1
  local after_count
  after_count=$(docker compose -f "$compose_file" exec -T flexget flexget movie-list list manual_movies 2>/dev/null | grep -c "│" || echo "0")

  if [[ "$success" == "true" ]]; then
    log_success "Movie '$movie_title' added successfully!"

    # Show current list
    echo
    log_info "Current movie list:"
    docker compose -f "$compose_file" exec -T flexget flexget movie-list list manual_movies 2>/dev/null
  else
    log_error "Failed to add movie '$movie_title'"
    log_info "Run './debug_flexget.sh' for detailed troubleshooting"
    return 1
  fi
}

# Show help
show_help() {
  cat <<EOF
${BLUE}FlexGet Movie Manager (Simple Version)${NC}

${YELLOW}USAGE:${NC}
  $0 "MOVIE_TITLE" [IMDB_ID]

${YELLOW}EXAMPLES:${NC}
  $0 "The Matrix"
  $0 "Inception" "tt1375666"

${YELLOW}OPTIONS:${NC}
  -h, --help    Show this help
  -s, --status  Show FlexGet status

Script location: $SCRIPT_DIR
EOF
}

# Show status
show_status() {
  local compose_file
  if ! compose_file=$(find_compose_file); then
    log_error "Could not find docker-compose.yml file"
    return 1
  fi

  log_info "Using compose file: $compose_file"

  local status
  status=$(docker compose -f "$compose_file" ps flexget --format "table {{.State}}" 2>/dev/null | tail -1)
  echo "FlexGet Status: $status"

  if [[ "$status" == "running" ]]; then
    echo
    echo "Current movies:"
    docker compose -f "$compose_file" exec -T flexget flexget movie-list list manual_movies 2>/dev/null |
      grep -E "^\s*│" | head -10
  fi
}

# Main execution
case "${1:-}" in
-h | --help)
  show_help
  exit 0
  ;;
-s | --status)
  show_status
  exit 0
  ;;
"")
  log_error "Movie title is required"
  show_help
  exit 1
  ;;
*)
  add_movie "$@"
  ;;
esac
