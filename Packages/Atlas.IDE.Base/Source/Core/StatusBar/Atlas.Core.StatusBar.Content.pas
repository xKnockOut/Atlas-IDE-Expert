unit Atlas.Core.StatusBar.Content;

// Atlas-Statusleiste (#1155), Inhalte ohne VCL und OTA:
// - Meldungen dieser Unit: Zähler je Art wie im Fenster „Atlas-Prüfung“
//   (TAtlasFindings.IsFinding, Art aus dem Schweregrad; Compilermeldungen nur
//   mit AWithCompiler wie problems.window.compiler). NextOf liefert den
//   nächsten Befund einer Art nach dem Cursor, am Ende wieder vom Anfang.
// - Live-Prüfung: „prüft …“ während einer Prüfung, sonst nach problems.update
//   „live“, „beim Speichern“ oder „manuell“, bei live und manuell mit dem
//   Alter der letzten Prüfung dieser Datei („live · geprüft vor 2 s“). Der
//   Tooltip nennt die Art und was ein Klick tut: live prüft alle Units neu,
//   sonst nur die offene Datei (ClickChecksFile). Die Texte kommen von der
//   Oberfläche (TAtlasStatusLiveTexts). Solange die Projektprüfung nicht alle
//   Units hat, folgt „ · Projekt 45 %“ (#1232).
// - Aktuelle Methode: innerste Methode bzw. Routine der Gliederung, die die
//   Cursorzeile umfasst, mit qualifiziertem Namen und Sprungziel (Name im
//   Kopf). Zeilen und zyklomatische Komplexität (CC) samt Grenzen kommen aus
//   atlas.server.metrics (Grenzen = Option max der Regeln metric-*); ohne
//   Metriken zählen die Zeilen der Gliederung, CC bleibt unbekannt.
// Zeilen 0-basiert.

interface

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Settings.ProblemsUpdate,
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Metrics;

