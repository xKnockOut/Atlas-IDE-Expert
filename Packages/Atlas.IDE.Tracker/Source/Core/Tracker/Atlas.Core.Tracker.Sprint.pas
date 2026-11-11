unit Atlas.Core.Tracker.Sprint;

// Sprint-Kachel der Atlas-Startseite (#1277), ohne VCL und Open Tools API.
// - Quelle ist das Board aus #1272 (TAtlasBoardSnapshot des aktuellen
//   Sprints): YouTrack-Agile-Board bzw. GitHub-Projekt mit Iterationen.
// - Arbeitstage (TAtlasSprintCalendar): Vorgabe Montag bis Freitag; YouTrack
//   liefert sie über IAtlasTrackerWorkDays. Resttage zählen den heutigen Tag
//   mit. Liegt kein Arbeitstag im Sprint, zählen alle Tage.
// - Burndown (TAtlasTrackerSprint.Summarize): Rest nach k Arbeitstagen aus dem
//   Zeitpunkt der Erledigung je Karte; mit Schätzfeld in Punkten (Karten ohne
//   Schätzung zählen 0), sonst als Anzahl. Karten in einer Erledigt-Spalte
//   ohne Zeitpunkt zählen ab der Abfrage. Ideallinie gerade von der Summe am
//   Start bis 0 am letzten Arbeitstag.
// - Vergleich mit dem vorherigen Sprint: dessen Werte auf den Sprinttag
//   normiert (gleicher Anteil am Sprint, auch bei anderer Länge), Abweichung
//   am heutigen Sprinttag und Velocity (erledigt am Ende) der letzten drei
//   Sprints. Abgeschlossene Sprints ändern sich nicht: Ihre Zusammenfassung
//   (TAtlasSprintSummary) liegt im Zwischenspeicher neben dem Board.

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board;

