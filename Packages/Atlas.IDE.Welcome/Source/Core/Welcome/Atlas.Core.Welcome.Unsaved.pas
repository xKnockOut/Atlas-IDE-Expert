unit Atlas.Core.Welcome.Unsaved;

// Bereich „Nicht gesichert“ der Willkommensseite (#762), Teil ohne VCL und
// Open Tools API: was in den zuletzt geöffneten Projekten noch nicht im
// Repository bzw. auf dem Server liegt, wie alt es ist und in welcher
// Reihenfolge und Farbe es erscheint.
// - Arten je Projekt (je Art eine Zeile): nicht übernommene Änderungen
//   (geändert, neu, gelöscht; nur im Projektordner), Dateien im Konflikt,
//   nicht gepushte Commits (Git, Branches mit Upstream), lokale Branches ohne
//   Upstream mit Commits, die auf keinem Remote liegen (Git), Stashes (Git).
//   SVN kennt nur Änderungen und Konflikte.
// - Alter: Änderungen und Konflikte nach der ältesten Änderungszeit der
//   Dateien, Commits nach dem ältesten nicht gepushten Commit, Branches ohne
//   Upstream nach ihrem ältesten nur lokalen Commit, Stashes nach dem ältesten
//   Stash. Ist es unbekannt (z. B. nur gelöschte Dateien), gilt der Zeitpunkt,
//   an dem Atlas die Art zuerst sah (Merge).
// - Ampel: grün, gelb ab welcomePage.unsaved.warnHours, rot ab
//   welcomePage.unsaved.alertHours; Zeilen jünger als
//   welcomePage.unsaved.minAgeHours und „bis morgen ignorierte“ entfallen.
//   Sortiert wird älteste zuerst.
// - Abfrage (Probe): nur im Hintergrund, über IAtlasVersionControl und
//   IAtlasVcsLocalWork (#571), ohne fetch und ohne Netzzugriff; nach
//   TimeLimitMs je Projekt startet sie keinen weiteren Aufruf. Was nicht mehr
//   abgefragt wurde, übernimmt Merge aus dem gespeicherten Stand.
// - Gespeichert wird im Abschnitt "unsaved" der Projekt-Zusammenfassung
//   (#592), damit die Seite sofort den letzten Stand zeigt:
//     "unsaved": {"at": "…", "kind": "git|svn|none", "root": "C:\\Repo",
//                 "branch": "main",
//                 "items": [{"kind": "changes", "count": 4, "modified": 3,
//                            "added": 1, "deleted": 0, "since": "…"},
//                           {"kind": "commits", "count": 3, "since": "…",
//                            "branches": ["main"]},
//                           {"kind": "noUpstream", "count": 1, "commits": 2,
//                            "since": "…", "branches": ["feature/x"]},
//                           {"kind": "stashes", "count": 1, "since": "…",
//                            "name": "WIP Hover-Cache", "ref": "<hash>"}],
//                 "ignore": {"changes": "…"}}
//   Unbekannte Felder im Abschnitt gehen beim Schreiben verloren; die übrige
//   Datei bleibt unverändert (Format 1).
// - Arten, die das ganze Repository betreffen (Commits, Branches, Stashes),
//   erscheinen nur einmal je Arbeitskopie, beim zuletzt geöffneten Projekt.
// - Externals und Submodule (#1292, vcs.externals.show): svn status der
//   Wurzel enthält die Änderungen der Externals schon (die Summe bleibt);
//   verteilen sie sich auf mehrere Arbeitskopien, nennt "places" die Anteile
//   ([{"path": "Packages/Drucken", "count": 5}, …], Wurzel mit "path": "").

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.WorkingCopies;

