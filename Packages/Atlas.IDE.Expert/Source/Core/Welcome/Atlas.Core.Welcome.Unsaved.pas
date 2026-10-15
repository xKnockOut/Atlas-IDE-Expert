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

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Vcs.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasUnsavedKind = (Changes, Conflicts, Commits, NoUpstream, Stashes);
  /// <summary>Ampel: Fresh grün, Warning gelb, Alert rot.</summary>
  TAtlasUnsavedLevel = (Fresh, Warning, Alert);
  TAtlasUnsavedAgeUnit = (Minutes, Hours, Days);
{$SCOPEDENUMS OFF}
  TAtlasUnsavedKinds = set of TAtlasUnsavedKind;

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
    /// <summary>Neueste zuerst, höchstens TAtlasWelcomeUnsaved.PushListMax.</summary>
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

  TAtlasWelcomeUnsaved = class
  public const
    /// <summary>Abschnitt in der Projekt-Zusammenfassung.</summary>
    SectionName = 'unsaved';
    DefaultMinAgeHours = 0;
    DefaultWarnHours = 24;
    DefaultAlertHours = 72;
    /// <summary>Obergrenze der Stunden-Einstellungen (ein Jahr).</summary>
    MaxHours = 8760;
    /// <summary>Zeitlimit je Projekt; danach startet die Abfrage keinen weiteren Aufruf.</summary>
    TimeLimitMs = 2000;
    /// <summary>Zeitlimit je Aufruf.</summary>
    CallTimeoutMs = 1000;
    /// <summary>Höchstens so viele git log je Projekt (Alter der Commits).</summary>
    MaxOutgoingCalls = 6;
    /// <summary>Höchstens so viele Commits je Branch für das Alter.</summary>
    MaxCommits = 1000;
    /// <summary>Höchstens so viele Commits je Branch im Dialog „Push …“.</summary>
    PushListMax = 50;
    /// <summary>Zeitlimit für git push.</summary>
    PushTimeoutMs = 120000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite dasselbe Projekt erneut ab.</summary>
    RefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet.</summary>
    QueryLimitMs = 8000;
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
      out AState: TAtlasUnsavedState): Boolean; static;
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
  Atlas.Core.Welcome.Projects;

const
  KindNames: array[TAtlasUnsavedKind] of string = ('changes', 'conflicts', 'commits', 'noUpstream', 'stashes');
  AllKinds: TAtlasUnsavedKinds = [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts,
    TAtlasUnsavedKind.Commits, TAtlasUnsavedKind.NoUpstream, TAtlasUnsavedKind.Stashes];

{ TAtlasUnsavedItem }

class function TAtlasUnsavedItem.Create(AKind: TAtlasUnsavedKind; ACount: Integer): TAtlasUnsavedItem;
begin
  Result := Default(TAtlasUnsavedItem);
  Result.Kind := AKind;
  Result.Count := ACount;
  Result.Commits := -1;
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
  Item: TAtlasUnsavedItem;
begin
  AItem := TAtlasUnsavedItem.Create(AKind, 0);
  Result := False;
  for Item in Items do
    if Item.Kind = AKind then
    begin
      AItem := Item;
      Exit(True);
    end;
end;

function TAtlasUnsavedState.IgnoredUntil(AKind: TAtlasUnsavedKind): TDateTime;
var
  Entry: TAtlasUnsavedIgnore;
begin
  Result := 0;
  for Entry in Ignored do
    if (Entry.Kind = AKind) and (Entry.UntilUtc > Result) then
      Result := Entry.UntilUtc;
end;

{ TAtlasUnsavedOptions }

class function TAtlasUnsavedOptions.Create(AMinAgeHours, AWarnHours, AAlertHours: Integer): TAtlasUnsavedOptions;
begin
  Result.MinAgeHours := AMinAgeHours;
  Result.WarnHours := AWarnHours;
  Result.AlertHours := AAlertHours;
end;

{ TAtlasUnsavedView }

function TAtlasUnsavedView.Clean: Boolean;
begin
  Result := Length(Rows) = 0;
end;

{ TAtlasUnsavedPush }

function TAtlasUnsavedPush.Target: string;
var
  Name: string;
begin
  Name := RemoteRef;
  if Copy(Name, 1, 11) = 'refs/heads/' then
    Name := Copy(Name, 12, MaxInt);
  Result := Remote + '/' + Name;
