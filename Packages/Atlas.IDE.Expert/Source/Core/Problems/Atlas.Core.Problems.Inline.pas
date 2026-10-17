unit Atlas.Core.Problems.Inline;

// Fehlertext am Zeilenende (#509), ohne VCL und Open Tools API:
// - Mode: editor.inlineDiagnostics (off, errors, errorsAndWarnings, all).
// - Pick: je Zeile die schwerste Diagnose, die mit ihrer ersten Zeile hier
//   beginnt und zum Modus passt; die übrigen passenden zählen als „(+n)“.
//   Abblendungen (inaktive Zweige, uses-Hinweise) sind keine Befunde.
// - Caption: erste Zeile der Meldung, auf MaxChars gekürzt („…“), dahinter
//   „(+n)“.
// - Counts: Fehler, Warnungen und Hinweise (Info zählt als Hinweis) wie in der
//   Liste „Atlas-Probleme“ (ohne Compilermeldungen) für die Statusleiste.
// - Next: nächster bzw. vorheriger Befund in der Datei ab der Cursorstelle,
//   am Ende wieder von vorn.
// - TypingPause: In der Cursorzeile erscheint der Text erst eine Sekunde nach
//   dem letzten Tastendruck.

interface

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract;

type
{$SCOPEDENUMS ON}
  TAtlasInlineDiagnosticsMode = (Off, Errors, ErrorsAndWarnings, All);
{$SCOPEDENUMS OFF}

  TAtlasInlineDiagnostic = record
    Problem: TAtlasProblem;
    /// <summary>Weitere passende Diagnosen dieser Zeile.</summary>
    More: Integer;
  end;

  TAtlasProblemCounts = record
    Errors: Integer;
    Warnings: Integer;
    /// <summary>Hinweise und Informationen.</summary>
    Hints: Integer;
    function Total: Integer;
  end;

  TAtlasInlineDiagnostics = class
  public const
    MaxChars = 120;
    PauseMs = 1000;
    ModeNames: array[TAtlasInlineDiagnosticsMode] of string = ('off', 'errors', 'errorsAndWarnings', 'all');
  public
    /// <summary>Modus aus dem Namen der Einstellung (ohne Groß-/Kleinschreibung); Unbekanntes = Errors.</summary>
    class function ModeOf(const AName: string): TAtlasInlineDiagnosticsMode; static;
    class function ModeName(AMode: TAtlasInlineDiagnosticsMode): string; static;
    /// <summary>Zeigt AMode Diagnosen mit ASeverity?</summary>
    class function Shows(AMode: TAtlasInlineDiagnosticsMode; ASeverity: TAtlasProblemSeverity): Boolean; static;
    /// <summary>Schwerste passende Diagnose, die in ALine (0-basiert) beginnt; False ohne.</summary>
    class function Pick(const AProblems: TArray<TAtlasProblem>; ALine: Integer; AMode: TAtlasInlineDiagnosticsMode;
      out AResult: TAtlasInlineDiagnostic): Boolean; static;
    /// <summary>Text am Zeilenende, z. B. "Undeklarierter Bezeichner: 'X' (+2)".</summary>
    class function Caption(const ADiagnostic: TAtlasInlineDiagnostic): string; static;
    /// <summary>Zähler über alle Dateien; ohne Compilermeldungen und Abblendungen.</summary>
    class function Counts(const AProblems: TArray<TAtlasProblem>): TAtlasProblemCounts; static;
    /// <summary>Nächster (AForward) bzw. vorheriger Befund ab ALine/ACharacter (0-basiert), am Ende wieder vom
    /// anderen Ende; False ohne Befund. Ein Befund genau an der Stelle zählt nicht.</summary>
    class function Next(const AProblems: TArray<TAtlasProblem>; ALine, ACharacter: Integer; AForward: Boolean;
      out ATarget: TAtlasProblem): Boolean; static;
    /// <summary>Ist die Tipp-Pause seit ATypedAt (Millisekunden, GetTickCount) um? 0 = nie getippt.</summary>
    class function PauseOver(ATypedAt, ANow: Cardinal): Boolean; static;
  end;

implementation

function Rank(ASeverity: TAtlasProblemSeverity): Integer;
begin
  // Kleiner = schwerer.
  Result := Ord(ASeverity);
end;

function IsFinding(const AProblem: TAtlasProblem): Boolean;
begin
  Result := not AProblem.Unnecessary and not AProblem.IsUses;
end;

/// <summary>Liegt A vor B (Zeile, dann Zeichen)?</summary>
function Before(ALine, ACharacter, BLine, BCharacter: Integer): Boolean;
begin
  Result := (ALine < BLine) or ((ALine = BLine) and (ACharacter < BCharacter));
end;

{ TAtlasProblemCounts }

function TAtlasProblemCounts.Total: Integer;
begin
  Result := Errors + Warnings + Hints;
end;

{ TAtlasInlineDiagnostics }

class function TAtlasInlineDiagnostics.ModeOf(const AName: string): TAtlasInlineDiagnosticsMode;
var
  Mode: TAtlasInlineDiagnosticsMode;
begin
  for Mode := Low(TAtlasInlineDiagnosticsMode) to High(TAtlasInlineDiagnosticsMode) do
    if SameText(Trim(AName), ModeNames[Mode]) then
      Exit(Mode);
  Result := TAtlasInlineDiagnosticsMode.Errors;
