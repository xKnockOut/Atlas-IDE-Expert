unit Atlas.Core.Debug.StepFilter;

// Schrittfilter beim Hineinspringen (#850), Kern ohne VCL und Open Tools API:
// - Antworten des Servers lesen: atlas.server.stepFilter (Routine an einer
//   Zeile mit Namen Unit.Klasse.Methode und Arten) und
//   atlas.server.stepFilterCounts (Treffer für das Fenster „Schrittfilter“).
// - Urteil: Gefiltert ist eine Routine, wenn debug.stepFilters an ist und eine
//   ihrer Arten in debug.stepFilters.kinds steht oder ein Muster aus
//   debug.stepFilters.patterns passt (Atlas.Text.StepFilter). Arten gehen vor,
//   in fester Reihenfolge; dann das erste passende Muster.
// - Ablauf eines Schritts (TAtlasStepFilterRun): F7 merkt die Tiefe des
//   Aufrufstapels. Führt der Halt danach tiefer (neue Routine) und ist sie
//   gefiltert, läuft Atlas „Bis zur Rückkehr“; zurück in der Ausgangsroutine
//   (gleiche Tiefe) springt Atlas erneut hinein, als hätte man dort F7
//   gedrückt: in den nächsten Aufruf derselben Anweisung bzw. auf die nächste
//   Zeile. Hält das Programm beim Zurückkehren tiefer (Haltepunkt in der
//   gefilterten Routine) oder flacher, bleibt der Halt stehen. Höchstens
//   MaxSkips Routinen je F7.
// - Zwischenspeicher je Debug-Sitzung: Antwort je Datei und Zeile (nach F7
//   steht die IDE am begin der Routine; der Code ändert sich während der
//   Sitzung nicht).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.StepFilter;

type
  {$SCOPEDENUMS ON}
  TAtlasStepVerdictKind = (None, Kind, Pattern);
  TAtlasStepFilterPhase = (Idle, Stepping, Returning);
  /// <summary>Was die IDE-Schicht nach einem Halt tut: stehen lassen, „Bis zur Rückkehr“, erneut hineinspringen.
  /// </summary>
  TAtlasStepFilterAction = (Keep, Return, StepInto);
  {$SCOPEDENUMS OFF}

  TAtlasStepRoutine = record
    Found: Boolean;
    /// <summary>Unit.TKlasse.Methode.</summary>
    Name: string;
    Container: string;
    Routine: string;
    StartLine: Integer;
    EndLine: Integer;
    Kinds: TStepFilterKinds;
  end;

  TAtlasStepCounts = record
    Files: Integer;
    Routines: Integer;
    Kinds: array[TStepFilterKind] of Integer;
    /// <summary>Treffer je Muster in der Reihenfolge der Anfrage.</summary>
    Patterns: TArray<Integer>;
    Truncated: Boolean;
  end;

  TAtlasStepVerdict = record
    Kind: TAtlasStepVerdictKind;
    FilterKind: TStepFilterKind;
    Pattern: string;
    function Filtered: Boolean;
  end;

  TAtlasStepFilterOptions = record
    Enabled: Boolean;
    Kinds: TStepFilterKinds;
    Patterns: TArray<string>;
    /// <summary>Aus den Einstellungen debug.stepFilters, .kinds und .patterns.</summary>
    class function Create(AEnabled: Boolean; const AKinds, APatterns: string): TAtlasStepFilterOptions; static;
  end;

  TAtlasStepFilter = class
  public const
    Command = 'atlas.server.stepFilter';
    CountsCommand = 'atlas.server.stepFilterCounts';
    /// <summary>So viele gefilterte Routinen überspringt Atlas je F7 höchstens.</summary>
    MaxSkips = 16;
  public
    /// <summary>JSON-Argumente [uri, line] für Command.</summary>
    class function Arguments(const AUri: string; ALine: Integer): string; static;
    /// <summary>JSON-Argumente [[Muster …]] für CountsCommand.</summary>
    class function CountsArguments(const APatterns: TArray<string>): string; static;
    /// <summary>Antwort von Command; False bei fremdem Format. Found False = keine Routine an der Zeile.</summary>
    class function ReadRoutine(AJson: TJSONValue; out ARoutine: TAtlasStepRoutine): Boolean; static;
    /// <summary>Antwort von CountsCommand; False bei fremdem Format. Fehlende Muster zählen 0.</summary>
    class function ReadCounts(AJson: TJSONValue; APatternCount: Integer; out ACounts: TAtlasStepCounts): Boolean;
      static;
    /// <summary>Wird ARoutine beim Hineinspringen übersprungen, und warum?</summary>
    class function Verdict(const AOptions: TAtlasStepFilterOptions;
      const ARoutine: TAtlasStepRoutine): TAtlasStepVerdict; static;
  end;

  TAtlasStepFilterRun = record
  private
    FPhase: TAtlasStepFilterPhase;
    FStartDepth: Integer;
    FSkips: Integer;
  public
    /// <summary>F7 des Benutzers bei Stapeltiefe ADepth (Anzahl der Rahmen).</summary>
    procedure Start(ADepth: Integer);
    procedure Cancel;
    /// <summary>Halt nach einem Schritt in eine neue Routine (tiefer als beim Start)? Nur dann fragt die
    /// IDE-Schicht den Server.</summary>
    function Entered(ADepth: Integer): Boolean;
    /// <summary>Halt nach dem Schritt: AFiltered = Urteil für die neue Routine (nur nach Entered von Bedeutung).
    /// </summary>
    function AfterStep(ADepth: Integer; AFiltered: Boolean): TAtlasStepFilterAction;
    /// <summary>Halt nach „Bis zur Rückkehr“.</summary>
    function AfterReturn(ADepth: Integer): TAtlasStepFilterAction;
    property Phase: TAtlasStepFilterPhase read FPhase;
    property StartDepth: Integer read FStartDepth;
    property Skips: Integer read FSkips;
  end;

  /// <summary>Antworten des Servers je Datei und Zeile, für eine Debug-Sitzung.</summary>
  TAtlasStepRoutineCache = class
  private
    FItems: TDictionary<string, TAtlasStepRoutine>;
    class function Key(const AFileName: string; ALine: Integer): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    function TryGet(const AFileName: string; ALine: Integer; out ARoutine: TAtlasStepRoutine): Boolean;
    procedure Add(const AFileName: string; ALine: Integer; const ARoutine: TAtlasStepRoutine);
    procedure Clear;
    function Count: Integer;
  end;