type
  TAtlasStatusCounts = array[TAtlasFindingKind] of Integer;

  TAtlasStatusLiveTexts = record
    /// <summary>„live“.</summary>
    Live: string;
    /// <summary>„beim Speichern“.</summary>
    OnSave: string;
    /// <summary>„manuell“ (problems.update manual).</summary>
    Manual: string;
    /// <summary>Tooltip je Art: „Prüft beim Tippen …“, „Prüft erst nach dem Speichern …“, „Prüft nur auf
    /// Anforderung …“.</summary>
    LiveHint: string;
    OnSaveHint: string;
    ManualHint: string;
    /// <summary>Tooltip zum Klick: „Klick: alle Units neu prüfen“ (live) bzw. „Klick: Datei jetzt prüfen“.</summary>
    RecheckClick: string;
    CheckFileClick: string;
    /// <summary>„prüft …“.</summary>
    Checking: string;
    /// <summary>„geprüft vor %s“.</summary>
    CheckedAgo: string;
    /// <summary>„%d s“, „%d min“, „%d h“.</summary>
    Seconds: string;
    Minutes: string;
    Hours: string;
    /// <summary>Trenner zwischen den Teilen („ · “).</summary>
    Separator: string;
    /// <summary>„Projekt %d %%“ (#1232).</summary>
    ProjectProgress: string;
    /// <summary>„Projekt fertig“ nach dem Ende des Laufs (#1247).</summary>
    ProjectDone: string;
    /// <summary>„pausiert (Kompilieren)“ hinter dem Fortschritt (#1247).</summary>
    ProjectPaused: string;
  end;

  TAtlasStatusMethod = record
    /// <summary>Methode am Cursor gefunden.</summary>
    Found: Boolean;
    /// <summary>Qualifizierter Name („TFoo.Bar“).</summary>
    Name: string;
    /// <summary>Sprungziel: Anfang des Namens im Kopf.</summary>
    Line: Integer;
    Character: Integer;
    Lines: Integer;
    /// <summary>Zyklomatische Komplexität; -1 = unbekannt (keine Metriken).</summary>
    Cyclomatic: Integer;
    /// <summary>Grenzen der Regeln metric-method-length bzw. metric-cyclomatic; MaxInt = keine.</summary>
    LinesLimit: Integer;
    CyclomaticLimit: Integer;
    function LinesOver: Boolean;
    function CyclomaticOver: Boolean;
    /// <summary>Mindestens eine Kennzahl über ihrer Grenze (Warnfarbe).</summary>
    function Over: Boolean;
  end;

  TAtlasStatusBarContent = class
  public const
    /// <summary>So lange steht „Projekt fertig“ nach dem Ende des Laufs (#1247).</summary>
    cProjectDoneMs = 5000;
  public
    /// <summary>Zählt der Eintrag in der Leiste? Wie im Fenster „Atlas-Prüfung“.</summary>
    class function Counted(const AProblem: TAtlasProblem; AWithCompiler: Boolean): Boolean; static;
    class function CountsOf(const AProblems: TArray<TAtlasProblem>; AWithCompiler: Boolean): TAtlasStatusCounts;
      static;
    /// <summary>Nächster gezählter Befund der Art AKind nach ALine/ACharacter, am Ende wieder vom Anfang; False
    /// ohne Befund dieser Art.</summary>
    class function NextOf(const AProblems: TArray<TAtlasProblem>; AKind: TAtlasFindingKind;
      AWithCompiler: Boolean; ALine, ACharacter: Integer; out ATarget: TAtlasProblem): Boolean; static;
    /// <summary>Alter als „2 s“, „3 min“, „1 h“ (abgerundet, nie negativ).</summary>
    class function AgeText(ASeconds: Int64; const ATexts: TAtlasStatusLiveTexts): string; static;
    /// <summary>Text der Live-Prüfung zur Art AMode (problems.update). ACheckedAt = 0: Datei noch nicht geprüft.
    /// </summary>
    class function LiveText(AMode: TAtlasProblemsUpdate; AChecking: Boolean; ACheckedAt, ANow: TDateTime;
      const ATexts: TAtlasStatusLiveTexts): string; static;
    /// <summary>Tooltip der Live-Prüfung zur Art AMode; mit AClickable zusätzlich, was ein Klick tut.</summary>
    class function LiveHint(AMode: TAtlasProblemsUpdate; AClickable: Boolean;
      const ATexts: TAtlasStatusLiveTexts): string; static;
    /// <summary>Prüft ein Klick auf die Live-Prüfung nur die offene Datei (save, manual) statt alle Units neu
    /// (live, #1231)?</summary>
    class function ClickChecksFile(AMode: TAtlasProblemsUpdate): Boolean; static;
    /// <summary>Anhang „ · Projekt 45 %“, solange die Projektprüfung nicht alle ATotal Units hat (#1232); sonst ''.
    /// Abgerundet: 100 % erst, wenn alle geprüft sind.</summary>
    class function ProgressText(AChecked, ATotal: Integer; const ATexts: TAtlasStatusLiveTexts): string; static;
    /// <summary>Anhang zum Lauf der Projektprüfung des Servers (#1247): während des Laufs „ · Projekt 45 %“, beim
    /// Kompilieren mit „pausiert (Kompilieren)“; nach dem Ende ProjectDoneMs lang „ · Projekt fertig“; sonst ''.
    /// </summary>
    class function RunText(AActive: Boolean; ADone, ATotal: Integer; const APaused: string;
      AFinishedAgoMs: UInt64; const ATexts: TAtlasStatusLiveTexts): string; static;
    /// <summary>Methode am Cursor (ALine) aus der Gliederung, Kennzahlen aus AMetrics, sofern AMetricsKnown.
    /// </summary>
    class function MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer; const AMetrics: TAtlasFileMetrics;
      AMetricsKnown: Boolean): TAtlasStatusMethod; static;
    /// <summary>Kennzahlen als Text, z. B. „4 Zeilen · CC 2“; ALinesFormat und ACyclomaticFormat mit %d.</summary>
    class function MethodDetail(const AMethod: TAtlasStatusMethod; const ALinesFormat, ACyclomaticFormat,
      ASeparator: string): string; static;
    /// <summary>Kennzahlen mit Grenze, z. B. „CC 17 (Grenze 15)“; ALimitFormat mit %s für den Teil und %d für die
    /// Grenze. Teile ohne Grenze stehen ohne Zusatz.</summary>
    class function MethodLimits(const AMethod: TAtlasStatusMethod; const ALinesFormat, ACyclomaticFormat,
      ALimitFormat, ASeparator: string): string; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Outline.Breadcrumbs;

