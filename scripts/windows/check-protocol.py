#!/usr/bin/env python3
"""Checks the shell protocol's shared fixtures against its JSON Schema (docs/windows-port/PROTOCOL.md).

Every `windows/protocol/fixtures/*.json` must be one line that is valid against `windows/protocol/schema/v1.schema.json`;
every `fixtures/invalid/*.json` must be a line a reader refuses, and those the schema itself can tell apart (the
envelope and field types) must fail it. Python's standard library has no JSON Schema validator and the port adds no
dependency, so this implements the keywords the schema uses and refuses any other, so that the schema cannot outgrow
the check unnoticed. Exit status 0 when everything holds.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTOCOL = ROOT / "windows" / "protocol"
ANNOTATIONS = {"$schema", "$id", "title", "description", "$defs"}
KEYWORDS = {"type", "const", "enum", "properties", "required", "additionalProperties", "items", "$ref", "oneOf",
            "minimum", "maximum", "minLength"}
# Invalid fixtures whose fault is a rule between fields, which the schema does not express; the Swift and C# readers
# refuse them (ShellProtocolTests, ProtocolTests).
SEMANTIC = {"answer-plan-without-accept.json", "answer-empty-id.json"}


class Invalid(Exception):
    pass


def kind(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    raise Invalid(f"not a JSON value: {value!r}")


def resolve(root, reference):
    if not reference.startswith("#/"):
        raise Invalid(f"only local references are supported: {reference}")
    node = root
    for part in reference[2:].split("/"):
        node = node[part]
    return node


def validate(value, schema, root, where="$"):
    unknown = set(schema) - KEYWORDS - ANNOTATIONS
    if unknown:
        raise Invalid(f"{where}: schema keyword(s) this check does not implement: {sorted(unknown)}")
    if "$ref" in schema:
        validate(value, resolve(root, schema["$ref"]), root, where)
    if "oneOf" in schema:
        matches = 0
        for option in schema["oneOf"]:
            try:
                validate(value, option, root, where)
                matches += 1
            except Invalid:
                pass
        if matches != 1:
            raise Invalid(f"{where}: matches {matches} of oneOf's {len(schema['oneOf'])} schemas, not exactly one")
    if "const" in schema and (value != schema["const"] or kind(value) != kind(schema["const"])):
        raise Invalid(f"{where}: {value!r} is not {schema['const']!r}")
    if "enum" in schema and not any(value == option and kind(value) == kind(option) for option in schema["enum"]):
        raise Invalid(f"{where}: {value!r} is not one of {schema['enum']}")
    if "type" in schema:
        allowed = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        actual = kind(value)
        if actual not in allowed and not (actual == "integer" and "number" in allowed):
            raise Invalid(f"{where}: {actual} where {allowed} is required")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise Invalid(f"{where}: {value} < {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            raise Invalid(f"{where}: {value} > {schema['maximum']}")
    if isinstance(value, str) and "minLength" in schema and len(value) < schema["minLength"]:
        raise Invalid(f"{where}: shorter than {schema['minLength']}")
    if isinstance(value, dict):
        for name in schema.get("required", []):
            if name not in value:
                raise Invalid(f"{where}: no {name}")
        properties = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for name, item in value.items():
            if name in properties:
                validate(item, properties[name], root, f"{where}.{name}")
            elif extra is False:
                raise Invalid(f"{where}: {name} is not a property of this message")
            elif isinstance(extra, dict):
                validate(item, extra, root, f"{where}.{name}")
    if isinstance(value, list) and "items" in schema:
        for index, item in enumerate(value):
            validate(item, schema["items"], root, f"{where}[{index}]")


def line_of(path):
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise Invalid("starts with a byte-order mark")
    text = data.decode("utf-8")
    if text.endswith("\n"):
        text = text[:-1]
    if "\n" in text or "\r" in text:
        raise Invalid("more than one line, or a CR")
    return text


def main():
    schema = json.loads((PROTOCOL / "schema" / "v1.schema.json").read_text(encoding="utf-8"))
    failures = []
    valid = sorted((PROTOCOL / "fixtures").glob("*.json"))
    for path in valid:
        try:
            validate(json.loads(line_of(path)), schema, schema)
        except (Invalid, ValueError) as error:
            failures.append(f"{path.name}: {error}")
    invalid = sorted((PROTOCOL / "fixtures" / "invalid").glob("*.json"))
    for path in invalid:
        if path.name in SEMANTIC:
            continue
        try:
            validate(json.loads(line_of(path)), schema, schema)
            failures.append(f"invalid/{path.name}: the schema takes a line a reader must refuse")
        except (Invalid, ValueError):
            pass
    for name in SEMANTIC:
        if not (PROTOCOL / "fixtures" / "invalid" / name).exists():
            failures.append(f"invalid/{name}: listed as semantic but missing")
    if not valid or not invalid:
        failures.append("no fixtures found")
    for failure in failures:
        print(failure)
    print(f"Protocol fixtures: {len(valid)} valid, {len(invalid)} invalid, {len(failures)} failure(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
