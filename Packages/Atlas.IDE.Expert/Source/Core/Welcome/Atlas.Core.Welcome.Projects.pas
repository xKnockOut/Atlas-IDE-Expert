unit Atlas.Core.Welcome.Projects;

// Bereich „Projekte“ der Willkommensseite (#592), Teil ohne VCL und Open
// Tools API: welche Projekte erscheinen und welche Marken (Pillen) sie tragen.
// - Liste: zuletzt geöffnete Projekte und Projektgruppen der IDE in deren
//   Reihenfolge, jedes einmal, ohne „Aus Liste entfernte“, höchstens
//   welcomePage.maxProjects (1–30, Vorgabe 8).
// - Marken: Build rot „N Fehler“ (Klick springt zur ersten Meldung), gelb
//   „Build F/W/H“ bei Warnungen oder Hinweisen, grün „Build 0/0/0“; rot
//   „Prüfung: N Fehler“, wenn die Hintergrundprüfung (#548) nach dem letzten
//   Build Fehler fand; gelb „N geändert“ bei offenen Änderungen; grau „↑N ↓M“
//   gegenüber dem Upstream; gelb „N neue Treffer“ gegenüber der Baseline.
// - Versionsverwaltung und Regeltreffer schreibt der Kern in die Zusammenfassung
//   (Atlas.Core.Projects.Recording, #1455). Keine Arbeitskopie oder vcs.provider
//   = off ergibt „none“ (kein Branch, keine Marke, kein Fehler); andere Fehler
//   lassen den gespeicherten Stand stehen („Stand vom …“).
// - Ohne Projekt (#1114): Ist das letzte Projekt geschlossen, öffnet sich das
//   Fenster „Atlas-Start“ (welcomePage.openWhenNoProject), nur solange die IDE
//   läuft und nicht beim Beenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary;

type
{$SCOPEDENUMS ON}
  TAtlasProjectPillKind = (Build, BuildErrors, CheckErrors, Changes, Sync, Rules);
  TAtlasProjectPillLevel = (Neutral, Good, Warning, Error);
{$SCOPEDENUMS OFF}

  TAtlasProjectPill = record
    Kind: TAtlasProjectPillKind;
    Level: TAtlasProjectPillLevel;
    /// <summary>Build: Fehler, Warnungen, Hinweise; BuildErrors und CheckErrors: Fehler in A; Changes: Dateien
    /// in A; Sync: vor (A) und hinter (B) dem Upstream; Rules: neue Treffer in A.</summary>
    A: Integer;
    B: Integer;
    C: Integer;
    /// <summary>Sprungziel der Fehler-Marken; leer = nicht anklickbar.</summary>
    Target: TAtlasProjectLocation;
    class function Create(AKind: TAtlasProjectPillKind; ALevel: TAtlasProjectPillLevel; AA, AB,
      AC: Integer): TAtlasProjectPill; static;
    function Clickable: Boolean;
  end;

  TAtlasProjectEntry = record
    Summary: TAtlasProjectSummary;
    /// <summary>Es gab eine lesbare Zusammenfassung.</summary>
    HasSummary: Boolean;
    /// <summary>Versionsverwaltung in dieser Sitzung abgefragt; sonst gilt der gespeicherte Stand.</summary>
    VcsFresh: Boolean;
    /// <summary>Die Abfrage der Versionsverwaltung läuft gerade.</summary>
    VcsQuerying: Boolean;
    function Project: string;
    function Name: string;
    /// <summary>Branch bzw. SVN-Pfad; bei losgelöstem HEAD die Kurzform des Commits; '' ohne Arbeitskopie.</summary>
    function Branch: string;
    /// <summary>Der gezeigte Stand der Versionsverwaltung stammt aus der Datei („Stand vom …“).</summary>
    function VcsStale: Boolean;
  end;

  TAtlasProjectEntries = TArray<TAtlasProjectEntry>;

  TAtlasProjectSummaryLoader = reference to function(const AProject: string;
    out ASummary: TAtlasProjectSummary): Boolean;

  TAtlasWelcomeProjects = class
  public const
    DefaultMax = 8;
    MinMax = 1;
    MaxMax = 30;
  public
    /// <summary>Einträge zu ARecent (Reihenfolge der IDE), jedes Projekt einmal, ohne entfernte, höchstens AMax
    /// (auf MinMax..MaxMax begrenzt).</summary>
    class function Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
      AMax: Integer): TAtlasProjectEntries; static;
    /// <summary>Marken eines Eintrags in der Reihenfolge Build, Prüfung, Änderungen, Upstream, Regeltreffer.</summary>
    class function Pills(const AEntry: TAtlasProjectEntry): TArray<TAtlasProjectPill>; static;
    /// <summary>Schlimmste Stufe der Marken; Neutral ohne Marken.</summary>
    class function Level(const APills: TArray<TAtlasProjectPill>): TAtlasProjectPillLevel; static;
    /// <summary>Pfad gekürzt auf höchstens AMaxLength Zeichen: Anfang, „…“ und so viele Ordner vom Ende wie
    /// passen.</summary>
    class function ShortPath(const APath: string; AMaxLength: Integer): string; static;
  end;

  /// <summary>Wann sich „Atlas-Start“ von selbst öffnet, nachdem ein Projekt geschlossen wurde (#1114).</summary>
  TAtlasWelcomeAutoOpen = record
    /// <summary>True, wenn das Fenster jetzt öffnen soll: Willkommensseite (AEnabled) und
    /// welcomePage.openWhenNoProject (AWhenNoProject) an, kein Projekt mehr offen (AOpenProjects = 0; negativ =
    /// unbekannt), die IDE läuft (AIdeRunning, nicht beim Beenden) und das Fenster ist noch nicht sichtbar
    /// (AShowing).</summary>
    class function AfterProjectClosed(AEnabled, AWhenNoProject: Boolean; AOpenProjects: Integer;
      AIdeRunning, AShowing: Boolean): Boolean; static;
  end;