end;

{ Hilfen }

function Older(ACurrent, ACandidate: TDateTime): TDateTime;
begin
  // 0 = unbekannt zählt nicht.
  Result := ACurrent;
  if (ACandidate > 0) and ((Result <= 0) or (ACandidate < Result)) then
    Result := ACandidate;
end;

function FileSince(const AFileTime: TAtlasUnsavedFileTime; const APath: string): TDateTime;
var
  Stamp: TDateTime;
begin
  Result := 0;
  if Assigned(AFileTime) and (APath <> '') and AFileTime(APath, Stamp) then
    Result := Stamp;
end;

function TimeUp(const AExpired: TAtlasUnsavedExpired): Boolean;
begin
  Result := Assigned(AExpired) and AExpired();
end;

procedure AddItem(var AState: TAtlasUnsavedState; const AItem: TAtlasUnsavedItem);
begin
  if AItem.Count > 0 then
    AState.Items := AState.Items + [AItem];
end;

procedure AddChanges(var AState: TAtlasUnsavedState; const AChanges: TArray<TAtlasVcsChange>;
  const AFileTime: TAtlasUnsavedFileTime);
var
  Change: TAtlasVcsChange;
  Changes, Conflicts: TAtlasUnsavedItem;
begin
  Changes := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Changes, 0);
  Conflicts := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Conflicts, 0);
  for Change in AChanges do
    case Change.Kind of
      TAtlasVcsChangeKind.Conflicted:
        begin
          Inc(Conflicts.Count);
          Conflicts.Since := Older(Conflicts.Since, FileSince(AFileTime, Change.Path));
        end;
      TAtlasVcsChangeKind.Added, TAtlasVcsChangeKind.Untracked:
        begin
          Inc(Changes.Count);
          Inc(Changes.Added);
          Changes.Since := Older(Changes.Since, FileSince(AFileTime, Change.Path));
        end;
      TAtlasVcsChangeKind.Deleted, TAtlasVcsChangeKind.Missing:
        begin
          // Keine Datei, keine Zeit: Alter dann über Merge.
          Inc(Changes.Count);
          Inc(Changes.Deleted);
        end;
    else
      Inc(Changes.Count);
      Inc(Changes.Modified);
      Changes.Since := Older(Changes.Since, FileSince(AFileTime, Change.Path));
    end;
  AddItem(AState, Changes);
  AddItem(AState, Conflicts);
end;

{ TAtlasWelcomeUnsaved }

class function TAtlasWelcomeUnsaved.KindName(AKind: TAtlasUnsavedKind): string;
begin
  Result := KindNames[AKind];
end;

class function TAtlasWelcomeUnsaved.KindOf(const AText: string; out AKind: TAtlasUnsavedKind): Boolean;
var
  Kind: TAtlasUnsavedKind;
begin
  AKind := TAtlasUnsavedKind.Changes;
  for Kind := Low(TAtlasUnsavedKind) to High(TAtlasUnsavedKind) do
    if SameText(KindNames[Kind], Trim(AText)) then
    begin
      AKind := Kind;
      Exit(True);
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
  Change: TAtlasVcsChange;
begin
  Result := nil;
  for Change in AChanges do
    if (AFolder = '') or TAtlasWelcomeProjects.InFolder(Change.Path, AFolder) or
      TAtlasWelcomeProjects.InFolder(Change.OldPath, AFolder) then
      Result := Result + [Change];
end;

class function TAtlasWelcomeUnsaved.Probe(const AVcs: IAtlasVersionControl; const AFolder: string;
  ANowUtc: TDateTime; const AFileTime: TAtlasUnsavedFileTime; const AExpired: TAtlasUnsavedExpired;
  out AState: TAtlasUnsavedState): Boolean;
var
  Outcome: TAtlasVcsOutcome;
  Changes: TArray<TAtlasVcsChange>;
  Local: IAtlasVcsLocalWork;
  Branches: TArray<TAtlasVcsBranch>;
  Branch: TAtlasVcsBranch;
  Stashes: TArray<TAtlasVcsStash>;
  Stash: TAtlasVcsStash;
  Commits: TArray<TAtlasVcsCommit>;
  Head: TAtlasVcsHead;
  Pushable, Lonely, StashItem: TAtlasUnsavedItem;
  Calls, LonelyCommits: Integer;
  AllCounted: Boolean;
