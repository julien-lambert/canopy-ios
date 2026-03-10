#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def to_pascal(s: str) -> str:
    parts = re.split(r"[^a-zA-Z0-9]+", s)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def to_camel(s: str) -> str:
    p = to_pascal(s)
    return p[:1].lower() + p[1:] if p else s


def parse_entities_yaml(path: Path):
    entities = []
    current = None
    in_fields = False

    name_re = re.compile(r"^\s*-\s*name:\s*([A-Za-z0-9_]+)\s*$")
    table_re = re.compile(r"^\s*table:\s*([a-z0-9_]+)\s*$")
    fields_re = re.compile(r"^\s*fields:\s*$")
    field_re = re.compile(r"^\s{6}([a-z0-9_]+):\s*\{")

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip("\n")
        m_name = name_re.match(line)
        if m_name:
            if current:
                entities.append(current)
            current = {"name": m_name.group(1), "table": None, "fields": []}
            in_fields = False
            continue

        if not current:
            continue

        m_table = table_re.match(line)
        if m_table:
            current["table"] = m_table.group(1)
            continue

        if fields_re.match(line):
            in_fields = True
            continue

        if in_fields:
            m_field = field_re.match(line)
            if m_field:
                current["fields"].append(m_field.group(1))
                continue

            # End of fields block when indentation drops and it's not a field line.
            if line.startswith("  - name:") or (line and not line.startswith("      ")):
                in_fields = False

    if current:
        entities.append(current)
    return entities


def render_swift(entities, core_tables):
    lines = []
    lines.append("// Generated file. Do not edit manually.")
    lines.append("// Source: jardin-supabase/schema/entities.yaml")
    lines.append("")
    lines.append("import Foundation")
    lines.append("")
    lines.append("enum CanopySchema {")
    lines.append("    enum Tables {")
    for table_name in sorted(core_tables.keys()):
        lines.append(f'        static let {to_camel(table_name)} = "{table_name}"')
    for ent in entities:
        table = ent["table"]
        if not table:
            continue
        lines.append(f'        static let {to_camel(table)} = "{table}"')
    lines.append("    }")
    lines.append("")
    for table_name, fields in sorted(core_tables.items()):
        enum_name = f"{to_pascal(table_name)}Fields"
        lines.append(f"    enum {enum_name} {{")
        for field in fields:
            lines.append(f'        static let {to_camel(field)} = "{field}"')
        lines.append("    }")
        lines.append("")

    for ent in entities:
        table = ent["table"]
        fields = ent["fields"]
        if not table:
            continue
        enum_name = f"{to_pascal(table)}Fields"
        lines.append(f"    enum {enum_name} {{")
        for field in fields:
            lines.append(f'        static let {to_camel(field)} = "{field}"')
        lines.append("    }")
        lines.append("")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    repo_root = Path(__file__).resolve().parents[1]
    default_source = repo_root.parent / "jardin-supabase" / "schema" / "entities.yaml"
    default_target = repo_root / "JardinForet" / "Data" / "Remote" / "CanopySchemaContract.generated.swift"
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else default_source
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else default_target

    if not source.exists():
        raise SystemExit(f"Source not found: {source}")

    entities = parse_entities_yaml(source)

    core_tables = {
        # Core contract from Canopy v0 hardened migrations (source-of-truth for app shell).
        "sites": [
            "id",
            "owner_id",
            "name",
            "slug",
            "description",
            "geom",
            "is_public",
            "settings",
            "created_at",
            "updated_at",
            "deleted_at",
        ],
        "site_members": [
            "site_id",
            "user_id",
            "role",
            "created_at",
            "updated_at",
            "deleted_at",
        ],
        "site_modules": [
            "site_id",
            "module_code",
            "enabled",
            "config",
            "created_at",
            "updated_at",
            "deleted_at",
        ],
        "modules_catalog": [
            "code",
            "min_plan",
            "is_billable",
            "depends_on",
            "metadata",
            "billing",
            "ui",
            "created_at",
            "updated_at",
        ],
        "site_templates": [
            "name",
            "description",
            "modules",
            "module_configs",
            "defaults",
            "created_at",
            "updated_at",
        ],
    }

    swift = render_swift(entities, core_tables)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(swift, encoding="utf-8")
    print(f"Generated: {target}")


if __name__ == "__main__":
    main()
