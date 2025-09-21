#!/bin/bash

# FlexGet Task Executor
# Simple menu to execute different FlexGet tasks

set -e

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="$SCRIPT_DIR/../../../docker-compose.yml"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Print header
print_header() {
  clear
  echo -e "${PURPLE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                     FLEXGET TASK EXECUTOR                    ║"
  echo "║                    Select a task to execute                  ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo
}

# Check if compose file exists
validate_environment() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "Docker compose file not found: $COMPOSE_FILE"
    log_error "Make sure you're running this from the correct location"
    exit 1
  fi

  # Check if Docker is running
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running"
    exit 1
  fi

  # Check FlexGet container
  local status
  status=$(docker compose -f "$COMPOSE_FILE" ps flexget --format "table {{.State}}" 2>/dev/null | tail -1)

  if [[ "$status" != "running" ]]; then
    log_warning "FlexGet container is not running, attempting to start..."
    if docker compose -f "$COMPOSE_FILE" start flexget >/dev/null 2>&1; then
      sleep 3
      log_success "FlexGet container started"
    else
      log_error "Failed to start FlexGet container"
      exit 1
    fi
  fi
}

# Execute FlexGet command
execute_flexget_command() {
  local task_name="$1"
  local description="$2"

  echo
  log_info "Executing: $description"
  log_info "Task: $task_name"
  echo
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

  # Execute the FlexGet command
  if docker compose -f "$COMPOSE_FILE" exec -T flexget flexget --loglevel debug execute --tasks "$task_name" --discover-now; then
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    log_success "Task '$task_name' completed successfully!"
  else
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    log_error "Task '$task_name' failed!"
    exit 1
  fi
}

# Execute movies task
execute_movies() {
  execute_flexget_command "manual_movies" "Movie Download Task"
}

# Execute TV shows task
execute_tv() {
  execute_flexget_command "manual_tv" "TV Shows Download Task"
}

# Execute anime task
execute_anime() {
  execute_flexget_command "manual_animes" "Anime Download Task"
}

execute_organize_movie() {
  execute_flexget_command "organize_movies" "Movies Organizer Task"
}

execute_organize_tv() {
  execute_flexget_command "organize_tv" "Tv Shows Organizer Task"
}

execute_organize_anime() {
  execute_flexget_command "organize_anime" "Anime Organizer Task"
}

execute_clean_completed_torrents() {
  execute_flexget_command "clean_completed_torrents" "Clean Completed Torrents Task"
}

execute_clean_stalled_torrents() {
  execute_flexget_command "clean_stalled_torrents" "Clean Stalled Torrents Task"
}

execute_purge_all_torrents() {
  execute_flexget_command "purge_all_torrents" "Purge All Torrents Task"
}

execute_purge_dead_torrents() {
  execute_flexget_command "purge_dead_torrents" "Purge Dead Torrents Task"
}

# Show menu and get selection
show_menu() {
  echo -e "${YELLOW}Select a task to execute:${NC}"
  echo
  echo -e "${CYAN}  1)${NC} Movies   - Download movies from queue"
  echo -e "${CYAN}  2)${NC} TV       - Download TV shows"
  echo -e "${CYAN}  3)${NC} Animes   - Download anime series"
  echo -e "${CYAN}  4)${NC} Organize Movies   - Organize downloaded movies into final folder"
  echo -e "${CYAN}  5)${NC} Organize TV   - Organize downloaded TV shows into final folder"
  echo -e "${CYAN}  6)${NC} Organize Anime   - Organize downloaded animes into final folder"
  echo -e "${CYAN}  7)${NC} Clean Completed Torrents   - Remove completed torrents from transmission"
  echo -e "${CYAN}  8)${NC} Clean Stalled Torrents   - Remove stalled torrents from transmission"
  echo -e "${CYAN}  9)${NC} Purge All Torrents   - Remove all torrents from transmission"
  echo -e "${CYAN}  10)${NC} Purge Dead Torrents   - Remove only dead torrents from transmission"
  echo
  echo -e "${CYAN}  11)${NC} Exit"
  echo
  echo -n -e "${YELLOW}Enter your choice [1-11]: ${NC}"
}

# Get user input with validation
get_user_choice() {
  local choice
  while true; do
    read -r choice
    case $choice in
    1)
      echo "movies"
      return 0
      ;;
    2)
      echo "tv"
      return 0
      ;;
    3)
      echo "anime"
      return 0
      ;;
    4)
      echo "organize_movies"
      return 0
      ;;
    5)
      echo "organize_tv"
      return 0
      ;;
    6)
      echo "organize_anime"
      return 0
      ;;
    7)
      echo "clean_completed_torrents"
      return 0
      ;;
    8)
      echo "clean_stalled_torrents"
      return 0
      ;;
    9)
      echo "purge_all_torrents"
      return 0
      ;;
    10)
      echo "purge_dead_torrents"
      return 0
      ;;
    11)
      echo "exit"
      return 0
      ;;
    *)
      echo -n -e "${RED}Invalid choice. Please enter 1-4: ${NC}"
      ;;
    esac
  done
}