end;

class function TAtlasInlineDiagnostics.ModeName(AMode: TAtlasInlineDiagnosticsMode): string;
begin
  Result := ModeNames[AMode];
end;

class function TAtlasInlineDiagnostics.Shows(AMode: TAtlasInlineDiagnosticsMode;
  ASeverity: TAtlasProblemSeverity): Boolean;
begin
  case AMode of
    TAtlasInlineDiagnosticsMode.Errors:
      Result := ASeverity = TAtlasProblemSeverity.Error;
    TAtlasInlineDiagnosticsMode.ErrorsAndWarnings:
      Result := (ASeverity = TAtlasProblemSeverity.Error) or (ASeverity = TAtlasProblemSeverity.Warning);
    TAtlasInlineDiagnosticsMode.All:
      Result := True;
  else
    Result := False;
  end;
end;

class function TAtlasInlineDiagnostics.Pick(const AProblems: TArray<TAtlasProblem>; ALine: Integer;
  AMode: TAtlasInlineDiagnosticsMode; out AResult: TAtlasInlineDiagnostic): Boolean;
var
  Problem: TAtlasProblem;
  Count: Integer;
begin
  AResult := Default(TAtlasInlineDiagnostic);
  Count := 0;
  for Problem in AProblems do
  begin
    if (Problem.StartLine <> ALine) or not IsFinding(Problem) or not Shows(AMode, Problem.Severity) then
      Continue;
    // Bei gleichem Schweregrad gewinnt die erste (weiter links).
    if (Count = 0) or (Rank(Problem.Severity) < Rank(AResult.Problem.Severity)) or
      ((Rank(Problem.Severity) = Rank(AResult.Problem.Severity)) and
      (Problem.StartCharacter < AResult.Problem.StartCharacter)) then
      AResult.Problem := Problem;
    Inc(Count);
  end;
  Result := Count > 0;
  if Result then
    AResult.More := Count - 1;
end;

class function TAtlasInlineDiagnostics.Caption(const ADiagnostic: TAtlasInlineDiagnostic): string;
var
  Cut: Integer;
begin
  Result := ADiagnostic.Problem.Message;
  Cut := Pos(#10, Result);
  if Cut > 0 then
    Result := Copy(Result, 1, Cut - 1);
  Result := Trim(StringReplace(Result, #13, '', [rfReplaceAll]));
  if Length(Result) > MaxChars then
    Result := TrimRight(Copy(Result, 1, MaxChars - 1)) + '…';
  if ADiagnostic.More > 0 then
    Result := Result + ' (+' + IntToStr(ADiagnostic.More) + ')';
end;

class function TAtlasInlineDiagnostics.Counts(const AProblems: TArray<TAtlasProblem>): TAtlasProblemCounts;
var
  Problem: TAtlasProblem;
begin
  Result := Default(TAtlasProblemCounts);
  for Problem in AProblems do
  begin
    if Problem.IsCompiler or not IsFinding(Problem) then
      Continue;
    case Problem.Severity of
      TAtlasProblemSeverity.Error:
        Inc(Result.Errors);
      TAtlasProblemSeverity.Warning:
        Inc(Result.Warnings);
    else
      Inc(Result.Hints);
    end;
  end;
end;

class function TAtlasInlineDiagnostics.Next(const AProblems: TArray<TAtlasProblem>; ALine, ACharacter: Integer;
  AForward: Boolean; out ATarget: TAtlasProblem): Boolean;
var
  Problem: TAtlasProblem;
  Found, Wrap: Boolean;
  Edge: TAtlasProblem;
begin
  ATarget := Default(TAtlasProblem);
  Edge := Default(TAtlasProblem);
  Found := False;
  Wrap := False;
  for Problem in AProblems do
  begin
    if not IsFinding(Problem) then
      Continue;
    // Am anderen Ende für den Umlauf: der erste bzw. letzte Befund der Datei.
    if not Wrap or (AForward and Before(Problem.StartLine, Problem.StartCharacter, Edge.StartLine,
      Edge.StartCharacter)) or (not AForward and Before(Edge.StartLine, Edge.StartCharacter, Problem.StartLine,
      Problem.StartCharacter)) then
      Edge := Problem;
    Wrap := True;
    if AForward then
    begin
      if Before(ALine, ACharacter, Problem.StartLine, Problem.StartCharacter) and
        (not Found or Before(Problem.StartLine, Problem.StartCharacter, ATarget.StartLine, ATarget.StartCharacter)) then
      begin
        ATarget := Problem;
        Found := True;
      end;
    end
    else if Before(Problem.StartLine, Problem.StartCharacter, ALine, ACharacter) and
      (not Found or Before(ATarget.StartLine, ATarget.StartCharacter, Problem.StartLine, Problem.StartCharacter)) then
    begin
      ATarget := Problem;
      Found := True;
    end;
  end;
  if not Found and Wrap then
  begin
    ATarget := Edge;
    Found := True;
  end;
  Result := Found;
end;

class function TAtlasInlineDiagnostics.PauseOver(ATypedAt, ANow: Cardinal): Boolean;
begin
  // Cardinal-Arithmetik übersteht den Überlauf von GetTickCount.
  Result := (ATypedAt = 0) or (Cardinal(ANow - ATypedAt) >= PauseMs);
end;

end.
