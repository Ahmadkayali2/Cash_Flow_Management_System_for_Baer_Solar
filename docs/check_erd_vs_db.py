#!/usr/bin/env python3
"""
Consistency check: Chen ERD  <->  live PostgreSQL schema.

The rule this enforces:

    The ERD may show LESS than the database.
    It must never show something DIFFERENT from the database.

So the check is asymmetric on purpose.

  ERROR   an entity, attribute or relationship is drawn on the ERD but
          does not exist in the database. The diagram is making a false
          claim, which is exactly the fault the Vakproject was marked
          down for ("forecasts-relatie staat in het Chen-diagram maar de
          overeenkomstige FK ontbreekt in schema.sql").

  ERROR   a table exists in the database and is neither drawn nor listed
          as a declared exclusion. Something is unaccounted for.

  OK      a table exists in the database, is not drawn, and IS listed as
          a declared exclusion with a reason. That is abstraction, not
          contradiction.

Usage:
    python3 check_erd_vs_db.py erd_conceptual_chen.dot schema.json
"""
import json, re, sys
from collections import defaultdict

# --- tables that exist in the database but are deliberately not drawn ----
# Each needs a reason. An exclusion without a reason is a gap, not a decision.
EXCLUSIONS = {
    'attribute domain': (
        "Implements the set of values an attribute may take. Conceptually a "
        "domain, not a business entity. Listed in the data dictionary.",
        ['ref_milestone_type','ref_project_status','ref_schedule_status',
         'ref_invoice_status','ref_order_status','ref_payment_method',
         'ref_product_category','ref_cost_category','ref_direct_cost_type',
         'ref_overhead_category']),
    'analytical layer': (
        "Dimensional model for the OLAP workload. Modelled in dimensional "
        "notation in the technical layer chapter, not in Chen notation.",
        ['dim_date','dim_project','dim_customer','dim_cost_type',
         'fact_daily_cashflow']),
    'pipeline and audit': (
        "Supports the import process and the GDPR accountability duty. "
        "Not part of the business domain.",
        ['etl_run','stg_sevdesk_invoice','data_erasure_log']),
}

def snake(name):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()

