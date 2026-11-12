unit Atlas.Core.Tracker.FlowMap;

// Ablauf-Karte „Atlas-Ablauf“ (#2125), ohne VCL und Open Tools API: über
// welche Zustände die Issues eines Projekts wirklich laufen, wie lange sie wo
// bleiben und welche liegen geblieben sind.
// - Daten (TAtlasFlowData): die Zustandswechsel der letzten Tage
//   (issues.flowMap.days) und die nicht erledigten Issues mit ihrem
//   Zustand. Holen kann sie ein Anbieter mit der Fähigkeit IAtlasTrackerFlow
//   (nur YouTrack: Atlas.Core.Tracker.YouTrackFlow).
// - Zwischenspeicher: "<TrackerId>-flow.json" neben dem Board. Der nächste
//   Abruf holt nur die Wechsel ab dem letzten Stand (SinceOf) und führt sie
//   mit dem gespeicherten zusammen (Merge); was vor dem Zeitraum liegt,
//   fällt weg.
// - Auswertung (TAtlasFlowMap.Build): Übergänge von → nach mit Anzahl,
//   mittlere Verweildauer je Zustand aus abgeschlossenen Aufenthalten (vom
//   Eintritt bis zum nächsten Wechsel; der erste Aufenthalt zählt nur, wenn
//   das Issue im Zeitraum angelegt wurde), offene und eigene Issues je
//   Zustand und die Liste „Liegt lange“: nicht erledigte Issues, die seit
//   mindestens issues.flowMap.stuckDays Tagen im selben Zustand stehen.
//   Liegt der letzte Wechsel vor dem Zeitraum, zählt der Beginn des
//   Zeitraums (Before).
// - Anordnung: Der häufigste Weg läuft von links nach rechts (Zeile 0): Start
//   ist der Zustand mit dem größten Überschuss an ausgehenden Wechseln, dann
//   jeweils der häufigste Übergang in einen noch freien Zustand. Die übrigen
//   Zustände stehen darunter (Zeile 1), nach Verkehr geordnet. Ein Übergang
//   im Hauptweg nach links ist ein Rückweg (Back).
// Personen erscheinen nur in der Liste (Zuständig), nicht in den Zahlen.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Ein Zustandswechsel eines Issues.</summary>
  TAtlasFlowChange = record
    /// <summary>ID der Aktivität beim Tracker (doppelte beim Nachladen); '' = unbekannt.</summary>
    Id: string;
    Key: string;
    Title: string;
    /// <summary>Zeitpunkt (UTC).</summary>
    Time: TDateTime;
    /// <summary>Anlage des Issues (UTC); 0 = unbekannt.</summary>
    Created: TDateTime;
    /// <summary>Zustand vorher bzw. nachher; '' = leer.</summary>
    FromState: string;
    ToState: string;
    class function Create(const AId, AKey: string; ATime: TDateTime; const AFrom, ATo: string): TAtlasFlowChange;
      static;
  end;

  /// <summary>Ein nicht erledigtes Issue mit seinem Zustand.</summary>
  TAtlasFlowIssue = record
    Key: string;
    Title: string;
    State: string;
    /// <summary>Anzeigename bzw. Login; '' ohne.</summary>
    Assignee: string;
    /// <summary>Anlage (UTC); 0 = unbekannt.</summary>
    Created: TDateTime;
    /// <summary>Mir zugewiesen.</summary>
    Mine: Boolean;
    class function Create(const AKey, ATitle, AState: string): TAtlasFlowIssue; static;
  end;

  /// <summary>Rohdaten der Ablauf-Karte eines Projekts.</summary>
  TAtlasFlowData = record
  public const
    cVersion = 1;
  public
    /// <summary>Zeitpunkt des Abrufs (UTC).</summary>
    Fetched: TDateTime;
    /// <summary>Zeitraum in Tagen.</summary>
    Days: Integer;
    /// <summary>Zustandsfeld, nach dem gefragt wurde ('' = erkannt).</summary>
    StateField: string;
    Changes: TArray<TAtlasFlowChange>;
    Open: TArray<TAtlasFlowIssue>;
    /// <summary>Zustände, die der Tracker als erledigt kennzeichnet.</summary>
    Resolved: TArray<string>;
    /// <summary>Nicht alles geholt (Seiten- oder Zeitgrenze).</summary>
    Truncated: Boolean;
    class function Empty: TAtlasFlowData; static;
  end;

  /// <summary>Auftrag an IAtlasTrackerFlow.LoadFlow.</summary>
  TAtlasFlowRequest = record
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    /// <summary>Name des Zustandsfeldes; '' = am Typ erkennen.</summary>
    StateField: string;
    /// <summary>Wechsel ab diesem Zeitpunkt (UTC).</summary>
    Since: TDateTime;
    TimeoutMs: Integer;
    class function Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const AStateField: string; ASince: TDateTime; ATimeoutMs: Integer): TAtlasFlowRequest; static;
  end;

  /// <summary>Optionale Fähigkeit eines Anbieters: Zustandswechsel eines Projekts holen (#2125); im Hintergrund.
  /// </summary>
  IAtlasTrackerFlow = interface
    ['{4E8B2D61-7A3C-4F19-9C5E-2B6D8A1F3E47}']
    /// <summary>Wechsel ab ARequest.Since und die nicht erledigten Issues des Projekts; Fetched und Days setzt
    /// der Aufrufer.</summary>
    function LoadFlow(const ARequest: TAtlasFlowRequest; out AData: TAtlasFlowData;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Ein Zustand der Karte.</summary>
  TAtlasFlowState = record
    Name: string;
    /// <summary>0 = Hauptweg, 1 = darunter.</summary>
    Row: Integer;
    /// <summary>Platz in der Zeile, ab 0.</summary>
    Column: Integer;
    /// <summary>Der Tracker kennzeichnet den Zustand als erledigt.</summary>
    Resolved: Boolean;
    /// <summary>Abgeschlossene Aufenthalte und ihre Dauer in Tagen.</summary>
    Stays: Integer;
    StayDays: Double;
    /// <summary>Nicht erledigte Issues darin, davon mir zugewiesen bzw. liegen lange.</summary>
    OpenCount: Integer;
    MineCount: Integer;
    StuckCount: Integer;
    /// <summary>Mittlere Verweildauer in Tagen; -1 ohne abgeschlossenen Aufenthalt.</summary>
    function AverageDays: Double;
  end;

  /// <summary>Ein genutzter Übergang.</summary>
  TAtlasFlowTransition = record
    FromIndex: Integer;
    ToIndex: Integer;
    Count: Integer;
    /// <summary>Im Hauptweg nach links.</summary>
    Back: Boolean;
  end;

  /// <summary>Ein Eintrag der Liste „Liegt lange“.</summary>
  TAtlasFlowStuck = record
    Key: string;
    Title: string;
    State: string;
    Assignee: string;
    /// <summary>Im Zustand seit (UTC).</summary>
    Since: TDateTime;
    /// <summary>Der Eintritt liegt vor dem Zeitraum; Since ist dann dessen Beginn.</summary>
    Before: Boolean;
    /// <summary>Volle Tage seit Since.</summary>
    Days: Integer;
    Mine: Boolean;
  end;

  /// <summary>Ausgewertete Ablauf-Karte.</summary>
  TAtlasFlowMap = record
    States: TArray<TAtlasFlowState>;
    Transitions: TArray<TAtlasFlowTransition>;
    /// <summary>Liegt lange, längste zuerst.</summary>
    Stuck: TArray<TAtlasFlowStuck>;
    /// <summary>Issues mit Wechsel oder offen.</summary>
    IssueCount: Integer;
    ChangeCount: Integer;
    Days: Integer;
    Truncated: Boolean;
    /// <summary>Auswertung von AData zum Zeitpunkt ANow (UTC).</summary>
    class function Build(const AData: TAtlasFlowData; ANow: TDateTime; AStuckDays: Integer): TAtlasFlowMap; static;
    /// <summary>Index des Zustands AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Größte Anzahl eines Übergangs; 0 ohne.</summary>
    function MaxCount: Integer;
    /// <summary>Liste „Liegt lange“ nur im Zustand AState; '' = alle.</summary>
    function StuckIn(const AState: string): TArray<TAtlasFlowStuck>;
    /// <summary>Zustände der Zeile ARow in Anzeigereihenfolge (Indizes in States).</summary>
    function RowStates(ARow: Integer): TArray<Integer>;
  end;

  /// <summary>Zeitraum, Nachladen und Zwischenspeicher.</summary>
  TAtlasTrackerFlow = class
  public const
    /// <summary>Zeitgrenze des ganzen Abrufs.</summary>
    cTimeoutMs = 60000;
    /// <summary>Beim Nachladen so weit vor dem letzten Abruf beginnen (Uhren von Server und Rechner).</summary>
    cOverlapMinutes = 10;
    cCacheName = 'flow';
  public
    /// <summary>Beginn des Zeitraums: ANow minus ADays Tage.</summary>
    class function WindowStart(ANow: TDateTime; ADays: Integer): TDateTime; static;
    /// <summary>Ab wann Wechsel zu holen sind: Passt der gespeicherte Stand (gleicher Zeitraum und gleiches
    /// Zustandsfeld, vollständig, Abruf im Zeitraum), dessen Abruf minus cOverlapMinutes; sonst der Beginn des
    /// Zeitraums.</summary>
    class function SinceOf(const ACached: TAtlasFlowData; AHasCache: Boolean; ANow: TDateTime; ADays: Integer;
      const AStateField: string): TDateTime; static;
    /// <summary>Neu geholt ANew mit dem gespeicherten AOld (nur mit AUseOld): Wechsel ohne doppelte ID, ältere
    /// als der Zeitraum fallen weg; offene Issues und erledigte Zustände aus ANew.</summary>
    class function Merge(const AOld, ANew: TAtlasFlowData; AUseOld: Boolean; ANow: TDateTime): TAtlasFlowData;
      static;
    class function ToJson(const AData: TAtlasFlowData): string; static;
    /// <summary>False bei ungültigem JSON oder anderer Version.</summary>
    class function FromJson(const AJson: string; out AData: TAtlasFlowData): Boolean; static;
    /// <summary>Stand von ATarget in AFolder merken; Fehler beim Schreiben werden übergangen.</summary>
    class procedure Save(const AFolder: string; const ATarget: TAtlasTrackerTarget; const AData: TAtlasFlowData);
      static;
    /// <summary>Letzter Stand von ATarget; False ohne (lesbare) Datei.</summary>
    class function Load(const AFolder: string; const ATarget: TAtlasTrackerTarget; out AData: TAtlasFlowData): Boolean;
      static;
  end;

implementation

uses
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON,
  System.Math,
  Atlas.Core.Tracker.Board,
  Atlas.Text.Json;

{ TAtlasFlowChange }

class function TAtlasFlowChange.Create(const AId, AKey: string; ATime: TDateTime;
  const AFrom, ATo: string): TAtlasFlowChange;
begin
  Result := Default(TAtlasFlowChange);
  Result.Id := AId;
  Result.Key := AKey;
  Result.Time := ATime;
  Result.FromState := AFrom;
  Result.ToState := ATo;
end;

{ TAtlasFlowIssue }

class function TAtlasFlowIssue.Create(const AKey, ATitle, AState: string): TAtlasFlowIssue;
begin
  Result := Default(TAtlasFlowIssue);
  Result.Key := AKey;
  Result.Title := ATitle;
  Result.State := AState;
end;

{ TAtlasFlowData }

class function TAtlasFlowData.Empty: TAtlasFlowData;
begin
  Result := Default(TAtlasFlowData);
end;

{ TAtlasFlowRequest }

class function TAtlasFlowRequest.Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const AStateField: string; ASince: TDateTime; ATimeoutMs: Integer): TAtlasFlowRequest;
begin
  Result.Target := ATarget;
  Result.Transport := ATransport;
  Result.StateField := AStateField;
  Result.Since := ASince;
  Result.TimeoutMs := ATimeoutMs;
