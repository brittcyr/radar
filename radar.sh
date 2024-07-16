#!/bin/bash
set -e

usage() {
    echo "Usage: $0 [-p <path> [-s <source_directory_or_file>] [-t <templates_directory>]] [-d]"
    echo "Options:"
    echo "  -p, --path       Path to the contract on the host."
    echo "  -s, --source     Specific source within the contract path (optional) (default - project root)."
    echo "  -t, --templates  Path to the templates directory (optional) (default - builtin_templates folder)."
    echo "  -d, --down       Shut down radar containers."
    echo "  -h, --help       Help message."
    exit 1
}

check_docker() {
    local timeout_duration=5

    docker compose version &> /dev/null &
    pid=$!

    ( sleep $timeout_duration && kill -0 "$pid" 2>/dev/null && kill -9 "$pid" && echo "[w] Docker availability check timed out." && exit 1 ) &

    wait $pid
    local status=$?

    if [ $status -ne 0 ]; then
        echo "[e] Docker is not available. Please ensure Docker is installed and running. If further problems arise consider restarting the Docker service."
        exit 1
    fi
}

adjust_source_path_for_docker() {
    local base=$1
    local target=$2

    local resolved_base=$(cd "$base" && pwd)
    local resolved_target=$(cd "$(dirname "$base/$target")" && pwd)/$(basename "$target")

    if [[ "$resolved_target" == "$resolved_base"* ]]; then
        local rel_path="${resolved_target#$resolved_base/}"
        echo "$rel_path"
    else
        echo "$target"
    fi
}

source_directory_or_file=""
shutdown_containers=false
path=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--path) path=$(realpath "$2"); shift ;;
        -s|--source) source_directory_or_file=$(adjust_source_path_for_docker "$path" "$2"); shift ;;
        -t|--templates) templates_directory=$(realpath "$2"); shift ;;
        -d|--down) shutdown_containers=true ;;
        -h|--help) usage ;;
        *) echo "[e] Unknown argument: $1"; usage ;;
    esac
    shift
done

if [ "$shutdown_containers" = true ] && [ -z "$path" ]; then
    echo "[i] Shutting down radar containers."
    docker compose down
    exit 0
fi

check_docker

if [ -z "$path" ]; then
    echo "[e] Path to the contract is not set."
    usage
fi

checksum_file="docker_checksum.sha"
current_checksum=$(cat docker-compose.yml | shasum -a 256 | cut -d" " -f1)

if [ -f "$checksum_file" ]; then
    stored_checksum=$(cat "$checksum_file")
    if [ "$current_checksum" != "$stored_checksum" ]; then
        echo "[i] Configuration changed, building images"
        docker compose up -d --build
        echo "$current_checksum" > "$checksum_file"
    else
        docker compose up -d --no-build
    fi
else
    echo "[i] No checksum stored, building images"
    docker compose up -d --build
    echo "$current_checksum" > "$checksum_file"
fi

container_path="/contract"
if [ -n "$source_directory_or_file" ]; then
    container_path+="/${source_directory_or_file}"
fi

docker_command="docker compose run --rm -v ${path}:/contract"
if [ -n "$templates_directory" ]; then
    docker_command+=" -v ${templates_directory}:/templates"
fi
docker_command+=" radar --path ${path} --container-path ${container_path}"
if [ -n "$templates_directory" ]; then
    docker_command+=" --templates /templates"
fi

echo "[i] Executing command: $docker_command"
eval "$docker_command"

if [ "$shutdown_containers" = true ]; then
    echo "[i] Shutting down radar containers"
    docker compose down
fi

docker cp radar-api:/radar_data/output.json . >/dev/null 2>&1