type
{$SCOPEDENUMS ON}
  TAtlasUnsavedKind = (Changes, Conflicts, Commits, NoUpstream, Stashes);
  /// <summary>Ampel: Fresh grün, Warning gelb, Alert rot.</summary>
  TAtlasUnsavedLevel = (Fresh, Warning, Alert);
  TAtlasUnsavedAgeUnit = (Minutes, Hours, Days);
{$SCOPEDENUMS OFF}
  TAtlasUnsavedKinds = set of TAtlasUnsavedKind;

  /// <summary>Anteil einer Arbeitskopie (#1292): Wurzel, External oder Submodul.</summary>
  TAtlasUnsavedPlace = record
    /// <summary>Ordner relativ zur Wurzel mit "/" ('' = Wurzel).</summary>
    Path: string;
    Count: Integer;
    class function Create(const APath: string; ACount: Integer): TAtlasUnsavedPlace; static;
  end;

  TAtlasUnsavedItem = record
    Kind: TAtlasUnsavedKind;
    /// <summary>Changes und Conflicts: Dateien; Commits: Commits; NoUpstream: Branches; Stashes: Stashes.</summary>
    Count: Integer;
    /// <summary>Nur Changes: geänderte (auch umbenannt), neue (auch unversioniert) und gelöschte Dateien.</summary>
    Modified: Integer;
    Added: Integer;
    Deleted: Integer;
    /// <summary>Ältester Stand (UTC); 0 = unbekannt.</summary>
    Since: TDateTime;
    /// <summary>Commits und NoUpstream: betroffene Branches.</summary>
    Branches: TArray<string>;
    /// <summary>Nur NoUpstream: Commits, die auf keinem Remote liegen; -1 unbekannt.</summary>
    Commits: Integer;
    /// <summary>Nur Stashes: Name bzw. Nachricht und Commit des ältesten.</summary>
    Name: string;
    Ref: string;
    /// <summary>Nur Changes und Conflicts mit vcs.externals.show (#1292): Anteile, wenn sich die Dateien auf
    /// mehr als eine Arbeitskopie verteilen (Wurzel und Externals bzw. Submodule); sonst leer.</summary>
    Places: TArray<TAtlasUnsavedPlace>;
    class function Create(AKind: TAtlasUnsavedKind; ACount: Integer): TAtlasUnsavedItem; static;
    /// <summary>„Push …“ statt „Ansehen“.</summary>
    function CanPush: Boolean;
  end;

  TAtlasUnsavedIgnore = record
    Kind: TAtlasUnsavedKind;
    /// <summary>Bis dahin ausgeblendet (UTC).</summary>
    UntilUtc: TDateTime;
  end;

  /// <summary>Stand eines Projekts (Abschnitt "unsaved" der Zusammenfassung).</summary>
  TAtlasUnsavedState = record
    Known: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
    /// <summary>"git", "svn" oder "none".</summary>
    Kind: string;
    /// <summary>Wurzel der Arbeitskopie.</summary>
    Root: string;
    /// <summary>Aktueller Branch bzw. SVN-Pfad.</summary>
    Branch: string;
    Items: TArray<TAtlasUnsavedItem>;
    Ignored: TArray<TAtlasUnsavedIgnore>;
    /// <summary>Arten, die die Abfrage vollständig geliefert hat (wird nicht gespeichert).</summary>
    Queried: TAtlasUnsavedKinds;
    class function Empty: TAtlasUnsavedState; static;
    function InWorkingCopy: Boolean;
    function Find(AKind: TAtlasUnsavedKind; out AItem: TAtlasUnsavedItem): Boolean;
    /// <summary>Ausgeblendet bis (UTC); 0 = nicht ausgeblendet.</summary>
    function IgnoredUntil(AKind: TAtlasUnsavedKind): TDateTime;
  end;

  /// <summary>Ein Projekt der Liste mit seinem Stand.</summary>
  TAtlasUnsavedProject = record
    Project: string;
    State: TAtlasUnsavedState;
    /// <summary>In dieser Sitzung abgefragt; sonst gilt der gespeicherte Stand.</summary>
    Fresh: Boolean;
    /// <summary>Abfrage läuft gerade.</summary>
    Querying: Boolean;
  end;

  TAtlasUnsavedOptions = record
    MinAgeHours: Integer;
    WarnHours: Integer;
    AlertHours: Integer;
    class function Create(AMinAgeHours, AWarnHours, AAlertHours: Integer): TAtlasUnsavedOptions; static;
  end;

  TAtlasUnsavedRow = record
    Project: string;
    /// <summary>Name des Projekts ohne Endung.</summary>
    Name: string;
    Branch: string;
    /// <summary>"git" oder "svn".</summary>
    VcsKind: string;
    Item: TAtlasUnsavedItem;
    Level: TAtlasUnsavedLevel;
    /// <summary>Stand aus der Datei, nicht in dieser Sitzung abgefragt.</summary>
    Stale: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
  end;

  TAtlasUnsavedView = record
    Rows: TArray<TAtlasUnsavedRow>;
    /// <summary>Zeilen, die zu jung oder bis morgen ignoriert sind.</summary>
    Hidden: Integer;
    /// <summary>Für mindestens ein Projekt ist ein Stand bekannt.</summary>
    Known: Boolean;
    /// <summary>Mindestens eine Abfrage läuft.</summary>
    Querying: Boolean;
    /// <summary>Nichts zu zeigen.</summary>
    function Clean: Boolean;
  end;

  /// <summary>Ein Branch zum Pushen mit Ziel und Commits („Push …“).</summary>
  TAtlasUnsavedPush = record
    Branch: string;
    Remote: string;
    /// <summary>Ziel auf dem Remote, z. B. "refs/heads/main".</summary>
    RemoteRef: string;
    /// <summary>Als verfolgten Branch eintragen (Branch ohne Upstream).</summary>
    SetUpstream: Boolean;
    /// <summary>Neueste zuerst, höchstens TAtlasWelcomeUnsaved.cPushListMax.</summary>
    Commits: TArray<TAtlasVcsCommit>;
    /// <summary>Es gibt mehr Commits als aufgeführt.</summary>
    More: Boolean;
    /// <summary>Ziel als Text, z. B. "origin/main".</summary>
    function Target: string;
  end;

  /// <summary>Änderungszeit einer Datei in UTC; False, wenn es sie nicht gibt.</summary>
  TAtlasUnsavedFileTime = reference to function(const AFileName: string; out AUtc: TDateTime): Boolean;
  /// <summary>True, sobald das Zeitlimit der Abfrage erreicht ist.</summary>
  TAtlasUnsavedExpired = reference to function: Boolean;

  /// <summary>Anfrage für TAtlasWelcomeUnsaved.Probe: Projektordner, Zeitpunkt (UTC), Änderungszeiten und
  /// Zeitlimit (beide dürfen nil sein) sowie vcs.externals.show (#1292).</summary>
  TAtlasUnsavedQuery = record
    Folder: string;
    NowUtc: TDateTime;
    FileTime: TAtlasUnsavedFileTime;
    Expired: TAtlasUnsavedExpired;
    /// <summary>Änderungen und Konflikte je Arbeitskopie aufteilen (Places), mit einer weiteren lokalen Abfrage
    /// (svn status bzw. git submodule status).</summary>
    WorkingCopies: Boolean;
    class function Create(const AFolder: string; ANowUtc: TDateTime; const AFileTime: TAtlasUnsavedFileTime;
      const AExpired: TAtlasUnsavedExpired): TAtlasUnsavedQuery; static;
  end;

  TAtlasWelcomeUnsaved = class
  public const
    /// <summary>Abschnitt in der Projekt-Zusammenfassung.</summary>
    cSectionName = 'unsaved';
    /// <summary>Obergrenze der Stunden-Einstellungen (ein Jahr).</summary>
    cMaxHours = 8760;
    /// <summary>Zeitlimit je Projekt; danach startet die Abfrage keinen weiteren Aufruf.</summary>
    cTimeLimitMs = 2000;
    /// <summary>Zeitlimit je Aufruf.</summary>
    cCallTimeoutMs = 1000;
    /// <summary>Höchstens so viele git log je Projekt (Alter der Commits).</summary>
    cMaxOutgoingCalls = 6;
    /// <summary>Höchstens so viele Commits je Branch für das Alter.</summary>
    cMaxCommits = 1000;
    /// <summary>Höchstens so viele Commits je Branch im Dialog „Push …“.</summary>
    cPushListMax = 50;
    /// <summary>Zeitlimit für git push.</summary>
    cPushTimeoutMs = 120000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite dasselbe Projekt erneut ab.</summary>
    cRefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet.</summary>
    cQueryLimitMs = 8000;
  public
    /// <summary>Art als Text für die Datei: "changes", "conflicts", "commits", "noUpstream", "stashes".</summary>
    class function KindName(AKind: TAtlasUnsavedKind): string; static;
    class function KindOf(const AText: string; out AKind: TAtlasUnsavedKind): Boolean; static;
    /// <summary>Betrifft das ganze Repository (nicht nur den Projektordner).</summary>
    class function RepositoryWide(AKind: TAtlasUnsavedKind): Boolean; static;
    /// <summary>Änderungen und Konflikte unterhalb von AFolder ('' = alle).</summary>
    class function ChangesBelow(const AChanges: TArray<TAtlasVcsChange>;
      const AFolder: string): TArray<TAtlasVcsChange>; static;
    /// <summary>Abfrage (startet Prozesse: nur im Hintergrund). True mit AState, wenn das Ergebnis gilt (auch
    /// „none“ ohne Versionsverwaltung); False bei Fehler, Zeitüberschreitung oder fehlendem Programm.
    /// AFileTime liefert Änderungszeiten, AExpired das Zeitlimit (beide dürfen nil sein).</summary>
    class function Probe(const AVcs: IAtlasVersionControl; const AFolder: string; ANowUtc: TDateTime;
      const AFileTime: TAtlasUnsavedFileTime; const AExpired: TAtlasUnsavedExpired;
      out AState: TAtlasUnsavedState): Boolean; overload; static;
    /// <summary>Wie oben mit allen Angaben in AQuery, auch WorkingCopies.</summary>
    class function Probe(const AVcs: IAtlasVersionControl; const AQuery: TAtlasUnsavedQuery;
      out AState: TAtlasUnsavedState): Boolean; overload; static;
    /// <summary>Anteile je Arbeitskopie aus den Änderungen AChanges (eine Art) und den Ordnern ARows; leer, wenn
    /// höchstens eine Arbeitskopie betroffen ist.</summary>
    class function PlacesOf(const AChanges: TArray<TAtlasVcsChange>;
      const ARows: TArray<TAtlasVcsWorkingCopyRow>): TArray<TAtlasUnsavedPlace>; static;
    /// <summary>"Kasse 2 · Packages\Drucken 5" (Wurzel = AName); '' ohne Anteile.</summary>
    class function PlacesText(const AItem: TAtlasUnsavedItem; const AName: string): string; static;
    /// <summary>Neues Ergebnis mit dem gespeicherten Stand zusammenführen: nicht abgefragte Arten und
    /// unbekanntes Alter aus AOld (sonst ANowUtc), Ignorieren aus AOld ohne abgelaufene.</summary>
    class function Merge(const AOld, ANew: TAtlasUnsavedState; ANowUtc: TDateTime): TAtlasUnsavedState; static;
    /// <summary>Alter in Stunden (nie negativ); 0 bei unbekanntem Zeitpunkt.</summary>
    class function AgeHours(ASince, ANowUtc: TDateTime): Double; static;
    /// <summary>Alter für die Anzeige: unter einer Stunde Minuten (mindestens 1), unter einem Tag Stunden, sonst
    /// Tage.</summary>
    class procedure Age(ASince, ANowUtc: TDateTime; out AValue: Integer; out AUnit: TAtlasUnsavedAgeUnit); static;
    /// <summary>Ampel nach Alter: rot ab AlertHours, gelb ab WarnHours, sonst grün; unbekannt = grün.</summary>
    class function Level(ASince, ANowUtc: TDateTime; const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedLevel;
      static;
    /// <summary>Zeilen aller Projekte: ohne Projekte ohne Versionsverwaltung, ohne zu junge und ignorierte,
    /// repositoryweite Arten einmal je Arbeitskopie, älteste zuerst.</summary>
    class function View(const AProjects: TArray<TAtlasUnsavedProject>; ANowUtc: TDateTime;
      const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedView; static;
    /// <summary>„Ignorieren bis morgen“: Beginn des nächsten Tages zu ANowLocal (Ortszeit).</summary>
    class function Tomorrow(ANowLocal: TDateTime): TDateTime; static;
    /// <summary>AKind bis AUntilUtc ausblenden.</summary>
    class procedure Ignore(var AState: TAtlasUnsavedState; AKind: TAtlasUnsavedKind; AUntilUtc: TDateTime); static;
    /// <summary>Abschnitt "unsaved" aus der Zusammenfassung; False ohne.</summary>
    class function Read(const ASummary: TAtlasProjectSummary; out AState: TAtlasUnsavedState): Boolean; static;
    /// <summary>Abschnitt "unsaved" in die Zusammenfassung (über Raw; TAtlasProjectSummaries.ToJson behält
    /// ihn).</summary>
    class procedure Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasUnsavedState); static;
    class function ToJson(const AState: TAtlasUnsavedState): string; static;
    class function FromJson(const AJson: string; out AState: TAtlasUnsavedState): Boolean; static;
    /// <summary>Was „Push …“ für AItem pushen würde (startet Prozesse: nur im Hintergrund). Commits: Branches
    /// mit Upstream und Vorsprung auf ihren Upstream. NoUpstream: auf das Remote des Branchs, sonst das
    /// einzige Remote oder "origin", mit --set-upstream; ohne solches Remote entfällt der Branch.</summary>
    class function PushPlans(const ALocal: IAtlasVcsLocalWork; const AItem: TAtlasUnsavedItem;
      out APlans: TArray<TAtlasUnsavedPush>): TAtlasVcsOutcome; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Projects.Recording,
  Atlas.Text.Json;

const
  cKindNames: array[TAtlasUnsavedKind] of string = ('changes', 'conflicts', 'commits', 'noUpstream', 'stashes');
  cAllKinds: TAtlasUnsavedKinds = [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts,
    TAtlasUnsavedKind.Commits, TAtlasUnsavedKind.NoUpstream, TAtlasUnsavedKind.Stashes];

{ TAtlasUnsavedItem }

class function TAtlasUnsavedItem.Create(AKind: TAtlasUnsavedKind; ACount: Integer): TAtlasUnsavedItem;
begin
  Result := Default(TAtlasUnsavedItem);
  Result.Kind := AKind;
  Result.Count := ACount;
  Result.Commits := -1;
end;

{ TAtlasUnsavedPlace }

class function TAtlasUnsavedPlace.Create(const APath: string; ACount: Integer): TAtlasUnsavedPlace;
begin
  Result.Path := APath;
  Result.Count := ACount;
end;

function TAtlasUnsavedItem.CanPush: Boolean;
begin
  Result := (Kind = TAtlasUnsavedKind.Commits) or (Kind = TAtlasUnsavedKind.NoUpstream);
end;

{ TAtlasUnsavedState }

class function TAtlasUnsavedState.Empty: TAtlasUnsavedState;
begin
  Result := Default(TAtlasUnsavedState);
end;

function TAtlasUnsavedState.InWorkingCopy: Boolean;
begin
  Result := Known and (SameText(Kind, 'git') or SameText(Kind, 'svn'));
end;

function TAtlasUnsavedState.Find(AKind: TAtlasUnsavedKind; out AItem: TAtlasUnsavedItem): Boolean;
var
  mItem: TAtlasUnsavedItem;
begin
  AItem := TAtlasUnsavedItem.Create(AKind, 0);
  Result := False;
  for mItem in Items do
  begin
    if mItem.Kind = AKind then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
end;

function TAtlasUnsavedState.IgnoredUntil(AKind: TAtlasUnsavedKind): TDateTime;
var
  mEntry: TAtlasUnsavedIgnore;
begin
  Result := 0;
  for mEntry in Ignored do
  begin
    if (mEntry.Kind = AKind) and (mEntry.UntilUtc > Result) then
    begin
      Result := mEntry.UntilUtc;
    end;
  end;
end;

{ TAtlasUnsavedOptions }

class function TAtlasUnsavedOptions.Create(AMinAgeHours, AWarnHours, AAlertHours: Integer): TAtlasUnsavedOptions;
begin
  Result.MinAgeHours := AMinAgeHours;
  Result.WarnHours := AWarnHours;
  Result.AlertHours := AAlertHours;
end;

{ TAtlasUnsavedQuery }

class function TAtlasUnsavedQuery.Create(const AFolder: string; ANowUtc: TDateTime;
  const AFileTime: TAtlasUnsavedFileTime; const AExpired: TAtlasUnsavedExpired): TAtlasUnsavedQuery;
begin
  Result.Folder := AFolder;
  Result.NowUtc := ANowUtc;
  Result.FileTime := AFileTime;
  Result.Expired := AExpired;
  Result.WorkingCopies := False;
end;

{ TAtlasUnsavedView }

function TAtlasUnsavedView.Clean: Boolean;
begin
  Result := Length(Rows) = 0;
end;

{ TAtlasUnsavedPush }

function TAtlasUnsavedPush.Target: string;
var
  mName: string;
begin
  mName := RemoteRef;
  if Copy(mName, 1, 11) = 'refs/heads/' then
  begin
    mName := Copy(mName, 12, MaxInt);
  end;
  Result := Remote + '/' + mName;
end;

{ Hilfen }

function Older(ACurrent, ACandidate: TDateTime): TDateTime;
begin
  // 0 = unbekannt zählt nicht.
  Result := ACurrent;
  if (ACandidate > 0) and ((Result <= 0) or (ACandidate < Result)) then
  begin
    Result := ACandidate;
  end;
end;

function FileSince(const AFileTime: TAtlasUnsavedFileTime; const APath: string): TDateTime;
var
  mStamp: TDateTime;
begin
  Result := 0;
  if Assigned(AFileTime) and (APath <> '') and AFileTime(APath, mStamp) then
  begin
    Result := mStamp;
  end;
end;

function TimeUp(const AExpired: TAtlasUnsavedExpired): Boolean;
begin
  Result := Assigned(AExpired) and AExpired();
end;

procedure AddItem(var AState: TAtlasUnsavedState; const AItem: TAtlasUnsavedItem);
begin
  if AItem.Count > 0 then
  begin
    AState.Items := AState.Items + [AItem];
  end;
end;

procedure AddChanges(var AState: TAtlasUnsavedState; const AChanges: TArray<TAtlasVcsChange>;
  const AFileTime: TAtlasUnsavedFileTime);
var
  mChange: TAtlasVcsChange;
  mChanges, mConflicts: TAtlasUnsavedItem;
begin
  mChanges := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Changes, 0);
  mConflicts := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Conflicts, 0);
  for mChange in AChanges do
    case mChange.Kind of
      TAtlasVcsChangeKind.Conflicted:
        begin
          Inc(mConflicts.Count);
          mConflicts.Since := Older(mConflicts.Since, FileSince(AFileTime, mChange.Path));
        end;
      TAtlasVcsChangeKind.Added, TAtlasVcsChangeKind.Untracked:
        begin
          Inc(mChanges.Count);
          Inc(mChanges.Added);
          mChanges.Since := Older(mChanges.Since, FileSince(AFileTime, mChange.Path));
        end;
      TAtlasVcsChangeKind.Deleted, TAtlasVcsChangeKind.Missing:
        begin
          // Keine Datei, keine Zeit: Alter dann über Merge.
          Inc(mChanges.Count);
          Inc(mChanges.Deleted);
        end;
    else
      Inc(mChanges.Count);
      Inc(mChanges.Modified);
      mChanges.Since := Older(mChanges.Since, FileSince(AFileTime, mChange.Path));
    end;
  AddItem(AState, mChanges);
  AddItem(AState, mConflicts);