# --- parse the DOT ------------------------------------------------------
def parse_dot(path):
    src = open(path, encoding='utf-8').read()
    src = re.sub(r'//[^\n]*', '', src)          # strip comments

    entities, weak, rels = set(), set(), set()
    nonattr = set()   # relationship / ISA nodes look like attribute nodes

    # entity / weak-entity / relationship declarations follow a `node [...]`
    # style line, so track the most recent style block
    current = None
    for line in src.splitlines():
        m = re.match(r'\s*node\s*\[(.*)\]', line)
        if m:
            attrs = m.group(1)
            if 'shape=box' in attrs:
                current = 'weak' if 'peripheries=2' in attrs else 'entity'
            elif 'shape=diamond' in attrs:
                current = 'rel'
            elif 'shape=triangle' in attrs:
                current = 'isa'
            elif 'shape=ellipse' in attrs:
                current = 'attr'
            else:
                current = None
            continue
        if current in ('entity', 'weak'):
            for n in re.findall(r'\b([A-Z][A-Za-z]+)\b(?=\s*[;,])', line):
                (weak if current == 'weak' else entities).add(n)
        elif current in ('rel', 'isa'):
            # these are declared with the same `name [label=...]` shape as
            # attributes, so record them and exclude them below
            for n in re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[', line):
                nonattr.add(n)
            rels.add(line)

    # attribute nodes:  cu_id [label=<<U>customer_id</U>>]   /   [label="city"]
    attr_col = {}
    for node, lbl in re.findall(r'^\s*([a-z][a-z0-9_]*)\s*\[label=(<<U>[^<]+</U>>|"[^"]+")', src, re.M):
        if node in nonattr:
            continue          # a relationship diamond, not an attribute
        col = re.sub(r'^<<U>|</U>>$|^"|"$', '', lbl)
        attr_col[node] = col

    # entity -> attribute edges:  Customer -- {a b c};   Product -- pd_id;
    ent_attrs = defaultdict(set)
    for ent, group in re.findall(r'\b([A-Z][A-Za-z]+)\s*--\s*\{([^}]*)\}', src):
        for n in group.split():
            if n in attr_col: ent_attrs[ent].add(attr_col[n])
    for ent, node in re.findall(r'\b([A-Z][A-Za-z]+)\s*--\s*([a-z][a-z0-9_]*)\s*(?:\[[^\]]*\])?\s*;', src):
        if node in attr_col: ent_attrs[ent].add(attr_col[node])

    # relationship edges: Entity -- r_x [...]  /  r_x -- Entity [...]
    left, right = defaultdict(list), defaultdict(list)
    for a, b in re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*--\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[headlabel', src):
        if a.startswith('r_') or a.startswith(('c','d','s')) and a[1:].isdigit():
            left[a].append(b)
        elif b.startswith('r_'):
            right[b].append(a)
    pairs = []
    for rel in set(list(left) + list(right)):
        for e1 in right.get(rel, []):
            for e2 in left.get(rel, []):
                pairs.append((e1, rel, e2))

    return entities | weak, weak, ent_attrs, pairs

# --- compare ------------------------------------------------------------
def main():
    dot, schema_path = sys.argv[1], sys.argv[2]
    S = json.load(open(schema_path))
    cols = defaultdict(set); fks = set(); tables = set()
    for r in S:
        t = r['table_name']; tables.add(t); cols[t].add(r['column_name'])
        if r['fk_target']:
            fks.add((t, r['fk_target'].split('.')[0]))

    entities, weak, ent_attrs, pairs = parse_dot(dot)
    errors, notes, ok = [], [], []

    # 1. every drawn entity must be a table
    for e in sorted(entities):
        t = snake(e)
        if t in tables: ok.append(f"entity {e} -> table {t}")
        else: errors.append(f"ENTITY DRAWN BUT NOT IN DATABASE: {e} (expected table '{t}')")

    # 2. every drawn attribute must be a column
    for e in sorted(ent_attrs):
        t = snake(e)
        if t not in tables: continue
        for a in sorted(ent_attrs[e]):
            if a in cols[t]: ok.append(f"attribute {e}.{a}")
            else: errors.append(f"ATTRIBUTE DRAWN BUT NOT IN DATABASE: {e}.{a} (table '{t}')")

    # 3. every drawn relationship must be backed by a real foreign key
    for e1, rel, e2 in pairs:
        t1, t2 = snake(e1), snake(e2)
        if t1 not in tables or t2 not in tables: continue
        label = rel.replace('r_', '')
        if (t2, t1) in fks or (t1, t2) in fks:
            ok.append(f"relationship {e1} --{label}-- {e2}")
        else:
            errors.append(f"RELATIONSHIP DRAWN BUT NO FOREIGN KEY: {e1} --{label}-- {e2} "
                          f"(no FK between '{t1}' and '{t2}')")

    # 4. every table must be drawn or declared as an exclusion
    drawn = {snake(e) for e in entities}
    declared = {t: k for k, (_, ts) in EXCLUSIONS.items() for t in ts}
    for t in sorted(tables):
        if t in drawn: continue
        if t in declared: notes.append(f"{t}  ->  not drawn, declared as: {declared[t]}")
        else: errors.append(f"TABLE IN DATABASE BUT NEITHER DRAWN NOR DECLARED: {t}")

    # --- report ---------------------------------------------------------
    print("=" * 68)
    print("ERD  <->  DATABASE CONSISTENCY CHECK")
    print("=" * 68)
    print(f"\nDrawn on the ERD : {len(entities)} entities, "
          f"{sum(len(v) for v in ent_attrs.values())} attributes, {len(pairs)} relationships")
    print(f"In the database  : {len(tables)} tables, {len(S)} columns, {len(fks)} foreign-key links")
    print(f"\nChecks passed    : {len(ok)}")
    print(f"Declared gaps    : {len(notes)}")
    print(f"ERRORS           : {len(errors)}")

    if notes:
        print("\n--- tables not drawn, with a declared reason ---")
        for n in notes: print("  " + n)
    if errors:
        print("\n--- ERRORS ---")
        for e in errors: print("  ! " + e)
        print("\nRESULT: FAIL")
        sys.exit(1)
    print("\nRESULT: PASS - the ERD makes no claim the database does not support,")
    print("               and every table is either drawn or declared.")

if __name__ == '__main__':
    main()