begin
  AState := TAtlasUnsavedState.Empty;
  Result := False;
  if AVcs = nil then
    Exit;
  Outcome := AVcs.Changes(Changes);
  if (Outcome = TAtlasVcsOutcome.NoWorkingCopy) or (Outcome = TAtlasVcsOutcome.Disabled) then
  begin
    // Keine Versionsverwaltung: keine Zeile, kein Fehler.
    AState.Known := True;
    AState.At := ANowUtc;
    AState.Kind := 'none';
    AState.Queried := AllKinds;
    Exit(True);
  end;
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  AState.Known := True;
  AState.At := ANowUtc;
  AState.Kind := LowerCase(AtlasVcsKindName(AVcs.Kind));
  AState.Root := AVcs.WorkingCopy.Root;
  // Eine Arbeitskopie kann mehrere Projekte enthalten: Änderungen nur im Projektordner.
  AddChanges(AState, ChangesBelow(Changes, AFolder), AFileTime);
  AState.Queried := [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts];
  Result := True;
  if Supports(AVcs, IAtlasVcsLocalWork, Local) and not TimeUp(AExpired) and
    (Local.Branches(Branches) = TAtlasVcsOutcome.Ok) then
  begin
    Pushable := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Commits, 0);
    Lonely := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.NoUpstream, 0);
    LonelyCommits := 0;
    AllCounted := True;
    Calls := 0;
    for Branch in Branches do
    begin
      if Branch.Current then
        AState.Branch := Branch.Name;
      if Branch.Tracked then
      begin
        if Branch.Ahead <= 0 then
          Continue;
        Inc(Pushable.Count, Branch.Ahead);
        Pushable.Branches := Pushable.Branches + [Branch.Name];
        // Alter: ältester nicht gepushter Commit; ohne Abfrage der letzte Commit des Branchs.
        if (Calls < MaxOutgoingCalls) and not TimeUp(AExpired) and
          (Local.Outgoing(Branch.Name, Branch.Upstream, MaxCommits, Commits) = TAtlasVcsOutcome.Ok) and
          (Length(Commits) > 0) then
          Pushable.Since := Older(Pushable.Since, Commits[High(Commits)].Date)
        else
          Pushable.Since := Older(Pushable.Since, Branch.TipDate);
        Inc(Calls);
      end
      else
      begin
        // Ohne (oder mit gelöschtem) Upstream: nur, wenn Commits auf keinem Remote liegen.
        if (Calls < MaxOutgoingCalls) and not TimeUp(AExpired) and
          (Local.Outgoing(Branch.Name, '', MaxCommits, Commits) = TAtlasVcsOutcome.Ok) then
        begin
          Inc(Calls);
          if Length(Commits) = 0 then
            Continue;
          Inc(LonelyCommits, Length(Commits));
          Lonely.Since := Older(Lonely.Since, Commits[High(Commits)].Date);
        end
        else
        begin
          Inc(Calls);
          AllCounted := False;
          Lonely.Since := Older(Lonely.Since, Branch.TipDate);
        end;
        Inc(Lonely.Count);
        Lonely.Branches := Lonely.Branches + [Branch.Name];
      end;
    end;
    if AllCounted then
      Lonely.Commits := LonelyCommits;
    AddItem(AState, Pushable);
    AddItem(AState, Lonely);
    AState.Queried := AState.Queried + [TAtlasUnsavedKind.Commits, TAtlasUnsavedKind.NoUpstream];
  end;
  if (Local <> nil) and not TimeUp(AExpired) and (Local.Stashes(Stashes) = TAtlasVcsOutcome.Ok) then
  begin
    StashItem := TAtlasUnsavedItem.Create(TAtlasUnsavedKind.Stashes, Length(Stashes));
    for Stash in Stashes do
      // Neuester zuerst: Der letzte ist der älteste; bei gleicher Zeit gilt der spätere in der Liste.
      if (StashItem.Since <= 0) or (Stash.Date <= StashItem.Since) then
      begin
        StashItem.Since := Stash.Date;
        StashItem.Name := Stash.Message;
        StashItem.Ref := Stash.Hash;
      end;
    AddItem(AState, StashItem);
    AState.Queried := AState.Queried + [TAtlasUnsavedKind.Stashes];
  end;
  // SVN und losgelöster HEAD: Branch bzw. Pfad aus Head.
  if (AState.Branch = '') and not TimeUp(AExpired) and (AVcs.Head(Head) = TAtlasVcsOutcome.Ok) then
  begin
    AState.Branch := Head.Branch;
    if AState.Branch = '' then
      AState.Branch := Head.ShortRevision(AVcs.Kind);
  end;
