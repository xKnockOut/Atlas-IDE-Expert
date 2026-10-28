unit Atlas.Core.StatusBar.Content;

// Atlas-Statusleiste (#1155), Inhalte ohne VCL und OTA:
// - Meldungen dieser Unit: Zähler je Art wie im Fenster „Atlas-Prüfung“
//   (TAtlasFindings.IsFinding, Art aus dem Schweregrad; Compilermeldungen nur
//   mit AWithCompiler wie problems.window.compiler). NextOf liefert den
//   nächsten Befund einer Art nach dem Cursor, am Ende wieder vom Anfang.
// - Live-Prüfung: „prüft …“ während einer Prüfung, sonst „live“ bzw. „beim
//   Speichern“ (problems.live aus), bei live mit dem Alter der letzten
//   Prüfung dieser Datei („live · geprüft vor 2 s“). Die Texte kommen von der
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
  Atlas.Core.Outline.Model,
  Atlas.Core.Editor.Metrics;

type
  TAtlasStatusCounts = array[TAtlasFindingKind] of Integer;

  TAtlasStatusLiveTexts = record
    /// <summary>„live“.</summary>
    Live: string;
    /// <summary>„beim Speichern“.</summary>
    OnSave: string;
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
    /// <summary>Text der Live-Prüfung. ACheckedAt = 0: Datei noch nicht geprüft.</summary>
    class function LiveText(ALive, AChecking: Boolean; ACheckedAt, ANow: TDateTime;
      const ATexts: TAtlasStatusLiveTexts): string; static;
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
  Kind: TAtlasFindingKind;
  Problem: TAtlasProblem;
begin
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    Result[Kind] := 0;
  for Problem in AProblems do
    if Counted(Problem, AWithCompiler) then
      Inc(Result[TAtlasFindings.KindOf(Problem.Severity)]);
end;

function Before(ALine, ACharacter, AOtherLine, AOtherCharacter: Integer): Boolean;
begin
  Result := (ALine < AOtherLine) or ((ALine = AOtherLine) and (ACharacter < AOtherCharacter));
end;

class function TAtlasStatusBarContent.NextOf(const AProblems: TArray<TAtlasProblem>; AKind: TAtlasFindingKind;
  AWithCompiler: Boolean; ALine, ACharacter: Integer; out ATarget: TAtlasProblem): Boolean;
var
  Problem, First: TAtlasProblem;
  Found, Any: Boolean;
begin
  ATarget := Default(TAtlasProblem);
  First := Default(TAtlasProblem);
  Found := False;
  Any := False;
  for Problem in AProblems do
  begin
    if not Counted(Problem, AWithCompiler) or (TAtlasFindings.KindOf(Problem.Severity) <> AKind) then
      Continue;
    // Der erste der Datei für den Umlauf.
    if not Any or Before(Problem.StartLine, Problem.StartCharacter, First.StartLine, First.StartCharacter) then
      First := Problem;
    Any := True;
    if Before(ALine, ACharacter, Problem.StartLine, Problem.StartCharacter) and
      (not Found or Before(Problem.StartLine, Problem.StartCharacter, ATarget.StartLine, ATarget.StartCharacter)) then
    begin
      ATarget := Problem;
      Found := True;
    end;
  end;
  if not Found and Any then
  begin
    ATarget := First;
    Found := True;
  end;
  Result := Found;
end;

class function TAtlasStatusBarContent.AgeText(ASeconds: Int64; const ATexts: TAtlasStatusLiveTexts): string;
begin
  if ASeconds < 0 then
    ASeconds := 0;
  if ASeconds < 60 then
    Result := Format(ATexts.Seconds, [ASeconds])
  else if ASeconds < 3600 then
    Result := Format(ATexts.Minutes, [ASeconds div 60])
  else
    Result := Format(ATexts.Hours, [ASeconds div 3600]);
end;

class function TAtlasStatusBarContent.LiveText(ALive, AChecking: Boolean; ACheckedAt, ANow: TDateTime;
  const ATexts: TAtlasStatusLiveTexts): string;
var
  Age: Int64;
begin
  if AChecking then
    Exit(ATexts.Checking);
  if not ALive then
    Exit(ATexts.OnSave);
  Result := ATexts.Live;
  if ACheckedAt <= 0 then
    Exit;
  // Uhr zurückgestellt: nicht „vor −5 s“.
  Age := 0;
  if ANow > ACheckedAt then
    Age := SecondsBetween(ANow, ACheckedAt);
  Result := Result + ATexts.Separator + Format(ATexts.CheckedAgo, [AgeText(Age, ATexts)]);
end;

class function TAtlasStatusBarContent.ProgressText(AChecked, ATotal: Integer;
  const ATexts: TAtlasStatusLiveTexts): string;
begin
  if (ATotal <= 0) or (AChecked >= ATotal) then
    Exit('');
  if AChecked < 0 then
    AChecked := 0;
  Result := ATexts.Separator + Format(ATexts.ProjectProgress, [Int64(AChecked) * 100 div ATotal]);
