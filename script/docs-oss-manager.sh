#!/bin/bash
# ./script/docs-oss-manager.sh upload -v 4.5.0 -f "/path/to/OCP V4.5.0.tar.gz"
# ./script/docs-oss-manager.sh list
# ./script/docs-oss-manager.sh delete -v 4.5.0   tips：暂无 delete 权限
# [arguments]
# -v, --version: version, should be join by -, like 4.4.0-bp3, or just 4.5.0
# -f, --file: local tar.gz path (relative to project root or absolute)
# -l, --list: list all available versions after operation (for upload/delete commands)

set -e

# Parse command line arguments
COMMAND=""
VERSION=""
FILE_PATH=""
LIST_AFTER_OPERATION=false

while [[ $# -gt 0 ]]; do
  case $1 in
    upload|download|delete|list)
      COMMAND="$1"
      shift
      ;;
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -f|--file)
      FILE_PATH="$2"
      shift 2
      ;;
    -l|--list)
      LIST_AFTER_OPERATION=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Validate command
if [[ -z "$COMMAND" ]] || [[ ! "$COMMAND" =~ ^(upload|download|delete|list)$ ]]; then
  echo "Usage: ./docs-oss-manager.sh <upload|download|delete|list> -v|--version <ocp-version> [-f|--file <file-path>] [-l|--list]"
  echo "Examples:"
  echo "  ./docs-oss-manager.sh upload -v 4.4.0-bp3 -f public/docs.tar.gz"
  echo "  ./docs-oss-manager.sh upload --version 4.4.0-bp3 --file public/docs.tar.gz"
  echo "  ./docs-oss-manager.sh upload -v 4.4.0-bp3 -f public/docs.tar.gz -l"
  echo "  ./docs-oss-manager.sh download -v 4.4.0"
  echo "  ./docs-oss-manager.sh delete --version 4.4.0 --list"
  echo "  ./docs-oss-manager.sh list"
  exit 1
fi

# Validate version (not required for list command)
if [[ "$COMMAND" != "list" ]] && [[ -z "$VERSION" ]]; then
  echo "Error: -v|--version parameter is required for $COMMAND command"
  echo "Usage: ./docs-oss-manager.sh <upload|download|delete|list> -v|--version <ocp-version> [-f|--file <file-path>] [-l|--list]"
  echo "Examples:"
  echo "  ./docs-oss-manager.sh upload -v 4.4.0-bp3 -f public/docs.tar.gz"
  echo "  ./docs-oss-manager.sh upload --version 4.4.0-bp3 --file public/docs.tar.gz"
  echo "  ./docs-oss-manager.sh upload -v 4.4.0-bp3 -f public/docs.tar.gz -l"
  echo "  ./docs-oss-manager.sh download -v 4.4.0"
  echo "  ./docs-oss-manager.sh delete --version 4.4.0 --list"
  echo "  ./docs-oss-manager.sh list"
  exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables from .env file
ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Export variable
    if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      export "$key"="$value"
    fi
  done < "$ENV_FILE"
fi

# Get environment variables
OSS_PATH="${ACI_VAR_OSS_PATH}"
OSS_AK="${ACI_VAR_OSS_AK}"
OSS_SK="${ACI_VAR_OSS_SK}"
OSS_ENDPOINT="${ACI_VAR_OSS_ENDPOINT}"

# Validate environment variables
MISSING_VARS=()
[[ -z "$OSS_PATH" ]] && MISSING_VARS+=("ACI_VAR_OSS_PATH")
[[ -z "$OSS_AK" ]] && MISSING_VARS+=("ACI_VAR_OSS_AK")
[[ -z "$OSS_SK" ]] && MISSING_VARS+=("ACI_VAR_OSS_SK")
[[ -z "$OSS_ENDPOINT" ]] && MISSING_VARS+=("ACI_VAR_OSS_ENDPOINT")

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  echo "Error: Missing required environment variables:"
  for var in "${MISSING_VARS[@]}"; do
    echo "  - $var"
  done
  echo ""
  echo "Please create a .env file with the required variables."
  exit 1
fi