{ TAtlasStatusMethod }

function TAtlasStatusMethod.LinesOver: Boolean;
begin
  Result := Found and (LinesLimit < MaxInt) and (Lines > LinesLimit);
end;

function TAtlasStatusMethod.CyclomaticOver: Boolean;
begin
  Result := Found and (Cyclomatic >= 0) and (CyclomaticLimit < MaxInt) and (Cyclomatic > CyclomaticLimit);
end;

function TAtlasStatusMethod.Over: Boolean;
begin
  Result := LinesOver or CyclomaticOver;
end;

{ TAtlasStatusBarContent }

class function TAtlasStatusBarContent.Counted(const AProblem: TAtlasProblem; AWithCompiler: Boolean): Boolean;
begin
  Result := TAtlasFindings.IsFinding(AProblem) and (AWithCompiler or not AProblem.IsCompiler);
end;

class function TAtlasStatusBarContent.CountsOf(const AProblems: TArray<TAtlasProblem>;
  AWithCompiler: Boolean): TAtlasStatusCounts;
var
  mKind: TAtlasFindingKind;
  mProblem: TAtlasProblem;
begin
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    Result[mKind] := 0;
  end;
  for mProblem in AProblems do
  begin
    if Counted(mProblem, AWithCompiler) then
    begin
      Inc(Result[TAtlasFindings.KindOf(mProblem.Severity)]);
    end;
  end;
end;

function Before(ALine, ACharacter, AOtherLine, AOtherCharacter: Integer): Boolean;
begin
  Result := (ALine < AOtherLine) or ((ALine = AOtherLine) and (ACharacter < AOtherCharacter));
end;

class function TAtlasStatusBarContent.NextOf(const AProblems: TArray<TAtlasProblem>; AKind: TAtlasFindingKind;
  AWithCompiler: Boolean; ALine, ACharacter: Integer; out ATarget: TAtlasProblem): Boolean;
var
  mProblem, mFirst: TAtlasProblem;
  mFound, mAny: Boolean;
begin
  ATarget := Default(TAtlasProblem);
  mFirst := Default(TAtlasProblem);
  mFound := False;
  mAny := False;
  for mProblem in AProblems do
  begin
    if not Counted(mProblem, AWithCompiler) or (TAtlasFindings.KindOf(mProblem.Severity) <> AKind) then
    begin
      Continue;
    end;
    // Der erste der Datei für den Umlauf.
    if not mAny or Before(mProblem.StartLine, mProblem.StartCharacter, mFirst.StartLine, mFirst.StartCharacter) then
    begin
      mFirst := mProblem;
    end;
    mAny := True;
    if Before(ALine, ACharacter, mProblem.StartLine, mProblem.StartCharacter) and
      (not mFound or Before(mProblem.StartLine, mProblem.StartCharacter, ATarget.StartLine,
        ATarget.StartCharacter)) then
    begin
      ATarget := mProblem;
      mFound := True;
    end;
  end;
  if not mFound and mAny then
  begin
    ATarget := mFirst;
    mFound := True;
  end;
  Result := mFound;
end;

