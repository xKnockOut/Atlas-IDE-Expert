unit Atlas.Common.Rules.CompilerPitfalls;

// Fallenkatalog der Compilermeldungen (#2621): bekannte Delphi-Fallen, bei denen der Meldungstext allein die
// Ursache nicht verrät (zwei gleich gebaute Methodenreferenztypen unter Delphi 12, TMonitor aus Vcl.Forms,
// Exit([...]), Units, die Free Pascal nicht verlangt …). Jede Falle steht als Datensatz da: Nummern, an denen sie
// auftritt, das Merkmal an der Stelle (Namen in Hochkommas, Text der Zeile, Sonderprüfung), die Atlas-Regel, die
// sie beim Tippen meldet, und die Art der sicheren Korrektur. Erklärung und Korrektur stehen als Texttabellen in
// beiden Sprachen daneben.
//
// Match ordnet die Fallen einer Meldung: zuerst die, deren Merkmal an der Stelle zu sehen ist, dann die übrigen
// Fallen derselben Nummer als weitere mögliche Ursachen. Die allgemeine Erklärung je Nummer steht im
// TCompilerMessageCatalog; die Korrekturen ohne Falle in TCompilerFixes.

interface

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  /// <summary>Eine bekannte Falle.</summary>
  TCompilerPitfall = (ReferenceTwins, ConstParameterToGeneric, ReferenceWithoutParentheses, ReferenceTypeInline,
    HiddenMonitor, RecordComparedWithNil, EnumHidesStatement, ExitArrayLiteral, ReferenceInvoked,
    AnonymousMethodOverload, AreEqualNativeInt, RectOverload, MemberHidesRoutine, ProtectedMember, FieldAfterMethod,
    LineTooLong, InlineUsesMissing, WinapiDeclarationMissing, WinapiUsesMissing, ActionsUsesMissing,
    PaletteUsesMissing, DesignEditorsUsesMissing, FormsUsesMissing, SysUtilsUsesMissing, BitmapHidden,
    CaptionStringHelper, ToolsApiSignature, DeprecatedScrollStyle, VclMethodHidden, NameOutOfScope);
  /// <summary>Wie die Falle an der Stelle erkannt wird.</summary>
  TPitfallCheck = (
    /// <summary>Namen in Hochkommas und/oder Text der Zeile (Names, Line, LineAlso, LineNot).</summary>
    Patterns,
    /// <summary>Die Nummer genügt.</summary>
    CodeOnly,
    /// <summary>Beide Namen der Meldung sind in der Datei als reference to deklariert.</summary>
    ReferenceTwins,
    /// <summary>Der erste Name ist in der Datei deklariert, aber an der Stelle nicht sichtbar.</summary>
    DeclaredInUnit,
    /// <summary>Die Zeile ist länger als 1023 Zeichen.</summary>
    LongLine,
    /// <summary>Kein Merkmal an der Stelle; nur als weitere Ursache.</summary>
    Unmarked);
  /// <summary>Sichere Korrektur der Falle.</summary>
  TPitfallFix = (None, QualifySystemMonitor, AddUses, ExitArrayLiteral);
{$SCOPEDENUMS OFF}

  /// <summary>Falle in einer Sprache.</summary>
  TCompilerPitfallInfo = record
    Pitfall: TCompilerPitfall;
    /// <summary>Kennung wie "reference-twins".</summary>
    Id: string;
    Title: string;
    /// <summary>Warum der Compiler an dieser Stelle meldet.</summary>
    Reason: string;
    /// <summary>Wie man es behebt, in einem Satz.</summary>
    Fix: string;
    /// <summary>Atlas-Regel, die die Falle beim Tippen meldet; '' = keine.</summary>
    Rule: string;
    FixKind: TPitfallFix;
    /// <summary>Unit, die AddUses einträgt; sonst ''.</summary>
    UsesUnit: string;
  end;

  /// <summary>Meldung für Match; Line ab 0, -1 ohne Stelle.</summary>
  TPitfallMessage = record
    Code: string;
    Text: string;
    Line: Integer;
    class function Create(const ACode, AText: string; ALine: Integer): TPitfallMessage; static;
  end;

  /// <summary>Eine Falle zu einer Meldung.</summary>
  TPitfallMatch = record
    Pitfall: TCompilerPitfall;
    /// <summary>Das Merkmal steht an der Stelle; sonst nur eine weitere mögliche Ursache.</summary>
    Marked: Boolean;
    /// <summary>Was an der Stelle passt, z. B. "TMonitor." oder "TAtlasNameFilter, TAtlasNamePredicate".</summary>
    Evidence: string;
  end;

  TCompilerPitfalls = class
  public
    /// <summary>Kennung, Texte in ALanguage, Regel und Art der Korrektur.</summary>
    class function Info(APitfall: TCompilerPitfall; ALanguage: TTextLanguage): TCompilerPitfallInfo; static;
    /// <summary>Nummern, bei denen APitfall auftritt.</summary>
    class function Codes(APitfall: TCompilerPitfall): TArray<string>; static;
    /// <summary>Gibt es zu ACode mindestens eine Falle?</summary>
    class function Knows(const ACode: string): Boolean; static;
    /// <summary>Fallen zu AMessage: zuerst die mit Merkmal an der Stelle (Zeile AMessage.Line in ASource), dann die
    /// übrigen derselben Nummer. ASource '' oder Line -1: alle ohne Merkmal.</summary>
    class function Match(const AMessage: TPitfallMessage; const ASource: string): TArray<TPitfallMatch>; static;
    /// <summary>Ist eine Meldung ACode nach den Meldungen APrevious (Nummern weiter oben in derselben Datei) nur ein
    /// Folgefehler? ACause erhält die Nummer, von der sie folgt.</summary>
    class function IsFollowUp(const ACode: string; const APrevious: TArray<string>; out ACause: string): Boolean;
      static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Text.Chars,
  Atlas.Common.Editing.CompilerFixes;

