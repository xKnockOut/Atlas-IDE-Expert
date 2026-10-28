# dcc-Minimalfälle (#1328)

Kleine Konsolenprojekte, die zeigen, welche Muster Delphi annimmt. Danach
richten sich die Compilerregeln („wie Exxxx“): Was dcc übersetzt, darf Atlas
nicht als Fehler melden. Die Fälle stammen aus der Fehlalarm-Prüfung über
öffentliche Delphi-Projekte vom 28.10.2026.

Jedes Projekt wird einzeln gebaut, damit ein Fehler die übrigen Fälle nicht
verdeckt. Projekte ohne „Gegen“ sollen sauber übersetzen. Projekte mit „Gegen“
enthalten Fälle, die dcc vermutlich meldet; sie bleiben als Gegentests der
Regeln. Jede Fallzeile trägt eine Marke (`// PA1` …), die das Bauskript zu
jeder Meldung ausgibt.

```
pwsh Tools/Build-DccFaelle.ps1
```

schreibt alle dcc-Meldungen nach `Output/DccFaelle-Ergebnis.txt`.

| Projekt | Regel | Fälle |
|---|---|---|
| `DccEigenschaften` | `property-accessor-invalid` | PA1 index mit Feld hinter read, PA2 index mit Array-Element, PA3 index mit Feld hinter write, PA4 index mit Aufzählungskonstante, PA5 Klassenmethode als Getter, PA6 überladener Getter |
| `DccEigenschaftenGegen` | `property-accessor-invalid` | PG1 Klassen-Property mit Instanz-Getter, PG2 index ohne Indexparameter, PG3 keine Überladung passt, PG4 unbekanntes Feld, PG5 class var und PG6 statische Klassenmethode an einer Instanz-Property |
| `DccVarParameter` | `invalid-var-argument` | IV1 Slice eines Open Arrays an var, IV2 Slice über Typumwandlung, IV3 Slice eines statischen Arrays |
| `DccVarParameterGegen` | `invalid-var-argument` | VG1 Slice an out, VG2 Konstante an var, VG3 Ausdruck an var |
| `DccSichtbarkeit` | `inaccessible-member` | IM1/IM2 protected-Mitglieder generischer Klassen aus generischem Code einer anderen Unit, IM3 dasselbe aus nicht generischem Code, IM4 private class constructor neben TObject.Create, IM5 Klassenmethoden-Überladung in einer Klassenmethode |
| `DccSichtbarkeitGegen` | `inaccessible-member` | SG1/SG2 protected-Felder nicht generischer Klassen |
| `DccInline` | `type-restriction-violated` | TR1/TR2 echte Konstante aus dem implementation-Teil in einer Inline-Routine, TR3 typisierte Konstante, TR4 Routine, TR5 inline nur an der Implementierung, TR6 Konstruktor im Class-Helfer ruft im if, TR7 class constructor im Class-Helfer |
| `DccInlineGegen` | `type-restriction-violated` | TG1 Variable, TG2 Typ aus dem implementation-Teil, TG3 Helfer-Konstruktor ohne Aufruf |
| `DccVorwaerts` | `type-used-before-declaration` | TU1/TU2 `class of` vor der Klasse im selben type-Block |
| `DccVorwaertsGegen` | `type-used-before-declaration` | UG1 Klasse erst im nächsten type-Block |
| `DccInterfaces` | `interface-declaration-invalid` | ID1 Property im abgeleiteten Interface mit write neu, ID2 dasselbe generisch |
| `DccInterfacesGegen` | `interface-declaration-invalid` | IG1 Neudeklaration ohne Typ (E2206), IG2 neue Property mit geerbtem Getter (E2370?) |
| `DccOperatoren` | `operator-declaration-invalid` | OP1–OP4 Vergleichsoperatoren ohne Boolean-Ergebnis, OP5 Benutzung |
| `DccOperatorenGegen` | `operator-declaration-invalid` | OG1/OG2 falsche Parameterzahl |
| `DccKonstanten` | `typed-constant-modified` | TC1 `{$J+}`, TC2 `{$WRITEABLECONST ON}`, TC3 `{$J+}` aus einer Include-Datei |
| `DccKonstantenGegen` | `typed-constant-modified` | KG1 `{$J-}` |