# Define paths
REMOTE_FILE_NAME="${VERSION}.tar.gz"
OSS_REMOTE_DIR="front-dist/frontend-docs"
REMOTE_PATH="${OSS_PATH}/${OSS_REMOTE_DIR}/${REMOTE_FILE_NAME}"

# Detect OS and set ossutil binary name and download URL
detect_os() {
  local os_type=$(uname -s)
  case "$os_type" in
    Darwin*)
      OSSUTIL_BINARY="ossutilmac64"
      OSSUTIL_URL="https://gosspublic.alicdn.com/ossutil/1.7.14/ossutilmac64"
      ;;
    Linux*)
      OSSUTIL_BINARY="ossutil64"
      OSSUTIL_URL="https://gosspublic.alicdn.com/ossutil/1.7.14/ossutil64"
      ;;
    *)
      echo "Unsupported OS: $os_type"
      exit 1
      ;;
  esac
  OSSUTIL_PATH="$PROJECT_ROOT/$OSSUTIL_BINARY"
}

detect_os

# Download file via curl or wget (CI 镜像可能未预装 curl)
download_file() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --noproxy '*' "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$dest"
  else
    echo "Error: curl or wget is required to download files"
    return 1
  fi
}

# Download ossutil if not exists
download_ossutil() {
  if [[ ! -f "$OSSUTIL_PATH" ]]; then
    echo "Downloading $OSSUTIL_BINARY..."
    if ! download_file "$OSSUTIL_URL" "$OSSUTIL_PATH"; then
      echo "Failed to download $OSSUTIL_BINARY"
      exit 1
    fi
    chmod +x "$OSSUTIL_PATH"
    echo "$OSSUTIL_BINARY downloaded successfully."
  fi
}

# Validate version format
validate_version() {
  local version="$1"
  # Version should be in format: x.y.z or x.y.z-xxx (where xxx can be any string)
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9_-]+)?$ ]]; then
    echo "Error: Invalid version format: $version"
    echo "Version should be in format: x.y.z or x.y.z-xxx"
    echo "Examples: 4.4.0, 4.4.0-bp1, 4.4.0-rc1, 4.4.0-hotfix"
    return 1
  fi
  return 0
}

# Validate file name
validate_file_name() {
  local file_path="$1"
  local file_name=$(basename "$file_path")

  if [[ "$file_name" != *.tar.gz ]]; then
    echo "Error: Invalid file name: $file_name"
    echo "File name must have .tar.gz extension"
    echo "Please ensure you're uploading a valid tar.gz archive."
    return 1
  fi
  return 0
}

