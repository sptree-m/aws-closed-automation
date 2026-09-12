#!/usr/bin/env python3
import csv, html, json, pathlib, sys
from datetime import datetime, timezone

out=pathlib.Path(sys.argv[1])
with (out/"results.tsv").open(encoding="utf-8") as f:
    rows=list(csv.DictReader(f, delimiter="\t"))
passed=sum(r["result"]=="PASS" for r in rows)
failed=sum(r["result"]=="FAIL" for r in rows)
overall="PASS" if failed==0 else "FAIL"
try:
    caller=json.loads((out/"raw/caller_identity.json").read_text())
except Exception:
    caller={}
generated=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")

md=[
"# Secure Claude Code Environment — Deployment Evidence Report","",
f"- Generated (UTC): {generated}",
f"- AWS Account: {caller.get('Account','unknown')}",
f"- Principal: {caller.get('Arn','unknown')}",
f"- Overall: **{overall}**",
f"- Checks: {passed} PASS / {failed} FAIL","",
"| ID | Category | Result | Expected | Actual |",
"|---|---|---|---|---|"]
for r in rows:
    md.append(f"| {r['id']} | {r['category']} | **{r['result']}** | {r['expected']} | {r['actual']} |")
md += ["","## Evidence integrity","","Raw AWS API/CLI outputs are under `raw/` and hashed in `SHA256SUMS`."]
(out/"report.md").write_text("\n".join(md)+"\n",encoding="utf-8")

trs="\n".join("<tr>"+ "".join([
f"<td>{html.escape(r['id'])}</td>",f"<td>{html.escape(r['category'])}</td>",
f"<td class='{r['result'].lower()}'>{html.escape(r['result'])}</td>",
f"<td>{html.escape(r['expected'])}</td>",f"<td>{html.escape(r['actual'])}</td>",
f"<td>{html.escape(r['detail'])}</td>"])+"</tr>" for r in rows)
doc=f"""<!doctype html><html><head><meta charset="utf-8"><title>Deployment Evidence Report</title>
<style>body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:40px;color:#172033}}.meta{{color:#566174}}.summary{{padding:14px 18px;border:1px solid #ccd5e0;border-radius:8px;margin:18px 0}}table{{border-collapse:collapse;width:100%;font-size:13px}}th,td{{border:1px solid #d9e0e8;padding:8px;vertical-align:top;text-align:left}}th{{background:#f5f7fa}}.pass,.fail{{font-weight:700}}.fail{{text-decoration:underline}}</style>
</head><body><h1>Secure Claude Code Environment</h1><div class="meta">Deployment Evidence Report</div>
<div class="summary"><b>Generated:</b> {html.escape(generated)}<br><b>AWS Account:</b> {html.escape(str(caller.get("Account","unknown")))}<br><b>Principal:</b> {html.escape(str(caller.get("Arn","unknown")))}<br><b>Overall:</b> {overall} — {passed} PASS / {failed} FAIL</div>
<table><thead><tr><th>ID</th><th>Category</th><th>Result</th><th>Expected</th><th>Actual</th><th>Detail</th></tr></thead><tbody>{trs}</tbody></table>
<h2>Evidence integrity</h2><p>Raw AWS API outputs are stored under <code>raw/</code>. SHA-256 hashes are recorded in <code>SHA256SUMS</code>.</p></body></html>"""
(out/"report.html").write_text(doc,encoding="utf-8")
print(f"Report generated: {out/'report.html'} ({overall})")
sys.exit(0 if failed==0 else 2)
