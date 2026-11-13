unit Atlas.Core.Welcome.ContinueIssues;

// Bereich „Weiterarbeiten“ der Willkommensseite, Reiter „Issues“ (#2052), Teil
// ohne VCL und Open Tools API: der Arbeitsstand je Issue.
// - Format: Abschnitt "continueIssues" der Projekt-Zusammenfassung (#592), je
//   Issue-Kennung ein Arbeitsstand im selben Format wie "continue"
//   (Atlas.Core.Welcome.Continue) mit Titel und Branch des Issues:
//     "continueIssues": {"#1926": {"title": "…", "branch": "feature/1926-…",
//                                  "at": "…", "active": 0, "tabs": […],
//                                  "edited": […]}}
//   Neueste zuerst, höchstens welcomePage.continue.issues.count Einträge
//   (1–30, Vorgabe 10); die ältesten fallen heraus. Der Abschnitt "continue"
//   und alle übrigen Felder der Zusammenfassung bleiben beim Schreiben
//   unverändert.
// - Gespeichert wird beim Wechsel des aktiven Issues, beim „Beenden“ und beim
//   Schließen des Projekts (IDE-Schicht). Behobene bzw. geschlossene Issues
//   fallen dabei heraus.
// - Zeilen des Reiters: Arbeitsstände der zuletzt geöffneten Projekte mit
//   Reitern, ohne behobene Issues, neueste zuerst. Den Zustand liefert der
//   Tracker (Vertrag Atlas.IDE.Contracts.IssueWork); ohne Antwort gilt er als
//   unbekannt und der Eintrag bleibt.
// - Fortsetzen: Plan wie „Zuletzt“ (TAtlasWelcomeContinue.Plan); der Branch
//   wird nur nach Rückfrage gewechselt, fehlt er, gibt es nur die Reiter.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.Core.Welcome.Continue;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand eines Issues: unbekannt, offen oder behoben bzw. geschlossen.</summary>
  TAtlasIssueStateKind = (Unknown, Open, Resolved);
  /// <summary>Branch bei „Fortsetzen“: bleiben (gleich oder keiner gespeichert), nach Rückfrage wechseln, oder es
  /// gibt ihn nicht mehr (nur Reiter).</summary>
  TAtlasIssueBranchStep = (Keep, Ask, Missing);
{$SCOPEDENUMS OFF}

  /// <summary>Gespeicherter Arbeitsstand eines Issues.</summary>
  TAtlasIssueWorkEntry = record
    /// <summary>Kennung wie im Tracker ("#1926", "ATL-12").</summary>
    Key: string;
    /// <summary>Titel beim Speichern; '' unbekannt.</summary>
    Title: string;
    /// <summary>Branch des Issues; '' ohne.</summary>
    Branch: string;
    State: TAtlasWorkState;
    class function Create(const AKey, ATitle, ABranch: string; const AState: TAtlasWorkState): TAtlasIssueWorkEntry;
      static;
  end;

  TAtlasIssueWorkEntries = TArray<TAtlasIssueWorkEntry>;

  /// <summary>Eine Zeile des Reiters „Issues“.</summary>
  TAtlasIssueWorkRow = record
    /// <summary>Projekt bzw. Projektgruppe (vollständiger Pfad).</summary>
    Project: string;
    Entry: TAtlasIssueWorkEntry;
    /// <summary>Open oder Unknown; behobene Issues stehen nicht in der Liste.</summary>
    Status: TAtlasIssueStateKind;
    /// <summary>Zuletzt bearbeitete Datei (TAtlasWorkState.LastIndex); leer ohne Reiter.</summary>
    function LastTab: TAtlasWorkTab;
  end;

  TAtlasIssueWorkRows = TArray<TAtlasIssueWorkRow>;

  /// <summary>Zustand der Issues AKeys im Tracker von AProject, in derselben Reihenfolge; fehlende Einträge gelten als
  /// unbekannt.</summary>
  TAtlasIssueStatusLookup = reference to function(const AProject: string;
    const AKeys: TArray<string>): TArray<TAtlasIssueStateKind>;

  TAtlasWelcomeContinueIssues = class
  public const
    /// <summary>Abschnitt in der Projekt-Zusammenfassung.</summary>
    cSectionName = 'continueIssues';
    /// <summary>Grenzen und Vorgabe für welcomePage.continue.issues.count.</summary>
    cMinCount = 1;
    cMaxCount = 30;
    cDefaultCount = 10;
  public
    /// <summary>Gleiche Kennung: Groß-/Kleinschreibung und Leerraum am Rand egal.</summary>
    class function SameKey(const A, B: string): Boolean; static;
    /// <summary>Abschnitt "continueIssues" aus der Zusammenfassung, neueste zuerst; False ohne.</summary>
    class function Read(const ASummary: TAtlasProjectSummary; out AEntries: TAtlasIssueWorkEntries): Boolean; static;
    /// <summary>Abschnitt "continueIssues" in die Zusammenfassung (über Raw); ohne Einträge fällt er weg. Die übrigen
    /// Felder bleiben.</summary>
    class procedure Write(var ASummary: TAtlasProjectSummary; const AEntries: TAtlasIssueWorkEntries); static;
    class function ToJson(const AEntries: TAtlasIssueWorkEntries): string; static;
    class function FromJson(const AJson: string; out AEntries: TAtlasIssueWorkEntries): Boolean; static;
    /// <summary>AEntry vorn einsetzen (ein Eintrag gleicher Kennung fällt weg), höchstens ACount (auf
    /// MinCount..MaxCount begrenzt) Einträge; ohne Kennung oder ohne Reiter unverändert.</summary>
    class function Store(const AEntries: TAtlasIssueWorkEntries; const AEntry: TAtlasIssueWorkEntry;
      ACount: Integer): TAtlasIssueWorkEntries; static;
    /// <summary>AEntries ohne die Kennungen AKeys.</summary>
    class function Without(const AEntries: TAtlasIssueWorkEntries; const AKeys: TArray<string>): TAtlasIssueWorkEntries;
      static;
    /// <summary>Höchstens ACount (auf MinCount..MaxCount begrenzt) Einträge.</summary>
    class function Limit(const AEntries: TAtlasIssueWorkEntries; ACount: Integer): TAtlasIssueWorkEntries; static;
    class function Find(const AEntries: TAtlasIssueWorkEntries; const AKey: string;
      out AEntry: TAtlasIssueWorkEntry): Boolean; static;
    /// <summary>Kennungen in der Reihenfolge der Einträge.</summary>
    class function Keys(const AEntries: TAtlasIssueWorkEntries): TArray<string>; static;
    /// <summary>Kennungen aus AKeys, deren Zustand in AStates Resolved ist (gleiche Reihenfolge).</summary>
    class function ResolvedKeys(const AKeys: TArray<string>;
      const AStates: TArray<TAtlasIssueStateKind>): TArray<string>; static;
    /// <summary>Zeilen des Reiters „Issues“ zu AProjects (jedes Projekt einmal): nur mit Reitern, ohne behobene
    /// Issues (AStatus nil: alle unbekannt), neueste zuerst, höchstens ACount (auf MinCount..MaxCount begrenzt).
    /// </summary>
    class function Rows(const AProjects: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
      const AStatus: TAtlasIssueStatusLookup; ACount: Integer): TAtlasIssueWorkRows; static;
    /// <summary>Was „Fortsetzen“ mit dem Branch tut: AStored gespeichert, ACurrent ausgecheckt, AExists, ob es
    /// AStored noch gibt.</summary>
    class function BranchStep(const AStored, ACurrent: string; AExists: Boolean): TAtlasIssueBranchStep; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

