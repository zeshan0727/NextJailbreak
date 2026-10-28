"""File Manager 1.10: safe delete/restore company and always-visible compact intake."""
from pathlib import Path
base=Path(__file__).resolve().parent

def change(s,a,b):
    if s.count(a)!=1:raise RuntimeError('Patch anchor not unique: '+a[:80])
    return s.replace(a,b,1)

p=base/'filemanager/core.py';s=p.read_text(encoding='utf-8')
s=change(s,'            self.conn.execute("CREATE INDEX IF NOT EXISTS ix_docs_company ON documents(company_id)")',
'''            if "archived_at" not in {r["name"] for r in self.conn.execute("PRAGMA table_info(companies)")}:
                self.conn.execute("ALTER TABLE companies ADD COLUMN archived_at TEXT DEFAULT NULL")
            self.conn.execute("CREATE INDEX IF NOT EXISTS ix_docs_company ON documents(company_id)")''')
s=change(s,'FROM companies c ORDER BY name COLLATE NOCASE','FROM companies c WHERE c.archived_at IS NULL ORDER BY name COLLATE NOCASE')
s=change(s,'    def add_company(self, name: str, aliases: str = "") -> int:', '''    def archived_companies(self):
        with self.lock:
            rows=self.conn.execute("""SELECT c.*,(SELECT COUNT(*) FROM documents d WHERE d.company_id=c.id) file_count
                FROM companies c WHERE archived_at IS NOT NULL ORDER BY name COLLATE NOCASE""").fetchall()
            return [dict(r) for r in rows]

    def archive_company(self, company_id):
        with self.lock,self.conn:
            row=self.conn.execute("SELECT archived_at FROM companies WHERE id=?",(int(company_id),)).fetchone()
            if row is None or row["archived_at"] is not None:raise ValueError("Company not active")
            self.conn.execute("UPDATE companies SET archived_at=CURRENT_TIMESTAMP WHERE id=?",(int(company_id),))

    def restore_company(self, company_id):
        with self.lock,self.conn:
            row=self.conn.execute("SELECT archived_at FROM companies WHERE id=?",(int(company_id),)).fetchone()
            if row is None or row["archived_at"] is None:raise ValueError("Company not archived")
            self.conn.execute("UPDATE companies SET archived_at=NULL WHERE id=?",(int(company_id),))

    def add_company(self, name: str, aliases: str = "") -> int:''')
s=change(s,'raise ValueError("This company already exists.")','raise ValueError("Company exists. Restore it in Manage companies if removed.")')
p.write_text(s,encoding='utf-8')

p=base/'filemanager/gui.py';s=p.read_text(encoding='utf-8')
s=change(s,'''        btn(header, "+ Add company", self.add_company, small=True).pack(side="right", padx=(8, 0))
        btn(header, "Import files", self.pick_files, accent=True, small=True).pack(side="right", padx=(0, 4))
        btn(header, "Open Inbox", self.open_inbox, small=True).pack(side="right", padx=(0, 5))''',
'''        btn(header, "Open Inbox", self.open_inbox, small=True).pack(side="right", padx=(0, 5))''')
s=change(s,'text(up_left, "↥  Smart intake", size=14, weight="bold", color="aqua", bg="panel")','text(up_left, "↥  Drop files here to organize", size=11, weight="bold", color="aqua", bg="panel")')
s=change(s,'"Drop files or folders anywhere in this window to import."','"Or choose Files / Folder. AI sorts files after import."')
s=change(s,'        self.drop_sub.pack(anchor="w")','        self.drop_sub.pack(anchor="w")\n        self.drop_sub.pack_forget()')
s=change(s,'up_left.pack(side="left", fill="both", expand=True, padx=15, pady=9)', 'up_left.pack(side="left", fill="both", expand=True, padx=14, pady=6)')
s=change(s,'welcome.pack(fill="x", pady=(9, 15))','welcome.pack(fill="x", pady=(3, 9))')
s=change(s,'"Find a file in seconds", size=17','"Your recent files", size=15')
s=change(s,'"Search above for a company, reference number or a few words."','"Search across all companies, or open a file below."')
s=change(s,'''        if home:
            for widget in (self.metrics,self.upload,self.filter_bar,self.content_pane):
                if widget.winfo_manager():widget.pack_forget()
            if not self.home_panel.winfo_manager():
                self.home_panel.pack(after=self.search_bar,fill="both",expand=True,
                                     padx=19,pady=(0,8))''', '''        if home:
            for widget in (self.metrics,self.filter_bar,self.content_pane):
                if widget.winfo_manager():widget.pack_forget()
            if not self.upload.winfo_manager():
                self.upload.pack(after=self.search_bar,fill="x",padx=19,pady=(0,7))
            if not self.home_panel.winfo_manager():
                self.home_panel.pack(after=self.upload,fill="both",expand=True,
                                     padx=19,pady=(0,8))''')
