#!/bin/bash
#LTO Archiver with optional GPG encryption

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

# --- Password Prompt Function ---
prompt_password() {
  local prompt="$1"
  local var_name="$2"
  
  while true; do
    read -s -p "$(printf "${YELLOW}%s: ${NC}" "$prompt")" password1
    echo
    read -s -p "$(printf "${YELLOW}%s (confirm): ${NC}" "$prompt")" password2
    echo
    
    if [ "$password1" = "$password2" ]; then
      if [ -z "$password1" ]; then
        printf "${RED}ERROR: Password cannot be empty${NC}\n"
      else
        eval "$var_name=\"$password1\""
        break
      fi
    else
      printf "${RED}ERROR: Passwords do not match${NC}\n"
    fi
  done
}

# --- Main Script ---
printf "${GREEN}=== LTO Archive Creator ===${NC}\n"

# Get user input
# Ask about encryption
USE_ENCRYPTION="n"
while true; do
  read -p "$(printf "${YELLOW}Enable GPG encryption? (y/n): ${NC}")" confirm
  case "$confirm" in
    [Yy]* ) USE_ENCRYPTION="y"; break;;
    [Nn]* ) break;;
    * ) printf "${RED}Please answer y or n.${NC}\n";;
  esac
done

if [ "$USE_ENCRYPTION" = "y" ]; then
  prompt_password "Enter encryption password" "GPG_PASSWORD"
fi

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
if [ "$USE_ENCRYPTION" = "y" ]; then
  printf "GPG File:    %s.tar.gpg\n" "$TAR_NAME"
fi
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

if [ "$USE_ENCRYPTION" = "y" ]; then
  echo -e "${GREEN}[3.5/5] Encrypting TAR archive with GPG...${NC}"
  gpg --batch --passphrase "$GPG_PASSWORD" --cipher-algo AES256 --symmetric --output "${DEST_DIR}/${TAR_NAME}.tar.gpg" "${DEST_DIR}/${TAR_NAME}.tar"
  VERIFY_TARGET="${TAR_NAME}.tar.gpg"
else
  VERIFY_TARGET="${TAR_NAME}.tar"
fi

echo -e "${GREEN}[4/5] Generating PAR2 recovery...${NC}"
(
  cd "${DEST_DIR}"
  par2create -q -r"${REDUNDANCY}" -n"${PAR2_BLOCKS}" "$VERIFY_TARGET"
)

# --- Verification Step ---
echo -e "${GREEN}[5/5] Verifying archive...${NC}"
(
  cd "${DEST_DIR}"

  # 1. Verify TAR/GPG checksum (newly generated)
  echo "  - Generating checksum..."
  sha256sum "$VERIFY_TARGET" > "$VERIFY_TARGET.sha256"
  sed -i 's|^\([0-9a-f]\{64\}\)  .*/|\1  |' "$VERIFY_TARGET.sha256"

  # 2. Verify checksum
  echo "  - Verifying checksum..."
  if ! sha256sum -c "$VERIFY_TARGET.sha256"; then
    echo -e "${RED}ERROR: File checksum verification failed!${NC}"
    exit 1
  fi

  # 3. Verify PAR2
  echo "  - Verifying PAR2..."
  if ! par2verify -q "$VERIFY_TARGET.par2"; then
    echo -e "${RED}ERROR: PAR2 verification failed!${NC}"
    exit 1
  fi

  # If encrypted, verify we can decrypt
  if [ "$USE_ENCRYPTION" = "y" ]; then
    echo "  - Testing decryption..."
    if ! gpg --batch --passphrase "$GPG_PASSWORD" --decrypt "$VERIFY_TARGET" > /dev/null; then
      echo -e "${RED}ERROR: GPG decryption test failed!${NC}"
      exit 1
    fi
  fi
)

echo -e "${GREEN}\n✅ Verification passed! Archive is valid.${NC}"
if [ "$USE_ENCRYPTION" = "y" ]; then
  echo -e "GPG:   ${DEST_DIR}/${TAR_NAME}.tar.gpg"
else
  echo -e "TAR:   ${DEST_DIR}/${TAR_NAME}.tar"
fi
echo -e "PAR2:  ${DEST_DIR}/${TAR_NAME}.tar$( [ "$USE_ENCRYPTION" = "y" ] && echo ".gpg" ).par2"