const
  cTitle = 'title';
  cBranch = 'branch';

{ TAtlasIssueWorkEntry }

class function TAtlasIssueWorkEntry.Create(const AKey, ATitle, ABranch: string;
  const AState: TAtlasWorkState): TAtlasIssueWorkEntry;
begin
  Result := Default(TAtlasIssueWorkEntry);
  Result.Key := Trim(AKey);
  Result.Title := ATitle;
  Result.Branch := Trim(ABranch);
  Result.State := AState;
end;

{ TAtlasIssueWorkRow }

function TAtlasIssueWorkRow.LastTab: TAtlasWorkTab;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasWorkTab);
  mIndex := Entry.State.LastIndex;
  if mIndex >= 0 then
  begin
    Result := Entry.State.Tabs[mIndex];
  end;
end;

{ JSON }

/// <summary>Ein Eintrag als Objekt: Titel und Branch, dann die Felder des Arbeitsstands wie "continue".</summary>
function EntryJson(const AEntry: TAtlasIssueWorkEntry): TJSONObject;
var
  mState: TJSONValue;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  Result := TJSONObject.Create;
  if AEntry.Title <> '' then
  begin
    Result.AddPair(cTitle, AEntry.Title);
  end;
  if AEntry.Branch <> '' then
  begin
    Result.AddPair(cBranch, AEntry.Branch);
  end;
  mState := TJsonRead.Parse(TAtlasWelcomeContinue.ToJson(AEntry.State));
  try
    if mState is TJSONObject then
    begin
      for mIndex := 0 to TJSONObject(mState).Count - 1 do
      begin
        mPair := TJSONObject(mState).Pairs[mIndex];
        Result.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
      end;
    end;
  finally
    mState.Free;
  end;
