# dcc-Minimalfälle (#1328)

Kleine Konsolenprojekte, die zeigen, welche Muster Delphi annimmt. Danach
richten sich die Compilerregeln („wie Exxxx“): Was dcc übersetzt, darf Atlas
nicht als Fehler melden. Die Fälle stammen aus der Fehlalarm-Prüfung über
öffentliche Delphi-Projekte vom 28.10.2026. Der dcc-Lauf vom 29.10.2026 hat
sie bestätigt oder verschoben: Fälle, die dcc anders bewertet hat als vermutet,
stehen jetzt im passenden Projekt und tragen eine neue Marke („vorher …“).

Jedes Projekt wird einzeln gebaut, damit ein Fehler die übrigen Fälle nicht
verdeckt. Projekte ohne „Gegen“ sollen sauber übersetzen. Projekte mit „Gegen“
enthalten Fälle, die dcc vermutlich meldet; sie bleiben als Gegentests der
Regeln. Jede Fallzeile trägt eine Marke (`// PA1` …), die das Bauskript zu
jeder Meldung ausgibt.

```
pwsh Tools/Build-DccFaelle.ps1
```

schreibt alle dcc-Meldungen nach `Output/DccFaelle-Ergebnis.txt`. Die Marke steht in der
Zeile, die dcc meldet. Das Präfix „[dcc32 …]“ übernimmt das Skript aus dem
Meldungsfenster der IDE; es steht auch bei Win64-Builds und sagt nichts über die
Plattform.