end;

{ TAtlasFlowState }

function TAtlasFlowState.AverageDays: Double;
begin
  Result := -1;
  if Stays > 0 then
  begin
    Result := StayDays / Stays;
  end;
end;

{ Auswertung }

type
  /// <summary>Zwischenstand der Auswertung.</summary>
  TFlowBuild = record
    Map: TAtlasFlowMap;
    Data: TAtlasFlowData;
    Now: TDateTime;
    Window: TDateTime;
    StuckDays: Integer;
    /// <summary>Wechsel nach Issue und Zeit geordnet.</summary>
    Sorted: TArray<TAtlasFlowChange>;
    function StateIndex(const AName: string): Integer;
    procedure AddTransition(AFrom, ATo: Integer);
    procedure AddStay(const AState: string; AFrom, ATo: TDateTime);
  end;

function TFlowBuild.StateIndex(const AName: string): Integer;
var
  mState: TAtlasFlowState;
begin
  Result := Map.IndexOf(AName);
  if (Result >= 0) or (Trim(AName) = '') then
  begin
    Exit;
  end;
  mState := Default(TAtlasFlowState);
  mState.Name := Trim(AName);
  Map.States := Map.States + [mState];
  Result := High(Map.States);
end;

procedure TFlowBuild.AddTransition(AFrom, ATo: Integer);
var
  mIndex: Integer;
  mTransition: TAtlasFlowTransition;
