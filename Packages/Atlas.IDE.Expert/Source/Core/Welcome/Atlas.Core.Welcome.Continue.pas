unit Atlas.Core.Welcome.Continue;

// Bereich „Weiterarbeiten“ der Willkommensseite (#755), Reiter „Zuletzt“,
// Teil ohne VCL und Open Tools API: der gespeicherte Arbeitsstand je Projekt,
// die Liste der Arbeitsstände, der Plan für „Fortsetzen“ und die eingehenden
// Commits („Neu seit deinem letzten Öffnen“).
// - Arbeitsstand: Reiter in ihrer Reihenfolge, aktiver Reiter, letzte
//   Änderungsstelle je Datei (sonst die Cursorstelle) mit der Methode dort
//   (aus der Gliederung, Atlas.Core.Editor.MethodToggle), Zeitpunkt des
//   Schließens, HEAD-Commit sowie verfolgter Branch und dessen Commit. Die
//   IDE schreibt ihn beim Schließen eines Projekts bzw. einer Projektgruppe
//   und beim Beenden in den Abschnitt "continue" der Projekt-Zusammenfassung
//   (#592):
//     "continue": {"at": "…", "active": 1, "vcs": "git", "head": "<hash>",
//                  "upstream": "origin/main", "upstreamRevision": "<hash>",
//                  "tabs": [{"file": "C:\\…\\Kunde.pas", "line": 42,
//                            "column": 5, "method": "TKunde.Laden",
//                            "changed": true, "changedAt": "…"}],
//                  "edited": ["C:\\…\\Alt.pas"]}
//   "line" und "column" zählen ab 1; "changed" steht nur, wenn die Stelle eine
//   Änderung ist (sonst Cursor); "edited" sind in der Sitzung geänderte
//   Dateien, die beim Schließen nicht mehr offen waren. Unbekannte Felder im
//   Abschnitt gehen beim Schreiben verloren, die übrige Datei bleibt (Format 1).
// - Liste: Arbeitsstände der zuletzt geöffneten Projekte und Projektgruppen,
//   neueste zuerst, höchstens welcomePage.continue.count (1–20, Vorgabe 5).
// - Fortsetzen: Reiter in ihrer Reihenfolge, fehlende Dateien übersprungen
//   (Hinweis), zuletzt aktiver Reiter am Ende aktiv, Cursor an der letzten
//   Änderung.
// - Eingehende Commits (welcomePage.continue.incoming): Commits auf dem
//   verfolgten Branch (#571), die weder im HEAD noch im verfolgten Branch beim
//   Schließen lagen und eine Datei des Arbeitsstands (offen oder geändert)
//   betreffen. Grundlage ist der lokale Stand der Remote-Branches; fetch nur
//   mit welcomePage.continue.fetch (5 s, ohne Rückfrage nach Zugangsdaten).
//   Ohne Arbeitskopie oder ohne verfolgten Branch (auch SVN) entfällt der
//   Abschnitt ohne Fehler.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zeitangabe: „gerade eben“, „vor 5 Min.“, „vor 2 Std.“, „gestern 18:40“, sonst Datum und Uhrzeit.
  /// </summary>
  TAtlasContinueAge = (JustNow, Minutes, Hours, Yesterday, Date);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Reiter des Arbeitsstands.</summary>
  TAtlasWorkTab = record
    /// <summary>Vollständiger Pfad.</summary>
    FileName: string;
    /// <summary>Letzte Änderung (Changed) bzw. Cursor; ab 1, 0 = unbekannt.</summary>
    Line: Integer;
    Column: Integer;
    /// <summary>Methode an dieser Stelle, z. B. TKunde.Laden; '' außerhalb einer Methode.</summary>
    Method: string;
    /// <summary>Line und Column sind eine Änderung.</summary>
    Changed: Boolean;
    /// <summary>Zeitpunkt der Änderung (UTC); 0 = unbekannt.</summary>
    ChangedAt: TDateTime;
    class function Create(const AFileName: string; ALine, AColumn: Integer): TAtlasWorkTab; static;
  end;

  /// <summary>Gespeicherter Arbeitsstand eines Projekts (Abschnitt "continue").</summary>
  TAtlasWorkState = record
    Known: Boolean;
    /// <summary>Zeitpunkt des Schließens (UTC).</summary>
    At: TDateTime;
    /// <summary>Reiter in ihrer Reihenfolge.</summary>
    Tabs: TArray<TAtlasWorkTab>;
    /// <summary>Zuletzt aktiver Reiter (Index in Tabs); -1 = unbekannt.</summary>
    Active: Integer;
    /// <summary>In der Sitzung geänderte Dateien, die beim Schließen nicht mehr offen waren.</summary>
    Edited: TArray<string>;
    /// <summary>"git", "svn", "none" oder '' (nicht abgefragt).</summary>
    VcsKind: string;
    /// <summary>HEAD-Commit beim Schließen; '' unbekannt.</summary>
    Head: string;
    /// <summary>Verfolgter Branch beim Schließen, z. B. "origin/main"; '' ohne.</summary>
    Upstream: string;
    /// <summary>Commit des verfolgten Branchs beim Schließen; '' unbekannt.</summary>
    UpstreamRevision: string;
    class function Empty: TAtlasWorkState; static;
    function TabCount: Integer;
    function IndexOf(const AFileName: string): Integer;
    /// <summary>Reiter mit der jüngsten Änderung, sonst der aktive, sonst der erste; -1 ohne Reiter.</summary>
    function LastIndex: Integer;
    /// <summary>Dateien des Arbeitsstands (Reiter und geänderte), jede einmal.</summary>
    function Files: TArray<string>;
  end;

  TAtlasContinueEntry = record
    /// <summary>Projekt oder Projektgruppe (vollständiger Pfad).</summary>
    Project: string;
    State: TAtlasWorkState;
    /// <summary>Dateiname ohne Endung.</summary>
    function Name: string;
    function IsGroup: Boolean;
    /// <summary>Zuletzt bearbeitete Datei (siehe TAtlasWorkState.LastIndex); leer ohne Reiter.</summary>
    function LastTab: TAtlasWorkTab;
  end;

  TAtlasContinueEntries = TArray<TAtlasContinueEntry>;

  /// <summary>Was „Fortsetzen“ öffnet.</summary>
  TAtlasContinuePlan = record
    Project: string;
    /// <summary>Vorhandene Dateien in der Reihenfolge der Reiter.</summary>
    Open: TArray<TAtlasWorkTab>;
    /// <summary>Übersprungene Dateien (gibt es nicht mehr).</summary>
    Missing: TArray<string>;
    /// <summary>Am Ende aktiver Reiter (Index in Open); -1 ohne.</summary>
    Active: Integer;
  end;

  /// <summary>Eingehender Commit mit den betroffenen Dateien des Arbeitsstands.</summary>
  TAtlasContinueCommit = record
    Commit: TAtlasVcsIncomingCommit;
    /// <summary>Dateien des Arbeitsstands, die der Commit ändert.</summary>
    Files: TArray<string>;
  end;

  /// <summary>Abschnitt „Neu seit deinem letzten Öffnen“ für einen Arbeitsstand.</summary>
  TAtlasContinueIncoming = record
    /// <summary>Abschnitt zeigen: Arbeitskopie mit verfolgtem Branch, Abfrage gelungen.</summary>
    Available: Boolean;
    /// <summary>Projekt, zu dem die Abfrage gehört.</summary>
    Project: string;
    /// <summary>Verfolgter Branch, z. B. "origin/main".</summary>
    Upstream: string;
    /// <summary>Neueste zuerst.</summary>
    Commits: TArray<TAtlasContinueCommit>;
    /// <summary>Es gibt mehr passende Commits als aufgeführt.</summary>
    More: Boolean;
    /// <summary>fetch war gewünscht und ist misslungen (Stand ohne Abruf).</summary>
    FetchFailed: Boolean;
    /// <summary>fetch ist misslungen, weil die Anmeldung am Server fehlt (#1287); dann auch FetchFailed.</summary>
    LoginNeeded: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
  end;

  TAtlasContinueFileExists = reference to function(const AFileName: string): Boolean;

  TAtlasWelcomeContinue = class
  public const
    /// <summary>Abschnitt in der Projekt-Zusammenfassung.</summary>
    SectionName = 'continue';
    DefaultCount = 5;
    MinCount = 1;
    MaxCount = 20;
    /// <summary>Höchstens so viele Reiter je Arbeitsstand.</summary>
    MaxTabs = 200;
    /// <summary>Höchstens so viele eingehende Commits werden geprüft bzw. gezeigt.</summary>
    MaxIncomingScan = 200;
    MaxIncomingShown = 8;
    /// <summary>Zeitlimit je Aufruf der Versionsverwaltung.</summary>
    CallTimeoutMs = 2000;
    /// <summary>Zeitlimit für fetch.</summary>
    FetchTimeoutMs = 5000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite erneut ab.</summary>
    RefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet (fetch plus vier Aufrufe plus Reserve).</summary>
    QueryLimitMs = 16000;
  public
    /// <summary>Abschnitt "continue" aus der Zusammenfassung; False ohne.</summary>
    class function Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasWorkState): Boolean; static;
    /// <summary>Abschnitt "continue" in die Zusammenfassung (über Raw; TAtlasProjectSummaries.ToJson behält ihn).
    /// </summary>
    class procedure Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasWorkState); static;
    class function ToJson(const AState: TAtlasWorkState): string; static;
    class function FromJson(const AJson: string; out AState: TAtlasWorkState): Boolean; static;
    /// <summary>Arbeitsstände zu ARecent (zuletzt geöffnete Projekte der IDE), jedes Projekt einmal, nur mit
    /// mindestens einem Reiter, neueste zuerst, höchstens ACount (auf MinCount..MaxCount begrenzt).</summary>
    class function Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
      ACount: Integer): TAtlasContinueEntries; static;
    /// <summary>Arbeitsstand beim Schließen: AOpen sind die offenen Reiter in ihrer Reihenfolge mit der
    /// Cursorstelle, AActive die aktive Datei, AChanges die Änderungen dieser Sitzung (letzte Stelle je Datei).
    /// Reiter ohne Änderung in dieser Sitzung behalten eine gespeicherte Änderung aus AOld.</summary>
    class function Build(const AOpen: TArray<TAtlasWorkTab>; const AActive: string;
      const AChanges: TArray<TAtlasWorkTab>; const AOld: TAtlasWorkState; ANowUtc: TDateTime): TAtlasWorkState;
      static;
    /// <summary>Methode um ALine (ab 1) in AText (Pascal); '' außerhalb jeder Methode.</summary>
    class function MethodAt(const AText: string; ALine: Integer): string; static;
    /// <summary>Dateien in der Reihenfolge der Reiterbeschriftungen ACaptions (Dateinamen ohne Pfad, mit oder ohne
    /// Endung, ggf. mit Markierung wie „*“); nicht zuordenbare bleiben in ihrer Reihenfolge dahinter.</summary>
    class function OrderByTabs(const AFiles, ACaptions: TArray<string>): TArray<string>; static;
    /// <summary>Plan für „Fortsetzen“; AExists prüft, ob es eine Datei gibt (nil = alle vorhanden).</summary>
    class function Plan(const AProject: string; const AState: TAtlasWorkState;
      const AExists: TAtlasContinueFileExists): TAtlasContinuePlan; static;
    /// <summary>Zeitangabe für AAtLocal gegenüber ANowLocal (beide Ortszeit); AValue: Minuten bzw. Stunden.</summary>
    class function Age(AAtLocal, ANowLocal: TDateTime; out AValue: Integer): TAtlasContinueAge; static;
    /// <summary>Commits, die eine Datei aus AFiles ändern, in ihrer Reihenfolge, höchstens AMax; AMore, wenn es
    /// mehr gibt.</summary>
    class function Select(const ACommits: TArray<TAtlasVcsIncomingCommit>; const AFiles: TArray<string>;
      AMax: Integer; out AMore: Boolean): TArray<TAtlasContinueCommit>; static;
    /// <summary>Beim Schließen (startet Prozesse: nur im Hintergrund): Art, HEAD, verfolgter Branch und dessen
    /// Commit in AState. False bei Fehler; ohne Arbeitskopie VcsKind = "none" und True.</summary>
    class function ProbeHead(const AVcs: IAtlasVersionControl; var AState: TAtlasWorkState): Boolean; static;
    /// <summary>Eingehende Commits zu AState (startet Prozesse: nur im Hintergrund). AFetchVcs (nil = kein fetch)
    /// ruft vorher die Remote-Branches ab. True mit AResult, wenn das Ergebnis gilt (auch „kein Abschnitt“ ohne
    /// Arbeitskopie oder verfolgten Branch); False bei Fehler oder Zeitüberschreitung.</summary>
    class function ProbeIncoming(const AVcs, AFetchVcs: IAtlasVersionControl; const AProject: string;
      const AState: TAtlasWorkState; ANowUtc: TDateTime; out AResult: TAtlasContinueIncoming): Boolean; overload;
      static;
    /// <summary>Wie oben; ohne verfolgten Branch vergleicht es gegen den Hauptbranch AMainBranch des Projekts
    /// (#1286; zuerst origin/AMainBranch, sonst AMainBranch). AMainBranch '' = kein Abschnitt wie bisher.</summary>
    class function ProbeIncoming(const AVcs, AFetchVcs: IAtlasVersionControl; const AProject, AMainBranch: string;
      const AState: TAtlasWorkState; ANowUtc: TDateTime; out AResult: TAtlasContinueIncoming): Boolean; overload;
      static;
    /// <summary>Gleiche Datei: Groß-/Kleinschreibung (ASCII), „/“ und „\“ sowie Leerraum am Rand egal.</summary>
    class function SameFile(const A, B: string): Boolean; static;
    /// <summary>Dateiname ohne Pfad (auch mit „/“).</summary>
    class function FileNameOf(const APath: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.DateUtils,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Bookmarks.Store;

{ TAtlasWorkTab }

class function TAtlasWorkTab.Create(const AFileName: string; ALine, AColumn: Integer): TAtlasWorkTab;
begin
  Result := Default(TAtlasWorkTab);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
end;

{ TAtlasWorkState }

class function TAtlasWorkState.Empty: TAtlasWorkState;
begin
  Result := Default(TAtlasWorkState);
  Result.Active := -1;
end;

function TAtlasWorkState.TabCount: Integer;
begin
  Result := Length(Tabs);
end;

function TAtlasWorkState.IndexOf(const AFileName: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Tabs) do
    if TAtlasWelcomeContinue.SameFile(Tabs[Index].FileName, AFileName) then
      Exit(Index);
end;

function TAtlasWorkState.LastIndex: Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Tabs) do
    if Tabs[Index].Changed and (Tabs[Index].ChangedAt > 0) and
      ((Result < 0) or (Tabs[Index].ChangedAt > Tabs[Result].ChangedAt)) then
      Result := Index;
  if Result >= 0 then
    Exit;
  if (Active >= 0) and (Active <= High(Tabs)) then
    Exit(Active);
  if Length(Tabs) > 0 then
    Result := 0;
