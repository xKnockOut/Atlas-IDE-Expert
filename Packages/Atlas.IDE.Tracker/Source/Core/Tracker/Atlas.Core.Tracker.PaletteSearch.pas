unit Atlas.Core.Tracker.PaletteSearch;

// Issues in der Befehlspalette suchen (#1270), ohne VCL und Open Tools API:
// - TAtlasIssuePaletteSearch.Parse erkennt den Auslöser. Text, der mit "#"
//   beginnt ("#Speicherleck", "#42"), oder bei YouTrack mit dem Projektkürzel
//   und "-" ("ATL-12", "ATL-Speicher"), sucht Issues; jede andere Eingabe
//   bleibt bei den Befehlen. Eine reine Kennung ("ATL-12", "#42") wird direkt
//   gelesen (IAtlasTrackerProvider.Lookup), anderer Text gesucht (Search).
//   Ein leeres "#" (bzw. "ATL-") zeigt die zuletzt geöffneten Issues ohne
//   Netzabfrage.
// - TAtlasIssueSearchDebounce: höchstens eine Anfrage je DelayMs; die Zeit
//   kommt von außen (Zeitgeber der IDE bzw. Test mit festen Werten).
// - TAtlasRecentIssues: die zuletzt in „Atlas-Issue“ geöffneten Issues je
//   Tracker (Server und Projekt), höchstens MaxRecent je Tracker; als JSON
//   über TAtlasDataFile gelesen und atomar geschrieben. Nie ein Token, nie
//   eine Adresse außer dem Server des Trackers.
// - Row: Zeile der Palette (Kennung und Titel, Zuständig gedimmt, Zustand als
//   Abzeichen).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>None: Befehle; Recent: zuletzt geöffnete; Key: eine Kennung; Text: Freitextsuche.</summary>
  TAtlasIssueSearchKind = (None, Recent, Key, Text);
{$SCOPEDENUMS OFF}

  TAtlasIssueSearchQuery = record
    Kind: TAtlasIssueSearchKind;
    /// <summary>Key: Kennung wie im Tracker ("ATL-12", "#42").</summary>
    Key: string;
    /// <summary>Text: Suchtext ohne Auslöser ("Speicherleck").</summary>
    Text: string;
    class function None: TAtlasIssueSearchQuery; static;
    /// <summary>Gleiche Anfrage (Art, Kennung, Text ohne Groß-/Kleinschreibung).</summary>
    function SameAs(const AOther: TAtlasIssueSearchQuery): Boolean;
    /// <summary>Text, dessen Zeichen in den Zeilen hervorgehoben werden.</summary>
    function Highlight: string;
  end;

  TAtlasIssuePaletteSearch = class
  public const
    /// <summary>Höchstens so viele Treffer je Suche.</summary>
    MaxResults = 20;
    /// <summary>Wartezeit nach der letzten Eingabe und Mindestabstand zweier Anfragen.</summary>
    DelayMs = 300;
    /// <summary>Zeitgrenze einer Anfrage.</summary>
    TimeoutMs = 5000;
  public
    /// <summary>Auslöser in APattern für den Tracker ATarget; Kind None, wenn die Eingabe den Befehlen gehört
    /// (auch ohne Tracker).</summary>
    class function Parse(const ATarget: TAtlasTrackerTarget; const APattern: string): TAtlasIssueSearchQuery;
      static;
    /// <summary>Zeile der Palette: Id = Kennung, Caption = Kennung und Titel, Path = Zuständig, Badge = Zustand.
    /// </summary>
    class function Row(const AIssue: TAtlasTrackerIssue): TAtlasCommand; static;
    /// <summary>Zeilen zu AIssues in derselben Reihenfolge.</summary>
    class function Rows(const AIssues: TArray<TAtlasTrackerIssue>): TArray<TAtlasCommand>; static;
  end;

  /// <summary>Entprellung der Suche mit Zeit von außen (Millisekunden, monoton).</summary>
  TAtlasIssueSearchDebounce = class
  private
    FDelayMs: Integer;
    FPending: Boolean;
    FText: string;
    FInputAt: UInt64;
    FSentAt: UInt64;
    FSent: Integer;
  public
    constructor Create(ADelayMs: Integer);
    /// <summary>Neue Eingabe: Die Wartezeit beginnt neu.</summary>
    procedure Input(const AText: string; ANowMs: UInt64);
    /// <summary>Nichts mehr fällig (Palette geschlossen, Eingabe ohne Auslöser).</summary>
    procedure Clear;
    /// <summary>Fällig: DelayMs seit der letzten Eingabe und seit der letzten Anfrage. Liefert den Text und merkt
    /// den Zeitpunkt als Anfrage.</summary>
    function Take(ANowMs: UInt64; out AText: string): Boolean;
    /// <summary>Millisekunden, bis Take fällig ist (0 = jetzt); -1, wenn nichts ansteht.</summary>
    function WaitMs(ANowMs: UInt64): Integer;
    function Pending: Boolean;
    /// <summary>Anzahl der Anfragen, die Take freigegeben hat.</summary>
    property Sent: Integer read FSent;
  end;

  /// <summary>Zuletzt in „Atlas-Issue“ geöffnete Issues (#1270).</summary>
  TAtlasRecentIssues = class
  public const
    /// <summary>So viele je Tracker zeigt die Palette.</summary>
    MaxRecent = 10;
    /// <summary>So viele werden über alle Tracker gespeichert.</summary>
    MaxStored = 50;
    Version = 1;
  private type
    TEntry = record
      Tracker: string;
      Issue: TAtlasTrackerIssue;
    end;
  private
    FEntries: TList<TEntry>;
    FKept: string;
    FKind: string;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AIssue zuerst; ein älterer Eintrag derselben Kennung im selben Tracker entfällt.</summary>
    procedure Add(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
    /// <summary>Höchstens MaxRecent des Trackers ATarget, zuletzt geöffnete zuerst.</summary>
    function Items(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
    function Count: Integer;
    procedure Clear;
    function ToJson: string;
    /// <summary>Übernimmt AText; Einträge anderer Form fallen weg. False, wenn AText kein Objekt der Version ist.
    /// </summary>
    function Parse(const AText: string): Boolean;
    /// <summary>Wie TAtlasCommandHistory.LoadFromFile: fehlt oder unbrauchbar = leer; Kept = nicht überschreiben.
    /// </summary>
    function LoadFromFile(const AFileName: string): TAtlasDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Schlüssel des Trackers: Server und Projekt (klein), ohne Abfrage.</summary>
    class function TrackerKey(const ATarget: TAtlasTrackerTarget): string; static;
    property Kind: string read FKind;
  end;

implementation

uses
  System.StrUtils,
  System.JSON;

function IsDigits(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

{ TAtlasIssueSearchQuery }

class function TAtlasIssueSearchQuery.None: TAtlasIssueSearchQuery;
begin
  Result.Kind := TAtlasIssueSearchKind.None;
  Result.Key := '';
  Result.Text := '';
end;

function TAtlasIssueSearchQuery.SameAs(const AOther: TAtlasIssueSearchQuery): Boolean;
begin
  Result := (Kind = AOther.Kind) and SameText(Key, AOther.Key) and SameText(Text, AOther.Text);
end;

function TAtlasIssueSearchQuery.Highlight: string;
begin
  case Kind of
    TAtlasIssueSearchKind.Key:
      Result := Key;
    TAtlasIssueSearchKind.Text:
      Result := Text;
  else
    Result := '';
  end;
end;

{ TAtlasIssuePaletteSearch }

function SearchQuery(AKind: TAtlasIssueSearchKind; const AKey, AText: string): TAtlasIssueSearchQuery;
begin
  Result.Kind := AKind;
  Result.Key := AKey;
  Result.Text := AText;
end;

/// <summary>Nummer ANumber als Kennung: "#42" bei GitHub, "ATL-42" bei YouTrack mit Projekt; sonst ''.</summary>
function NumberKey(const ATarget: TAtlasTrackerTarget; const ANumber: string): string;
begin
  Result := '';
  if not IsDigits(ANumber) or (StrToIntDef(ANumber, 0) <= 0) then
  begin
    Exit;
  end;
  if SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) then
  begin
    Result := '#' + IntToStr(StrToIntDef(ANumber, 0));
  end
  else if ATarget.Project <> '' then
  begin
    Result := UpperCase(ATarget.Project) + '-' + IntToStr(StrToIntDef(ANumber, 0));
  end;
end;

/// <summary>ARest ist eine Kennung des YouTrack-Projekts ("ATL-12").</summary>
function IsProjectKey(const ATarget: TAtlasTrackerTarget; const ARest: string): Boolean;
begin
  Result := not SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) and (ATarget.Project <> '') and
    StartsText(ATarget.Project + '-', ARest) and IsDigits(Copy(ARest, Length(ATarget.Project) + 2, MaxInt));
end;

/// <summary>Suche nach "#": leer die letzten Issues, "#42" die Nummer, "#ATL-12" die Kennung, sonst Text.</summary>
function ParseHash(const ATarget: TAtlasTrackerTarget; const ARest: string): TAtlasIssueSearchQuery;
var
  mKey: string;
begin
  mKey := NumberKey(ATarget, ARest);
  if ARest = '' then
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Recent, '', '');
  end
  else if mKey <> '' then
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Key, mKey, '');
  end
  else if IsProjectKey(ATarget, ARest) then
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Key, UpperCase(ARest), '');
  end
  else
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Text, '', ARest);
  end;