type
  TPitfallData = record
    /// <summary>Nummern, durch | getrennt.</summary>
    Codes: string;
    Check: TPitfallCheck;
    /// <summary>Namen in Hochkommas, durch | getrennt; * am Ende = Anfang des Namens.</summary>
    Names: string;
    /// <summary>Text, der in der Zeile stehen muss (einer davon), durch | getrennt.</summary>
    Line: string;
    /// <summary>Zusätzlich muss einer dieser Texte in der Zeile stehen; '' = nichts weiter.</summary>
    LineAlso: string;
    /// <summary>Steht einer dieser Texte in der Zeile, passt die Falle nicht.</summary>
    LineNot: string;
    Rule: string;
    Fix: TPitfallFix;
    UsesUnit: string;
  end;

  TFollowUp = record
    Code: string;
    /// <summary>Nummern, nach denen ACode nur folgt, durch | getrennt; E = jeder Fehler.</summary>
    After: string;
  end;

const
  cLongLine = 1023;
  // Getrennt geschrieben, weil der Linux-Bau System.TMonitor im Quelltext zu TMonitor macht (Convert-ForFpc.py).
  cSystemMonitor = 'System' + '.TMonitor.';

  cIds: array[TCompilerPitfall] of string = ('reference-twins', 'const-parameter-to-generic',
    'reference-without-parentheses', 'reference-type-inline', 'hidden-monitor', 'record-compared-with-nil',
    'enum-hides-statement', 'exit-array-literal', 'reference-invoked', 'anonymous-method-overload',
    'areequal-nativeint', 'rect-overload', 'member-hides-routine', 'protected-member', 'field-after-method',
    'line-too-long', 'inline-uses-missing', 'winapi-declaration-missing', 'winapi-uses-missing',
    'actions-uses-missing', 'palette-uses-missing', 'designeditors-uses-missing', 'forms-uses-missing',
    'sysutils-uses-missing', 'bitmap-hidden', 'caption-string-helper', 'toolsapi-signature',
    'deprecated-scrollstyle', 'vcl-method-hidden', 'name-out-of-scope');

  cData: array[TCompilerPitfall] of TPitfallData = (
    (Codes: 'E2010'; Check: TPitfallCheck.ReferenceTwins; Rule: 'type-mismatch'),
    (Codes: 'E2010'; Check: TPitfallCheck.Patterns; Names: 'TProc<*|TFunc<*|TPredicate<*'; Rule: 'type-mismatch'),
    (Codes: 'E2010'; Check: TPitfallCheck.Unmarked),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'reference'),
    (Codes: 'E2003|E2018'; Check: TPitfallCheck.Patterns; Line: 'TMonitor.'; LineNot: cSystemMonitor;
     Fix: TPitfallFix.QualifySystemMonitor),
    (Codes: 'E2015|E2008'; Check: TPitfallCheck.Patterns; Line: '<> nil|= nil'; Rule: 'type-mismatch'),
    (Codes: 'E2014'; Check: TPitfallCheck.Patterns; Line: 'Continue|Break|Exit'),
    (Codes: 'E2001|E2010'; Check: TPitfallCheck.Patterns; Line: 'Exit(['; Rule: 'exit-array-literal';
     Fix: TPitfallFix.ExitArrayLiteral),
    (Codes: 'E2035|E2010'; Check: TPitfallCheck.Patterns; Line: 'Exit(|+ ['),
    (Codes: 'E2250|E2010'; Check: TPitfallCheck.Patterns; Line: 'procedure(|function(|procedure (|function (';
     Rule: 'overload-resolution'),
    (Codes: 'E2532|E2250'; Check: TPitfallCheck.Patterns; Line: 'AreEqual|AreNotEqual';
     LineAlso: 'Length(|High(|Low(|Count'; Rule: 'dunitx-areequal-length'),
    (Codes: 'E2250|E2010'; Check: TPitfallCheck.Patterns; Line: 'Rect('),
    (Codes: 'E2034|E2035|E2010'; Check: TPitfallCheck.Patterns; Line: 'Scaled(|AddLabel('),
    (Codes: 'E2362'; Check: TPitfallCheck.CodeOnly; Rule: 'inaccessible-member'),
    (Codes: 'E2169'; Check: TPitfallCheck.CodeOnly; Rule: 'field-after-method'),
    (Codes: 'F2069'; Check: TPitfallCheck.LongLine; Rule: 'line-length'),
    (Codes: 'H2443'; Check: TPitfallCheck.CodeOnly; Rule: 'inline-not-expanded'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'OpenThread|THREAD_SUSPEND_RESUME|THREAD_GET_CONTEXT|' +
     'THREAD_QUERY_INFORMATION|PROCESS_QUERY_LIMITED_INFORMATION|ERROR_NOT_FOUND|CAPTUREBLT';
     Rule: 'winapi-declaration-missing'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'GetTickCount64|GetTickCount|MulDiv';
     Rule: 'winapi-uses-missing'; Fix: TPitfallFix.AddUses; UsesUnit: 'Winapi.Windows'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'TActionListState|TContainedAction';
     Fix: TPitfallFix.AddUses; UsesUnit: 'System.Actions'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'IOTAPaletteServices'; Fix: TPitfallFix.AddUses;
     UsesUnit: 'PaletteAPI'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'GetComponentEditor'; Fix: TPitfallFix.AddUses;
     UsesUnit: 'DesignEditors'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'TScrollBox'; Fix: TPitfallFix.AddUses;
     UsesUnit: 'Vcl.Forms'),
    (Codes: 'E2003'; Check: TPitfallCheck.Patterns; Names: 'TFunc|TProc|TFunc<*|TProc<*'; Fix: TPitfallFix.AddUses;
     UsesUnit: 'System.SysUtils'),
    (Codes: 'E2003|E2010'; Check: TPitfallCheck.Patterns; Line: 'TBitmap'; Rule: 'uses-order-hides-type'),
    (Codes: 'E2018'; Check: TPitfallCheck.Patterns; Line: 'Caption.|Text.'; Rule: 'caption-string-helper'),
    (Codes: 'E2211|E2037'; Check: TPitfallCheck.Patterns; Names: 'GetGlyph'; Rule: 'signature-mismatch'),
    (Codes: 'W1000'; Check: TPitfallCheck.Patterns; Names: 'TScrollStyle'; Rule: 'deprecated-symbol'),
    (Codes: 'W1010'; Check: TPitfallCheck.Patterns; Names: 'Dispatch|DoClose|CanResize'),
    (Codes: 'E2003'; Check: TPitfallCheck.DeclaredInUnit));

  cFollowUps: array[0..2] of TFollowUp = (
    (Code: 'E2250'; After: 'E2003|E2010'),
    (Code: 'F2063'; After: 'E'),
    (Code: 'F1026'; After: 'F2613'));

  cTitles: array[TCompilerPitfall] of TAtlasText = (
    (De: 'Zwei gleich gebaute Methodenreferenztypen'; En: 'Two method reference types of the same shape'),
    (De: 'Routine mit const-Parameter an TProc<…>'; En: 'Routine with const parameter passed to TProc<…>'),
    (De: 'Funktion mit Methodenreferenz-Ergebnis ohne () aufgerufen';
     En: 'Function returning a method reference called without ()'),
    (De: 'reference to direkt als Feld- oder Variablentyp'; En: 'reference to directly as field or variable type'),
    (De: 'TMonitor aus Vcl.Forms verdeckt den aus System'; En: 'TMonitor from Vcl.Forms hides the one from System'),
    (De: 'Record mit nil verglichen'; En: 'Record compared with nil'),
    (De: 'Aufzählungswert verdeckt Continue, Break oder Exit'; En: 'Enumeration value hides Continue, Break or Exit'),
    (De: 'Exit([...]) mit Array-Literal'; En: 'Exit([...]) with an array literal'),
    (De: 'Methodenreferenz in Exit(…) oder im Array-Literal aufgerufen';
     En: 'Method reference called in Exit(…) or in an array literal'),
    (De: 'Anonyme Methode als Argument einer Überladung'; En: 'Anonymous method as argument of an overload'),
    (De: 'Assert.AreEqual mit Length, High oder Count'; En: 'Assert.AreEqual with Length, High or Count'),
    (De: 'Rect(P1, P2) je nach uses-Reihenfolge'; En: 'Rect(P1, P2) depending on the uses order'),
    (De: 'Mitglied der Klasse verdeckt eine freie Routine'; En: 'Member of the class hides a free routine'),
    (De: 'Zugriff auf protected-Mitglied'; En: 'Access to a protected member'),
    (De: 'Feld nach Methoden im selben Abschnitt'; En: 'Field after methods in the same section'),
    (De: 'Zeile über 1023 Zeichen'; En: 'Line over 1023 characters'),
    (De: 'Unit der Inline-Funktion fehlt in uses'; En: 'Unit of the inline function missing in uses'),
    (De: 'Fehlt in Delphis Winapi.Windows'; En: 'Missing from Delphi''s Winapi.Windows'),
    (De: 'Winapi.Windows fehlt in uses'; En: 'Winapi.Windows missing in uses'),
    (De: 'System.Actions fehlt in uses'; En: 'System.Actions missing in uses'),
    (De: 'PaletteAPI fehlt in uses'; En: 'PaletteAPI missing in uses'),
    (De: 'DesignEditors fehlt in uses'; En: 'DesignEditors missing in uses'),
    (De: 'Vcl.Forms fehlt in uses'; En: 'Vcl.Forms missing in uses'),
    (De: 'System.SysUtils fehlt in uses'; En: 'System.SysUtils missing in uses'),
    (De: 'Winapi.Windows nach Vcl.Graphics verdeckt TBitmap'; En: 'Winapi.Windows after Vcl.Graphics hides TBitmap'),
    (De: 'TCaption hat keine String-Helfer'; En: 'TCaption has no string helpers'),
    (De: 'ToolsAPI-Signatur nicht genau übernommen'; En: 'ToolsAPI signature not copied exactly'),
    (De: 'Veralteter Typ TScrollStyle aus Vcl.StdCtrls'; En: 'Deprecated type TScrollStyle from Vcl.StdCtrls'),
    (De: 'Eigene Methode verdeckt eine virtuelle der VCL'; En: 'Own method hides a virtual one of the VCL'),
    (De: 'Name in der Unit deklariert, aber hier nicht sichtbar';
     En: 'Name declared in the unit but not visible here'));

  cReasons: array[TCompilerPitfall] of TAtlasText = (
    (De: 'Delphi 12 behandelt zwei Methodenreferenztypen mit gleicher Signatur als verschiedene Typen; Delphi 13 ' +
      'und Free Pascal nehmen die Zuweisung an.';
     En: 'Delphi 12 treats two method reference types with the same signature as different types; Delphi 13 and ' +
      'Free Pascal accept the assignment.'),
    (De: 'Eine Prozedur mit const AName: string passt nicht zu TProc<string>, dessen Parameter kein const hat.';
     En: 'A procedure with const AName: string does not fit TProc<string>, whose parameter has no const.'),
    (De: 'Ohne () nimmt Delphi die Funktion selbst statt der Methodenreferenz, die sie liefert.';
     En: 'Without () Delphi takes the function itself instead of the method reference it returns.'),
    (De: 'Delphi kennt reference to nur in einer Typdeklaration; als Feld- oder Variablentyp ist reference ein ' +
      'unbekannter Name.';
     En: 'Delphi knows reference to only in a type declaration; as a field or variable type reference is an ' +
      'unknown name.'),
    (De: 'Vcl.Forms deklariert eine Klasse TMonitor für Bildschirme; sie verdeckt den Monitor aus System, der Enter ' +
      'und Exit hat.';
     En: 'Vcl.Forms declares a class TMonitor for screens; it hides the monitor from System that has Enter and Exit.'),
    (De: 'Ein Record ist kein Zeiger; = nil und <> nil sind darauf nicht definiert (oft nach einem Typumbau von ' +
      'Klasse zu Record).';
     En: 'A record is not a pointer; = nil and <> nil are not defined on it (often after changing a class into a ' +
      'record).'),
    (De: 'Ein Aufzählungswert Continue, Break oder Exit ohne {$SCOPEDENUMS ON} verdeckt die Anweisung in der ganzen ' +
      'Unit; sie wird zum Ausdruck.';
     En: 'An enumeration value Continue, Break or Exit without {$SCOPEDENUMS ON} hides the statement in the whole ' +
      'unit; it becomes an expression.'),
    (De: 'Delphi liest die eckigen Klammern in Exit(...) als Mengenkonstruktor, nicht als Array-Literal; Free ' +
      'Pascal übersetzt es.';
     En: 'Delphi reads the brackets in Exit(...) as a set constructor, not as an array literal; Free Pascal compiles ' +
      'it.'),
    (De: 'In Exit(ARef) und in FListe + [ARef] ruft Delphi die Methodenreferenz auf, statt sie weiterzugeben.';
     En: 'In Exit(ARef) and in FList + [ARef] Delphi calls the method reference instead of passing it on.'),
    (De: 'Bei Überladungen erkennt Delphi den Typ einer anonymen Methode als Argument nicht immer; E2250 ist oft nur ' +
      'die Folge davon.';
     En: 'With overloads Delphi does not always infer the type of an anonymous method as argument; E2250 is often ' +
      'just the consequence.'),
    (De: 'Length, High und Count liefern seit Delphi 12 NativeInt; zu Integer passt dann keine Überladung von ' +
      'AreEqual eindeutig.';
     En: 'Length, High and Count return NativeInt since Delphi 12; with Integer no overload of AreEqual fits ' +
      'unambiguously.'),
    (De: 'Rect mit zwei Punkten gibt es je nach Reihenfolge von System.Types und Winapi.Windows in uses nicht.';
     En: 'Rect with two points does not exist depending on the order of System.Types and Winapi.Windows in uses.'),
    (De: 'In Methoden einer Klasse verdeckt ein geerbtes Mitglied (Scaled, AddLabel) die freie Routine gleichen ' +
      'Namens.';
     En: 'In methods of a class an inherited member (Scaled, AddLabel) hides the free routine of the same name.'),
    (De: 'Protected-Mitglieder wie TControl.Font sind außerhalb der Unit und der Ableitungen nicht sichtbar.';
     En: 'Protected members such as TControl.Font are not visible outside the unit and the descendants.'),
    (De: 'Delphi verlangt im selben Sichtbarkeitsabschnitt Felder vor Methoden und Properties; Free Pascal nimmt es ' +
      'an.';
     En: 'Delphi requires fields before methods and properties in the same visibility section; Free Pascal accepts ' +
      'it.'),
    (De: 'Je nach Delphi-Version bricht der Compiler bei Zeilen über 1023 Zeichen ab, auch in erzeugten Units.';
     En: 'Depending on the Delphi version the compiler stops at lines over 1023 characters, also in generated units.'),
    (De: 'Delphi setzt eine Inline-Funktion nur ein, wenn die Units ihres Rumpfs in uses stehen (z. B. ' +
      'System.Generics.Collections für TJSONArray, Winapi.Windows für RenameFile, System.UITypes für TFont.Style).';
     En: 'Delphi expands an inline function only if the units of its body are in uses (e.g. ' +
      'System.Generics.Collections for TJSONArray, Winapi.Windows for RenameFile, System.UITypes for TFont.Style).'),
    (De: 'Die Windows-Unit von Free Pascal deklariert den Namen, Delphis Winapi.Windows nicht.';
     En: 'The Windows unit of Free Pascal declares the name, Delphi''s Winapi.Windows does not.'),
    (De: 'Free Pascal findet die Routine auch in SysUtils, Delphi nur in Winapi.Windows.';
     En: 'Free Pascal also finds the routine in SysUtils, Delphi only in Winapi.Windows.'),
    (De: 'Delphi deklariert den Typ in System.Actions; Free Pascal verlangt die Unit nicht.';
     En: 'Delphi declares the type in System.Actions; Free Pascal does not require the unit.'),
    (De: 'Die Schnittstelle der Werkzeugpalette steht in PaletteAPI, nicht in ToolsAPI.';
     En: 'The interface of the tool palette is in PaletteAPI, not in ToolsAPI.'),
    (De: 'GetComponentEditor steht in DesignEditors.'; En: 'GetComponentEditor is in DesignEditors.'),
    (De: 'Delphi deklariert TScrollBox in Vcl.Forms.'; En: 'Delphi declares TScrollBox in Vcl.Forms.'),
    (De: 'TFunc und TProc stehen in System.SysUtils; Free Pascal findet sie auch ohne.';
     En: 'TFunc and TProc are in System.SysUtils; Free Pascal finds them without it too.'),
    (De: 'Die letzte Unit in uses gewinnt: Nach Vcl.Graphics meint TBitmap den Record aus Winapi.Windows.';
     En: 'The last unit in uses wins: after Vcl.Graphics TBitmap means the record from Winapi.Windows.'),
    (De: 'TCaption ist ein eigener Typ (type string); der String-Helfer gilt dafür nicht.';
     En: 'TCaption is a distinct type (type string); the string helper does not apply to it.'),
    (De: 'Unter Win64 sind THandle und Cardinal verschieden; die Signatur muss genau wie in ToolsAPI lauten.';
     En: 'Under Win64 THandle and Cardinal differ; the signature must be exactly as in ToolsAPI.'),
    (De: 'TScrollStyle aus Vcl.StdCtrls ist veraltet (W1000); der Typ steht jetzt in System.UITypes.';
     En: 'TScrollStyle from Vcl.StdCtrls is deprecated (W1000); the type now lives in System.UITypes.'),
    (De: 'Eine eigene Methode Dispatch, DoClose oder CanResize verdeckt die virtuelle Methode der VCL.';
     En: 'An own method Dispatch, DoClose or CanResize hides the virtual method of the VCL.'),
    (De: 'Der Name steht in dieser Unit, aber in einer anderen Klasse, als geerbte Klassenkonstante in der ' +
      'Klassendeklaration oder als Methode in einer freien Routine; dort sieht Delphi ihn ohne Klassennamen nicht.';
     En: 'The name is in this unit, but in another class, as an inherited class constant in the class declaration ' +
      'or as a method in a free routine; there Delphi does not see it without the class name.'));

  cFixes: array[TCompilerPitfall] of TAtlasText = (
    (De: 'Einen gemeinsamen Typ verwenden statt einen zweiten gleichen zu deklarieren.';
     En: 'Use one shared type instead of declaring a second identical one.'),
    (De: 'Parameter ohne const deklarieren oder eine anonyme Methode dazwischen setzen.';
     En: 'Declare the parameter without const or put an anonymous method in between.'),
    (De: 'Die Funktion mit () aufrufen: mFilter := FilterOf();';
     En: 'Call the function with (): mFilter := FilterOf();'),
    (De: 'Einen benannten Typ deklarieren (TMyFunc = reference to function …) und ihn verwenden.';
     En: 'Declare a named type (TMyFunc = reference to function …) and use it.'),
    (De: 'TMonitor mit dem Unit-Namen System qualifizieren.'; En: 'Qualify TMonitor with the unit name System.'),
    (De: 'Ein Feld des Records prüfen oder mit Default(…) vergleichen.';
     En: 'Check a field of the record or compare with Default(…).'),
    (De: '{$SCOPEDENUMS ON} vor die Aufzählung setzen oder den Wert umbenennen.';
     En: 'Put {$SCOPEDENUMS ON} before the enumeration or rename the value.'),
    (De: 'Erst Result := [...]; zuweisen, dann Exit;'; En: 'First assign Result := [...]; then Exit;'),
    (De: 'Result := ARef; Exit; schreiben bzw. SetLength und das Element zuweisen.';
     En: 'Write Result := ARef; Exit; or use SetLength and assign the element.'),
    (De: 'Die anonyme Methode erst einer typisierten Variablen zuweisen oder eine benannte Methode übergeben.';
     En: 'Assign the anonymous method to a typed variable first or pass a named method.'),
    (De: 'Die NativeInt-Seite in Integer(...) setzen.'; En: 'Wrap the NativeInt side in Integer(...).'),
    (De: 'TRect.Create(P1, P2) schreiben.'; En: 'Write TRect.Create(P1, P2).'),
    (De: 'Die freie Routine umbenennen.'; En: 'Rename the free routine.'),
    (De: 'Über eine Zugriffsklasse gehen: TControlAccess = class(TControl) und TControlAccess(AControl).Font.';
     En: 'Go through an access class: TControlAccess = class(TControl) and TControlAccess(AControl).Font.'),
    (De: 'Das Feld an den Anfang des Abschnitts setzen oder var davor schreiben.';
     En: 'Move the field to the start of the section or write var before it.'),
    (De: 'Lange Literale umbrechen, auch in erzeugten Units.'; En: 'Wrap long literals, also in generated units.'),
    (De: 'Die Unit aus der Meldung in uses ergänzen.'; En: 'Add the unit from the message to uses.'),
    (De: 'Die Konstante bzw. Routine selbst deklarieren.'; En: 'Declare the constant or routine yourself.'),
    (De: 'Winapi.Windows in uses ergänzen.'; En: 'Add Winapi.Windows to uses.'),
    (De: 'System.Actions in uses ergänzen.'; En: 'Add System.Actions to uses.'),
    (De: 'PaletteAPI in uses ergänzen.'; En: 'Add PaletteAPI to uses.'),
    (De: 'DesignEditors in uses ergänzen.'; En: 'Add DesignEditors to uses.'),
    (De: 'Vcl.Forms in uses ergänzen.'; En: 'Add Vcl.Forms to uses.'),
    (De: 'System.SysUtils in uses ergänzen.'; En: 'Add System.SysUtils to uses.'),
    (De: 'Winapi.Windows vor Vcl.Graphics in uses setzen.'; En: 'Put Winapi.Windows before Vcl.Graphics in uses.'),
    (De: 'Den Ausdruck in string(...) setzen.'; En: 'Wrap the expression in string(...).'),
    (De: 'Die Signatur aus ToolsAPI übernehmen, z. B. GetGlyph: THandle statt Cardinal.';
     En: 'Copy the signature from ToolsAPI, e.g. GetGlyph: THandle instead of Cardinal.'),
    (De: 'System.UITypes.TScrollStyle schreiben.'; En: 'Write System.UITypes.TScrollStyle.'),
    (De: 'Einen anderen Namen wählen oder override ergänzen, wenn die VCL-Methode gemeint ist.';
     En: 'Choose another name, or add override if the VCL method is meant.'),
    (De: 'Mit dem Klassennamen bzw. dem Objekt qualifizieren: TBasis.cGap, AFrame.ListSelectItem.';
     En: 'Qualify with the class name or the object: TBase.cGap, AFrame.ListSelectItem.'));