implementation

{ TAtlasStepVerdict }

function TAtlasStepVerdict.Filtered: Boolean;
begin
  Result := Kind <> TAtlasStepVerdictKind.None;
end;

{ TAtlasStepFilterOptions }

class function TAtlasStepFilterOptions.Create(AEnabled: Boolean;
  const AKinds, APatterns: string): TAtlasStepFilterOptions;
begin
  Result.Enabled := AEnabled;
  Result.Kinds := TStepFilterNames.ParseKinds(AKinds);
  Result.Patterns := TStepFilterNames.ParsePatterns(APatterns);
end;

{ TAtlasStepFilter }

class function TAtlasStepFilter.Arguments(const AUri: string; ALine: Integer): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(ALine);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasStepFilter.CountsArguments(const APatterns: TArray<string>): string;
var
  mItems, mPatterns: TJSONArray;
  mPattern: string;
begin
  mItems := TJSONArray.Create;
  try
    mPatterns := TJSONArray.Create;
    mItems.AddElement(mPatterns);
    for mPattern in APatterns do
      mPatterns.Add(mPattern);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasStepFilter.ReadRoutine(AJson: TJSONValue; out ARoutine: TAtlasStepRoutine): Boolean;
var
  mRoot: TJSONObject;
  mKinds: TJSONArray;
  mIndex: Integer;
  mKind: TStepFilterKind;
begin
  ARoutine := Default(TAtlasStepRoutine);
  ARoutine.StartLine := -1;
  ARoutine.EndLine := -1;
  Result := False;
  if not (AJson is TJSONObject) then
    Exit;
  mRoot := TJSONObject(AJson);
  if mRoot.GetValue<Integer>('format', 0) <> 1 then
    Exit;
  Result := True;
  ARoutine.Found := mRoot.GetValue<Boolean>('found', False) and (mRoot.GetValue<string>('name', '') <> '');
  if not ARoutine.Found then
    Exit;
  ARoutine.Name := mRoot.GetValue<string>('name', '');
  ARoutine.Container := mRoot.GetValue<string>('container', '');
  ARoutine.Routine := mRoot.GetValue<string>('routine', '');
  ARoutine.StartLine := mRoot.GetValue<Integer>('startLine', -1);
  ARoutine.EndLine := mRoot.GetValue<Integer>('endLine', -1);
  if mRoot.TryGetValue<TJSONArray>('kinds', mKinds) then
    for mIndex := 0 to mKinds.Count - 1 do
      if TStepFilterNames.TryKind(mKinds.Items[mIndex].Value, mKind) then
        Include(ARoutine.Kinds, mKind);
end;

class function TAtlasStepFilter.ReadCounts(AJson: TJSONValue; APatternCount: Integer;
  out ACounts: TAtlasStepCounts): Boolean;
var
  mRoot, mKinds: TJSONObject;
  mPatterns: TJSONArray;
  mKind: TStepFilterKind;
  mIndex: Integer;
