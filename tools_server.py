#!/usr/bin/env python3
"""
Keyless tool service for the Any-Model Playground.
Runs inside the codespace next to Ollama so the browser can do web search
and page reading without any API key (DuckDuckGo HTML + plain fetch).

  python3 tools_server.py 8765

Endpoints (all CORS open):
  GET /health
  GET /search?q=...&n=6      -> [{title,url,snippet}]
  GET /read?url=...&max=8000 -> {url,title,text}
"""
import html
import ipaddress
import json
import re
import socket
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def strip_tags(s: str) -> str:
    s = re.sub(r'(?is)<(script|style|noscript|svg|head)[^>]*>.*?</\1>', ' ', s)
    s = re.sub(r'(?is)<br\s*/?>', '\n', s)
    s = re.sub(r'(?is)</?(p|div|li|tr|h[1-6]|section|article)[^>]*>', '\n', s)
    s = re.sub(r'(?is)<[^>]+>', ' ', s)
    s = html.unescape(s)
    s = re.sub(r'[ \t\xa0]+', ' ', s)
    s = re.sub(r'\n\s*\n\s*\n+', '\n\n', s)
    return s.strip()


def blocked_host(host: str) -> bool:
    host = (host or '').strip().lower()
    if not host or host in ('localhost', 'metadata.google.internal'):
        return True
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return (ip.is_private or ip.is_loopback or ip.is_link_local
            or ip.is_reserved or ip.is_multicast)


def fetch(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers={
        'User-Agent': UA,
        'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5',
        'Accept-Language': 'en-US,en;q=0.9',
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read(3_000_000)
        enc = r.headers.get_content_charset() or 'utf-8'
        return raw.decode(enc, 'ignore')


def search(q: str, n: int = 6):
    out = []
    for tpl in ('https://lite.duckduckgo.com/lite/?q=',
                'https://html.duckduckgo.com/html/?q='):
        try:
            page = fetch(tpl + urllib.parse.quote(q))
        except Exception:
            continue
        if 'lite' in tpl:
            pat = (r'(?is)<a[^>]+class="result-link"[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
                   r'.*?class="result-snippet"[^>]*>(.*?)</td>')
        else:
            pat = (r'(?is)<a[^>]+class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
                   r'.*?class="result__snippet"[^>]*>(.*?)</(?:a|div)>')
        for m in re.finditer(pat, page):
            link = html.unescape(m.group(1))
            if 'uddg=' in link:
                try:
                    link = urllib.parse.unquote(
                        parse_qs(urlparse(link).query).get('uddg', [link])[0])
                except Exception:
                    pass
            title = strip_tags(m.group(2))[:180]
            snip = strip_tags(m.group(3))[:400]
            if title and link.startswith('http'):
                out.append({'title': title, 'url': link, 'snippet': snip})
            if len(out) >= n:
                break
        if out:
            break
    # de-dup by url
    seen, uniq = set(), []
    for r in out:
        if r['url'] in seen:
            continue
        seen.add(r['url'])
        uniq.append(r)
    return uniq


def read_page(url: str, max_chars: int = 8000):
    u = urlparse(url)
    if u.scheme not in ('http', 'https'):
        raise ValueError('only http/https allowed')
    if blocked_host(u.hostname or ''):
        raise ValueError('blocked host')
    page = fetch(url)
    title = ''
    m = re.search(r'(?is)<title[^>]*>(.*?)</title>', page)
    if m:
        title = strip_tags(m.group(1))[:200]
    text = strip_tags(page)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return {'url': url, 'title': title, 'text': text[:max_chars]}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,OPTIONS')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        u = urlparse(self.path)
        qs = parse_qs(u.query)
        try:
            if u.path in ('/', '/health'):
                return self._send(200, {'ok': True, 'service': 'any-model-tools'})
            if u.path == '/search':
                q = (qs.get('q') or [''])[0].strip()
                if not q:
                    return self._send(400, {'error': 'missing q'})
                n = min(int((qs.get('n') or ['6'])[0]), 10)
                return self._send(200, {'query': q, 'results': search(q, n)})
            if u.path == '/read':
                url = (qs.get('url') or [''])[0].strip()
                if not url:
                    return self._send(400, {'error': 'missing url'})
                mx = min(int((qs.get('max') or ['8000'])[0]), 20000)
                return self._send(200, read_page(url, mx))
            return self._send(404, {'error': 'unknown path'})
        except Exception as e:
            return self._send(500, {'error': str(e)})

    def log_message(self, fmt, *args):
        sys.stderr.write('%s - %s\n' % (self.address_string(), fmt % args))


if __name__ == '__main__':
    socket.setdefaulttimeout(25)
    print('tools service on http://0.0.0.0:%d' % PORT, flush=True)
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
