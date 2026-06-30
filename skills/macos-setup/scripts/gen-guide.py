#!/usr/bin/env python3
# gen-guide.py — render the bilingual offline-installer guide from offline-apps.tsv.
# Standalone (no package transfer): the guide only needs the tsv + template, so it
# can be built in ANY session and shipped to the target Mac independently of the
# (slow) disk-image transfer. Usage:
#   gen-guide.py <offline-apps.tsv> <template.html> <output.html> <host-label>
import sys, html, datetime

tsv, tpl, out, host = sys.argv[1:5]
e = html.escape
# Lucide line icons (ISC) — inlined; one per app, picked by the tsv `icon` column.
LUCIDE = {
    'camera': '<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/>',
    'file-text': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v6h6"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>',
    'repeat': '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
    'image': '<rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
    'globe': '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
    'video': '<path d="m22 8-6 4 6 4V8Z"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    'pipette': '<path d="m2 22 1-1h3l9-9"/><path d="M3 21v-3l9-9"/><path d="m15 6 3.4-3.4a2.12 2.12 0 0 1 3 3L18 9l.4.4a2.12 2.12 0 0 1-3 3l-3.8-3.8a2.12 2.12 0 0 1 3-3l.4.4Z"/>',
    'battery-charging': '<path d="M15 7h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><path d="M6 7H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h1"/><path d="m11 7-3 5h4l-3 5"/><path d="M22 11v2"/>',
    'activity': '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
}
cards = []
for raw in open(tsv, encoding='utf-8'):
    raw = raw.rstrip('\n')
    if not raw or raw.startswith('#'):
        continue
    p = raw.split('\t')
    if len(p) < 9:
        continue
    f, app, ver, cz, ce, dz, de, nz, ne = p[:9]
    icon = p[9].strip() if len(p) > 9 else ''
    icon_svg = '<svg viewBox="0 0 24 24" aria-hidden="true">%s</svg>' % LUCIDE.get(icon, '')
    cards.append(
        '<article class="card">\n'
        '  <div class="top"><span class="icon">%s</span><span class="ct"><span class="en">%s</span><span class="zh">%s</span></span></div>\n'
        '  <h3>%s <span class="ver">v%s</span></h3>\n'
        '  <p class="ds"><span class="en">%s</span><span class="zh">%s</span></p>\n'
        '  <p class="nt"><span class="en">📌 %s</span><span class="zh">📌 %s</span></p>\n'
        '  <code class="fn">%s</code>\n'
        '</article>'
        % (icon_svg, e(ce), e(cz), e(app), e(ver), e(de), e(dz), e(ne), e(nz), e(f))
    )
t = open(tpl, encoding='utf-8').read()
t = (t.replace('{{CARDS}}', '\n'.join(cards))
       .replace('{{COUNT}}', str(len(cards)))
       .replace('{{HOST}}', e(host))
       .replace('{{DATE}}', datetime.datetime.now().strftime('%Y-%m-%d %H:%M')))
open(out, 'w', encoding='utf-8').write(t)
print('guide: %s (%d cards, host=%s)' % (out, len(cards), host))