begin
  if (AFrom < 0) or (ATo < 0) or (AFrom = ATo) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Map.Transitions) do
  begin
    if (Map.Transitions[mIndex].FromIndex = AFrom) and (Map.Transitions[mIndex].ToIndex = ATo) then
    begin
      Inc(Map.Transitions[mIndex].Count);
      Exit;
    end;
  end;
  mTransition := Default(TAtlasFlowTransition);
  mTransition.FromIndex := AFrom;
  mTransition.ToIndex := ATo;
  mTransition.Count := 1;
  Map.Transitions := Map.Transitions + [mTransition];
end;

procedure TFlowBuild.AddStay(const AState: string; AFrom, ATo: TDateTime);
var
  mIndex: Integer;
begin
  mIndex := StateIndex(AState);
  if (mIndex < 0) or (AFrom <= 0) or (ATo < AFrom) then
  begin
    Exit;
  end;
  Inc(Map.States[mIndex].Stays);
  Map.States[mIndex].StayDays := Map.States[mIndex].StayDays + (ATo - AFrom);
end;

function CompareChanges(const ALeft, ARight: TAtlasFlowChange): Integer;
begin
  Result := CompareText(ALeft.Key, ARight.Key);
  if Result = 0 then
  begin
    Result := CompareValue(ALeft.Time, ARight.Time);
  end;
  if Result = 0 then
  begin
    // Gleiche Zeit: eindeutig weiter (TArray.Sort ist nicht stabil).
    Result := CompareStr(ALeft.Id, ARight.Id);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.ToState, ARight.ToState);
  end;
