unit Atlas.Common.Rules.Baseline;

// Baseline für Altprojekte (#97): bestehende Treffer werden einmalig in
// atlas-baseline.json festgehalten und danach ausgeblendet; gemeldet
// werden nur neue. Ein Treffer wird über Datei, Regel, umgebende Routine und
// einen Fingerabdruck der Quelltextzeile zugeordnet, nicht über die
// Zeilennummer. So bleibt die Zuordnung stabil, wenn sich Code oberhalb
// verschiebt. Gleiche Treffer in gleichen Zeilen werden gezählt: kommt einer
// hinzu, wird der neue gemeldet.
//
// Umgebende Routine (Atlas.Common.Rules.Scopes): voll qualifizierter Name wie
// "TFoo.Bar", außerhalb einer Routine der Unit-Abschnitt. Zwei gleiche Zeilen
// "X.Free;" in verschiedenen Routinen sind damit verschiedene Einträge;
// wandert ein Treffer in eine andere Routine, gilt er als neu.
// Zusätzlich hält jeder Eintrag einen Fingerabdruck des Codekontexts (die
// Zeile und je ContextLines Zeilen davor und danach, Leerraum normalisiert;
// der Kopf der eigenen Routine zählt als leere Zeile, damit ihr Name nicht
// eingeht).
// Wurde eine Routine umbenannt (ihr alter Name kommt in der Datei nicht mehr
// vor, ihr neuer steht in keinem Eintrag der Datei), findet der Kontext den
// Eintrag wieder. Einrücken und geänderte Meldungstexte ändern keinen der
// Fingerabdrücke.
//
// Ältere Dateien ohne "routine" bleiben lesbar: ihre Einträge gelten für jede
// Routine der Datei wie bisher und werden beim nächsten Aktualisieren um
// Routine und Kontext ergänzt. Das Format bleibt Version 1; ältere Fassungen
// von Atlas übergehen die neuen Felder.
//
// Beim Neuschreiben entstehen die Einträge allein aus den aktuellen Treffern,
// verschwundene fallen damit heraus. Update zählt dabei hinzugekommene,
// entfernte und unveränderte Einträge und nennt Einträge ohne Datei (Datei
// umbenannt, verschoben oder gelöscht), bevor sie herausfallen.
//
// Format:
//   {"version": 1, "findings": [
//     {"path": "Src/U.pas", "rule": "empty-except", "fingerprint": "1a2b3c4d",
//      "count": 1, "routine": "TFoo.Bar", "context": "5e6f7a8b"}]}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Scopes;

const
  BaselineFileName = 'atlas-baseline.json';
  /// <summary>Name vor der Umbenennung in Atlas (#403); gilt, solange atlas-baseline.json fehlt.</summary>
  LegacyBaselineFileName = 'delphi-lsp-baseline.json';