end;

function TAtlasWorkState.Files: TArray<string>;

  procedure Add(const AFileName: string);
  var
    Known: string;
  begin
    if Trim(AFileName) = '' then
      Exit;
    for Known in Result do
      if TAtlasWelcomeContinue.SameFile(Known, AFileName) then
        Exit;
    Result := Result + [AFileName];
  end;

var
  Tab: TAtlasWorkTab;
  FileName: string;
begin
  Result := nil;
  for Tab in Tabs do
    Add(Tab.FileName);
  for FileName in Edited do
    Add(FileName);
end;

{ TAtlasContinueEntry }

function TAtlasContinueEntry.Name: string;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(Project);
  Result := Summary.Name;
end;

function TAtlasContinueEntry.IsGroup: Boolean;
begin
  Result := SameText(ExtractFileExt(Project), '.groupproj');
end;

function TAtlasContinueEntry.LastTab: TAtlasWorkTab;
var
  Index: Integer;
begin
  Result := Default(TAtlasWorkTab);
  Index := State.LastIndex;
  if Index >= 0 then
    Result := State.Tabs[Index];
end;

{ JSON }

function TextIn(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function NumberIn(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt;
end;

function FlagIn(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := SameText(Value.Value, 'true');
end;

function ObjectIn(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    Result := TJSONObject(Value);
end;

function ParseObject(const AJson: string): TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  try
    Result := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Result := nil;
  end;
end;

function SectionJson(const AState: TAtlasWorkState): TJSONObject;
var
  Tabs, Edited: TJSONArray;
  Entry: TJSONObject;
  Tab: TAtlasWorkTab;
  FileName: string;
begin
  Result := TJSONObject.Create;
  if AState.At > 0 then
    Result.AddPair('at', TAtlasProjectSummaries.TimeText(AState.At));
  Result.AddPair('active', TJSONNumber.Create(AState.Active));
  if AState.VcsKind <> '' then
    Result.AddPair('vcs', AState.VcsKind);
  if AState.Head <> '' then
    Result.AddPair('head', AState.Head);
  if AState.Upstream <> '' then
    Result.AddPair('upstream', AState.Upstream);
  if AState.UpstreamRevision <> '' then
    Result.AddPair('upstreamRevision', AState.UpstreamRevision);
  Tabs := TJSONArray.Create;
  Result.AddPair('tabs', Tabs);
  for Tab in AState.Tabs do
  begin
    Entry := TJSONObject.Create;
    Tabs.AddElement(Entry);
    Entry.AddPair('file', Tab.FileName);
    Entry.AddPair('line', TJSONNumber.Create(Tab.Line));
    Entry.AddPair('column', TJSONNumber.Create(Tab.Column));
    if Tab.Method <> '' then
      Entry.AddPair('method', Tab.Method);
    if Tab.Changed then
      Entry.AddPair('changed', TJSONBool.Create(True));
    if Tab.ChangedAt > 0 then
      Entry.AddPair('changedAt', TAtlasProjectSummaries.TimeText(Tab.ChangedAt));
  end;
  if Length(AState.Edited) > 0 then
  begin
    Edited := TJSONArray.Create;
    Result.AddPair('edited', Edited);
    for FileName in AState.Edited do
      Edited.Add(FileName);
  end;
end;

function StateOf(ASection: TJSONObject; out AState: TAtlasWorkState): Boolean;
var
  Tabs, Edited, Element: TJSONValue;
  Entry: TJSONObject;
  Tab: TAtlasWorkTab;
  Index: Integer;
begin
  AState := TAtlasWorkState.Empty;
  Result := ASection <> nil;
  if not Result then
    Exit;
  AState.Known := True;
  AState.At := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'at'));
  AState.VcsKind := LowerCase(TextIn(ASection, 'vcs'));
  AState.Head := TextIn(ASection, 'head');
  AState.Upstream := TextIn(ASection, 'upstream');
  AState.UpstreamRevision := TextIn(ASection, 'upstreamRevision');
  Tabs := ASection.GetValue('tabs');
  if Tabs is TJSONArray then
    for Index := 0 to TJSONArray(Tabs).Count - 1 do
    begin
      Element := TJSONArray(Tabs).Items[Index];
      if not (Element is TJSONObject) then
        Continue;
      Entry := TJSONObject(Element);
      Tab := TAtlasWorkTab.Create(TextIn(Entry, 'file'), NumberIn(Entry, 'line', 0), NumberIn(Entry, 'column', 0));
      if Trim(Tab.FileName) = '' then
        Continue;
      Tab.Method := TextIn(Entry, 'method');
      Tab.Changed := FlagIn(Entry, 'changed');
      Tab.ChangedAt := TAtlasProjectSummaries.TimeOf(TextIn(Entry, 'changedAt'));
      if Tab.Line < 0 then
        Tab.Line := 0;
      if Tab.Column < 0 then
        Tab.Column := 0;
      AState.Tabs := AState.Tabs + [Tab];
    end;
  AState.Active := NumberIn(ASection, 'active', -1);
  if (AState.Active < 0) or (AState.Active > High(AState.Tabs)) then
    AState.Active := -1;
  Edited := ASection.GetValue('edited');
  if Edited is TJSONArray then
    for Index := 0 to TJSONArray(Edited).Count - 1 do
    begin
      Element := TJSONArray(Edited).Items[Index];
      // TJSONNumber erbt von TJSONString: Zahlen sind keine Dateien.
      if (Element is TJSONString) and not (Element is TJSONNumber) and (Trim(TJSONString(Element).Value) <> '') then
        AState.Edited := AState.Edited + [TJSONString(Element).Value];
    end;
end;

{ TAtlasWelcomeContinue }

class function TAtlasWelcomeContinue.SameFile(const A, B: string): Boolean;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(A) = TAtlasProjectSummaries.NormalizedPath(B);
end;

class function TAtlasWelcomeContinue.FileNameOf(const APath: string): string;
var
  Index: Integer;
begin
  // Ohne ExtractFileName: Die Pfade haben „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := Trim(APath);
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
      Exit(Copy(Result, Index + 1, MaxInt));
end;

class function TAtlasWelcomeContinue.ToJson(const AState: TAtlasWorkState): string;
var
  Section: TJSONObject;
begin
  Section := SectionJson(AState);
  try
    Result := Section.ToJSON;
  finally
    Section.Free;
  end;
end;

class function TAtlasWelcomeContinue.FromJson(const AJson: string; out AState: TAtlasWorkState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasWorkState.Empty;
  Value := ParseObject(AJson);
  try
    Result := (Value is TJSONObject) and StateOf(TJSONObject(Value), AState);
  finally
    Value.Free;
  end;
end;

class function TAtlasWelcomeContinue.Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasWorkState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasWorkState.Empty;
  Value := ParseObject(ASummary.Raw);
  try
    Result := (Value is TJSONObject) and StateOf(ObjectIn(TJSONObject(Value), SectionName), AState);
  finally
    Value.Free;
  end;
end;

class procedure TAtlasWelcomeContinue.Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasWorkState);
var
  Value: TJSONValue;
  Original, Root: TJSONObject;
  Index: Integer;
  Pair: TJSONPair;
begin
  Value := ParseObject(ASummary.Raw);
  Root := TJSONObject.Create;
  try
    // Alles außer dem Abschnitt übernehmen; ohne Datei schreibt TAtlasProjectSummaries.ToJson die übrigen
    // Felder aus dem Datensatz.
    if Value is TJSONObject then
    begin
      Original := TJSONObject(Value);
      for Index := 0 to Original.Count - 1 do
      begin
        Pair := Original.Pairs[Index];
        if Pair.JsonString.Value <> SectionName then
          Root.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
      end;
    end;
    Root.AddPair(SectionName, SectionJson(AState));
    ASummary.Raw := Root.ToJSON;
  finally
    Root.Free;
    Value.Free;
  end;
end;

class function TAtlasWelcomeContinue.Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
  ACount: Integer): TAtlasContinueEntries;
var
  Limit, Index, Position: Integer;
  Project, Key, Known: string;
  Seen: TArray<string>;
  Duplicate: Boolean;
  Summary: TAtlasProjectSummary;
  Entry: TAtlasContinueEntry;
  Found: TAtlasContinueEntries;
begin
  Result := nil;
  Found := nil;
  Seen := nil;
  Limit := ACount;
  if Limit < MinCount then
    Limit := MinCount;
  if Limit > MaxCount then
    Limit := MaxCount;
  if not Assigned(ALoad) then
    Exit;
  for Project in ARecent do
  begin
    if Trim(Project) = '' then
      Continue;
    Key := TAtlasProjectSummaries.NormalizedPath(Project);
    Duplicate := False;
    for Known in Seen do
      if Known = Key then
        Duplicate := True;
    if Duplicate then
      Continue;
    Seen := Seen + [Key];
    if not ALoad(Trim(Project), Summary) then
      Continue;
    Entry := Default(TAtlasContinueEntry);
    Entry.Project := Trim(Project);
    if not Read(Summary, Entry.State) or (Entry.State.TabCount = 0) then
      Continue;
    // Neueste zuerst; bei Gleichstand bleibt die Reihenfolge der IDE (stabil einsortieren).
    Position := Length(Found);
    for Index := 0 to High(Found) do
      if Entry.State.At > Found[Index].State.At then
      begin
        Position := Index;
        Break;
      end;
    Insert(Entry, Found, Position);
  end;
  for Index := 0 to High(Found) do
  begin
    if Length(Result) >= Limit then
      Break;
    Result := Result + [Found[Index]];
  end;
end;

class function TAtlasWelcomeContinue.Build(const AOpen: TArray<TAtlasWorkTab>; const AActive: string;
  const AChanges: TArray<TAtlasWorkTab>; const AOld: TAtlasWorkState; ANowUtc: TDateTime): TAtlasWorkState;
var
  Tab, Change, Old: TAtlasWorkTab;
  Index, Position: Integer;
  Found, Open: Boolean;
  FileName: string;
begin
  Result := TAtlasWorkState.Empty;
  Result.Known := True;
  Result.At := ANowUtc;
  for Tab in AOpen do
  begin
    if Trim(Tab.FileName) = '' then
      Continue;
    if Length(Result.Tabs) >= MaxTabs then
      Break;
    // Jede Datei einmal (dieselbe Datei in zwei Editorfenstern).
    if Result.IndexOf(Tab.FileName) >= 0 then
      Continue;
    Found := False;
    Change := Default(TAtlasWorkTab);
    for Index := High(AChanges) downto 0 do
      if SameFile(AChanges[Index].FileName, Tab.FileName) then
      begin
        Change := AChanges[Index];
        Found := True;
        Break;
      end;
    if Found then
    begin
      Change.FileName := Tab.FileName;
      Change.Changed := True;
      if Change.ChangedAt <= 0 then
        Change.ChangedAt := ANowUtc;
      Result.Tabs := Result.Tabs + [Change];
      Continue;
    end;
    // Ohne Änderung in dieser Sitzung: eine gespeicherte Änderung bleibt die letzte.
    Position := AOld.IndexOf(Tab.FileName);
    if (Position >= 0) and AOld.Tabs[Position].Changed then
    begin
      Old := AOld.Tabs[Position];
      Old.FileName := Tab.FileName;
      Result.Tabs := Result.Tabs + [Old];
      Continue;
    end;
    Old := Tab;
    Old.Changed := False;
    Old.ChangedAt := 0;
    Result.Tabs := Result.Tabs + [Old];
  end;
  Result.Active := -1;
  if AActive <> '' then
    Result.Active := Result.IndexOf(AActive);
  // Geändert, aber nicht mehr offen.
  for Change in AChanges do
  begin
    if (Trim(Change.FileName) = '') or (Result.IndexOf(Change.FileName) >= 0) then
      Continue;
    Open := False;
    for FileName in Result.Edited do
      if SameFile(FileName, Change.FileName) then
        Open := True;
    if not Open then
      Result.Edited := Result.Edited + [Change.FileName];
  end;
end;

class function TAtlasWelcomeContinue.MethodAt(const AText: string; ALine: Integer): string;
var
  Place: TAtlasMethodPlace;
begin
  Result := '';
  if (AText = '') or (ALine < 1) then
    Exit;
  if TAtlasBookmarks.MethodAt(TAtlasMethodToggle.Places(AText), ALine - 1, Place) then
    Result := Place.Name;
end;

/// <summary>Beschriftung eines Reiters ohne Markierungen (z. B. „*“ für geändert) und Leerraum.</summary>
function CaptionName(const ACaption: string): string;
begin
  Result := Trim(ACaption);
  while (Result <> '') and CharInSet(Result[Length(Result)], ['*', ' ']) do
    Delete(Result, Length(Result), 1);
  while (Result <> '') and CharInSet(Result[1], ['*', ' ', '&']) do
    Delete(Result, 1, 1);
end;

class function TAtlasWelcomeContinue.OrderByTabs(const AFiles, ACaptions: TArray<string>): TArray<string>;
var
  Used: TArray<Boolean>;
  Caption, Name: string;
  Index: Integer;
begin
  Result := nil;
  SetLength(Used, Length(AFiles));
  for Caption in ACaptions do
  begin
    Name := CaptionName(Caption);
    if Name = '' then
      Continue;
    // Gleich benannte Dateien in verschiedenen Ordnern: die erste noch nicht vergebene. Die IDE zeigt Units
    // auch ohne Endung („Kunde“ statt „Kunde.pas“).
    for Index := 0 to High(AFiles) do
      if not Used[Index] and (SameText(FileNameOf(AFiles[Index]), Name) or
        SameText(ChangeFileExt(FileNameOf(AFiles[Index]), ''), Name)) then
      begin
        Used[Index] := True;
        Result := Result + [AFiles[Index]];
        Break;
      end;
  end;
  for Index := 0 to High(AFiles) do
    if not Used[Index] then
      Result := Result + [AFiles[Index]];
end;

class function TAtlasWelcomeContinue.Plan(const AProject: string; const AState: TAtlasWorkState;
  const AExists: TAtlasContinueFileExists): TAtlasContinuePlan;
var
  Index, Wanted: Integer;
  Exists: Boolean;
begin
  Result := Default(TAtlasContinuePlan);
  Result.Project := AProject;
  Result.Active := -1;
  Wanted := AState.Active;
  if (Wanted < 0) or (Wanted > High(AState.Tabs)) then
    Wanted := AState.LastIndex;
  for Index := 0 to High(AState.Tabs) do
  begin
    Exists := True;
    if Assigned(AExists) then
      Exists := AExists(AState.Tabs[Index].FileName);
    if not Exists then
    begin
      Result.Missing := Result.Missing + [AState.Tabs[Index].FileName];
      Continue;
    end;
    Result.Open := Result.Open + [AState.Tabs[Index]];
    if Index = Wanted then
      Result.Active := High(Result.Open);
  end;
  // Fehlt der aktive Reiter, bleibt der zuletzt geöffnete aktiv.
  if (Result.Active < 0) and (Length(Result.Open) > 0) then
    Result.Active := High(Result.Open);
end;

class function TAtlasWelcomeContinue.Age(AAtLocal, ANowLocal: TDateTime; out AValue: Integer): TAtlasContinueAge;
var
  Minutes: Int64;
begin
  AValue := 0;
  Minutes := MinutesBetween(ANowLocal, AAtLocal);
  if (AAtLocal >= ANowLocal) or (Minutes < 1) then
    Exit(TAtlasContinueAge.JustNow);
  if Minutes < 60 then
  begin
    AValue := Minutes;
    Exit(TAtlasContinueAge.Minutes);
  end;
  if Trunc(AAtLocal) = Trunc(ANowLocal) then
  begin
    AValue := Minutes div 60;
    Exit(TAtlasContinueAge.Hours);
  end;
  if Trunc(AAtLocal) = Trunc(ANowLocal) - 1 then
    Exit(TAtlasContinueAge.Yesterday);
  Result := TAtlasContinueAge.Date;
end;

class function TAtlasWelcomeContinue.Select(const ACommits: TArray<TAtlasVcsIncomingCommit>;
  const AFiles: TArray<string>; AMax: Integer; out AMore: Boolean): TArray<TAtlasContinueCommit>;
var
  Commit: TAtlasVcsIncomingCommit;
  Item: TAtlasContinueCommit;
  Changed, Wanted: string;
begin
  Result := nil;
  AMore := False;
  for Commit in ACommits do
  begin
    Item := Default(TAtlasContinueCommit);
    Item.Commit := Commit;
    for Wanted in AFiles do
      for Changed in Commit.Files do
        if SameFile(Changed, Wanted) then
        begin
          Item.Files := Item.Files + [Wanted];
          Break;
        end;
    if Length(Item.Files) = 0 then
      Continue;
    if Length(Result) >= AMax then
    begin
      AMore := True;
      Break;
    end;
    Result := Result + [Item];
  end;
end;

class function TAtlasWelcomeContinue.ProbeHead(const AVcs: IAtlasVersionControl; var AState: TAtlasWorkState): Boolean;
var
  Outcome: TAtlasVcsOutcome;
  Head: TAtlasVcsHead;
  Incoming: IAtlasVcsIncoming;
  Revision: string;
begin
  Result := False;
  AState.Head := '';
  AState.Upstream := '';
  AState.UpstreamRevision := '';
  if AVcs = nil then
    Exit;
  Outcome := AVcs.Head(Head);
  if (Outcome = TAtlasVcsOutcome.NoWorkingCopy) or (Outcome = TAtlasVcsOutcome.Disabled) then
  begin
    AState.VcsKind := 'none';
    Exit(True);
  end;
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  AState.VcsKind := LowerCase(AtlasVcsKindName(AVcs.Kind));
  AState.Head := Head.Revision;
  AState.Upstream := Head.Upstream;
  if (Head.Upstream <> '') and Supports(AVcs, IAtlasVcsIncoming, Incoming) and
    (Incoming.Resolve(Head.Upstream, Revision) = TAtlasVcsOutcome.Ok) then
    AState.UpstreamRevision := Revision;
  Result := True;
end;

class function TAtlasWelcomeContinue.ProbeIncoming(const AVcs, AFetchVcs: IAtlasVersionControl;
  const AProject: string; const AState: TAtlasWorkState; ANowUtc: TDateTime;
  out AResult: TAtlasContinueIncoming): Boolean;
begin
  Result := ProbeIncoming(AVcs, AFetchVcs, AProject, '', AState, ANowUtc, AResult);
end;

class function TAtlasWelcomeContinue.ProbeIncoming(const AVcs, AFetchVcs: IAtlasVersionControl;
  const AProject, AMainBranch: string; const AState: TAtlasWorkState; ANowUtc: TDateTime;
  out AResult: TAtlasContinueIncoming): Boolean;
var
  Incoming, Fetcher: IAtlasVcsIncoming;
  Outcome: TAtlasVcsOutcome;
  Head: TAtlasVcsHead;
  Upstream, Revision, Resolved: string;
  Exclude, Saved: TArray<string>;
  Commits: TArray<TAtlasVcsIncomingCommit>;
  More: Boolean;
begin
  AResult := Default(TAtlasContinueIncoming);
  AResult.Project := AProject;
  AResult.At := ANowUtc;
  Result := False;
  if AVcs = nil then
    Exit;
  // Keine Versionsverwaltung oder keine Schnittstelle: kein Abschnitt, kein Fehler.
  if (AVcs.Kind = TAtlasVcsKind.None) or not Supports(AVcs, IAtlasVcsIncoming, Incoming) then
    Exit(True);
  if (AFetchVcs <> nil) and Supports(AFetchVcs, IAtlasVcsIncoming, Fetcher) then
  begin
    Outcome := Fetcher.Fetch('');
    AResult.FetchFailed := Outcome <> TAtlasVcsOutcome.Ok;
    // Ursache sichtbar machen (#1287): fehlende Anmeldung statt nur „ohne Abruf“.
    AResult.LoginNeeded := Outcome = TAtlasVcsOutcome.LoginNeeded;
  end;
  Outcome := AVcs.Head(Head);
  if (Outcome = TAtlasVcsOutcome.NoWorkingCopy) or (Outcome = TAtlasVcsOutcome.Disabled) then
    Exit(True);
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  // Der verfolgte Branch beim Schließen gilt; ohne ihn der heutige.
  Upstream := AState.Upstream;
  if Upstream = '' then
    Upstream := Head.Upstream;
  // Ohne verfolgten Branch gilt der Hauptbranch des Projekts (#1286), wenn es ihn gibt; nicht für ihn selbst.
  if (Upstream = '') and (Trim(AMainBranch) <> '') and not SameText(Head.Branch, Trim(AMainBranch)) then
  begin
    if (Incoming.Resolve('origin/' + Trim(AMainBranch), Resolved) = TAtlasVcsOutcome.Ok) and (Resolved <> '') then
      Upstream := 'origin/' + Trim(AMainBranch)
    else if (Incoming.Resolve(Trim(AMainBranch), Resolved) = TAtlasVcsOutcome.Ok) and (Resolved <> '') then
      Upstream := Trim(AMainBranch);
  end;
  // Ohne verfolgten Branch (auch SVN): kein Abschnitt.
  if Upstream = '' then
    Exit(True);
  // Was beim Schließen schon da war: HEAD und verfolgter Branch von damals (sofern es die Commits noch gibt).
  Exclude := nil;
  Saved := nil;
  Saved := Saved + [AState.Head, AState.UpstreamRevision];
  for Revision in Saved do
    if (Revision <> '') and (Incoming.Resolve(Revision, Resolved) = TAtlasVcsOutcome.Ok) and (Resolved <> '') then
      Exclude := Exclude + [Resolved];
  // Ohne gemerkten Stand: gegenüber dem heutigen HEAD (vor dem ersten Commit gibt es nichts zu vergleichen).
  if Length(Exclude) = 0 then
  begin
    if Head.Revision = '' then
      Exit(True);
    Exclude := Exclude + [Head.Revision];
  end;
  Outcome := Incoming.Incoming(Upstream, Exclude, MaxIncomingScan, Commits);
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  AResult.Available := True;
  AResult.Upstream := Upstream;
  AResult.Commits := Select(Commits, AState.Files, MaxIncomingShown, More);
  AResult.More := More;
  Result := True;
end;

end.