end;

{ TAtlasWelcomeUnsaved }

class function TAtlasWelcomeUnsaved.KindName(AKind: TAtlasUnsavedKind): string;
begin
  Result := cKindNames[AKind];
end;

class function TAtlasWelcomeUnsaved.KindOf(const AText: string; out AKind: TAtlasUnsavedKind): Boolean;
var
  mKind: TAtlasUnsavedKind;
begin
  AKind := TAtlasUnsavedKind.Changes;
  for mKind := Low(TAtlasUnsavedKind) to High(TAtlasUnsavedKind) do
  begin
    if SameText(cKindNames[mKind], Trim(AText)) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasWelcomeUnsaved.RepositoryWide(AKind: TAtlasUnsavedKind): Boolean;
begin
  Result := (AKind = TAtlasUnsavedKind.Commits) or (AKind = TAtlasUnsavedKind.NoUpstream) or
    (AKind = TAtlasUnsavedKind.Stashes);
end;

class function TAtlasWelcomeUnsaved.ChangesBelow(const AChanges: TArray<TAtlasVcsChange>;
  const AFolder: string): TArray<TAtlasVcsChange>;
var
  mChange: TAtlasVcsChange;
begin
  Result := nil;
  for mChange in AChanges do
  begin
    if (AFolder = '') or TAtlasProjectRecording.InFolder(mChange.Path, AFolder) or
      TAtlasProjectRecording.InFolder(mChange.OldPath, AFolder) then
    begin
      Result := Result + [mChange];
    end;
  end;