{ TPitfallMessage }

class function TPitfallMessage.Create(const ACode, AText: string; ALine: Integer): TPitfallMessage;
begin
  Result.Code := UpperCase(Trim(ACode));
  Result.Text := AText;
  Result.Line := ALine;
end;

{ Hilfen }

function Parts(const AList: string): TArray<string>;
begin
  Result := nil;
  if AList <> '' then
  begin
    Result := AList.Split(['|']);
  end;
end;

/// <summary>Steht APattern in ALine? Beginnt bzw. endet das Muster mit einem Buchstaben, muss es dort an einer
/// Wortgrenze stehen (Rect( nicht in BoundsRect(, Exit nicht in ExitCode).</summary>
function ContainsPattern(const ALine, APattern: string): Boolean;
var
  mStart, mEnd: Integer;
  mOpenStart, mOpenEnd: Boolean;
begin
  mStart := Pos(UpperCase(APattern), UpperCase(ALine));
  while mStart > 0 do
  begin
    mEnd := mStart + Length(APattern);
    mOpenStart := TTextChars.IsIdentChar(APattern[1]) and (mStart > 1) and TTextChars.IsIdentChar(ALine[mStart - 1]);
    mOpenEnd := TTextChars.IsIdentChar(APattern[Length(APattern)]) and (mEnd <= Length(ALine)) and
      TTextChars.IsIdentChar(ALine[mEnd]);
    if not mOpenStart and not mOpenEnd then
    begin
      Exit(True);
    end;
    mStart := PosEx(UpperCase(APattern), UpperCase(ALine), mStart + 1);
  end;
  Result := False;