# Upload function
upload() {
  # Validate version format
  if ! validate_version "$VERSION"; then
    exit 1
  fi

  # Validate file parameter for upload
  if [[ -z "$FILE_PATH" ]]; then
    echo "Error: -f parameter is required for upload"
    echo "Usage: ./docs-oss-manager.sh upload -v <ocp-version> -f <file-path>"
    echo "Example: ./docs-oss-manager.sh upload -v 4.4.0-bp3 -f public/docs.tar.gz"
    exit 1
  fi

  # Convert to absolute path if relative
  if [[ "$FILE_PATH" != /* ]]; then
    LOCAL_FILE_PATH="$PROJECT_ROOT/$FILE_PATH"
  else
    LOCAL_FILE_PATH="$FILE_PATH"
  fi

  # Validate file name
  if ! validate_file_name "$LOCAL_FILE_PATH"; then
    exit 1
  fi

  echo ""
  echo "Uploading docs to OSS..."
  echo "Local file: $LOCAL_FILE_PATH"
  echo "Remote path: $REMOTE_PATH"
  echo "Version: $VERSION"
  echo ""

  if [[ ! -f "$LOCAL_FILE_PATH" ]]; then
    echo "Error: Local file not found: $LOCAL_FILE_PATH"
    exit 1
  fi

  download_ossutil

  if "$OSSUTIL_PATH" cp -f "$LOCAL_FILE_PATH" "$REMOTE_PATH" \
    --meta x-oss-object-acl:public-read \
    --access-key-id="$OSS_AK" \
    --access-key-secret="$OSS_SK" \
    --endpoint="$OSS_ENDPOINT"; then
    echo ""
    echo "✓ Upload completed successfully!"

    # List versions if requested
    if [[ "$LIST_AFTER_OPERATION" == "true" ]]; then
      echo ""
      list
    fi
  else
    echo ""
    echo "✗ Upload failed"
    exit 1
  fi
}

OSS_BASE_URL="https://obocp-release.oss-cn-hangzhou.aliyuncs.com"
DOWNLOAD_URL="${OSS_BASE_URL}/${OSS_REMOTE_DIR}/${REMOTE_FILE_NAME}"

# Delete function
delete() {
  # Validate version format
  if ! validate_version "$VERSION"; then
    exit 1
  fi

  echo ""
  echo "Deleting docs from OSS..."
  echo "Remote path: $REMOTE_PATH"
  echo "Version: $VERSION"
  echo ""

  download_ossutil

  # Confirm deletion
  echo "⚠️  WARNING: This will permanently delete the file from OSS!"
  echo "File: $REMOTE_PATH"
  read -p "Are you sure you want to continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
  fi

  if "$OSSUTIL_PATH" rm "$REMOTE_PATH" \
    --access-key-id="$OSS_AK" \
    --access-key-secret="$OSS_SK" \
    --endpoint="$OSS_ENDPOINT" \
    --force; then
    echo ""
    echo "✓ Delete completed successfully!"

    # List versions if requested
    if [[ "$LIST_AFTER_OPERATION" == "true" ]]; then
      echo ""
      list
    fi
  else
    echo ""
    echo "✗ Delete failed or file not found"
    echo "Note: This may be due to insufficient OSS permissions."
    echo "Please check your OSS access key permissions or contact administrator."
    exit 1
  fi
}

# List function
list() {
  echo ""
  echo "Listing docs from OSS..."
  echo "OSS Path: $OSS_PATH/$OSS_REMOTE_DIR/"
  echo ""

  download_ossutil

  echo "Available document versions:"
  echo "=========================="

  # List files in the docs directory
  if "$OSSUTIL_PATH" ls "$OSS_PATH/$OSS_REMOTE_DIR/" \
    --access-key-id="$OSS_AK" \
    --access-key-secret="$OSS_SK" \
    --endpoint="$OSS_ENDPOINT" 2>/dev/null | grep '\.tar\.gz$' | awk '{print $NF}' | sed "s|${OSS_PATH}/${OSS_REMOTE_DIR}/||"; then
    echo ""
    echo "✓ List completed successfully!"
  else
    echo ""
    echo "✗ List failed or no files found"
    exit 1
  fi
}

# Download function
download() {
  echo ""
  echo "Downloading docs from OSS..."
  echo "Remote path: $DOWNLOAD_URL"
  echo "Version: $VERSION"
  echo ""

  DOWNLOAD_PATH="$PROJECT_ROOT/public/$REMOTE_FILE_NAME"
  EXTRACT_PATH="$PROJECT_ROOT/public/docs"

  # Download from OSS
  if ! download_file "$DOWNLOAD_URL" "$DOWNLOAD_PATH"; then
    echo ""
    echo "✗ Download failed"
    exit 1
  fi
  echo ""
  echo "✓ Download completed successfully!"

  # Remove existing docs directory if exists
  if [[ -d "$EXTRACT_PATH" ]]; then
    echo "Removing existing docs directory..."
    rm -rf "$EXTRACT_PATH"
  fi

  # Extract tar.gz
  echo "Extracting archive..."
  PUBLIC_PATH="$PROJECT_ROOT/public"
  if ! tar -xzf "$DOWNLOAD_PATH" -C "$PUBLIC_PATH"; then
    echo "✗ Extraction failed"
    exit 1
  fi
  echo "✓ Extraction completed successfully!"

  # Clean up downloaded archive
  echo "Cleaning up..."
  rm -f "$DOWNLOAD_PATH"
  echo "✓ Cleanup completed!"

  echo ""
  echo "✓ All done! Docs extracted to: $EXTRACT_PATH"
}

# Execute command
case "$COMMAND" in
  upload)
    upload
    ;;
  download)
    download
    ;;
  delete)
    delete
    ;;
  list)
    list
    ;;
esac
