unit Atlas.Core.Problems.Store;

// Probleme je Datei (#398), nur im Hauptthread benutzt. Jede Datei merkt sich
// den Text, auf den sich die Positionen beziehen.
// - Update: neue Diagnosen des Servers für einen Text. Atlas-Meldungen werden
//   ersetzt; Compilermeldungen (dcc) nur mit AReplaceCompiler (erste Meldung,
//   nach workspace/diagnostic/refresh, nicht geöffnete Dateien), sonst
//   behält die Datei ihre mitgewanderten Compilermeldungen: Der Server liefert
//   sie an den Zeilen des letzten Compiles, auch wenn der Text sich seither
//   verschoben hat.
// - Edit: Der Editortext hat sich geändert. Zeilen vor und hinter der
//   geänderten Stelle bleiben bzw. verschieben sich um die Zahl eingefügter
//   oder gelöschter Zeilen; Meldungen in der geänderten Stelle werden blass
//   (Stale). Compilermeldungen werden nach jeder Änderung blass, bis zum
//   nächsten Compile.
// Version zählt jede Änderung, damit Zeichner und Liste nur bei Bedarf
// neu aufbauen.
// Inaktive {$IFDEF}-Zweige (#615) liefert InactiveSpans je Zeile als Spalten
// des Editors, auch für Zweige, die innerhalb einer Zeile beginnen oder enden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract;

