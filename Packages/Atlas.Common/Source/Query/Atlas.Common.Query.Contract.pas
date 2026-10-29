unit Atlas.Common.Query.Contract;

// Contract des Platform-Features Query (#1351): Code-Abfragen über den Index.
//
//   <Menge> [where <Bedingung>] [order by <Feld> [asc|desc]] [limit n]
//
// Eine Abfrage liefert Zeilen je Element der Menge (Unit, Klasse, Methode …)
// mit den Werten der abgefragten Felder. Die Felder stammen aus vorhandenen
// Diensten: Symbolindex, Metriken, Uses-Graph und Aufrufhierarchie; eine
// eigene zweite Datenhaltung gibt es nicht. Aufrufer und Aufgerufene kommen
// über TQueryCallsFunc herein, damit das Feature die LSP-Schicht nicht kennt.
//
// ICodeQueries ist der Dienst je Arbeitsbereich: IDE-Fenster, MCP query_code,
// --query und die Regeln query:<name> fragen ihn, er rechnet je Index-Stand
// und Abfrage einmal.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  TQueryValueKind = (None, Number, Text, Flag);

  /// <summary>Wert eines Felds: Zahl, Text, Wahrheitswert oder None (das Element hat das Feld nicht, etwa die
  /// Komplexität einer abstrakten Methode).</summary>
  TQueryValue = record
    Kind: TQueryValueKind;
    Number: Int64;
    Text: string;
    class function Empty: TQueryValue; static;
    class function OfNumber(AValue: Int64): TQueryValue; static;
    class function OfText(const AValue: string): TQueryValue; static;
    class function OfFlag(AValue: Boolean): TQueryValue; static;
    /// <summary>Anzeige: Zahl, Text, "ja"/"nein"; '' bei None.</summary>
    function Display: string;
  end;

  /// <summary>Ein Treffer der Abfrage.</summary>
  TQueryRow = record
    /// <summary>Name des Elements (Methode ohne Klasse, Unit mit Punkten).</summary>
    Name: string;
    /// <summary>Umgebender Typ bei Methoden, Feldern und Properties; sonst ''.</summary>
    Container: string;
    UnitName: string;
    /// <summary>Absoluter Pfad der Datei mit der Deklaration.</summary>
    FileName: string;
    /// <summary>Pfad relativ zur Wurzel der Abfrage mit "/".</summary>
    Path: string;
    /// <summary>Name in der Deklaration (Sprungziel, Stelle des Befunds).</summary>
    Range: TTextRange;
    /// <summary>Werte je Spalte von TQueryResult.Columns.</summary>
    Values: TArray<TQueryValue>;
    /// <summary>Ein Wert stützt sich auf erschlossene Aufrufe (#1119); Inferred nennt den Grund.</summary>
    Inferred: Boolean;
    InferredDetail: string;
    /// <summary>Container.Name bzw. Name.</summary>
    function QualifiedName: string;
  end;

  /// <summary>Ergebnis einer Abfrage. Bei einem Fehler stehen Meldung, Spalte (ab 1) und Vorschlag im Ergebnis,
  /// Rows bleibt leer.</summary>
  TQueryResult = record
    Query: string;
    /// <summary>Abgefragte Menge in Kleinschreibung (classes, methods …).</summary>
    Entity: string;
    /// <summary>Feldnamen der Werte: name, unit, line, dann die Felder der Bedingung, der Sortierung und weitere
    /// angeforderte.</summary>
    Columns: TArray<string>;
    Rows: TArray<TQueryRow>;
    /// <summary>Treffer vor limit.</summary>
    Total: Integer;
    /// <summary>Treffer, die sich auf erschlossene Aufrufe stützen.</summary>
    InferredCount: Integer;
    ElapsedMs: Int64;
    Error: string;
    /// <summary>Spalte des Fehlers in der Abfrage ab 1; 0 ohne.</summary>
    ErrorColumn: Integer;
    /// <summary>Vorschlag zum Fehler, etwa der gemeinte Feldname; '' ohne.</summary>
    Suggestion: string;
    function Failed: Boolean;
    /// <summary>Spalte AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function ColumnOf(const AName: string): Integer;
    /// <summary>Wurde limit wirksam?</summary>
    function Truncated: Boolean;
    /// <summary>Angezeigter Wert der Spalte AColumn in ARow; '' ohne.</summary>
    class function CellText(const ARow: TQueryRow; AColumn: Integer): string; static;
    /// <summary>Meldung einer gespeicherten Abfrage: {feld} durch den Wert der Spalte ersetzt, {query} durch die
    /// Abfrage, {path} durch den Pfad; unbekannte Platzhalter bleiben stehen. '' = Vorgabetext.</summary>
    function Message(const ATemplate: string; const ARow: TQueryRow): string;
    /// <summary>Felder in geschweiften Klammern aus ATemplate ({name} → name), in Reihenfolge.</summary>
    class function Placeholders(const ATemplate: string): TArray<string>; static;
  end;

  /// <summary>Ein Aufrufer bzw. Aufgerufener aus der Aufrufhierarchie (#1119, #1122).</summary>
  TQueryCall = record
    /// <summary>Qualifiziert: TFoo.Bar bzw. Name einer Routine.</summary>
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>Erschlossen statt sicher, mit Grund ("interface", "virtual" …).</summary>
    Inferred: Boolean;
    Reason: string;
  end;

  /// <summary>Aufrufer (AIncoming) bzw. aufgerufene Routinen des Symbols ALocation; nil ohne Treffer.</summary>
  TQueryCallsFunc = reference to function(const ALocation: TSymbolLocation; AIncoming: Boolean): TArray<TQueryCall>;

  /// <summary>Text einer Datei (geöffnete Dokumente zuerst); False, wenn sie fehlt.</summary>
  TQueryReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>True, wenn die Auswertung abbrechen soll (Fenster, Zeitlimit).</summary>
  TQueryCancelled = reference to function: Boolean;

  /// <summary>Daten, über die eine Abfrage läuft.</summary>
  TQuerySource = record
    Index: ISymbolIndex;
    /// <summary>Wurzel für TQueryRow.Path.</summary>
    Root: string;
    /// <summary>Dateien im Umfang (Projekte der Gruppe); leer = alle Units des Index ohne Bibliothek.</summary>
    Files: TArray<string>;
    /// <summary>Namensräume für uses ohne Präfix (SysUtils → System.SysUtils).</summary>
    Namespaces: TArray<string>;
    ReadText: TQueryReadText;
    /// <summary>Aufrufhierarchie; nil = callers, callees und calls haben keinen Wert.</summary>
    Calls: TQueryCallsFunc;
    Cancelled: TQueryCancelled;
  end;

  /// <summary>Eine Anfrage an ICodeQueries.</summary>
  TQueryRequest = record
    Query: string;
    /// <summary>Weitere Spalten, z. B. Felder der Meldung einer gespeicherten Abfrage.</summary>
    Fields: TArray<string>;
    /// <summary>Höchstzahl der Zeilen; 0 = ohne Grenze (limit der Abfrage gilt zusätzlich).</summary>
    Limit: Integer;
    /// <summary>Abbruch dieser Anfrage (LSP $/cancelRequest, Knopf „Abbrechen“); nil = nur der Abbruch der Quelle.
    /// </summary>
    Cancelled: TQueryCancelled;
    class function Create(const AQuery: string; ALimit: Integer): TQueryRequest; static;
  end;

  /// <summary>Code-Abfragen eines Arbeitsbereichs (#1351). Threadsicher; ein Ergebnis gilt, solange Index und
  /// Umfang gleich bleiben.</summary>
  ICodeQueries = interface
    ['{5B8E2D47-0C93-4F1A-A6D2-93E7C41B58F0}']
    function Execute(const ARequest: TQueryRequest): TQueryResult;
  end;

