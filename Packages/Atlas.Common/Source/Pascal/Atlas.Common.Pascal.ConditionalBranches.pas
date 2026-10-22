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

class function TConditionalBranches.Paths(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  Stack: TArray<string>;
  Index, Next, Dot: Integer;
  Name, Path, Top: string;
begin
  Result := nil;
  Stack := nil;
  Next := 0;
  Path := '';
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Kind = TPascalTokenKind.Directive then
    begin
      Name := TPascalLexer.DirectiveName(ATokens[Index].Text);
      if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
      begin
        if Result = nil then
          SetLength(Result, Length(ATokens));
        Stack := Stack + [IntToStr(Next) + '.0'];
        Inc(Next);
      end
      else if ((Name = 'ELSE') or (Name = 'ELSEIF')) and (Stack <> nil) then
      begin
        Top := Stack[High(Stack)];
        Dot := Pos('.', Top);
        Stack[High(Stack)] := Copy(Top, 1, Dot) + IntToStr(StrToIntDef(Copy(Top, Dot + 1, MaxInt), 0) + 1);
      end
      else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (Stack <> nil) then
        SetLength(Stack, Length(Stack) - 1);
      Path := string.Join('/', Stack);
    end;
    if Result <> nil then
      Result[Index] := Path;
  end;
end;

class function TConditionalBranches.PathAt(const APaths: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < Length(APaths)) then
    Result := APaths[AIndex];
end;

class function TConditionalBranches.Exclusive(const APath, AOther: string): Boolean;
var
  Mine, Theirs: TArray<string>;
  Part, Other: string;
begin
  Result := False;
  if (APath = '') or (AOther = '') or (APath = AOther) then
    Exit;
  Mine := APath.Split(['/']);
  Theirs := AOther.Split(['/']);
  for Part in Mine do
    for Other in Theirs do
      if (Copy(Part, 1, Pos('.', Part)) = Copy(Other, 1, Pos('.', Other))) and (Part <> Other) then
        Exit(True);
end;

class function TConditionalBranches.Implies(const APath, AOuter: string): Boolean;
begin
  Result := (AOuter = '') or (APath = AOuter) or APath.StartsWith(AOuter + '/');
end;

end.
