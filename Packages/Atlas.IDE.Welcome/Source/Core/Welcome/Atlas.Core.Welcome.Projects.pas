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
    cDefaultMax = 8;
    cMinMax = 1;
    cMaxMax = 30;
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

uses
  System.Math;

const
  cEllipsis = #$2026;

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
  begin
    Exit;
  end;
  Result := Summary.Vcs.Branch;
  if (Result = '') and SameText(Summary.Vcs.Kind, 'git') then
  begin
    Result := Copy(Summary.Vcs.Revision, 1, 7);
  end;
end;

function TAtlasProjectEntry.VcsStale: Boolean;
begin
  Result := not VcsFresh and Summary.Vcs.InWorkingCopy;
end;

{ TAtlasWelcomeProjects }

/// <summary>Eintrag für AProject mit seiner Zusammenfassung, sofern ALoad eine liefert.</summary>
function EntryFor(const AProject: string; const ALoad: TAtlasProjectSummaryLoader): TAtlasProjectEntry;
begin
  Result := Default(TAtlasProjectEntry);
  Result.Summary := TAtlasProjectSummary.Create(AProject);
  if Assigned(ALoad) then
  begin
    Result.HasSummary := ALoad(AProject, Result.Summary);
  end;
  if not Result.HasSummary then
  begin
    Result.Summary := TAtlasProjectSummary.Create(AProject);
  end;
  // Der Pfad der IDE gilt: Die Datei kann vom selben Projekt in anderer Schreibweise stammen.
  Result.Summary.Project := AProject;
end;

/// <summary>Steht AKey schon in ASeen? Sonst anfügen.</summary>
function SeenBefore(var ASeen: TArray<string>; const AKey: string): Boolean;
var
  mKnown: string;
begin
  Result := False;
  for mKnown in ASeen do
  begin
    Result := Result or (mKnown = AKey);
  end;
  if not Result then
  begin
    ASeen := ASeen + [AKey];
  end;
end;

class function TAtlasWelcomeProjects.Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
  AMax: Integer): TAtlasProjectEntries;
var
  mLimit: Integer;
  mProject: string;
  mSeen: TArray<string>;
  mEntry: TAtlasProjectEntry;
begin
  Result := nil;
  mSeen := nil;
  mLimit := Min(Max(AMax, cMinMax), cMaxMax);
  for mProject in ARecent do
  begin
    if Length(Result) >= mLimit then
    begin
      Break;
    end;
    if (Trim(mProject) = '') or SeenBefore(mSeen, TAtlasProjectSummaries.NormalizedPath(mProject)) then
    begin
      Continue;
    end;
    mEntry := EntryFor(Trim(mProject), ALoad);
    if not (mEntry.HasSummary and mEntry.Summary.Hidden) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

/// <summary>Pille des letzten Builds.</summary>
function BuildPill(const ABuild: TAtlasProjectBuild): TAtlasProjectPill;
begin
  if ABuild.Errors > 0 then
  begin
    Result := TAtlasProjectPill.Create(TAtlasProjectPillKind.BuildErrors, TAtlasProjectPillLevel.Error,
      ABuild.Errors, 0, 0);
    Result.Target := ABuild.First;
  end
  else if not ABuild.Succeeded then
  begin
    // Fehlgeschlagen ohne lesbare Fehlermeldung (z. B. Linker): rot, aber ohne Sprungziel.
    Result := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Error, ABuild.Errors,
      ABuild.Warnings, ABuild.Hints);
  end
  else if (ABuild.Warnings > 0) or (ABuild.Hints > 0) then
  begin
    Result := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Warning, 0,
      ABuild.Warnings, ABuild.Hints);
  end
  else
  begin
    Result := TAtlasProjectPill.Create(TAtlasProjectPillKind.Build, TAtlasProjectPillLevel.Good, 0, 0, 0);
  end;
end;