end;

/// <summary>Suche mit Projektkürzel und "-" (nur YouTrack; GitHub: "owner/repo").</summary>
function ParseProjectPrefix(const ATarget: TAtlasTrackerTarget; const APattern: string): TAtlasIssueSearchQuery;
var
  mPrefix, mRest: string;
begin
  Result := TAtlasIssueSearchQuery.None;
  mPrefix := ATarget.Project + '-';
  if SameText(ATarget.Provider, TAtlasTrackerTarget.GitHub) or (ATarget.Project = '') or
    (Pos(' ', ATarget.Project) > 0) or not StartsText(mPrefix, APattern) then
  begin
    Exit;
  end;
  mRest := Trim(Copy(APattern, Length(mPrefix) + 1, MaxInt));
  if mRest = '' then
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Recent, '', '');
  end
  else if NumberKey(ATarget, mRest) <> '' then
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Key, NumberKey(ATarget, mRest), '');
  end
  else
  begin
    Result := SearchQuery(TAtlasIssueSearchKind.Text, '', mRest);
  end;
end;

class function TAtlasIssuePaletteSearch.Parse(const ATarget: TAtlasTrackerTarget;
  const APattern: string): TAtlasIssueSearchQuery;
var
  mPattern: string;
begin
  mPattern := TrimLeft(APattern);
  if (mPattern = '') or (ATarget.Provider = '') then
  begin
    Result := TAtlasIssueSearchQuery.None;
  end
  else if mPattern[1] = '#' then
  begin
    Result := ParseHash(ATarget, Trim(Copy(mPattern, 2, MaxInt)));
  end
  else
  begin
    Result := ParseProjectPrefix(ATarget, mPattern);
  end;