end;

/// <summary>Wechsel im Zeitraum, nach Issue und Zeit geordnet.</summary>
function SortedChanges(const AChanges: TArray<TAtlasFlowChange>; AWindow: TDateTime): TArray<TAtlasFlowChange>;
var
  mChange: TAtlasFlowChange;
begin
  Result := nil;
  for mChange in AChanges do
  begin
    if (mChange.Key <> '') and (mChange.Time >= AWindow) then
    begin
      Result := Result + [mChange];
    end;
  end;
  TArray.Sort<TAtlasFlowChange>(Result, TComparer<TAtlasFlowChange>.Construct(
    function(const ALeft, ARight: TAtlasFlowChange): Integer
    begin
      Result := CompareChanges(ALeft, ARight);
    end));
end;

/// <summary>Übergänge und Aufenthalte der Wechsel von ABuild.Sorted[AFirst..ALast] (ein Issue).</summary>
procedure CountIssue(var ABuild: TFlowBuild; AFirst, ALast: Integer);
var
  mIndex: Integer;
  mFirst: TAtlasFlowChange;
begin
  mFirst := ABuild.Sorted[AFirst];
  // Erster Aufenthalt: nur, wenn das Issue im Zeitraum angelegt wurde (sonst ist sein Beginn unbekannt).
  if (mFirst.Created >= ABuild.Window) and (mFirst.FromState <> '') then
  begin
    ABuild.AddStay(mFirst.FromState, mFirst.Created, mFirst.Time);
  end;
  for mIndex := AFirst to ALast do
  begin
    ABuild.AddTransition(ABuild.StateIndex(ABuild.Sorted[mIndex].FromState),
      ABuild.StateIndex(ABuild.Sorted[mIndex].ToState));
    if mIndex > AFirst then
    begin
      ABuild.AddStay(ABuild.Sorted[mIndex - 1].ToState, ABuild.Sorted[mIndex - 1].Time, ABuild.Sorted[mIndex].Time);
    end;
  end;
end;

/// <summary>Alle Wechsel auswerten; liefert die Zahl der Issues mit Wechsel.</summary>
function CountChanges(var ABuild: TFlowBuild): Integer;
var
  mFirst, mIndex: Integer;
begin
  Result := 0;
  mFirst := 0;
  for mIndex := 0 to High(ABuild.Sorted) do
  begin
    if (mIndex = High(ABuild.Sorted)) or not SameText(ABuild.Sorted[mIndex + 1].Key, ABuild.Sorted[mIndex].Key) then
    begin
      CountIssue(ABuild, mFirst, mIndex);
      Inc(Result);
      mFirst := mIndex + 1;
    end;
  end;
end;

/// <summary>Letzter Wechsel von AKey in den Zustand AState; False ohne.</summary>
function LastEntry(const ABuild: TFlowBuild; const AKey, AState: string; out ATime: TDateTime): Boolean;
var
  mChange: TAtlasFlowChange;
begin
  Result := False;
  ATime := 0;
  for mChange in ABuild.Sorted do
  begin
    if SameText(mChange.Key, AKey) and SameText(mChange.ToState, AState) and (mChange.Time >= ATime) then
    begin
      ATime := mChange.Time;
      Result := True;
    end;
  end;
end;

/// <summary>Seit wann AIssue in seinem Zustand steht; ABefore, wenn das vor dem Zeitraum liegt.</summary>
function SinceOfIssue(const ABuild: TFlowBuild; const AIssue: TAtlasFlowIssue; out ABefore: Boolean): TDateTime;
begin
  ABefore := False;
  if LastEntry(ABuild, AIssue.Key, AIssue.State, Result) then
  begin
    Exit;
  end;
  // Kein Wechsel im Zeitraum: seit der Anlage, sonst mindestens seit Beginn des Zeitraums.
  Result := AIssue.Created;
  if Result < ABuild.Window then
  begin
    Result := ABuild.Window;
    ABefore := True;
  end;
