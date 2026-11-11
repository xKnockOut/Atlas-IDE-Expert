unit Atlas.Core.Projects.Recording;

// Stand eines Projekts in seine Zusammenfassung schreiben (#528, #571, #97): Ergebnis eines Compiles, Stand der
// Versionsverwaltung, Regeltreffer im Projektordner. Im Kern (#1455): Die Zusammenfassungen schreibt
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
  Atlas.Core.VersionControl.Contract;

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
    cVcsCallTimeoutMs = 1000;
    /// <summary>Frühestens nach dieser Zeit fragt die Seite dasselbe Projekt erneut ab.</summary>
    cVcsRefreshMs = 60000;
    /// <summary>Spätestens dann gilt eine Abfrage als beendet, auch ohne Ergebnis (zwei Aufrufe mit Zeitlimit
    /// plus Reserve).</summary>
    cVcsQueryLimitMs = 5000;
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
  mMessage: TAtlasCompilerMessage;
  mErrors, mWarnings, mHints: Integer;
  mFirst: TAtlasProjectLocation;
begin
  mErrors := 0;
  mWarnings := 0;
  mHints := 0;
  mFirst := Default(TAtlasProjectLocation);
  for mMessage in AMessages do
    case mMessage.Severity of
      TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal:
        begin
          Inc(mErrors);
          // Erste Fehlermeldung mit Datei; ohne Datei kein Sprungziel.
          if mFirst.IsEmpty and (mMessage.FileName <> '') then
          begin
            mFirst.FileName := mMessage.FileName;
            mFirst.Line := mMessage.Line;
            mFirst.Column := mMessage.Column;
            mFirst.Code := mMessage.Code;
            mFirst.Text := mMessage.Text;
          end;
        end;
      TAtlasCompilerSeverity.Warning:
        Inc(mWarnings);
      TAtlasCompilerSeverity.Hint:
        Inc(mHints);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  if ARun.Background then
  begin
    ASummary.Check := TAtlasProjectCheck.Empty;
    ASummary.Check.Known := True;
    ASummary.Check.At := ANowUtc;
    ASummary.Check.Errors := mErrors;
    ASummary.Check.First := mFirst;
    Exit;
  end;
  ASummary.Build := TAtlasProjectBuild.Empty;
  ASummary.Build.Known := True;
  ASummary.Build.At := ANowUtc;
  ASummary.Build.Kind := ARun.Kind;
  ASummary.Build.Configuration := ARun.Configuration;
  ASummary.Build.Platform := ARun.Platform;
  ASummary.Build.Succeeded := ARun.Succeeded;
  ASummary.Build.Errors := mErrors;
  ASummary.Build.Warnings := mWarnings;
  ASummary.Build.Hints := mHints;
  ASummary.Build.First := mFirst;
end;

class function TAtlasProjectRecording.Probe(const AVcs: IAtlasVersionControl; ANowUtc: TDateTime;
  out AState: TAtlasProjectVcs): Boolean;
begin
  Result := Probe(AVcs, '', ANowUtc, AState);
end;

class function TAtlasProjectRecording.Probe(const AVcs: IAtlasVersionControl; const AFolder: string;
  ANowUtc: TDateTime; out AState: TAtlasProjectVcs): Boolean;
var
  mOutcome: TAtlasVcsOutcome;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
  mCount: Integer;
begin
  AState := TAtlasProjectVcs.Empty;
  Result := False;
  if AVcs = nil then
  begin
    Exit;
  end;
  mOutcome := AVcs.Head(mHead);
  if (mOutcome = TAtlasVcsOutcome.NoWorkingCopy) or (mOutcome = TAtlasVcsOutcome.Disabled) then
  begin
    // Keine Versionsverwaltung: kein Branch, keine Marke, kein Fehler.
    AState.Known := True;
    AState.At := ANowUtc;
    AState.Kind := 'none';
    Exit(True);
  end;
  if mOutcome <> TAtlasVcsOutcome.Ok then
  begin
    Exit;
  end;
  AState.Known := True;
  AState.At := ANowUtc;
  AState.Kind := LowerCase(AtlasVcsKindName(AVcs.Kind));
  AState.Branch := mHead.Branch;
  AState.Revision := mHead.Revision;
  AState.Ahead := mHead.Ahead;
  AState.Behind := mHead.Behind;
  if AVcs.Changes(mChanges) = TAtlasVcsOutcome.Ok then
  begin
    mCount := 0;
    for mChange in mChanges do
    begin
      if (AFolder = '') or InFolder(mChange.Path, AFolder) or InFolder(mChange.OldPath, AFolder) then
      begin
        Inc(mCount);
      end;
    end;
    AState.Changed := mCount;
  end;
  Result := True;
end;

class function TAtlasProjectRecording.InFolder(const AFileName, AFolder: string): Boolean;
var
  mFolder, mFileName: string;
begin
  mFolder := StringReplace(Trim(AFolder), '/', '\', [rfReplaceAll]);
  mFileName := StringReplace(Trim(AFileName), '/', '\', [rfReplaceAll]);
  if (mFolder = '') or (mFileName = '') then
  begin
    Exit(False);
  end;
  if mFolder[Length(mFolder)] <> '\' then
  begin
    mFolder := mFolder + '\';
  end;
  Result := SameText(Copy(mFileName, 1, Length(mFolder)), mFolder);
end;

class function TAtlasProjectRecording.QueryRunning(AStartedMs, ANowMs: UInt64): Boolean;
begin
  // Ein Tick vor dem Start (Uhr übergelaufen o. Ä.) zählt als beendet.
  Result := (ANowMs >= AStartedMs) and (ANowMs - AStartedMs < cVcsQueryLimitMs);
end;

class function TAtlasProjectRecording.IsRuleHit(const AProblem: TAtlasProblem): Boolean;
begin
  // Fehlgeschlagene Tests (#69) sind keine Regeltreffer.
  Result := (AProblem.Code <> '') and not AProblem.IsCompiler and not AProblem.Unnecessary and
    not SameText(AProblem.Source, TAtlasProblemStore.cTestSource);
end;

class function TAtlasProjectRecording.CountRuleHits(AStore: TAtlasProblemStore; const AFolder: string;
  out AHits: Integer): Boolean;
var
  mFileName: string;
  mProblem: TAtlasProblem;
begin
  AHits := 0;
  Result := False;
  if AStore = nil then
  begin
    Exit;
  end;
  for mFileName in AStore.AllFiles do
  begin
    if InFolder(mFileName, AFolder) then
    begin
      Result := True;
      for mProblem in AStore.ForFile(mFileName) do
      begin
        if IsRuleHit(mProblem) then
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