end;

function SectionJson(const AEntries: TAtlasIssueWorkEntries): TJSONObject;
var
  mEntry: TAtlasIssueWorkEntry;
begin
  Result := TJSONObject.Create;
  for mEntry in AEntries do
  begin
    if (mEntry.Key <> '') and (Result.GetValue(mEntry.Key) = nil) then
    begin
      Result.AddPair(mEntry.Key, EntryJson(mEntry));
    end;
  end;
end;

/// <summary>AEntry nach Zeit einsortieren, neueste zuerst; bei Gleichstand bleibt die Reihenfolge (stabil).</summary>
procedure InsertEntry(var AFound: TAtlasIssueWorkEntries; const AEntry: TAtlasIssueWorkEntry);
var
  mIndex, mPosition: Integer;
begin
  mPosition := Length(AFound);
  for mIndex := High(AFound) downto 0 do
  begin
    if AEntry.State.At > AFound[mIndex].State.At then
    begin
      mPosition := mIndex;
    end;
  end;
  Insert(AEntry, AFound, mPosition);
end;

/// <summary>Einträge aus dem Abschnitt, neueste zuerst; Einträge ohne Kennung oder Objekt fallen weg.</summary>
function EntriesOf(ASection: TJSONObject): TAtlasIssueWorkEntries;
var
  mIndex: Integer;
  mPair: TJSONPair;
  mEntry: TAtlasIssueWorkEntry;
  mKey: string;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.Count - 1 do
  begin
    mPair := ASection.Pairs[mIndex];
    mKey := Trim(mPair.JsonString.Value);
    if (mKey = '') or not (mPair.JsonValue is TJSONObject) then
    begin
      Continue;
    end;
    mEntry := Default(TAtlasIssueWorkEntry);
    mEntry.Key := mKey;
    mEntry.Title := TJsonRead.Text(TJSONObject(mPair.JsonValue), cTitle);
    mEntry.Branch := Trim(TJsonRead.Text(TJSONObject(mPair.JsonValue), cBranch));
    if TAtlasWelcomeContinue.FromJson(mPair.JsonValue.ToJSON, mEntry.State) then
    begin
      InsertEntry(Result, mEntry);
    end;
  end;
end;