end;

function IsResolved(const AData: TAtlasFlowData; const AState: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AData.Resolved do
  begin
    if SameText(mName, AState) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Offene Issues zählen und die Liste „Liegt lange“ füllen.</summary>
procedure CountOpen(var ABuild: TFlowBuild);
var
  mIssue: TAtlasFlowIssue;
  mIndex: Integer;
  mStuck: TAtlasFlowStuck;
begin
  for mIssue in ABuild.Data.Open do
  begin
    mIndex := ABuild.StateIndex(mIssue.State);
    if mIndex < 0 then
    begin
      Continue;
    end;
    Inc(ABuild.Map.States[mIndex].OpenCount);
    if mIssue.Mine then
    begin
      Inc(ABuild.Map.States[mIndex].MineCount);
    end;
    if IsResolved(ABuild.Data, mIssue.State) then
    begin
      Continue;
    end;
    mStuck := Default(TAtlasFlowStuck);
    mStuck.Since := SinceOfIssue(ABuild, mIssue, mStuck.Before);
    mStuck.Days := Max(0, Trunc(ABuild.Now - mStuck.Since));
    if mStuck.Days >= ABuild.StuckDays then
    begin
      mStuck.Key := mIssue.Key;
      mStuck.Title := mIssue.Title;
      mStuck.State := ABuild.Map.States[mIndex].Name;
      mStuck.Assignee := mIssue.Assignee;
      mStuck.Mine := mIssue.Mine;
      ABuild.Map.Stuck := ABuild.Map.Stuck + [mStuck];
      Inc(ABuild.Map.States[mIndex].StuckCount);
    end;
  end;
  TArray.Sort<TAtlasFlowStuck>(ABuild.Map.Stuck, TComparer<TAtlasFlowStuck>.Construct(
    function(const ALeft, ARight: TAtlasFlowStuck): Integer
    begin
      Result := CompareValue(ALeft.Since, ARight.Since);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Key, ARight.Key);
      end;
    end));
end;

{ Anordnung }

type
  TFlowCounts = record
    Outgoing: TArray<Integer>;
    Incoming: TArray<Integer>;
  end;

function CountsOf(const AMap: TAtlasFlowMap): TFlowCounts;
var
  mTransition: TAtlasFlowTransition;
begin
  SetLength(Result.Outgoing, Length(AMap.States));
  SetLength(Result.Incoming, Length(AMap.States));
  for mTransition in AMap.Transitions do
  begin
    Inc(Result.Outgoing[mTransition.FromIndex], mTransition.Count);
    Inc(Result.Incoming[mTransition.ToIndex], mTransition.Count);
  end;
end;

/// <summary>Ist ACandidate bei gleichem Überschuss der bessere Start als ABest: mehr ausgehende Wechsel, dann Name.
/// </summary>
function BreaksTie(const AMap: TAtlasFlowMap; const ACounts: TFlowCounts; ACandidate, ABest: Integer): Boolean;
begin
  if ACounts.Outgoing[ACandidate] <> ACounts.Outgoing[ABest] then
  begin
    Exit(ACounts.Outgoing[ACandidate] > ACounts.Outgoing[ABest]);
  end;
  Result := CompareText(AMap.States[ACandidate].Name, AMap.States[ABest].Name) < 0;
end;

/// <summary>Start des Hauptwegs: größter Überschuss ausgehender Wechsel, dann mehr ausgehende, dann Name; -1 ohne
/// Übergang.</summary>
function StartState(const AMap: TAtlasFlowMap; const ACounts: TFlowCounts): Integer;
var
  mIndex, mBest, mScore, mBestScore: Integer;
begin
  Result := -1;
  mBestScore := 0;
  for mIndex := 0 to High(AMap.States) do
  begin
    if ACounts.Outgoing[mIndex] = 0 then
    begin
      Continue;
    end;
    mScore := ACounts.Outgoing[mIndex] - ACounts.Incoming[mIndex];
    mBest := Result;
    if (mBest < 0) or (mScore > mBestScore) or ((mScore = mBestScore) and BreaksTie(AMap, ACounts, mIndex, mBest)) then
    begin
      Result := mIndex;
      mBestScore := mScore;
    end;
  end;
end;

/// <summary>Häufigster Übergang von AFrom in einen Zustand ohne Platz; -1 ohne.</summary>
function NextState(const AMap: TAtlasFlowMap; AFrom: Integer; const APlaced: TArray<Boolean>): Integer;
var
  mTransition: TAtlasFlowTransition;
  mBest: Integer;