end;

/// <summary>Erstes Muster aus AList, das in ALine steht; '' ohne.</summary>
function FirstPattern(const ALine, AList: string): string;
var
  mPattern: string;
begin
  for mPattern in Parts(AList) do
  begin
    if ContainsPattern(ALine, mPattern) then
    begin
      Exit(mPattern);
    end;
  end;
  Result := '';
end;

/// <summary>Passt der Name AName aus der Meldung zum Muster? * am Ende: Anfang des Namens; Namespaces vorn zählen
/// nicht (System.SysUtils.TProc&lt;string&gt; passt zu TProc&lt;*).</summary>
function NameMatches(const AName, APattern: string): Boolean;
var
  mHead, mBare: string;
begin
  mHead := AName;
  if Pos('<', mHead) > 0 then
  begin
    mHead := Copy(mHead, 1, Pos('<', mHead) - 1);
  end;
  mBare := Copy(AName, LastDelimiter('.', mHead) + 1, MaxInt);
  if EndsStr('*', APattern) then
  begin
    Result := StartsText(Copy(APattern, 1, Length(APattern) - 1), mBare);
  end
  else
  begin
    Result := SameText(mBare, APattern);
  end;
end;

/// <summary>Erster Name der Meldung, der zu einem Muster aus AList passt; '' ohne.</summary>
function FirstName(const ANames: TArray<string>; const AList: string): string;
var
  mName, mPattern: string;