end;

class function TAtlasWelcomeUnsaved.PlacesOf(const AChanges: TArray<TAtlasVcsChange>;
  const ARows: TArray<TAtlasVcsWorkingCopyRow>): TArray<TAtlasUnsavedPlace>;
var
  mCounts: TArray<Integer>;
  mIndex: Integer;
begin
  Result := nil;
  if Length(ARows) < 2 then
  begin
    Exit;
  end;
  mCounts := TAtlasVcsWorkingCopies.Split(AChanges, ARows);
  for mIndex := 0 to High(ARows) do
  begin
    if mCounts[mIndex] > 0 then
    begin
      Result := Result + [TAtlasUnsavedPlace.Create(ARows[mIndex].Path, mCounts[mIndex])];
    end;
  end;
  if Length(Result) < 2 then
  begin
    Result := nil;
  end;
end;

class function TAtlasWelcomeUnsaved.PlacesText(const AItem: TAtlasUnsavedItem; const AName: string): string;
var
  mPlace: TAtlasUnsavedPlace;
  mText: string;
begin
  Result := '';
  for mPlace in AItem.Places do
  begin
    mText := StringReplace(mPlace.Path, '/', '\', [rfReplaceAll]);
    if mText = '' then
    begin
      mText := AName;
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + mText + ' ' + IntToStr(mPlace.Count);
  end;
end;

class function TAtlasWelcomeUnsaved.Probe(const AVcs: IAtlasVersionControl; const AFolder: string;
  ANowUtc: TDateTime; const AFileTime: TAtlasUnsavedFileTime; const AExpired: TAtlasUnsavedExpired;
  out AState: TAtlasUnsavedState): Boolean;
begin
  Result := Probe(AVcs, TAtlasUnsavedQuery.Create(AFolder, ANowUtc, AFileTime, AExpired), AState);
end;

procedure AddPlaces(var AState: TAtlasUnsavedState; const AVcs: IAtlasVersionControl;
  const AChanges: TArray<TAtlasVcsChange>);
var
  mRows: TArray<TAtlasVcsWorkingCopyRow>;
  mConflicts, mOthers: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
  mIndex: Integer;
begin
  if Length(AState.Items) = 0 then
  begin
    Exit;
  end;
  mRows := TAtlasVcsWorkingCopies.Folders(AVcs);
  if Length(mRows) < 2 then
  begin
    Exit;
  end;
  // Getrennt wie AddChanges: Konflikte für sich, alle übrigen (auch unversionierte) als Änderungen.
  mConflicts := nil;
  mOthers := nil;
  for mChange in AChanges do
  begin
    if mChange.Kind = TAtlasVcsChangeKind.Conflicted then
    begin
      mConflicts := mConflicts + [mChange];
    end
    else
    begin
      mOthers := mOthers + [mChange];
    end;
  end;
  for mIndex := 0 to High(AState.Items) do
  begin
    if AState.Items[mIndex].Kind = TAtlasUnsavedKind.Changes then
    begin
      AState.Items[mIndex].Places := TAtlasWelcomeUnsaved.PlacesOf(mOthers, mRows);
    end
    else if AState.Items[mIndex].Kind = TAtlasUnsavedKind.Conflicts then
    begin
      AState.Items[mIndex].Places := TAtlasWelcomeUnsaved.PlacesOf(mConflicts, mRows);
    end;
  end;
end;

type
  /// <summary>Branches einer Abfrage: nicht gepushte Commits und Branches ohne Upstream, mit höchstens
  /// MaxOutgoingCalls git log.</summary>
  TBranchScan = record
    Local: IAtlasVcsLocalWork;
    Expired: TAtlasUnsavedExpired;
    Calls: Integer;
    Pushable: TAtlasUnsavedItem;
    Lonely: TAtlasUnsavedItem;
    LonelyCommits: Integer;
    AllCounted: Boolean;
    function CanCall: Boolean;
    procedure AddTracked(const ABranch: TAtlasVcsBranch);
    procedure AddUntracked(const ABranch: TAtlasVcsBranch);
  end;

function TBranchScan.CanCall: Boolean;
begin
  Result := (Calls < TAtlasWelcomeUnsaved.cMaxOutgoingCalls) and not TimeUp(Expired);
end;

procedure TBranchScan.AddTracked(const ABranch: TAtlasVcsBranch);
var
  mCommits: TArray<TAtlasVcsCommit>;
begin
  if ABranch.Ahead <= 0 then
  begin
    Exit;
  end;
  Inc(Pushable.Count, ABranch.Ahead);
  Pushable.Branches := Pushable.Branches + [ABranch.Name];
  // Alter: ältester nicht gepushter Commit; ohne Abfrage der letzte Commit des Branchs.
  if CanCall and (Local.Outgoing(ABranch.Name, ABranch.Upstream, TAtlasWelcomeUnsaved.cMaxCommits,
    mCommits) = TAtlasVcsOutcome.Ok) and (Length(mCommits) > 0) then
  begin
    Pushable.Since := Older(Pushable.Since, mCommits[High(mCommits)].Date);
  end
  else
  begin
    Pushable.Since := Older(Pushable.Since, ABranch.TipDate);
  end;
  Inc(Calls);
end;

procedure TBranchScan.AddUntracked(const ABranch: TAtlasVcsBranch);
var
  mCommits: TArray<TAtlasVcsCommit>;
begin
  // Ohne (oder mit gelöschtem) Upstream: nur, wenn Commits auf keinem Remote liegen.
  if CanCall and (Local.Outgoing(ABranch.Name, '', TAtlasWelcomeUnsaved.cMaxCommits,
    mCommits) = TAtlasVcsOutcome.Ok) then
  begin
    Inc(Calls);
    if Length(mCommits) = 0 then
    begin
      Exit;
    end;
    Inc(LonelyCommits, Length(mCommits));
    Lonely.Since := Older(Lonely.Since, mCommits[High(mCommits)].Date);
  end
  else
  begin
    Inc(Calls);
    AllCounted := False;
    Lonely.Since := Older(Lonely.Since, ABranch.TipDate);
  end;
  Inc(Lonely.Count);
  Lonely.Branches := Lonely.Branches + [ABranch.Name];
end;

procedure AddBranches(var AState: TAtlasUnsavedState; const ALocal: IAtlasVcsLocalWork;
  const ABranches: TArray<TAtlasVcsBranch>; const AExpired: TAtlasUnsavedExpired);
var
  mScan: TBranchScan;
  mBranch: TAtlasVcsBranch;
begin
  mScan := Default(TBranchScan);
  mScan.Local := ALocal;
  mScan.Expired := AExpired;
  mScan.Pushable := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Commits, 0);
  mScan.Lonely := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.NoUpstream, 0);
  mScan.AllCounted := True;
  for mBranch in ABranches do
  begin
    if mBranch.Current then
    begin
      AState.Branch := mBranch.Name;
    end;
    if mBranch.Tracked then
    begin
      mScan.AddTracked(mBranch);
    end
    else
    begin
      mScan.AddUntracked(mBranch);
    end;
  end;
  if mScan.AllCounted then
  begin
    mScan.Lonely.Commits := mScan.LonelyCommits;
  end;
  AddItem(AState, mScan.Pushable);
  AddItem(AState, mScan.Lonely);
  AState.Queried := AState.Queried + [TAtlasUnsavedKind.Commits, TAtlasUnsavedKind.NoUpstream];
