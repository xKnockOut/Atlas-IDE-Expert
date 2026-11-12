unit Atlas.Common.Rules.MessageCatalog;

// Erklärungen zu Compilermeldungen (#54): Name, Erklärung, typische Ursache und
// Beispiel falsch/richtig je Meldungsnummer (E2003, W1036 …). Die Nummer ist der
// Schlüssel, nicht der Text: Die deutsche und die englische Compilerausgabe
// bekommen dieselbe Erklärung. Gilt für jede Diagnose mit Code, gleich ob aus
// dcc, dem IDE-Compiler oder als "wie E2035" an einer Atlas-Regel; die Starter-
// Edition ohne dcc braucht also nichts weiter.
//
// Die Texte sind selbst geschrieben; das DocWiki wird nur verlinkt (DocWikiUrl,
// Suche nach der Nummer im Release der eingestellten Delphi-Version). Die
// Sprache wählt der Aufrufer (#1458), wie beim Regelkatalog.
//
// Der Regelkatalog (regelkatalog.json) beschreibt nur Regeln mit Schweregrad,
// Gruppe und Optionen; Compilermeldungen haben stattdessen eine Ursache. Sie
// stehen deshalb hier als Texttabelle neben ihm und laufen über dieselbe
// Übersetzungsprüfung (TAtlasTextTables).