implementation

uses
  System.SysUtils;

{ TQueryValue }

class function TQueryValue.Empty: TQueryValue;
begin
  Result := Default(TQueryValue);
end;

class function TQueryValue.OfNumber(AValue: Int64): TQueryValue;
begin
  Result := Default(TQueryValue);
  Result.Kind := TQueryValueKind.Number;
  Result.Number := AValue;
end;

class function TQueryValue.OfText(const AValue: string): TQueryValue;
begin
  Result := Default(TQueryValue);
  Result.Kind := TQueryValueKind.Text;
  Result.Text := AValue;
end;

class function TQueryValue.OfFlag(AValue: Boolean): TQueryValue;
begin
  Result := Default(TQueryValue);
  Result.Kind := TQueryValueKind.Flag;
  if AValue then
    Result.Number := 1;
end;

function TQueryValue.Display: string;
begin
  case Kind of
    TQueryValueKind.Number:
      Result := IntToStr(Number);
    TQueryValueKind.Text:
      Result := Text;
    TQueryValueKind.Flag:
      if Number <> 0 then
        Result := 'ja'
      else
        Result := 'nein';
  else
    Result := '';
  end;
end;

{ TQueryRow }

function TQueryRow.QualifiedName: string;
begin
  if Container = '' then
    Result := Name
  else
    Result := Container + '.' + Name;
end;

{ TQueryResult }

function TQueryResult.Failed: Boolean;
begin
  Result := Error <> '';
end;

function TQueryResult.ColumnOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Columns) do
    if SameText(Columns[mIndex], AName) then
      Exit(mIndex);
  Result := -1;
end;

function TQueryResult.Truncated: Boolean;
begin
  Result := Total > Length(Rows);
end;

class function TQueryResult.CellText(const ARow: TQueryRow; AColumn: Integer): string;
begin
  if (AColumn >= 0) and (AColumn <= High(ARow.Values)) then
    Result := ARow.Values[AColumn].Display
  else
    Result := '';
end;

class function TQueryResult.Placeholders(const ATemplate: string): TArray<string>;
var
  mStart, mStop: Integer;
begin
  Result := nil;
  mStart := Pos('{', ATemplate);
  while mStart > 0 do
  begin
    mStop := Pos('}', ATemplate, mStart + 1);
    if mStop = 0 then
      Break;
    Result := Result + [Copy(ATemplate, mStart + 1, mStop - mStart - 1)];
    mStart := Pos('{', ATemplate, mStop + 1);
  end;
end;

function TQueryResult.Message(const ATemplate: string; const ARow: TQueryRow): string;
var
  mName: string;
  mColumn: Integer;
begin
  Result := ATemplate;
  if Result = '' then
    Result := '{name}: Treffer der Abfrage {query}';
  for mName in Placeholders(Result) do
  begin
    mColumn := ColumnOf(mName);
    if mColumn >= 0 then
      Result := StringReplace(Result, '{' + mName + '}', CellText(ARow, mColumn), [rfReplaceAll])
    else if SameText(mName, 'query') then
      Result := StringReplace(Result, '{' + mName + '}', Query, [rfReplaceAll])
    else if SameText(mName, 'path') then
      Result := StringReplace(Result, '{' + mName + '}', ARow.Path, [rfReplaceAll]);
  end;
end;

{ TQueryRequest }

class function TQueryRequest.Create(const AQuery: string; ALimit: Integer): TQueryRequest;
begin
  Result := Default(TQueryRequest);
  Result.Query := AQuery;
  Result.Limit := ALimit;
end;

end.
