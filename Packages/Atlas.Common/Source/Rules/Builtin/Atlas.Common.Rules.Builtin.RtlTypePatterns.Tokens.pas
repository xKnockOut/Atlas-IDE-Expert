unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens;

// Gemeinsame Tokenhilfen der Regeln für RTL-Muster (RtlTypePatterns und ihre Teilunits): Code-Token
// suchen, Klammern und Argumente zählen, einfache Bezeichner und Routinenrümpfe erkennen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes;

type
  TTokens = TArray<TPascalToken>;

/// <summary>Kommentar oder Compileranweisung?</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;

/// <summary>Erstes Code-Token ab AIndex (hinter dem Ende: Length(ATokens)).</summary>
function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;

/// <summary>Letztes Code-Token vor AIndex (davor: -1).</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;

/// <summary>Schließende Klammer zu der Klammer bei AOpen; -1 ohne Gegenstück.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;

/// <summary>Zahl der Argumente auf oberster Ebene zwischen AOpen und AClose.</summary>
function ArgumentCount(const ATokens: TTokens; AOpen, AClose: Integer): Integer;

/// <summary>Bereich vom Anfang von ATokens[AFirst] bis zum Ende von ATokens[ALast].</summary>
function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;

/// <summary>Bezeichner mit dem Namen AName (ohne Beachtung der Groß-/Kleinschreibung)?</summary>
function IsIdentifierNamed(const AToken: TPascalToken; const AName: string): Boolean;

/// <summary>Deklarierter Typ des Bezeichners ATokens[AIndex] an seiner Stelle; '' wenn unbekannt.</summary>
function DeclaredTypeAt(ATypes: TDeclaredTypes; const ATokens: TTokens; AIndex: Integer): string;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;

/// <summary>Ist AStatement die Zuweisung "X := ACall" direkt in einer Anweisungsliste?</summary>
function IsListedAssignment(AStatement, ACall: TSyntaxNode): Boolean;

/// <summary>Steht AName in der kommagetrennten Namensliste AList (Name einer Deklaration "A, B")?</summary>
function ListsName(const AList, AName: string): Boolean;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils;

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
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
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
  mIndex, mDepth: Integer;
begin
  if NextCode(ATokens, AOpen + 1) = AClose then
  begin
    Exit(0);
  end;
  Result := 1;
  mDepth := 0;
  for mIndex := AOpen + 1 to AClose - 1 do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and ATokens[mIndex].IsSymbol(',') then
    begin
      Inc(Result);
    end;
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function IsIdentifierNamed(const AToken: TPascalToken; const AName: string): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Identifier) and SameText(AToken.Text, AName);
end;

function DeclaredTypeAt(ATypes: TDeclaredTypes; const ATokens: TTokens; AIndex: Integer): string;
begin
  Result := ATypes.DeclaredType(ATokens[AIndex].Text, ATokens[AIndex].StartPos);
end;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  mPrev, mNext: Integer;
begin
  if (AIndex < 0) or (AIndex > High(ATokens)) or (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit(False);
  end;
  mPrev := PreviousCode(ATokens, AIndex);
  mNext := NextCode(ATokens, AIndex + 1);
  Result := not ((mPrev >= 0) and (ATokens[mPrev].IsSymbol('.') or ATokens[mPrev].IsSymbol('@'))) and
    not ((mNext <= High(ATokens)) and (ATokens[mNext].IsSymbol('.') or ATokens[mNext].IsSymbol('(') or
    ATokens[mNext].IsSymbol('[') or ATokens[mNext].IsSymbol('^')));
end;

function IsListedAssignment(AStatement, ACall: TSyntaxNode): Boolean;
begin
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and
    (AStatement.ChildCount = 2) and (AStatement[1] = ACall) and (AStatement.Parent <> nil);
  Result := Result and (AStatement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.RepeatStatement,
    TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection]);
end;

function ListsName(const AList, AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in SplitString(AList, ',') do
  begin
    Result := Result or SameText(Trim(mName), AName);
  end;
end;

/// <summary>Liegt APosition vor oder auf ALimit?</summary>
function NotAfter(const APosition, ALimit: TTextPosition): Boolean;
begin
  Result := (APosition.Line < ALimit.Line) or ((APosition.Line = ALimit.Line) and
    (APosition.Character <= ALimit.Character));
end;

/// <summary>Umschließt ANode die Stelle APosition (Anfang eingeschlossen, Ende ausgeschlossen)?</summary>
function Encloses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := NotAfter(ANode.StartPos, APosition) and not NotAfter(ANode.EndPos, APosition);
end;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  mRoot: TSyntaxNode;
  mPosition: TTextPosition;
begin
  mRoot := ATree.Root;
  if mRoot = nil then
  begin
    Exit(False);
  end;
  mPosition := APosition;
  // Iterativ (Bericht M1). Die Wurzel selbst zählt wie früher nicht.
  Result := mRoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Block) and (ANode <> mRoot) and Encloses(ANode, mPosition) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;
end.