interface

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Erklärung einer Compilermeldung in einer Sprache.</summary>
  TCompilerMessageEntry = record
    /// <summary>Nummer in Großbuchstaben, z. B. E2003.</summary>
    Code: string;
    Name: string;
    Description: string;
    /// <summary>Typische Ursache in einem Satz, für die Zeile im Hover.</summary>
    Cause: string;
    Bad: string;
    Good: string;
  end;

  TCompilerMessageCatalog = class
  public
    /// <summary>Nummer am Anfang einer Meldung bzw. eines Codes ("E2003", "[dcc32 Fehler] E2003 …",
    /// "W1036 Variable …"); '' ohne.</summary>
    class function CodeOf(const AText: string): string; static;
    /// <summary>Eintrag zur Nummer ACode (Groß-/Kleinschreibung egal) in ALanguage.</summary>
    class function TryFind(const ACode: string; ALanguage: TTextLanguage; out AEntry: TCompilerMessageEntry): Boolean;
      static;
    /// <summary>Alle Einträge in ALanguage, nach Nummer.</summary>
    class function Entries(ALanguage: TTextLanguage): TArray<TCompilerMessageEntry>; static;
    /// <summary>Suche nach ACode im DocWiki des Releases zu ADelphiVersion (BDS-Nummer, '' = neuestes).</summary>
    class function DocWikiUrl(const ACode, ADelphiVersion: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Lsp.DocWiki;

type
  TExample = record
    Bad: string;
    Good: string;
  end;

const
  cDocWikiBase = 'https://docwiki.embarcadero.com/RADStudio/';

  cCodes: array[0..37] of string = ('E2003', 'E2004', 'E2005', 'E2008', 'E2009', 'E2010', 'E2012', 'E2014', 'E2015',
    'E2017', 'E2018', 'E2023', 'E2029', 'E2033', 'E2034', 'E2035', 'E2036', 'E2037', 'E2064', 'E2065', 'E2066',
    'E2129', 'E2250', 'F1026', 'F2063', 'F2613', 'W1000', 'W1010', 'W1035', 'W1036', 'W1057', 'W1058', 'W1071',
    'H2077', 'H2135', 'H2164', 'H2219', 'H2443');

  cNames: array[0..37] of TAtlasText = (
    (De: 'Undeklarierter Bezeichner'; En: 'Undeclared identifier'),
    (De: 'Bezeichner doppelt deklariert'; En: 'Identifier redeclared'),
    (De: 'Kein Typbezeichner'; En: 'Not a type identifier'),
    (De: 'Inkompatible Typen'; En: 'Incompatible types'),
    (De: 'Inkompatible Typen (Art des Typs)'; En: 'Incompatible types (kind of type)'),
    (De: 'Inkompatible Typen zweier Seiten'; En: 'Incompatible types of two sides'),
    (De: 'Ausdruck muss Boolean sein'; En: 'Expression must be Boolean'),
    (De: 'Anweisung erwartet, Ausdruck gefunden'; En: 'Statement expected, expression found'),
    (De: 'Operator passt nicht zum Operandentyp'; En: 'Operator not applicable to operand type'),
    (De: 'Zeigertyp erforderlich'; En: 'Pointer type required'),
    (De: 'Record-, Objekt- oder Klassentyp erforderlich'; En: 'Record, object or class type required'),
    (De: 'Funktion ohne Ergebnistyp'; En: 'Function needs result type'),
    (De: 'Anderes Zeichen erwartet'; En: 'Other token expected'),
    (De: 'var-Parameter mit anderem Typ'; En: 'var parameter of another type'),
    (De: 'Zu viele Parameter'; En: 'Too many actual parameters'),
    (De: 'Zu wenige Parameter'; En: 'Not enough actual parameters'),
    (De: 'Variable erforderlich'; En: 'Variable required'),
    (De: 'Deklaration weicht ab'; En: 'Declaration differs'),
    (De: 'Linker Seite kann nichts zugewiesen werden'; En: 'Left side cannot be assigned to'),
    (De: 'Deklaration ohne Implementierung'; En: 'Unsatisfied forward or external declaration'),
    (De: 'Operator oder Semikolon fehlt'; En: 'Missing operator or semicolon'),
    (De: 'Zuweisung an Property ohne write'; En: 'Assignment to read-only property'),
    (De: 'Keine passende Überladung'; En: 'No matching overload'),
    (De: 'Datei nicht gefunden'; En: 'File not found'),
    (De: 'Verwendete Unit nicht übersetzbar'; En: 'Could not compile used unit'),
    (De: 'Unit nicht gefunden'; En: 'Unit not found'),
    (De: 'Symbol ist veraltet'; En: 'Symbol is deprecated'),
    (De: 'Methode verdeckt virtuelle Methode'; En: 'Method hides virtual method'),
    (De: 'Funktionsergebnis evtl. undefiniert'; En: 'Function result might be undefined'),
    (De: 'Variable evtl. nicht initialisiert'; En: 'Variable might not be initialized'),
    (De: 'Implizite String-Umwandlung'; En: 'Implicit string cast'),
    (De: 'Implizite String-Umwandlung mit Datenverlust'; En: 'Implicit string cast with data loss'),
    (De: 'Implizite Ganzzahl-Umwandlung mit Datenverlust'; En: 'Implicit integer cast with data loss'),
    (De: 'Zugewiesener Wert wird nie benutzt'; En: 'Assigned value never used'),
    (De: 'Schleife läuft nie'; En: 'Loop executes zero times'),
    (De: 'Variable deklariert, aber nicht verwendet'; En: 'Variable declared but never used'),
    (De: 'Privates Symbol nie verwendet'; En: 'Private symbol never used'),
    (De: 'Inline-Funktion nicht expandiert'; En: 'Inline function not expanded'));

  cDescriptions: array[0..37] of TAtlasText = (
    (De: 'Der Compiler kennt den Namen an dieser Stelle nicht. Er sucht in der Routine, der Klasse, der Unit und ' +
      'den Units aus uses, und zwar nur oberhalb der Stelle.';
     En: 'The compiler does not know the name at this point. It searches the routine, the class, the unit and the ' +
      'units from uses, and only above this point.'),
    (De: 'Derselbe Name ist im selben Gültigkeitsbereich zweimal deklariert, z. B. zwei Felder oder eine lokale ' +
      'Variable mit dem Namen eines Parameters.';
     En: 'The same name is declared twice in the same scope, e.g. two fields or a local variable named like a ' +
      'parameter.'),
    (De: 'An dieser Stelle muss ein Typ stehen, der Name bezeichnet aber eine Variable, Konstante oder Routine.';
     En: 'A type must stand here, but the name denotes a variable, constant or routine.'),
    (De: 'Die Typen passen nicht zueinander, z. B. ein String, wo eine Zahl erwartet wird.';
     En: 'The types do not fit, e.g. a string where a number is expected.'),
    (De: 'Der Ausdruck hat eine andere Art von Typ als erwartet, z. B. eine Routine statt einer Methode (procedure ' +
      'of object).';
     En: 'The expression has another kind of type than expected, e.g. a routine instead of a method (procedure of ' +
      'object).'),
    (De: 'Die beiden Seiten einer Zuweisung bzw. ein Argument und sein Parameter haben Typen, zwischen denen es ' +
      'keine Umwandlung gibt.';
     En: 'The two sides of an assignment, or an argument and its parameter, have types without a conversion ' +
      'between them.'),
    (De: 'if, while und until erwarten einen Boolean-Ausdruck; Delphi wandelt Zahlen nicht still um.';
     En: 'if, while and until expect a Boolean expression; Delphi does not convert numbers silently.'),
    (De: 'Ein Ausdruck steht allein als Anweisung, z. B. ein Vergleich mit = statt einer Zuweisung mit :=.';
     En: 'An expression stands alone as a statement, e.g. a comparison with = instead of an assignment with :=.'),
    (De: 'Der Operator ist für diesen Typ nicht definiert, z. B. + zwischen einer Zahl und einem String oder and auf ' +
      'Strings.';
     En: 'The operator is not defined for this type, e.g. + between a number and a string or and on strings.'),
    (De: '^ zum Dereferenzieren steht an einem Wert, der kein Zeiger ist.';
     En: '^ for dereferencing follows a value that is not a pointer.'),
    (De: 'Vor dem Punkt steht etwas ohne Felder und Methoden, z. B. ein String ohne Helfer oder eine Zahl.';
     En: 'Before the dot stands something without fields and methods, e.g. a string without helper or a number.'),
    (De: 'Eine function braucht einen Ergebnistyp; ohne Ergebnis ist es eine procedure.';
     En: 'A function needs a result type; without a result it is a procedure.'),
    (De: 'Die Syntax verlangt hier ein bestimmtes Zeichen oder Schlüsselwort, z. B. ";" oder "end"; die Ursache ' +
      'liegt oft eine Zeile davor.';
     En: 'The syntax requires a certain token or keyword here, e.g. ";" or "end"; the cause is often one line ' +
      'earlier.'),
    (De: 'Ein var- oder out-Parameter verlangt genau seinen Typ; Umwandlungen sind nicht erlaubt.';
     En: 'A var or out parameter requires exactly its type; conversions are not allowed.'),
    (De: 'Der Aufruf übergibt mehr Argumente, als die Routine Parameter hat.';
     En: 'The call passes more arguments than the routine has parameters.'),
    (De: 'Der Aufruf übergibt weniger Argumente, als die Routine Parameter ohne Vorgabewert hat.';
     En: 'The call passes fewer arguments than the routine has parameters without default value.'),
    (De: 'Hier muss eine Variable stehen (var-Parameter, @, Zuweisung), aber es steht eine Konstante, ein Ausdruck ' +
      'oder eine Property.';
     En: 'A variable must stand here (var parameter, @, assignment), but there is a constant, an expression or a ' +
      'property.'),
    (De: 'Der Kopf in implementation hat andere Parameter, einen anderen Ergebnistyp oder eine andere ' +
      'Aufrufkonvention als die Deklaration.';
     En: 'The header in implementation has other parameters, another result type or another calling convention than ' +
      'the declaration.'),
    (De: 'Die linke Seite ist kein Speicherort: eine Konstante, ein Funktionsergebnis oder das Feld eines Records, den ' +
      'eine Property nur als Kopie liefert.';
     En: 'The left side is not a storage location: a constant, a function result or the field of a record that a ' +
      'property only delivers as a copy.'),
    (De: 'Eine Methode oder forward-Routine ist deklariert, aber nirgends implementiert.';
     En: 'A method or forward routine is declared but implemented nowhere.'),
    (De: 'Zwischen zwei Ausdrücken fehlt ein Operator, oder zwei Anweisungen sind nicht durch ";" getrennt.';
     En: 'An operator is missing between two expressions, or two statements are not separated by ";".'),
    (De: 'Die Property hat kein write; sie lässt sich nur lesen.';
     En: 'The property has no write; it can only be read.'),
    (De: 'Keine der überladenen Varianten passt zu den Typen der Argumente.';
     En: 'None of the overloaded versions fits the types of the arguments.'),
    (De: 'Eine Include-, Ressourcen- oder Unit-Datei liegt nicht im Suchpfad.';
     En: 'An include, resource or unit file is not in the search path.'),
    (De: 'Eine Unit aus uses hat selbst Fehler; die eigentliche Meldung steht weiter oben.';
     En: 'A unit from uses has errors itself; the actual message is further up.'),
    (De: 'Weder .pas noch .dcu der Unit liegen im Suchpfad, oder der Name hat einen Tippfehler bzw. keinen ' +
      'Namespace.';
     En: 'Neither .pas nor .dcu of the unit are in the search path, or the name has a typo or lacks a namespace.'),
    (De: 'Das Symbol ist mit deprecated markiert und soll nicht mehr verwendet werden; der Text nennt oft den ' +
      'Ersatz.';
     En: 'The symbol is marked deprecated and should no longer be used; the text often names the replacement.'),
    (De: 'Eine Methode mit dem Namen einer virtuellen Methode des Vorfahren verdeckt diese, statt sie zu ' +
      'überschreiben.';
     En: 'A method with the name of a virtual method of the ancestor hides it instead of overriding it.'),
    (De: 'Auf mindestens einem Weg durch die Funktion wird Result nicht gesetzt.';
     En: 'On at least one path through the function Result is not set.'),
    (De: 'Die Variable wird gelesen, bevor sie auf jedem Weg einen Wert bekommen hat.';
     En: 'The variable is read before it got a value on every path.'),
    (De: 'Zwischen AnsiString und UnicodeString wird still umgewandelt; das kostet Zeit.';
     En: 'AnsiString and UnicodeString are converted silently; this costs time.'),
    (De: 'Beim Umwandeln in einen Ansi-Typ können Zeichen verloren gehen, die die Codepage nicht kennt.';
     En: 'Converting to an Ansi type can lose characters that the code page does not know.'),
    (De: 'Ein größerer Ganzzahltyp wird in einen kleineren gespeichert; hohe Bits gehen verloren.';
     En: 'A larger integer type is stored into a smaller one; high bits are lost.'),
    (De: 'Der zugewiesene Wert wird überschrieben oder die Routine endet, bevor er gelesen wird.';
     En: 'The assigned value is overwritten, or the routine ends, before it is read.'),
    (De: 'Die Grenzen der Schleife sind konstant so, dass sie nie läuft; der Compiler entfernt sie.';
     En: 'The bounds of the loop are constant so that it never runs; the compiler removes it.'),
    (De: 'Die lokale Variable wird nirgends gelesen oder geschrieben.';
     En: 'The local variable is never read or written.'),
    (De: 'Ein private-Mitglied wird in der Unit nirgends verwendet.';
     En: 'A private member is used nowhere in the unit.'),
    (De: 'Die Inline-Funktion braucht eine weitere Unit in uses, damit der Compiler sie einsetzen kann.';
     En: 'The inline function needs another unit in uses so that the compiler can expand it.'));

  cCauses: array[0..37] of TAtlasText = (
    (De: 'Tippfehler, fehlende Unit in uses oder die Deklaration steht erst weiter unten.';
     En: 'Typo, missing unit in uses, or the declaration comes only further down.'),
    (De: 'Name kopiert und nicht umbenannt, oder Feld und Property mit gleichem Namen.';
     En: 'Name copied and not renamed, or field and property with the same name.'),
    (De: 'Variable statt Typ geschrieben oder Typ aus einer nicht eingebundenen Unit verdeckt.';
     En: 'Variable written instead of type, or type hidden by a unit not in uses.'),
    (De: 'Fehlende Umwandlung wie IntToStr, StrToInt oder ein falscher Typ im Aufruf.';
     En: 'Missing conversion such as IntToStr or StrToInt, or a wrong type in the call.'),
    (De: 'Freie Prozedur an ein Ereignis zugewiesen oder Klasse statt Instanz übergeben.';
     En: 'Free procedure assigned to an event, or class passed instead of an instance.'),
    (De: 'Fehlende Umwandlung oder ein Ergebnis einer anderen Überladung als gedacht.';
     En: 'Missing conversion, or a result of another overload than expected.'),
    (De: 'Zahl statt Vergleich in der Bedingung, z. B. if Count then.';
     En: 'Number instead of comparison in the condition, e.g. if Count then.'),
    (De: '= statt := geschrieben.'; En: '= written instead of :=.'),
    (De: 'Fehlende Umwandlung oder Klammern um einen Vergleich mit and/or vergessen.';
     En: 'Missing conversion, or parentheses around a comparison with and/or forgotten.'),
    (De: '^ an einem Objekt; Objekte sind schon Referenzen.';
     En: '^ on an object; objects are references already.'),
    (De: 'Fehlende Unit mit dem Record-Helfer oder Punkt an einem falschen Bezeichner.';
     En: 'Missing unit with the record helper, or dot on a wrong identifier.'),
    (De: 'procedure in function umbenannt und den Ergebnistyp vergessen.';
     En: 'procedure renamed to function and result type forgotten.'),
    (De: 'Fehlendes ";" oder "end" in der Zeile davor.'; En: 'Missing ";" or "end" in the line before.'),
    (De: 'Integer an einen var-Parameter vom Typ Cardinal oder NativeInt übergeben.';
     En: 'Integer passed to a var parameter of type Cardinal or NativeInt.'),
    (De: 'Signatur geändert, Aufrufe nicht angepasst.'; En: 'Signature changed, calls not adjusted.'),
    (De: 'Neuer Parameter ohne Vorgabewert, Aufrufe nicht angepasst.';
     En: 'New parameter without default value, calls not adjusted.'),
    (De: 'Property an einen var-Parameter übergeben, z. B. Inc(Liste.Count).';
     En: 'Property passed to a var parameter, e.g. Inc(List.Count).'),
    (De: 'Nur Deklaration oder nur Implementierung geändert.'; En: 'Only declaration or only implementation changed.'),
    (De: 'Feld eines Records über eine Property gesetzt, z. B. Rahmen.BoundsRect.Left := 0.';
     En: 'Field of a record set through a property, e.g. Frame.BoundsRect.Left := 0.'),
    (De: 'Methode deklariert und Implementierung vergessen oder Klassenname im Kopf falsch.';
     En: 'Method declared and implementation forgotten, or class name in the header wrong.'),
    (De: 'Fehlendes ";" am Ende der vorigen Zeile.'; En: 'Missing ";" at the end of the previous line.'),
    (De: 'Count, Handle oder Text zugewiesen, obwohl die Klasse dafür eine Methode hat.';
     En: 'Count, Handle or Text assigned although the class has a method for it.'),
    (De: 'Literal mit falschem Typ, z. B. Integer statt Int64 oder string statt Char.';
     En: 'Literal with the wrong type, e.g. Integer instead of Int64 or string instead of Char.'),
    (De: 'Suchpfad der Plattform fehlt oder Groß-/Kleinschreibung des Dateinamens.';
     En: 'Search path of the platform missing, or case of the file name.'),
    (De: 'Folgefehler; die erste Meldung in der genannten Unit beheben.';
     En: 'Follow-up error; fix the first message in the named unit.'),
    (De: 'Unit-Namespace fehlt (Windows statt Winapi.Windows) oder Bibliothekspfad nicht gesetzt.';
     En: 'Unit namespace missing (Windows instead of Winapi.Windows), or library path not set.'),
    (De: 'Code aus einer älteren Delphi-Version.'; En: 'Code from an older Delphi version.'),
    (De: 'override vergessen.'; En: 'override forgotten.'),
    (De: 'Ein Zweig von if oder case ohne Zuweisung an Result.';
     En: 'A branch of if or case without assignment to Result.'),
    (De: 'Zuweisung nur in einem Zweig oder nach einer frühen Exit-Prüfung.';
     En: 'Assignment only in one branch, or after an early Exit check.'),
    (De: 'AnsiString aus einer älteren API mit string gemischt.'; En: 'AnsiString from an older API mixed with string.'),
    (De: 'string an eine Ansi-API oder an AnsiString übergeben.'; En: 'string passed to an Ansi API or to AnsiString.'),
    (De: 'Int64 oder NativeInt in Integer gespeichert, oft bei Größen und Zeigern.';
     En: 'Int64 or NativeInt stored in Integer, often with sizes and pointers.'),
    (De: 'Vorbelegung, die danach in jedem Zweig überschrieben wird.';
     En: 'Initial value that is overwritten in every branch afterwards.'),
    (De: 'Konstante Grenzen nach einer Änderung, z. B. for I := 1 to 0.';
     En: 'Constant bounds after a change, e.g. for I := 1 to 0.'),
    (De: 'Rest nach einem Umbau.'; En: 'Leftover after a refactoring.'),
    (De: 'Rest nach einem Umbau oder nur über RTTI verwendet.'; En: 'Leftover after a refactoring, or used via RTTI only.'),
    (De: 'Unit der Inline-Funktion fehlt in uses, z. B. System.Types oder Winapi.Windows.';
     En: 'Unit of the inline function missing in uses, e.g. System.Types or Winapi.Windows.'));

  cExamples: array[0..37] of TExample = (
    (Bad: 'Result := Trim(Name);  // ohne System.SysUtils'; Good: 'uses' + #10 + '  System.SysUtils;'),
    (Bad: 'procedure Rechne(Wert: Integer);' + #10 + 'var' + #10 + '  Wert: Integer;';
     Good: 'procedure Rechne(AWert: Integer);' + #10 + 'var' + #10 + '  mWert: Integer;'),
    (Bad: 'var' + #10 + '  mListe: Liste;'; Good: 'var' + #10 + '  mListe: TStringList;'),
    (Bad: 'Edit1.Text := Anzahl;'; Good: 'Edit1.Text := IntToStr(Anzahl);'),
    (Bad: 'Button1.OnClick := Klick;  // freie Prozedur'; Good: 'Button1.OnClick := Self.Klick;  // Methode'),
    (Bad: 'mZahl := Edit1.Text;'; Good: 'mZahl := StrToInt(Edit1.Text);'),
    (Bad: 'if Liste.Count then'; Good: 'if Liste.Count > 0 then'),
    (Bad: 'mSumme = 0;'; Good: 'mSumme := 0;'),
    (Bad: 'if A > 0 and B > 0 then'; Good: 'if (A > 0) and (B > 0) then'),
    (Bad: 'mListe^.Add(''a'');'; Good: 'mListe.Add(''a'');'),
    (Bad: 'mText.Trim;  // ohne System.SysUtils'; Good: 'uses' + #10 + '  System.SysUtils;'),
    (Bad: 'function Summe;'; Good: 'function Summe: Integer;'),
    (Bad: 'mA := 1' + #10 + 'mB := 2;'; Good: 'mA := 1;' + #10 + 'mB := 2;'),
    (Bad: 'var' + #10 + '  mZahl: Integer;' + #10 + '…' + #10 + 'Lese(mZahl);  // var AWert: Cardinal';
     Good: 'var' + #10 + '  mZahl: Cardinal;' + #10 + '…' + #10 + 'Lese(mZahl);'),
    (Bad: 'ShowMessage(''a'', ''b'');'; Good: 'ShowMessage(''a'' + ''b'');'),
    (Bad: 'Format(''%d Treffer'');'; Good: 'Format(''%d Treffer'', [Anzahl]);'),
    (Bad: 'Inc(Liste.Count);'; Good: 'mAnzahl := Liste.Count;' + #10 + 'Inc(mAnzahl);'),
    (Bad: 'procedure Laden(const AName: string);  // interface' + #10 + 'procedure Laden(AName: string);  // ' +
      'implementation';
     Good: 'procedure Laden(const AName: string);'),
    (Bad: 'Rahmen.BoundsRect.Left := 0;';
     Good: 'mRect := Rahmen.BoundsRect;' + #10 + 'mRect.Left := 0;' + #10 + 'Rahmen.BoundsRect := mRect;'),
    (Bad: 'procedure Speichern;  // nur im Typ'; Good: 'procedure TDaten.Speichern;' + #10 + 'begin' + #10 + 'end;'),
    (Bad: 'mA := 1' + #10 + 'mB := 2;'; Good: 'mA := 1;' + #10 + 'mB := 2;'),
    (Bad: 'Liste.Count := 0;'; Good: 'Liste.Clear;'),
    (Bad: 'Max(mInt64, 0);  // Max(Int64, Integer)'; Good: 'Max(mInt64, Int64(0));'),
    (Bad: '{$I Einstellungen.inc}  // Datei fehlt im Suchpfad'; // german-ok: Codebeispiel
     Good: '{$I ..\Gemeinsam\Einstellungen.inc}'),
    (Bad: 'uses' + #10 + '  Daten.Kunden;  // hat selbst Fehler'; // german-ok: Codebeispiel
     Good: 'Erste Meldung in Daten.Kunden beheben'),
    (Bad: 'uses' + #10 + '  Windows;'; Good: 'uses' + #10 + '  Winapi.Windows;'),
    (Bad: 'mDatei := FileAge(mName);'; Good: 'FileAge(mName, mDatum);'),
    (Bad: 'procedure Paint;  // im Vorfahren virtual'; Good: 'procedure Paint; override;'),
    (Bad: 'function Sign(A: Integer): Integer;' + #10 + 'begin' + #10 + '  if A > 0 then' + #10 + '    Result := 1;' +
      #10 + 'end;';
     Good: 'function Sign(A: Integer): Integer;' + #10 + 'begin' + #10 + '  Result := 0;' + #10 + '  if A > 0 then' +
      #10 + '    Result := 1;' + #10 + 'end;'),
    (Bad: 'if mOk then' + #10 + '  mWert := 1;' + #10 + 'Zeige(mWert);';
     Good: 'mWert := 0;' + #10 + 'if mOk then' + #10 + '  mWert := 1;' + #10 + 'Zeige(mWert);'),
    (Bad: 'mText := mAnsi;  // string := AnsiString'; Good: 'mText := string(mAnsi);'),
    (Bad: 'mAnsi := mText;  // AnsiString := string'; Good: 'mAnsi := AnsiString(mText);'),
    (Bad: 'mGroesse := mStrom.Size;  // Integer := Int64'; Good: 'mGroesse := Integer(mStrom.Size);'),
    (Bad: 'Result := '''';' + #10 + 'if mOk then' + #10 + '  Result := ''a''' + #10 + 'else' + #10 +
      '  Result := ''b'';';
     Good: 'if mOk then' + #10 + '  Result := ''a''' + #10 + 'else' + #10 + '  Result := ''b'';'),
    (Bad: 'for I := 1 to 0 do'; Good: 'for I := 0 to Liste.Count - 1 do'),
    (Bad: 'var' + #10 + '  mAlt: Integer;  // nirgends verwendet'; Good: '(Variable entfernen)'),
    (Bad: 'private' + #10 + '  FAlt: Integer;  // nirgends verwendet'; Good: '(Feld entfernen)'),
    (Bad: 'mRect.Width;  // ohne System.Types'; Good: 'uses' + #10 + '  System.Types;'));

function Localized(AIndex: Integer; ALanguage: TTextLanguage): TCompilerMessageEntry;
begin
  Result.Code := cCodes[AIndex];
  Result.Name := cNames[AIndex].TextIn(ALanguage);
  Result.Description := cDescriptions[AIndex].TextIn(ALanguage);
  Result.Cause := cCauses[AIndex].TextIn(ALanguage);
  Result.Bad := cExamples[AIndex].Bad;
  Result.Good := cExamples[AIndex].Good;
end;

{ TCompilerMessageCatalog }

class function TCompilerMessageCatalog.CodeOf(const AText: string): string;
var
  mIndex, mStart: Integer;
begin
  // Erstes Wort aus Buchstabe E/W/H/F und vier Ziffern, z. B. hinter "[dcc32 Fehler] ".
  for mStart := 1 to Length(AText) - 4 do
  begin
    if CharInSet(UpCase(AText[mStart]), ['E', 'W', 'H', 'F']) and
      ((mStart = 1) or not CharInSet(AText[mStart - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then
    begin
      mIndex := mStart + 1;
      while (mIndex <= Length(AText)) and (mIndex - mStart <= 4) and CharInSet(AText[mIndex], ['0'..'9']) do
      begin
        Inc(mIndex);
      end;
      if (mIndex - mStart = 5) and
        ((mIndex > Length(AText)) or not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then
      begin
        Exit(UpperCase(Copy(AText, mStart, 5)));
      end;
    end;
  end;
  Result := '';
end;

class function TCompilerMessageCatalog.TryFind(const ACode: string; ALanguage: TTextLanguage;
  out AEntry: TCompilerMessageEntry): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexText(Trim(ACode), cCodes);
  Result := mIndex >= 0;
  if Result then
  begin
    AEntry := Localized(mIndex, ALanguage);
  end
  else
  begin
    AEntry := Default(TCompilerMessageEntry);
  end;
end;

class function TCompilerMessageCatalog.Entries(ALanguage: TTextLanguage): TArray<TCompilerMessageEntry>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cCodes));
  for mIndex := 0 to High(cCodes) do
  begin
    Result[mIndex] := Localized(mIndex, ALanguage);
  end;
end;

class function TCompilerMessageCatalog.DocWikiUrl(const ACode, ADelphiVersion: string): string;
begin
  Result := cDocWikiBase + TDocWiki.ReleaseName(ADelphiVersion) + '/e/index.php?search=' + UpperCase(Trim(ACode));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.MessageCatalog.Names', cNames);
  TAtlasTextTables.Add('Atlas.Common.Rules.MessageCatalog.Descriptions', cDescriptions);
  TAtlasTextTables.Add('Atlas.Common.Rules.MessageCatalog.Causes', cCauses);

end.
