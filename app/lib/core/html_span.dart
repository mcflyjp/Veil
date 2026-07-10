import 'package:flutter/material.dart';

/// Parses a small subset of Matrix/AIM HTML into InlineSpans for RichText.
/// Supported tags: b, i, u, font (face/data-pt attributes), br, and HTML entities.
List<InlineSpan> htmlToSpans(String html, TextStyle base) {
  final out = <InlineSpan>[];
  _parse(html, base, out);
  return out;
}

void _parse(String html, TextStyle style, List<InlineSpan> out) {
  int i = 0;
  while (i < html.length) {
    if (html[i] != '<') {
      // Text node
      final next = html.indexOf('<', i);
      final raw = next == -1 ? html.substring(i) : html.substring(i, next);
      if (raw.isNotEmpty) out.add(TextSpan(text: _ent(raw), style: style));
      i = next == -1 ? html.length : next;
      continue;
    }

    final close = html.indexOf('>', i);
    if (close == -1) { out.add(TextSpan(text: html.substring(i), style: style)); break; }

    final tag = html.substring(i + 1, close).trim();

    // Self-closing / void
    if (tag.toLowerCase() == 'br' || tag.toLowerCase() == 'br/') {
      out.add(TextSpan(text: '\n', style: style));
      i = close + 1;
      continue;
    }

    // Closing tag — return to caller
    if (tag.startsWith('/')) break;

    final tagName = tag.split(RegExp(r'[\s/]'))[0].toLowerCase();
    final innerStart = close + 1;
    final innerEnd = _findClose(html, innerStart, tagName);

    if (innerEnd == -1) { i = close + 1; continue; }

    final inner = html.substring(innerStart, innerEnd);
    final TextStyle nextStyle;

    switch (tagName) {
      case 'b': case 'strong':
        nextStyle = style.copyWith(fontWeight: FontWeight.bold);
      case 'i': case 'em':
        nextStyle = style.copyWith(fontStyle: FontStyle.italic);
      case 'u':
        nextStyle = style.copyWith(decoration: TextDecoration.underline);
      case 'font':
        final face = _attr(tag, 'face');
        // data-pt is Veil-specific; also check standard CSS style attribute
        final pt = double.tryParse(_attr(tag, 'data-pt') ?? '')
            ?? _parseFontSizePt(_attr(tag, 'style') ?? '');
        nextStyle = style.copyWith(
          fontFamily: (face != null && face.isNotEmpty) ? face : style.fontFamily,
          fontSize:   pt ?? style.fontSize,
        );
      default:
        nextStyle = style;
    }

    _parse(inner, nextStyle, out);
    i = innerEnd + '</$tagName>'.length;
  }
}

/// Finds the matching closing tag for [tagName] in [html] starting at [from],
/// accounting for nesting. Strips the leading '/' before name extraction so
/// '/b'.split(...)[0] gives 'b' not '' (the original bug that broke all HTML tags).
int _findClose(String html, int from, String tagName) {
  int depth = 0, i = from;
  while (i < html.length) {
    if (html[i] != '<') { i++; continue; }
    final end = html.indexOf('>', i);
    if (end == -1) return -1;
    final tag = html.substring(i + 1, end).trim();
    final isClose = tag.startsWith('/');
    final rawName = isClose ? tag.substring(1) : tag;
    final name = rawName.split(RegExp(r'[\s/]'))[0].toLowerCase();
    if (isClose && name == tagName) {
      if (depth == 0) return i;
      depth--;
    } else if (!isClose && name == tagName && !tag.endsWith('/')) {
      depth++;
    }
    i = end + 1;
  }
  return -1;
}

String? _attr(String tag, String name) =>
    RegExp('$name=["\']([^"\']*)["\']', caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);

/// Extracts the numeric pt value from a CSS style string like "font-size:18pt".
double? _parseFontSizePt(String style) {
  final m = RegExp(r'font-size\s*:\s*([\d.]+)pt', caseSensitive: false)
      .firstMatch(style);
  return m != null ? double.tryParse(m.group(1)!) : null;
}

String _ent(String s) => s
    .replaceAll('&amp;',  '&')
    .replaceAll('&lt;',   '<')
    .replaceAll('&gt;',   '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;',  "'")
    .replaceAll('&nbsp;', ' ');
