unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens;

// Gemeinsame Tokenhilfen der Regeln für RTL-Muster (RtlTypePatterns und ihre Teilunits): Code-Token
// suchen, Klammern und Argumente zählen, einfache Bezeichner und Routinenrümpfe erkennen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TTokens = TArray<TPascalToken>;

function IsTrivia(const AToken: TPascalToken): Boolean;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;

function Closing(const ATokens: TTokens; AOpen: Integer): Integer;

/// <summary>Zahl der Argumente auf oberster Ebene zwischen AOpen und AClose.</summary>
function ArgumentCount(const ATokens: TTokens; AOpen, AClose: Integer): Integer;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;

implementation

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Zahl der Argumente auf oberster Ebene zwischen AOpen und AClose.</summary>
function ArgumentCount(const ATokens: TTokens; AOpen, AClose: Integer): Integer;
var
  Index, Depth: Integer;
begin
  if NextCode(ATokens, AOpen + 1) = AClose then
  begin
    Exit(0);
  end;
  Result := 1;
  Depth := 0;
  for Index := AOpen + 1 to AClose - 1 do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and ATokens[Index].IsSymbol(',') then
    begin
      Inc(Result);
    end;
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  Prev, Next: Integer;
begin
  if (AIndex < 0) or (AIndex > High(ATokens)) or (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit(False);
  end;
  Prev := PreviousCode(ATokens, AIndex);
  Next := NextCode(ATokens, AIndex + 1);
  Result := not ((Prev >= 0) and (ATokens[Prev].IsSymbol('.') or ATokens[Prev].IsSymbol('@'))) and
    not ((Next <= High(ATokens)) and (ATokens[Next].IsSymbol('.') or ATokens[Next].IsSymbol('(') or
    ATokens[Next].IsSymbol('[') or ATokens[Next].IsSymbol('^')));
end;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  Root: TSyntaxNode;
  Position: TTextPosition;
begin
  Root := ATree.Root;
  if Root = nil then
  begin
    Exit(False);
  end;
  Position := APosition;
  // Iterativ (Bericht M1). Die Wurzel selbst zählt wie früher nicht.
  Result := Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Block) and (ANode <> Root) and
        ((ANode.StartPos.Line < Position.Line) or ((ANode.StartPos.Line = Position.Line) and
        (ANode.StartPos.Character <= Position.Character))) and
        ((ANode.EndPos.Line > Position.Line) or ((ANode.EndPos.Line = Position.Line) and
        (ANode.EndPos.Character > Position.Character))) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

end.
