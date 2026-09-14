/* Next Jailbreak — live article/category renderer */
(function () {
  'use strict';

  var path = window.location.pathname || '/';
  var isHome = path === '/' || path === '/index.html';
  var isTutorials = path === '/tutorials/' || path === '/tutorials' || path === '/tutorials.html';
  if (!isHome && !isTutorials) return;

  var HOME_FALLBACK_IMAGE = '/assets/brand/next-jailbreak-social-card.png';
  var HOME_PAGE_SIZE = 8;
  var homeEntries = [];
  var homePage = 1;
  var homePinnedCard = null;
  var TWEAKS_START = 'AUTO_ARTICLES_TUTORIALS_START';
  var TWEAKS_END = 'AUTO_ARTICLES_TUTORIALS_END';
  var JAILBREAK_START = 'AUTO_ARTICLES_JAILBREAK_START';
  var JAILBREAK_END = 'AUTO_ARTICLES_JAILBREAK_END';

  function text(value) {
    return String(value == null ? '' : value);
  }

  function categoryId(entry) {
    var category = entry && entry.category;
    return category && typeof category === 'object' ? text(category.id).trim().toLowerCase() : '';
  }

  function categoryLabel(entry) {
    var category = entry && entry.category;
    return category && typeof category === 'object' && category.label ? text(category.label) : 'Tweak';
  }

  function isJailbreak(entry) {
    return categoryId(entry) === 'jailbreak' || categoryLabel(entry).trim().toLowerCase() === 'jailbreak';
  }

  function cleanHref(value) {
    var href = text(value).trim();
    if (!href) return '/';
    if (/^https?:\/\//i.test(href) || href.charAt(0) === '/' || href.charAt(0) === '#') return href;
    return '/' + href.replace(/^\/+/, '');
  }

  function cleanImage(value) {
    var image = text(value).trim();
    if (!image) return HOME_FALLBACK_IMAGE;
    if (/^https?:\/\//i.test(image) || image.charAt(0) === '/') return image;
    return '/' + image.replace(/^\/+/, '');
  }

  function timestamp(entry) {
    return Date.parse(text(entry.modified_at || entry.published_at || '')) || 0;
  }

  function orderedEntries(entries) {
    return entries.filter(function (entry) {
      return entry && typeof entry === 'object' && entry.href;
    }).sort(function (a, b) {
      return timestamp(b) - timestamp(a);
    });
  }

  function installHomePolish() {
    if (!isHome) return;
    if (!document.getElementById('ns-home-polish')) {
      var style = document.createElement('style');
      style.id = 'ns-home-polish';
      style.textContent = '.editorial-hero.editorial-hero-clean{min-height:0;grid-template-columns:minmax(0,1fr);padding:clamp(48px,7vw,86px);background:radial-gradient(circle at 88% 18%,rgba(255,255,255,.88),transparent 30%),linear-gradient(120deg,#f8faff 0%,#e8edff 54%,#eee5ff 100%)}.editorial-hero.editorial-hero-clean .hero-copy{max-width:930px}.editorial-hero.editorial-hero-clean .hero-copy h1{max-width:900px}.editorial-hero.editorial-hero-clean .hero-copy>p{max-width:760px}.ns-latest-pagination{display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:8px;margin-top:18px;padding:18px;border:1px solid var(--line);border-radius:18px;background:rgba(255,255,255,.82)}.ns-latest-pagination-label{width:100%;margin:0 0 4px;text-align:center;color:var(--muted);font-size:.78rem;font-weight:800;letter-spacing:.02em}.ns-page-button{min-width:42px;height:42px;display:inline-flex;align-items:center;justify-content:center;padding:0 13px;border:1px solid var(--line-dark);border-radius:999px;background:#fff;color:var(--ink);font:800 .82rem/1 inherit;cursor:pointer;transition:transform .18s ease,background .18s ease,border-color .18s ease}.ns-page-button:hover{transform:translateY(-1px);border-color:var(--ink)}.ns-page-button[aria-current="page"]{border-color:var(--ink);background:var(--ink);color:#fff}.ns-page-button:disabled{opacity:.42;cursor:not-allowed;transform:none}.ns-page-ellipsis{padding:0 3px;color:var(--quiet);font-weight:900}@media(max-width:720px){.editorial-hero.editorial-hero-clean{padding:38px 24px;border-radius:24px;margin-top:18px}.editorial-hero.editorial-hero-clean .hero-copy h1{font-size:clamp(2.65rem,13vw,4rem)}.ns-latest-pagination{padding:15px 10px;gap:6px}.ns-page-button{min-width:38px;height:38px;padding:0 10px;font-size:.76rem}}';
      document.head.appendChild(style);
    }
  }

  function createCard(entry, eager) {
    var article = document.createElement('article');
    article.className = 'content-card has-visual';
    article.setAttribute('data-runtime-entry', text(entry.href));
    var meta = document.createElement('div'); meta.className = 'card-meta';
    var category = document.createElement('span'); category.className = 'tag'; category.textContent = categoryLabel(entry); meta.appendChild(category);
    var source = document.createElement('span'); source.className = 'tag'; source.textContent = text(entry.source_name || 'Next Jailbreak'); meta.appendChild(source); article.appendChild(meta);
    var href = cleanHref(entry.href);
    var link = document.createElement('a'); link.className = 'card-media'; link.href = href; link.setAttribute('aria-label', 'Open ' + text(entry.title || entry.name || 'article'));
    var image = document.createElement('img'); image.src = cleanImage(entry.image); image.alt = text(entry.title || entry.name || 'Next Jailbreak article'); image.width = 1600; image.height = 900; image.loading = eager ? 'eager' : 'lazy'; image.addEventListener('error', function () { if (image.src.indexOf(HOME_FALLBACK_IMAGE) === -1) image.src = HOME_FALLBACK_IMAGE; }, { once: true }); link.appendChild(image); article.appendChild(link);
    var title = document.createElement('h3'); title.textContent = text(entry.title || entry.name || 'Next Jailbreak article'); article.appendChild(title);
    var description = document.createElement('p'); description.textContent = text(entry.description || 'Read the full article for details, compatibility notes, and source information.'); article.appendChild(description);
    var read = document.createElement('a'); read.className = 'card-link'; read.href = href; read.textContent = 'Read article →'; article.appendChild(read);
    return article;
  }

  function removeRuntimeCards(container) { if (!container) return; Array.prototype.forEach.call(container.querySelectorAll('[data-runtime-entry]'), function (node) { node.remove(); }); }
  function removeMarkerBlock(container, startLabel, endLabel) { if (!container) return; var nodes = Array.prototype.slice.call(container.childNodes); var removing = false; nodes.forEach(function (node) { if (node.nodeType === Node.COMMENT_NODE && text(node.nodeValue).indexOf(startLabel) !== -1) { removing = true; return; } if (node.nodeType === Node.COMMENT_NODE && text(node.nodeValue).indexOf(endLabel) !== -1) { removing = false; return; } if (removing) node.remove(); }); }
  function updateCategoryLabels() { Array.prototype.forEach.call(document.querySelectorAll('.nav-links a, .category-rail a, .category-list a'), function (link) { var label = link.textContent.trim(); if (label === 'Cydia Tweaks' || label === 'Latest tweaks') link.textContent = 'Tweaks'; if (label === 'Latest tweak information') link.textContent = 'Tweaks & tweak articles'; if (label === 'Jailbreak tutorials' || label === 'Jailbreak guides') link.textContent = 'Jailbreak news & guides'; }); }
  function pageButton(label, page, currentPage, maxPage, disabled, ariaLabel) { var button = document.createElement('button'); button.type='button'; button.className='ns-page-button'; button.textContent=label; button.disabled=!!disabled; if (ariaLabel) button.setAttribute('aria-label',ariaLabel); if (page===currentPage&&!disabled) button.setAttribute('aria-current','page'); if (!disabled) button.addEventListener('click',function(){ homePage=Math.max(1,Math.min(maxPage,page)); renderHome(homeEntries,homePage); var latest=document.getElementById('latest'); if(latest) latest.scrollIntoView({behavior:'smooth',block:'start'});}); return button; }
  function paginationPages(currentPage,maxPage){ if(maxPage<=7){var all=[];for(var p=1;p<=maxPage;p+=1)all.push(p);return all;} var pages=[1];var start=Math.max(2,currentPage-1);var end=Math.min(maxPage-1,currentPage+1);if(start>2)pages.push('ellipsis');for(var i=start;i<=end;i+=1)pages.push(i);if(end<maxPage-1)pages.push('ellipsis');pages.push(maxPage);return pages; }
  function renderPagination(feed,currentPage,maxPage){ if(maxPage<=1)return; var nav=document.createElement('nav');nav.className='ns-latest-pagination';nav.setAttribute('aria-label','Latest article pages');var label=document.createElement('p');label.className='ns-latest-pagination-label';label.textContent='See more articles';nav.appendChild(label);nav.appendChild(pageButton('Previous',currentPage-1,currentPage,maxPage,currentPage===1,'Previous article page'));paginationPages(currentPage,maxPage).forEach(function(page){if(page==='ellipsis'){var ellipsis=document.createElement('span');ellipsis.className='ns-page-ellipsis';ellipsis.textContent='…';ellipsis.setAttribute('aria-hidden','true');nav.appendChild(ellipsis);}else{nav.appendChild(pageButton(String(page),page,currentPage,maxPage,false,'Article page '+page));}});nav.appendChild(pageButton('Next',currentPage+1,currentPage,maxPage,currentPage===maxPage,'Next article page'));feed.appendChild(nav); }
  function renderHome(entries,requestedPage){ var feed=document.querySelector('#latest .news-feed');if(!feed)return;homeEntries=orderedEntries(entries);var maxPage=Math.max(1,Math.ceil(homeEntries.length/HOME_PAGE_SIZE));homePage=Math.max(1,Math.min(maxPage,requestedPage||homePage||1));var start=(homePage-1)*HOME_PAGE_SIZE;var current=homeEntries.slice(start,start+HOME_PAGE_SIZE);if(!homePinnedCard){var staticPinned=feed.querySelector('.content-card.featured');if(staticPinned)homePinnedCard=staticPinned.cloneNode(true);}feed.innerHTML='';if(homePage===1&&homePinnedCard)feed.appendChild(homePinnedCard.cloneNode(true));current.forEach(function(entry,index){feed.appendChild(createCard(entry,homePage===1&&index<2));});renderPagination(feed,homePage,maxPage); }
  function renderTutorials(entries){ var ordered=orderedEntries(entries);var tweakEntries=ordered.filter(function(entry){return !isJailbreak(entry);});var jailbreakEntries=ordered.filter(isJailbreak);var tweakGrid=document.querySelector('#verified-articles .archive-cards');if(tweakGrid){removeRuntimeCards(tweakGrid);removeMarkerBlock(tweakGrid,TWEAKS_START,TWEAKS_END);var featured=tweakGrid.querySelector('.content-card.featured');var insertAfter=featured;tweakEntries.forEach(function(entry){var card=createCard(entry,false);if(insertAfter&&insertAfter.parentNode===tweakGrid){insertAfter.insertAdjacentElement('afterend',card);insertAfter=card;}else{tweakGrid.appendChild(card);insertAfter=card;}});}var jailbreakGrid=document.querySelector('#jailbreak-guides .guide-card-grid');if(jailbreakGrid){removeRuntimeCards(jailbreakGrid);removeMarkerBlock(jailbreakGrid,JAILBREAK_START,JAILBREAK_END);var firstStatic=jailbreakGrid.firstElementChild;jailbreakEntries.forEach(function(entry){var card=createCard(entry,false);if(firstStatic)jailbreakGrid.insertBefore(card,firstStatic);else jailbreakGrid.appendChild(card);});}var tweakHeading=document.querySelector('#verified-articles h2');if(tweakHeading)tweakHeading.textContent='Tweaks & tweak articles';var jailbreakHeading=document.querySelector('#jailbreak-guides h2');if(jailbreakHeading)jailbreakHeading.textContent='Jailbreak news & guides'; }
  function init(){installHomePolish();updateCategoryLabels();fetch('/automation/published-articles.json?ts='+Date.now(),{cache:'no-store'}).then(function(response){if(!response.ok)throw new Error('article index request failed');return response.json();}).then(function(data){var entries=data&&Array.isArray(data.entries)?data.entries:[];if(!entries.length)return;if(isHome)renderHome(entries,1);if(isTutorials)renderTutorials(entries);}).catch(function(){});}
  if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',init,{once:true});}else{init();}
}());