begin
  Result := -1;
  mBest := 0;
  for mTransition in AMap.Transitions do
  begin
    if (mTransition.FromIndex <> AFrom) or APlaced[mTransition.ToIndex] then
    begin
      Continue;
    end;
    if (mTransition.Count > mBest) or ((mTransition.Count = mBest) and (Result >= 0) and
      (CompareText(AMap.States[mTransition.ToIndex].Name, AMap.States[Result].Name) < 0)) then
    begin
      Result := mTransition.ToIndex;
      mBest := mTransition.Count;
    end;
  end;
end;

/// <summary>Verkehr eines Zustands: Wechsel hinein und hinaus plus offene Issues.</summary>
function Traffic(const AMap: TAtlasFlowMap; const ACounts: TFlowCounts; AIndex: Integer): Integer;
begin
  Result := ACounts.Outgoing[AIndex] + ACounts.Incoming[AIndex] + AMap.States[AIndex].OpenCount;
end;

/// <summary>Übrige Zustände (ohne Platz) nach Verkehr, dann Name.</summary>
function RestStates(const AMap: TAtlasFlowMap; const ACounts: TFlowCounts;
  const APlaced: TArray<Boolean>): TArray<Integer>;
var
  mIndex: Integer;
  mMap: TAtlasFlowMap;
  mCounts: TFlowCounts;
begin
  Result := nil;
  for mIndex := 0 to High(AMap.States) do
  begin
    if not APlaced[mIndex] then
    begin
      Result := Result + [mIndex];
    end;
  end;
  mMap := AMap;
  mCounts := ACounts;
  TArray.Sort<Integer>(Result, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := Traffic(mMap, mCounts, ARight) - Traffic(mMap, mCounts, ALeft);
      if Result = 0 then
      begin
        Result := CompareText(mMap.States[ALeft].Name, mMap.States[ARight].Name);
      end;
    end));
end;

/// <summary>Zeile und Platz je Zustand, Rückwege markieren.</summary>
procedure Arrange(var AMap: TAtlasFlowMap);
var
  mCounts: TFlowCounts;
  mPlaced: TArray<Boolean>;
  mCurrent, mColumn, mRow, mIndex: Integer;
  mRest: TArray<Integer>;
begin
  mCounts := CountsOf(AMap);
  SetLength(mPlaced, Length(AMap.States));
  mColumn := 0;
  mCurrent := StartState(AMap, mCounts);
  while mCurrent >= 0 do
  begin
    mPlaced[mCurrent] := True;
    AMap.States[mCurrent].Row := 0;
    AMap.States[mCurrent].Column := mColumn;
    Inc(mColumn);
    mCurrent := NextState(AMap, mCurrent, mPlaced);
  end;
  // Ohne Hauptweg (keine Wechsel) stehen alle Zustände in der ersten Zeile.
  mRow := 1;
  if mColumn = 0 then
  begin
    mRow := 0;
  end;
  mRest := RestStates(AMap, mCounts, mPlaced);
  for mIndex := 0 to High(mRest) do
  begin
    AMap.States[mRest[mIndex]].Row := mRow;
    AMap.States[mRest[mIndex]].Column := mIndex;
  end;
  for mIndex := 0 to High(AMap.Transitions) do
  begin
    AMap.Transitions[mIndex].Back := (AMap.States[AMap.Transitions[mIndex].FromIndex].Row = 0) and
      (AMap.States[AMap.Transitions[mIndex].ToIndex].Row = 0) and
      (AMap.States[AMap.Transitions[mIndex].ToIndex].Column < AMap.States[AMap.Transitions[mIndex].FromIndex].Column);
  end;
end;

/// <summary>Issues mit Wechsel oder offen, ohne doppelte.</summary>
function DistinctIssues(const ABuild: TFlowBuild; AWithChanges: Integer): Integer;
var
  mIssue: TAtlasFlowIssue;
  mChange: TAtlasFlowChange;
  mFound: Boolean;
begin
  Result := AWithChanges;
  for mIssue in ABuild.Data.Open do
  begin
    mFound := False;
    for mChange in ABuild.Sorted do
    begin
      if SameText(mChange.Key, mIssue.Key) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasFlowMap.Build(const AData: TAtlasFlowData; ANow: TDateTime; AStuckDays: Integer): TAtlasFlowMap;
var
  mBuild: TFlowBuild;
  mIndex: Integer;