end;

procedure AddStashes(var AState: TAtlasUnsavedState; const AStashes: TArray<TAtlasVcsStash>);
var
  mItem: TAtlasUnsavedItem;
  mStash: TAtlasVcsStash;
begin
  mItem := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Stashes, Length(AStashes));
  for mStash in AStashes do
  begin
    // Neuester zuerst: Der letzte ist der älteste; bei gleicher Zeit gilt der spätere in der Liste.
    if (mItem.Since <= 0) or (mStash.Date <= mItem.Since) then
    begin
      mItem.Since := mStash.Date;
      mItem.Name := mStash.Message;
      mItem.Ref := mStash.Hash;
    end;
  end;
  AddItem(AState, mItem);
  AState.Queried := AState.Queried + [TAtlasUnsavedKind.Stashes];
end;

/// <summary>Branches und Stashes (Git), soweit das Zeitlimit reicht.</summary>
procedure AddLocalWork(var AState: TAtlasUnsavedState; const AVcs: IAtlasVersionControl;
  const AExpired: TAtlasUnsavedExpired);
var
  mLocal: IAtlasVcsLocalWork;
  mBranches: TArray<TAtlasVcsBranch>;
  mStashes: TArray<TAtlasVcsStash>;
begin
  if not Supports(AVcs, IAtlasVcsLocalWork, mLocal) then
  begin
    Exit;
  end;
  if not TimeUp(AExpired) and (mLocal.Branches(mBranches) = TAtlasVcsOutcome.Ok) then
  begin
    AddBranches(AState, mLocal, mBranches, AExpired);
  end;
  if not TimeUp(AExpired) and (mLocal.Stashes(mStashes) = TAtlasVcsOutcome.Ok) then
  begin
    AddStashes(AState, mStashes);
  end;
end;

/// <summary>SVN und losgelöster HEAD: Branch bzw. Pfad aus Head.</summary>
procedure AddHeadBranch(var AState: TAtlasUnsavedState; const AVcs: IAtlasVersionControl;
  const AExpired: TAtlasUnsavedExpired);
var
  mHead: TAtlasVcsHead;
begin
  if (AState.Branch = '') and not TimeUp(AExpired) and (AVcs.Head(mHead) = TAtlasVcsOutcome.Ok) then
  begin
    AState.Branch := mHead.Branch;
    if AState.Branch = '' then
    begin
      AState.Branch := mHead.ShortRevision(AVcs.Kind);
    end;
  end;
end;

/// <summary>Stand einer Arbeitskopie aus ihren Änderungen AChanges und den weiteren Abfragen.</summary>
procedure ProbeWorkingCopy(const AVcs: IAtlasVersionControl; const AQuery: TAtlasUnsavedQuery;
  const AChanges: TArray<TAtlasVcsChange>; var AState: TAtlasUnsavedState);
var
  mBelow: TArray<TAtlasVcsChange>;
begin
  AState.Known := True;
  AState.At := AQuery.NowUtc;
  AState.Kind := LowerCase(AtlasVcsKindName(AVcs.Kind));
  AState.Root := AVcs.WorkingCopy.Root;
  // Eine Arbeitskopie kann mehrere Projekte enthalten: Änderungen nur im Projektordner.
  mBelow := TAtlasWelcomeUnsaved.ChangesBelow(AChanges, AQuery.Folder);
  AddChanges(AState, mBelow, AQuery.FileTime);
  // Externals bzw. Submodule (#1292): Die Summe bleibt, die Anteile nennen die Arbeitskopien.
  if AQuery.WorkingCopies and not TimeUp(AQuery.Expired) then
  begin
    AddPlaces(AState, AVcs, mBelow);
  end;
  AState.Queried := [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts];
  AddLocalWork(AState, AVcs, AQuery.Expired);
  AddHeadBranch(AState, AVcs, AQuery.Expired);
end;

class function TAtlasWelcomeUnsaved.Probe(const AVcs: IAtlasVersionControl; const AQuery: TAtlasUnsavedQuery;
  out AState: TAtlasUnsavedState): Boolean;
var
  mOutcome: TAtlasVcsOutcome;
  mChanges: TArray<TAtlasVcsChange>;
begin
  AState := TAtlasUnsavedState.Empty;
  Result := False;
  if AVcs = nil then
  begin
    Exit;
  end;
  mOutcome := AVcs.Changes(mChanges);
  if (mOutcome = TAtlasVcsOutcome.NoWorkingCopy) or (mOutcome = TAtlasVcsOutcome.Disabled) then
  begin
    // Keine Versionsverwaltung: keine Zeile, kein Fehler.
    AState.Known := True;
    AState.At := AQuery.NowUtc;
    AState.Kind := 'none';
    AState.Queried := cAllKinds;
    Exit(True);
  end;
  Result := mOutcome = TAtlasVcsOutcome.Ok;
  if Result then
  begin
    ProbeWorkingCopy(AVcs, AQuery, mChanges, AState);
  end;
end;

function KeptIgnores(const AIgnored: TArray<TAtlasUnsavedIgnore>; ANowUtc: TDateTime): TArray<TAtlasUnsavedIgnore>;
var
  mEntry: TAtlasUnsavedIgnore;
begin
  Result := nil;
  for mEntry in AIgnored do
  begin
    if mEntry.UntilUtc > ANowUtc then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

/// <summary>Nicht mehr abgefragte Arten: letzter bekannter Stand aus AOld.</summary>
procedure AddUnqueried(var AState: TAtlasUnsavedState; const AOld: TAtlasUnsavedState);
var
  mKind: TAtlasUnsavedKind;
  mOld, mItem: TAtlasUnsavedItem;
begin
  for mKind := Low(TAtlasUnsavedKind) to High(TAtlasUnsavedKind) do
  begin
    if not (mKind in AState.Queried) and AOld.Find(mKind, mOld) and not AState.Find(mKind, mItem) then
    begin
      AState.Items := AState.Items + [mOld];
    end;
  end;
end;

