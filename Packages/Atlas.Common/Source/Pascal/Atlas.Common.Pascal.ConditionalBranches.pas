unit Atlas.Common.Pascal.ConditionalBranches;

// Zweige bedingter Übersetzung je Token (#983, #986): Der Syntaxbaum enthält
// beide Zweige von {$IFDEF} … {$ELSE} … {$ENDIF}. Regeln, die zwei Stellen
// vergleichen, fragen hier, ob sich die Stellen ausschließen bzw. ob die eine
// immer mit übersetzt wird, wenn die andere übersetzt wird.
//
// Ein Pfad wie "3.0/5.1" heißt: Zweig 0 des {$IF} Nummer 3, darin Zweig 1
// ({$ELSE} bzw. {$ELSEIF}) des {$IF} Nummer 5; '' steht außerhalb jeder Bedingung.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TConditionalBranches = record
  private
    /// <summary>Ändert den Zweigstapel für die Direktive AName; True bei Beginn eines {$IF…}.</summary>
    class function ApplyDirective(const AName: string; var AStack: TArray<string>; var ANext: Integer): Boolean; static;
  public
    /// <summary>Pfad je Token (gleiche Länge wie ATokens); leer, wenn der Text keine {$IF…} enthält.</summary>
    class function Paths(const ATokens: TArray<TPascalToken>): TArray<string>; static;
    /// <summary>Pfad des Tokens AIndex aus APaths; '' ohne Bedingungen.</summary>
    class function PathAt(const APaths: TArray<string>; AIndex: Integer): string; static;
    /// <summary>Werden APath und AOther nie zusammen übersetzt (verschiedene Zweige desselben {$IF})?</summary>
    class function Exclusive(const APath, AOther: string): Boolean; static;
    /// <summary>Wird AOuter immer übersetzt, wenn APath übersetzt wird (AOuter gleich oder umschließend)?</summary>
    class function Implies(const APath, AOuter: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Lexer;

class function TConditionalBranches.ApplyDirective(const AName: string; var AStack: TArray<string>;
  var ANext: Integer): Boolean;
var
  mTop: string;
  mDot: Integer;
begin
  Result := (AName = 'IF') or (AName = 'IFDEF') or (AName = 'IFNDEF') or (AName = 'IFOPT');
  if Result then
  begin
    AStack := AStack + [IntToStr(ANext) + '.0'];
    Inc(ANext);
  end
  else if AStack = nil then
  begin
    Exit;
  end
  else if (AName = 'ELSE') or (AName = 'ELSEIF') then
  begin
    mTop := AStack[High(AStack)];
    mDot := Pos('.', mTop);
    AStack[High(AStack)] := Copy(mTop, 1, mDot) + IntToStr(StrToIntDef(Copy(mTop, mDot + 1, MaxInt), 0) + 1);
  end
  else if (AName = 'ENDIF') or (AName = 'IFEND') then
  begin
    SetLength(AStack, Length(AStack) - 1);
  end;
end;

class function TConditionalBranches.Paths(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mStack: TArray<string>;
  mIndex, mNext: Integer;
  mPath: string;
begin
  Result := nil;
  mStack := nil;
  mNext := 0;
  mPath := '';
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      if ApplyDirective(TPascalLexer.DirectiveName(ATokens[mIndex].Text), mStack, mNext) and (Result = nil) then
      begin
        SetLength(Result, Length(ATokens));
      end;
      mPath := string.Join('/', mStack);
    end;
    if Result <> nil then
    begin
      Result[mIndex] := mPath;
    end;
  end;
end;

class function TConditionalBranches.PathAt(const APaths: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(APaths)) then
  begin
    Result := APaths[AIndex];
  end;
end;

class function TConditionalBranches.Exclusive(const APath, AOther: string): Boolean;
var
  mMine, mTheirs: TArray<string>;
  mPart, mOther: string;
begin
  Result := False;
  if (APath = '') or (AOther = '') or (APath = AOther) then
  begin
    Exit;
  end;
  mMine := APath.Split(['/']);
  mTheirs := AOther.Split(['/']);
  for mPart in mMine do
  begin
    for mOther in mTheirs do
    begin
      if (Copy(mPart, 1, Pos('.', mPart)) = Copy(mOther, 1, Pos('.', mOther))) and (mPart <> mOther) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

class function TConditionalBranches.Implies(const APath, AOuter: string): Boolean;
begin
  Result := (AOuter = '') or (APath = AOuter) or APath.StartsWith(AOuter + '/');
end;

end.