end;

class function TAtlasIssuePaletteSearch.Row(const AIssue: TAtlasTrackerIssue): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AIssue.Key;
  Result.Caption := Trim(AIssue.Key + '  ' + AIssue.Title);
  Result.Path := AIssue.Assignee;
  Result.Badge := AIssue.State;
  Result.Description := AIssue.Title;
end;

class function TAtlasIssuePaletteSearch.Rows(const AIssues: TArray<TAtlasTrackerIssue>): TArray<TAtlasCommand>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AIssues));
  for mIndex := 0 to High(AIssues) do
  begin
    Result[mIndex] := Row(AIssues[mIndex]);
  end;
end;

{ TAtlasIssueSearchDebounce }

constructor TAtlasIssueSearchDebounce.Create(ADelayMs: Integer);
begin
  inherited Create;
  FDelayMs := ADelayMs;
  if FDelayMs < 0 then
  begin
    FDelayMs := 0;
  end;
end;

procedure TAtlasIssueSearchDebounce.Input(const AText: string; ANowMs: UInt64);
begin
  FPending := True;
  FText := AText;
  FInputAt := ANowMs;
end;

procedure TAtlasIssueSearchDebounce.Clear;
begin
  FPending := False;
  FText := '';
end;

function TAtlasIssueSearchDebounce.Pending: Boolean;
begin
  Result := FPending;
end;

function TAtlasIssueSearchDebounce.WaitMs(ANowMs: UInt64): Integer;
var
  mDue: UInt64;
begin
  Result := -1;
  if not FPending then
  begin
    Exit;
  end;
  mDue := FInputAt + UInt64(FDelayMs);
  // Auch nach einer Tipppause nicht öfter als einmal je DelayMs.
  if (FSent > 0) and (FSentAt + UInt64(FDelayMs) > mDue) then
  begin
    mDue := FSentAt + UInt64(FDelayMs);
  end;
  if mDue <= ANowMs then
  begin
    Result := 0;
  end
  else
  begin
    Result := Integer(mDue - ANowMs);
  end;
end;

function TAtlasIssueSearchDebounce.Take(ANowMs: UInt64; out AText: string): Boolean;
begin
  AText := '';
  Result := WaitMs(ANowMs) = 0;
  if not Result then
  begin
    Exit;
  end;
  AText := FText;
  FPending := False;
  FSentAt := ANowMs;
  Inc(FSent);
end;

{ TAtlasRecentIssues }

constructor TAtlasRecentIssues.Create;
begin
  inherited Create;
  FEntries := TList<TEntry>.Create;
  FKind := 'Zuletzt geöffnete Issues';
end;