begin
  for mName in ANames do
  begin
    for mPattern in Parts(AList) do
    begin
      if NameMatches(mName, mPattern) then
      begin
        Exit(mName);
      end;
    end;
  end;
  Result := '';
end;

/// <summary>Beginnt die Zeile ALine (ohne Einrückung) mit dem Bezeichner AName, gefolgt von AFollower?</summary>
function DeclaresAs(const ALine, AName, AFollower: string): Boolean;
var
  mRest: string;
begin
  mRest := TrimLeft(ALine);
  Result := StartsText(AName, mRest) and
    ((Length(mRest) = Length(AName)) or not TTextChars.IsIdentChar(mRest[Length(AName) + 1]));
  if Result then
  begin
    Result := StartsText(AFollower, TrimLeft(Copy(mRest, Length(AName) + 1, MaxInt)));
  end;
end;

/// <summary>Ist AName in ALines als Methodenreferenztyp deklariert (AName = reference to …)?</summary>
function IsReferenceType(const ALines: TArray<string>; const AName: string): Boolean;
var
  mLine, mRest: string;
begin
  for mLine in ALines do
  begin
    if DeclaresAs(mLine, AName, '=') then
    begin
      mRest := TrimLeft(Copy(TrimLeft(mLine), Length(AName) + 1, MaxInt));
      mRest := TrimLeft(Copy(mRest, 2, MaxInt));
      if StartsText('reference', mRest) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Deklariert die Zeile ALine (ohne Einrückung) AName als Konstante, Feld, Variable oder Routine?