/// <summary>Alter unbekannt: seit Atlas die Art zuerst sah (aus AOld, wenn ASameCopy), sonst ANowUtc.</summary>
procedure FillSince(var AState: TAtlasUnsavedState; const AOld: TAtlasUnsavedState; ASameCopy: Boolean;
  ANowUtc: TDateTime);
var
  mIndex: Integer;
  mOld: TAtlasUnsavedItem;
begin
  for mIndex := 0 to High(AState.Items) do
  begin
    if AState.Items[mIndex].Since > 0 then
    begin
      Continue;
    end;
    AState.Items[mIndex].Since := ANowUtc;
    if ASameCopy and AOld.Find(AState.Items[mIndex].Kind, mOld) and (mOld.Since > 0) then
    begin
      AState.Items[mIndex].Since := mOld.Since;
    end;
  end;
end;

class function TAtlasWelcomeUnsaved.Merge(const AOld, ANew: TAtlasUnsavedState;
  ANowUtc: TDateTime): TAtlasUnsavedState;
var
  mSameCopy: Boolean;
begin
  Result := ANew;
  // Eigene Kopie: Die Einträge werden unten geändert.
  Result.Items := Copy(ANew.Items);
  Result.Ignored := KeptIgnores(AOld.Ignored, ANowUtc);
  if not ANew.Known then
  begin
    Exit;
  end;
  mSameCopy := AOld.Known and SameText(AOld.Kind, ANew.Kind) and SameText(AOld.Root, ANew.Root);
  if mSameCopy then
  begin
    AddUnqueried(Result, AOld);
  end;
  FillSince(Result, AOld, mSameCopy, ANowUtc);
end;

class function TAtlasWelcomeUnsaved.AgeHours(ASince, ANowUtc: TDateTime): Double;
begin
  Result := 0;
  if (ASince > 0) and (ANowUtc > ASince) then
  begin
    Result := (ANowUtc - ASince) * 24;
  end;
end;

class procedure TAtlasWelcomeUnsaved.Age(ASince, ANowUtc: TDateTime; out AValue: Integer;
  out AUnit: TAtlasUnsavedAgeUnit);
var
  mMinutes: Int64;
begin
  mMinutes := Trunc(AgeHours(ASince, ANowUtc) * 60 + 1E-6);
  if mMinutes < 60 then
  begin
    AUnit := TAtlasUnsavedAgeUnit.Minutes;
    AValue := Integer(mMinutes);
    if AValue < 1 then
    begin
      AValue := 1;
    end;
  end
  else if mMinutes < 24 * 60 then
  begin
    AUnit := TAtlasUnsavedAgeUnit.Hours;
    AValue := Integer(mMinutes div 60);
  end
  else
  begin
    AUnit := TAtlasUnsavedAgeUnit.Days;
    AValue := Integer(mMinutes div (24 * 60));
  end;
end;