destructor TAtlasRecentIssues.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasRecentIssues.TrackerKey(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := LowerCase(ATarget.Server + '|' + ATarget.Project);
end;

procedure TAtlasRecentIssues.Add(const ATarget: TAtlasTrackerTarget; const AIssue: TAtlasTrackerIssue);
var
  mEntry: TEntry;
  mIndex: Integer;
begin
  if (Trim(AIssue.Key) = '') or (ATarget.Server = '') then
  begin
    Exit;
  end;
  mEntry.Tracker := TrackerKey(ATarget);
  mEntry.Issue := AIssue;
  mEntry.Issue.Key := Trim(AIssue.Key);
  // Nur die Felder der Zeile; Labels und Pull Request gehören nicht in den Verlauf.
  mEntry.Issue.Labels := nil;
  mEntry.Issue.PullRequest := Default(TAtlasTrackerPullRequest);
  for mIndex := FEntries.Count - 1 downto 0 do
  begin
    if (FEntries[mIndex].Tracker = mEntry.Tracker) and SameText(FEntries[mIndex].Issue.Key, mEntry.Issue.Key) then
    begin
      FEntries.Delete(mIndex);
    end;
  end;
  FEntries.Insert(0, mEntry);
  while FEntries.Count > MaxStored do
  begin
    FEntries.Delete(FEntries.Count - 1);
  end;
end;

function TAtlasRecentIssues.Items(const ATarget: TAtlasTrackerTarget): TArray<TAtlasTrackerIssue>;
var
  mTracker: string;
  mEntry: TEntry;
begin
  Result := nil;
  mTracker := TrackerKey(ATarget);
  for mEntry in FEntries do
  begin
    if Length(Result) >= MaxRecent then
    begin
      Break;
    end;
    if mEntry.Tracker = mTracker then
    begin
      Result := Result + [mEntry.Issue];
    end;
  end;
end;

function TAtlasRecentIssues.Count: Integer;
begin
  Result := FEntries.Count;
end;

procedure TAtlasRecentIssues.Clear;
begin
  FEntries.Clear;
end;

function TAtlasRecentIssues.ToJson: string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mEntry: TEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(Version));
    mList := TJSONArray.Create;
    mRoot.AddPair('issues', mList);
    for mEntry in FEntries do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('tracker', mEntry.Tracker);
      mItem.AddPair('key', mEntry.Issue.Key);
      mItem.AddPair('number', TJSONNumber.Create(mEntry.Issue.Number));
      mItem.AddPair('title', mEntry.Issue.Title);
      mItem.AddPair('state', mEntry.Issue.State);
      mItem.AddPair('assignee', mEntry.Issue.Assignee);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasRecentIssues.Parse(const AText: string): Boolean;
var
  mRoot, mList, mItem: TJSONValue;
  mObject: TJSONObject;
  mEntry: TEntry;
  mVersion, mNumber: Integer;
begin
  FEntries.Clear;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<Integer>('version', mVersion) and
      (mVersion = Version);
    if not Result then
    begin
      Exit;
    end;
    mList := TJSONObject(mRoot).Values['issues'];
    if not (mList is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mList) do
    begin
      if FEntries.Count >= MaxStored then
      begin
        Break;
      end;
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mObject := TJSONObject(mItem);
      mEntry.Tracker := '';
      mEntry.Issue := TAtlasTrackerIssue.Empty;
      if not mObject.TryGetValue<string>('tracker', mEntry.Tracker) or
        not mObject.TryGetValue<string>('key', mEntry.Issue.Key) or (Trim(mEntry.Issue.Key) = '') or
        (mEntry.Tracker = '') then
      begin
        Continue;
      end;
      if mObject.TryGetValue<Integer>('number', mNumber) and (mNumber > 0) then
      begin
        mEntry.Issue.Number := mNumber;
      end;
      mObject.TryGetValue<string>('title', mEntry.Issue.Title);
      mObject.TryGetValue<string>('state', mEntry.Issue.State);
      mObject.TryGetValue<string>('assignee', mEntry.Issue.Assignee);
      mEntry.Issue.Title := Copy(mEntry.Issue.Title, 1, TAtlasTrackerIssue.MaxTitle);
      FEntries.Add(mEntry);
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasRecentIssues.LoadFromFile(const AFileName: string): TAtlasDataLoad;
begin
  FEntries.Clear;
  FKept := '';
  Result := TAtlasDataFile.Load(AFileName, FKind,
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TAtlasDataFile.Writable(Result) then
  begin
    FKept := AFileName;
  end;
  if Result <> TAtlasDataLoad.Loaded then
  begin
    FEntries.Clear;
  end;
end;

function TAtlasRecentIssues.SaveToFile(const AFileName: string): Boolean;
begin
  Result := not SameFileName(AFileName, FKept);
  if Result then
  begin
    TAtlasDataFile.Write(AFileName, ToJson);
  end;
end;

end.