end;

class function TAtlasWelcomeUnsaved.Merge(const AOld, ANew: TAtlasUnsavedState;
  ANowUtc: TDateTime): TAtlasUnsavedState;
var
  Kind: TAtlasUnsavedKind;
  Old, Item: TAtlasUnsavedItem;
  Index: Integer;
  Entry: TAtlasUnsavedIgnore;
  SameCopy: Boolean;
begin
  Result := ANew;
  // Eigene Kopie: Die Einträge werden unten geändert.
  Result.Items := Copy(ANew.Items);
  Result.Ignored := nil;
  for Entry in AOld.Ignored do
    if Entry.UntilUtc > ANowUtc then
      Result.Ignored := Result.Ignored + [Entry];
  if not ANew.Known then
    Exit;
  SameCopy := AOld.Known and SameText(AOld.Kind, ANew.Kind) and SameText(AOld.Root, ANew.Root);
  // Nicht mehr abgefragte Arten: letzter bekannter Stand.
  if SameCopy then
    for Kind := Low(TAtlasUnsavedKind) to High(TAtlasUnsavedKind) do
      if not (Kind in ANew.Queried) and AOld.Find(Kind, Old) and not Result.Find(Kind, Item) then
        Result.Items := Result.Items + [Old];
  for Index := 0 to High(Result.Items) do
    if Result.Items[Index].Since <= 0 then
    begin
      // Alter unbekannt: seit Atlas die Art zuerst sah.
      if SameCopy and AOld.Find(Result.Items[Index].Kind, Old) and (Old.Since > 0) then
        Result.Items[Index].Since := Old.Since
      else
        Result.Items[Index].Since := ANowUtc;
    end;
end;

class function TAtlasWelcomeUnsaved.AgeHours(ASince, ANowUtc: TDateTime): Double;
begin
  Result := 0;
  if (ASince > 0) and (ANowUtc > ASince) then
    Result := (ANowUtc - ASince) * 24;
end;

class procedure TAtlasWelcomeUnsaved.Age(ASince, ANowUtc: TDateTime; out AValue: Integer;
  out AUnit: TAtlasUnsavedAgeUnit);
var
  Minutes: Int64;
begin
  Minutes := Trunc(AgeHours(ASince, ANowUtc) * 60 + 1E-6);
  if Minutes < 60 then
  begin
    AUnit := TAtlasUnsavedAgeUnit.Minutes;
    AValue := Minutes;
    if AValue < 1 then
      AValue := 1;
  end
  else if Minutes < 24 * 60 then
  begin
    AUnit := TAtlasUnsavedAgeUnit.Hours;
    AValue := Minutes div 60;
  end
  else
  begin
    AUnit := TAtlasUnsavedAgeUnit.Days;
    AValue := Minutes div (24 * 60);
  end;
end;

