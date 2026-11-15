unit Atlas.Core.Problems.Marks;

// Unterstreichungen der Probleme im Editor (#398), Entscheidungen ohne IDE und
// VCL (#1967):
// - CharRange: Zeichenbereich eines Problems in einer seiner Zeilen; ein leerer
//   Bereich wird ein Zeichen, am Zeilenende das letzte.
// - Column: Editorspalte zu einem Zeichenindex, Tabs aufgelöst.
// - HideTarget: Ausblenden am Element (#628): Befunde mit Regel über die Regel
//   an ihrer Startzeile, andere (Compiler) je Codezeile.
// - Lines: Zeilen, die die Probleme belegen (je Problem höchstens MaxSpan).

interface

uses
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.Hide;

type
  TAtlasProblemMarks = record
  public const
    /// <summary>Höchstens so viele Zeilen eines Problems werden verfolgt.</summary>
    cMaxSpan = 64;
  public
    class procedure CharRange(const AProblem: TAtlasProblem; ALine: Integer; const AText: string; out AFrom,
      ATill: Integer); static;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine.</summary>
    class function Column(const ALine: string; ACharacter, ATabWidth: Integer): Integer; static;
    class function HideTarget(const AFileName: string; const AProblem: TAtlasProblem; ALine: Integer;
      const AText: string): TAtlasHideTarget; static;
    class function Lines(const AProblems: TArray<TAtlasProblem>): TArray<Integer>; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Editor.Pairs;

class procedure TAtlasProblemMarks.CharRange(const AProblem: TAtlasProblem; ALine: Integer; const AText: string;
  out AFrom, ATill: Integer);
begin
  AFrom := 0;
  ATill := Length(AText);
  if ALine = AProblem.StartLine then
  begin
    AFrom := AProblem.StartCharacter;
  end;
  if ALine = AProblem.EndLine then
  begin
    ATill := AProblem.EndCharacter;
  end;
  AFrom := EnsureRange(AFrom, 0, Length(AText));
  ATill := EnsureRange(ATill, 0, Length(AText));
  if ATill <= AFrom then
  begin
    if AFrom >= Length(AText) then
    begin
      AFrom := Max(0, Length(AText) - 1);
    end;
    ATill := AFrom + 1;
  end;
end;

class function TAtlasProblemMarks.Column(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(TAtlasPairs.DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

class function TAtlasProblemMarks.HideTarget(const AFileName: string; const AProblem: TAtlasProblem; ALine: Integer;
  const AText: string): TAtlasHideTarget;
begin
  if not AProblem.IsCompiler and (AProblem.Code <> '') then
  begin
    Result := TAtlasHideTarget.Finding(AFileName, AProblem.StartLine, AProblem.Code, AText);
  end
  else
  begin
    Result := TAtlasHideTarget.Finding(AFileName, ALine, '', AText);
  end;
  Result.Caption := AProblem.Caption;
end;

class function TAtlasProblemMarks.Lines(const AProblems: TArray<TAtlasProblem>): TArray<Integer>;
const
  cFirstCapacity = 16;
var
  mProblem: TAtlasProblem;
  mLine, mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  for mProblem in AProblems do
  begin
    for mLine := mProblem.StartLine to Min(mProblem.EndLine, mProblem.StartLine + cMaxSpan - 1) do
    begin
      if mCount = Length(Result) then
      begin
        SetLength(Result, Max(cFirstCapacity, 2 * mCount));
      end;
      Result[mCount] := mLine;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

end.