function HasKey(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  mKnown: string;
begin
  for mKnown in AKeys do
  begin
    if TAtlasWelcomeContinueIssues.SameKey(mKnown, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ClampCount(ACount: Integer): Integer;
begin
  Result := Min(Max(ACount, TAtlasWelcomeContinueIssues.cMinCount), TAtlasWelcomeContinueIssues.cMaxCount);
end;

{ TAtlasWelcomeContinueIssues }

class function TAtlasWelcomeContinueIssues.SameKey(const A, B: string): Boolean;
begin
  Result := SameText(Trim(A), Trim(B));
end;

class function TAtlasWelcomeContinueIssues.ToJson(const AEntries: TAtlasIssueWorkEntries): string;
var
  mSection: TJSONObject;
begin
  mSection := SectionJson(AEntries);
  try
    Result := mSection.ToJSON;
  finally
    mSection.Free;
  end;
end;

class function TAtlasWelcomeContinueIssues.FromJson(const AJson: string; out AEntries: TAtlasIssueWorkEntries): Boolean;
var
  mValue: TJSONValue;
begin
  AEntries := nil;
  mValue := TJsonRead.Parse(AJson);
  try
    Result := mValue is TJSONObject;
    if Result then
    begin
      AEntries := EntriesOf(TJSONObject(mValue));
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasWelcomeContinueIssues.Read(const ASummary: TAtlasProjectSummary;
  out AEntries: TAtlasIssueWorkEntries): Boolean;
var
  mValue: TJSONValue;
  mSection: TJSONObject;
begin
  AEntries := nil;
  mValue := TJsonRead.Parse(ASummary.Raw);
  try
    mSection := nil;
    if mValue is TJSONObject then
    begin
      mSection := TJsonRead.Obj(TJSONObject(mValue), cSectionName);
    end;
    Result := mSection <> nil;
    AEntries := EntriesOf(mSection);
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasWelcomeContinueIssues.Write(var ASummary: TAtlasProjectSummary;
  const AEntries: TAtlasIssueWorkEntries);
var
  mValue: TJSONValue;
  mOriginal, mRoot: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  mValue := TJsonRead.Parse(ASummary.Raw);
  mRoot := TJSONObject.Create;
  try
    // Alles außer dem Abschnitt übernehmen (auch "continue" und unbekannte Felder).
    if mValue is TJSONObject then
    begin
      mOriginal := TJSONObject(mValue);
      for mIndex := 0 to mOriginal.Count - 1 do
      begin
        mPair := mOriginal.Pairs[mIndex];
        if mPair.JsonString.Value <> cSectionName then
        begin
          mRoot.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
        end;
      end;
    end;
    if Length(AEntries) > 0 then
    begin
      mRoot.AddPair(cSectionName, SectionJson(AEntries));
    end;
    ASummary.Raw := mRoot.ToJSON;
  finally
    mRoot.Free;
    mValue.Free;
  end;
end;

class function TAtlasWelcomeContinueIssues.Limit(const AEntries: TAtlasIssueWorkEntries;
  ACount: Integer): TAtlasIssueWorkEntries;
begin
  Result := Copy(AEntries, 0, ClampCount(ACount));
end;

class function TAtlasWelcomeContinueIssues.Store(const AEntries: TAtlasIssueWorkEntries;
  const AEntry: TAtlasIssueWorkEntry; ACount: Integer): TAtlasIssueWorkEntries;
var
  mEntry: TAtlasIssueWorkEntry;
begin
  if (Trim(AEntry.Key) = '') or (AEntry.State.TabCount = 0) then
  begin
    Exit(Limit(AEntries, ACount));
  end;
  SetLength(Result, 1);
  Result[0] := AEntry;
  Result[0].Key := Trim(AEntry.Key);
  for mEntry in AEntries do
  begin
    if not SameKey(mEntry.Key, AEntry.Key) then
    begin
      Result := Result + [mEntry];
    end;
  end;
  Result := Limit(Result, ACount);
end;

class function TAtlasWelcomeContinueIssues.Without(const AEntries: TAtlasIssueWorkEntries;
  const AKeys: TArray<string>): TAtlasIssueWorkEntries;
var
  mEntry: TAtlasIssueWorkEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if not HasKey(AKeys, mEntry.Key) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

class function TAtlasWelcomeContinueIssues.Find(const AEntries: TAtlasIssueWorkEntries; const AKey: string;
  out AEntry: TAtlasIssueWorkEntry): Boolean;
var
  mEntry: TAtlasIssueWorkEntry;
begin
  AEntry := Default(TAtlasIssueWorkEntry);
  for mEntry in AEntries do
  begin
    if SameKey(mEntry.Key, AKey) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasWelcomeContinueIssues.Keys(const AEntries: TAtlasIssueWorkEntries): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result[mIndex] := AEntries[mIndex].Key;
  end;
end;

class function TAtlasWelcomeContinueIssues.ResolvedKeys(const AKeys: TArray<string>;
  const AStates: TArray<TAtlasIssueStateKind>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to Min(High(AKeys), High(AStates)) do
  begin
    if AStates[mIndex] = TAtlasIssueStateKind.Resolved then
    begin
      Result := Result + [AKeys[mIndex]];
    end;
  end;
end;

/// <summary>Zustand des Eintrags AIndex; unbekannt, wenn AStates zu kurz ist.</summary>
function StateAt(const AStates: TArray<TAtlasIssueStateKind>; AIndex: Integer): TAtlasIssueStateKind;
begin
  Result := TAtlasIssueStateKind.Unknown;
  if (AIndex >= 0) and (AIndex <= High(AStates)) then
  begin
    Result := AStates[AIndex];
  end;
end;

/// <summary>ARow nach Zeit einsortieren, neueste zuerst; stabil.</summary>
procedure InsertRow(var ARows: TAtlasIssueWorkRows; const ARow: TAtlasIssueWorkRow);
var
  mIndex, mPosition: Integer;
begin
  mPosition := Length(ARows);
  for mIndex := High(ARows) downto 0 do
  begin
    if ARow.Entry.State.At > ARows[mIndex].Entry.State.At then
    begin
      mPosition := mIndex;
    end;
  end;
  Insert(ARow, ARows, mPosition);
end;

/// <summary>Zeilen eines Projekts in ARows einsortieren.</summary>
procedure AddProjectRows(var ARows: TAtlasIssueWorkRows; const AProject: string;
  const AEntries: TAtlasIssueWorkEntries; const AStatus: TAtlasIssueStatusLookup);
var
  mStates: TArray<TAtlasIssueStateKind>;
  mIndex: Integer;
  mRow: TAtlasIssueWorkRow;
begin
  mStates := nil;
  if Assigned(AStatus) then
  begin
    mStates := AStatus(AProject, TAtlasWelcomeContinueIssues.Keys(AEntries));
  end;
  for mIndex := 0 to High(AEntries) do
  begin
    mRow := Default(TAtlasIssueWorkRow);
    mRow.Project := AProject;
    mRow.Entry := AEntries[mIndex];
    mRow.Status := StateAt(mStates, mIndex);
    if (mRow.Status <> TAtlasIssueStateKind.Resolved) and (mRow.Entry.State.TabCount > 0) then
    begin
      InsertRow(ARows, mRow);
    end;
  end;
end;

class function TAtlasWelcomeContinueIssues.Rows(const AProjects: TArray<string>;
  const ALoad: TAtlasProjectSummaryLoader; const AStatus: TAtlasIssueStatusLookup;
  ACount: Integer): TAtlasIssueWorkRows;
var
  mProject, mKey: string;
  mSeen: TList<string>;
  mSummary: TAtlasProjectSummary;
  mEntries: TAtlasIssueWorkEntries;
  mFound: TAtlasIssueWorkRows;
begin
  Result := nil;
  if not Assigned(ALoad) then
  begin
    Exit;
  end;
  mFound := nil;
  mSeen := TList<string>.Create;
  try
    for mProject in AProjects do
    begin
      mKey := TAtlasProjectSummaries.NormalizedPath(mProject);
      if (Trim(mProject) = '') or mSeen.Contains(mKey) then
      begin
        Continue;
      end;
      mSeen.Add(mKey);
      if ALoad(Trim(mProject), mSummary) and Read(mSummary, mEntries) then
      begin
        AddProjectRows(mFound, Trim(mProject), mEntries, AStatus);
      end;
    end;
  finally
    mSeen.Free;
  end;
  Result := Copy(mFound, 0, ClampCount(ACount));
end;

class function TAtlasWelcomeContinueIssues.BranchStep(const AStored, ACurrent: string;
  AExists: Boolean): TAtlasIssueBranchStep;
begin
  if (Trim(AStored) = '') or SameText(Trim(AStored), Trim(ACurrent)) then
  begin
    Result := TAtlasIssueBranchStep.Keep;
  end
  else if AExists then
  begin
    Result := TAtlasIssueBranchStep.Ask;
  end
  else
  begin
    Result := TAtlasIssueBranchStep.Missing;
  end;
end;

end.
