#!/usr/bin/env bash
set -e

# Test runner for nvim-project-config using plenary.nvim

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLENARY_PATH="$PROJECT_ROOT/.test-agent/plenary.nvim"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_header() {
  echo -e "${GREEN}=== $1 ===${NC}"
}

function print_info() {
  echo -e "${YELLOW}INFO:${NC} $1"
}

# Check if neovim is installed
if ! command -v nvim &> /dev/null; then
  echo -e "${RED}ERROR: nvim not found. Please install Neovim first.${NC}"
  exit 1
fi

# Check if plenary.nvim exists
if [[ ! -d "$PLENARY_PATH" ]]; then
  print_info "plenary.nvim not found at $PLENARY_PATH"
  print_info "Please install plenary.nvim to .test-agent/plenary.nvim/"
  exit 1
fi

# Parse arguments
TEST_TYPE=""
TEST_PATH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --unit)
      TEST_TYPE="unit"
      shift
      ;;
    --integration)
      TEST_TYPE="integration"
      shift
      ;;
    --file)
      TEST_PATH="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --unit              Run unit tests only (default)"
      echo "  --integration       Run integration tests"
      echo "  --file <path>       Run specific test file"
      echo "  --help, -h          Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                          # Run all unit tests"
      echo "  $0 --unit                   # Run all unit tests"
      echo "  $0 --integration            # Run all integration tests"
      echo "  $0 --file test/unit/matchers_spec.lua  # Run specific test file"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Run --help for usage information"
      exit 1
      ;;
  esac
done

# Set default if no test type specified
if [[ -z "$TEST_TYPE" ]] && [[ -z "$TEST_PATH" ]]; then
  TEST_TYPE="unit"
fi

# Build test command
NVIM_CMD="nvim --headless -c 'set rtp+=$PLENARY_PATH'"

if [[ -n "$TEST_PATH" ]]; then
  # Run specific test file
  print_header "Running test file: $TEST_PATH"
  nvim --headless -c "set rtp+=$PLENARY_PATH,." -c "lua require('plenary.test_harness').test_file('$TEST_PATH')" -c 'q!'
elif [[ "$TEST_TYPE" == "unit" ]]; then
  # Run unit tests
  print_header "Running unit tests"
  nvim --headless -c "set rtp+=$PLENARY_PATH,." -c "lua require('plenary.test_harness').test_directory('test/unit')" -c 'q!'
elif [[ "$TEST_TYPE" == "integration" ]]; then
  # Run integration tests
  print_header "Running integration tests"
  nvim --headless -c "set rtp+=$PLENARY_PATH,." -c "lua require('plenary.test_harness').test_directory('test/integration')" -c 'q!'
fi

# Check exit code
if [[ $? -eq 0 ]]; then
  print_header "All tests passed!"
  exit 0
else
  echo -e "${RED}Tests failed!${NC}"
  exit 1
fi
