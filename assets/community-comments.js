(() => {
  'use strict';

  const section = document.querySelector('[data-nj-comments]');
  if (!section) return;

  const apiBase = (section.dataset.commentsApi || 'https://comments.nextjailbreak.com').replace(/\/$/, '');
  const list = section.querySelector('[data-comment-list]');
  const status = section.querySelector('[data-comment-status]');
  const form = section.querySelector('[data-comment-form]');
  const count = section.querySelector('[data-comment-count]');
  const slug = new URL(document.querySelector('link[rel="canonical"]')?.href || location.href).pathname.replace(/\/index\.html$/i, '/');

  const setStatus = (message, tone = '') => {
    if (!status) return;
    status.textContent = message;
    status.dataset.tone = tone;
  };

  const formatDate = (value) => {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return new Intl.DateTimeFormat(undefined, {
      year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
    }).format(date);
  };

  const renderComments = (items) => {
    if (!list) return;
    list.replaceChildren();
    if (count) count.textContent = String(items.length);
    if (!items.length) {
      const empty = document.createElement('p');
      empty.className = 'nj-comments-empty';
      empty.textContent = 'No comments yet. Start the discussion.';
      list.appendChild(empty);
      return;
    }
    for (const item of items) {
      const article = document.createElement('article');
      article.className = 'nj-comment';

      const head = document.createElement('div');
      head.className = 'nj-comment-head';
      const name = document.createElement('strong');
      name.textContent = item.name || 'Reader';
      const time = document.createElement('time');
      time.dateTime = item.created_at || '';
      time.textContent = formatDate(item.created_at);
      head.append(name, time);

      const body = document.createElement('p');
      body.textContent = item.body || '';
      article.append(head, body);
      list.appendChild(article);
    }
  };

  const loadComments = async () => {
    try {
      setStatus('Loading comments…');
      const response = await fetch(`${apiBase}/api/comments?slug=${encodeURIComponent(slug)}`, {
        headers: { 'Accept': 'application/json' },
        mode: 'cors'
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json();
      const items = Array.isArray(payload.comments) ? payload.comments : [];
      renderComments(items);
      setStatus(items.length ? '' : 'Be the first to comment.');
    } catch (error) {
      console.warn('Next Jailbreak comments unavailable:', error);
      setStatus('Community comments are temporarily unavailable. Please try again shortly.', 'error');
      if (form) form.querySelector('button[type="submit"]')?.setAttribute('disabled', 'disabled');
    }
  };

  if (form) {
    const savedName = localStorage.getItem('nj-comment-name');
    const nameInput = form.querySelector('input[name="name"]');
    if (savedName && nameInput) nameInput.value = savedName;

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = form.querySelector('button[type="submit"]');
      const data = new FormData(form);
      const name = String(data.get('name') || '').trim();
      const body = String(data.get('body') || '').trim();
      const website = String(data.get('website') || '').trim();
      if (name.length < 2 || body.length < 2) {
        setStatus('Enter your name and a comment before posting.', 'error');
        return;
      }
      button?.setAttribute('disabled', 'disabled');
      setStatus('Posting…');
      try {
        const response = await fetch(`${apiBase}/api/comments`, {
          method: 'POST',
          mode: 'cors',
          headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
          body: JSON.stringify({ slug, name, body, website })
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
        localStorage.setItem('nj-comment-name', name);
        form.querySelector('textarea[name="body"]').value = '';
        setStatus('Comment posted.', 'success');
        await loadComments();
      } catch (error) {
        console.warn('Comment post failed:', error);
        setStatus(error.message || 'Could not post your comment. Please try again.', 'error');
      } finally {
        button?.removeAttribute('disabled');
      }
    });
  }

  loadComments();
})();
