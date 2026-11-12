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
// Compilermeldungen (#530) stehen in derselben Datei: "rule" ist dann der
// Code der Meldung ("w1035", "h2164"; IsCompilerCode). Sie entstehen nur über
// ReplaceCompiler (Befehl „Aktuelle Compilermeldungen in die Basislinie“).
// Update (Regeln neu schreiben) übernimmt sie unverändert, solange ihre Datei
// existiert, und Classify/AbsentOf melden sie nie als Absent: Die Regelprüfung
// sieht keine Compilermeldungen und darf sie nicht als verschwunden werten.
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
  cBaselineFileName = 'atlas-baseline.json';
  /// <summary>Name vor der Umbenennung in Atlas (#403); gilt, solange atlas-baseline.json fehlt.</summary>
  cLegacyBaselineFileName = 'delphi-lsp-baseline.json';

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

  /// <summary>Ein Eintrag der Datei: Treffer gleicher Datei, Regel, Routine und Fingerabdrücke mit Anzahl.
  /// </summary>
  TBaselineEntry = record
    Path: string;
    RuleId: string;
    Routine: string;
    Fingerprint: string;
    Context: string;
    Count: Integer;
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
    /// <summary>Alle Einträge in der Reihenfolge der Datei.</summary>
    function Entries: TArray<TBaselineEntry>;
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
    /// <summary>Übernommene Compilermeldungen (#530); zählen nicht zu Total, Added, Removed und Unchanged.
    /// </summary>
    Compiler: Integer;
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
    cContextLines = 2;
  private type
    TEntry = TBaselineEntry;
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
    class function BuildJson(const ASources: TArray<TBaselineSource>; const AScopes: TArray<TFindingScopes>;
      const AKept: TArray<TBaselineEntry>): string; static;
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
    function Entries: TArray<TBaselineEntry>;
    /// <summary>Liest eine Baseline-Datei. Löst ERuleBaseline bei ungültigem Inhalt aus.</summary>
    class function FromJson(const AJson: string): IRuleBaseline; static;
    /// <summary>Neue Baseline aus den aktuellen Treffern, als JSON mit fester Reihenfolge.</summary>
    class function Build(const ASources: TArray<TBaselineSource>): string; static;
    /// <summary>Neue Baseline wie Build und Vergleich mit AOld (nil = es gab keine). Einträge von AOld, deren
    /// Datei nicht unter ASources ist und laut AExists nicht existiert (nil = keine existiert), sind Orphans.
    /// </summary>
    class function Update(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>;
      const AExists: TBaselineFileExists): TBaselineUpdate; static;
    /// <summary>Neue Baseline für Compilermeldungen (#530): ASources tragen je Datei die aktuellen Meldungen
    /// (RuleId = Code). Deren bisherige Compiler-Einträge werden ersetzt, alle übrigen Einträge von AOld
    /// (Regeln, Compilermeldungen anderer Dateien) bleiben. Ein Make meldet nur neu übersetzte Units; deren
    /// Einträge bleiben so erhalten. Zähler: Total = Compilermeldungen in der neuen Datei, Added, Unchanged und
    /// Removed für die Dateien aus ASources.</summary>
    class function ReplaceCompiler(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>):
      TBaselineUpdate; static;
    /// <summary>Ist ARuleId der Code einer Compilermeldung (Buchstabe E, W, H oder F und vier Ziffern)?</summary>
    class function IsCompilerCode(const ARuleId: string): Boolean; static;
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
  Atlas.Text.Json,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TBaselineText = (ObjectExpected, VersionExpected, FindingsMissing, EntryNoObject, EntryIncomplete);

const
  cTexts: array[TBaselineText] of TAtlasText = (
    (De: 'Baseline: Objekt erwartet'; En: 'Baseline: object expected'),
    (De: 'Baseline: Formatversion %d erwartet'; En: 'Baseline: format version %d expected'),
    (De: 'Baseline: "findings" fehlt'; En: 'Baseline: "findings" is missing'),
    (De: 'Baseline: Eintrag ist kein Objekt'; En: 'Baseline: entry is not an object'),
    (De: 'Baseline: Eintrag ohne path, rule oder fingerprint';
     En: 'Baseline: entry without path, rule or fingerprint'));

{$SCOPEDENUMS OFF}

const
  cFormatVersion = 1;

function LineAt(const ALines: TArray<string>; ALine: Integer): string;
begin
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    Result := ALines[ALine];
  end
  else
  begin
    Result := '';
  end;
end;

/// Zeile ALine (0-basiert) von AText; Zeilen wie TTextLines.SplitLines.
function LineOf(const AText: string; ALine: Integer): string;
begin
  Result := LineAt(TTextLines.SplitLines(AText), ALine);
