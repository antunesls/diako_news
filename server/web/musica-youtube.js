'use strict';

function videoYoutube(referencia) {
  let url;
  try { url = new URL(String(referencia || '').trim()); } catch (_) { return null; }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) return null;
  const partes = url.pathname.split('/').filter(Boolean);
  let id = null;
  if (url.hostname === 'youtu.be' && partes.length === 1) id = partes[0];
  if (['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'].includes(url.hostname)) {
    if (url.pathname === '/watch') id = url.searchParams.get('v');
    if (partes.length === 2 && ['shorts', 'live', 'embed'].includes(partes[0])) id = partes[1];
  }
  return /^[A-Za-z0-9_-]{11}$/.test(id || '') ? id : null;
}

function linkYoutube(referencia) {
  const id = videoYoutube(referencia);
  return id ? `https://www.youtube.com/watch?v=${id}` : null;
}

function miniaturaYoutube(referencia) {
  const id = videoYoutube(referencia);
  return id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : null;
}

if (typeof module !== 'undefined' && module.exports) module.exports = { videoYoutube, linkYoutube, miniaturaYoutube };
