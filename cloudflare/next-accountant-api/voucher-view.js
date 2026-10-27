// Next Accountant private staging draft voucher screens.
// All user text is inserted through textContent, never HTML templates.
export const DRAFT_JS = String.raw`(function () {
  "use strict";
  const money=n=>new Intl.NumberFormat("en-QA",{
    style:"currency",currency:"QAR"
  }).format(Number(n||0)/100);
  function node(tag,text,cls){
    const v=document.createElement(tag);
    if(text!==undefined&&text!==null)v.textContent=String(text);
    if(cls)v.className=cls;
    return v;
  }
  function label(title,control){
    const l=node("label",null,"field-label");
    l.append(node("span",title),control);
    return l;
  }
  function field(placeholder,required=false){
    const v=document.createElement("input");
    v.placeholder=placeholder;
    v.required=required;
    v.maxLength=160;
    v.className="draft-input";
    return v;
  }
  function table(headers,items){
    const scroll=node("div",null,"data-scroll"),t=node("table");
    const hd=node("thead"),tr=node("tr");
    headers.forEach(x=>tr.append(node("th",x)));hd.append(tr);
    const body=node("tbody");
    items.forEach(c=>body.append(c));
    t.append(hd,body);scroll.append(t);return scroll;
  }
  async function jsonFetch(path,options={}){
    const r=await fetch(path,{credentials:"same-origin",cache:"no-store",...options});
    const v=await r.json().catch(()=>({error:"Cannot read server response."}));
    if(!r.ok)throw Error(v.error||"Private staging request rejected.");
    return v;
  }
  window.renderVoucherDrafts=async function(container,entityId){
    container.replaceChildren();
    const header=node("section",null,"panel");
    header.append(node("h2","Voucher drafts · PV / RV"));
    header.append(node("p","Drafts are private staging records only. They are NOT entered into the Windows ledger, assigned official voucher numbers or included in financial statements."));
    const form=node("form",null,"draft-form");
    const grid=node("div",null,"draft-form-grid");
    const kind=node("select");[["PV","Payment voucher"],["RV","Receipt voucher"]].forEach(([id,txt])=>{
      const o=node("option",txt);o.value=id;kind.append(o);
    });
    const date=field("",true);date.type="date";date.value=new Date().toISOString().slice(0,10);
    const currency=node("select");["QAR","USD","EUR","GBP","AED","PKR","JPY"].forEach(k=>{
      const o=node("option",k);o.value=k;currency.append(o);
    });
    const value=field("0.00",true);value.type="number";value.min="0.01";value.max="1000000000";value.step="0.01";
    const party=field("Counterparty or employee",true);
    const reference=field("Optional reference");
    const description=document.createElement("textarea");
    description.className="draft-input";description.rows=3;description.maxLength=1200;
    description.placeholder="Purpose / explanation";
    const documentInput=field("");
    documentInput.type="file";documentInput.required=false;
    documentInput.accept=".pdf,.jpg,.jpeg,.png,.heic,.heif,.webp,application/pdf,image/*";
    const uploadNote=node("div","Optional: choose a photo, use your phone camera or attach an existing PDF. Maximum 12 MB.","muted");
    grid.append(
      label("Voucher type",kind),label("Date",date),
      label("Currency",currency),label("Amount",value),
      label("Counterparty",party),label("Reference",reference),
      label("Description",description),label("Proof / scanned document",documentInput)
    );
    const feedback=node("div","","draft-feedback");feedback.setAttribute("role","status");
    const save=node("button","Save draft only");save.type="submit";save.className="draft-submit";
    form.append(grid,uploadNote,save,feedback);
    header.append(form);
    const records=node("section",null,"panel");
    records.append(node("h2","Saved staging drafts"));
    const list=node("div","Retrieving drafts…","loading");records.append(list);
    container.append(header,records);
    async function reload(){
      try{
        const data=await jsonFetch("/api/web/drafts?entityId="+encodeURIComponent(entityId));
        list.replaceChildren();
        if(!data.records?.length){
          list.append(node("div","No draft vouchers for this company.","empty"));return;
        }
        const rows=data.records.map(d=>{
          const tr=node("tr");
          const cols=[d.TransactionDate,d.Kind,d.Counterparty,money(d.AmountMinor),
            d.Reference||"—",d.Status];
          cols.forEach(x=>tr.append(node("td",x)));
          const docCell=node("td");
          if(d.AttachmentName){
            const a=node("a","View attachment");a.href="/api/web/drafts/"+encodeURIComponent(d.Id)+"/document";
            a.target="_blank";a.rel="noopener noreferrer";a.className="draft-link";
            docCell.append(a);
          }else docCell.textContent="—";
          tr.append(docCell);return tr;
        });
        list.append(table(["Date","Type","Counterparty","Amount (QAR units)","Reference","Status","Document"],rows));
      }catch(e){list.replaceChildren(node("div",e.message,"empty"));}
    }
    form.onsubmit=async e=>{
      e.preventDefault();
      const val=Number(value.value);
      const minor=Math.round(val*100);
      if(!Number.isFinite(val)||val<=0 || Math.abs(minor/100-val)>0.0000001){
        feedback.textContent="Enter a valid monetary amount with a maximum of two decimals.";return;
      }
      const file=documentInput.files?.[0]||null;
      if(file && file.size>12*1024*1024){
        feedback.textContent="Document exceeds the 12 MB upload limit.";return;
      }
      save.disabled=true;feedback.textContent="Saving private staging draft…";
      try{
        const d=await jsonFetch("/api/web/drafts",{
          method:"POST",headers:{"Content-Type":"application/json"},
          body:JSON.stringify({entityId:Number(entityId),kind:kind.value,date:date.value,
            currency:currency.value,amountMinor:minor,counterparty:party.value,
            reference:reference.value,narrative:description.value})
        });
        feedback.textContent="Draft created. It is not posted to the ledger.";
        if(file){
          let fileType=file.type||"application/octet-stream";
          if(!fileType || fileType==="application/octet-stream"){
            const ext=file.name.split(".").pop()?.toLowerCase();
            fileType=({pdf:"application/pdf",jpg:"image/jpeg",jpeg:"image/jpeg",
              png:"image/png",heic:"image/heic",heif:"image/heif",webp:"image/webp"})[ext]||
              "application/octet-stream";
          }
          const upload=await fetch("/api/web/drafts/"+encodeURIComponent(d.id)+"/document",{
            method:"PUT",credentials:"same-origin",cache:"no-store",
            headers:{"Content-Type":fileType,"X-File-Name-Encoded":encodeURIComponent(file.name)},
            body:file
          });
          if(!upload.ok){
            const body=await upload.json().catch(()=>({}));
            throw Error("Draft saved, but document upload failed: "+(body.error||upload.status));
          }
          feedback.textContent="Draft and document saved securely. Not posted to Windows.";
        }
        form.reset();date.value=new Date().toISOString().slice(0,10);
        await reload();
      }catch(error){feedback.textContent=error.message||"Unable to save draft.";}
      finally{save.disabled=false;}
    };
    await reload();
  };
})();`;