class function TAtlasWelcomeUnsaved.Level(ASince, ANowUtc: TDateTime;
  const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedLevel;
var
  mHours: Double;
begin
  Result := TAtlasUnsavedLevel.Fresh;
  if ASince <= 0 then
  begin
    Exit;
  end;
  mHours := AgeHours(ASince, ANowUtc) + 1E-9;
  if mHours >= AOptions.AlertHours then
  begin
    Result := TAtlasUnsavedLevel.Alert;
  end
  else if mHours >= AOptions.WarnHours then
  begin
    Result := TAtlasUnsavedLevel.Warning;
  end;
end;

/// <summary>Kommt ALeft vor ARight? Älteste zuerst, unbekanntes Alter zuletzt; dann Liste der Projekte, dann
/// Art.</summary>
function Comes(const ALeft, ARight: TAtlasUnsavedRow; ALeftIndex, ARightIndex: Integer): Boolean;
begin
  if (ALeft.Item.Since > 0) <> (ARight.Item.Since > 0) then
  begin
    Exit(ALeft.Item.Since > 0);
  end;
  if Abs(ALeft.Item.Since - ARight.Item.Since) > 1 / (24 * 3600) then
  begin
    Exit(ALeft.Item.Since < ARight.Item.Since);
  end;
  if ALeftIndex <> ARightIndex then
  begin
    Exit(ALeftIndex < ARightIndex);
  end;
  Result := Ord(ALeft.Item.Kind) < Ord(ARight.Item.Kind);
end;

type
  /// <summary>Aufbau der Ansicht: Zeilen in Reihenfolge, je Zeile der Index ihres Projekts, schon gezeigte
  /// repositoryweite Arten je Arbeitskopie.</summary>
  TViewBuild = record
    View: TAtlasUnsavedView;
    Order: TArray<Integer>;
    Seen: TArray<string>;
    NowUtc: TDateTime;
    Options: TAtlasUnsavedOptions;
    function FirstInCopy(const AState: TAtlasUnsavedState; AKind: TAtlasUnsavedKind): Boolean;
    function Hidden(const AState: TAtlasUnsavedState; const AItem: TAtlasUnsavedItem): Boolean;
    procedure AddRow(const AProject: TAtlasUnsavedProject; AProjectIndex: Integer; const AItem: TAtlasUnsavedItem);
    procedure AddProject(const AProject: TAtlasUnsavedProject; AProjectIndex: Integer);
  end;

function TViewBuild.FirstInCopy(const AState: TAtlasUnsavedState; AKind: TAtlasUnsavedKind): Boolean;
var
  mKey, mKnown: string;
begin
  Result := True;
  if not TAtlasWelcomeUnsaved.RepositoryWide(AKind) or (AState.Root = '') then
  begin
    Exit;
  end;
  // Einmal je Arbeitskopie: beim ersten (zuletzt geöffneten) Projekt.
  mKey := TAtlasProjectSummaries.NormalizedPath(AState.Root) + '|' + TAtlasWelcomeUnsaved.KindName(AKind);
  for mKnown in Seen do
  begin
    if mKnown = mKey then
    begin
      Exit(False);
    end;
  end;
  Seen := Seen + [mKey];
end;

function TViewBuild.Hidden(const AState: TAtlasUnsavedState; const AItem: TAtlasUnsavedItem): Boolean;
begin
  Result := (AState.IgnoredUntil(AItem.Kind) > NowUtc) or ((Options.MinAgeHours > 0) and
    (TAtlasWelcomeUnsaved.AgeHours(AItem.Since, NowUtc) + 1E-9 < Options.MinAgeHours));
end;

procedure TViewBuild.AddRow(const AProject: TAtlasUnsavedProject; AProjectIndex: Integer;
  const AItem: TAtlasUnsavedItem);
var
  mRow: TAtlasUnsavedRow;
  mPosition: Integer;
begin
  mRow := Default(TAtlasUnsavedRow);
  mRow.Project := AProject.Project;
  mRow.Name := TAtlasProjectSummary.Create(AProject.Project).Name;
  mRow.Branch := AProject.State.Branch;
  mRow.VcsKind := LowerCase(AProject.State.Kind);
  mRow.Item := AItem;
  mRow.Level := TAtlasWelcomeUnsaved.Level(AItem.Since, NowUtc, Options);
  mRow.Stale := not AProject.Fresh;
  mRow.At := AProject.State.At;
  // Einfügen nach Reihenfolge (stabil).
  mPosition := Length(View.Rows);
  while (mPosition > 0) and Comes(mRow, View.Rows[mPosition - 1], AProjectIndex, Order[mPosition - 1]) do
  begin
    Dec(mPosition);
  end;
  Insert(mRow, View.Rows, mPosition);
  Insert(AProjectIndex, Order, mPosition);
end;

procedure TViewBuild.AddProject(const AProject: TAtlasUnsavedProject; AProjectIndex: Integer);
var
  mItem: TAtlasUnsavedItem;
begin
  View.Querying := View.Querying or AProject.Querying;
  View.Known := View.Known or AProject.State.Known;
  if not AProject.State.InWorkingCopy then
  begin
    Exit;
  end;
  for mItem in AProject.State.Items do
  begin
    if (mItem.Count <= 0) or not FirstInCopy(AProject.State, mItem.Kind) then
    begin
      Continue;
    end;
    if Hidden(AProject.State, mItem) then
    begin
      Inc(View.Hidden);
    end
    else
    begin
      AddRow(AProject, AProjectIndex, mItem);
    end;
  end;
end;

class function TAtlasWelcomeUnsaved.View(const AProjects: TArray<TAtlasUnsavedProject>; ANowUtc: TDateTime;
  const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedView;
var
  mBuild: TViewBuild;
  mIndex: Integer;
begin
  mBuild := Default(TViewBuild);
  mBuild.NowUtc := ANowUtc;
  mBuild.Options := AOptions;
  for mIndex := 0 to High(AProjects) do
  begin
    mBuild.AddProject(AProjects[mIndex], mIndex);
  end;
  Result := mBuild.View;
end;

class function TAtlasWelcomeUnsaved.Tomorrow(ANowLocal: TDateTime): TDateTime;
begin
  Result := Trunc(ANowLocal) + 1;
end;

class procedure TAtlasWelcomeUnsaved.Ignore(var AState: TAtlasUnsavedState; AKind: TAtlasUnsavedKind;
  AUntilUtc: TDateTime);
var
  mIndex: Integer;
  mEntry: TAtlasUnsavedIgnore;
begin
  for mIndex := 0 to High(AState.Ignored) do
  begin
    if AState.Ignored[mIndex].Kind = AKind then
    begin
      AState.Ignored[mIndex].UntilUtc := AUntilUtc;
      Exit;
    end;
  end;
  mEntry.Kind := AKind;
  mEntry.UntilUtc := AUntilUtc;
  AState.Ignored := AState.Ignored + [mEntry];
end;

{ JSON }

function ParseObject(const AJson: string): TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  try
    Result := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Result := nil;
  end;
end;

procedure AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

function PlacesJson(const APlaces: TArray<TAtlasUnsavedPlace>): TJSONArray;
var
  mPlace: TAtlasUnsavedPlace;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mPlace in APlaces do
  begin
    mEntry := TJSONObject.Create;
    Result.AddElement(mEntry);
    mEntry.AddPair('path', mPlace.Path);
    mEntry.AddPair('count', TJSONNumber.Create(mPlace.Count));
  end;
end;

function NamesJson(const ANames: TArray<string>): TJSONArray;
var
  mName: string;
begin
  Result := TJSONArray.Create;
  for mName in ANames do
  begin
    Result.Add(mName);
  end;
end;

function ItemJson(const AItem: TAtlasUnsavedItem): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', TAtlasWelcomeUnsaved.KindName(AItem.Kind));
  Result.AddPair('count', TJSONNumber.Create(AItem.Count));
  if AItem.Kind = TAtlasUnsavedKind.Changes then
  begin
    Result.AddPair('modified', TJSONNumber.Create(AItem.Modified));
    Result.AddPair('added', TJSONNumber.Create(AItem.Added));
    Result.AddPair('deleted', TJSONNumber.Create(AItem.Deleted));
  end;
  if AItem.Kind = TAtlasUnsavedKind.NoUpstream then
  begin
    Result.AddPair('commits', TJSONNumber.Create(AItem.Commits));
  end;
  if AItem.Since > 0 then
  begin
    Result.AddPair('since', TAtlasProjectSummaries.TimeText(AItem.Since));
  end;
  if Length(AItem.Branches) > 0 then
  begin
    Result.AddPair('branches', NamesJson(AItem.Branches));
  end;
  AddText(Result, 'name', AItem.Name);
  AddText(Result, 'ref', AItem.Ref);
  if Length(AItem.Places) > 0 then
  begin
    Result.AddPair('places', PlacesJson(AItem.Places));
  end;
end;

function SectionJson(const AState: TAtlasUnsavedState): TJSONObject;
var
  mItems: TJSONArray;
  mIgnore: TJSONObject;
  mItem: TAtlasUnsavedItem;
  mIgnored: TAtlasUnsavedIgnore;
begin
  Result := TJSONObject.Create;
  if AState.At > 0 then
  begin
    Result.AddPair('at', TAtlasProjectSummaries.TimeText(AState.At));
  end;
  Result.AddPair('kind', AState.Kind);
  AddText(Result, 'root', AState.Root);
  AddText(Result, 'branch', AState.Branch);
  mItems := TJSONArray.Create;
  Result.AddPair('items', mItems);
  for mItem in AState.Items do
  begin
    mItems.AddElement(ItemJson(mItem));
  end;
  if Length(AState.Ignored) > 0 then
  begin
    mIgnore := TJSONObject.Create;
    Result.AddPair('ignore', mIgnore);
    for mIgnored in AState.Ignored do
    begin
      mIgnore.AddPair(TAtlasWelcomeUnsaved.KindName(mIgnored.Kind),
        TAtlasProjectSummaries.TimeText(mIgnored.UntilUtc));
    end;
  end;
end;

function BranchesOf(AValue: TJSONValue): TArray<string>;
var
  mIndex: Integer;
  mName: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mName := TJSONArray(AValue).Items[mIndex];
    if mName is TJSONString then
    begin
      Result := Result + [TJSONString(mName).Value];
    end;
  end;
end;

function PlacesFrom(AValue: TJSONValue): TArray<TAtlasUnsavedPlace>;
var
  mIndex: Integer;
  mPlace: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mPlace := TJSONArray(AValue).Items[mIndex];
    if mPlace is TJSONObject then
    begin
      Result := Result + [TAtlasUnsavedPlace.Create(TJsonRead.Text(TJSONObject(mPlace), 'path'),
        TJsonRead.IntOr(TJSONObject(mPlace), 'count', 0))];
    end;
  end;
end;

/// <summary>Eintrag aus „items“; False ohne Objekt oder bei unbekannter Art (spätere Fassungen).</summary>
function ItemOf(AElement: TJSONValue; out AItem: TAtlasUnsavedItem): Boolean;
var
  mEntry: TJSONObject;
  mKind: TAtlasUnsavedKind;
begin
  AItem := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Changes, 0);
  Result := (AElement is TJSONObject) and TAtlasWelcomeUnsaved.KindOf(TJsonRead.Text(TJSONObject(AElement), 'kind'), mKind);
  if not Result then
  begin
    Exit;
  end;
  mEntry := TJSONObject(AElement);
  AItem := TAtlasUnsavedItem.Create(mKind, TJsonRead.IntOr(mEntry, 'count', 0));
  AItem.Modified := TJsonRead.IntOr(mEntry, 'modified', 0);
  AItem.Added := TJsonRead.IntOr(mEntry, 'added', 0);
  AItem.Deleted := TJsonRead.IntOr(mEntry, 'deleted', 0);
  AItem.Commits := TJsonRead.IntOr(mEntry, 'commits', -1);
  AItem.Since := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(mEntry, 'since'));
  AItem.Name := TJsonRead.Text(mEntry, 'name');
  AItem.Ref := TJsonRead.Text(mEntry, 'ref');
  AItem.Branches := BranchesOf(mEntry.GetValue('branches'));
  AItem.Places := PlacesFrom(mEntry.GetValue('places'));
end;