# Confirmation prompt
confirm_execution() {
  local task_type="$1"
  local task_description

  case "$task_type" in
  movies) task_description="manual_movies" ;;
  tv) task_description="manual_tv" ;;
  anime) task_description="manual_animes" ;;
  organize_movies) task_description="organize_movies" ;;
  organize_tv) task_description="organize_tv" ;;
  organize_anime) task_description="organize_anime" ;;
  clean_completed_torrents) task_description="clean_completed_torrents" ;;
  clean_stalled_torrents) task_description="clean_stalled_torrents" ;;
  purge_all_torrents) task_description="purge_all_torrents" ;;
  purge_dead_torrents) task_description="purge_dead_torrents" ;;
  *) task_description="Selected Task" ;;
  esac

  echo
  echo -e "${YELLOW}You selected: ${CYAN}$task_description${NC}"
  echo -n -e "${YELLOW}Do you want to continue? [Y/n]: ${NC}"

  local confirm
  read -r confirm

  case "$confirm" in
  "" | y | Y | yes | Yes | YES)
    return 0
    ;;
  *)
    log_info "Operation cancelled"
    return 1
    ;;
  esac
}

# Wait for user to press enter
wait_for_enter() {
  echo
  echo -n -e "${YELLOW}Press Enter to continue...${NC}"
  read -r
}

# Main execution loop
main() {
  # Validate environment first
  validate_environment

  while true; do
    print_header
    show_menu

    local choice
    choice=$(get_user_choice)

    case "$choice" in
    "movies")
      if confirm_execution "movies"; then
        execute_movies
        wait_for_enter
      fi
      ;;
    "tv")
      if confirm_execution "tv"; then
        execute_tv
        wait_for_enter
      fi
      ;;
    "anime")
      if confirm_execution "anime"; then
        execute_anime
        wait_for_enter
      fi
      ;;
    "organize_movies")
      if confirm_execution "organize_movies"; then
        execute_organize_movie
        wait_for_enter
      fi
      ;;
    "organize_tv")
      if confirm_execution "organize_tv"; then
        execute_organize_tv
        wait_for_enter
      fi
      ;;
    "organize_anime")
      if confirm_execution "organize_anime"; then
        execute_organize_anime
        wait_for_enter
      fi
      ;;
    "clean_completed_torrents")
      if confirm_execution "clean_completed_torrents"; then
        execute_clean_completed_torrents
        wait_for_enter
      fi
      ;;
    "clean_stalled_torrents")
      if confirm_execution "clean_stalled_torrents"; then
        execute_clean_stalled_torrents
        wait_for_enter
      fi
      ;;
    "purge_all_torrents")
      if confirm_execution "purge_all_torrents"; then
        execute_purge_all_torrents
        wait_for_enter
      fi
      ;;
    "purge_dead_torrents")
      if confirm_execution "purge_dead_torrents"; then
        execute_purge_dead_torrents
        wait_for_enter
      fi
      ;;
    "exit")
      echo
      log_info "Goodbye!"
      exit 0
      ;;
    *)
      log_error "Unexpected choice: $choice"
      sleep 2
      ;;
    esac
  done
}

# Handle script arguments for non-interactive mode
if [[ $# -gt 0 ]]; then
  validate_environment

  case "$1" in
  movies | 1)
    log_info "Non-interactive mode: Executing movies task"
    execute_movies
    ;;
  tv | 2)
    log_info "Non-interactive mode: Executing TV task"
    execute_tv
    ;;
  anime | 3)
    log_info "Non-interactive mode: Executing anime task"
    execute_anime
    ;;
  organize_movies | 4)
    log_info "Non-interactive mode: Executing organize movies task"
    execute_organize_movie
    ;;
  organize_tv | 5)
    log_info "Non-interactive mode: Executing organize tv task"
    execute_organize_tv
    ;;
  organize_anime | 6)
    log_info "Non-interactive mode: Executing organize anime task"
    execute_organize_anime
    ;;
  clean_completed_torrents | 7)
    log_info "Non-interactive mode: Executing clean completed torrents task"
    execute_clean_completed_torrents
    ;;
  clean_stalled_torrents | 8)
    log_info "Non-interactive mode: Executing clean stalled torrents task"
    execute_clean_stalled_torrents
    ;;
  purge_all_torrents | 9)
    log_info "Non-interactive mode: Executing purge all torrents task"
    execute_purge_all_torrents
    ;;
  purge_dead_torretns | 10)
    log_info "Non-interactive mode: Executing purge dead torrents task"
    execute_purge_dead_torrents
    ;;
  *)
    log_error "Unknown argument: $1"
    log_info "Use --help for usage information"
    exit 1
    ;;
  esac
else
  # No arguments - run interactive mode
  main
fi