implementation

const
  Ellipsis = #$2026;

{ TAtlasProjectPill }

class function TAtlasProjectPill.Create(AKind: TAtlasProjectPillKind; ALevel: TAtlasProjectPillLevel; AA, AB,
  AC: Integer): TAtlasProjectPill;
begin
  Result := Default(TAtlasProjectPill);
  Result.Kind := AKind;
  Result.Level := ALevel;
  Result.A := AA;
  Result.B := AB;
  Result.C := AC;
end;

function TAtlasProjectPill.Clickable: Boolean;
begin
  Result := not Target.IsEmpty;
end;

{ TAtlasProjectEntry }

function TAtlasProjectEntry.Project: string;
begin
  Result := Summary.Project;
end;

function TAtlasProjectEntry.Name: string;
begin
  Result := Summary.Name;
end;

function TAtlasProjectEntry.Branch: string;
begin
  Result := '';
  if not Summary.Vcs.InWorkingCopy then
    Exit;
  Result := Summary.Vcs.Branch;
  if (Result = '') and SameText(Summary.Vcs.Kind, 'git') then
    Result := Copy(Summary.Vcs.Revision, 1, 7);
end;

function TAtlasProjectEntry.VcsStale: Boolean;
begin
  Result := not VcsFresh and Summary.Vcs.InWorkingCopy;
end;

{ TAtlasWelcomeProjects }

class function TAtlasWelcomeProjects.Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
  AMax: Integer): TAtlasProjectEntries;
var
  Limit: Integer;
  Project, Key: string;
  Seen: TArray<string>;
  Known: string;
  Duplicate: Boolean;
  Entry: TAtlasProjectEntry;
begin
  Result := nil;
  Seen := nil;
  Limit := AMax;
  if Limit < MinMax then
    Limit := MinMax;
  if Limit > MaxMax then
    Limit := MaxMax;
  for Project in ARecent do
  begin
    if Length(Result) >= Limit then
      Break;
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
    Entry := Default(TAtlasProjectEntry);
    Entry.Summary := TAtlasProjectSummary.Create(Trim(Project));
    if Assigned(ALoad) then
      Entry.HasSummary := ALoad(Trim(Project), Entry.Summary);
    if not Entry.HasSummary then
      Entry.Summary := TAtlasProjectSummary.Create(Trim(Project));
    // Der Pfad der IDE gilt: Die Datei kann vom selben Projekt in anderer Schreibweise stammen.
    Entry.Summary.Project := Trim(Project);
    if Entry.HasSummary and Entry.Summary.Hidden then
      Continue;
    Result := Result + [Entry];
  end;
end;