begin
  ACounts := Default(TAtlasStepCounts);
  SetLength(ACounts.Patterns, APatternCount);
  for mIndex := 0 to High(ACounts.Patterns) do
    ACounts.Patterns[mIndex] := 0;
  Result := False;
  if not (AJson is TJSONObject) then
    Exit;
  mRoot := TJSONObject(AJson);
  if mRoot.GetValue<Integer>('format', 0) <> 1 then
    Exit;
  ACounts.Files := mRoot.GetValue<Integer>('files', 0);
  ACounts.Routines := mRoot.GetValue<Integer>('routines', 0);
  ACounts.Truncated := mRoot.GetValue<Boolean>('truncated', False);
  if mRoot.TryGetValue<TJSONObject>('kinds', mKinds) then
    for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
      ACounts.Kinds[mKind] := mKinds.GetValue<Integer>(TStepFilterNames.KindNames[mKind], 0);
  if mRoot.TryGetValue<TJSONArray>('patterns', mPatterns) then
    for mIndex := 0 to High(ACounts.Patterns) do
      if (mIndex < mPatterns.Count) and (mPatterns.Items[mIndex] is TJSONNumber) then
        ACounts.Patterns[mIndex] := TJSONNumber(mPatterns.Items[mIndex]).AsInt;
  Result := True;
end;

class function TAtlasStepFilter.Verdict(const AOptions: TAtlasStepFilterOptions;
  const ARoutine: TAtlasStepRoutine): TAtlasStepVerdict;
var
  mKind: TStepFilterKind;
  mIndex: Integer;
begin
  Result := Default(TAtlasStepVerdict);
  if not AOptions.Enabled or not ARoutine.Found then
    Exit;
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    if (mKind in AOptions.Kinds) and (mKind in ARoutine.Kinds) then
    begin
      Result.Kind := TAtlasStepVerdictKind.Kind;
      Result.FilterKind := mKind;
      Exit;
    end;
  mIndex := TStepFilterNames.MatchingPattern(AOptions.Patterns, ARoutine.Name);
  if mIndex >= 0 then
  begin
    Result.Kind := TAtlasStepVerdictKind.Pattern;
    Result.Pattern := AOptions.Patterns[mIndex];
  end;
end;

{ TAtlasStepFilterRun }

procedure TAtlasStepFilterRun.Start(ADepth: Integer);
begin
  FPhase := TAtlasStepFilterPhase.Stepping;
  FStartDepth := ADepth;
  FSkips := 0;
end;

procedure TAtlasStepFilterRun.Cancel;
begin
  FPhase := TAtlasStepFilterPhase.Idle;
  FSkips := 0;
end;

function TAtlasStepFilterRun.Entered(ADepth: Integer): Boolean;
begin
  Result := (FPhase = TAtlasStepFilterPhase.Stepping) and (ADepth > FStartDepth);
end;

function TAtlasStepFilterRun.AfterStep(ADepth: Integer; AFiltered: Boolean): TAtlasStepFilterAction;
begin
  Result := TAtlasStepFilterAction.Keep;
  if not Entered(ADepth) or not AFiltered or (FSkips >= TAtlasStepFilter.MaxSkips) then
  begin
    Cancel;
    Exit;
  end;
  Inc(FSkips);
  FPhase := TAtlasStepFilterPhase.Returning;
  Result := TAtlasStepFilterAction.Return;
end;

function TAtlasStepFilterRun.AfterReturn(ADepth: Integer): TAtlasStepFilterAction;
begin
  Result := TAtlasStepFilterAction.Keep;
  // Tiefer: Haltepunkt in der übersprungenen Routine; flacher: die Ausgangsroutine ist zu Ende.
  if (FPhase <> TAtlasStepFilterPhase.Returning) or (ADepth <> FStartDepth) then
  begin
    Cancel;
    Exit;
  end;
  FPhase := TAtlasStepFilterPhase.Stepping;
  Result := TAtlasStepFilterAction.StepInto;
end;

{ TAtlasStepRoutineCache }

constructor TAtlasStepRoutineCache.Create;
begin
  inherited Create;
  FItems := TDictionary<string, TAtlasStepRoutine>.Create;
end;

destructor TAtlasStepRoutineCache.Destroy;
begin
  FItems.Free;
  inherited;
end;

class function TAtlasStepRoutineCache.Key(const AFileName: string; ALine: Integer): string;
begin
  Result := LowerCase(AFileName.Replace('/', '\')) + '|' + IntToStr(ALine);
end;

function TAtlasStepRoutineCache.TryGet(const AFileName: string; ALine: Integer;
  out ARoutine: TAtlasStepRoutine): Boolean;
begin
  Result := FItems.TryGetValue(Key(AFileName, ALine), ARoutine);
end;

procedure TAtlasStepRoutineCache.Add(const AFileName: string; ALine: Integer; const ARoutine: TAtlasStepRoutine);
begin
  FItems.AddOrSetValue(Key(AFileName, ALine), ARoutine);
end;

procedure TAtlasStepRoutineCache.Clear;
begin
  FItems.Clear;
end;

function TAtlasStepRoutineCache.Count: Integer;
begin
  Result := FItems.Count;
end;

end.
