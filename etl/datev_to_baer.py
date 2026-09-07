#!/usr/bin/env python3
"""
DATEV EXTF Buchungsstapel  ->  Baer Solar operational schema.

WHY THIS EXISTS
SEVDESK exports bookkeeping, not invoices. The file is a DATEV
"Buchungsstapel": a general ledger in double-entry form, 122 columns wide,
of which 33 carry data. Every line is a posting (Konto / Gegenkonto /
debit-credit flag), not a business document. Turning it into the project's
operational tables means reading the accounting, not just reshaping columns.

WHAT IT DOES
  1. parse    - German decimals, DDMM dates, quoted DATEV fields
  2. classify - each posting by account class (SKR04) into revenue,
                customer payment, supplier expense or bank movement
  3. resolve  - cancel-and-reissue (storno) pairs, so a corrected invoice
                is not counted twice
  4. pseudonymise - real customer and supplier names are replaced before
                anything leaves this script (GDPR Art. 4(5))
  5. emit     - CSVs matching the project schema, plus one in the exact
                format the ingest pipeline expects

USAGE
  python3 datev_to_baer.py EXTF_Buchungsstapel_*.csv --year 2026 --out ./out
"""
import argparse, csv, hashlib, os, re, sys
from collections import defaultdict

# --- SKR04 account classes -------------------------------------------------
REVENUE_PREFIX   = ('4',)          # 4000-4999 Umsatzerlöse
MATERIAL_PREFIX  = ('5',)          # 5000-5499 Wareneingang / Fremdleistungen (5500+ = Personal)
OVERHEAD_PREFIX  = ('6',)          # 6000-6999 Betriebliche Aufwendungen
BANK_ACCOUNTS    = {'1800'}        # Bank
DEBTOR_RANGE     = (10000, 69999)  # Debitoren  = customers
CREDITOR_RANGE   = (70000, 99999)  # Kreditoren = suppliers

OVERHEAD_MAP = {   # SKR04 -> the project's ref_overhead_category domain
    '6020':'Rent','6070':'Rent','6110':'Rent','6520':'Fuel','6530':'Fuel',
    '6600':'Advertising','6740':'Insurance','6805':'Software License',
    '6830':'Software License','6837':'Software License','6845':'Software License',
    '6850':'Software License','6855':'Software License','5736':'Insurance',
}

def de_num(s):
    s = (s or '').strip()
    if not s: return 0.0
    return float(s.replace('.', '').replace(',', '.'))

def de_date(ddmm, year):
    """DATEV Belegdatum is DDMM, sometimes without the leading zero."""
    s = (ddmm or '').strip()
    if not s: return None
    s = s.zfill(4)
    return f"{year}-{s[2:4]}-{s[0:2]}"

def acct_class(g):
    try: v = int(g)
    except (TypeError, ValueError): return 'GL'
    if DEBTOR_RANGE[0]   <= v <= DEBTOR_RANGE[1]:   return 'DEB'
    if CREDITOR_RANGE[0] <= v <= CREDITOR_RANGE[1]: return 'KRED'
    return 'GL'

# --- pseudonymisation ------------------------------------------------------
FIRST = ['Andreas','Birgit','Christoph','Daniela','Erik','Franziska','Gerd',
         'Helena','Ingo','Johanna','Klaus','Lena','Martin','Nina','Oliver',
         'Petra','Rainer','Sabine','Thomas','Ulrike','Viktor','Wiebke']
LAST  = ['Albrecht','Böhm','Christen','Dietrich','Engel','Falk','Gruber',
         'Hartmann','Ihle','Jansen','Köhler','Lindner','Möller','Naumann',
         'Ostermann','Pfeiffer','Reuter','Sander','Thiele','Ulrich','Vogt','Werner']
COMPANY_TAIL = ['GmbH','GmbH & Co. KG','e.K.','AG','UG (haftungsbeschränkt)']
CITIES = [('Köln','50931'),('Stuttgart','70178'),('Hannover','30177'),
          ('Dresden','01099'),('Dortmund','44139'),('Freiburg','79104'),
          ('Nürnberg','90429'),('Hamburg','20259'),('Leipzig','04277'),
          ('Bremen','28195'),('Essen','45127'),('Bonn','53111')]
STREETS = ['Ahornweg','Birkenallee','Comeniusstraße','Domplatz','Erlenkamp',
           'Feldstraße','Goethering','Hafenweg','Isarstraße','Jahnplatz']

def pseudo(name, kind, salt='baer-solar-2026'):
    """Deterministic: the same real name always yields the same pseudonym,
    so relationships survive, but the original is not recoverable."""
    h = int(hashlib.sha256((salt + '|' + name).encode()).hexdigest(), 16)
    if kind == 'company' or re.search(r'\b(GmbH|AG|KG|e\.K\.|UG|Inc|Ltd|SE)\b', name):
        return f"{LAST[h % len(LAST)]} {['Energie','Solar','Technik','Bau','Handel'][h//7 % 5]} {COMPANY_TAIL[h//11 % len(COMPANY_TAIL)]}"
    return f"{FIRST[h % len(FIRST)]} {LAST[(h//13) % len(LAST)]}"

