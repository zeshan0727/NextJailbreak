"""v1.6: scrollable companies, unfiltered review, and per-file manual correction."""
from pathlib import Path
r=Path(__file__).resolve().parent
def put(name,fn):
 p=r/name;s=p.read_text(encoding="utf8");q=fn(s);p.write_text(q,encoding="utf8")
def one(s,a,b):
 if s.count(a)!=1: raise RuntimeError("Patch anchor missing or duplicated: "+a[:70])
 return s.replace(a,b,1)
def core(s):
 return one(s,"(SELECT COUNT(*) FROM documents d WHERE d.company_id=c.id AND d.state='filed') AS file_count","(SELECT COUNT(*) FROM documents d WHERE d.company_id=c.id) AS file_count")
put("filemanager/core.py",core)
def repair(s):
 s=one(s,'        changes = bool(dest != source or before["category"] != cat or before["company_id"] != cid or','        changes = bool(dest != source or before["state"] != "filed" or before["category"] != cat or before["company_id"] != cid or')
 s+='''
def manual_repair_proposal(core, doc_id, company_id, category, filename):
    """Manually confirmed, safe, reversible proposal for any existing document."""
    import re
    row=core.document(int(doc_id))
    company=core.get_company(int(company_id))
    source=Path(row["absolute_path"])
    if category not in CATEGORIES or category=="Other":
        raise ValueError("Select a specific document category")
    if not source.is_file(): raise FileNotFoundError(str(source))
    filename=str(filename or "").strip()
    if (not filename or filename!=Path(filename).name or
            len(Path(filename).stem)>88 or
            re.search(r'[<>:"/\\\\\\\\|?*\\\\x00-\\\\x1f]',filename)):
        raise ValueError("Enter a valid short filename")
    if Path(filename).suffix.lower()!=source.suffix.lower():
        raise ValueError("File extension must remain unchanged")
    return {
        "id":int(doc_id),"fingerprint":hash_file(source),
        "previous_relative_path":row["relative_path"],
        "company_id":company["id"],"company":company["name"],
        "category":category,"new_name":filename,
        "old_name":row["title"],"content":row["content"] or "",
        "date":"","reference":"","label":"",
        "eligible":True,"manual_override":True,"confidence":1.0,
        "reason":"Manually confirmed by user"
    }
'''
 return s