| Projekt | Regel | Fälle |
|---|---|---|
| `DccEigenschaften` | `property-accessor-invalid` | PA1 index mit Feld hinter read, PA2 index mit Array-Element, PA3 index mit Feld hinter write, PA4 index mit Aufzählungskonstante, PA5 Klassenmethode als Getter, PA6 überladener Getter |
| `DccEigenschaftenGegen` | `property-accessor-invalid` | PG1 Klassen-Property mit Instanz-Getter, PG2 index ohne Indexparameter, PG3 keine Überladung passt, PG4 unbekanntes Feld, PG5 class var und PG6 statische Klassenmethode an einer Instanz-Property |
| `DccVarParameter` | `invalid-var-argument` | IV1 Slice eines Open Arrays an var, IV2 Slice über Typumwandlung, IV3 Slice eines statischen Arrays, IV4 Slice an out (vorher VG1) |
| `DccVarParameterGegen` | `invalid-var-argument` | VG2 Konstante an var, VG3 konstanter Ausdruck an var (dcc: E2197) |
| `DccSichtbarkeit` | `inaccessible-member` | IM1/IM2 protected-Mitglieder generischer Klassen aus generischem Code einer anderen Unit, IM4 private class constructor neben TObject.Create, IM5 Klassenmethoden-Überladung in einer Klassenmethode |
| `DccSichtbarkeitGegen` | `inaccessible-member` | SG1/SG2 protected-Felder nicht generischer Klassen, SG3 protected-Feld einer generischen Klasse aus nicht generischem Code (vorher IM3) |
| `DccInline` | `type-restriction-violated` | TR1/TR2 echte Konstante aus dem implementation-Teil in einer Inline-Routine, TR4 Routine, TR5 inline nur an der Implementierung, TR6 Konstruktor im Class-Helfer ruft im if, TR7 class constructor im Class-Helfer, TR8 Typ aus dem implementation-Teil (vorher TG2), TR9 Helfer-Konstruktor ohne Aufruf (vorher TG3) |
| `DccInlineGegen` | `type-restriction-violated` | TG1 Variable aus dem implementation-Teil (E2441) |
| `DccInlineKonstanteGegen` | `type-restriction-violated` | TG4 typisierte Konstante aus dem implementation-Teil (vorher TR3, E2441); eigenes Projekt, weil dcc E2441 nur einmal je Unit meldet |
| `DccVorwaerts` | `type-used-before-declaration` | TU1/TU2 `class of` vor der Klasse im selben type-Block |
| `DccVorwaertsGegen` | `type-used-before-declaration` | UG1 Klasse erst im nächsten type-Block |
| `DccInterfaces` | `interface-declaration-invalid` | ID1 Property im abgeleiteten Interface mit write neu, ID2 dasselbe generisch, ID3 neue Property mit geerbtem Getter (vorher IG2) |
| `DccInterfacesGegen` | `interface-declaration-invalid` | IG1 Neudeklaration ohne Typ (E2206) |
| `DccPublished` | `published-type-invalid` | PU1 `TArray<Integer>`, PU2 benanntes dynamisches Array, PU3 Record als published-Property (aus #1326); dcc übersetzt alle drei |
| `DccPublishedGegen` | `published-type-invalid` | PV1 statisches Array, PV2 Zeiger (E2188) |
| `DccGenerics` | `generic-declaration-invalid`, `generic-inference-failed` | GN1 anonyme Methode in einer Methode eines generischen Typs, GN2 lokale Routine in einer normalen Methode, GN3 Alias auf `TBehaelter<Integer>` und `type Integer`, GN4 ableitbarer Typparameter, GN5 gleichartige Argumente, GN6 Klasse, Interface und constructor als Einschränkung, GN7 Integer und Double, GN8 Variant und Zahl für denselben Typparameter (#1376; ungeprüft mit dcc) |
| `DccGenericsGegen` | `generic-declaration-invalid`, `generic-inference-failed` | GG1 Konstruktor mit Typparameter und Parameter (E2528), GG2 lokale Routine in einer generischen Methode (E2570), GG3 `type TArray<Integer>` (E2574), GG4 `TStream` und `record` als Einschränkung (E2552), GG5 `Neu` ohne Typargument als Anweisung und mit Klammern (E2531), GG6 Zahl und Zeichenkette bzw. Boolean und Zahl (E2532) (#1376; ungeprüft mit dcc) |
| `DccAutomation` | `automation-invalid` | AU1–AU5 erlaubte Typen, register, dispid, Getter und Setter als Methoden im Abschnitt automated, AU6 override ohne dispid, AU7 dispid des Vorfahren noch einmal (Atlas still), AU8–AU10 Aufrufe über Variant mit erlaubten und benannten Argumenten (aus #1373) |
| `DccAutomationGegen` | `automation-invalid` | AG1 Destruktor (E2177), AG2 message (E2178), AG3 safecall (E2179), AG4–AG7 und AG13 Zeiger, Menge und Record als Typ (E2176), AG8–AG10 stored, default, nodefault (E2182), AG11/AG12 dieselbe dispid als Hex und an einer Property (E2180) |
| `DccAutomationAufrufGegen` | `automation-invalid` | AC1 Variant mit Record, AC2 OleVariant mit Pointer (welcher Code: E2160 oder E2281?), AC3 typisierter Zeiger, AC4 Kette über OleVariant, AC5 unbenannt nach benannt (E2166) |
| `DccOperatoren` | `operator-declaration-invalid` | OP1–OP4 Vergleichsoperatoren ohne Boolean-Ergebnis, OP5 Benutzung |
| `DccOperatorenGegen` | `operator-declaration-invalid` | OG1/OG2 falsche Parameterzahl |
| `DccDeklarationen` | `declaration-invalid` und weitere (#1380) | DK1/DK2 packed vor array und record, DK3 Zeiger auf den eigenen Record, DK4 Vorfahr erst vorwärts und dann vollständig, DK5 sealed ohne offene abstrakte Methoden, DK6 überladene default-Property, DK7 Klassen-Property an class var, DK8 Konstruktoren mit gleichen Parametern ohne C++-Ausgabe, DK9 dispinterface-Property ohne read/write, DK10 external cdecl varargs, DK11 @ vor Array-Element |
| `DccDeklarationenGegen` | `declaration-invalid` und weitere (#1380) | DG1/DG2 packed vor Byte und Klasse (E2006), DG3 Vorfahr nur vorwärts (E2086), DG4/DG5 Property ohne read/write in Interface und automated (E2128), DG6 stdcall varargs ohne external (E2277, Win32), DG7 @ vor Ausdruck (E2036) |
| `DccKonstanten` | `typed-constant-modified` | TC1 `{$J+}`, TC2 `{$WRITEABLECONST ON}`, TC3 `{$J+}` aus einer Include-Datei |
| `DccKonstantenGegen` | `typed-constant-modified` | KG1 `{$J-}` |
| `DccAssembler` | `asm-invalid` | AK1–AK23 gültiger Inline-Assembler (esp als Basis, Befehle mit verschieden großen Operanden, Segmentregister, `out 5, al`, `db` mit Konstante, `OFFSET x + 4`, vier Zeichen an `eax`, Hex mit Nachsilbe h, Präfixe, Sprungmarken), AK24 gemeinsames end von `{$IFNDEF} asm … {$ELSE} begin …` (wie FastMM5); nur Win32 (#1375) |
| `DccAssemblerGegen` | `asm-invalid` | AF1–AF12 Formen, die Atlas meldet (Code in der Marke), AF13–AF18 Kandidaten, die Atlas noch nicht meldet (`dd` mit Variable, `db` mit Parameter, `mov al, 'ab'`, Zahl über 32 Bit, `cmp 5, eax`, `db 1 / 0`); nur Win32 |
| `DccUeberladungen` | `overload-resolution` | UL1–UL3 Ganzzahl, string und Char an Integer/string, UL4 Ganzzahl an Double, UL5 untypisierte Konstante `'a'` an Char/Integer, UL6 Record mit Implicit-Operator, UL7 Alias auf Integer, UL8 weiteres Argument entscheidet, UL9 Integer passt genauer als Double, UL10 Überladung erst hinter dem Aufruf, UL11 Überladung aus dem Vorfahren (#1371) |
| `DccUeberladungenGegen` | `overload-resolution` | UG1–UG6 keine Überladung passt (E2250: Gleitkomma, Boolean, Double-Variable, zu viele und keine Argumente, Aliase), UG7/UG8 nur Standardparameter verschieden (E2251), UG9–UG11 dasselbe an Methoden und mit Überladung aus dem Vorfahren |