class function TAtlasWelcomeUnsaved.Level(ASince, ANowUtc: TDateTime;
  const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedLevel;
var
  Hours: Double;
begin
  Result := TAtlasUnsavedLevel.Fresh;
  if ASince <= 0 then
    Exit;
  Hours := AgeHours(ASince, ANowUtc) + 1E-9;
  if Hours >= AOptions.AlertHours then
    Result := TAtlasUnsavedLevel.Alert
  else if Hours >= AOptions.WarnHours then
    Result := TAtlasUnsavedLevel.Warning;
end;

/// <summary>Kommt ALeft vor ARight? Älteste zuerst, unbekanntes Alter zuletzt; dann Liste der Projekte, dann
/// Art.</summary>
function Comes(const ALeft, ARight: TAtlasUnsavedRow; ALeftIndex, ARightIndex: Integer): Boolean;
begin
  if (ALeft.Item.Since > 0) <> (ARight.Item.Since > 0) then
    Exit(ALeft.Item.Since > 0);
  if Abs(ALeft.Item.Since - ARight.Item.Since) > 1 / (24 * 3600) then
    Exit(ALeft.Item.Since < ARight.Item.Since);
  if ALeftIndex <> ARightIndex then
    Exit(ALeftIndex < ARightIndex);
  Result := Ord(ALeft.Item.Kind) < Ord(ARight.Item.Kind);
end;

class function TAtlasWelcomeUnsaved.View(const AProjects: TArray<TAtlasUnsavedProject>; ANowUtc: TDateTime;
  const AOptions: TAtlasUnsavedOptions): TAtlasUnsavedView;
var
  Seen: TArray<string>;
  Order: TArray<Integer>;
  ProjectIndex, Position: Integer;
  Project: TAtlasUnsavedProject;
  Item: TAtlasUnsavedItem;
  Row: TAtlasUnsavedRow;
  Key, Known: string;
  Duplicate: Boolean;
  Summary: TAtlasProjectSummary;
begin
  Result := Default(TAtlasUnsavedView);
  Seen := nil;
  Order := nil;
  for ProjectIndex := 0 to High(AProjects) do
  begin
    Project := AProjects[ProjectIndex];
    if Project.Querying then
      Result.Querying := True;
    if Project.State.Known then
      Result.Known := True;
    if not Project.State.InWorkingCopy then
      Continue;
    for Item in Project.State.Items do
    begin
      if Item.Count <= 0 then
        Continue;
      if RepositoryWide(Item.Kind) and (Project.State.Root <> '') then
      begin
        // Einmal je Arbeitskopie: beim ersten (zuletzt geöffneten) Projekt.
        Key := TAtlasProjectSummaries.NormalizedPath(Project.State.Root) + '|' + KindName(Item.Kind);
        Duplicate := False;
        for Known in Seen do
          if Known = Key then
            Duplicate := True;
        if Duplicate then
          Continue;
        Seen := Seen + [Key];
      end;
      if (Project.State.IgnoredUntil(Item.Kind) > ANowUtc) or
        ((AOptions.MinAgeHours > 0) and (AgeHours(Item.Since, ANowUtc) + 1E-9 < AOptions.MinAgeHours)) then
      begin
        Inc(Result.Hidden);
        Continue;
      end;
      Row := Default(TAtlasUnsavedRow);
      Row.Project := Project.Project;
      Summary := TAtlasProjectSummary.Create(Project.Project);
      Row.Name := Summary.Name;
      Row.Branch := Project.State.Branch;
      Row.VcsKind := LowerCase(Project.State.Kind);
      Row.Item := Item;
      Row.Level := Level(Item.Since, ANowUtc, AOptions);
      Row.Stale := not Project.Fresh;
      Row.At := Project.State.At;
      // Einfügen nach Reihenfolge (stabil).
      Position := Length(Result.Rows);
      while (Position > 0) and Comes(Row, Result.Rows[Position - 1], ProjectIndex, Order[Position - 1]) do
        Dec(Position);
      Insert(Row, Result.Rows, Position);
      Insert(ProjectIndex, Order, Position);
    end;
  end;
end;

class function TAtlasWelcomeUnsaved.Tomorrow(ANowLocal: TDateTime): TDateTime;
begin
  Result := Trunc(ANowLocal) + 1;
end;

class procedure TAtlasWelcomeUnsaved.Ignore(var AState: TAtlasUnsavedState; AKind: TAtlasUnsavedKind;
  AUntilUtc: TDateTime);
var
  Index: Integer;
  Entry: TAtlasUnsavedIgnore;
begin
  for Index := 0 to High(AState.Ignored) do
    if AState.Ignored[Index].Kind = AKind then
    begin
      AState.Ignored[Index].UntilUtc := AUntilUtc;
      Exit;
    end;
  Entry.Kind := AKind;
  Entry.UntilUtc := AUntilUtc;
  AState.Ignored := AState.Ignored + [Entry];
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

function SectionJson(const AState: TAtlasUnsavedState): TJSONObject;
var
  Items, Names: TJSONArray;
  Entry, Ignore: TJSONObject;
  Item: TAtlasUnsavedItem;
  Name: string;
  Ignored: TAtlasUnsavedIgnore;
begin
  Result := TJSONObject.Create;
  if AState.At > 0 then
    Result.AddPair('at', TAtlasProjectSummaries.TimeText(AState.At));
  Result.AddPair('kind', AState.Kind);
  if AState.Root <> '' then
    Result.AddPair('root', AState.Root);
  if AState.Branch <> '' then
    Result.AddPair('branch', AState.Branch);
  Items := TJSONArray.Create;
  Result.AddPair('items', Items);
  for Item in AState.Items do
  begin
    Entry := TJSONObject.Create;
    Items.AddElement(Entry);
    Entry.AddPair('kind', TAtlasWelcomeUnsaved.KindName(Item.Kind));
    Entry.AddPair('count', TJSONNumber.Create(Item.Count));
    if Item.Kind = TAtlasUnsavedKind.Changes then
    begin
      Entry.AddPair('modified', TJSONNumber.Create(Item.Modified));
      Entry.AddPair('added', TJSONNumber.Create(Item.Added));
      Entry.AddPair('deleted', TJSONNumber.Create(Item.Deleted));
    end;
    if Item.Kind = TAtlasUnsavedKind.NoUpstream then
      Entry.AddPair('commits', TJSONNumber.Create(Item.Commits));
    if Item.Since > 0 then
      Entry.AddPair('since', TAtlasProjectSummaries.TimeText(Item.Since));
    if Length(Item.Branches) > 0 then
    begin
      Names := TJSONArray.Create;
      Entry.AddPair('branches', Names);
      for Name in Item.Branches do
        Names.Add(Name);
    end;
    if Item.Name <> '' then
      Entry.AddPair('name', Item.Name);
    if Item.Ref <> '' then
      Entry.AddPair('ref', Item.Ref);
  end;
  if Length(AState.Ignored) > 0 then
  begin
    Ignore := TJSONObject.Create;
    Result.AddPair('ignore', Ignore);
    for Ignored in AState.Ignored do
      Ignore.AddPair(TAtlasWelcomeUnsaved.KindName(Ignored.Kind), TAtlasProjectSummaries.TimeText(Ignored.UntilUtc));
  end;
end;

function StateOf(ASection: TJSONObject; out AState: TAtlasUnsavedState): Boolean;
var
  Items, Names: TJSONValue;
  Element, Name: TJSONValue;
  Entry, Ignore: TJSONObject;
  Item: TAtlasUnsavedItem;
  Kind: TAtlasUnsavedKind;
  Index, Position: Integer;
  Ignored: TAtlasUnsavedIgnore;
begin
  AState := TAtlasUnsavedState.Empty;
  Result := ASection <> nil;
  if not Result then
    Exit;
  AState.Known := True;
  AState.At := TAtlasProjectSummaries.TimeOf(TextIn(ASection, 'at'));
  AState.Kind := LowerCase(TextIn(ASection, 'kind'));
  AState.Root := TextIn(ASection, 'root');
  AState.Branch := TextIn(ASection, 'branch');
  Items := ASection.GetValue('items');
  if Items is TJSONArray then
    for Index := 0 to TJSONArray(Items).Count - 1 do
    begin
      Element := TJSONArray(Items).Items[Index];
      if not (Element is TJSONObject) then
        Continue;
      Entry := TJSONObject(Element);
      // Unbekannte Arten (spätere Fassungen) überspringen.
      if not TAtlasWelcomeUnsaved.KindOf(TextIn(Entry, 'kind'), Kind) then
        Continue;
      Item := TAtlasUnsavedItem.Create(Kind, NumberIn(Entry, 'count', 0));
      Item.Modified := NumberIn(Entry, 'modified', 0);
      Item.Added := NumberIn(Entry, 'added', 0);
      Item.Deleted := NumberIn(Entry, 'deleted', 0);
      Item.Commits := NumberIn(Entry, 'commits', -1);
      Item.Since := TAtlasProjectSummaries.TimeOf(TextIn(Entry, 'since'));
      Item.Name := TextIn(Entry, 'name');
      Item.Ref := TextIn(Entry, 'ref');
      Names := Entry.GetValue('branches');
      if Names is TJSONArray then
        for Position := 0 to TJSONArray(Names).Count - 1 do
        begin
          Name := TJSONArray(Names).Items[Position];
          if Name is TJSONString then
            Item.Branches := Item.Branches + [TJSONString(Name).Value];
        end;
      AState.Items := AState.Items + [Item];
    end;
  Ignore := ObjectIn(ASection, 'ignore');
  if Ignore <> nil then
    for Index := 0 to Ignore.Count - 1 do
      if TAtlasWelcomeUnsaved.KindOf(Ignore.Pairs[Index].JsonString.Value, Kind) and
        (Ignore.Pairs[Index].JsonValue is TJSONString) then
      begin
        Ignored.Kind := Kind;
        Ignored.UntilUtc := TAtlasProjectSummaries.TimeOf(TJSONString(Ignore.Pairs[Index].JsonValue).Value);
        if Ignored.UntilUtc > 0 then
          AState.Ignored := AState.Ignored + [Ignored];
      end;
end;

class function TAtlasWelcomeUnsaved.ToJson(const AState: TAtlasUnsavedState): string;
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

class function TAtlasWelcomeUnsaved.FromJson(const AJson: string; out AState: TAtlasUnsavedState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasUnsavedState.Empty;
  Value := ParseObject(AJson);
  try
    Result := (Value is TJSONObject) and StateOf(TJSONObject(Value), AState);
  finally
    Value.Free;
  end;
end;

class function TAtlasWelcomeUnsaved.Read(const ASummary: TAtlasProjectSummary;
  out AState: TAtlasUnsavedState): Boolean;
var
  Value: TJSONValue;
begin
  AState := TAtlasUnsavedState.Empty;
  Value := ParseObject(ASummary.Raw);
  try
    Result := (Value is TJSONObject) and StateOf(ObjectIn(TJSONObject(Value), SectionName), AState);
  finally
    Value.Free;
  end;
end;

class procedure TAtlasWelcomeUnsaved.Write(var ASummary: TAtlasProjectSummary; const AState: TAtlasUnsavedState);
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

class function TAtlasWelcomeUnsaved.PushPlans(const ALocal: IAtlasVcsLocalWork; const AItem: TAtlasUnsavedItem;
  out APlans: TArray<TAtlasUnsavedPush>): TAtlasVcsOutcome;
var
  Branches: TArray<TAtlasVcsBranch>;
  Branch: TAtlasVcsBranch;
  Remotes: TArray<string>;
  Remote, Fallback, Name: string;
  Plan: TAtlasUnsavedPush;
  Commits: TArray<TAtlasVcsCommit>;
  Wanted: Boolean;
begin
  APlans := nil;
  if (ALocal = nil) or not AItem.CanPush then
    Exit(TAtlasVcsOutcome.Failed);
  Result := ALocal.Branches(Branches);
  if Result <> TAtlasVcsOutcome.Ok then
    Exit;
  Fallback := '';
  if AItem.Kind = TAtlasUnsavedKind.NoUpstream then
  begin
    Result := ALocal.Remotes(Remotes);
    if Result <> TAtlasVcsOutcome.Ok then
      Exit;
    if Length(Remotes) = 1 then
      Fallback := Remotes[0]
    else
      for Remote in Remotes do
        if Remote = 'origin' then
          Fallback := Remote;
  end;
  for Branch in Branches do
  begin
    Wanted := False;
    for Name in AItem.Branches do
      if Name = Branch.Name then
        Wanted := True;
    if not Wanted then
      Continue;
    Plan := Default(TAtlasUnsavedPush);
    Plan.Branch := Branch.Name;
    if AItem.Kind = TAtlasUnsavedKind.Commits then
    begin
      // Nur, was jetzt noch vor dem Upstream liegt.
      if not Branch.Tracked or (Branch.Ahead <= 0) or (Branch.Remote = '') or (Branch.RemoteRef = '') then
        Continue;
      Plan.Remote := Branch.Remote;
      Plan.RemoteRef := Branch.RemoteRef;
      Result := ALocal.Outgoing(Branch.Name, Branch.Upstream, PushListMax + 1, Commits);
    end
    else
    begin
      if Branch.Tracked then
        Continue;
      Plan.Remote := Branch.Remote;
      if Plan.Remote = '' then
        Plan.Remote := Fallback;
      if Plan.Remote = '' then
        Continue;
      Plan.RemoteRef := 'refs/heads/' + Branch.Name;
      Plan.SetUpstream := True;
      Result := ALocal.Outgoing(Branch.Name, '', PushListMax + 1, Commits);
    end;
    if Result <> TAtlasVcsOutcome.Ok then
    begin
      APlans := nil;
      Exit;
    end;
    if Length(Commits) = 0 then
      Continue;
    Plan.More := Length(Commits) > PushListMax;
    if Plan.More then
      SetLength(Commits, PushListMax);
    Plan.Commits := Commits;
    APlans := APlans + [Plan];
  end;
  Result := TAtlasVcsOutcome.Ok;
end;

end.
