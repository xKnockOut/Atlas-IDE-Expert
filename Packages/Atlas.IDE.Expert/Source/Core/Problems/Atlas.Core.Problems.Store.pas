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
// Hinweise zu uses-Einträgen (#621, data.uses) sind weder Probleme noch
// inaktive Zweige: UsesSpans liefert die ungenutzten zum Abblenden, UsesAt die
// an einer Stelle für den Tooltip.
// Fehlgeschlagene Tests (#69) stehen als dritte Art neben Atlas- und
// Compilermeldungen (Quelle "DUnitX"): SetTests ersetzt die eines Testlaufs,
// Update des Servers lässt sie stehen, Edit führt sie wie Atlas-Meldungen mit.
// Eine Datei nur mit Tests gilt nicht als vom Server geprüft (Contains,
// AllFiles).
// Befunde von Projektaufgaben (#900) stehen als vierte Art daneben (Quelle =
// Name der Aufgabe): SetTaskProblems ersetzt die einer Aufgabe in allen
// Dateien, Update des Servers lässt sie stehen; ändert sich die Zeile eines
// Befunds (Edit), fällt er weg, statt blass zu werden. Ausgeblendete Aufgaben
// (SetTaskHidden) fehlen in ForFile und allem, was darauf aufbaut.
// Gruppe „Compiler vorab“ (#1024): Meldet der letzte Build an der Zeile eines
// Atlas-Befunds einen der Codes aus data.compilerCodes, ist der Befund „vom
// Compiler bestätigt“ (Confirmed, ConfirmedCode). Mit CompilerMerge (Vorgabe,
// problems.compilerMerge = merge) entfällt die Compilermeldung dann in
// ForFile und allem, was darauf aufbaut (Wellenlinie, Hover, Fenster); mit
// both bleiben beide. Ist die Meldung nach dem nächsten Build weg, bleibt nur
// der Atlas-Befund.

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
  public const
    /// <summary>Quelle der Meldungen fehlgeschlagener Tests (#69).</summary>
    TestSource = 'DUnitX';
  private type
    TEntry = class
      FileName: string;
      Text: string;
      TextKnown: Boolean;
      ResultId: string;
      Atlas: TArray<TAtlasProblem>;
      Compiler: TArray<TAtlasProblem>;
      /// <summary>Fehlgeschlagene Tests des letzten Laufs (#69).</summary>
      Tests: TArray<TAtlasProblem>;
      /// <summary>Befunde von Projektaufgaben (#900), Source = Name der Aufgabe.</summary>
      Tasks: TArray<TAtlasProblem>;
      /// <summary>Diagnosen des Servers kamen schon (Update); False bei einer Datei nur mit Tests.</summary>
      FromServer: Boolean;
      // ForFile bzw. Inactive, bis sich etwas ändert.
      Visible: TArray<TAtlasProblem>;
      VisibleValid: Boolean;
      InactiveList: TArray<TAtlasProblem>;
      InactiveValid: Boolean;
      UsesList: TArray<TAtlasProblem>;
      UsesValid: Boolean;
      // Zeilen von Text, bei Bedarf.
      Lines: TArray<string>;
      LinesValid: Boolean;
    end;
  private
    FEntries: TObjectDictionary<string, TEntry>;
    FVersion: Integer;
    FCompilerMerge: Boolean;
    FHiddenTasks: TArray<string>;
    procedure SetCompilerMerge(AValue: Boolean);
    /// <summary>Einträge ohne Server, Tests und Aufgaben entfernen.</summary>
    procedure DropEmpty;
    function Find(const AFileName: string): TEntry;
    function Ensure(const AFileName: string): TEntry;
    class procedure Shift(AEntry: TEntry; const ANewText: string); static;
    /// <summary>Spalten der Bereiche AProblems in der Zeile (wie InactiveSpans).</summary>
    function SpansOf(const AFileName: string; const AProblems: TArray<TAtlasProblem>;
      ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
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
    /// <summary>Fehlgeschlagene Tests eines Laufs (#69): ersetzt die Tests aller Dateien. AProblems je Datei;
    /// Positionen beziehen sich auf den Text der Platte bzw. den bekannten Text.</summary>
    procedure SetTests(const AProblems: TArray<TPair<string, TAtlasProblem>>);
    /// <summary>Tests aller Dateien entfernen.</summary>
    procedure ClearTests;
    /// <summary>Befunde der Projektaufgabe ATask (#900): ersetzt ihre Befunde in allen Dateien. AProblems je
    /// Datei; Source wird ATask.</summary>
    procedure SetTaskProblems(const ATask: string; const AProblems: TArray<TPair<string, TAtlasProblem>>);
    /// <summary>Befunde der Aufgabe ATask entfernen.</summary>
    procedure ClearTask(const ATask: string);
    /// <summary>Befunde aller Aufgaben entfernen.</summary>
    procedure ClearTasks;
    /// <summary>Befunde der Aufgabe ATask aus- bzw. wieder einblenden (Problemliste, Editor).</summary>
    procedure SetTaskHidden(const ATask: string; AHidden: Boolean);
    function TaskHidden(const ATask: string): Boolean;
    /// <summary>Aufgaben mit Befunden (auch ausgeblendete), nach Namen.</summary>
    function TaskNames: TArray<string>;
    /// <summary>Zahl der Befunde der Aufgabe ATask, auch ausgeblendet.</summary>
    function TaskCount(const ATask: string): Integer;
    /// <summary>Hat der Server die Datei schon geliefert? Dateien nur mit Tests zählen nicht.</summary>
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
    /// <summary>Ungenutzte uses-Einträge der Datei (#621).</summary>
    function UnusedUses(const AFileName: string): TArray<TAtlasProblem>;
    /// <summary>Spalten ungenutzter uses-Einträge in der Zeile (0-basiert), wie InactiveSpans.</summary>
    function UsesSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
    /// <summary>Hinweise zu uses-Einträgen an der Stelle (0-basiert), auch behaltene und verschiebbare.</summary>
    function UsesAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
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
    /// <summary>Alle Dateien mit Diagnosen des Servers, auch ohne Probleme, nach Namen sortiert (Projektzustand
    /// #592: Was hier fehlt, ist nicht geprüft).</summary>
    function AllFiles: TArray<string>;
    property Version: Integer read FVersion;
    /// <summary>Bestätigte Compilermeldungen mit dem Atlas-Befund zusammenführen (problems.compilerMerge, #1024).
    /// </summary>
    property CompilerMerge: Boolean read FCompilerMerge write SetCompilerMerge;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  Atlas.Core.Editor.Pairs,
  Atlas.Text.Diff;

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
  FCompilerMerge := True;
end;

procedure TAtlasProblemStore.SetCompilerMerge(AValue: Boolean);
var
  Entry: TEntry;
begin
  if FCompilerMerge = AValue then
    Exit;
  FCompilerMerge := AValue;
  for Entry in FEntries.Values do
    Entry.VisibleValid := False;
  Inc(FVersion);
end;

/// <summary>Index der Compilermeldung in AProblems, die AProblem bestätigt (gleiche Zeile, Code aus
/// CompilerCodes); -1 ohne.</summary>
function ConfirmingIndex(const AProblems: TArray<TAtlasProblem>; const AProblem: TAtlasProblem): Integer;
var
  Index: Integer;
  Code: string;
begin
  for Index := 0 to High(AProblems) do
    if AProblems[Index].IsCompiler and (AProblems[Index].StartLine = AProblem.StartLine) then
      for Code in AProblem.CompilerCodes do
        if SameText(Code, AProblems[Index].Code) then
          Exit(Index);
  Result := -1;
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
  // Eine Datei, die bisher nur Tests hatte, ist für den Server neu.
  Entry := Find(AFileName);
  IsNew := (Entry = nil) or not Entry.FromServer;
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
  Entry.FromServer := True;
  Entry.VisibleValid := False;
  Entry.InactiveValid := False;
  Entry.UsesValid := False;
  Inc(FVersion);
end;

class procedure TAtlasProblemStore.Shift(AEntry: TEntry; const ANewText: string);
var
  OldLines, NewLines: TArray<string>;
  Prefix, Suffix, ChangedEnd, Delta, Index: Integer;
  Kept: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;

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
  TTextDiff.CommonPrefixSuffix(OldLines, NewLines, Prefix, Suffix);
  ChangedEnd := Length(OldLines) - Suffix;
  Delta := Length(NewLines) - Length(OldLines);
  for Index := 0 to High(AEntry.Atlas) do
    Map(AEntry.Atlas[Index], False);
  for Index := 0 to High(AEntry.Compiler) do
    Map(AEntry.Compiler[Index], True);
  for Index := 0 to High(AEntry.Tests) do
    Map(AEntry.Tests[Index], False);
  // Befunde von Aufgaben gelten für den Stand, den das Werkzeug sah: in der geänderten Stelle fallen sie weg.
  Kept := nil;
  for Index := 0 to High(AEntry.Tasks) do
  begin
    Problem := AEntry.Tasks[Index];
    if (Problem.EndLine >= Prefix) and (Problem.StartLine < ChangedEnd) then
      Continue;
    if Problem.StartLine >= ChangedEnd then
    begin
      Inc(Problem.StartLine, Delta);
      Inc(Problem.EndLine, Delta);
    end;
    Kept := Kept + [Problem];
  end;
  AEntry.Tasks := Kept;
  AEntry.Text := ANewText;
  AEntry.LinesValid := False;
  AEntry.VisibleValid := False;
  AEntry.InactiveValid := False;
  AEntry.UsesValid := False;
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
    if Problem.Unnecessary and not Problem.IsUses then
      Result := Result + [Problem];
  Entry.InactiveList := Result;
  Entry.InactiveValid := True;
end;

function TAtlasProblemStore.UnusedUses(const AFileName: string): TArray<TAtlasProblem>;
var
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  if Entry.UsesValid then
    Exit(Entry.UsesList);
  for Problem in Entry.Atlas do
    if Problem.UsesState = TAtlasProblem.UsesUnused then
      Result := Result + [Problem];
  Entry.UsesList := Result;
  Entry.UsesValid := True;
end;

function TAtlasProblemStore.UsesSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
begin
  Result := SpansOf(AFileName, UnusedUses(AFileName), ALine, ATabWidth);
end;

function TAtlasProblemStore.UsesAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>;
var
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  for Problem in Entry.Atlas do
    if Problem.IsUses and Problem.Contains(ALine, ACharacter) then
      Result := Result + [Problem];
end;

function TAtlasProblemStore.InactiveSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
begin
  Result := SpansOf(AFileName, Inactive(AFileName), ALine, ATabWidth);
end;

function TAtlasProblemStore.SpansOf(const AFileName: string; const AProblems: TArray<TAtlasProblem>;
  ALine, ATabWidth: Integer): TArray<TAtlasColumnSpan>;
var
  Problem: TAtlasProblem;
  Text: string;
  HasText: Boolean;
  First, Last: Integer;
begin
  Result := nil;
  HasText := False;
  Text := '';
  for Problem in AProblems do
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
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  Result := (Entry <> nil) and Entry.FromServer;
end;

procedure TAtlasProblemStore.DropEmpty;
var
  Entry: TEntry;
  Emptied: TArray<string>;
  FileName: string;
begin
  Emptied := nil;
  for Entry in FEntries.Values do
    if not Entry.FromServer and (Length(Entry.Tests) = 0) and (Length(Entry.Tasks) = 0) then
      Emptied := Emptied + [Entry.FileName];
  for FileName in Emptied do
    FEntries.Remove(Key(FileName));
end;

procedure TAtlasProblemStore.ClearTests;
var
  Entry: TEntry;
  Changed: Boolean;
begin
  Changed := False;
  for Entry in FEntries.Values do
    if Length(Entry.Tests) > 0 then
    begin
      Entry.Tests := nil;
      Entry.VisibleValid := False;
      Changed := True;
    end;
  DropEmpty;
  if Changed then
    Inc(FVersion);
end;

procedure TAtlasProblemStore.ClearTask(const ATask: string);
var
  Entry: TEntry;
  Kept: TArray<TAtlasProblem>;
  Problem: TAtlasProblem;
  Changed: Boolean;
begin
  Changed := False;
  for Entry in FEntries.Values do
  begin
    Kept := nil;
    for Problem in Entry.Tasks do
      if not SameText(Problem.Source, ATask) then
        Kept := Kept + [Problem];
    if Length(Kept) <> Length(Entry.Tasks) then
    begin
      Entry.Tasks := Kept;
      Entry.VisibleValid := False;
      Changed := True;
    end;
  end;
  DropEmpty;
  if Changed then
    Inc(FVersion);
end;

procedure TAtlasProblemStore.ClearTasks;
var
  Entry: TEntry;
  Changed: Boolean;
begin
  Changed := False;
  for Entry in FEntries.Values do
    if Length(Entry.Tasks) > 0 then
    begin
      Entry.Tasks := nil;
      Entry.VisibleValid := False;
      Changed := True;
    end;
  DropEmpty;
  if Changed then
    Inc(FVersion);
end;

procedure TAtlasProblemStore.SetTaskProblems(const ATask: string;
  const AProblems: TArray<TPair<string, TAtlasProblem>>);
var
  Item: TPair<string, TAtlasProblem>;
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  ClearTask(ATask);
  for Item in AProblems do
  begin
    Entry := Ensure(Item.Key);
    Problem := Item.Value;
    Problem.Source := ATask;
    Entry.Tasks := Entry.Tasks + [Problem];
    Entry.VisibleValid := False;
  end;
  if Length(AProblems) > 0 then
    Inc(FVersion);
end;

function TAtlasProblemStore.TaskHidden(const ATask: string): Boolean;
var
  Name: string;
begin
  for Name in FHiddenTasks do
    if SameText(Name, ATask) then
      Exit(True);
  Result := False;
end;

procedure TAtlasProblemStore.SetTaskHidden(const ATask: string; AHidden: Boolean);
var
  Kept: TArray<string>;
  Name: string;
  Entry: TEntry;
begin
  if TaskHidden(ATask) = AHidden then
    Exit;
  if AHidden then
    FHiddenTasks := FHiddenTasks + [ATask]
  else
  begin
    Kept := nil;
    for Name in FHiddenTasks do
      if not SameText(Name, ATask) then
        Kept := Kept + [Name];
    FHiddenTasks := Kept;
  end;
  for Entry in FEntries.Values do
    Entry.VisibleValid := False;
  Inc(FVersion);
end;

function TAtlasProblemStore.TaskNames: TArray<string>;
var
  Entry: TEntry;
  Problem: TAtlasProblem;
  Name: string;
  Known: Boolean;
begin
  Result := nil;
  for Entry in FEntries.Values do
    for Problem in Entry.Tasks do
    begin
      Known := False;
      for Name in Result do
        if SameText(Name, Problem.Source) then
          Known := True;
      if not Known then
        Result := Result + [Problem.Source];
    end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
end;

function TAtlasProblemStore.TaskCount(const ATask: string): Integer;
var
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  Result := 0;
  for Entry in FEntries.Values do
    for Problem in Entry.Tasks do
      if SameText(Problem.Source, ATask) then
        Inc(Result);
end;

procedure TAtlasProblemStore.SetTests(const AProblems: TArray<TPair<string, TAtlasProblem>>);
var
  Item: TPair<string, TAtlasProblem>;
  Entry: TEntry;
  Problem: TAtlasProblem;
begin
  ClearTests;
  for Item in AProblems do
  begin
    Entry := Ensure(Item.Key);
    Problem := Item.Value;
    Problem.Source := TestSource;
    Entry.Tests := Entry.Tests + [Problem];
    Entry.VisibleValid := False;
  end;
  if Length(AProblems) > 0 then
    Inc(FVersion);
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
  Visible, Merged: TArray<TAtlasProblem>;
  Drop: TArray<Boolean>;
  Index, Found: Integer;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  if Entry.VisibleValid then
    Exit(Entry.Visible);
  Visible := nil;
  for Problem in Entry.Compiler + Entry.Atlas + Entry.Tests + Entry.Tasks do
  begin
    // Inaktive Zweige und uses-Hinweise (#621) sind keine Probleme.
    if Problem.Unnecessary or Problem.IsUses then
      Continue;
    // Ausgeblendete Projektaufgaben (#900).
    if (FHiddenTasks <> nil) and TaskHidden(Problem.Source) then
      Continue;
    Duplicate := False;
    for Other in Visible do
      if (Other.StartLine = Problem.StartLine) and (Other.StartCharacter = Problem.StartCharacter) and
        SameText(Other.Message, Problem.Message) then
        Duplicate := True;
    if not Duplicate then
      Visible := Visible + [Problem];
  end;
  // Vom Compiler bestätigte Befunde (#1024); beim Zusammenführen ohne die Compilermeldung.
  SetLength(Drop, Length(Visible));
  for Index := 0 to High(Visible) do
    if not Visible[Index].IsCompiler and (Visible[Index].CompilerCodes <> nil) then
    begin
      Found := ConfirmingIndex(Visible, Visible[Index]);
      if Found < 0 then
        Continue;
      Visible[Index].Confirmed := True;
      Visible[Index].ConfirmedCode := Visible[Found].Code;
      if FCompilerMerge then
        Drop[Found] := True;
    end;
  Merged := nil;
  for Index := 0 to High(Visible) do
    if not Drop[Index] then
      Merged := Merged + [Visible[Index]];
  Visible := Merged;
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

function TAtlasProblemStore.AllFiles: TArray<string>;
var
  Entry: TEntry;
begin
  Result := nil;
  for Entry in FEntries.Values do
    if Entry.FromServer then
      Result := Result + [Entry.FileName];
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
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