type
  /// <summary>Arbeitstage des Trackers (#1277); optional neben IAtlasTrackerBoards, im Hintergrund.</summary>
  IAtlasTrackerWorkDays = interface
    ['{6B1E4D27-3A8C-4F95-B7D2-1C9E5A3F8B64}']
    /// <summary>Arbeitstage 1 = Montag … 7 = Sonntag; False ohne Antwort (dann gilt Montag bis Freitag).</summary>
    function WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ADays: TArray<Integer>): Boolean;
  end;

  TAtlasSprintCalendar = record
  public
    /// <summary>Arbeitstage nach ISO: 1 = Montag … 7 = Sonntag.</summary>
    Days: TArray<Integer>;
    /// <summary>Montag bis Freitag.</summary>
    class function WorkWeek: TAtlasSprintCalendar; static;
    /// <summary>Aus ADays (Werte außerhalb 1–7 fallen weg); ohne gültigen Tag Montag bis Freitag.</summary>
    class function Create(const ADays: TArray<Integer>): TAtlasSprintCalendar; static;
    /// <summary>"1,2,3,4,5" bzw. zurück (Zwischenspeicher).</summary>
    function Text: string;
    class function FromText(const AText: string): TAtlasSprintCalendar; static;
    function IsWorkDay(ADate: TDateTime): Boolean;
    /// <summary>Arbeitstage (Datum ohne Uhrzeit) vom Tag von AStart bis zum letzten Tag vor AFinish; ohne
    /// Arbeitstag im Zeitraum alle Tage; leer ohne Zeitraum.</summary>
    function SprintDays(AStart, AFinish: TDateTime): TArray<TDateTime>;
    /// <summary>Verbleibende Arbeitstage ab dem Tag von ANow (zählt mit) bis Sprintende; 0 danach.</summary>
    function DaysLeft(ANow, AStart, AFinish: TDateTime): Integer;
  end;

  /// <summary>Ein Sprint für Vergleich und Velocity; abgeschlossene im Zwischenspeicher.</summary>
  TAtlasSprintSummary = record
  public const
    cVersion = 1;
  public
    Id: string;
    Name: string;
    Start: TDateTime;
    Finish: TDateTime;
    /// <summary>Werte in Punkten des Schätzfeldes, sonst Anzahl Issues.</summary>
    UsesPoints: Boolean;
    Total: Double;
    /// <summary>Arbeitstage des Sprints.</summary>
    Days: Integer;
    /// <summary>Erledigt (kumuliert) nach k Arbeitstagen, k = 0 … bis heute bzw. Days.</summary>
    Done: TArray<Double>;
    /// <summary>Erledigt am Ende (letzter Wert); 0 ohne.</summary>
    function Velocity: Double;
    /// <summary>Erledigt am selben Anteil des Sprints (0 = Start, 1 = Ende), auf den nächsten Tag gerundet.
    /// </summary>
    function DoneAt(AFraction: Double): Double;
  end;

  TAtlasSprintView = record
    /// <summary>Ein Sprint mit Zeitraum ist da.</summary>
    Known: Boolean;
    Name: string;
    Start: TDateTime;
    Finish: TDateTime;
    /// <summary>Board im Browser; '' unbekannt.</summary>
    Page: string;
    DayCount: Integer;
    /// <summary>Arbeitstage des Sprints (Datum, UTC); Tag k des Diagramms endet mit Dates[k - 1].</summary>
    Dates: TArray<TDateTime>;
    DaysLeft: Integer;
    /// <summary>Arbeitstage bis heute (Ist-Linie hat Today + 1 Punkte).</summary>
    Today: Integer;
    UsesPoints: Boolean;
    /// <summary>Anmeldename bekannt: Zahlen „meine …“ gelten.</summary>
    MineKnown: Boolean;
    MineOpen: TArray<TAtlasTrackerIssue>;
    MineDone: TArray<TAtlasTrackerIssue>;
    Total: Double;
    TeamDone: Double;
    TeamLeft: Double;
    /// <summary>Rest nach k Arbeitstagen, k = 0 … Today.</summary>
    Actual: TArray<Double>;
    /// <summary>Ideallinie, k = 0 … DayCount.</summary>
    Ideal: TArray<Double>;
    HasPrevious: Boolean;
    PreviousName: string;
    /// <summary>Rest des Vorsprints auf diesen Sprint normiert und auf Total skaliert, k = 0 … DayCount.</summary>
    Previous: TArray<Double>;
    /// <summary>Erledigt im Vorsprint am selben Sprinttag (in seiner Einheit).</summary>
    PreviousDone: Double;
    /// <summary>Erledigt in diesem Sprint bis heute (Done[Today]).</summary>
    DoneToday: Double;
    /// <summary>Velocity der letzten Sprints, ältester zuerst (höchstens drei).</summary>
    Velocity: TArray<Double>;
    VelocityNames: TArray<string>;
    Fetched: TDateTime;
  end;

  TAtlasTrackerSprint = class
  public const
    /// <summary>So viele frühere Sprints für die Velocity.</summary>
    cVelocitySprints = 3;
    /// <summary>Höchstens so viele Tage hat ein Sprint (Schutz gegen kaputte Daten).</summary>
    cMaxDays = 366;
    /// <summary>Zeitgrenze für Board, Vorsprints und Arbeitstage zusammen.</summary>
    cTimeoutMs = 15000;
  public
    /// <summary>Gewicht einer Karte: Punkte (ohne Schätzung 0) bzw. 1.</summary>
    class function Weight(const ACard: TAtlasBoardCard; AUsesPoints: Boolean): Double; static;
    /// <summary>Schätzfeld da und mindestens eine Karte geschätzt.</summary>
    class function UsesPoints(const ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>Zeitpunkt der Erledigung der Karte ACard (UTC); in einer Erledigt-Spalte ohne Zeitpunkt
    /// ANow; 0 = offen.</summary>
    class function DoneAt(const ASnapshot: TAtlasBoardSnapshot; ACard: Integer; ANow: TDateTime): TDateTime; static;
    /// <summary>Zusammenfassung des Sprints in ASnapshot zum Zeitpunkt ANow (UTC).</summary>
    class function Summarize(const ASnapshot: TAtlasBoardSnapshot; const ACalendar: TAtlasSprintCalendar;
      ANow: TDateTime): TAtlasSprintSummary; static;
    /// <summary>Gerade von ATotal bis 0 über ADays Tage (ADays + 1 Punkte).</summary>
    class function Ideal(ATotal: Double; ADays: Integer): TArray<Double>; static;
    /// <summary>APrevious auf ADays Tage normiert: Rest als Anteil × AScale, k = 0 … ADays.</summary>
    class function Normalized(const APrevious: TAtlasSprintSummary; ADays: Integer;
      AScale: Double): TArray<Double>; static;
    /// <summary>Bis zu ACount Sprints, die vor ACurrent enden, ältester zuerst.</summary>
    class function PreviousSprints(const ASprints: TArray<TAtlasBoardSprint>; const ACurrent: TAtlasBoardSprint;
      ACount: Integer): TArray<TAtlasBoardSprint>; static;
    /// <summary>Alles für die Kachel. APrevious: frühere Sprints, ältester zuerst (der letzte ist der Vorsprint);
    /// leer ohne Vergleich.</summary>
    class function View(const ASnapshot: TAtlasBoardSnapshot; const ACalendar: TAtlasSprintCalendar;
      ANow: TDateTime; const APrevious: TArray<TAtlasSprintSummary>): TAtlasSprintView; static;
    class function SummaryToJson(const ASummary: TAtlasSprintSummary): string; static;
    /// <summary>False bei ungültigem JSON oder anderer Version.</summary>
    class function SummaryFromJson(const AJson: string; out ASummary: TAtlasSprintSummary): Boolean; static;
    /// <summary>Name der Datei eines abgeschlossenen Sprints im Zwischenspeicher (für CacheFile).</summary>
    class function SummaryName(const ABoardId, ASprintId: string): string; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

{ TAtlasSprintCalendar }

class function TAtlasSprintCalendar.WorkWeek: TAtlasSprintCalendar;
begin
  Result.Days := TArray<Integer>.Create(1, 2, 3, 4, 5);
end;

class function TAtlasSprintCalendar.Create(const ADays: TArray<Integer>): TAtlasSprintCalendar;
var
  mDay, mKnown: Integer;
  mFound: Boolean;
begin
  Result.Days := nil;
  for mDay in ADays do
  begin
    if (mDay < 1) or (mDay > 7) then
    begin
      Continue;
    end;
    mFound := False;
    for mKnown in Result.Days do
    begin
      if mKnown = mDay then
      begin
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Result.Days := Result.Days + [mDay];
    end;
  end;
  if Length(Result.Days) = 0 then
  begin
    Result := WorkWeek;
  end;
end;

function TAtlasSprintCalendar.Text: string;
var
  mDay: Integer;
begin
  Result := '';
  for mDay in Days do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(mDay);
  end;
end;

class function TAtlasSprintCalendar.FromText(const AText: string): TAtlasSprintCalendar;
var
  mPart: string;
  mDay: Integer;
  mDays: TArray<Integer>;
begin
  mDays := nil;
  for mPart in AText.Split([',']) do
  begin
    if TryStrToInt(Trim(mPart), mDay) then
    begin
      mDays := mDays + [mDay];
    end;
  end;
  Result := Create(mDays);
end;

function TAtlasSprintCalendar.IsWorkDay(ADate: TDateTime): Boolean;
var
  mDay, mWeekDay: Integer;
begin
  mWeekDay := DayOfTheWeek(ADate);
  Result := False;
  for mDay in Days do
  begin
    if mDay = mWeekDay then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasSprintCalendar.SprintDays(AStart, AFinish: TDateTime): TArray<TDateTime>;
var
  mDay, mLast: TDateTime;
  mAll: TArray<TDateTime>;
begin
  Result := nil;
  if (AStart <= 0) or (AFinish <= AStart) then
  begin
    Exit;
  end;
  // Das Ende gehört nicht mehr dazu (GitHub: Start + Dauer; YouTrack: Mitternacht nach dem letzten Tag).
  mLast := DateOf(AFinish - OneSecond);
  mDay := DateOf(AStart);
  mAll := nil;
  while (mDay <= mLast) and (Length(mAll) < TAtlasTrackerSprint.cMaxDays) do
  begin
    mAll := mAll + [mDay];
    if IsWorkDay(mDay) then
    begin
      Result := Result + [mDay];
    end;
    mDay := IncDay(mDay);
  end;
  if Length(Result) = 0 then
  begin
    Result := mAll;
  end;
end;

function TAtlasSprintCalendar.DaysLeft(ANow, AStart, AFinish: TDateTime): Integer;
var
  mDay: TDateTime;
begin
  Result := 0;
  for mDay in SprintDays(AStart, AFinish) do
  begin
    if mDay >= DateOf(ANow) then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasSprintSummary }

