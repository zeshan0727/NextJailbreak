// Source-verified historical manager-report snapshot explorer; no recomputation.
export const REPORT_JS=String.raw`(function () {
  "use strict";
  const fmt=new Intl.NumberFormat("en-QA",{minimumFractionDigits:2,maximumFractionDigits:2});
  const formatAmount=v=>v==null?"—":Number.isFinite(Number(v))?fmt.format(Number(v)):"Invalid source amount";
  function node(tag,value,css){
    const el=document.createElement(tag);
    if(value!==undefined && value!==null)el.textContent=String(value);
    if(css)el.className=css;
    return el;
  }
  async function request(url){
    const result=await fetch(url,{credentials:"same-origin",cache:"no-store"});
    const body=await result.json().catch(()=>({}));
    if(!result.ok)throw Error(body.error||"Private report data could not be loaded.");
    return body;
  }
  function table(headers,entries){
    const scroll=node("div",null,"data-scroll"),tbl=node("table");
    const th=node("thead"),row=node("tr");
    headers.forEach(h=>row.append(node("th",h)));th.append(row);
    const tbody=node("tbody");
    entries.forEach(cells=>{
      const tr=node("tr");cells.forEach(v=>tr.append(node("td",v==null?"—":v)));
      tbody.append(tr);
    });
    tbl.append(th,tbody);scroll.append(tbl);return scroll;
  }
  function miniButton(text,click){
    const b=node("button",text,"outline-button");
    b.type="button";b.onclick=click;return b;
  }
  function panel(title,description){
    const p=node("section",null,"panel");
    p.append(node("h2",title),node("p",description));
    return p;
  }
  window.renderManagerLedger=async function(container,entityId){
    const source=panel("Original manager-report trial balance snapshots",
      "View Windows V6 account rows exactly as migrated. These are historical source snapshots, NOT a newly calculated Balance Sheet or Income Statement.");
    const picker=node("select");picker.setAttribute("aria-label","Choose historical snapshot");
    picker.className="report-snapshot-select";
    const metrics=node("div",null,"report-snapshot-meta");
    const accountArea=node("div","Select a snapshot to inspect its account rows.","empty");
    const pager=node("div",null,"row-actions");
    const mappingArea=panel("Original Windows report line mappings",
      "These mappings were imported from V6. Unmapped accounts and sign/period conventions must be resolved before generating a certified financial statement.");
    const mappingGrid=node("div","Reading original report mappings…","loading");
    const mapPager=node("div",null,"row-actions");
    mappingArea.append(mappingGrid,mapPager);
    source.append(picker,metrics,accountArea,pager);
    container.append(source,mappingArea);

    const token=String(entityId);
    const valid=()=>String(document.getElementById("entity-picker")?.value)===token;
    const base="/api/web/report-accounts?entityId="+encodeURIComponent(token);
    let currentSnapshot=null;
    async function loadAccounts(page){
      if(!valid()||!currentSnapshot)return;
      accountArea.replaceChildren(node("div","Loading source account lines…","loading"));
      pager.replaceChildren();
      try{
        const d=await request(base+"&snapshotId="+encodeURIComponent(currentSnapshot)+"&page="+page);
        if(!valid()||currentSnapshot!==d.snapshot.SnapshotId)return;
        metrics.replaceChildren(
          node("span","Snapshot date: "+(d.snapshot.SnapshotDate||"Unknown"),"pill"),
          node("span","Accounts: "+d.total,"pill"),
          node("span","Source balanced flag: "+(d.snapshot.Balanced===1?"Yes":d.snapshot.Balanced===0?"No":"Unspecified"),"pill"),
          node("span","Unmapped: "+(d.snapshot.UnmappedCount??"Unknown"),"pill"),
          node("span","Final locked: "+(d.snapshot.FinalLocked===1?"Yes":"No / unknown"),"pill")
        );
        accountArea.replaceChildren(d.rows.length?
          table(["Account code","Account name","Account type","Element","Debit YTD","Credit YTD","Current balance"],
            d.rows.map(x=>[x.AccountCode,x.AccountName,x.AccountType,x.Element,
              formatAmount(x.DebitYtd),formatAmount(x.CreditYtd),
              formatAmount(x.CurrentBalance)])):
          node("div","No source-account rows in this snapshot.","empty"));
        const prev=miniButton("Previous",()=>loadAccounts(page-1));
        prev.disabled=page===0;
        const next=miniButton("Next",()=>loadAccounts(page+1));
        next.disabled=(page+1)*d.pageSize>=d.total;
        pager.replaceChildren(prev,node("span",d.total+" accounts · page "+(page+1),"muted"),next);
      }catch(e){if(valid())accountArea.replaceChildren(node("div",e.message,"empty"));}
    }
    async function loadMappings(page){
      if(!valid())return;
      try{
        const d=await request("/api/web/report-mappings?entityId="+encodeURIComponent(token)+"&page="+page);
        if(!valid())return;
        mappingGrid.replaceChildren(d.rows.length?
          table(["Account code","Account","Source type","Statement type","Template code","Template row","Sub-mapping"],
            d.rows.map(x=>[x.AccountCode,x.AccountName,x.SourceType,x.StatementType,x.TemplateCode,x.TemplateRow,x.SubMapping])):
          node("div","No source mapping rows were imported for this company.","empty"));
        const prev=miniButton("Previous",()=>loadMappings(page-1));prev.disabled=page===0;
        const next=miniButton("Next",()=>loadMappings(page+1));next.disabled=(page+1)*d.pageSize>=d.total;
        mapPager.replaceChildren(prev,node("span",d.total+" mappings · page "+(page+1),"muted"),next);
      }catch(e){if(valid())mappingGrid.replaceChildren(node("div",e.message,"empty"));}
    }
    try{
      const snapshots=await request("/api/web/report-snapshots?entityId="+encodeURIComponent(token));
      if(!valid())return;
      picker.replaceChildren();
      if(!snapshots.snapshots?.length){
        picker.disabled=true;
        picker.append(node("option","No historical report snapshots"));
        accountArea.replaceChildren(node("div","No historical trial-balance snapshot was found for this company.","empty"));
      }else{
        snapshots.snapshots.forEach(s=>{
          const option=node("option",(s.SnapshotDate||"Undated")+" · "+(s.Company||"Company")+" · v"+(s.Version??"?"));
          option.value=s.SnapshotId;picker.append(option);
        });
        currentSnapshot=picker.value;
        picker.onchange=()=>{currentSnapshot=picker.value;loadAccounts(0);};
        await loadAccounts(0);
      }
    }catch(e){
      picker.disabled=true;picker.replaceChildren();
      accountArea.replaceChildren(node("div",e.message,"empty"));
    }
    await loadMappings(0);
  };
})();`;