end;

class function TAtlasStatusBarContent.RunText(AActive: Boolean; ADone, ATotal: Integer; const APaused: string;
  AFinishedAgoMs: UInt64; const ATexts: TAtlasStatusLiveTexts): string;
begin
  Result := '';
  if ATotal <= 0 then
    Exit;
  if not AActive then
  begin
    if AFinishedAgoMs < cProjectDoneMs then
      Result := ATexts.Separator + ATexts.ProjectDone;
    Exit;
  end;
  if ADone < 0 then
    ADone := 0;
  if ADone > ATotal then
    ADone := ATotal;
  Result := ATexts.Separator + Format(ATexts.ProjectProgress, [Int64(ADone) * 100 div ATotal]);
  // Debuggen meldet die Statusleiste schon selbst; der Indexaufbau gehört zum Lauf.
  if APaused = 'compile' then
    Result := Result + ' ' + ATexts.ProjectPaused;
end;

/// <summary>Innerste Methode bzw. Routine, die ALine umfasst; -1 ohne.</summary>
function NodeAt(const ANodes: TAtlasOutlineNodes; ALine: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ANodes) do
  begin
    if not (ANodes[Index].Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) then
      Continue;
    if (ALine < ANodes[Index].StartLine) or (ALine > ANodes[Index].EndLine) then
      Continue;
    // Die innerste: der späteste Anfang.
    if (Result < 0) or (ANodes[Index].StartLine >= ANodes[Result].StartLine) then
      Result := Index;
  end;
end;

/// <summary>Kennzahlen der Methode: Kopfzeile des Namens, sonst gleicher Name; -1 ohne.</summary>
function MetricsIndex(const AMetrics: TAtlasFileMetrics; ALine: Integer; const AName: string): Integer;
var
  Index: Integer;
begin
  Result := AMetrics.IndexAt(ALine);
  if Result >= 0 then
    Exit;
  for Index := 0 to High(AMetrics.Methods) do
    if SameText(AMetrics.Methods[Index].Name, AName) then
      Exit(Index);
end;

class function TAtlasStatusBarContent.MethodAt(const ANodes: TAtlasOutlineNodes; ALine: Integer;
  const AMetrics: TAtlasFileMetrics; AMetricsKnown: Boolean): TAtlasStatusMethod;
var
  Node, Index: Integer;
  Values: TAtlasMetricValues;
begin
  Result := Default(TAtlasStatusMethod);
  Result.Cyclomatic := -1;
  Result.LinesLimit := MaxInt;
  Result.CyclomaticLimit := MaxInt;
  Node := NodeAt(ANodes, ALine);
  if Node < 0 then
    Exit;
  Result.Found := True;
  Result.Name := TAtlasBreadcrumbs.QualifiedName(ANodes, Node);
  Result.Line := ANodes[Node].NameLine;
  Result.Character := ANodes[Node].NameCharacter;
  Result.Lines := ANodes[Node].EndLine - ANodes[Node].StartLine + 1;
  if not AMetricsKnown then
    Exit;
  Result.LinesLimit := AMetrics.Limits[TAtlasMetric.MethodLength];
  Result.CyclomaticLimit := AMetrics.Limits[TAtlasMetric.Cyclomatic];
  Index := MetricsIndex(AMetrics, ANodes[Node].NameLine, Result.Name);
  if Index < 0 then
    Exit;
  Values := AMetrics.Methods[Index].Values;
  // Dieselben Zahlen wie die Regeln metric-*.
  if Values[TAtlasMetric.MethodLength] > 0 then
    Result.Lines := Values[TAtlasMetric.MethodLength];
  Result.Cyclomatic := Values[TAtlasMetric.Cyclomatic];
end;

class function TAtlasStatusBarContent.MethodDetail(const AMethod: TAtlasStatusMethod; const ALinesFormat,
  ACyclomaticFormat, ASeparator: string): string;
begin
  if not AMethod.Found then
    Exit('');
  Result := Format(ALinesFormat, [AMethod.Lines]);
  if AMethod.Cyclomatic >= 0 then
    Result := Result + ASeparator + Format(ACyclomaticFormat, [AMethod.Cyclomatic]);
end;

class function TAtlasStatusBarContent.MethodLimits(const AMethod: TAtlasStatusMethod; const ALinesFormat,
  ACyclomaticFormat, ALimitFormat, ASeparator: string): string;
var
  Part: string;
begin
  if not AMethod.Found then
    Exit('');
  Result := Format(ALinesFormat, [AMethod.Lines]);
  if AMethod.LinesLimit < MaxInt then
    Result := Format(ALimitFormat, [Result, AMethod.LinesLimit]);
  if AMethod.Cyclomatic < 0 then
    Exit;
  Part := Format(ACyclomaticFormat, [AMethod.Cyclomatic]);
  if AMethod.CyclomaticLimit < MaxInt then
    Part := Format(ALimitFormat, [Part, AMethod.CyclomaticLimit]);
  Result := Result + ASeparator + Part;
end;

end.
