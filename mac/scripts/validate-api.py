"""Validate the local contract without resolving remote or filesystem references."""
import sys
from pathlib import Path


def validate(path, expected):
    import yaml
    from openapi_spec_validator import validate as validate_spec

    document = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError("contract must be an OpenAPI object")
    if not str(document.get("openapi", "")).startswith(("3.0.", "3.1.")):
        raise ValueError("expected OpenAPI 3.0 or 3.1 for Swift OpenAPI Generator")
    info = document.get("info")
    if not isinstance(info, dict):
        raise ValueError("contract info must be an object with title and version")
    actual = info.get("version")
    if actual != expected:
        raise ValueError(f"API version mismatch: api-version requires {expected}, info.version is {actual!r}")

    def check_refs(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "$ref" and (not isinstance(item, str) or not item.startswith("#/")):
                    raise ValueError("contract must be self-contained; only local #/ references are supported")
                check_refs(item)
        elif isinstance(value, list):
            for item in value:
                check_refs(item)

    check_refs(document)
    validate_spec(document)


if __name__ == "__main__":
    try:
        validate(sys.argv[1], sys.argv[2])
    except ImportError:
        sys.exit("error: Validation dependencies missing. Install scripts/requirements-api.txt with the selected Python interpreter.")
    except Exception as error:
        sys.exit(f"error: OpenAPI validation failed: {error}")
    print("API version and OpenAPI format are valid.")