begin
  mBuild := Default(TFlowBuild);
  mBuild.Data := AData;
  mBuild.Now := ANow;
  mBuild.Window := TAtlasTrackerFlow.WindowStart(ANow, AData.Days);
  mBuild.StuckDays := Max(1, AStuckDays);
  mBuild.Sorted := SortedChanges(AData.Changes, mBuild.Window);
  mBuild.Map.Days := AData.Days;
  mBuild.Map.Truncated := AData.Truncated;
  mBuild.Map.ChangeCount := Length(mBuild.Sorted);
  mBuild.Map.IssueCount := DistinctIssues(mBuild, CountChanges(mBuild));
  CountOpen(mBuild);
  for mIndex := 0 to High(mBuild.Map.States) do
  begin
    mBuild.Map.States[mIndex].Resolved := IsResolved(AData, mBuild.Map.States[mIndex].Name);
  end;
  Arrange(mBuild.Map);
  Result := mBuild.Map;
end;

function TAtlasFlowMap.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(States) do
  begin
    if SameText(States[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasFlowMap.MaxCount: Integer;
var
  mTransition: TAtlasFlowTransition;
begin
  Result := 0;
  for mTransition in Transitions do
  begin
    Result := Max(Result, mTransition.Count);
  end;
end;

function TAtlasFlowMap.StuckIn(const AState: string): TArray<TAtlasFlowStuck>;
var
  mStuck: TAtlasFlowStuck;
begin
  Result := nil;
  for mStuck in Stuck do
  begin
    if (AState = '') or SameText(mStuck.State, AState) then
    begin
      Result := Result + [mStuck];
    end;
  end;
end;

function TAtlasFlowMap.RowStates(ARow: Integer): TArray<Integer>;
var
  mIndex, mColumn: Integer;
begin
  Result := nil;
  mColumn := 0;
  // Platz für Platz: die Spalten einer Zeile sind lückenlos ab 0.
  while True do
  begin
    mIndex := 0;
    while (mIndex <= High(States)) and not ((States[mIndex].Row = ARow) and (States[mIndex].Column = mColumn)) do
    begin
      Inc(mIndex);
    end;
    if mIndex > High(States) then
    begin
      Break;
    end;
    Result := Result + [mIndex];
    Inc(mColumn);
  end;
end;

{ TAtlasTrackerFlow }

class function TAtlasTrackerFlow.WindowStart(ANow: TDateTime; ADays: Integer): TDateTime;
begin
  Result := ANow - Max(1, ADays);
end;

class function TAtlasTrackerFlow.SinceOf(const ACached: TAtlasFlowData; AHasCache: Boolean; ANow: TDateTime;
  ADays: Integer; const AStateField: string): TDateTime;
var
  mWindow: TDateTime;
begin
  mWindow := WindowStart(ANow, ADays);
  Result := mWindow;
  // Nur ein vollständiger Stand mit denselben Vorgaben, abgerufen innerhalb des Zeitraums, trägt das Nachladen.
  if not AHasCache or ACached.Truncated or (ACached.Days <> ADays) then
  begin
    Exit;
  end;
  if SameText(ACached.StateField, AStateField) and (ACached.Fetched > mWindow) and (ACached.Fetched <= ANow) then
  begin
    Result := ACached.Fetched - cOverlapMinutes / MinsPerDay;
  end;
end;

function ChangeIndex(const AChanges: TArray<TAtlasFlowChange>; const AChange: TAtlasFlowChange): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AChanges) do
  begin
    if (AChange.Id <> '') and (AChanges[mIndex].Id = AChange.Id) then
    begin
      Exit(mIndex);
    end;
    if (AChange.Id = '') and SameText(AChanges[mIndex].Key, AChange.Key) and SameValue(AChanges[mIndex].Time,
      AChange.Time) and SameText(AChanges[mIndex].ToState, AChange.ToState) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTrackerFlow.Merge(const AOld, ANew: TAtlasFlowData; AUseOld: Boolean;
  ANow: TDateTime): TAtlasFlowData;
var
  mWindow: TDateTime;
  mChange: TAtlasFlowChange;
  mIndex: Integer;
begin
  Result := ANew;
  Result.Changes := nil;
  mWindow := WindowStart(ANow, ANew.Days);
  if AUseOld then
  begin
    for mChange in AOld.Changes do
    begin
      if mChange.Time >= mWindow then
      begin
        Result.Changes := Result.Changes + [mChange];
      end;
    end;
  end;
  for mChange in ANew.Changes do
  begin
    if mChange.Time < mWindow then
    begin
      Continue;
    end;
    mIndex := ChangeIndex(Result.Changes, mChange);
    if mIndex >= 0 then
    begin
      Result.Changes[mIndex] := mChange;
    end
    else
    begin
      Result.Changes := Result.Changes + [mChange];
    end;
  end;
end;

{ Zwischenspeicher }

function ChangesJson(const AChanges: TArray<TAtlasFlowChange>): TJSONArray;
var
  mChange: TAtlasFlowChange;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mChange in AChanges do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('id', mChange.Id);
    mItem.AddPair('key', mChange.Key);
    mItem.AddPair('title', mChange.Title);
    mItem.AddPair('time', TAtlasTrackerBoard.TimeText(mChange.Time));
    mItem.AddPair('created', TAtlasTrackerBoard.TimeText(mChange.Created));
    mItem.AddPair('from', mChange.FromState);
    mItem.AddPair('to', mChange.ToState);
    Result.AddElement(mItem);
  end;
end;

function OpenJson(const AIssues: TArray<TAtlasFlowIssue>): TJSONArray;
var
  mIssue: TAtlasFlowIssue;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mIssue in AIssues do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('key', mIssue.Key);
    mItem.AddPair('title', mIssue.Title);
    mItem.AddPair('state', mIssue.State);
    mItem.AddPair('assignee', mIssue.Assignee);
    mItem.AddPair('created', TAtlasTrackerBoard.TimeText(mIssue.Created));
    mItem.AddPair('mine', TJSONBool.Create(mIssue.Mine));
    Result.AddElement(mItem);
  end;
end;

function TextsJson(const ATexts: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ATexts do
  begin
    Result.Add(mText);
  end;
end;

class function TAtlasTrackerFlow.ToJson(const AData: TAtlasFlowData): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(TAtlasFlowData.cVersion));
    mRoot.AddPair('fetched', TAtlasTrackerBoard.TimeText(AData.Fetched));
    mRoot.AddPair('days', TJSONNumber.Create(AData.Days));
    mRoot.AddPair('stateField', AData.StateField);
    mRoot.AddPair('truncated', TJSONBool.Create(AData.Truncated));
    mRoot.AddPair('resolved', TextsJson(AData.Resolved));
    mRoot.AddPair('changes', ChangesJson(AData.Changes));
    mRoot.AddPair('open', OpenJson(AData.Open));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function ChangesOf(AValue: TJSONValue): TArray<TAtlasFlowChange>;
var
  mItem: TJSONValue;
  mObject: TJSONObject;
  mChange: TAtlasFlowChange;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mObject := TJSONObject(mItem);
    mChange := TAtlasFlowChange.Create(TJsonRead.Text(mObject, 'id'), TJsonRead.Text(mObject, 'key'),
      TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mObject, 'time')), TJsonRead.Text(mObject, 'from'),
      TJsonRead.Text(mObject, 'to'));
    mChange.Title := TJsonRead.Text(mObject, 'title');
    mChange.Created := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mObject, 'created'));
    Result := Result + [mChange];
  end;
