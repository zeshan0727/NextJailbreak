"""v1.7: fix manual-review filename validation (no user library mutation)."""
from pathlib import Path
root=Path(__file__).resolve().parent
p=root/'filemanager/repair.py'
s=p.read_text(encoding='utf-8')
start=s.index('def manual_repair_proposal(')
end=s.index('\ndef apply_repair(',start)
replacement='''def _normalize_manual_filename(value: str, source_ext: str) -> str:
    """Accept a stem or full filename. Keep original extension without doubling."""
    raw=str(value or "").strip()
    ext=source_ext.lower()
    if not ext:
        raise ValueError("The managed file has no extension")
    while raw.lower().endswith(ext) and len(raw)>len(ext):
        raw=raw[:-len(ext)].rstrip()
    known={".pdf",".jpg",".jpeg",".png",".webp",".heic",".gif",
           ".doc",".docx",".xls",".xlsx",".csv",".txt",".pptx",
           ".zip",".tif",".tiff",".msg",".eml",".exe",".bat"}
    if Path(raw).suffix.lower() in known:
        raise ValueError("Original file extension must remain "+ext)
    if not raw or raw in {".",".."} or raw.endswith("."):
        raise ValueError("Enter a short name, for example Staff Incentives")
    if len(raw)>85:
        raise ValueError("Use a short filename (85 characters maximum)")
    # v1.6 accidentally double-escaped the regex and rejected valid letters.
    invalid=set('<>:"/|?*')|{chr(92)}
    if any(ord(ch)<32 or ch in invalid for ch in raw):
        raise ValueError("The filename contains a Windows-reserved character")
    reserved={"CON","PRN","AUX","NUL",*(f"COM{i}" for i in range(1,10)),
              *(f"LPT{i}" for i in range(1,10))}
    if raw.upper().split(".")[0] in reserved:
        raise ValueError("This filename is reserved by Windows")
    return raw+ext


def manual_repair_proposal(core: FileManagerCore, doc_id: int, company_id: int,
                           category: str, short_name: str) -> dict:
    """Safe, reversible manual classification, preserving managed contents."""
    row=core.document(int(doc_id))
    company=core.get_company(int(company_id))
    source=Path(row["absolute_path"])
    if category not in CATEGORIES or category=="Other":
        raise ValueError("Select a specific document category")
    if not source.is_file():
        raise FileNotFoundError("Managed file is missing: "+str(source))
    name=_normalize_manual_filename(short_name,source.suffix)
    return {
        "id":int(doc_id),"fingerprint":hash_file(source),
        "previous_relative_path":row["relative_path"],
        "company_id":company["id"],"company":company["name"],
        "category":category,"new_name":name,
        "old_name":row["title"],"content":row["content"] or "",
        "date":"","reference":"","label":"",
        "eligible":True,"manual_override":True,"confidence":1.0,
        "reason":"Manually confirmed by user"
    }

'''
s=s[:start]+replacement+s[end:]
p.write_text(s,encoding='utf-8')
p=root/'filemanager/gui.py'
s=p.read_text(encoding='utf-8')
old='nv.get().strip()+Path(doc["title"]).suffix.lower()'
if s.count(old)!=1:
    raise RuntimeError("Manual review save source changed unexpectedly")
s=s.replace(old,'nv.get().strip()',1)
s=s.replace('"Short filename (extension stays "+Path(doc["title"]).suffix.lower()+")"',
            '"Short filename (extension "+Path(doc["title"]).suffix.lower()+" added automatically)"',1)
p.write_text(s,encoding='utf-8')
print("v1.7 manual review filename fix applied")
