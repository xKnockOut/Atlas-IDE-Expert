unit Atlas.Common.Rules.Builtin.Flow.Shared;

// Gemeinsame Hilfen der Flussregeln aus Atlas.Common.Rules.Builtin.Flow (#269): Bereiche, Namen in Ausdrücken,
// Verwendungen, die der Kontrollfluss nicht sieht.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract;

const
  /// <summary>Einfache Typen, die Delphi nicht vorbelegt.</summary>
  SimpleTypes: array[0..23] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'Byte', 'Word', 'ShortInt', 'SmallInt', 'LongInt', 'LongWord', 'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'Char', 'AnsiChar', 'WideChar', 'Double', 'Single', 'Extended', 'Currency', 'Pointer');
  /// <summary>Verwaltete Typen, die Delphi vorbelegt.</summary>
  ManagedTypes: array[0..7] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString',
    'Variant', 'OleVariant', 'TArray');
  /// <summary>Anweisungen und ihre Teile; ein Knoten des Graphen wertet sie nicht selbst aus.</summary>
  FlowStatementKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.CaseItem,
    TSyntaxKind.CaseElse, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement, TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.ExceptBlock,
    TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];

function NodeRange(ANode: TSyntaxNode): TTextRange;
/// <summary>Bezeichner, an dem eine Kette wie Result.Feld oder Result[I] hängt.</summary>
function RootName(ANode: TSyntaxNode): string;
function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
/// <summary>ANode ist die Zuweisung "AName := …".</summary>
function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
/// <summary>Wird AName in ABlock so benutzt, dass der Kontrollfluss die Zuweisung nicht sieht?</summary>
function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
function ShortName(const AName: string): string;
/// <summary>Bereich des Routinennamens im Kopf; sonst der Kopf.</summary>
function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
/// <summary>Legt die Kinder von ANode rückwärts auf APending, damit das erste Kind zuerst drankommt.</summary>
procedure PushChildren(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);

/// <summary>Name einer Variablen oder eines Feldes (X oder Self.X); sonst ''.</summary>
function FreedPath(ANode: TSyntaxNode): string;
/// <summary>Gibt die Anweisung AStatement X frei? AToNil bei FreeAndNil.</summary>
function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
  begin
    ANode := ANode[0];
  end;
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
  begin
    Result := ANode.Name;
  end
  else
  begin
    Result := '';
  end;
end;

function IsName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and IsName(ANode[0], AName);
end;

/// <summary>ANode ist AName selbst oder ein Teil davon (AName.Feld, AName[I]).</summary>
function IsNameOrPart(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := IsName(ANode, AName) or ((ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess]) and
    SameText(RootName(ANode), AName));
end;

/// <summary>Auch X.Feld oder X[I] als Argument: Ein var- oder out-Parameter schreibt dann einen Teil von X
/// (Liste.Find(Name, Eintrag.Wert)).</summary>
function PassedAsArgument(ACall: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ACall.ChildCount - 1 do
  begin
    Result := Result or IsNameOrPart(ACall[Index], AName);
  end;
end;

/// <summary>AName ist ein Ausdruck von with … do.</summary>
function IsWithTarget(AWith: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to AWith.ChildCount - 2 do
  begin
    Result := Result or SameText(RootName(AWith[Index]), AName);
  end;
end;

/// <summary>Erster Teil von ANode hängt an AName (@X.Feld, X.Feld := …).</summary>
function FirstRootIs(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.ChildCount > 0) and SameText(RootName(ANode[0]), AName);
end;

function FoundIf(AFound: Boolean): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if AFound then
  begin
    Result := TSyntaxSearchStep.Found;
  end;
end;

/// <summary>Schritt der Suche in HasOpaqueUse für ANode.</summary>
function OpaqueStep(ANode: TSyntaxNode; const AName: string): TSyntaxSearchStep;
begin
  case ANode.Kind of
    // Lokale Routinen und anonyme Methoden laufen außerhalb dieses Flusses.
    TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod:
      Result := TSyntaxSearchStep.Skip;
    TSyntaxKind.Call:
      Result := FoundIf(PassedAsArgument(ANode, AName));
    TSyntaxKind.AddressOf:
      Result := FoundIf(FirstRootIs(ANode, AName));
    TSyntaxKind.AssignStatement:
      Result := FoundIf(FirstRootIs(ANode, AName) and (ANode[0].Kind <> TSyntaxKind.Identifier));
    TSyntaxKind.WithStatement:
      Result := FoundIf(IsWithTarget(ANode, AName));
  else
    Result := TSyntaxSearchStep.Descend;
  end;
end;

function HasOpaqueUse(ABlock: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  Result := ABlock.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := OpaqueStep(ANode, Name);
    end) <> nil;
end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      if AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function HeaderNameRange(const AContext: TRuleContext; ARoutine: TSyntaxNode): TTextRange;
var
  Header: TSyntaxNode;
  Token: TPascalToken;
  Index: Integer;
  Name: string;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Header := ARoutine;
  end;
  Name := ShortName(ARoutine.Name);
  for Index := AContext.Tree.FirstTokenFrom(Header.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    Token := AContext.Tree.Tokens[Index];
    if Token.Offset >= Header.EndOffset then
    begin
      Break;
    end;
    if (Token.Offset >= Header.StartOffset) and SameText(Token.Text, Name) then
    begin
      Exit(TTextRange.Create(Token.StartPos, Token.EndPos));
    end;
  end;
  Result := NodeRange(Header);
end;

procedure PushChildren(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
var
  Child: Integer;
begin
  for Child := ANode.ChildCount - 1 downto 0 do
  begin
    APending.Push(ANode[Child]);
  end;
end;

function FreedPath(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and IsName(ANode[0], 'Self') then
  begin
    Result := ANode.Name;
  end;
  if SameText(Result, 'Self') or SameText(Result, 'inherited') then
  begin
    Result := '';
  end;
end;

function FreedBy(AStatement: TSyntaxNode; out APath: string; out AToNil: Boolean): Boolean;
var
  Callee, Target: TSyntaxNode;
begin
  Result := False;
  APath := '';
  AToNil := False;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  Callee := AStatement[0];
  Target := nil;
  // X.Free; bzw. X.Free();
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
  begin
    Callee := Callee[0];
  end;
  if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and
    MatchText(Callee.Name, ['Free', 'Destroy', 'DisposeOf']) then
  begin
    Target := Callee[0];
  end
  else if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 2) and (Callee[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Callee[0].Name, ['FreeAndNil', 'Dispose']) then
  begin
    Target := Callee[1];
    AToNil := SameText(Callee[0].Name, 'FreeAndNil');
  end;
  APath := FreedPath(Target);
  Result := APath <> '';
end;

end.