end;

function OpenOf(AValue: TJSONValue): TArray<TAtlasFlowIssue>;
var
  mItem: TJSONValue;
  mObject: TJSONObject;
  mIssue: TAtlasFlowIssue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mObject := TJSONObject(mItem);
    mIssue := TAtlasFlowIssue.Create(TJsonRead.Text(mObject, 'key'), TJsonRead.Text(mObject, 'title'),
      TJsonRead.Text(mObject, 'state'));
    mIssue.Assignee := TJsonRead.Text(mObject, 'assignee');
    mIssue.Created := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mObject, 'created'));
    mIssue.Mine := TJsonRead.Flag(mObject, 'mine');
    Result := Result + [mIssue];
  end;
end;

function TextsOf(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [TJSONString(mItem).Value];
      end;
    end;
  end;
end;

class function TAtlasTrackerFlow.FromJson(const AJson: string; out AData: TAtlasFlowData): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  AData := TAtlasFlowData.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if TJsonRead.Int(mRoot, 'version') <> TAtlasFlowData.cVersion then
    begin
      Exit;
    end;
    AData.Fetched := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mRoot, 'fetched'));
    AData.Days := TJsonRead.Int(mRoot, 'days');
    AData.StateField := TJsonRead.Text(mRoot, 'stateField');
    AData.Truncated := TJsonRead.Flag(mRoot, 'truncated');
    AData.Resolved := TextsOf(mRoot.Values['resolved']);
    AData.Changes := ChangesOf(mRoot.Values['changes']);
    AData.Open := OpenOf(mRoot.Values['open']);
    Result := True;
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasTrackerFlow.Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const AData: TAtlasFlowData);
begin
  TAtlasTrackerBoard.WriteText(TAtlasTrackerBoard.CacheFile(AFolder, ATarget, cCacheName), ToJson(AData));
end;

class function TAtlasTrackerFlow.Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  out AData: TAtlasFlowData): Boolean;
var
  mText: string;
begin
  AData := TAtlasFlowData.Empty;
  Result := TAtlasTrackerBoard.ReadText(TAtlasTrackerBoard.CacheFile(AFolder, ATarget, cCacheName), mText) and
    FromJson(mText, AData);
end;

end.