def pseudo_address(key):
    h = int(hashlib.sha256(key.encode()).hexdigest(), 16)
    city, plz = CITIES[h % len(CITIES)]
    return STREETS[(h//7) % len(STREETS)], str(1 + h % 180), plz, city

# --- main ------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('infile')
    ap.add_argument('--year', type=int, required=True,
                    help='DATEV Belegdatum has no year; take it from the export period')
    ap.add_argument('--out', default='./out')
    ap.add_argument('--keep-real-names', action='store_true',
                    help='skip pseudonymisation (never use for the thesis repo)')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    rows = list(csv.DictReader(open(a.infile, encoding='utf-8-sig')))
    log = []

    # ---- classify -------------------------------------------------------
    revenue, cust_pay, expenses, supp_pay, skipped = [], [], [], [], []
    for i, r in enumerate(rows, start=2):
        konto = (r.get('Konto') or '').strip()
        geg   = (r.get('Gegenkonto (ohne BU-Schlüssel)') or '').strip()
        sh    = (r.get('Soll-/Haben-Kennzeichen') or '').strip()
        amt   = de_num(r.get('Umsatz'))
        cls   = acct_class(geg)
        rec = dict(line=i, konto=konto, geg=geg, sh=sh, amount=amt,
                   date=de_date(r.get('Belegdatum'), a.year),
                   doc=(r.get('Belegfeld 1') or '').strip(),
                   text=(r.get('Buchungstext') or '').strip(),
                   vat=(r.get('Beleginfo-Inhalt 2') or '').strip(),
                   name=(r.get('Beleginfo-Inhalt 3') or '').strip())
        if konto.startswith(REVENUE_PREFIX) and cls == 'DEB':
            revenue.append(rec)
        elif konto in BANK_ACCOUNTS and cls == 'DEB':
            cust_pay.append(rec)
        elif konto.startswith(MATERIAL_PREFIX + OVERHEAD_PREFIX) and cls == 'KRED':
            expenses.append(rec)
        elif konto in BANK_ACCOUNTS and cls == 'KRED':
            supp_pay.append(rec)
        else:
            skipped.append(rec)
    log.append(f"classified {len(rows)} postings: {len(revenue)} revenue, "
               f"{len(cust_pay)} customer payments, {len(expenses)} expenses, "
               f"{len(supp_pay)} supplier payments, {len(skipped)} internal/GL movements")

    # ---- resolve storno pairs -------------------------------------------
    # A credit note (S on a revenue account) carries its OWN document number
    # and reverses an EARLIER invoice. Matching purely on amount is wrong: it
    # will happily pair a credit note with the reissue that came after it and
    # delete the live invoice. The cancelled document must therefore have a
    # lower document number than the credit note. When no such document
    # exists in this period the original was billed earlier, so only the
    # credit note itself is out of scope.
    def docnum(d):
        m = re.search(r'(\d+)', d or '')
        return int(m.group(1)) if m else -1

    credits  = sorted([r for r in revenue if r['sh'] == 'S'], key=lambda x: docnum(x['doc']))
    invoices = sorted([r for r in revenue if r['sh'] == 'H'], key=lambda x: docnum(x['doc']))
    cancelled, out_of_period = set(), []
    for c in credits:
        hit = next((h for h in invoices
                    if h['doc'] not in cancelled
                    and docnum(h['doc']) < docnum(c['doc'])
                    and h['geg'] == c['geg']
                    and abs(h['amount'] - c['amount']) < 0.005), None)
        if hit:
            cancelled.add(hit['doc'])
            log.append(f"storno: credit note {c['doc']} reverses {hit['doc']} "
                       f"EUR {c['amount']:,.2f} on debtor {c['geg']}")
        else:
            out_of_period.append(c)
            log.append(f"storno: credit note {c['doc']} EUR {c['amount']:,.2f} "
                       f"reverses an invoice billed before this period "
                       f"(debtor {c['geg']}) - excluded from this batch")
    live_invoices = [r for r in invoices if r['doc'] not in cancelled]
    log.append(f"{len(revenue)} revenue postings -> {len(live_invoices)} live invoices "
               f"({len(cancelled)} reversed in-period, {len(out_of_period)} credit notes "
               f"against earlier periods)")

    # ---- identities ------------------------------------------------------
    debtor_name, creditor_name = {}, {}
    for r in revenue + cust_pay:
        if r['name']: debtor_name.setdefault(r['geg'], r['name'])
    for r in cust_pay:
        m = re.search(r'(?:Zahlung zu|Zahlung)\s+', r['text'])
        debtor_name.setdefault(r['geg'], r['text'][:40])
    for r in expenses:
        creditor_name.setdefault(r['geg'], (r['name'] or r['text'])[:40])

    def show(raw, key, kind):
        return raw if a.keep_real_names else pseudo(raw or key, kind)

    # ---- emit -------------------------------------------------------------
    w = lambda name, hdr: (open(os.path.join(a.out, name), 'w', newline='', encoding='utf-8'), hdr)

    f, hdr = w('customers.csv', ['debtor_account','first_name','last_name','company_name',
                                 'email','street_name','house_number','postal_code','city','country'])
    cw = csv.writer(f); cw.writerow(hdr)
    for acct in sorted(debtor_name):
        disp = show(debtor_name[acct], acct, 'person')
        st, hn, plz, city = pseudo_address(acct)
        if any(t in disp for t in COMPANY_TAIL):
            first, last, comp = 'Kontakt', disp.split()[0], disp
        else:
            parts = disp.split(); first, last, comp = parts[0], parts[-1], ''
        cw.writerow([acct, first, last, comp,
                     f"{first.lower()}.{last.lower()}@example.de".replace('ä','ae').replace('ö','oe').replace('ü','ue').replace('ß','ss'),
                     st, hn, plz, city, 'Germany'])
    f.close()

    f, hdr = w('suppliers.csv', ['creditor_account','supplier_name','payment_terms_days','contact_email'])
    cw = csv.writer(f); cw.writerow(hdr)
    for acct in sorted(creditor_name):
        disp = show(creditor_name[acct], acct, 'company')
        cw.writerow([acct, disp, 7, f"orders@{re.sub(r'[^a-z]','',disp.lower())[:14] or 'supplier'}.de"])
    f.close()

    # invoices in the pipeline's own format
    f, hdr = w('invoices_for_pipeline.csv',
               ['invoice_number','project_id','invoice_date','due_date','amount','status'])
    cw = csv.writer(f); cw.writerow(hdr)
    paid_docs = {r['doc'] for r in cust_pay}
    inv_meta = []
    for r in sorted(live_invoices, key=lambda x: (x['date'] or '', x['doc'])):
        due = r['date']
        if due:
            d = [int(x) for x in due.split('-')]
            import datetime
            due = (datetime.date(*d) + datetime.timedelta(days=7)).isoformat()
        status = 'Paid' if r['doc'] in paid_docs else 'Issued'
        cw.writerow([r['doc'], '', r['date'], due, f"{r['amount']:.2f}", status])
        inv_meta.append((r['doc'], r['geg'], r['amount'], r['date'], status, r['vat']))
    f.close()

    f, hdr = w('payments.csv', ['invoice_number','debtor_account','payment_date','amount','payment_method'])
    cw = csv.writer(f); cw.writerow(hdr)
    for r in sorted(cust_pay, key=lambda x: (x['date'] or '')):
        cw.writerow([r['doc'], r['geg'], r['date'], f"{r['amount']:.2f}", 'Bank Transfer'])
    f.close()

    f, hdr = w('costs.csv', ['cost_date','amount','skr04_account','cost_category','overhead_category','creditor_account','memo'])
    cw = csv.writer(f); cw.writerow(hdr)
    for r in sorted(expenses, key=lambda x: (x['date'] or '')):
        # SKR04: 5000-5499 is material and bought-in services (direct);
        # 5500+ is personnel-related and belongs to overhead.
        direct = r['konto'].startswith('5') and int(r['konto']) < 5500
        cw.writerow([r['date'], f"{r['amount']:.2f}", r['konto'],
                     'Direct Project' if direct else 'Operational Overhead',
                     '' if direct else OVERHEAD_MAP.get(r['konto'], 'Software License'),
                     r['geg'], show(r['text'][:40], r['geg'], 'company')])
    f.close()

    f, hdr = w('supplier_payments.csv', ['creditor_account','payment_date','amount','memo'])
    cw = csv.writer(f); cw.writerow(hdr)
    for r in sorted(supp_pay, key=lambda x: (x['date'] or '')):
        cw.writerow([r['geg'], r['date'], f"{r['amount']:.2f}",
                     show(r['text'][:40], r['geg'], 'company')])
    f.close()

    # ---- report -----------------------------------------------------------
    unmatched = sorted({r['doc'] for r in cust_pay} - {d for d,*_ in inv_meta})
    if unmatched:
        log.append(f"{len(unmatched)} payments reference invoices not in this period "
                   f"(billed earlier): {', '.join(unmatched)}")
    gross = sum(r['amount'] for r in revenue if r['sh']=='H')
    net   = sum(r['amount'] for r in live_invoices)
    log.append(f"gross credited revenue EUR {gross:,.2f} -> net of storno EUR {net:,.2f}")
    log.append(f"customers {len(debtor_name)}, suppliers {len(creditor_name)}, "
               f"invoices {len(live_invoices)}, customer payments {len(cust_pay)}, "
               f"supplier payments {len(supp_pay)}, cost postings {len(expenses)}")
    with open(os.path.join(a.out,'transform_report.txt'),'w',encoding='utf-8') as fh:
        fh.write('\n'.join(log)+'\n')
    print('\n'.join(log))
    print(f"\nwritten to {a.out}/")

if __name__ == '__main__':
    main()