/// <summary>Pillen der Versionsverwaltung: Änderungen und Abstand zum Ziel (nur in einer Arbeitskopie).</summary>
function VcsPills(const AVcs: TAtlasProjectVcs): TArray<TAtlasProjectPill>;
begin
  Result := nil;
  if not AVcs.InWorkingCopy then
  begin
    Exit;
  end;
  if AVcs.Changed > 0 then
  begin
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Changes, TAtlasProjectPillLevel.Warning,
      AVcs.Changed, 0, 0)];
  end;
  if (AVcs.Ahead > 0) or (AVcs.Behind > 0) then
  begin
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Sync, TAtlasProjectPillLevel.Neutral,
      Max(AVcs.Ahead, 0), Max(AVcs.Behind, 0), 0)];
  end;
end;

class function TAtlasWelcomeProjects.Pills(const AEntry: TAtlasProjectEntry): TArray<TAtlasProjectPill>;
var
  mBuild: TAtlasProjectBuild;
  mCheck: TAtlasProjectCheck;
  mPill: TAtlasProjectPill;
begin
  Result := nil;
  mBuild := AEntry.Summary.Build;
  mCheck := AEntry.Summary.Check;
  if mBuild.Known then
  begin
    Result := Result + [BuildPill(mBuild)];
  end;
  // Prüfung nur, wenn sie nach dem letzten Build lief: sonst zeigt der Build den neueren Stand.
  if mCheck.Known and (mCheck.Errors > 0) and (not mBuild.Known or (mCheck.At >= mBuild.At)) then
  begin
    mPill := TAtlasProjectPill.Create(TAtlasProjectPillKind.CheckErrors, TAtlasProjectPillLevel.Error, mCheck.Errors,
      0, 0);
    mPill.Target := mCheck.First;
    Result := Result + [mPill];
  end;
  Result := Result + VcsPills(AEntry.Summary.Vcs);
  if AEntry.Summary.Rules.Known and (AEntry.Summary.Rules.NewHits > 0) then
  begin
    Result := Result + [TAtlasProjectPill.Create(TAtlasProjectPillKind.Rules, TAtlasProjectPillLevel.Warning,
      AEntry.Summary.Rules.NewHits, 0, 0)];
  end;
end;

class function TAtlasWelcomeProjects.Level(const APills: TArray<TAtlasProjectPill>): TAtlasProjectPillLevel;
var
  mPill: TAtlasProjectPill;
begin
  Result := TAtlasProjectPillLevel.Neutral;
  for mPill in APills do
  begin
    if Ord(mPill.Level) > Ord(Result) then
    begin
      Result := mPill.Level;
    end;
  end;
end;

class function TAtlasWelcomeProjects.ShortPath(const APath: string; AMaxLength: Integer): string;
var
  mParts: TArray<string>;
  mHead, mTail, mCandidate: string;
  mIndex: Integer;
begin
  Result := APath;
  if (AMaxLength < 4) or (Length(Result) <= AMaxLength) then
  begin
    Exit;
  end;
  mParts := StringReplace(APath, '/', '\', [rfReplaceAll]).Split(['\']);
  if Length(mParts) < 3 then
  begin
    Exit(cEllipsis + Copy(APath, Length(APath) - AMaxLength + 2, MaxInt));
  end;
  mHead := mParts[0] + '\' + cEllipsis;
  mTail := '\' + mParts[High(mParts)];
  if Length(mHead) + Length(mTail) > AMaxLength then
  begin
    Exit(cEllipsis + Copy(APath, Length(APath) - AMaxLength + 2, MaxInt));
  end;
  for mIndex := High(mParts) - 1 downto 1 do
  begin
    mCandidate := '\' + mParts[mIndex] + mTail;
    if Length(mHead) + Length(mCandidate) > AMaxLength then
    begin
      Break;
    end;
    mTail := mCandidate;
  end;
  Result := mHead + mTail;
end;

{ TAtlasWelcomeAutoOpen }

class function TAtlasWelcomeAutoOpen.AfterProjectClosed(AEnabled, AWhenNoProject: Boolean; AOpenProjects: Integer;
  AIdeRunning, AShowing: Boolean): Boolean;
begin
  Result := AEnabled and AWhenNoProject and (AOpenProjects = 0) and AIdeRunning and not AShowing;
end;

end.