class function TAtlasStatusBarContent.AgeText(ASeconds: Int64; const ATexts: TAtlasStatusLiveTexts): string;
begin
  if ASeconds < 0 then
  begin
    ASeconds := 0;
  end;
  if ASeconds < 60 then
  begin
    Result := Format(ATexts.Seconds, [ASeconds]);
  end
  else if ASeconds < 3600 then
  begin
    Result := Format(ATexts.Minutes, [ASeconds div 60]);
  end
  else
  begin
    Result := Format(ATexts.Hours, [ASeconds div 3600]);
  end;
end;

class function TAtlasStatusBarContent.LiveText(AMode: TAtlasProblemsUpdate; AChecking: Boolean; ACheckedAt,
  ANow: TDateTime; const ATexts: TAtlasStatusLiveTexts): string;
var
  mAge: Int64;
begin
  if AChecking then
  begin
    Exit(ATexts.Checking);
  end;
  case AMode of
    TAtlasProblemsUpdate.Save:
      Exit(ATexts.OnSave);
    TAtlasProblemsUpdate.Manual:
      Result := ATexts.Manual;
  else
    Result := ATexts.Live;
  end;
  if ACheckedAt <= 0 then
  begin
    Exit;
  end;
  // Uhr zurückgestellt: nicht „vor −5 s“.
  mAge := 0;
  if ANow > ACheckedAt then
  begin
    mAge := SecondsBetween(ANow, ACheckedAt);
  end;
  Result := Result + ATexts.Separator + Format(ATexts.CheckedAgo, [AgeText(mAge, ATexts)]);
end;

class function TAtlasStatusBarContent.LiveHint(AMode: TAtlasProblemsUpdate; AClickable: Boolean;
  const ATexts: TAtlasStatusLiveTexts): string;
begin
  case AMode of
    TAtlasProblemsUpdate.Save:
      Result := ATexts.OnSaveHint;
    TAtlasProblemsUpdate.Manual:
      Result := ATexts.ManualHint;
  else
    Result := ATexts.LiveHint;
  end;
  if not AClickable then
  begin
    Exit;
  end;
  if ClickChecksFile(AMode) then
  begin
    Result := Result + sLineBreak + ATexts.CheckFileClick;
  end
  else
  begin
    Result := Result + sLineBreak + ATexts.RecheckClick;
  end;
end;

class function TAtlasStatusBarContent.ClickChecksFile(AMode: TAtlasProblemsUpdate): Boolean;
begin
  Result := AMode <> TAtlasProblemsUpdate.Live;
end;

class function TAtlasStatusBarContent.ProgressText(AChecked, ATotal: Integer;
  const ATexts: TAtlasStatusLiveTexts): string;
begin
  if (ATotal <= 0) or (AChecked >= ATotal) then
  begin
    Exit('');
  end;
  if AChecked < 0 then
  begin
    AChecked := 0;
  end;
  Result := ATexts.Separator + Format(ATexts.ProjectProgress, [Int64(AChecked) * 100 div ATotal]);
end;

class function TAtlasStatusBarContent.RunText(AActive: Boolean; ADone, ATotal: Integer; const APaused: string;
  AFinishedAgoMs: UInt64; const ATexts: TAtlasStatusLiveTexts): string;
begin
  Result := '';
  if ATotal <= 0 then
  begin
    Exit;
  end;
  if not AActive then
  begin
    if AFinishedAgoMs < cProjectDoneMs then
    begin
      Result := ATexts.Separator + ATexts.ProjectDone;
    end;
    Exit;
  end;
  if ADone < 0 then
  begin
    ADone := 0;
  end;
  if ADone > ATotal then
  begin
    ADone := ATotal;
  end;
  Result := ATexts.Separator + Format(ATexts.ProjectProgress, [Int64(ADone) * 100 div ATotal]);
  // Debuggen meldet die Statusleiste schon selbst; der Indexaufbau gehört zum Lauf.
  if APaused = 'compile' then
  begin
    Result := Result + ' ' + ATexts.ProjectPaused;
  end;
end;

