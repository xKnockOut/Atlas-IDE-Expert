unit Atlas.Core.Welcome.Projects;

// Bereich „Projekte“ der Willkommensseite (#592), Teil ohne VCL und Open
// Tools API: welche Projekte erscheinen, welche Marken (Pillen) sie tragen,
// wie ein Compile in die Projekt-Zusammenfassung kommt und wie die
// Versionsverwaltung abgefragt wird.
// - Liste: zuletzt geöffnete Projekte und Projektgruppen der IDE in deren
//   Reihenfolge, jedes einmal, ohne „Aus Liste entfernte“, höchstens
//   welcomePage.maxProjects (1–30, Vorgabe 8).
// - Marken: Build rot „N Fehler“ (Klick springt zur ersten Meldung), gelb
//   „Build F/W/H“ bei Warnungen oder Hinweisen, grün „Build 0/0/0“; rot
//   „Prüfung: N Fehler“, wenn die Hintergrundprüfung (#548) nach dem letzten
//   Build Fehler fand; gelb „N geändert“ bei offenen Änderungen; grau „↑N ↓M“
//   gegenüber dem Upstream; gelb „N neue Treffer“ gegenüber der Baseline.
// - Versionsverwaltung: Head und Änderungen mit je VcsCallTimeoutMs (zusammen
//   2 s je Projekt), nur im Hintergrund. Keine Arbeitskopie oder vcs.provider
//   = off ergibt „none“ (kein Branch, keine Marke, kein Fehler); andere Fehler
//   lassen den gespeicherten Stand stehen („Stand vom …“). Geänderte Dateien
//   zählen nur unterhalb des Projektordners (eine Arbeitskopie kann mehrere
//   Projekte enthalten). Kommt eine Abfrage nicht binnen VcsQueryLimitMs
//   zurück, gilt sie als beendet (kein dauerhaftes „wird abgefragt …“).
// - Regeltreffer (#97): Atlas-Regeltreffer, die das Plugin vom Server bekommt
//   (Probleme #398, auch für nicht geöffnete Projektdateien über
//   workspace/diagnostic); der Server hat die Baseline schon abgezogen. Gezählt
//   werden Treffer in Dateien unterhalb des Projektordners, nur wenn dort
//   mindestens eine Datei geprüft ist („sofern bekannt“).

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Messages,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Vcs.Contract;

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
    /// <summary>Zeitlimit je Aufruf (Head, Changes); zusammen 2 s je Projekt.</summary>
    VcsCallTimeoutMs = 1000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite dasselbe Projekt erneut ab.</summary>
    VcsRefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet, auch ohne Ergebnis (zwei Aufrufe mit Zeitlimit
    /// plus Reserve).</summary>
    VcsQueryLimitMs = 5000;
  public
    /// <summary>Einträge zu ARecent (Reihenfolge der IDE), jedes Projekt einmal, ohne entfernte, höchstens AMax
    /// (auf MinMax..MaxMax begrenzt).</summary>
    class function Entries(const ARecent: TArray<string>; const ALoad: TAtlasProjectSummaryLoader;
      AMax: Integer): TAtlasProjectEntries; static;
    /// <summary>Marken eines Eintrags in der Reihenfolge Build, Prüfung, Änderungen, Upstream, Regeltreffer.</summary>
    class function Pills(const AEntry: TAtlasProjectEntry): TArray<TAtlasProjectPill>; static;
    /// <summary>Schlimmste Stufe der Marken; Neutral ohne Marken.</summary>
    class function Level(const APills: TArray<TAtlasProjectPill>): TAtlasProjectPillLevel; static;
    /// <summary>Ergebnis eines Compiles in die Zusammenfassung: ABackground (Hintergrundprüfung, #548) setzt
    /// "check", sonst "build". Fehler zählen mit schweren Fehlern (Fatal).</summary>
    class procedure RecordCompile(var ASummary: TAtlasProjectSummary;
      const AMessages: TArray<TAtlasCompilerMessage>; ABackground, ASucceeded: Boolean;
      const AKind, AConfiguration, APlatform: string; ANowUtc: TDateTime); static;
    /// <summary>Head und Änderungen abfragen (startet Prozesse: nur im Hintergrund). True mit AState, wenn das
    /// Ergebnis gilt (auch „none“); False bei Fehler, Zeitüberschreitung oder fehlendem Programm.</summary>
    class function Probe(const AVcs: IAtlasVersionControl; ANowUtc: TDateTime;
      out AState: TAtlasProjectVcs): Boolean; overload; static;
    /// <summary>Wie oben; geänderte Dateien nur unterhalb von AFolder (Projektordner; '' = alle).</summary>
    class function Probe(const AVcs: IAtlasVersionControl; const AFolder: string; ANowUtc: TDateTime;
      out AState: TAtlasProjectVcs): Boolean; overload; static;
    /// <summary>Liegt AFileName in AFolder oder darunter? Groß-/Kleinschreibung und / bzw. \ egal.</summary>
    class function InFolder(const AFileName, AFolder: string): Boolean; static;
    /// <summary>Läuft eine Abfrage, die bei AStartedMs begann (Tick in ms), bei ANowMs noch?</summary>
    class function QueryRunning(AStartedMs, ANowMs: UInt64): Boolean; static;
    /// <summary>Atlas-Regeltreffer: Code einer Regel, nicht vom Compiler, kein inaktiver Bereich.</summary>
    class function IsRuleHit(const AProblem: TAtlasProblem): Boolean; static;
    /// <summary>Regeltreffer in den Dateien von AStore unterhalb von AFolder. False (unbekannt), wenn dort keine
    /// Datei geprüft ist.</summary>
    class function CountRuleHits(AStore: TAtlasProblemStore; const AFolder: string;
      out AHits: Integer): Boolean; static;
    /// <summary>Neue Regeltreffer gegenüber der Baseline in die Zusammenfassung ("rules").</summary>
    class procedure RecordRules(var ASummary: TAtlasProjectSummary; AHits: Integer; ANowUtc: TDateTime); static;
    /// <summary>Pfad gekürzt auf höchstens AMaxLength Zeichen: Anfang, „…“ und so viele Ordner vom Ende wie
    /// passen.</summary>
    class function ShortPath(const APath: string; AMaxLength: Integer): string; static;
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

class procedure TAtlasWelcomeProjects.RecordCompile(var ASummary: TAtlasProjectSummary;
  const AMessages: TArray<TAtlasCompilerMessage>; ABackground, ASucceeded: Boolean;
  const AKind, AConfiguration, APlatform: string; ANowUtc: TDateTime);
var
  Message: TAtlasCompilerMessage;
  Errors, Warnings, Hints: Integer;
  First: TAtlasProjectLocation;
begin
  Errors := 0;
  Warnings := 0;
  Hints := 0;
  First := Default(TAtlasProjectLocation);
  for Message in AMessages do
    case Message.Severity of
      TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal:
        begin
          Inc(Errors);
          // Erste Fehlermeldung mit Datei; ohne Datei kein Sprungziel.
          if First.IsEmpty and (Message.FileName <> '') then
          begin
            First.FileName := Message.FileName;
            First.Line := Message.Line;
            First.Column := Message.Column;
            First.Code := Message.Code;
            First.Text := Message.Text;
          end;
        end;
      TAtlasCompilerSeverity.Warning:
        Inc(Warnings);
      TAtlasCompilerSeverity.Hint:
        Inc(Hints);
    end;
  if ABackground then
  begin
    ASummary.Check := TAtlasProjectCheck.Empty;
    ASummary.Check.Known := True;
    ASummary.Check.At := ANowUtc;
    ASummary.Check.Errors := Errors;
    ASummary.Check.First := First;
    Exit;
  end;
  ASummary.Build := TAtlasProjectBuild.Empty;
  ASummary.Build.Known := True;
  ASummary.Build.At := ANowUtc;
  ASummary.Build.Kind := AKind;
  ASummary.Build.Configuration := AConfiguration;
  ASummary.Build.Platform := APlatform;
  ASummary.Build.Succeeded := ASucceeded;
  ASummary.Build.Errors := Errors;
  ASummary.Build.Warnings := Warnings;
  ASummary.Build.Hints := Hints;
  ASummary.Build.First := First;
end;

class function TAtlasWelcomeProjects.Probe(const AVcs: IAtlasVersionControl; ANowUtc: TDateTime;
  out AState: TAtlasProjectVcs): Boolean;
begin
  Result := Probe(AVcs, '', ANowUtc, AState);
end;

class function TAtlasWelcomeProjects.InFolder(const AFileName, AFolder: string): Boolean;
var
  Folder, FileName: string;
begin
  Folder := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
  FileName := StringReplace(Trim(AFileName), '/', '\', [rfReplaceAll]);
  if (Folder = '') or (FileName = '') then
    Exit(False);
  if Folder[Length(Folder)] <> '\' then
    Folder := Folder + '\';
  Result := SameText(Copy(FileName, 1, Length(Folder)), Folder);
end;

class function TAtlasWelcomeProjects.QueryRunning(AStartedMs, ANowMs: UInt64): Boolean;
begin
  // Ein Tick vor dem Start (Uhr übergelaufen o. Ä.) zählt als beendet.
  Result := (ANowMs >= AStartedMs) and (ANowMs - AStartedMs < VcsQueryLimitMs);
end;

class function TAtlasWelcomeProjects.IsRuleHit(const AProblem: TAtlasProblem): Boolean;
begin
  Result := (AProblem.Code <> '') and not AProblem.IsCompiler and not AProblem.Unnecessary;
end;

class function TAtlasWelcomeProjects.CountRuleHits(AStore: TAtlasProblemStore; const AFolder: string;
  out AHits: Integer): Boolean;
var
  FileName: string;
  Problem: TAtlasProblem;
begin
  AHits := 0;
  Result := False;
  if AStore = nil then
    Exit;
  for FileName in AStore.AllFiles do
    if InFolder(FileName, AFolder) then
    begin
      Result := True;
      for Problem in AStore.ForFile(FileName) do
        if IsRuleHit(Problem) then
          Inc(AHits);
    end;
end;

class procedure TAtlasWelcomeProjects.RecordRules(var ASummary: TAtlasProjectSummary; AHits: Integer;
  ANowUtc: TDateTime);
begin
  ASummary.Rules := TAtlasProjectRules.Empty;
  ASummary.Rules.Known := True;
  ASummary.Rules.At := ANowUtc;
  ASummary.Rules.NewHits := AHits;
end;

class function TAtlasWelcomeProjects.Probe(const AVcs: IAtlasVersionControl; const AFolder: string;
  ANowUtc: TDateTime; out AState: TAtlasProjectVcs): Boolean;
var
  Outcome: TAtlasVcsOutcome;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Change: TAtlasVcsChange;
  Count: Integer;
begin
  AState := TAtlasProjectVcs.Empty;
  Result := False;
  if AVcs = nil then
    Exit;
  Outcome := AVcs.Head(Head);
  if (Outcome = TAtlasVcsOutcome.NoWorkingCopy) or (Outcome = TAtlasVcsOutcome.Disabled) then
  begin
    // Keine Versionsverwaltung: kein Branch, keine Marke, kein Fehler.
    AState.Known := True;
    AState.At := ANowUtc;
    AState.Kind := 'none';
    Exit(True);
  end;
  if Outcome <> TAtlasVcsOutcome.Ok then
    Exit;
  AState.Known := True;
  AState.At := ANowUtc;
  AState.Kind := LowerCase(AtlasVcsKindName(AVcs.Kind));
  AState.Branch := Head.Branch;
  AState.Revision := Head.Revision;
  AState.Ahead := Head.Ahead;
  AState.Behind := Head.Behind;
  if AVcs.Changes(Changes) = TAtlasVcsOutcome.Ok then
  begin
    Count := 0;
    for Change in Changes do
      if (AFolder = '') or InFolder(Change.Path, AFolder) or InFolder(Change.OldPath, AFolder) then
        Inc(Count);
    AState.Changed := Count;
  end;
  Result := True;
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

end.
