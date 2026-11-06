unit Atlas.Core.Projects.Recording;

// Stand eines Projekts in seine Zusammenfassung schreiben (#528, #571, #97): Ergebnis eines Compiles, Stand der
// Versionsverwaltung, Regeltreffer im Projektordner. Im Kern (#1455, ADR 0017): Die Zusammenfassungen schreibt
// Base auch ohne die Willkommensseite; Willkommensseite, Projektverlauf und die Module lesen sie.
// - Versionsverwaltung: Head und Änderungen mit je VcsCallTimeoutMs; geänderte Dateien zählen nur im
//   Projektordner (eine Arbeitskopie kann mehrere Projekte enthalten). Eine Abfrage, die nicht binnen
//   VcsQueryLimitMs zurückkommt, gilt als beendet.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Messages,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Vcs.Contract;

type
  /// <summary>Art eines Compiles für RecordCompile: Hintergrundprüfung (#548) oder Build mit Art, Konfiguration
  /// und Plattform.</summary>
  TAtlasProjectCompileRun = record
    Background: Boolean;
    Succeeded: Boolean;
    Kind: string;
    Configuration: string;
    Platform: string;
    class function Create(ABackground, ASucceeded: Boolean; const AKind, AConfiguration,
      APlatform: string): TAtlasProjectCompileRun; static;
  end;

  TAtlasProjectRecording = class
  public const
    /// <summary>Zeitlimit je Aufruf (Head, Changes); zusammen 2 s je Projekt.</summary>
    VcsCallTimeoutMs = 1000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite dasselbe Projekt erneut ab.</summary>
    VcsRefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet, auch ohne Ergebnis (zwei Aufrufe mit Zeitlimit
    /// plus Reserve).</summary>
    VcsQueryLimitMs = 5000;
  public
    /// <summary>Ergebnis eines Compiles in die Zusammenfassung: ARun.Background (Hintergrundprüfung, #548) setzt
    /// "check", sonst "build". Fehler zählen mit schweren Fehlern (Fatal).</summary>
    class procedure RecordCompile(var ASummary: TAtlasProjectSummary;
      const AMessages: TArray<TAtlasCompilerMessage>; const ARun: TAtlasProjectCompileRun; ANowUtc: TDateTime); static;
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
  end;

implementation

{ TAtlasProjectCompileRun }

class function TAtlasProjectCompileRun.Create(ABackground, ASucceeded: Boolean; const AKind, AConfiguration,
  APlatform: string): TAtlasProjectCompileRun;
begin
  Result.Background := ABackground;
  Result.Succeeded := ASucceeded;
  Result.Kind := AKind;
  Result.Configuration := AConfiguration;
  Result.Platform := APlatform;
end;

{ TAtlasProjectRecording }

class procedure TAtlasProjectRecording.RecordCompile(var ASummary: TAtlasProjectSummary;
  const AMessages: TArray<TAtlasCompilerMessage>; const ARun: TAtlasProjectCompileRun; ANowUtc: TDateTime);
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
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  if ARun.Background then
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
  ASummary.Build.Kind := ARun.Kind;
  ASummary.Build.Configuration := ARun.Configuration;
  ASummary.Build.Platform := ARun.Platform;
  ASummary.Build.Succeeded := ARun.Succeeded;
  ASummary.Build.Errors := Errors;
  ASummary.Build.Warnings := Warnings;
  ASummary.Build.Hints := Hints;
  ASummary.Build.First := First;
end;

class function TAtlasProjectRecording.Probe(const AVcs: IAtlasVersionControl; ANowUtc: TDateTime;
  out AState: TAtlasProjectVcs): Boolean;
begin
  Result := Probe(AVcs, '', ANowUtc, AState);
end;

class function TAtlasProjectRecording.Probe(const AVcs: IAtlasVersionControl; const AFolder: string;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
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
    begin
      if (AFolder = '') or InFolder(Change.Path, AFolder) or InFolder(Change.OldPath, AFolder) then
      begin
        Inc(Count);
      end;
    end;
    AState.Changed := Count;
  end;
  Result := True;
end;

class function TAtlasProjectRecording.InFolder(const AFileName, AFolder: string): Boolean;
var
  Folder, FileName: string;
begin
  Folder := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
  FileName := StringReplace(Trim(AFileName), '/', '\', [rfReplaceAll]);
  if (Folder = '') or (FileName = '') then
  begin
    Exit(False);
  end;
  if Folder[Length(Folder)] <> '\' then
  begin
    Folder := Folder + '\';
  end;
  Result := SameText(Copy(FileName, 1, Length(Folder)), Folder);
end;

class function TAtlasProjectRecording.QueryRunning(AStartedMs, ANowMs: UInt64): Boolean;
begin
  // Ein Tick vor dem Start (Uhr übergelaufen o. Ä.) zählt als beendet.
  Result := (ANowMs >= AStartedMs) and (ANowMs - AStartedMs < VcsQueryLimitMs);
end;

class function TAtlasProjectRecording.IsRuleHit(const AProblem: TAtlasProblem): Boolean;
begin
  // Fehlgeschlagene Tests (#69) sind keine Regeltreffer.
  Result := (AProblem.Code <> '') and not AProblem.IsCompiler and not AProblem.Unnecessary and
    not SameText(AProblem.Source, TAtlasProblemStore.TestSource);
end;

class function TAtlasProjectRecording.CountRuleHits(AStore: TAtlasProblemStore; const AFolder: string;
  out AHits: Integer): Boolean;
var
  FileName: string;
  Problem: TAtlasProblem;
begin
  AHits := 0;
  Result := False;
  if AStore = nil then
  begin
    Exit;
  end;
  for FileName in AStore.AllFiles do
  begin
    if InFolder(FileName, AFolder) then
    begin
      Result := True;
      for Problem in AStore.ForFile(FileName) do
      begin
        if IsRuleHit(Problem) then
        begin
          Inc(AHits);
        end;
      end;
    end;
  end;
end;

class procedure TAtlasProjectRecording.RecordRules(var ASummary: TAtlasProjectSummary; AHits: Integer;
  ANowUtc: TDateTime);
begin
  ASummary.Rules := TAtlasProjectRules.Empty;
  ASummary.Rules.Known := True;
  ASummary.Rules.At := ANowUtc;
  ASummary.Rules.NewHits := AHits;
end;

end.