function TAtlasSprintSummary.Velocity: Double;
begin
  Result := 0;
  if Length(Done) > 0 then
  begin
    Result := Done[High(Done)];
  end;
end;

function TAtlasSprintSummary.DoneAt(AFraction: Double): Double;
var
  mIndex: Integer;
begin
  Result := 0;
  if Length(Done) = 0 then
  begin
    Exit;
  end;
  mIndex := Round(EnsureRange(AFraction, 0, 1) * Days);
  Result := Done[Min(mIndex, High(Done))];
end;

{ TAtlasTrackerSprint }

class function TAtlasTrackerSprint.Weight(const ACard: TAtlasBoardCard; AUsesPoints: Boolean): Double;
begin
  Result := 1;
  if not AUsesPoints then
  begin
    Exit;
  end;
  Result := 0;
  if ACard.HasPoints and (ACard.Points > 0) then
  begin
    Result := ACard.Points;
  end;
end;

class function TAtlasTrackerSprint.UsesPoints(const ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mCard: TAtlasBoardCard;
begin
  Result := False;
  if Trim(ASnapshot.PointsField) = '' then
  begin
    Exit;
  end;
  for mCard in ASnapshot.Cards do
  begin
    if mCard.HasPoints then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTrackerSprint.DoneAt(const ASnapshot: TAtlasBoardSnapshot; ACard: Integer;
  ANow: TDateTime): TDateTime;
var
  mColumn: Integer;
begin
  Result := 0;
  if (ACard < 0) or (ACard > High(ASnapshot.Cards)) then
  begin
    Exit;
  end;
  mColumn := ASnapshot.CardColumn(ACard);
  // Wieder geöffnet: Der alte Zeitpunkt der Erledigung zählt nicht.
  if (mColumn >= 0) and not ASnapshot.Columns[mColumn].Resolved then
  begin
    Exit;
  end;
  if ASnapshot.Cards[ACard].ResolvedAt > 0 then
  begin
    Exit(ASnapshot.Cards[ACard].ResolvedAt);
  end;
  if mColumn >= 0 then
  begin
    Result := ASnapshot.Fetched;
    if Result <= 0 then
    begin
      Result := ANow;
    end;
  end;
end;

class function TAtlasTrackerSprint.Summarize(const ASnapshot: TAtlasBoardSnapshot;
  const ACalendar: TAtlasSprintCalendar; ANow: TDateTime): TAtlasSprintSummary;
var
  mDays: TArray<TDateTime>;
  mToday, mDay, mCard: Integer;
  mLimit, mDone: TDateTime;
  mWeights: TArray<Double>;
  mDoneAt: TArray<TDateTime>;
  mSum: Double;
begin
  Result := Default(TAtlasSprintSummary);
  Result.Id := ASnapshot.Sprint.Id;
  Result.Name := ASnapshot.Sprint.Name;
  Result.Start := ASnapshot.Sprint.Start;
  Result.Finish := ASnapshot.Sprint.Finish;
  Result.UsesPoints := UsesPoints(ASnapshot);
  mDays := ACalendar.SprintDays(ASnapshot.Sprint.Start, ASnapshot.Sprint.Finish);
  Result.Days := Length(mDays);
  SetLength(mWeights, Length(ASnapshot.Cards));
  SetLength(mDoneAt, Length(ASnapshot.Cards));
  for mCard := 0 to High(ASnapshot.Cards) do
  begin
    mWeights[mCard] := Weight(ASnapshot.Cards[mCard], Result.UsesPoints);
    mDoneAt[mCard] := DoneAt(ASnapshot, mCard, ANow);
    Result.Total := Result.Total + mWeights[mCard];
  end;
  // Tage bis heute: der laufende Tag zählt mit; nach dem Ende alle.
  mToday := 0;
  for mDay := 0 to High(mDays) do
  begin
    if mDays[mDay] <= DateOf(ANow) then
    begin
      mToday := mDay + 1;
    end;
  end;
  SetLength(Result.Done, mToday + 1);
  for mDay := 0 to mToday do
  begin
    // k = 0: vor dem ersten Tag; sonst bis zum Ende des k-ten Arbeitstags.
    if mDay = 0 then
    begin
      mLimit := DateOf(ASnapshot.Sprint.Start);
    end
    else
    begin
      mLimit := mDays[mDay - 1] + 1;
    end;
    mSum := 0;
    for mCard := 0 to High(ASnapshot.Cards) do
    begin
      mDone := mDoneAt[mCard];
      if (mDone > 0) and (mDone < mLimit) then
      begin
        mSum := mSum + mWeights[mCard];
      end;
    end;
    Result.Done[mDay] := mSum;
  end;
end;

class function TAtlasTrackerSprint.Ideal(ATotal: Double; ADays: Integer): TArray<Double>;
var
  mDay: Integer;
begin
  if ADays <= 0 then
  begin
    Exit(TArray<Double>.Create(ATotal));
  end;
  SetLength(Result, ADays + 1);
  for mDay := 0 to ADays do
  begin
    Result[mDay] := ATotal * (ADays - mDay) / ADays;
  end;
end;

class function TAtlasTrackerSprint.Normalized(const APrevious: TAtlasSprintSummary; ADays: Integer;
  AScale: Double): TArray<Double>;
var
  mDay: Integer;
  mFraction, mDone: Double;
begin
  Result := nil;
  if (ADays <= 0) or (APrevious.Days <= 0) or (APrevious.Total <= 0) or (Length(APrevious.Done) = 0) then
  begin
    Exit;
  end;
  SetLength(Result, ADays + 1);
  for mDay := 0 to ADays do
  begin
    mFraction := mDay / ADays;
    mDone := APrevious.DoneAt(mFraction);
    Result[mDay] := AScale * (1 - mDone / APrevious.Total);
  end;
end;

class function TAtlasTrackerSprint.PreviousSprints(const ASprints: TArray<TAtlasBoardSprint>;
  const ACurrent: TAtlasBoardSprint; ACount: Integer): TArray<TAtlasBoardSprint>;
var
  mCandidates: TList<TAtlasBoardSprint>;
  mSprint: TAtlasBoardSprint;
  mIndex, mBest: Integer;
begin
  Result := nil;
  if (ACount <= 0) or (ACurrent.Start <= 0) then
  begin
    Exit;
  end;
  mCandidates := TList<TAtlasBoardSprint>.Create;
  try
    // Endet spätestens einen Tag nach dem Start des aktuellen (Sprints grenzen oft auf den Tag aneinander).
    for mSprint in ASprints do
    begin
      if not SameText(mSprint.Id, ACurrent.Id) and (mSprint.Start > 0) and (mSprint.Finish > 0) and
        (mSprint.Start < ACurrent.Start) and (mSprint.Finish <= ACurrent.Start + 1) then
      begin
        mCandidates.Add(mSprint);
      end;
    end;
    // Die jüngsten ACount, ohne instabiles Sortieren: je Runde den spätesten Start (bei Gleichstand die ID).
    while (Length(Result) < ACount) and (mCandidates.Count > 0) do
    begin
      mBest := 0;
      for mIndex := 1 to mCandidates.Count - 1 do
      begin
        if (mCandidates[mIndex].Start > mCandidates[mBest].Start) or
          ((mCandidates[mIndex].Start = mCandidates[mBest].Start) and
          (CompareText(mCandidates[mIndex].Id, mCandidates[mBest].Id) > 0)) then
        begin
          mBest := mIndex;
        end;
      end;
      Result := TArray<TAtlasBoardSprint>.Create(mCandidates[mBest]) + Result;
      mCandidates.Delete(mBest);
    end;
  finally
    mCandidates.Free;
  end;
end;

/// <summary>Erledigt im Team und „meine“ Karten (offen bzw. erledigt) zum Zeitpunkt ANow.</summary>
procedure CountCards(var AView: TAtlasSprintView; const ASnapshot: TAtlasBoardSnapshot; ANow: TDateTime;
  AUsesPoints: Boolean);
var
  mCard: Integer;
  mDone: Boolean;
begin
  for mCard := 0 to High(ASnapshot.Cards) do
  begin
    mDone := TAtlasTrackerSprint.DoneAt(ASnapshot, mCard, ANow) > 0;
    if mDone then
    begin
      AView.TeamDone := AView.TeamDone + TAtlasTrackerSprint.Weight(ASnapshot.Cards[mCard], AUsesPoints);
    end;
    if not AView.MineKnown or not TAtlasTrackerBoard.Mine(ASnapshot.Cards[mCard], ASnapshot.Me) then
    begin
      Continue;
    end;
    if mDone then
    begin
      AView.MineDone := AView.MineDone + [ASnapshot.Cards[mCard].Issue];
    end
    else
    begin
      AView.MineOpen := AView.MineOpen + [ASnapshot.Cards[mCard].Issue];
    end;
  end;
end;

/// <summary>Velocity der früheren Sprints und Vergleich mit dem Vorsprint (dem letzten in APrevious).</summary>
procedure AddPrevious(var AView: TAtlasSprintView; const ASummary: TAtlasSprintSummary;
  const APrevious: TArray<TAtlasSprintSummary>);
var
  mLast: TAtlasSprintSummary;
  mScale: Double;
begin
  for mLast in APrevious do
  begin
    AView.Velocity := AView.Velocity + [mLast.Velocity];
    AView.VelocityNames := AView.VelocityNames + [mLast.Name];
  end;
  if Length(APrevious) = 0 then
  begin
    Exit;
  end;
  mLast := APrevious[High(APrevious)];
  mScale := ASummary.Total;
  if mScale <= 0 then
  begin
    mScale := mLast.Total;
  end;
  AView.Previous := TAtlasTrackerSprint.Normalized(mLast, ASummary.Days, mScale);
  AView.HasPrevious := Length(AView.Previous) > 0;
  AView.PreviousName := mLast.Name;
  if AView.HasPrevious and (ASummary.Days > 0) then
  begin
    AView.PreviousDone := mLast.DoneAt(AView.Today / ASummary.Days);
  end;
end;

class function TAtlasTrackerSprint.View(const ASnapshot: TAtlasBoardSnapshot; const ACalendar: TAtlasSprintCalendar;
  ANow: TDateTime; const APrevious: TArray<TAtlasSprintSummary>): TAtlasSprintView;
var
  mSummary: TAtlasSprintSummary;
  mDay: Integer;
begin
  Result := Default(TAtlasSprintView);
  Result.Fetched := ASnapshot.Fetched;
  Result.Page := ASnapshot.Page;
  Result.Name := ASnapshot.Sprint.Name;
  Result.Start := ASnapshot.Sprint.Start;
  Result.Finish := ASnapshot.Sprint.Finish;
  Result.Known := (ASnapshot.Sprint.Start > 0) and (ASnapshot.Sprint.Finish > ASnapshot.Sprint.Start);
  mSummary := Summarize(ASnapshot, ACalendar, ANow);
  Result.DayCount := mSummary.Days;
  Result.Dates := ACalendar.SprintDays(ASnapshot.Sprint.Start, ASnapshot.Sprint.Finish);
  Result.DaysLeft := ACalendar.DaysLeft(ANow, ASnapshot.Sprint.Start, ASnapshot.Sprint.Finish);
  Result.Today := High(mSummary.Done);
  Result.UsesPoints := mSummary.UsesPoints;
  Result.Total := mSummary.Total;
  // Zahlen „meine …“ als Anzahl; ohne Anmeldename unbekannt.
  Result.MineKnown := Trim(ASnapshot.Me) <> '';
  CountCards(Result, ASnapshot, ANow, mSummary.UsesPoints);
  Result.TeamLeft := Max(0, Result.Total - Result.TeamDone);
  SetLength(Result.Actual, Length(mSummary.Done));
  for mDay := 0 to High(mSummary.Done) do
  begin
    Result.Actual[mDay] := Max(0, mSummary.Total - mSummary.Done[mDay]);
  end;
  if Length(mSummary.Done) > 0 then
  begin
    Result.DoneToday := mSummary.Done[High(mSummary.Done)];
  end;
  Result.Ideal := Ideal(mSummary.Total, mSummary.Days);
  AddPrevious(Result, mSummary, APrevious);
end;

class function TAtlasTrackerSprint.SummaryToJson(const ASummary: TAtlasSprintSummary): string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mValue: Double;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(TAtlasSprintSummary.cVersion));
    mRoot.AddPair('id', ASummary.Id);
    mRoot.AddPair('name', ASummary.Name);
    mRoot.AddPair('start', TAtlasTrackerBoard.TimeText(ASummary.Start));
    mRoot.AddPair('finish', TAtlasTrackerBoard.TimeText(ASummary.Finish));
    mRoot.AddPair('usesPoints', TJSONBool.Create(ASummary.UsesPoints));
    mRoot.AddPair('total', TJSONNumber.Create(ASummary.Total));
    mRoot.AddPair('days', TJSONNumber.Create(ASummary.Days));
    mList := TJSONArray.Create;
    for mValue in ASummary.Done do
    begin
      mList.AddElement(TJSONNumber.Create(mValue));
    end;
    mRoot.AddPair('done', mList);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerSprint.SummaryFromJson(const AJson: string; out ASummary: TAtlasSprintSummary): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot: TJSONObject;