/// <summary>Innerste Methode bzw. Routine, die ALine umfasst; -1 ohne.</summary>
function NodeAt(const ANodes: TAtlasOutlineNodes; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    if not (ANodes[mIndex].Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) then
    begin
      Continue;
    end;
    if (ALine < ANodes[mIndex].StartLine) or (ALine > ANodes[mIndex].EndLine) then
    begin
      Continue;
    end;
    // Die innerste: der späteste Anfang.
    if (Result < 0) or (ANodes[mIndex].StartLine >= ANodes[Result].StartLine) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Kennzahlen der Methode: Kopfzeile des Namens, sonst gleicher Name; -1 ohne.</summary>
function MetricsIndex(const AMetrics: TAtlasFileMetrics; ALine: Integer; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := AMetrics.IndexAt(ALine);
  if Result >= 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AMetrics.Methods) do
  begin
    if SameText(AMetrics.Methods[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasStatusBarContent.MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer;
  const AMetrics: TAtlasFileMetrics; AMetricsKnown: Boolean): TAtlasStatusMethod;
var
  mNode, mIndex: Integer;
  mValues: TAtlasMetricValues;
begin
  Result := Default(TAtlasStatusMethod);
  Result.Cyclomatic := -1;
  Result.LinesLimit := MaxInt;
  Result.CyclomaticLimit := MaxInt;
  mNode := NodeAt(ANodes, ALine);
  if mNode < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.Name := TAtlasBreadcrumbs.QualifiedName(ANodes, mNode);
  Result.Line := ANodes[mNode].NameLine;
  Result.Character := ANodes[mNode].NameCharacter;
  Result.Lines := ANodes[mNode].EndLine - ANodes[mNode].StartLine + 1;
  if not AMetricsKnown then
  begin
    Exit;
  end;
  Result.LinesLimit := AMetrics.Limits[TAtlasMetric.MethodLength];
  Result.CyclomaticLimit := AMetrics.Limits[TAtlasMetric.Cyclomatic];
  mIndex := MetricsIndex(AMetrics, ANodes[mNode].NameLine, Result.Name);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mValues := AMetrics.Methods[mIndex].Values;
  // Dieselben Zahlen wie die Regeln metric-*.
  if mValues[TAtlasMetric.MethodLength] > 0 then
  begin
    Result.Lines := mValues[TAtlasMetric.MethodLength];
  end;
  Result.Cyclomatic := mValues[TAtlasMetric.Cyclomatic];
end;

class function TAtlasStatusBarContent.MethodDetail(const AMethod: TAtlasStatusMethod; const ALinesFormat,
  ACyclomaticFormat, ASeparator: string): string;
begin
  if not AMethod.Found then
  begin
    Exit('');
  end;
  Result := Format(ALinesFormat, [AMethod.Lines]);
  if AMethod.Cyclomatic >= 0 then
  begin
    Result := Result + ASeparator + Format(ACyclomaticFormat, [AMethod.Cyclomatic]);
  end;
end;

class function TAtlasStatusBarContent.MethodLimits(const AMethod: TAtlasStatusMethod; const ALinesFormat,
  ACyclomaticFormat, ALimitFormat, ASeparator: string): string;
var
  mPart: string;
begin
  if not AMethod.Found then
  begin
    Exit('');
  end;
  Result := Format(ALinesFormat, [AMethod.Lines]);
  if AMethod.LinesLimit < MaxInt then
  begin
    Result := Format(ALimitFormat, [Result, AMethod.LinesLimit]);
  end;
  if AMethod.Cyclomatic < 0 then
  begin
    Exit;
  end;
  mPart := Format(ACyclomaticFormat, [AMethod.Cyclomatic]);
  if AMethod.CyclomaticLimit < MaxInt then
  begin
    mPart := Format(ALimitFormat, [mPart, AMethod.CyclomaticLimit]);
  end;
  Result := Result + ASeparator + mPart;
end;

end.