/// </summary>
function IsDeclarationOf(const ALine, AName: string): Boolean;
begin
  if StartsText('procedure ', ALine) or StartsText('function ', ALine) then
  begin
    Result := ContainsPattern(ALine, '.' + AName) or DeclaresAs(Copy(ALine, Pos(' ', ALine) + 1, MaxInt), AName, '');
  end
  else
  begin
    Result := DeclaresAs(ALine, AName, '=') or DeclaresAs(ALine, AName, ':');
  end;
end;

/// <summary>Ist AName in ALines außerhalb der Zeile ALine deklariert?</summary>
function IsDeclaredElsewhere(const ALines: TArray<string>; ALine: Integer; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALines) do
  begin
    if (mIndex <> ALine) and IsDeclarationOf(TrimLeft(ALines[mIndex]), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function CodeIn(const ACode, ACodes: string): Boolean;
begin
  Result := IndexText(ACode, Parts(ACodes)) >= 0;
end;

/// <summary>Merkmal der Muster in der Zeile ALineText bzw. den Namen ANames; '' = passt nicht.</summary>
function PatternEvidence(const AData: TPitfallData; const ANames: TArray<string>; const ALineText: string): string;
var
  mLinePart: string;
begin
  Result := '';
  if AData.Names <> '' then
  begin
    Result := FirstName(ANames, AData.Names);
    if Result = '' then
    begin
      Exit;
    end;
  end;
  if AData.Line <> '' then
  begin
    mLinePart := FirstPattern(ALineText, AData.Line);
    if (mLinePart = '') or ((AData.LineAlso <> '') and (FirstPattern(ALineText, AData.LineAlso) = '')) or
      ((AData.LineNot <> '') and (FirstPattern(ALineText, AData.LineNot) <> '')) then
    begin
      Exit('');
    end;
    Result := mLinePart;
  end;
end;

/// <summary>Merkmal von APitfall an der Stelle; '' = keins.</summary>
function Evidence(APitfall: TCompilerPitfall; const ANames, ALines: TArray<string>; ALine: Integer): string;
var
  mLineText: string;
begin
  Result := '';
  mLineText := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    mLineText := ALines[ALine];
  end;
  case cData[APitfall].Check of
    TPitfallCheck.Patterns:
      Result := PatternEvidence(cData[APitfall], ANames, mLineText);
    TPitfallCheck.CodeOnly:
      Result := cData[APitfall].Codes;
    TPitfallCheck.ReferenceTwins:
      if (Length(ANames) >= 2) and IsReferenceType(ALines, ANames[0]) and IsReferenceType(ALines, ANames[1]) then
      begin
        Result := ANames[0] + ', ' + ANames[1];
      end;
    TPitfallCheck.DeclaredInUnit:
      if (Length(ANames) > 0) and IsDeclaredElsewhere(ALines, ALine, ANames[0]) then
      begin
        Result := ANames[0];
      end;
    TPitfallCheck.LongLine:
      if Length(mLineText) > cLongLine then
      begin
        Result := IntToStr(Length(mLineText));
      end;
  end;
end;

function MatchOf(APitfall: TCompilerPitfall; AMarked: Boolean; const AEvidence: string): TPitfallMatch;
begin
  Result.Pitfall := APitfall;
  Result.Marked := AMarked;
  Result.Evidence := AEvidence;
end;

{ TCompilerPitfalls }

class function TCompilerPitfalls.Info(APitfall: TCompilerPitfall; ALanguage: TTextLanguage): TCompilerPitfallInfo;
begin
  Result.Pitfall := APitfall;
  Result.Id := cIds[APitfall];
  Result.Title := cTitles[APitfall].TextIn(ALanguage);
  Result.Reason := cReasons[APitfall].TextIn(ALanguage);
  Result.Fix := cFixes[APitfall].TextIn(ALanguage);
  Result.Rule := cData[APitfall].Rule;
  Result.FixKind := cData[APitfall].Fix;
  Result.UsesUnit := cData[APitfall].UsesUnit;
end;

class function TCompilerPitfalls.Codes(APitfall: TCompilerPitfall): TArray<string>;
begin
  Result := Parts(cData[APitfall].Codes);
end;

class function TCompilerPitfalls.Knows(const ACode: string): Boolean;
var
  mPitfall: TCompilerPitfall;
begin
  for mPitfall := Low(TCompilerPitfall) to High(TCompilerPitfall) do
  begin
    if CodeIn(Trim(ACode), cData[mPitfall].Codes) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompilerPitfalls.Match(const AMessage: TPitfallMessage; const ASource: string): TArray<TPitfallMatch>;
var
  mPitfall: TCompilerPitfall;
  mNames, mLines: TArray<string>;
  mEvidence: string;
  mOthers: TArray<TPitfallMatch>;
begin
  Result := nil;
  mOthers := nil;
  mNames := TCompilerFixes.QuotedNames(AMessage.Text);
  mLines := nil;
  if (ASource <> '') and (AMessage.Line >= 0) then
  begin
    mLines := TTextLines.SplitLines(ASource);
  end;
  for mPitfall := Low(TCompilerPitfall) to High(TCompilerPitfall) do
  begin
    if CodeIn(AMessage.Code, cData[mPitfall].Codes) then
    begin
      mEvidence := '';
      if mLines <> nil then
      begin
        mEvidence := Evidence(mPitfall, mNames, mLines, AMessage.Line);
      end;
      if mEvidence <> '' then
      begin
        Result := Result + [MatchOf(mPitfall, True, mEvidence)];
      end
      else
      begin
        mOthers := mOthers + [MatchOf(mPitfall, False, '')];
      end;
    end;
  end;
  Result := Result + mOthers;
end;

class function TCompilerPitfalls.IsFollowUp(const ACode: string; const APrevious: TArray<string>;
  out ACause: string): Boolean;
var
  mFollowUp: TFollowUp;
  mPrevious: string;
begin
  ACause := '';
  for mFollowUp in cFollowUps do
  begin
    if SameText(mFollowUp.Code, ACode) then
    begin
      for mPrevious in APrevious do
      begin
        if CodeIn(mPrevious, mFollowUp.After) or ((mFollowUp.After = 'E') and StartsText('E', mPrevious)) then
        begin
          ACause := UpperCase(mPrevious);
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.CompilerPitfalls.Titles', cTitles);
  TAtlasTextTables.Add('Atlas.Common.Rules.CompilerPitfalls.Reasons', cReasons);
  TAtlasTextTables.Add('Atlas.Common.Rules.CompilerPitfalls.Fixes', cFixes);

end.
