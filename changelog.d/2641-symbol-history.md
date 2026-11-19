### Neu
- MCP-Werkzeug `get_symbol_history`: Geschichte einer Routine, Methode oder eines Typs mit den Commits, die ihre Zeilen geändert haben, je mit Datum, Kennung, Autor, Zeilen, erster Zeile der Nachricht und Issue-Kennungen. Mit Git folgt die Suche Umbenennungen und Verschiebungen in andere Units über die Ähnlichkeit der Rümpfe; Grenzen sind `limit`, `requestTimeoutMs` und Abbruch, ohne Versionsverwaltung kommt ein Hinweis (#2641).

### Behoben
- Hotspots: Texte aus älteren Ständen (`git show`, `svn cat`) behalten kein BOM mehr am Anfang; der Trend der Komplexität fand in solchen Dateien sonst keine Routinen (#2641).
