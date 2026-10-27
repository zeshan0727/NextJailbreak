"""Fix optional metadata validation so accepted AI repairs are not blocked."""
from pathlib import Path
root=Path(__file__).resolve().parent
p=root/'filemanager/repair.py'
s=p.read_text(encoding='utf-8')
start=s.index('        if date and not grounded_date(date, str(proposal.get("content") or "") + " " + before["original_name"]):')
end=s.index('        if not name or Path(name).name != name',start)
s=s[:start]+'''        # Preview and commit must consider the same document and filename evidence.
        # Earlier library schemas may have blank original_name fields.
        original_name = before["original_name"] or before["title"]
        proof = str(proposal.get("content") or "") + " " + original_name
        reference = str(proposal.get("reference") or "")
        notices = []
        # Unsupported optional metadata must not block a good company/category.
        if date and not grounded_date(date, proof):
            notices.append("Unsupported document date omitted")
            date = ""
        refs = meaningful_ref(reference, proof) if reference else ""
        if reference and not refs:
            notices.append("Unsupported reference omitted")
        name = str(proposal.get("new_name") or "")
        # Never leave an unsupported auto-generated reference in the saved name.
        if notices and not proposal.get("manual_override"):
            name = make_repair_name(original_name, company["name"], cat, refs, date,
                                    str(proposal.get("label") or ""))
''' + s[end:]
old='            return {"status":"unchanged", "id": doc_id, "name": before["title"]}'
assert old in s
s=s.replace(old,'            return {"status":"unchanged", "id": doc_id, "name": before["title"], "notices": notices}')
old='        return {"status":"updated", "id":doc_id,"name":dest.name, "company":company["name"], "category":cat}'
assert old in s
s=s.replace(old,'        return {"status":"updated", "id":doc_id,"name":dest.name, "company":company["name"], "category":cat, "notices": notices}')
p.write_text(s,encoding='utf-8')
p=root/'filemanager/gui.py'
s=p.read_text(encoding='utf-8')
for old,new in [
 ('("confidence","AI MATCH",88)', '("confidence","AI ESTIMATE",100)'),
 ('        done=0; errors=[]\n        for docid in ids:', '        done=0; errors=[]; omitted=0\n        for docid in ids:'),
 ('                done+=out["status"]=="updated"\n                del self.repair_proposals[docid]', '                done+=out["status"]=="updated"\n                omitted += len(out.get("notices", ()))\n                del self.repair_proposals[docid]'),
 ('        self.status_label.configure(text=f"Repaired {done} existing document(s); {len(errors)} errors",fg=C["amber"] if errors else C["aqua"])',
  '        self.status_label.configure(text=f"Repaired {done} file(s); {omitted} unsupported metadata value(s) safely skipped; {len(errors)} errors",fg=C["amber"] if errors else C["aqua"])\n        self.repair_summary.configure(text=f"{done} repaired • {omitted} optional fields omitted • {len(errors)} failed")'),
 ('        else:messagebox.showinfo("Repair applied",f"Updated {done} file(s) without re-uploading. Use Undo last repair if needed.",parent=self.repair_window)',
  '        # A successful batch no longer opens a modal dialog.'),
 ('        text(win,"Green = high confidence and specific category. Yellow = manual review required. Preview never moves any files.",',
  '        text(win,"AI estimate is not verified accuracy. Unsupported optional references are skipped, not blocked. Green = ready; yellow = review.",')
]:
 assert old in s, 'Missing expected GUI snippet: '+old[:100]
 s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('v1.5 validation and nonblocking batch repair patch applied')