end;

function CollapseWhitespace(const AText: string): string;
var
  mBuilder: TStringBuilder;
  C: Char;
  mPending: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    mPending := False;
    for C in AText do
    begin
      if CharInSet(C, [' ', #9, #13, #10]) then
      begin
        mPending := mBuilder.Length > 0;
      end
      else
      begin
        if mPending then
        begin
          mBuilder.Append(' ');
        end;
        mPending := False;
        mBuilder.Append(C);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// FNV-1a über UTF-16-Zeichen, 32 Bit, als Hex.
function Fnv1a(const AText: string): string;
var
  mHash: Cardinal;
  C: Char;
begin
  mHash := 2166136261;
  for C in AText do
  begin
    mHash := mHash xor Ord(C);
    mHash := Cardinal(UInt64(mHash) * 16777619);
  end;
  Result := LowerCase(IntToHex(mHash, 8));
end;

function LineFingerprint(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := Fnv1a(CollapseWhitespace(LineAt(ALines, ALine)));
end;

function ContextOf(const ALines: TArray<string>; ALine, AHeaderLine: Integer): string;
var
  mBuilder: TStringBuilder;
  mLine: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mLine := ALine - TRuleBaseline.cContextLines to ALine + TRuleBaseline.cContextLines do
    begin
      if mLine > ALine - TRuleBaseline.cContextLines then
      begin
        mBuilder.Append(#10);
      end;
      // Der Kopf trägt den Namen der Routine: Umbenennen soll den Kontext nicht ändern.
      if mLine <> AHeaderLine then
      begin
        mBuilder.Append(CollapseWhitespace(LineAt(ALines, mLine)));
      end;
    end;
    Result := Fnv1a(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

{ TBaselineUpdate }

function TBaselineUpdate.OrphanCount: Integer;
var
  mOrphan: TBaselineOrphan;
begin
  Result := 0;
  for mOrphan in Orphans do
  begin
    Inc(Result, mOrphan.Count);
  end;
end;

function TBaselineUpdate.CountersJson: string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(Format('{"total": %d, "files": %d, "added": %d, "removed": %d, "unchanged": %d, ' +
      '"completed": %d, "compiler": %d, "orphaned": {"count": %d, "entries": [', [Total, Files, Added, Removed,
      Unchanged, Completed, Compiler, OrphanCount]));
    for mIndex := 0 to High(Orphans) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append('{"path": ').Append(TJsonText.Quote(Orphans[mIndex].Path));
      mBuilder.Append(Format(', "count": %d}', [Orphans[mIndex].Count]));
    end;
    mBuilder.Append(']}}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
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
  Result := ContextOf(TTextLines.SplitLines(AText), ALine, AScopes.HeaderLine(ALine));
end;

class function TRuleBaseline.SarifFingerprint(const AMark: TBaselineMark): string;
begin
  Result := Fnv1a(LowerCase(AMark.Finding.RuleId) + #0 + LowerCase(AMark.Routine) + #0 + AMark.Fingerprint);
end;

procedure TRuleBaseline.AddEntry(const AEntry: TEntry);
var
  mIndex, mExisting: Integer;
  mKey: string;
  mIndices: TArray<Integer>;
  mEntry: TEntry;
begin
  // Gleiche Einträge (auch doppelt in der Datei) zusammenzählen.
  if AEntry.Routine <> '' then
  begin
    mKey := ExactKey(AEntry.Path, AEntry.RuleId, AEntry.Routine, AEntry.Fingerprint);
  end
  else
  begin
    mKey := LegacyKey(AEntry.Path, AEntry.RuleId, AEntry.Fingerprint);
  end;
  mIndices := nil;
  if AEntry.Routine <> '' then
  begin
    FExact.TryGetValue(mKey, mIndices);
  end
  else
  begin
    FLegacy.TryGetValue(mKey, mIndices);
  end;
  for mExisting in mIndices do
  begin
    if FEntries[mExisting].Context = AEntry.Context then
    begin
      mEntry := FEntries[mExisting];
      Inc(mEntry.Count, AEntry.Count);
      FEntries[mExisting] := mEntry;
      Inc(FTotal, AEntry.Count);
      if AEntry.Routine = '' then
      begin
        Inc(FLegacyTotal, AEntry.Count);
      end;
      Exit;
    end;
  end;
  mIndex := FEntries.Add(AEntry);
  mIndices := mIndices + [mIndex];
  if AEntry.Routine <> '' then
  begin
    FExact.AddOrSetValue(mKey, mIndices);
    FHasRoutines := True;
  end
  else
  begin
    FLegacy.AddOrSetValue(mKey, mIndices);
    Inc(FLegacyTotal, AEntry.Count);
  end;
  Inc(FTotal, AEntry.Count);
  mKey := PathKey(AEntry.Path);
  mIndices := nil;
  FByPath.TryGetValue(mKey, mIndices);
  FByPath.AddOrSetValue(mKey, mIndices + [mIndex]);
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
  mIndices: TArray<Integer>;
  mIndex: Integer;
begin
  Result := 0;
  if FByPath.TryGetValue(PathKey(ARelativePath), mIndices) then
  begin
    for mIndex in mIndices do
    begin
      Inc(Result, FEntries[mIndex].Count);
    end;
  end;
end;

function TRuleBaseline.Paths: TArray<string>;
var
  mIndices: TArray<Integer>;
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    for mIndices in FByPath.Values do
    begin
      mList.Add(FEntries[mIndices[0]].Path);
    end;
    mList.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TRuleBaseline.Entries: TArray<TBaselineEntry>;
begin
  Result := FEntries.ToArray;
end;

class function TRuleBaseline.IsCompilerCode(const ARuleId: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(ARuleId) = 5) and CharInSet(UpCase(ARuleId[1]), ['E', 'W', 'H', 'F']);
  if Result then
  begin
    for mIndex := 2 to 5 do
    begin
      if not CharInSet(ARuleId[mIndex], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TRuleBaseline.MarksOf(const ALines: TArray<string>; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
var
  mIndex, mLine: Integer;
begin
  SetLength(Result, Length(AFindings));
  for mIndex := 0 to High(AFindings) do
  begin
    mLine := AFindings[mIndex].Range.StartPos.Line;
    Result[mIndex].Finding := AFindings[mIndex];
    Result[mIndex].Routine := AScopes.At(mLine);
    Result[mIndex].Fingerprint := LineFingerprint(ALines, mLine);
    Result[mIndex].Context := ContextOf(ALines, mLine, AScopes.HeaderLine(mLine));
    Result[mIndex].State := TBaselineState.None;
    Result[mIndex].Match := TBaselineMatch.Unmatched;
  end;
end;

class function TRuleBaseline.Mark(const AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
begin
  Result := MarksOf(TTextLines.SplitLines(AText), AScopes, AFindings);
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

/// <summary>ACount Absent-Treffer zu AEntry; keine für Compilermeldungen (#530), die die Regelprüfung nicht sieht
/// und daher nie als verschwunden meldet.</summary>
function AbsentCopies(const AEntry: TBaselineEntry; ACount: Integer): TArray<TBaselineMark>;
var
  mCopy: Integer;
begin
  Result := nil;
  if TRuleBaseline.IsCompilerCode(AEntry.RuleId) then
  begin
    Exit;
  end;
  for mCopy := 1 to ACount do
  begin
    Result := Result + [AbsentMark(AEntry.RuleId, AEntry.Routine, AEntry.Fingerprint, AEntry.Context)];
  end;
end;

/// <summary>Gilt AEntry für AMark mit umbenannter Routine: gleiche Regel und gleicher Kontext, die alte Routine fehlt
/// in der Datei?</summary>
function Renames(const AEntry: TBaselineEntry; const AMark: TBaselineMark; const AScopes: TFindingScopes): Boolean;
begin
  Result := (AEntry.Routine <> '') and (AEntry.Context <> '') and (AEntry.Context = AMark.Context) and
    SameText(AEntry.RuleId, AMark.Finding.RuleId) and not AScopes.HasRoutine(AEntry.Routine);
end;

type
  /// <summary>Ein Aufruf von Classify für eine Datei: eigene Restzähler je Eintrag, damit die Baseline selbst
  /// unverändert bleibt.</summary>
  TBaselineClassifier = class
  private
    FEntries: TList<TBaselineEntry>;
    FPathEntries: TArray<Integer>;
    FLeft: TDictionary<Integer, Integer>;
    /// <summary>Routinen der Einträge, klein geschrieben.</summary>
    FKnown: TList<string>;
  public
    constructor Create(AEntries: TList<TBaselineEntry>; const APathEntries: TArray<Integer>);
    destructor Destroy; override;
    /// <summary>Zählt einen der Einträge ACandidates herunter, bevorzugt den mit Kontext AContext; False, wenn
    /// keiner mehr Rest hat.</summary>
    function Take(const ACandidates: TArray<Integer>; const AContext: string): Boolean;
    /// <summary>Zählt einen Eintrag einer umbenannten Routine zu AMark herunter: alter Name fehlt in der Datei,
    /// neuer steht in keinem Eintrag; gleicher Kontext.</summary>
    function TakeRenamed(const AMark: TBaselineMark; const AScopes: TFindingScopes): Boolean;
    /// <summary>Die nicht mehr gefundenen Treffer der Datei.</summary>
    function Absent: TArray<TBaselineMark>;
  end;

constructor TBaselineClassifier.Create(AEntries: TList<TBaselineEntry>; const APathEntries: TArray<Integer>);
var
  mIndex: Integer;
  mRoutine: string;
begin
  inherited Create;
  FEntries := AEntries;
  FPathEntries := APathEntries;
  FLeft := TDictionary<Integer, Integer>.Create;
  FKnown := TList<string>.Create;
  for mIndex in FPathEntries do
  begin
    FLeft.Add(mIndex, FEntries[mIndex].Count);
    mRoutine := LowerCase(FEntries[mIndex].Routine);
    if (mRoutine <> '') and not FKnown.Contains(mRoutine) then
    begin
      FKnown.Add(mRoutine);
    end;
  end;
end;

destructor TBaselineClassifier.Destroy;
begin
  FKnown.Free;
  FLeft.Free;
  inherited;
end;

function TBaselineClassifier.Take(const ACandidates: TArray<Integer>; const AContext: string): Boolean;
var
  mCandidate, mChosen, mValue: Integer;
begin
  // Bevorzugt den Eintrag mit gleichem Kontext; sonst irgendeinen mit Rest.
  mChosen := -1;
  for mCandidate in ACandidates do
  begin
    if not (FLeft.TryGetValue(mCandidate, mValue) and (mValue > 0)) then
    begin
      Continue;
    end;
    if FEntries[mCandidate].Context = AContext then
    begin
      mChosen := mCandidate;
      Break;
    end;
    if mChosen < 0 then
    begin
      mChosen := mCandidate;
    end;
  end;
  Result := mChosen >= 0;
  if Result then
  begin
    FLeft[mChosen] := FLeft[mChosen] - 1;
  end;
end;

function TBaselineClassifier.TakeRenamed(const AMark: TBaselineMark; const AScopes: TFindingScopes): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if FKnown.Contains(LowerCase(AMark.Routine)) then
  begin
    Exit;
  end;
  for mIndex in FPathEntries do
  begin
    if Renames(FEntries[mIndex], AMark, AScopes) and (FLeft[mIndex] > 0) then
    begin
      FLeft[mIndex] := FLeft[mIndex] - 1;
      Exit(True);
    end;
  end;
end;

function TBaselineClassifier.Absent: TArray<TBaselineMark>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex in FPathEntries do
  begin
    Result := Result + AbsentCopies(FEntries[mIndex], FLeft[mIndex]);
  end;
end;

/// <summary>Ordnet AMark über gleiche Routine und Zeile zu, sonst über Einträge ohne Routine (ältere Datei).
/// </summary>
procedure MatchKnown(AExact, ALegacy: TDictionary<string, TArray<Integer>>; ARun: TBaselineClassifier;
  const ARelativePath: string; var AMark: TBaselineMark);
var
  mIndices: TArray<Integer>;
begin
  if AExact.TryGetValue(TRuleBaseline.ExactKey(ARelativePath, AMark.Finding.RuleId, AMark.Routine,
    AMark.Fingerprint), mIndices) and ARun.Take(mIndices, AMark.Context) then
  begin
    AMark.State := TBaselineState.Unchanged;
    AMark.Match := TBaselineMatch.Exact;
  end
  else if ALegacy.TryGetValue(TRuleBaseline.LegacyKey(ARelativePath, AMark.Finding.RuleId, AMark.Fingerprint),
    mIndices) and ARun.Take(mIndices, '') then
  begin
    AMark.State := TBaselineState.Unchanged;
    AMark.Match := TBaselineMatch.Legacy;
  end;
end;

function TRuleBaseline.Classify(const ARelativePath, AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TBaselineMark>;
var
  mMarks: TArray<TBaselineMark>;
  mPathEntries: TArray<Integer>;
  mRun: TBaselineClassifier;
  mIndex: Integer;
begin
  mMarks := MarksOf(TTextLines.SplitLines(AText), AScopes, AFindings);
  for mIndex := 0 to High(mMarks) do
  begin
    mMarks[mIndex].State := TBaselineState.New;
  end;
  if not FByPath.TryGetValue(PathKey(ARelativePath), mPathEntries) then
  begin
    Exit(mMarks);
  end;
  mRun := TBaselineClassifier.Create(FEntries, mPathEntries);
  try
    // 1. Gleiche Routine und Zeile, sonst Einträge ohne Routine.
    for mIndex := 0 to High(mMarks) do
    begin
      MatchKnown(FExact, FLegacy, mRun, ARelativePath, mMarks[mIndex]);
    end;
    // 2. Umbenannte Routine.
    for mIndex := 0 to High(mMarks) do
    begin
      if (mMarks[mIndex].State = TBaselineState.New) and mRun.TakeRenamed(mMarks[mIndex], AScopes) then
      begin
        mMarks[mIndex].State := TBaselineState.Unchanged;
        mMarks[mIndex].Match := TBaselineMatch.Renamed;
      end;
    end;
    // 3. Nicht mehr gefunden.
    Result := mMarks + mRun.Absent;
  finally
    mRun.Free;
  end;
end;

function TRuleBaseline.AbsentOf(const ARelativePath: string): TArray<TBaselineMark>;
var
  mIndices: TArray<Integer>;
  mIndex: Integer;
begin
  Result := nil;
  if FByPath.TryGetValue(PathKey(ARelativePath), mIndices) then
  begin
    for mIndex in mIndices do
    begin
      Result := Result + AbsentCopies(FEntries[mIndex], FEntries[mIndex].Count);
    end;
  end;
end;

function TRuleBaseline.Filter(const ARelativePath, AText: string;
  const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  if (FTotal = 0) or (Length(AFindings) = 0) or not FByPath.ContainsKey(PathKey(ARelativePath)) then
  begin
    Exit(AFindings);
  end;
  // Routinen braucht nur eine Baseline mit Routinen; ältere Dateien kommen ohne Parsen aus.
  if FHasRoutines then
  begin
    mScopes := TFindingScopes.FromText(AText);
  end
  else
  begin
    mScopes := TFindingScopes.FromTree(nil);
  end;
  Result := Filter(ARelativePath, AText, mScopes, AFindings);
end;

function TRuleBaseline.Filter(const ARelativePath, AText: string; const AScopes: TFindingScopes;
  const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  mMark: TBaselineMark;
begin
  if (FTotal = 0) or (Length(AFindings) = 0) or not FByPath.ContainsKey(PathKey(ARelativePath)) then
  begin
    Exit(AFindings);
  end;
  Result := nil;
  for mMark in Classify(ARelativePath, AText, AScopes, AFindings) do
  begin
    if mMark.State = TBaselineState.New then
    begin
      Result := Result + [mMark.Finding];
    end;
  end;
end;

/// <summary>Liste "findings" der Datei; löst ERuleBaseline aus, wenn Form oder Formatversion nicht stimmen.
/// </summary>
function FindingsOf(ARoot: TJSONValue): TJSONArray;
var
  mValue: TJSONValue;
begin
  if not (ARoot is TJSONObject) then
  begin
    raise ERuleBaseline.Create(cTexts[TBaselineText.ObjectExpected].Text);
  end;
  mValue := TJSONObject(ARoot).GetValue('version');
  if not ((mValue is TJSONNumber) and (TJSONNumber(mValue).AsInt = cFormatVersion)) then
  begin
    raise ERuleBaseline.CreateFmt(cTexts[TBaselineText.VersionExpected].Text, [cFormatVersion]);
  end;
  mValue := TJSONObject(ARoot).GetValue('findings');
  if not (mValue is TJSONArray) then
  begin
    raise ERuleBaseline.Create(cTexts[TBaselineText.FindingsMissing].Text);
  end;
  Result := TJSONArray(mValue);
end;

/// <summary>Eintrag aus AValue; False bei count unter 1. Löst ERuleBaseline bei ungültigem Eintrag aus.</summary>
function EntryOf(AValue: TJSONValue; out AEntry: TBaselineEntry): Boolean;
var
  mItem: TJSONObject;
  mCount: TJSONValue;
begin
  if not (AValue is TJSONObject) then
  begin
    raise ERuleBaseline.Create(cTexts[TBaselineText.EntryNoObject].Text);
  end;
  mItem := TJSONObject(AValue);
  if not ((mItem.GetValue('path') is TJSONString) and (mItem.GetValue('rule') is TJSONString) and
    (mItem.GetValue('fingerprint') is TJSONString)) then
  begin
    raise ERuleBaseline.Create(cTexts[TBaselineText.EntryIncomplete].Text);
  end;
  AEntry := Default(TBaselineEntry);
  AEntry.Count := 1;
  mCount := mItem.GetValue('count');
  if mCount is TJSONNumber then
  begin
    AEntry.Count := TJSONNumber(mCount).AsInt;
  end;
  AEntry.Path := TRuleBaseline.NormalizePath(TJSONString(mItem.GetValue('path')).Value);
  AEntry.RuleId := LowerCase(TJSONString(mItem.GetValue('rule')).Value);
  AEntry.Fingerprint := TJSONString(mItem.GetValue('fingerprint')).Value;
  // Fehlen bei Dateien vor #97 (Routine im Schlüssel).
  AEntry.Routine := TJsonRead.Text(mItem, 'routine');
  AEntry.Context := TJsonRead.Text(mItem, 'context');
  Result := AEntry.Count >= 1;
end;

class function TRuleBaseline.FromJson(const AJson: string): IRuleBaseline;
var
  mBaseline: TRuleBaseline;
  mRoot: TJSONValue;
  mItems: TJSONArray;
  mIndex: Integer;
  mEntry: TEntry;
begin
  mBaseline := TRuleBaseline.Create;
  Result := mBaseline;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    mItems := FindingsOf(mRoot);
    for mIndex := 0 to mItems.Count - 1 do
    begin
      if EntryOf(mItems.Items[mIndex], mEntry) then
      begin
        mBaseline.AddEntry(mEntry);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

type
  TBuildEntry = TBaselineEntry;

function CompareBuildEntries(const ALeft, ARight: TBuildEntry): Integer;
begin
  Result := CompareText(ALeft.Path, ARight.Path);
  if Result = 0 then
  begin
    Result := CompareText(ALeft.RuleId, ARight.RuleId);
  end;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Routine, ARight.Routine);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Fingerprint, ARight.Fingerprint);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Context, ARight.Context);
  end;
end;

type
  TBuildEntries = TDictionary<string, TBuildEntry>;

/// <summary>Schlüssel eines Eintrags beim Aufbau: Pfad, Regel, Routine, Zeile und Kontext.</summary>
function BuildKey(const AEntry: TBuildEntry): string;
begin
  Result := TRuleBaseline.ExactKey(AEntry.Path, AEntry.RuleId, AEntry.Routine, AEntry.Fingerprint) + #0 +
    AEntry.Context;
end;

/// <summary>Die Treffer von ASource als Einträge in AEntries; gleiche werden gezählt.</summary>
procedure AddSourceEntries(AEntries: TBuildEntries; const ASource: TBaselineSource; const AScopes: TFindingScopes);
var
  mItem: TBaselineMark;
  mEntry, mExisting: TBuildEntry;
  mKey: string;
begin
  for mItem in TRuleBaseline.Mark(ASource.Text, AScopes, ASource.Findings) do
  begin
    mEntry := Default(TBuildEntry);
    mEntry.Path := TRuleBaseline.NormalizePath(ASource.Path);
    mEntry.RuleId := LowerCase(mItem.Finding.RuleId);
    mEntry.Routine := mItem.Routine;
    mEntry.Fingerprint := mItem.Fingerprint;
    mEntry.Context := mItem.Context;
    mKey := BuildKey(mEntry);
    // TryGetValue leert mExisting bei Misserfolg, daher getrennt.
    if AEntries.TryGetValue(mKey, mExisting) then
    begin
      mEntry.Count := mExisting.Count + 1;
    end
    else
    begin
      mEntry.Count := 1;
    end;
    AEntries.AddOrSetValue(mKey, mEntry);
  end;
end;

/// <summary>Übernommene Einträge (#530) unverändert; trifft einer einen neuen, zählen beide zusammen.</summary>
procedure AddKeptEntries(AEntries: TBuildEntries; const AKept: TArray<TBaselineEntry>);
var
  mEntry, mExisting: TBuildEntry;
  mKey: string;
begin
  for mEntry in AKept do
  begin
    mKey := BuildKey(mEntry);
    if AEntries.TryGetValue(mKey, mExisting) then
    begin
      mExisting.Count := mExisting.Count + mEntry.Count;
      AEntries[mKey] := mExisting;
    end
    else
    begin
      AEntries.Add(mKey, mEntry);
    end;
  end;
end;

/// <summary>Die Datei zu den sortierten Einträgen ASorted.</summary>
function EntriesJson(ASorted: TList<TBuildEntry>): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{').Append(sLineBreak);
    mBuilder.Append(Format('  "version": %d,', [cFormatVersion])).Append(sLineBreak);
    mBuilder.Append('  "findings": [');
    for mIndex := 0 to ASorted.Count - 1 do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(',');
      end;
      mBuilder.Append(sLineBreak);
      mBuilder.Append('    {"path": ').Append(TJsonText.Quote(ASorted[mIndex].Path));
      mBuilder.Append(', "rule": ').Append(TJsonText.Quote(ASorted[mIndex].RuleId));
      mBuilder.Append(', "fingerprint": ').Append(TJsonText.Quote(ASorted[mIndex].Fingerprint));
      mBuilder.Append(Format(', "count": %d', [ASorted[mIndex].Count]));
      mBuilder.Append(', "routine": ').Append(TJsonText.Quote(ASorted[mIndex].Routine));
      mBuilder.Append(', "context": ').Append(TJsonText.Quote(ASorted[mIndex].Context)).Append('}');
    end;
    if ASorted.Count > 0 then
    begin
      mBuilder.Append(sLineBreak).Append('  ');
    end;
    mBuilder.Append(']').Append(sLineBreak).Append('}').Append(sLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TRuleBaseline.BuildJson(const ASources: TArray<TBaselineSource>;
  const AScopes: TArray<TFindingScopes>; const AKept: TArray<TBaselineEntry>): string;
var
  mEntries: TBuildEntries;
  mSorted: TList<TBuildEntry>;
  mIndex: Integer;
begin
  mEntries := TBuildEntries.Create;
  mSorted := TList<TBuildEntry>.Create(TComparer<TBuildEntry>.Construct(CompareBuildEntries));
  try
    for mIndex := 0 to High(ASources) do
    begin
      AddSourceEntries(mEntries, ASources[mIndex], AScopes[mIndex]);
    end;
    AddKeptEntries(mEntries, AKept);
    mSorted.AddRange(mEntries.Values);
    mSorted.Sort;
    Result := EntriesJson(mSorted);
  finally
    mSorted.Free;
    mEntries.Free;
  end;
end;

function ScopesOf(const ASources: TArray<TBaselineSource>): TArray<TFindingScopes>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ASources));
  for mIndex := 0 to High(ASources) do
  begin
    // Ohne Treffer braucht es keine Routinen: kein Parsen.
    if Length(ASources[mIndex].Findings) > 0 then
    begin
      Result[mIndex] := TFindingScopes.FromText(ASources[mIndex].Text);
    end
    else
    begin
      Result[mIndex] := TFindingScopes.FromTree(nil);
    end;
  end;
end;

class function TRuleBaseline.Build(const ASources: TArray<TBaselineSource>): string;
begin
  Result := BuildJson(ASources, ScopesOf(ASources), nil);
end;

/// <summary>Pfadschlüssel der Dateien aus ASources; der Aufrufer gibt die Liste frei.</summary>
function PathKeysOf(const ASources: TArray<TBaselineSource>): TList<string>;
var
  mSource: TBaselineSource;
begin
  Result := TList<string>.Create;
  for mSource in ASources do
  begin
    Result.Add(TRuleBaseline.PathKey(mSource.Path));
  end;
end;

/// <summary>Anzahl der Treffer in ASources.</summary>
function FindingCount(const ASources: TArray<TBaselineSource>): Integer;
var
  mSource: TBaselineSource;
begin
  Result := 0;
  for mSource in ASources do
  begin
    Inc(Result, Length(mSource.Findings));
  end;
end;

/// <summary>Gibt es die Datei APath noch: geprüft (AChecked) oder laut AExists vorhanden?</summary>
function StillExists(AChecked: TList<string>; const AExists: TBaselineFileExists; const APath: string): Boolean;
begin
  Result := AChecked.Contains(TRuleBaseline.PathKey(APath)) or (Assigned(AExists) and AExists(APath));
end;

/// <summary>Compilermeldungen (#530) aus AOld, deren Datei noch existiert; sie entstehen nicht aus den Regeln und
/// bleiben daher. ACompiler zählt ihre Treffer.</summary>
function KeptCompiler(const AOld: IRuleBaseline; AChecked: TList<string>; const AExists: TBaselineFileExists;
  var ACompiler: Integer): TArray<TBaselineEntry>;
var
  mEntry: TBaselineEntry;
begin
  Result := nil;
  if AOld = nil then
  begin
    Exit;
  end;
  for mEntry in AOld.Entries do
  begin
    if TRuleBaseline.IsCompilerCode(mEntry.RuleId) and StillExists(AChecked, AExists, mEntry.Path) then
    begin
      Result := Result + [mEntry];
      Inc(ACompiler, mEntry.Count);
    end;
  end;
end;

/// <summary>Zählt AMarks in AUpdate (Added, Completed) und AMatched (Unchanged).</summary>
procedure CountMarks(const AMarks: TArray<TBaselineMark>; var AUpdate: TBaselineUpdate; var AMatched: Integer);
var
  mMark: TBaselineMark;
begin
  for mMark in AMarks do
  begin
    if mMark.State = TBaselineState.New then
    begin
      Inc(AUpdate.Added);
    end
    else if mMark.State = TBaselineState.Unchanged then
    begin
      Inc(AMatched);
      if mMark.Match = TBaselineMatch.Legacy then
      begin
        Inc(AUpdate.Completed);
      end;
    end;
  end;
end;

/// <summary>Dateien aus AOld, die es nicht mehr gibt, mit ihrer Trefferzahl.</summary>
function OrphansOf(const AOld: IRuleBaseline; AChecked: TList<string>;
  const AExists: TBaselineFileExists): TArray<TBaselineOrphan>;
var
  mPath: string;
  mOrphan: TBaselineOrphan;
begin
  Result := nil;
  for mPath in AOld.Paths do
  begin
    if not StillExists(AChecked, AExists, mPath) then
    begin
      mOrphan.Path := mPath;
      mOrphan.Count := AOld.CountOf(mPath);
      Result := Result + [mOrphan];
    end;
  end;
end;

class function TRuleBaseline.Update(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>;
  const AExists: TBaselineFileExists): TBaselineUpdate;
var
  mScopes: TArray<TFindingScopes>;
  mChecked: TList<string>;
  mIndex, mMatched: Integer;
begin
  Result := Default(TBaselineUpdate);
  Result.Orphans := nil;
  mScopes := ScopesOf(ASources);
  Result.Files := Length(ASources);
  Result.Total := FindingCount(ASources);
  mChecked := PathKeysOf(ASources);
  try
    Result.Json := BuildJson(ASources, mScopes, KeptCompiler(AOld, mChecked, AExists, Result.Compiler));
    if AOld = nil then
    begin
      Result.Added := Result.Total;
      Exit;
    end;
    mMatched := 0;
    for mIndex := 0 to High(ASources) do
    begin
      CountMarks(AOld.Classify(ASources[mIndex].Path, ASources[mIndex].Text, mScopes[mIndex],
        ASources[mIndex].Findings), Result, mMatched);
    end;
    Result.Unchanged := mMatched;
    // Herausgefallene Compilermeldungen (Datei weg) zählen mit, übernommene nicht.
    Result.Removed := AOld.Count - mMatched - Result.Compiler;
    Result.Orphans := OrphansOf(AOld, mChecked, AExists);
  finally
    mChecked.Free;
  end;
end;

/// <summary>Einträge von AOld ohne die Compilermeldungen der Dateien AReplaced; ABefore zählt deren Treffer,
/// ACompiler die der übrigen Compilermeldungen.</summary>
function KeptBesideCompiler(const AOld: IRuleBaseline; AReplaced: TList<string>;
  var ABefore, ACompiler: Integer): TArray<TBaselineEntry>;
var
  mEntry: TBaselineEntry;
  mCompiler: Boolean;
begin
  Result := nil;
  for mEntry in AOld.Entries do
  begin
    mCompiler := TRuleBaseline.IsCompilerCode(mEntry.RuleId);
    if mCompiler and AReplaced.Contains(TRuleBaseline.PathKey(mEntry.Path)) then
    begin
      Inc(ABefore, mEntry.Count);
      Continue;
    end;
    Result := Result + [mEntry];
    if mCompiler then
    begin
      Inc(ACompiler, mEntry.Count);
    end;
  end;
end;

/// <summary>Treffer aus ASources, die AOld schon kennt.</summary>
function MatchedCount(const AOld: IRuleBaseline; const ASources: TArray<TBaselineSource>;
  const AScopes: TArray<TFindingScopes>): Integer;
var
  mIndex: Integer;
  mMark: TBaselineMark;
begin
  Result := 0;
  for mIndex := 0 to High(ASources) do
  begin
    for mMark in AOld.Classify(ASources[mIndex].Path, ASources[mIndex].Text, AScopes[mIndex],
      ASources[mIndex].Findings) do
    begin
      if mMark.State = TBaselineState.Unchanged then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

class function TRuleBaseline.ReplaceCompiler(const AOld: IRuleBaseline;
  const ASources: TArray<TBaselineSource>): TBaselineUpdate;
var
  mScopes: TArray<TFindingScopes>;
  mReplaced: TList<string>;
  mKept: TArray<TBaselineEntry>;
  mFindings, mBefore, mOther, mMatched: Integer;
begin
  Result := Default(TBaselineUpdate);
  Result.Orphans := nil;
  Result.Files := Length(ASources);
  mScopes := ScopesOf(ASources);
  mFindings := FindingCount(ASources);
  mKept := nil;
  mBefore := 0;
  mOther := 0;
  mMatched := 0;
  mReplaced := PathKeysOf(ASources);
  try
    if AOld <> nil then
    begin
      mKept := KeptBesideCompiler(AOld, mReplaced, mBefore, mOther);
      mMatched := MatchedCount(AOld, ASources, mScopes);
    end;
    Result.Json := BuildJson(ASources, mScopes, mKept);
  finally
    mReplaced.Free;
  end;
  Result.Total := mFindings + mOther;
  Result.Compiler := Result.Total;
  Result.Unchanged := mMatched;
  Result.Added := mFindings - mMatched;
  Result.Removed := mBefore - mMatched;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Baseline', cTexts);

end.