class function TAtlasWelcomeProjects.Pills(const AEntry: TAtlasProjectEntry): TArray<TAtlasProjectPill>;
var
  Build: TAtlasProjectBuild;
  Check: TAtlasProjectCheck;
  Vcs: TAtlasProjectVcs;
  Pill: TAtlasProjectPill;
  Ahead, Behind: Integer;
begin
  Result := nil;
  Build := AEntry.Summary.Build;
  Check := AEntry.Summary.Check;
  Vcs := AEntry.Summary.Vcs;
  if Build.Known then
  begin
    if Build.Errors > 0 then
    begin
      Pill := TAtlasProjectPill.Create(TAtlasProjectPillKind.BuildErrors, TAtlasProjectPillLevel.Error,
        Build.Errors, 0, 0);
      Pill.Target := Build.First;
    end
    else if not Build.Succeeded then
      // Fehlgeschlagen ohne lesbare Fehlermeldung (z. B. Linker): rot, aber ohne Sprungziel.
      Pill := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Error, Build.Errors,
        Build.Warnings, Build.Hints)
    else if (Build.Warnings > 0) or (Build.Hints > 0) then
      Pill := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Warning, 0,
        Build.Warnings, Build.Hints)
    else
      Pill := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Good, 0, 0, 0);
    Result := Result + [Pill];
  end;
  // Prüfung nur, wenn sie nach dem letzten Build lief: sonst zeigt der Build den neueren Stand.
  if Check.Known and (Check.Errors > 0) and (not Build.Known or (Check.At >= Build.At)) then
  begin
    Pill := TAtlasProjectPill.Create(TAtlasProjectPillKind.CheckErrors, TAtlasProjectPillLevel.Error, Check.Errors,
      0, 0);
    Pill.Target := Check.First;
    Result := Result + [Pill];
  end;
  if Vcs.InWorkingCopy and (Vcs.Changed > 0) then
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Changes, TAtlasProjectPillLevel.Warning,
      Vcs.Changed, 0, 0)];
  if Vcs.InWorkingCopy and ((Vcs.Ahead > 0) or (Vcs.Behind > 0)) then
  begin
    Ahead := Vcs.Ahead;
    if Ahead < 0 then
      Ahead := 0;
    Behind := Vcs.Behind;
    if Behind < 0 then
      Behind := 0;
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Sync, TAtlasProjectPillLevel.Neutral, Ahead,
      Behind, 0)];
  end;
  if AEntry.Summary.Rules.Known and (AEntry.Summary.Rules.NewHits > 0) then
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Rules, TAtlasProjectPillLevel.Warning,
      AEntry.Summary.Rules.NewHits, 0, 0)];
end;

class function TAtlasWelcomeProjects.Level(const APills: TArray<TAtlasProjectPill>): TAtlasProjectPillLevel;
var
  Pill: TAtlasProjectPill;
begin
  Result := TAtlasProjectPillLevel.Neutral;
  for Pill in APills do
    if Ord(Pill.Level) > Ord(Result) then
      Result := Pill.Level;
end;

class function TAtlasWelcomeProjects.ShortPath(const APath: string; AMaxLength: Integer): string;
var
  Parts: TArray<string>;
  Head, Tail, Candidate: string;
  Index: Integer;
begin
  Result := APath;
  if (AMaxLength < 4) or (Length(Result) <= AMaxLength) then
    Exit;
  Parts := StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']);
  if Length(Parts) < 3 then
    Exit(Ellipsis + Copy(APath, Length(APath) - AMaxLength + 2, MaxInt));
  Head := Parts[0] + '\' + Ellipsis;
  Tail := '\' + Parts[High(Parts)];
  if Length(Head) + Length(Tail) > AMaxLength then
    Exit(Ellipsis + Copy(APath, Length(APath) - AMaxLength + 2, MaxInt));
  for Index := High(Parts) - 1 downto 1 do
  begin
    Candidate := '\' + Parts[Index] + Tail;
    if Length(Head) + Length(Candidate) > AMaxLength then
      Break;
    Tail := Candidate;
  end;
  Result := Head + Tail;
end;

{ TAtlasWelcomeAutoOpen }

class function TAtlasWelcomeAutoOpen.AfterProjectClosed(AEnabled, AWhenNoProject: Boolean; AOpenProjects: Integer;
  AIdeRunning, AShowing: Boolean): Boolean;
begin
  Result := AEnabled and AWhenNoProject and (AOpenProjects = 0) and AIdeRunning and not AShowing;
end;

end.