put("filemanager/repair.py",repair)
def gui(s):
 s=one(s,'from .repair import repair_proposal, apply_repair, undo_last_repair, make_repair_name','from .repair import repair_proposal, apply_repair, undo_last_repair, make_repair_name, manual_repair_proposal')
 s=one(s,'        self.context.add_command(label="AI review / fix existing", command=self.show_repair)',
       '        self.context.add_command(label="Manual review / correct", command=self.manual_review_selected)\n        self.context.add_command(label="AI review / fix existing", command=self.show_repair)')
 s=one(s,'        btn(actions, "Move to Trash", self.delete_selected, danger=True, small=True).grid(row=2, column=0, columnspan=2, sticky="ew")',
       '        btn(actions,"Manual review",self.manual_review_selected,small=True,accent=True).grid(row=2,column=0,columnspan=2,sticky="ew",pady=(0,4))\n        btn(actions, "Move to Trash", self.delete_selected, danger=True, small=True).grid(row=3, column=0, columnspan=2, sticky="ew")')
 s=one(s,'        btn(filter_bar, "Export CSV", self.export_csv, small=True).pack(side="right", padx=(6, 0))',
       '        btn(filter_bar, "Export CSV", self.export_csv, small=True).pack(side="right", padx=(6, 0))\n        btn(filter_bar,"Review selected",self.manual_review_selected,small=True).pack(side="right",padx=(6,0))')
 s=one(s,'''        if hasattr(self, "company_canvas"):
            target_height = max(85, min(260, self.winfo_height() - 490))
            if int(self.company_canvas.cget("height")) != target_height:
                self.company_canvas.configure(height=target_height)
''','')
 s=one(s,'        companyarea.pack(fill="x", padx=14, pady=(19, 0))','        companyarea.pack(fill="both", expand=True, padx=14, pady=(10, 0))')
 s=one(s,'        company_canvas = tk.Canvas(companyarea, bg=C["side"], highlightthickness=0, height=205)',
       '        company_list=tk.Frame(companyarea,bg=C["side"])\n        company_list.pack(fill="both",expand=True)\n        company_canvas = tk.Canvas(company_list, bg=C["side"], highlightthickness=0, height=250)')
 s=one(s,'        bar = ttk.Scrollbar(companyarea, orient="vertical", command=company_canvas.yview)',
       '        bar = ttk.Scrollbar(company_list, orient="vertical", command=company_canvas.yview)')
 s=one(s,'        company_canvas.configure(yscrollcommand=bar.set)',
       '''        company_canvas.configure(yscrollcommand=bar.set)
        def wheel(event):
            amount = -1 if getattr(event,"delta",0)>0 or getattr(event,"num",0)==4 else 1
            company_canvas.yview_scroll(3*amount,"units")
            return "break"
        for widget in (company_canvas,scrollable):
            for sequence in ("<MouseWheel>","<Button-4>","<Button-5>"):
                widget.bind(sequence,wheel)''')
 s=one(s,'        self._nav_button(companyarea, "✎   Manage companies", self.manage_companies)',
       '''        for row in scrollable.winfo_children():
            for widget in (row,*row.winfo_children()):
                for seq in ("<MouseWheel>","<Button-4>","<Button-5>"):
                    widget.bind(seq,wheel)
        self._nav_button(companyarea, "✎   Manage companies", self.manage_companies)''')
 s=one(s,'''    def set_view(self, view):
        self.current_view = view
        self.active_company = None
        self._refresh()

    def set_company(self, company_id):
        self.active_company = company_id
        self.current_view = "company"
        self._refresh()
''','''    def _clear_navigation_filters(self):
        self.ai_search_payload=None
        self.placeholder_active=False
        self.search_var.set("")
        self._show_placeholder()

    def set_view(self, view):
        self._clear_navigation_filters()
        self.current_view=view
        self.active_company=None
        self._refresh()

    def set_company(self, company_id):
        self._clear_navigation_filters()
        self.active_company=company_id
        self.current_view="company"
        self._refresh()
''')
 s=one(s,'''    def _schedule_search(self, *_):
        self.ai_search_payload = None
        self.repair_window = None
        self.repair_proposals = {}
''','''    def _schedule_search(self, *_):
        self.ai_search_payload = None
''')
 s=one(s,'LOCAL STORAGE  •  v1.4 AI REPAIR','LOCAL STORAGE  •  v1.6 MANUAL REVIEW')
 insert='''
    def manual_review_selected(self):
        """Edit one existing document without AI, re-uploading or deleting it."""
        if self.busy:
            messagebox.showinfo("Busy","Finish the current import or AI review first.")
            return
        doc=self.selected_doc()
        if not doc:return
        companies=self.core.companies()
        if not companies:
            messagebox.showinfo("Companies","Add a company first.")
            return
        win=self._dialog("Manual review - "+doc["title"][:50],610,475)
        text(win,"Review document",size=17,weight="bold",bg="panel").pack(anchor="w",padx=20,pady=(16,5))
        text(win,"Correct the company, document type and short filename; no re-upload needed.",
             size=9,color="sub",bg="panel").pack(anchor="w",padx=20,pady=(0,14))
        text(win,"Current: "+doc["title"],size=9,color="sub",bg="panel",
             wraplength=550,justify="left").pack(anchor="w",padx=20,pady=(0,10))
        names=[c["name"] for c in companies]
        cv=tk.StringVar(value=doc["company_name"] if doc["company_name"] in names else "")
        tv=tk.StringVar(value=doc["category"])
        nv=tk.StringVar(value=Path(doc["title"]).stem)
        text(win,"Company",size=9,bg="panel").pack(anchor="w",padx=20)
        ttk.Combobox(win,textvariable=cv,values=names,state="readonly").pack(fill="x",padx=20,pady=(2,10))
        text(win,"Document category",size=9,bg="panel").pack(anchor="w",padx=20)
        ttk.Combobox(win,textvariable=tv,values=list(CATEGORIES),state="readonly").pack(fill="x",padx=20,pady=(2,10))
        text(win,"Short filename (extension stays "+Path(doc["title"]).suffix.lower()+")",
             size=9,bg="panel").pack(anchor="w",padx=20)
        tk.Entry(win,textvariable=nv,bg=C["surface2"],fg=C["text"],
                 font=(FONT,10),relief="flat").pack(fill="x",padx=20,ipady=6,pady=(3,10))
        text(win,"Original filename: "+(doc["original_name"] or doc["title"]),
             size=9,color="muted",bg="panel",wraplength=550,justify="left").pack(anchor="w",padx=20)
        text(win,"Saved changes can be reversed using Undo last AI repair.",
             size=9,color="sub",bg="panel").pack(anchor="w",padx=20,pady=(9,5))
        foot=tk.Frame(win,bg=C["panel"])
        foot.pack(fill="x",padx=20,pady=(16,0))
        btn(foot,"Cancel",win.destroy,small=True).pack(side="left")
        def save():
            if cv.get() not in names:
                messagebox.showwarning("Choose company","Select a company.",parent=win);return
            if tv.get()=="Other":
                messagebox.showwarning("Choose category","Select a specific category.",parent=win);return
            cid=next(c["id"] for c in companies if c["name"]==cv.get())
            try:
                p=manual_repair_proposal(self.core,doc["id"],cid,tv.get(),
                                          nv.get().strip()+Path(doc["title"]).suffix.lower())
                result=apply_repair(self.core,p,approve_uncertain=True)
                win.destroy()
                self._refresh()
                if self.tree.exists(str(doc["id"])):
                    self.tree.selection_set(str(doc["id"]))
                    self.tree.see(str(doc["id"]))
                self.status_label.configure(text="Manual review saved: "+result["name"],fg=C["aqua"])
            except Exception as exc:
                messagebox.showerror("Review failed",str(exc),parent=win)
        btn(foot,"Save review",save,small=True,accent=True).pack(side="right")

'''
 s=one(s,'    def show_repair(self):\n',insert+'    def show_repair(self):\n')
 return s
put("filemanager/gui.py",gui)
print("v1.6 applied")
