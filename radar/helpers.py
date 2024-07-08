import argparse
import os
from pathlib import Path
import shutil


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="radar")
    parser.add_argument(
        "--path", type=str, required=True, help="Path to the contract source"
    )
    parser.add_argument(
        "--templates", type=str, required=False, help="Path to custom templates folder"
    )
    return parser.parse_args()


def get_env_variable(var_name: str) -> str:
    value = os.getenv(var_name)
    if value is None:
        error_msg = f"Set the {var_name} environment variable"
        raise EnvironmentError(error_msg)
    return value


def check_path(path: Path) -> str:
    if not path.exists():
        print(
            "[e] Error: Contract path provided in argument was not found. Did you configure the volume mount correctly?"
        )
        raise FileNotFoundError

    if path.is_file():
        return "file"
    if path.is_dir():
        return "folder"


def copy_to_docker_mount(src_path: Path, path_type: str) -> None:
    dst_path = Path("/radar_data") / src_path.relative_to("/")
    if dst_path.exists() and dst_path.is_dir():
        shutil.rmtree(dst_path)

    try:
        if path_type == "file":
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(src_path, dst_path)
        elif path_type == "folder":
            shutil.copytree(src_path, dst_path, dirs_exist_ok=True)
        print(f"[i] Successfully copied {path_type} to {dst_path}")
    except Exception as e:
        raise Exception(f"[e] Failed to copy contract {path_type} to volume: {str(e)}")
