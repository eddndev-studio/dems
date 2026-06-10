#!/usr/bin/env python3
"""Importa prototipos reales (Excel, una hoja por categoría) a la API de DEMS.

- Cada hoja = una categoría (mapeada por slug).
- Columnas: IDENTIFICADOR (folio), NOMBRE DEL PROYECTO, INTEGRANTES (;), ASESORES (;).
- Folios: convención <PREFIJO><NNN>. A las filas sin folio o con folio duplicado se les
  asigna el siguiente número libre del prefijo de la hoja.
- Filas sin nombre se omiten (nombre es obligatorio).
- Idempotente: un folio ya existente devuelve 409 → se salta.

Uso:
  DEMS_ADMIN_PASSWORD=... python3 scripts/import_prototipos.py <xlsx> [--base URL] [--dry-run]
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

import pandas as pd

SHEET2SLUG = {
    "Aplicación Empresa": "aplicacion-empresa",
    "Desarrollo Software": "desarrollo-software",
    "Maquinaria y Equipo": "maquinaria-equipo",
    "Procesos Químicos": "procesos-quimicos-biologicos",
    "Productos Enseñanza": "productos-ensenanza",
    "Productos Salud": "productos-salud",
    "Soluciones Domésticas": "soluciones-domesticas",
}

EDITION_YEAR = 2026
EDITION_NAME = "35° Premio a los Mejores Prototipos NMS 2026"
MAX_NOMBRE = 200


def api(base, method, path, token=None, body=None):
    url = base.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "dems-importer/1.0")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def clean(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip()
    return s if s and s.lower() != "nan" else None


def split_people(v, rol):
    s = clean(v)
    if not s:
        return []
    out = []
    for p in re.split(r"[;\n]+", s):
        p = p.strip()
        if p and p.lower() != "nan":
            out.append({"nombre": p[:MAX_NOMBRE], "rol": rol})
    return out


def parse_folio(v):
    s = clean(v)
    if not s:
        return None
    m = re.match(r"^([A-Za-z]+)\s*0*(\d+)$", s)
    return (m.group(1).upper(), int(m.group(2))) if m else None


def build_plan(df, sheet):
    """Devuelve (rows_plan, skipped). rows_plan: dicts con folio/nombre/integrantes/assigned."""
    parsed = []
    prefix_counts, used_nums, seen = {}, set(), set()
    for _, row in df.iterrows():
        name = clean(row.get("NOMBRE DEL PROYECTO"))
        pf = parse_folio(row.get("IDENTIFICADOR"))
        parsed.append((row, name, pf))
        if pf:
            prefix_counts[pf[0]] = prefix_counts.get(pf[0], 0) + 1
    prefix = max(prefix_counts, key=prefix_counts.get) if prefix_counts else "XXX"
    # registrar números de folios válidos (primera ocurrencia)
    for row, name, pf in parsed:
        if name is None or not pf:
            continue
        fol = f"{pf[0]}{pf[1]:03d}"
        if fol not in seen:
            seen.add(fol)
            used_nums.add(pf[1])

    def next_folio():
        n = (max(used_nums) + 1) if used_nums else 1
        used_nums.add(n)
        return f"{prefix}{n:03d}"

    rows_plan, skipped, assigned_seen = [], [], set()
    for row, name, pf in parsed:
        if name is None:
            skipped.append({"folio": (pf and f"{pf[0]}{pf[1]:03d}"), "reason": "sin nombre"})
            continue
        fol = f"{pf[0]}{pf[1]:03d}" if pf else None
        assigned = False
        original = None
        if fol is None or fol in assigned_seen:
            original = fol  # None (sin folio) o folio duplicado
            fol = next_folio()
            assigned = True
        assigned_seen.add(fol)
        integr = split_people(row.get("INTEGRANTES"), "integrante")
        ases = split_people(row.get("ASESORES"), "asesor")
        nombre = name[:MAX_NOMBRE]
        rows_plan.append({
            "folio": fol,
            "nombre": nombre,
            "nombre_truncado": len(name) > MAX_NOMBRE,
            "assigned": assigned,
            "original": original,
            "integrantes": integr + ases,
            "n_int": len(integr),
            "n_ase": len(ases),
        })
    return rows_plan, skipped, prefix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx")
    ap.add_argument("--base", default="https://dems.eddndev.work")
    ap.add_argument("--email", default=os.environ.get("DEMS_ADMIN_EMAIL", "admin@dems.local"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    pw = os.environ.get("DEMS_ADMIN_PASSWORD")
    if not pw:
        sys.exit("falta DEMS_ADMIN_PASSWORD en el entorno")

    st, res = api(args.base, "POST", "/auth/login", body={"email": args.email, "password": pw})
    if st != 200:
        sys.exit(f"login falló ({st}): {res}")
    token = res["access_token"]

    st, cats = api(args.base, "GET", "/admin/categorias", token)
    slug2id = {c["slug"]: c["id"] for c in cats}

    st, eds = api(args.base, "GET", "/admin/editions", token)
    edition = next((e for e in eds if e["year"] == EDITION_YEAR), None)
    if edition:
        edition_id = edition["id"]
        print(f"edición {EDITION_YEAR} ya existe: {edition['name']} ({edition_id}) phase={edition['phase']}")
    elif args.dry_run:
        edition_id = "<se-crearía>"
        print(f"[dry-run] se crearía edición {EDITION_YEAR}: {EDITION_NAME!r} (active=true)")
    else:
        st, edition = api(args.base, "POST", "/admin/editions",
                          token, {"year": EDITION_YEAR, "name": EDITION_NAME, "active": True})
        if st not in (200, 201):
            sys.exit(f"crear edición falló ({st}): {edition}")
        edition_id = edition["id"]
        print(f"edición {EDITION_YEAR} creada: {EDITION_NAME!r} ({edition_id})")

    xls = pd.ExcelFile(args.xlsx)
    created = skipped_409 = errors = 0
    total_plan = 0
    for sheet in xls.sheet_names:
        slug = SHEET2SLUG.get(sheet)
        cat_id = slug2id.get(slug)
        df = pd.read_excel(args.xlsx, sheet_name=sheet)
        plan, skipped, prefix = build_plan(df, sheet)
        total_plan += len(plan)
        print(f"\n=== {sheet} → {slug} (prefijo {prefix})  plan={len(plan)}  omitidas={len(skipped)}")
        for s in skipped:
            print(f"   OMITIR {s['folio']}: {s['reason']}")
        for p in plan:
            tag = ""
            if p["assigned"]:
                tag = f"  [FOLIO ASIGNADO {p['folio']}, original={p['original'] or 'SIN FOLIO'}]"
            if p["nombre_truncado"]:
                tag += "  [nombre truncado a 200]"
            line = f"   {p['folio']}  {p['nombre'][:55]!r}  int={p['n_int']} ase={p['n_ase']}{tag}"
            if args.dry_run:
                print(line)
                continue
            body = {
                "edition_id": edition_id,
                "folio": p["folio"],
                "nombre": p["nombre"],
                "eje_transversal": False,
                "categorias": [cat_id] if cat_id else [],
                "integrantes": p["integrantes"],
            }
            st, res = api(args.base, "POST", "/admin/prototipos", token, body)
            if st in (200, 201):
                created += 1
            elif st == 409:
                skipped_409 += 1
                print(f"   SKIP 409 (ya existe) {p['folio']}")
            else:
                errors += 1
                print(f"   ERROR {st} {p['folio']}: {res}")

    print(f"\n===== {'DRY-RUN ' if args.dry_run else ''}RESUMEN =====")
    print(f"planeados: {total_plan}")
    if not args.dry_run:
        print(f"creados: {created}   ya existían(409): {skipped_409}   errores: {errors}")


if __name__ == "__main__":
    main()