begin
  ASummary := Default(TAtlasSprintSummary);
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if Round(TJsonRead.Float(mRoot, 'version')) <> TAtlasSprintSummary.cVersion then
    begin
      Exit;
    end;
    ASummary.Id := TJsonRead.Text(mRoot, 'id');
    ASummary.Name := TJsonRead.Text(mRoot, 'name');
    ASummary.Start := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mRoot, 'start'));
    ASummary.Finish := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mRoot, 'finish'));
    ASummary.UsesPoints := (mRoot.Values['usesPoints'] is TJSONBool) and
      TJSONBool(mRoot.Values['usesPoints']).AsBoolean;
    ASummary.Total := TJsonRead.Float(mRoot, 'total');
    ASummary.Days := EnsureRange(Round(TJsonRead.Float(mRoot, 'days')), 0, TAtlasTrackerSprint.cMaxDays);
    if mRoot.Values['done'] is TJSONArray then
    begin
      for mItem in TJSONArray(mRoot.Values['done']) do
      begin
        if (mItem is TJSONNumber) and (Length(ASummary.Done) <= ASummary.Days) then
        begin
          ASummary.Done := ASummary.Done + [TJSONNumber(mItem).AsDouble];
        end;
      end;
    end;
    Result := ASummary.Id <> '';
  finally
    mValue.Free;
  end;
end;

class function TAtlasTrackerSprint.SummaryName(const ABoardId, ASprintId: string): string;
begin
  Result := 'sprint-' + ABoardId + '-' + ASprintId;
end;

end.
