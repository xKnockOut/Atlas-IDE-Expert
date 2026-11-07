unit Atlas.Core.Problems.InlineHints;

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
function Before(ALine, ACharacter, ABLine, ABCharacter: Integer): Boolean;
begin
  Result := (ALine < ABLine) or ((ALine = ABLine) and (ACharacter < ABCharacter));
end;

{ TAtlasProblemCounts }

function TAtlasProblemCounts.Total: Integer;
begin
  Result := Errors + Warnings + Hints;
end;

{ TAtlasInlineDiagnostics }

class function TAtlasInlineDiagnostics.ModeOf(const AName: string): TAtlasInlineDiagnosticsMode;
var
  mMode: TAtlasInlineDiagnosticsMode;
begin
  for mMode := Low(TAtlasInlineDiagnosticsMode) to High(TAtlasInlineDiagnosticsMode) do
  begin
    if SameText(Trim(AName), ModeNames[mMode]) then
    begin
      Exit(mMode);
    end;
  end;
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
  mProblem: TAtlasProblem;
  mCount: Integer;
begin
  AResult := Default(TAtlasInlineDiagnostic);
  mCount := 0;
  for mProblem in AProblems do
  begin
    if (mProblem.StartLine <> ALine) or not IsFinding(mProblem) or not Shows(AMode, mProblem.Severity) then
    begin
      Continue;
    end;
    // Bei gleichem Schweregrad gewinnt die erste (weiter links).
    if (mCount = 0) or (Rank(mProblem.Severity) < Rank(AResult.Problem.Severity)) or
      ((Rank(mProblem.Severity) = Rank(AResult.Problem.Severity)) and
      (mProblem.StartCharacter < AResult.Problem.StartCharacter)) then
    begin
      AResult.Problem := mProblem;
    end;
    Inc(mCount);
  end;
  Result := mCount > 0;
  if Result then
  begin
    AResult.More := mCount - 1;
  end;
end;

class function TAtlasInlineDiagnostics.Caption(const ADiagnostic: TAtlasInlineDiagnostic): string;
var
  mCut: Integer;
begin
  Result := ADiagnostic.Problem.Message;
  mCut := Pos(#10, Result);
  if mCut > 0 then
  begin
    Result := Copy(Result, 1, mCut - 1);
  end;
  Result := Trim(StringReplace(Result, #13, '', [rfReplaceAll]));
  if Length(Result) > MaxChars then
  begin
    Result := TrimRight(Copy(Result, 1, MaxChars - 1)) + '…';
  end;
  if ADiagnostic.More > 0 then
  begin
    Result := Result + ' (+' + IntToStr(ADiagnostic.More) + ')';
  end;
end;

class function TAtlasInlineDiagnostics.Counts(const AProblems: TArray<TAtlasProblem>): TAtlasProblemCounts;
var
  mProblem: TAtlasProblem;
begin
  Result := Default(TAtlasProblemCounts);
  for mProblem in AProblems do
  begin
    if mProblem.IsCompiler or not IsFinding(mProblem) then
    begin
      Continue;
    end;
    case mProblem.Severity of
      TAtlasProblemSeverity.Error:
        Inc(Result.Errors);
      TAtlasProblemSeverity.Warning:
        Inc(Result.Warnings);
    else
      Inc(Result.Hints);
    end;
  end;
end;

/// <summary>Steht A in Richtung AForward vor B (vorwärts: weiter oben, rückwärts: weiter unten)?</summary>
function Ahead(const A, B: TAtlasProblem; AForward: Boolean): Boolean;
begin
  if AForward then
  begin
    Result := Before(A.StartLine, A.StartCharacter, B.StartLine, B.StartCharacter);
  end
  else
  begin
    Result := Before(B.StartLine, B.StartCharacter, A.StartLine, A.StartCharacter);
  end;
end;

class function TAtlasInlineDiagnostics.Next(const AProblems: TArray<TAtlasProblem>; ALine, ACharacter: Integer;
  AForward: Boolean; out ATarget: TAtlasProblem): Boolean;
var
  mProblem, mEdge, mCursor: TAtlasProblem;
  mWrap: Boolean;
begin
  ATarget := Default(TAtlasProblem);
  mEdge := Default(TAtlasProblem);
  mCursor := Default(TAtlasProblem);
  mCursor.StartLine := ALine;
  mCursor.StartCharacter := ACharacter;
  Result := False;
  mWrap := False;
  for mProblem in AProblems do
  begin
    if not IsFinding(mProblem) then
    begin
      Continue;
    end;
    // Am anderen Ende für den Umlauf: der erste bzw. letzte Befund der Datei.
    if not mWrap or Ahead(mProblem, mEdge, AForward) then
    begin
      mEdge := mProblem;
    end;
    mWrap := True;
    if Ahead(mCursor, mProblem, AForward) and (not Result or Ahead(mProblem, ATarget, AForward)) then
    begin
      ATarget := mProblem;
      Result := True;
    end;
  end;
  if not Result and mWrap then
  begin
    ATarget := mEdge;
    Result := True;
  end;
end;

class function TAtlasInlineDiagnostics.PauseOver(ATypedAt, ANow: Cardinal): Boolean;
begin
  // Cardinal-Arithmetik übersteht den Überlauf von GetTickCount.
  Result := (ATypedAt = 0) or (Cardinal(ANow - ATypedAt) >= PauseMs);
end;

end.
