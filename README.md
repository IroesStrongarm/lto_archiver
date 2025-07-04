# lto_archiver
The purpose of this script is to prepare a directory for transfer to a long term archival medium.  In this case LTO tape, but it could be used for anything.

The script performs the following tasks:
1. Creates a text file containing the path and names of all files in the directory and subdirectories.
2. Creates a sha256 file for every file in the directory and subdirectories.
3. Creates a tar file of the directory.
4. Creates par2 files of that tar file.
5. Creates a sha256 file of the tar file.
6. Verifies the checksum of the tar file and its sha256 file as well as veriies the par2 files.

When first run it will prompt the user for information such as source and destination locations, as well as how much redundancy is desired.

This script relies on having `hashdeep` and `par2` installed.

# lto_archiver_encrypt
Added an optional prompt if encryption is desired.  If 'y' prompts for password and generates an additional .tar.gpg archive along with associated checksum.

# checksum_verifier
This script is useful for confirming that all the files in your restored archive match the original checksums.  You are given the option to either compare two checksum files against each other, or generate the checksum file on a given directly and then compare to the original.
