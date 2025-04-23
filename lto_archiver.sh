#!/bin/bash
#LTO Archiver

set -euo pipefail

# --- Color Setup ---
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0)

# --- Prompt Function ---
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
printf "${GREEN}=== LTO Archive Creator ===${NC}\n"

# Get user input
prompt_input "Enter tape serial" "TAPE_SER" "None" "^[A-Za-z0-9]+$" "Letters and Numbers only"
prompt_input "Enter source directory" "SOURCE_DIR" "$HOME" "^\/.+" "Path must start with /"
prompt_input "Enter destination directory" "DEST_DIR" "/backup" "^\/.+" "Path must start with /"
prompt_input "Enter TAR filename (without .tar)" "TAR_NAME" "${TAPE_SER}_$(date +%Y-%m-%d)" "^[a-zA-Z0-9_.-]+$" "Only letters/numbers/._-"
prompt_input "Enter PAR2 redundancy %" "REDUNDANCY" "10" "^[0-9]+$" "Must be number"
prompt_input "Enter PAR2 blocks" "PAR2_BLOCKS" "2" "^[0-9]+$" "Must be number"

# --- Confirmation ---
printf "\n${YELLOW}=== Settings Summary ===${NC}\n"
printf "Tape Serial: %s\n" "$TAPE_SER"
printf "Source:      %s\n" "$SOURCE_DIR"
printf "Destination: %s\n" "$DEST_DIR"
printf "TAR File:    %s.tar\n" "$TAR_NAME"
printf "PAR2:        %s%% redundancy, %s blocks\n\n" "$REDUNDANCY" "$PAR2_BLOCKS"

while true; do
  read -p "$(printf "${YELLOW}Proceed with archiving? (y/n): ${NC}")" confirm
  case "$confirm" in
    [Yy]* ) break;;
    [Nn]* ) exit 0;;
    * ) printf "${RED}Please answer y or n.${NC}\n";;
  esac
done

# --- Archive Creation ---
echo -e "\n${GREEN}[1/5] Generating file list...${NC}"
find "$SOURCE_DIR" -type f > "${DEST_DIR}/${TAR_NAME}_file_list.txt"

echo -e "${GREEN}[2/5] Generating file checksums...${NC}"
sha256deep -r -l "${SOURCE_DIR}" > "${DEST_DIR}/${TAR_NAME}_file_checksums.sha256"

echo -e "${GREEN}[3/5] Creating TAR archive...${NC}"
tar -cf "${DEST_DIR}/${TAR_NAME}.tar" -C "${SOURCE_DIR}" .

echo -e "${GREEN}[4/5] Generating PAR2 recovery...${NC}"
(
  cd "${DEST_DIR}"
  par2create -q -r"${REDUNDANCY}" -n"${PAR2_BLOCKS}" "${TAR_NAME}.tar"
)

# --- FIXED Verification Step ---
echo -e "${GREEN}[5/5] Verifying archive...${NC}"
(
  cd "${DEST_DIR}"

  # 1. Verify TAR checksum (newly generated)
  echo "  - Generating TAR checksum..."
  sha256sum "${DEST_DIR}/${TAR_NAME}.tar" > "${DEST_DIR}/${TAR_NAME}.tar.sha256"

  # 2. Verify internal file checksums
  echo "  - Verifying internal files..."
  if ! sha256sum -c "${TAR_NAME}.tar.sha256"; then
    echo -e "${RED}ERROR: File checksum verification failed!${NC}"
    exit 1
  fi

  # 3. Verify PAR2
  echo "  - Verifying PAR2..."
  if ! par2verify -q "${TAR_NAME}.tar.par2"; then
    echo -e "${RED}ERROR: PAR2 verification failed!${NC}"
    exit 1
  fi
)

echo -e "${GREEN}\n✅ Verification passed! Archive is valid.${NC}"
echo -e "TAR:   ${DEST_DIR}/${TAR_NAME}.tar"
echo -e "PAR2:  ${DEST_DIR}/${TAR_NAME}.tar.par2"