type
  ERuleBaseline = class(Exception);

  /// <summary>Zustand eines Treffers gegenüber der Baseline, wie SARIF baselineState; None ohne Baseline.</summary>
  TBaselineState = (None, New, Unchanged, Absent);

  /// <summary>Wodurch ein Treffer einem Eintrag zugeordnet wurde.</summary>
  TBaselineMatch = (Unmatched, Exact, Legacy, Renamed);

  /// <summary>Treffer mit Fingerabdrücken und Zustand. Bei Absent stammen Regel, Routine und Fingerabdrücke aus
  /// dem Eintrag; Range und Meldung sind leer.</summary>
  TBaselineMark = record
    Finding: TRuleFinding;
    Routine: string;
    /// <summary>Fingerabdruck der Zeile.</summary>
    Fingerprint: string;
    /// <summary>Fingerabdruck des Codekontexts.</summary>
    Context: string;
    State: TBaselineState;
    Match: TBaselineMatch;
  end;

  /// <summary>Unveränderlich nach dem Laden, daher aus mehreren Threads lesbar.</summary>
  IRuleBaseline = interface
    ['{6C1D8C3E-3A0B-4C59-9E0A-2F0F7B7D5A11}']
    /// <summary>Treffer aus AFindings, die nicht in der Baseline stehen. Parst AText, wenn Einträge eine Routine
    /// tragen.</summary>
    function Filter(const ARelativePath, AText: string; const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
      overload;
    /// <summary>Wie oben mit den schon bekannten Routinen der Datei.</summary>
    function Filter(const ARelativePath, AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>; overload;
    /// <summary>Jeder Treffer als New oder Unchanged in der Reihenfolge von AFindings, danach je nicht mehr
    /// gefundenem Eintrag der Datei ein Absent.</summary>
    function Classify(const ARelativePath, AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
    /// <summary>Alle Einträge einer Datei als Absent, z. B. für eine Datei, die es nicht mehr gibt.</summary>
    function AbsentOf(const ARelativePath: string): TArray<TBaselineMark>;
    /// <summary>Anzahl der festgehaltenen Treffer.</summary>
    function Count: Integer;
    /// <summary>Festgehaltene Treffer einer Datei.</summary>
    function CountOf(const ARelativePath: string): Integer;
    /// <summary>Treffer aus Einträgen ohne Routine (ältere Datei).</summary>
    function LegacyCount: Integer;
    /// <summary>Pfade mit Einträgen, wie in der Datei (mit "/"), sortiert.</summary>
    function Paths: TArray<string>;
  end;

  /// <summary>Eine geprüfte Datei als Grundlage einer neuen Baseline.</summary>
  TBaselineSource = record
    Path: string;
    Text: string;
    Findings: TArray<TRuleFinding>;
  end;

  /// <summary>Einträge einer Datei, die es nicht mehr gibt.</summary>
  TBaselineOrphan = record
    Path: string;
    Count: Integer;
  end;

  /// <summary>Gibt es die Datei (Pfad relativ wie in der Baseline)?</summary>
  TBaselineFileExists = reference to function(const ARelativePath: string): Boolean;

  /// <summary>Ergebnis von TRuleBaseline.Update.</summary>
  TBaselineUpdate = record
    /// <summary>Neuer Inhalt der Datei.</summary>
    Json: string;
    /// <summary>Treffer in der neuen Baseline.</summary>
    Total: Integer;
    /// <summary>Geprüfte Dateien.</summary>
    Files: Integer;
    /// <summary>Neu aufgenommene Treffer (vorher nicht in der Baseline).</summary>
    Added: Integer;
    /// <summary>Herausgefallene Treffer, samt der Einträge ohne Datei.</summary>
    Removed: Integer;
    /// <summary>Treffer, die schon in der Baseline standen.</summary>
    Unchanged: Integer;
    /// <summary>Davon aus Einträgen ohne Routine (ältere Datei), jetzt mit Routine und Kontext.</summary>
    Completed: Integer;
    /// <summary>Einträge ohne Datei, die herausfallen; nach Pfad sortiert.</summary>
    Orphans: TArray<TBaselineOrphan>;
    /// <summary>Summe der Treffer in Orphans.</summary>
    function OrphanCount: Integer;
    /// <summary>Zähler als JSON-Objekt (ohne Json), Antwort von atlas.updateBaseline.</summary>
    function CountersJson: string;
  end;

  TRuleBaseline = class(TInterfacedObject, IRuleBaseline)
  public const
    /// <summary>Zeilen vor und nach dem Treffer im Kontext-Fingerabdruck.</summary>
    ContextLines = 2;
  private type
    TEntry = record
      Path: string;
      RuleId: string;
      Routine: string;
      Fingerprint: string;
      Context: string;
      Count: Integer;
    end;
  private
    FEntries: TList<TEntry>;
    /// <summary>Pfad, Regel, Routine, Zeile → Einträge (mit Routine).</summary>
    FExact: TDictionary<string, TArray<Integer>>;
    /// <summary>Pfad, Regel, Zeile → Einträge ohne Routine.</summary>
    FLegacy: TDictionary<string, TArray<Integer>>;
    /// <summary>Pfad → Einträge.</summary>
    FByPath: TDictionary<string, TArray<Integer>>;
    FTotal: Integer;
    FLegacyTotal: Integer;
    FHasRoutines: Boolean;
    procedure AddEntry(const AEntry: TEntry);
    class function PathKey(const APath: string): string; static;
    class function ExactKey(const APath, ARuleId, ARoutine, AFingerprint: string): string; static;
    class function LegacyKey(const APath, ARuleId, AFingerprint: string): string; static;
    class function MarksOf(const ALines: TArray<string>; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>; static;
    class function BuildJson(const ASources: TArray<TBaselineSource>;
      const AScopes: TArray<TFindingScopes>): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    function Filter(const ARelativePath, AText: string; const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
      overload;
    function Filter(const ARelativePath, AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>; overload;
    function Classify(const ARelativePath, AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
    function AbsentOf(const ARelativePath: string): TArray<TBaselineMark>;
    function Count: Integer;
    function CountOf(const ARelativePath: string): Integer;
    function LegacyCount: Integer;
    function Paths: TArray<string>;
    /// <summary>Liest eine Baseline-Datei. Löst ERuleBaseline bei ungültigem Inhalt aus.</summary>
    class function FromJson(const AJson: string): IRuleBaseline; static;
    /// <summary>Neue Baseline aus den aktuellen Treffern, als JSON mit fester Reihenfolge.</summary>
    class function Build(const ASources: TArray<TBaselineSource>): string; static;
    /// <summary>Neue Baseline wie Build und Vergleich mit AOld (nil = es gab keine). Einträge von AOld, deren
    /// Datei nicht unter ASources ist und laut AExists nicht existiert (nil = keine existiert), sind Orphans.
    /// </summary>
    class function Update(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>;
      const AExists: TBaselineFileExists): TBaselineUpdate; static;
    /// <summary>Treffer mit Fingerabdrücken, ohne Baseline (State None).</summary>
    class function Mark(const AText: string; const AScopes: TFindingScopes;
      const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>; static;
    /// <summary>Fingerabdruck der Zeile des Treffers: Text ohne Einrückung und mehrfache Leerzeichen.</summary>
    class function Fingerprint(const AText: string; const AFinding: TRuleFinding): string; static;
    /// <summary>Fingerabdruck des Codekontexts um Zeile ALine (ab 0), Leerraum normalisiert, ohne den Kopf der
    /// Routine aus AScopes.</summary>
    class function ContextFingerprint(const AText: string; const AScopes: TFindingScopes; ALine: Integer): string;
      static;
    /// <summary>Wert für SARIF partialFingerprints (ohne Zähler): Regel, Routine und Zeile.</summary>
    class function SarifFingerprint(const AMark: TBaselineMark): string; static;
    /// <summary>Pfad mit "/" als Trenner.</summary>
    class function NormalizePath(const APath: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  Atlas.Common.Rules.Output;

const
  FormatVersion = 1;

function LineOf(const AText: string; ALine: Integer): string;
var
  I, Line, Start: Integer;
begin
  Line := 0;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = #10) then
    begin
      if Line = ALine then
      begin
        Result := Copy(AText, Start, I - Start);
        Exit;
      end;
      Inc(Line);
      Start := I + 1;
    end;
  Result := '';
end;

function SplitLines(const AText: string): TArray<string>;
var
  I, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = #10) then
    begin
      Result := Result + [Copy(AText, Start, I - Start)];
      Start := I + 1;
    end;
end;

function LineAt(const ALines: TArray<string>; ALine: Integer): string;
begin
  if (ALine >= 0) and (ALine <= High(ALines)) then
    Result := ALines[ALine]
  else
    Result := '';
end;

function CollapseWhitespace(const AText: string): string;
var
  Builder: TStringBuilder;
  C: Char;
  Pending: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Pending := False;
    for C in AText do
      if CharInSet(C, [' ', #9, #13, #10]) then
        Pending := Builder.Length > 0
      else
      begin
        if Pending then
          Builder.Append(' ');
        Pending := False;
        Builder.Append(C);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// FNV-1a über UTF-16-Zeichen, 32 Bit, als Hex.
function Fnv1a(const AText: string): string;
var
  Hash: Cardinal;
  C: Char;
begin
  Hash := 2166136261;
  for C in AText do
  begin
    Hash := Hash xor Ord(C);
    Hash := Cardinal(UInt64(Hash) * 16777619);
  end;
  Result := LowerCase(IntToHex(Hash, 8));
end;

function LineFingerprint(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := Fnv1a(CollapseWhitespace(LineAt(ALines, ALine)));
end;

function ContextOf(const ALines: TArray<string>; ALine, AHeaderLine: Integer): string;
var
  Builder: TStringBuilder;
  Line: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Line := ALine - TRuleBaseline.ContextLines to ALine + TRuleBaseline.ContextLines do
    begin
      if Line > ALine - TRuleBaseline.ContextLines then
        Builder.Append(#10);
      // Der Kopf trägt den Namen der Routine: Umbenennen soll den Kontext nicht ändern.
      if Line <> AHeaderLine then
        Builder.Append(CollapseWhitespace(LineAt(ALines, Line)));
    end;
    Result := Fnv1a(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

{ TBaselineUpdate }

function TBaselineUpdate.OrphanCount: Integer;
var
  Orphan: TBaselineOrphan;
begin
  Result := 0;
  for Orphan in Orphans do
    Inc(Result, Orphan.Count);
end;

function TBaselineUpdate.CountersJson: string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append(Format('{"total": %d, "files": %d, "added": %d, "removed": %d, "unchanged": %d, ' +
      '"completed": %d, "orphaned": {"count": %d, "entries": [', [Total, Files, Added, Removed, Unchanged, Completed,
      OrphanCount]));
    for Index := 0 to High(Orphans) do
    begin
      if Index > 0 then
        Builder.Append(', ');
      Builder.Append('{"path": ').Append(TFindingsOutput.JsonString(Orphans[Index].Path));
      Builder.Append(Format(', "count": %d}', [Orphans[Index].Count]));
    end;
    Builder.Append(']}}');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TRuleBaseline }

constructor TRuleBaseline.Create;
begin
  inherited Create;
  FEntries := TList<TEntry>.Create;
  FExact := TDictionary<string, TArray<Integer>>.Create;
  FLegacy := TDictionary<string, TArray<Integer>>.Create;
  FByPath := TDictionary<string, TArray<Integer>>.Create;
end;

destructor TRuleBaseline.Destroy;
begin
  FByPath.Free;
  FLegacy.Free;
  FExact.Free;
  FEntries.Free;
  inherited;
end;

class function TRuleBaseline.PathKey(const APath: string): string;
begin
  Result := LowerCase(NormalizePath(APath));
end;

class function TRuleBaseline.ExactKey(const APath, ARuleId, ARoutine, AFingerprint: string): string;
begin
  Result := PathKey(APath) + #0 + LowerCase(ARuleId) + #0 + LowerCase(ARoutine) + #0 + AFingerprint;
end;

class function TRuleBaseline.LegacyKey(const APath, ARuleId, AFingerprint: string): string;
begin
  Result := PathKey(APath) + #0 + LowerCase(ARuleId) + #0 + AFingerprint;
end;

class function TRuleBaseline.NormalizePath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

class function TRuleBaseline.Fingerprint(const AText: string; const AFinding: TRuleFinding): string;
begin
  Result := Fnv1a(CollapseWhitespace(LineOf(AText, AFinding.Range.StartPos.Line)));
end;

class function TRuleBaseline.ContextFingerprint(const AText: string; const AScopes: TFindingScopes;
  ALine: Integer): string;
begin
  Result := ContextOf(SplitLines(AText), ALine, AScopes.HeaderLine(ALine));
end;

class function TRuleBaseline.SarifFingerprint(const AMark: TBaselineMark): string;
begin
  Result := Fnv1a(LowerCase(AMark.Finding.RuleId) + #0 + LowerCase(AMark.Routine) + #0 + AMark.Fingerprint);
end;

procedure TRuleBaseline.AddEntry(const AEntry: TEntry);
var
  Index, Existing: Integer;
  Key: string;
  Indices: TArray<Integer>;
  Entry: TEntry;
begin
  // Gleiche Einträge (auch doppelt in der Datei) zusammenzählen.
  if AEntry.Routine <> '' then
    Key := ExactKey(AEntry.Path, AEntry.RuleId, AEntry.Routine, AEntry.Fingerprint)
  else
    Key := LegacyKey(AEntry.Path, AEntry.RuleId, AEntry.Fingerprint);
  Indices := nil;
  if AEntry.Routine <> '' then
    FExact.TryGetValue(Key, Indices)
  else
    FLegacy.TryGetValue(Key, Indices);
  for Existing in Indices do
    if FEntries[Existing].Context = AEntry.Context then
    begin
      Entry := FEntries[Existing];
      Inc(Entry.Count, AEntry.Count);
      FEntries[Existing] := Entry;
      Inc(FTotal, AEntry.Count);
      if AEntry.Routine = '' then
        Inc(FLegacyTotal, AEntry.Count);
      Exit;
    end;
  Index := FEntries.Add(AEntry);
  Indices := Indices + [Index];
  if AEntry.Routine <> '' then
  begin
    FExact.AddOrSetValue(Key, Indices);
    FHasRoutines := True;
  end
  else
  begin
    FLegacy.AddOrSetValue(Key, Indices);
    Inc(FLegacyTotal, AEntry.Count);
  end;
  Inc(FTotal, AEntry.Count);
  Key := PathKey(AEntry.Path);
  Indices := nil;
  FByPath.TryGetValue(Key, Indices);
  FByPath.AddOrSetValue(Key, Indices + [Index]);
end;

function TRuleBaseline.Count: Integer;
begin
  Result := FTotal;
end;

function TRuleBaseline.LegacyCount: Integer;
begin
  Result := FLegacyTotal;
end;

function TRuleBaseline.CountOf(const ARelativePath: string): Integer;
var
  Indices: TArray<Integer>;
  Index: Integer;
begin
  Result := 0;
  if FByPath.TryGetValue(PathKey(ARelativePath), Indices) then
    for Index in Indices do
      Inc(Result, FEntries[Index].Count);
end;

function TRuleBaseline.Paths: TArray<string>;
var
  Indices: TArray<Integer>;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    for Indices in FByPath.Values do
      List.Add(FEntries[Indices[0]].Path);
    List.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TRuleBaseline.MarksOf(const ALines: TArray<string>; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
var
  Index, Line: Integer;
begin
  SetLength(Result, Length(AFindings));
  for Index := 0 to High(AFindings) do
  begin
    Line := AFindings[Index].Range.StartPos.Line;
    Result[Index].Finding := AFindings[Index];
    Result[Index].Routine := AScopes.At(Line);
    Result[Index].Fingerprint := LineFingerprint(ALines, Line);
    Result[Index].Context := ContextOf(ALines, Line, AScopes.HeaderLine(Line));
    Result[Index].State := TBaselineState.None;
    Result[Index].Match := TBaselineMatch.Unmatched;
  end;
end;

class function TRuleBaseline.Mark(const AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
begin
  Result := MarksOf(SplitLines(AText), AScopes, AFindings);
end;

function AbsentMark(const AEntryRule, ARoutine, AFingerprint, AContext: string): TBaselineMark;
begin
  Result := Default(TBaselineMark);
  Result.Finding.RuleId := AEntryRule;
  Result.Routine := ARoutine;
  Result.Fingerprint := AFingerprint;
  Result.Context := AContext;
  Result.State := TBaselineState.Absent;
  Result.Match := TBaselineMatch.Unmatched;
end;

function TRuleBaseline.Classify(const ARelativePath, AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
var
  Marks: TArray<TBaselineMark>;
  PathEntries, Indices: TArray<Integer>;
  Left: TDictionary<Integer, Integer>;
  Known: TList<string>;
  Index, EntryIndex, Remaining, Copies: Integer;
  Entry: TEntry;

  function Take(const ACandidates: TArray<Integer>; const AContext: string): Boolean;
  var
    Candidate, Chosen, Value: Integer;
  begin
    // Bevorzugt den Eintrag mit gleichem Kontext; sonst irgendeinen mit Rest.
    Chosen := -1;
    for Candidate in ACandidates do
      if Left.TryGetValue(Candidate, Value) and (Value > 0) then
      begin
        if FEntries[Candidate].Context = AContext then
        begin
          Chosen := Candidate;
          Break;
        end;
        if Chosen < 0 then
          Chosen := Candidate;
      end;
    Result := Chosen >= 0;
    if Result then
      Left[Chosen] := Left[Chosen] - 1;
  end;

begin
  Marks := MarksOf(SplitLines(AText), AScopes, AFindings);
  for Index := 0 to High(Marks) do
    Marks[Index].State := TBaselineState.New;
  if not FByPath.TryGetValue(PathKey(ARelativePath), PathEntries) then
    Exit(Marks);
  // Eigene Zähler je Aufruf: die Baseline selbst bleibt unverändert.
  Left := TDictionary<Integer, Integer>.Create;
  Known := TList<string>.Create;
  try
    for EntryIndex in PathEntries do
    begin
      Left.Add(EntryIndex, FEntries[EntryIndex].Count);
      if (FEntries[EntryIndex].Routine <> '') and not Known.Contains(LowerCase(FEntries[EntryIndex].Routine)) then
        Known.Add(LowerCase(FEntries[EntryIndex].Routine));
    end;
    // 1. Gleiche Routine und Zeile, sonst Einträge ohne Routine (ältere Datei).
    for Index := 0 to High(Marks) do
    begin
      if FExact.TryGetValue(ExactKey(ARelativePath, Marks[Index].Finding.RuleId, Marks[Index].Routine,
        Marks[Index].Fingerprint), Indices) and Take(Indices, Marks[Index].Context) then
      begin
        Marks[Index].State := TBaselineState.Unchanged;
        Marks[Index].Match := TBaselineMatch.Exact;
      end
      else if FLegacy.TryGetValue(LegacyKey(ARelativePath, Marks[Index].Finding.RuleId,
        Marks[Index].Fingerprint), Indices) and Take(Indices, '') then
      begin
        Marks[Index].State := TBaselineState.Unchanged;
        Marks[Index].Match := TBaselineMatch.Legacy;
      end;
    end;
    // 2. Umbenannte Routine: alter Name fehlt in der Datei, neuer steht in keinem Eintrag; gleicher Kontext.
    for Index := 0 to High(Marks) do
    begin
      if (Marks[Index].State <> TBaselineState.New) or Known.Contains(LowerCase(Marks[Index].Routine)) then
        Continue;
      for EntryIndex in PathEntries do
      begin
        Entry := FEntries[EntryIndex];
        if (Entry.Routine = '') or (Entry.Context = '') or (Entry.Context <> Marks[Index].Context) or
          not SameText(Entry.RuleId, Marks[Index].Finding.RuleId) or AScopes.HasRoutine(Entry.Routine) or
          (Left[EntryIndex] <= 0) then
          Continue;
        Left[EntryIndex] := Left[EntryIndex] - 1;
        Marks[Index].State := TBaselineState.Unchanged;
        Marks[Index].Match := TBaselineMatch.Renamed;
        Break;
      end;
    end;
    // 3. Nicht mehr gefunden.
    Result := Marks;
    for EntryIndex in PathEntries do
    begin
      Remaining := Left[EntryIndex];
      Entry := FEntries[EntryIndex];
      for Copies := 1 to Remaining do
        Result := Result + [AbsentMark(Entry.RuleId, Entry.Routine, Entry.Fingerprint, Entry.Context)];
    end;
  finally
    Known.Free;
    Left.Free;
  end;
end;

function TRuleBaseline.AbsentOf(const ARelativePath: string): TArray<TBaselineMark>;
var
  Indices: TArray<Integer>;
  Index, Copies: Integer;
  Entry: TEntry;
begin
  Result := nil;
  if not FByPath.TryGetValue(PathKey(ARelativePath), Indices) then
    Exit;
  for Index in Indices do
  begin
    Entry := FEntries[Index];
    for Copies := 1 to Entry.Count do
      Result := Result + [AbsentMark(Entry.RuleId, Entry.Routine, Entry.Fingerprint, Entry.Context)];
  end;
end;

function TRuleBaseline.Filter(const ARelativePath, AText: string;
  const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  Scopes: TFindingScopes;
begin
  if (FTotal = 0) or (Length(AFindings) = 0) or not FByPath.ContainsKey(PathKey(ARelativePath)) then
    Exit(AFindings);
  // Routinen braucht nur eine Baseline mit Routinen; ältere Dateien kommen ohne Parsen aus.
  if FHasRoutines then
    Scopes := TFindingScopes.FromText(AText)
  else
    Scopes := TFindingScopes.FromTree(nil);
  Result := Filter(ARelativePath, AText, Scopes, AFindings);
end;

function TRuleBaseline.Filter(const ARelativePath, AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  Mark: TBaselineMark;
begin
  if (FTotal = 0) or (Length(AFindings) = 0) or not FByPath.ContainsKey(PathKey(ARelativePath)) then
    Exit(AFindings);
  Result := nil;
  for Mark in Classify(ARelativePath, AText, AScopes, AFindings) do
    if Mark.State = TBaselineState.New then
      Result := Result + [Mark.Finding];
end;

class function TRuleBaseline.FromJson(const AJson: string): IRuleBaseline;
var
  Baseline: TRuleBaseline;
  Root, Value: TJSONValue;
  Items: TJSONArray;
  Item: TJSONObject;
  I, Count: Integer;
  Entry: TEntry;

  function OptionalText(const AName: string): string;
  var
    Field: TJSONValue;
  begin
    Field := Item.GetValue(AName);
    if Field is TJSONString then
      Result := TJSONString(Field).Value
    else
      Result := '';
  end;

begin
  Baseline := TRuleBaseline.Create;
  Result := Baseline;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      raise ERuleBaseline.Create('Baseline: Objekt erwartet');
    Value := TJSONObject(Root).GetValue('version');
    if not ((Value is TJSONNumber) and (TJSONNumber(Value).AsInt = FormatVersion)) then
      raise ERuleBaseline.CreateFmt('Baseline: Formatversion %d erwartet', [FormatVersion]);
    Value := TJSONObject(Root).GetValue('findings');
    if not (Value is TJSONArray) then
      raise ERuleBaseline.Create('Baseline: "findings" fehlt');
    Items := TJSONArray(Value);
    for I := 0 to Items.Count - 1 do
    begin
      if not (Items.Items[I] is TJSONObject) then
        raise ERuleBaseline.Create('Baseline: Eintrag ist kein Objekt');
      Item := TJSONObject(Items.Items[I]);
      if not ((Item.GetValue('path') is TJSONString) and (Item.GetValue('rule') is TJSONString) and
        (Item.GetValue('fingerprint') is TJSONString)) then
        raise ERuleBaseline.Create('Baseline: Eintrag ohne path, rule oder fingerprint');
      Value := Item.GetValue('count');
      if Value is TJSONNumber then
        Count := TJSONNumber(Value).AsInt
      else
        Count := 1;
      if Count < 1 then
        Continue;
      Entry := Default(TEntry);
      Entry.Path := NormalizePath(TJSONString(Item.GetValue('path')).Value);
      Entry.RuleId := LowerCase(TJSONString(Item.GetValue('rule')).Value);
      Entry.Fingerprint := TJSONString(Item.GetValue('fingerprint')).Value;
      // Fehlen bei Dateien vor #97 (Routine im Schlüssel).
      Entry.Routine := OptionalText('routine');
      Entry.Context := OptionalText('context');
      Entry.Count := Count;
      Baseline.AddEntry(Entry);
    end;
  finally
    Root.Free;
  end;
end;

type
  TBuildEntry = record
    Path: string;
    RuleId: string;
    Routine: string;
    Fingerprint: string;
    Context: string;
    Count: Integer;
  end;

function CompareBuildEntries(const ALeft, ARight: TBuildEntry): Integer;
begin
  Result := CompareText(ALeft.Path, ARight.Path);
  if Result = 0 then
    Result := CompareText(ALeft.RuleId, ARight.RuleId);
  if Result = 0 then
    Result := CompareText(ALeft.Routine, ARight.Routine);
  if Result = 0 then
    Result := CompareStr(ALeft.Fingerprint, ARight.Fingerprint);
  if Result = 0 then
    Result := CompareStr(ALeft.Context, ARight.Context);
end;

class function TRuleBaseline.BuildJson(const ASources: TArray<TBaselineSource>;
  const AScopes: TArray<TFindingScopes>): string;
var
  Entries: TDictionary<string, TBuildEntry>;
  Sorted: TList<TBuildEntry>;
  Item: TBaselineMark;
  Entry, Existing: TBuildEntry;
  K: string;
  Builder: TStringBuilder;
  I, SourceIndex: Integer;
begin
  Entries := TDictionary<string, TBuildEntry>.Create;
  Sorted := TList<TBuildEntry>.Create(TComparer<TBuildEntry>.Construct(CompareBuildEntries));
  Builder := TStringBuilder.Create;
  try
    for SourceIndex := 0 to High(ASources) do
      for Item in Mark(ASources[SourceIndex].Text, AScopes[SourceIndex], ASources[SourceIndex].Findings) do
      begin
        Entry := Default(TBuildEntry);
        Entry.Path := NormalizePath(ASources[SourceIndex].Path);
        Entry.RuleId := LowerCase(Item.Finding.RuleId);
        Entry.Routine := Item.Routine;
        Entry.Fingerprint := Item.Fingerprint;
        Entry.Context := Item.Context;
        K := ExactKey(Entry.Path, Entry.RuleId, Entry.Routine, Entry.Fingerprint) + #0 + Entry.Context;
        // TryGetValue leert Existing bei Misserfolg, daher getrennt.
        if Entries.TryGetValue(K, Existing) then
          Entry.Count := Existing.Count + 1
        else
          Entry.Count := 1;
        Entries.AddOrSetValue(K, Entry);
      end;
    Sorted.AddRange(Entries.Values);
    Sorted.Sort;
    Builder.Append('{').Append(sLineBreak);
    Builder.Append(Format('  "version": %d,', [FormatVersion])).Append(sLineBreak);
    Builder.Append('  "findings": [');
    for I := 0 to Sorted.Count - 1 do
    begin
      if I > 0 then
        Builder.Append(',');
      Builder.Append(sLineBreak);
      Builder.Append('    {"path": ').Append(TFindingsOutput.JsonString(Sorted[I].Path));
      Builder.Append(', "rule": ').Append(TFindingsOutput.JsonString(Sorted[I].RuleId));
      Builder.Append(', "fingerprint": ').Append(TFindingsOutput.JsonString(Sorted[I].Fingerprint));
      Builder.Append(Format(', "count": %d', [Sorted[I].Count]));
      Builder.Append(', "routine": ').Append(TFindingsOutput.JsonString(Sorted[I].Routine));
      Builder.Append(', "context": ').Append(TFindingsOutput.JsonString(Sorted[I].Context)).Append('}');
    end;
    if Sorted.Count > 0 then
      Builder.Append(sLineBreak).Append('  ');
    Builder.Append(']').Append(sLineBreak).Append('}').Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
    Sorted.Free;
    Entries.Free;
  end;
end;

function ScopesOf(const ASources: TArray<TBaselineSource>): TArray<TFindingScopes>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ASources));
  for Index := 0 to High(ASources) do
    // Ohne Treffer braucht es keine Routinen: kein Parsen.
    if Length(ASources[Index].Findings) > 0 then
      Result[Index] := TFindingScopes.FromText(ASources[Index].Text)
    else
      Result[Index] := TFindingScopes.FromTree(nil);
end;

class function TRuleBaseline.Build(const ASources: TArray<TBaselineSource>): string;
begin
  Result := BuildJson(ASources, ScopesOf(ASources));
end;

class function TRuleBaseline.Update(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>;
  const AExists: TBaselineFileExists): TBaselineUpdate;
var
  Scopes: TArray<TFindingScopes>;
  Checked: TList<string>;
  Index, Matched: Integer;
  Mark: TBaselineMark;
  Path: string;
  Orphan: TBaselineOrphan;
begin
  Result := Default(TBaselineUpdate);
  Result.Orphans := nil;
  Scopes := ScopesOf(ASources);
  Result.Json := BuildJson(ASources, Scopes);
  Result.Files := Length(ASources);
  Checked := TList<string>.Create;
  try
    Matched := 0;
    for Index := 0 to High(ASources) do
    begin
      Inc(Result.Total, Length(ASources[Index].Findings));
      Checked.Add(PathKey(ASources[Index].Path));
      if AOld = nil then
        Continue;
      for Mark in AOld.Classify(ASources[Index].Path, ASources[Index].Text, Scopes[Index],
        ASources[Index].Findings) do
        case Mark.State of
          TBaselineState.New:
            Inc(Result.Added);
          TBaselineState.Unchanged:
            begin
              Inc(Matched);
              if Mark.Match = TBaselineMatch.Legacy then
                Inc(Result.Completed);
            end;
        end;
    end;
    if AOld = nil then
    begin
      Result.Added := Result.Total;
      Exit;
    end;
    Result.Unchanged := Matched;
    Result.Removed := AOld.Count - Matched;
    for Path in AOld.Paths do
      if not Checked.Contains(PathKey(Path)) and not (Assigned(AExists) and AExists(Path)) then
      begin
        Orphan.Path := Path;
        Orphan.Count := AOld.CountOf(Path);
        Result.Orphans := Result.Orphans + [Orphan];
      end;
  finally
    Checked.Free;
  end;
end;

end.