function ItemsOf(AValue: TJSONValue): TArray<TAtlasUnsavedItem>;
var
  mIndex: Integer;
  mItem: TAtlasUnsavedItem;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    if ItemOf(TJSONArray(AValue).Items[mIndex], mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

function IgnoredOf(AIgnore: TJSONObject): TArray<TAtlasUnsavedIgnore>;
var
  mIndex: Integer;
  mPair: TJSONPair;
  mIgnored: TAtlasUnsavedIgnore;
begin
  Result := nil;
  if AIgnore = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AIgnore.Count - 1 do
  begin
    mPair := AIgnore.Pairs[mIndex];
    if TAtlasWelcomeUnsaved.KindOf(mPair.JsonString.Value, mIgnored.Kind) and (mPair.JsonValue is TJSONString) then
    begin
      mIgnored.UntilUtc := TAtlasProjectSummaries.TimeOf(TJSONString(mPair.JsonValue).Value);
      if mIgnored.UntilUtc > 0 then
      begin
        Result := Result + [mIgnored];
      end;
    end;
  end;
end;

function StateOf(ASection: TJSONObject; out AState: TAtlasUnsavedState): Boolean;
begin
  AState := TAtlasUnsavedState.Empty;
  Result := ASection <> nil;
  if not Result then
  begin
    Exit;
  end;
  AState.Known := True;
  AState.At := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(ASection, 'at'));
  AState.Kind := LowerCase(TJsonRead.Text(ASection, 'kind'));
  AState.Root := TJsonRead.Text(ASection, 'root');
  AState.Branch := TJsonRead.Text(ASection, 'branch');
  AState.Items := ItemsOf(ASection.GetValue('items'));
  AState.Ignored := IgnoredOf(TJsonRead.Obj(ASection, 'ignore'));
end;

class function TAtlasWelcomeUnsaved.ToJson(const AState: TAtlasUnsavedState): string;
var
  mSection: TJSONObject;
begin
  mSection := SectionJson(AState);
  try
    Result := mSection.ToJSON;
  finally
    mSection.Free;
  end;
end;

class function TAtlasWelcomeUnsaved.FromJson(const AJson: string; out AState: TAtlasUnsavedState): Boolean;
var
  mValue: TJSONValue;
begin
  AState := TAtlasUnsavedState.Empty;
  mValue := ParseObject(AJson);
  try
    Result := (mValue is TJSONObject) and StateOf(TJSONObject(mValue), AState);
  finally
    mValue.Free;
  end;
end;

class function TAtlasWelcomeUnsaved.Read(const ASummary: TAtlasProjectSummary;
  out AState: TAtlasUnsavedState): Boolean;
var
  mValue: TJSONValue;
begin
  AState := TAtlasUnsavedState.Empty;
  mValue := ParseObject(ASummary.Raw);
  try
    Result := (mValue is TJSONObject) and StateOf(TJsonRead.Obj(TJSONObject(mValue), cSectionName), AState);
  finally
    mValue.Free;
  end;
end;

class procedure TAtlasWelcomeUnsaved.Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasUnsavedState);
var
  mValue: TJSONValue;
  mOriginal, mRoot: TJSONObject;
  mIndex: Integer;
  mPair: TJSONPair;
begin
  mValue := ParseObject(ASummary.Raw);
  mRoot := TJSONObject.Create;
  try
    // Alles außer dem Abschnitt übernehmen; ohne Datei schreibt TAtlasProjectSummaries.ToJson die übrigen
    // Felder aus dem Datensatz.
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
    mRoot.AddPair(cSectionName, SectionJson(AState));
    ASummary.Raw := mRoot.ToJSON;
  finally
    mRoot.Free;
    mValue.Free;
  end;
end;

function HasName(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if mName = AName then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Remote für Branches ohne eigenes (nur NoUpstream): das einzige, sonst "origin", sonst ''.</summary>
function FallbackRemote(const ALocal: IAtlasVcsLocalWork; const AItem: TAtlasUnsavedItem;
  out ARemote: string): TAtlasVcsOutcome;
var
  mRemotes: TArray<string>;
begin
  ARemote := '';
  Result := TAtlasVcsOutcome.Ok;
  if AItem.Kind <> TAtlasUnsavedKind.NoUpstream then
  begin
    Exit;
  end;
  Result := ALocal.Remotes(mRemotes);
  if (Result = TAtlasVcsOutcome.Ok) and (Length(mRemotes) = 1) then
  begin
    ARemote := mRemotes[0];
  end
  else if (Result = TAtlasVcsOutcome.Ok) and HasName(mRemotes, 'origin') then
  begin
    ARemote := 'origin';
  end;
end;

/// <summary>Ziel für ABranch; False, wenn er nicht gepusht wird. Commits: nur, was jetzt noch vor dem Upstream
/// liegt; NoUpstream: auf sein Remote oder AFallback, mit --set-upstream.</summary>
function PlanFor(const ABranch: TAtlasVcsBranch; const AItem: TAtlasUnsavedItem; const AFallback: string;
  out APlan: TAtlasUnsavedPush): Boolean;
begin
  APlan := Default(TAtlasUnsavedPush);
  APlan.Branch := ABranch.Name;
  APlan.Remote := ABranch.Remote;
  if AItem.Kind = TAtlasUnsavedKind.Commits then
  begin
    APlan.RemoteRef := ABranch.RemoteRef;
    Result := ABranch.Tracked and (ABranch.Ahead > 0) and (ABranch.Remote <> '') and (ABranch.RemoteRef <> '');
  end
  else
  begin
    if APlan.Remote = '' then
    begin
      APlan.Remote := AFallback;
    end;
    APlan.RemoteRef := 'refs/heads/' + ABranch.Name;
    APlan.SetUpstream := True;
    Result := not ABranch.Tracked and (APlan.Remote <> '');
  end;
end;

/// <summary>Commits für APlan holen und den Plan anhängen, wenn es welche gibt.</summary>
function AddPlan(const ALocal: IAtlasVcsLocalWork; const ABranch: TAtlasVcsBranch; var APlan: TAtlasUnsavedPush;
  var APlans: TArray<TAtlasUnsavedPush>): TAtlasVcsOutcome;
var
  mUpstream: string;
  mCommits: TArray<TAtlasVcsCommit>;
begin
  mUpstream := '';
  if not APlan.SetUpstream then
  begin
    mUpstream := ABranch.Upstream;
  end;
  Result := ALocal.Outgoing(ABranch.Name, mUpstream, TAtlasWelcomeUnsaved.cPushListMax + 1, mCommits);
  if (Result = TAtlasVcsOutcome.Ok) and (Length(mCommits) > 0) then
  begin
    APlan.More := Length(mCommits) > TAtlasWelcomeUnsaved.cPushListMax;
    if APlan.More then
    begin
      SetLength(mCommits, TAtlasWelcomeUnsaved.cPushListMax);
    end;
    APlan.Commits := mCommits;
    APlans := APlans + [APlan];
  end;
end;

class function TAtlasWelcomeUnsaved.PushPlans(const ALocal: IAtlasVcsLocalWork; const AItem: TAtlasUnsavedItem;
  out APlans: TArray<TAtlasUnsavedPush>): TAtlasVcsOutcome;
var
  mBranches: TArray<TAtlasVcsBranch>;
  mFallback: string;
  mPlan: TAtlasUnsavedPush;
  mIndex: Integer;
begin
  APlans := nil;
  if (ALocal = nil) or not AItem.CanPush then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Result := ALocal.Branches(mBranches);
  if Result = TAtlasVcsOutcome.Ok then
  begin
    Result := FallbackRemote(ALocal, AItem, mFallback);
  end;
  mIndex := 0;
  while (Result = TAtlasVcsOutcome.Ok) and (mIndex <= High(mBranches)) do
  begin
    if HasName(AItem.Branches, mBranches[mIndex].Name) and PlanFor(mBranches[mIndex], AItem, mFallback, mPlan) then
    begin
      Result := AddPlan(ALocal, mBranches[mIndex], mPlan, APlans);
    end;
    Inc(mIndex);
  end;
  if Result <> TAtlasVcsOutcome.Ok then
  begin
    APlans := nil;
  end;
end;

end.