start=s.index('    def manage_companies(self):')
end=s.index('    def company_editor(self, company=None):',start)
s=s[:start]+'''    def manage_companies(self):
        """Delete from navigation safely; documents remain indexed and recoverable."""
        win=self._dialog("Manage companies",525,500)
        text(win,"Manage companies",size=16,weight="bold",bg="panel").pack(anchor="w",padx=20,pady=(17,6))
        text(win,"Delete hides a company, never its documents. Restore it anytime.",
             size=9,color="sub",bg="panel").pack(anchor="w",padx=20,pady=(0,12))
        listing=tk.Listbox(win,font=(FONT,11),bg=C["surface"],fg=C["text"],
                           selectbackground=C["surface2"],selectforeground=C["aqua"],
                           bd=0,highlightthickness=0,height=12)
        listing.pack(fill="both",expand=True,padx=20,pady=5)
        rows=[("active",c) for c in self.core.companies()]+[("removed",c) for c in self.core.archived_companies()]
        for state,c in rows:
            listing.insert("end",("[Removed] " if state=="removed" else "")+f"{c['name']}  ({c['file_count']} files)")
        actions=tk.Frame(win,bg=C["panel"])
        actions.pack(fill="x",padx=20,pady=(14,18))
        def selection():
            idx=listing.curselection()
            if not idx:
                messagebox.showinfo("Select company","Choose a company first.",parent=win)
                return None
            return rows[idx[0]]
        def rename():
            entry=selection()
            if not entry:return
            state,c=entry
            if state=="removed":return messagebox.showinfo("Restore first","Restore this company before editing it.",parent=win)
            win.destroy();self.company_editor(c)
        def remove():
            entry=selection()
            if not entry:return
            state,c=entry
            if state=="removed":return messagebox.showinfo("Already deleted","Use Restore to show this company again.",parent=win)
            msg=f"Delete {c['name']} from company navigation?\\n\\n{c['file_count']} indexed file(s) stay stored and searchable, without moving or deleting them. Restore anytime."
            if not messagebox.askyesno("Delete company safely",msg,parent=win):return
            try:
                self.core.archive_company(c['id']);win.destroy()
                if self.active_company==c['id']:
                    self.active_company=None;self.active_category=None;self.current_view="recent"
                self._refresh()
                self.status_label.configure(text="Company hidden. Documents preserved.",fg=C["aqua"])
            except Exception as exc:messagebox.showerror("Delete company",str(exc),parent=win)
        def restore():
            entry=selection()
            if not entry:return
            state,c=entry
            if state!="removed":return messagebox.showinfo("Already visible","This company is already active.",parent=win)
            try:
                self.core.restore_company(c['id']);win.destroy();self._refresh()
                self.status_label.configure(text="Company restored.",fg=C["aqua"])
            except Exception as exc:messagebox.showerror("Restore company",str(exc),parent=win)
        btn(actions,"Rename",rename,small=True).pack(side="left",padx=(0,5))
        btn(actions,"Delete",remove,danger=True,small=True).pack(side="left",padx=(0,5))
        btn(actions,"Restore",restore,small=True).pack(side="left")
        btn(actions,"+ Add",lambda:(win.destroy(),self.add_company()),accent=True,small=True).pack(side="right")

'''+s[end:]
p.write_text(s,encoding='utf-8')
# Explicit immediate scans must ignore filesystem clock rounding.
# Background scans retain their 3-second stability guard.
p=base/'filemanager/core.py'
s=p.read_text(encoding='utf-8')
s=change(s,'if not st.st_size or st.st_mtime>cutoff:',
         'if not st.st_size or (stable_seconds > 0 and st.st_mtime>cutoff):')
p.write_text(s,encoding='utf-8')

print('v1.10 patch applied')
