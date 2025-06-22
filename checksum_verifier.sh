#!/bin/bash
# SHA256 Checksum Verifier

set -euo pipefail

# --- Color Setup ---
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0)

# --- Prompt Function with Tab Completion ---
prompt_input() {
  local prompt="$1"
  local var_name="$2"
  local default="$3"
  local validation_regex="$4"
  local error_msg="$5"

  while true; do
    read -e -p "$(printf "${YELLOW}%s [%s]: ${NC}" "$prompt" "$default")" input
    input="${input:-$default}"

    if [[ "$input" =~ $validation_regex ]]; then
      if [[ "$prompt" == *"directory"* ]]; then
        eval "$var_name=\"$(realpath "$input")\""
      else
        eval "$var_name=\"$input\""
      fi
      break
    else
      printf "${RED}ERROR: %s${NC}\n" "$error_msg"
    fi
  done
}

# --- Main Script ---
printf "${GREEN}=== SHA256 Checksum Verifier ===${NC}\n"

# Operation selection
printf "\n${YELLOW}Select operation:${NC}\n"
PS3="$(printf "${YELLOW}Enter choice (1-2): ${NC}")"
select opt in "Compare two checksum files" "Generate new checksums and compare to original"; do
  case $REPLY in
    1) MODE="compare"; break ;;
    2) MODE="generate"; break ;;
    *) printf "${RED}Invalid option. Please try again.${NC}\n" ;;
  esac
done

if [[ "$MODE" == "compare" ]]; then
  # Compare two existing checksum files
  prompt_input "Enter path to original checksum file" "ORIG_FILE" "original_checksums.sha256" "^\/.+" "Path must start with /"
  prompt_input "Enter path to new checksum file" "NEW_FILE" "new_checksums.sha256" "^\/.+" "Path must start with /"
else
  # Generate new checksums and compare
  prompt_input "Enter path to original checksum file" "ORIG_FILE" "original_checksums.sha256" "^\/.+" "Path must start with /"
  prompt_input "Enter directory to scan for new checksums" "SCAN_DIR" "$PWD" "^\/.+" "Path must start with /"
  prompt_input "Enter directory to save new checksums" "SAVE_DIR" "$PWD" "^\/.+" "Path must start with /"
  
  # Generate the new checksum filename
  dir_name=$(basename "$SCAN_DIR")
  NEW_FILE="${SAVE_DIR}/${dir_name}_file_checksums.sha256"
  
  printf "\n${GREEN}Generating new checksums for ${SCAN_DIR}...${NC}\n"
  printf "${YELLOW}Saving to: ${NEW_FILE}${NC}\n"
  sha256deep -r -l "${SCAN_DIR}" > "${NEW_FILE}"
fi

# --- Comparison ---
printf "\n${GREEN}Comparing checksum files...${NC}\n"

# Compare the files and capture output
output=$(join -v1 -v2 -j1 \
    <(sort "$ORIG_FILE") \
    <(sort "$NEW_FILE") | \
    sed 's/^/Mismatch: /')

# Check if there was any output
if [[ -z "$output" ]]; then
    printf "${GREEN}\n✅ All files verified correctly! Checksums match.${NC}\n"
else
    printf "\n${RED}Found mismatches:${NC}\n"
    printf "%s\n" "$output"
    printf "${RED}\n❌ Verification failed with above mismatches${NC}\n"
fi