type
  /// <summary>Spalten einer Editorzeile (1-basiert, Tabs aufgelöst), Last einschließlich;
  /// Last = MaxInt bis zum Zeilenende.</summary>
  TAtlasColumnSpan = record
    First: Integer;
    Last: Integer;
    class function Create(AFirst, ALast: Integer): TAtlasColumnSpan; static;
    /// <summary>Liegt die Spalte in einem der Bereiche?</summary>
    class function Contains(const ASpans: TArray<TAtlasColumnSpan>; AColumn: Integer): Boolean; static;
    /// <summary>Liegen alle Spalten AColumn .. AColumn + ACount - 1 in den Bereichen?</summary>
    class function Covers(const ASpans: TArray<TAtlasColumnSpan>; AColumn, ACount: Integer): Boolean; static;
  end;

  TAtlasProblemStore = class
  private type
    TEntry = class
      FileName: string;
      Text: string;
      TextKnown: Boolean;
      ResultId: string;
      Atlas: TArray<TAtlasProblem>;
      Compiler: TArray<TAtlasProblem>;
      // ForFile bzw. Inactive, bis sich etwas ändert.
      Visible: TArray<TAtlasProblem>;
      VisibleValid: Boolean;
      InactiveList: TArray<TAtlasProblem>;
      InactiveValid: Boolean;
      // Zeilen von Text, bei Bedarf.
      Lines: TArray<string>;
      LinesValid: Boolean;
    end;
  private
    FEntries: TObjectDictionary<string, TEntry>;
    FVersion: Integer;
    function Find(const AFileName: string): TEntry;
    function Ensure(const AFileName: string): TEntry;
    class procedure Shift(AEntry: TEntry; const ANewText: string); static;
  public
    constructor Create;
    destructor Destroy; override;
    class function Key(const AFileName: string): string; static;
    /// <summary>Diagnosen des Servers für AText (ATextKnown = False: Text unbekannt, etwa von der Platte).</summary>
    procedure Update(const AFileName, AText: string; ATextKnown: Boolean; const AProblems: TArray<TAtlasProblem>;
      const AResultId: string; AReplaceCompiler: Boolean);
    /// <summary>Editortext geändert: Positionen mitführen.</summary>
    procedure Edit(const AFileName, ANewText: string);
    procedure Remove(const AFileName: string);
    procedure Clear;
    function Contains(const AFileName: string): Boolean;
    function ResultId(const AFileName: string): string;
    /// <summary>Probleme der Datei ohne inaktive Bereiche und ohne Doppelte, nach Position.</summary>
    function ForFile(const AFileName: string): TArray<TAtlasProblem>;
    /// <summary>Inaktive {$IFDEF}-Zweige der Datei (Diagnosen mit Tag Unnecessary, #615).</summary>
    function Inactive(const AFileName: string): TArray<TAtlasProblem>;
    /// <summary>Liegt die ganze Zeile (0-basiert) in einem inaktiven Zweig?</summary>
    function LineInactive(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Inaktive Spalten der Zeile (0-basiert) für die Tabweite ATabWidth: ganze Zeilen und, bei
    /// bekanntem Text, Teile von Zeilen ({$IFDEF X} a {$ENDIF}). Blasse Bereiche (geänderte Stelle) nur
    /// als ganze Zeilen, bis neue Diagnosen da sind.</summary>
    function InactiveSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
    /// <summary>Inaktive Bereiche an der Stelle (0-basiert), für den Hinweis im Tooltip.</summary>
    function InactiveAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
    /// <summary>Probleme, die die Zeile (0-basiert) berühren.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasProblem>;
    /// <summary>Probleme an der Stelle (0-basiert).</summary>
    function At(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
    /// <summary>Text, auf den sich die Positionen beziehen; '' wenn unbekannt.</summary>
    function TextOf(const AFileName: string): string;
    /// <summary>Zeile (0-basiert, ohne #13) des Texts, auf den sich die Positionen beziehen.</summary>
    function LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
    /// <summary>Dateien mit Problemen, nach Namen sortiert.</summary>
    function Files: TArray<string>;
    property Version: Integer read FVersion;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  Atlas.Core.Editor.Pairs;

{ TAtlasColumnSpan }

class function TAtlasColumnSpan.Create(AFirst, ALast: Integer): TAtlasColumnSpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

class function TAtlasColumnSpan.Contains(const ASpans: TArray<TAtlasColumnSpan>; AColumn: Integer): Boolean;
var
  Span: TAtlasColumnSpan;
begin
  for Span in ASpans do
    if (AColumn >= Span.First) and (AColumn <= Span.Last) then
      Exit(True);
  Result := False;
end;

class function TAtlasColumnSpan.Covers(const ASpans: TArray<TAtlasColumnSpan>; AColumn, ACount: Integer): Boolean;
var
  Column: Integer;
begin
  for Column := AColumn to AColumn + ACount - 1 do
    if not Contains(ASpans, Column) then
      Exit(False);
  Result := ACount > 0;
end;

{ TAtlasProblemStore }

constructor TAtlasProblemStore.Create;
begin
  inherited Create;
  FEntries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
end;

destructor TAtlasProblemStore.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

class function TAtlasProblemStore.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TAtlasProblemStore.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
    Result := nil;
end;

function TAtlasProblemStore.Ensure(const AFileName: string): TEntry;
begin
  Result := Find(AFileName);
  if Result = nil then
  begin
    Result := TEntry.Create;
    Result.FileName := AFileName;
    FEntries.Add(Key(AFileName), Result);
  end;
end;

procedure TAtlasProblemStore.Update(const AFileName, AText: string; ATextKnown: Boolean;
  const AProblems: TArray<TAtlasProblem>; const AResultId: string; AReplaceCompiler: Boolean);
var
  Entry: TEntry;
  IsNew: Boolean;
  Problem: TAtlasProblem;
  Compiler: TArray<TAtlasProblem>;
begin
  IsNew := Find(AFileName) = nil;
  Entry := Ensure(AFileName);
  // Behaltene Compilermeldungen auf den neuen Text bringen.
  if not IsNew and Entry.TextKnown and ATextKnown and (Entry.Text <> AText) then
    Shift(Entry, AText);
  Entry.Atlas := nil;
  Compiler := nil;
  for Problem in AProblems do
    if Problem.IsCompiler then
      Compiler := Compiler + [Problem]
    else
      Entry.Atlas := Entry.Atlas + [Problem];
  if IsNew or AReplaceCompiler then
    Entry.Compiler := Compiler;
  Entry.Text := AText;
  Entry.LinesValid := False;
  Entry.TextKnown := ATextKnown;
  Entry.ResultId := AResultId;
  Entry.VisibleValid := False;
  Entry.InactiveValid := False;
  Inc(FVersion);
end;

class procedure TAtlasProblemStore.Shift(AEntry: TEntry; const ANewText: string);
var
  OldLines, NewLines: TArray<string>;
  Prefix, Suffix, ChangedEnd, Delta, Index: Integer;

  procedure Map(var AProblem: TAtlasProblem; ACompiler: Boolean);
  begin
    if ACompiler then
      AProblem.Stale := True;
    if AProblem.EndLine < Prefix then
      Exit;
    if AProblem.StartLine >= ChangedEnd then
    begin
      Inc(AProblem.StartLine, Delta);
      Inc(AProblem.EndLine, Delta);
      Exit;
    end;
    // In der geänderten Stelle: bleibt stehen, aber blass und im Text.
    AProblem.Stale := True;
    AProblem.StartLine := EnsureRange(AProblem.StartLine, 0, Max(0, High(NewLines)));
    AProblem.EndLine := EnsureRange(AProblem.EndLine, AProblem.StartLine, Max(0, High(NewLines)));
  end;

begin
  OldLines := AEntry.Text.Split([#10]);
  NewLines := ANewText.Split([#10]);
  Prefix := 0;
  while (Prefix < Length(OldLines)) and (Prefix < Length(NewLines)) and (OldLines[Prefix] = NewLines[Prefix]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Length(OldLines) - Prefix) and (Suffix < Length(NewLines) - Prefix) and
    (OldLines[High(OldLines) - Suffix] = NewLines[High(NewLines) - Suffix]) do
    Inc(Suffix);
  ChangedEnd := Length(OldLines) - Suffix;
  Delta := Length(NewLines) - Length(OldLines);
  for Index := 0 to High(AEntry.Atlas) do
    Map(AEntry.Atlas[Index], False);
  for Index := 0 to High(AEntry.Compiler) do
    Map(AEntry.Compiler[Index], True);
  AEntry.Text := ANewText;
  AEntry.LinesValid := False;
  AEntry.VisibleValid := False;
  AEntry.InactiveValid := False;
end;

function TAtlasProblemStore.Inactive(const AFileName: string): TArray<TAtlasProblem>;
var
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  // Zeichnen fragt je Textlauf: nicht jedes Mal alle Meldungen durchgehen.
  if Entry.InactiveValid then
    Exit(Entry.InactiveList);
  for Problem in Entry.Atlas do
    if Problem.Unnecessary then
      Result := Result + [Problem];
  Entry.InactiveList := Result;
  Entry.InactiveValid := True;
end;

function TAtlasProblemStore.InactiveSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
var
  Problem: TAtlasProblem;
  Text: string;
  HasText: Boolean;
  First, Last: Integer;
begin
  Result := nil;
  HasText := False;
  Text := '';
  for Problem in Inactive(AFileName) do
  begin
    if (ALine < Problem.StartLine) or (ALine > Problem.EndLine) then
      Continue;
    // Zeilen zwischen den Direktiven ganz.
    if (ALine > Problem.StartLine) and (ALine < Problem.EndLine) then
    begin
      Result := Result + [TAtlasColumnSpan.Create(1, MaxInt)];
      Continue;
    end;
    // Erste bzw. letzte Zeile: ab dem Ende der öffnenden bis vor die schließende Direktive.
    if Problem.Stale then
      Continue;
    if not HasText then
    begin
      if not LineText(AFileName, ALine, Text) then
        Exit;
      HasText := True;
    end;
    if ALine = Problem.StartLine then
      First := TAtlasPairs.ColumnOf(Text, Min(Problem.StartCharacter, Length(Text)), ATabWidth)
    else
      First := 1;
    if ALine = Problem.EndLine then
      Last := TAtlasPairs.ColumnOf(Text, Min(Problem.EndCharacter, Length(Text)), ATabWidth) - 1
    else
      Last := MaxInt;
    // Nur Text dimmen, nicht das Zeilenende.
    if Last = MaxInt then
      Last := TAtlasPairs.ColumnOf(Text, Length(Text), ATabWidth) - 1;
    if Last >= First then
      Result := Result + [TAtlasColumnSpan.Create(First, Last)];
  end;
end;

function TAtlasProblemStore.InactiveAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
var
  Problem: TAtlasProblem;
begin
  Result := nil;
  for Problem in Inactive(AFileName) do
    // Das Ende gehört schon zur schließenden Direktive.
    if Problem.Contains(ALine, ACharacter) and
      ((ALine < Problem.EndLine) or (ACharacter < Problem.EndCharacter)) then
      Result := Result + [Problem];
end;

function TAtlasProblemStore.LineInactive(const AFileName: string; ALine: Integer): Boolean;
var
  Problem: TAtlasProblem;
begin
  // Ein Bereich beginnt hinter der Direktive, die den Zweig abschaltet, und endet vor der nächsten:
  // Die Zeilen dazwischen sind ganz inaktiv, die Zeilen der Direktiven selbst nicht.
  Result := False;
  for Problem in Inactive(AFileName) do
    if (ALine > Problem.StartLine) and (ALine < Problem.EndLine) then
      Exit(True);
end;

procedure TAtlasProblemStore.Edit(const AFileName, ANewText: string);
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if (Entry = nil) or (Entry.TextKnown and (Entry.Text = ANewText)) then
    Exit;
  if not Entry.TextKnown then
  begin
    // Positionen kamen ohne bekannten Text (Platte): ab jetzt diesen Text zugrunde legen.
    Entry.Text := ANewText;
    Entry.LinesValid := False;
    Entry.TextKnown := True;
    Exit;
  end;
  Shift(Entry, ANewText);
  Inc(FVersion);
end;

procedure TAtlasProblemStore.Remove(const AFileName: string);
begin
  if Find(AFileName) = nil then
    Exit;
  FEntries.Remove(Key(AFileName));
  Inc(FVersion);
end;

procedure TAtlasProblemStore.Clear;
begin
  if FEntries.Count = 0 then
    Exit;
  FEntries.Clear;
  Inc(FVersion);
end;

function TAtlasProblemStore.Contains(const AFileName: string): Boolean;
begin
  Result := Find(AFileName) <> nil;
end;

function TAtlasProblemStore.ResultId(const AFileName: string): string;
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if Entry = nil then
    Result := ''
  else
    Result := Entry.ResultId;
end;

function TAtlasProblemStore.TextOf(const AFileName: string): string;
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if (Entry = nil) or not Entry.TextKnown then
    Result := ''
  else
    Result := Entry.Text;
end;

function TAtlasProblemStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  Entry: TEntry;
begin
  AText := '';
  Entry := Find(AFileName);
  if (Entry = nil) or not Entry.TextKnown then
    Exit(False);
  if not Entry.LinesValid then
  begin
    Entry.Lines := Entry.Text.Split([#10]);
    Entry.LinesValid := True;
  end;
  Result := (ALine >= 0) and (ALine <= High(Entry.Lines));
  if Result then
    AText := Entry.Lines[ALine].TrimRight([#13]);
end;

function TAtlasProblemStore.ForFile(const AFileName: string): TArray<TAtlasProblem>;
var
  Entry: TEntry;
  Problem, Other: TAtlasProblem;
  Duplicate: Boolean;
  Visible: TArray<TAtlasProblem>;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  if Entry.VisibleValid then
    Exit(Entry.Visible);
  Visible := nil;
  for Problem in Entry.Compiler + Entry.Atlas do
  begin
    if Problem.Unnecessary then
      Continue;
    Duplicate := False;
    for Other in Visible do
      if (Other.StartLine = Problem.StartLine) and (Other.StartCharacter = Problem.StartCharacter) and
        SameText(Other.Message, Problem.Message) then
        Duplicate := True;
    if not Duplicate then
      Visible := Visible + [Problem];
  end;
  TArray.Sort<TAtlasProblem>(Visible, TComparer<TAtlasProblem>.Construct(
    function(const A, B: TAtlasProblem): Integer
    begin
      Result := A.StartLine - B.StartLine;
      if Result = 0 then
        Result := A.StartCharacter - B.StartCharacter;
      if Result = 0 then
        Result := Ord(A.Severity) - Ord(B.Severity);
    end));
  Entry.Visible := Visible;
  Entry.VisibleValid := True;
  Result := Visible;
end;

function TAtlasProblemStore.OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasProblem>;
var
  Problem: TAtlasProblem;
begin
  Result := nil;
  for Problem in ForFile(AFileName) do
    if (ALine >= Problem.StartLine) and (ALine <= Problem.EndLine) then
      Result := Result + [Problem];
end;

function TAtlasProblemStore.At(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
var
  Problem: TAtlasProblem;
begin
  Result := nil;
  for Problem in ForFile(AFileName) do
    if Problem.Contains(ALine, ACharacter) then
      Result := Result + [Problem];
end;

function TAtlasProblemStore.Files: TArray<string>;
var
  Entry: TEntry;
begin
  Result := nil;
  for Entry in FEntries.Values do
    if Length(ForFile(Entry.FileName)) > 0 then
      Result := Result + [Entry.FileName];
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
end;

end.
