unit Argus.Core.Problems.Store;

// Probleme je Datei (#398), nur im Hauptthread benutzt. Jede Datei merkt sich
// den Text, auf den sich die Positionen beziehen.
// - Update: neue Diagnosen des Servers für einen Text. Argus-Meldungen werden
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

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Core.Problems.Contract;

type
  TArgusProblemStore = class
  private type
    TEntry = class
      FileName: string;
      Text: string;
      TextKnown: Boolean;
      ResultId: string;
      Argus: TArray<TArgusProblem>;
      Compiler: TArray<TArgusProblem>;
      // ForFile, bis sich etwas ändert.
      Visible: TArray<TArgusProblem>;
      VisibleValid: Boolean;
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
    procedure Update(const AFileName, AText: string; ATextKnown: Boolean; const AProblems: TArray<TArgusProblem>;
      const AResultId: string; AReplaceCompiler: Boolean);
    /// <summary>Editortext geändert: Positionen mitführen.</summary>
    procedure Edit(const AFileName, ANewText: string);
    procedure Remove(const AFileName: string);
    procedure Clear;
    function Contains(const AFileName: string): Boolean;
    function ResultId(const AFileName: string): string;
    /// <summary>Probleme der Datei ohne inaktive Bereiche und ohne Doppelte, nach Position.</summary>
    function ForFile(const AFileName: string): TArray<TArgusProblem>;
    /// <summary>Probleme, die die Zeile (0-basiert) berühren.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<TArgusProblem>;
    /// <summary>Probleme an der Stelle (0-basiert).</summary>
    function At(const AFileName: string; ALine, ACharacter: Integer): TArray<TArgusProblem>;
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
  System.Generics.Defaults;

{ TArgusProblemStore }

constructor TArgusProblemStore.Create;
begin
  inherited Create;
  FEntries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
end;

destructor TArgusProblemStore.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

class function TArgusProblemStore.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TArgusProblemStore.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
    Result := nil;
end;

function TArgusProblemStore.Ensure(const AFileName: string): TEntry;
begin
  Result := Find(AFileName);
  if Result = nil then
  begin
    Result := TEntry.Create;
    Result.FileName := AFileName;
    FEntries.Add(Key(AFileName), Result);
  end;
end;

procedure TArgusProblemStore.Update(const AFileName, AText: string; ATextKnown: Boolean;
  const AProblems: TArray<TArgusProblem>; const AResultId: string; AReplaceCompiler: Boolean);
var
  Entry: TEntry;
  IsNew: Boolean;
  Problem: TArgusProblem;
  Compiler: TArray<TArgusProblem>;
begin
  IsNew := Find(AFileName) = nil;
  Entry := Ensure(AFileName);
  // Behaltene Compilermeldungen auf den neuen Text bringen.
  if not IsNew and Entry.TextKnown and ATextKnown and (Entry.Text <> AText) then
    Shift(Entry, AText);
  Entry.Argus := nil;
  Compiler := nil;
  for Problem in AProblems do
    if Problem.IsCompiler then
      Compiler := Compiler + [Problem]
    else
      Entry.Argus := Entry.Argus + [Problem];
  if IsNew or AReplaceCompiler then
    Entry.Compiler := Compiler;
  Entry.Text := AText;
  Entry.LinesValid := False;
  Entry.TextKnown := ATextKnown;
  Entry.ResultId := AResultId;
  Entry.VisibleValid := False;
  Inc(FVersion);
end;

class procedure TArgusProblemStore.Shift(AEntry: TEntry; const ANewText: string);
var
  OldLines, NewLines: TArray<string>;
  Prefix, Suffix, ChangedEnd, Delta, Index: Integer;

  procedure Map(var AProblem: TArgusProblem; ACompiler: Boolean);
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
  for Index := 0 to High(AEntry.Argus) do
    Map(AEntry.Argus[Index], False);
  for Index := 0 to High(AEntry.Compiler) do
    Map(AEntry.Compiler[Index], True);
  AEntry.Text := ANewText;
  AEntry.LinesValid := False;
  AEntry.VisibleValid := False;
end;

procedure TArgusProblemStore.Edit(const AFileName, ANewText: string);
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

procedure TArgusProblemStore.Remove(const AFileName: string);
begin
  if Find(AFileName) = nil then
    Exit;
  FEntries.Remove(Key(AFileName));
  Inc(FVersion);
end;

procedure TArgusProblemStore.Clear;
begin
  if FEntries.Count = 0 then
    Exit;
  FEntries.Clear;
  Inc(FVersion);
end;

function TArgusProblemStore.Contains(const AFileName: string): Boolean;
begin
  Result := Find(AFileName) <> nil;
end;

function TArgusProblemStore.ResultId(const AFileName: string): string;
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if Entry = nil then
    Result := ''
  else
    Result := Entry.ResultId;
end;

function TArgusProblemStore.TextOf(const AFileName: string): string;
var
  Entry: TEntry;
begin
  Entry := Find(AFileName);
  if (Entry = nil) or not Entry.TextKnown then
    Result := ''
  else
    Result := Entry.Text;
end;

function TArgusProblemStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
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

function TArgusProblemStore.ForFile(const AFileName: string): TArray<TArgusProblem>;
var
  Entry: TEntry;
  Problem, Other: TArgusProblem;
  Duplicate: Boolean;
  Visible: TArray<TArgusProblem>;
begin
  Result := nil;
  Entry := Find(AFileName);
  if Entry = nil then
    Exit;
  if Entry.VisibleValid then
    Exit(Entry.Visible);
  Visible := nil;
  for Problem in Entry.Compiler + Entry.Argus do
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
  TArray.Sort<TArgusProblem>(Visible, TComparer<TArgusProblem>.Construct(
    function(const A, B: TArgusProblem): Integer
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

function TArgusProblemStore.OnLine(const AFileName: string; ALine: Integer): TArray<TArgusProblem>;
var
  Problem: TArgusProblem;
begin
  Result := nil;
  for Problem in ForFile(AFileName) do
    if (ALine >= Problem.StartLine) and (ALine <= Problem.EndLine) then
      Result := Result + [Problem];
end;

function TArgusProblemStore.At(const AFileName: string; ALine, ACharacter: Integer): TArray<TArgusProblem>;
var
  Problem: TArgusProblem;
begin
  Result := nil;
  for Problem in ForFile(AFileName) do
    if Problem.Contains(ALine, ACharacter) then
      Result := Result + [Problem];
end;

function TArgusProblemStore.Files: TArray<string>;
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
