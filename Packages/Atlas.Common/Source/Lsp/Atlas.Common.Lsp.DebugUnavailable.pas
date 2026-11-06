unit Atlas.Common.Lsp.DebugUnavailable;

// Warum der Debugger einen Wert nicht liefert (#840): Anfrage
// atlas/debugUnavailable mit textDocument, position (Halt, Zeile 0-basiert)
// und name (Bezeichner, dessen Auswertung scheiterte). Der Server nennt die
// Tatsachen, das Plugin wählt daraus die Ursache:
//   - switches: D (DEBUGINFO), L (LOCALSYMBOLS) und O (OPTIMIZATION) an der
//     Stelle mit Herkunft wie atlas/compilerSwitches (#558);
//   - routine: innerste benannte Routine am Halt mit Zeilen und ob sie inline
//     deklariert ist (am Kopf der Implementierung oder an der Deklaration in
//     der Klasse bzw. im interface);
//   - variable: lokal (lokale Variable, Parameter, Result, Inline- oder
//     Schleifenvariable), erste und letzte Verwendung im Rumpf und daraus die
//     Lebensdauer am Halt (before, within, after, unused). Eine Verwendung in
//     einer Schleife zählt für die ganze Schleife. Parameter leben ab dem
//     Routinenanfang. Das ist eine Näherung: Der Compiler kann Register früher
//     freigeben oder später belegen.
//   - fixes: Änderungen als WorkspaceEdit: {$OPTIMIZATION OFF} vor und
//     {$OPTIMIZATION ON} nach der äußeren Routine, {$O-} unter dem Kopf der
//     Unit; fehlt, wo nichts einzufügen ist.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Lsp.CompilerSwitches;

type
  {$SCOPEDENUMS ON}
  TVariableLifetime = (Unknown, Unused, Before, Within, After);
  {$SCOPEDENUMS OFF}

  TUnavailableFacts = record
    HasRoutine: Boolean;
    RoutineName: string;
    RoutineInline: Boolean;
    RoutineStartLine: Integer;
    RoutineEndLine: Integer;
    /// <summary>Lokale Variable, Parameter, Result, Inline- oder Schleifenvariable der Routine.</summary>
    Local: Boolean;
    IsParameter: Boolean;
    /// <summary>Erste und letzte Verwendung (Zeilen, 0-basiert, Schleifen ganz); -1 ohne.</summary>
    FirstUse: Integer;
    LastUse: Integer;
    Lifetime: TVariableLifetime;
    /// <summary>Einfügungen für {$OPTIMIZATION OFF}/{$OPTIMIZATION ON} um die äußere Routine; leer ohne.</summary>
    RoutineFix: TArray<TTextEdit>;
    /// <summary>Einfügung {$O-} unter dem Kopf der Unit.</summary>
    UnitFix: TArray<TTextEdit>;
  end;

  TLspDebugUnavailable = class
  public const
    Method = 'atlas/debugUnavailable';
    LifetimeNames: array[TVariableLifetime] of string = ('unknown', 'unused', 'before', 'within', 'after');
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FContextFor: TCompilerSwitchContextFunc;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
      const AContextFor: TCompilerSwitchContextFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Tatsachen zu AName beim Halt in Zeile AStoppedLine (0-basiert). AResolver darf nil sein; dann
    /// gilt ein Name als lokal, wenn er in der Routine deklariert ist.</summary>
    class function Facts(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText, AName: string;
      AStoppedLine: Integer): TUnavailableFacts; static;
    /// <summary>Antwort wie im Kopf beschrieben; gehört dem Aufrufer.</summary>
    class function ToJson(const AFacts: TUnavailableFacts; const AState: TCompilerSwitchState;
      const AFileName: string): TJSONObject; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDebugUnavailableText = (FieldsTextDocumentUriPositionAnd);

const
  cTexts: array[TDebugUnavailableText] of TAtlasText = (
    (De: 'Felder "textDocument.uri", "position" und "name" fehlen in ';
     En: 'Fields "textDocument.uri", "position" and "name" missing in '));

{$SCOPEDENUMS OFF}

function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Innerste (AOuter: äußerste) benannte Routine, die AOffset enthält; nil außerhalb.</summary>
function RoutineAt(ARoot: TSyntaxNode; AOffset: Integer; AOuter: Boolean): TSyntaxNode;
var
  Node, Child: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  Result := nil;
  Node := ARoot;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      Child := Node[Index];
      if (Child.StartOffset <= AOffset) and (AOffset < Child.EndOffset) then
      begin
        Node := Child;
        if (Node.Kind = TSyntaxKind.RoutineDecl) and not (AOuter and (Result <> nil)) then
        begin
          Result := Node;
        end;
        Descended := True;
        Break;
      end;
    end;
  until not Descended;
end;

function Significant(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

/// <summary>Offset des ersten bedeutsamen Tokens in ALine bzw. danach; -1 ohne.</summary>
function LineOffset(const ATokens: TArray<TPascalToken>; ALine: Integer): Integer;
var
  Token: TPascalToken;
begin
  for Token in ATokens do
  begin
    if (Token.StartPos.Line >= ALine) and Significant(Token) then
    begin
      Exit(Token.Offset);
    end;
  end;
  Result := -1;
end;

function HasInlineDirective(AHeader: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if AHeader = nil then
  begin
    Exit;
  end;
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[Index].Kind = TSyntaxKind.Directive) and SameText(AHeader[Index].Name, 'inline') then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Name des umgebenden Typs eines Kopfs in einer Klassen- bzw. Record-Deklaration; '' sonst.</summary>
function OwnerTypeName(ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
begin
  Result := '';
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.TypeDecl then
    begin
      Exit(Node.Name);
    end;
    if Node.Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.RoutineDecl] then
    begin
      Exit;
    end;
    Node := Node.Parent;
  end;
end;

function InInterface(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Result := False;
  Node := ANode.Parent;
  while Node <> nil do
  begin
    if Node.Kind = TSyntaxKind.InterfaceSection then
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
end;

/// <summary>Ist ANode ein Kopf mit inline, der zu ARoutine (Kurzname AShortName, Typ ATypeName) gehört?</summary>
function DeclaresInline(ANode, ARoutine: TSyntaxNode; const AShortName, ATypeName: string): Boolean;
begin
  Result := False;
  if (ANode.Kind <> TSyntaxKind.RoutineHeader) or (ANode.Parent = nil) or (ANode.Parent = ARoutine) or
    not SameText(LastPart(ANode.Name), AShortName) then
  begin
    Exit;
  end;
  if ATypeName <> '' then
  begin
    Result := SameText(OwnerTypeName(ANode), ATypeName) and HasInlineDirective(ANode);
  end
  else
  begin
    Result := InInterface(ANode) and HasInlineDirective(ANode);
  end;
end;

/// <summary>inline am Kopf der Routine oder an ihrer Deklaration (Klasse bzw. interface).</summary>
function RoutineIsInline(ARoot, ARoutine: TSyntaxNode): Boolean;
var
  mShortName, mTypeName: string;
  mFound: Boolean;
begin
  Result := HasInlineDirective(ARoutine.FindChild(TSyntaxKind.RoutineHeader));
  if Result then
  begin
    Exit;
  end;
  mShortName := LastPart(ARoutine.Name);
  mTypeName := '';
  if Pos('.', ARoutine.Name) > 0 then
  begin
    mTypeName := LastPart(Copy(ARoutine.Name, 1, LastDelimiter('.', ARoutine.Name) - 1));
  end;
  mFound := False;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not mFound;
      if not mFound and DeclaresInline(ANode, ARoutine, mShortName, mTypeName) then
      begin
        mFound := True;
      end;
    end);
  Result := mFound;
end;

/// <summary>Zeile hinter dem Kopf "unit X;" bzw. "program X;"; 0 ohne Kopf.</summary>
function LineAfterHeader(const ATokens: TArray<TPascalToken>): Integer;
var
  Index, Last: Integer;
begin
  Result := 0;
  Index := 0;
  while (Index <= High(ATokens)) and not Significant(ATokens[Index]) do
  begin
    Inc(Index);
  end;
  if (Index > High(ATokens)) or not (SameText(ATokens[Index].Text, 'unit') or
    SameText(ATokens[Index].Text, 'program') or SameText(ATokens[Index].Text, 'library') or
    SameText(ATokens[Index].Text, 'package')) then
  begin
    Exit;
  end;
  Last := Index;
  while (Last <= High(ATokens)) and not ATokens[Last].IsSymbol(';') do
  begin
    Inc(Last);
  end;
  if Last <= High(ATokens) then
  begin
    Result := ATokens[Last].EndPos.Line + 1;
  end;
end;

/// <summary>Lebensdauer am Halt AStoppedLine aus erster und letzter Verwendung.</summary>
function LifetimeAt(const AFacts: TUnavailableFacts; AStoppedLine: Integer): TVariableLifetime;
begin
  if AFacts.FirstUse < 0 then
  begin
    Result := TVariableLifetime.Unused;
  end
  else if AStoppedLine < AFacts.FirstUse then
  begin
    Result := TVariableLifetime.Before;
  end
  else if AStoppedLine > AFacts.LastUse then
  begin
    Result := TVariableLifetime.After;
  end
  else
  begin
    Result := TVariableLifetime.Within;
  end;
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

type
  /// <summary>Sammelt die Tatsachen zu einem Namen in der Routine am Halt (TLspDebugUnavailable.Facts).</summary>
  TFactsCollector = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FTokens: TArray<TPascalToken>;
    FFileName: string;
    FName: string;
    FRoutine: TSyntaxNode;
    FBody: TSyntaxNode;
    FLoops: TList<TSyntaxNode>;
    FResolved: Boolean;
    FDeclared: Boolean;
    FFacts: TUnavailableFacts;
    procedure ReadRoutine(AOuter: TSyntaxNode; const ALineEnd: string);
    procedure ScanDeclarations;
    procedure CollectLoops;
    function IsUse(AIndex: Integer): Boolean;
    procedure ResolveOnce(const AToken: TPascalToken);
    procedure AddUse(const AToken: TPascalToken);
    procedure ScanBody;
  public
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AName: string);
    destructor Destroy; override;
    function Run(const AText: string; AStoppedLine: Integer): TUnavailableFacts;
  end;

constructor TFactsCollector.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AName: string);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FTokens := ATree.Tokens;
  FFileName := AFileName;
  FName := AName;
  FLoops := TList<TSyntaxNode>.Create;
end;

destructor TFactsCollector.Destroy;
begin
  FLoops.Free;
  inherited;
end;

procedure TFactsCollector.ReadRoutine(AOuter: TSyntaxNode; const ALineEnd: string);
begin
  FFacts.HasRoutine := True;
  FFacts.RoutineName := FRoutine.Name;
  FFacts.RoutineStartLine := FRoutine.StartPos.Line;
  FFacts.RoutineEndLine := FRoutine.EndPos.Line;
  FFacts.RoutineInline := RoutineIsInline(FTree.Root, FRoutine);
  FFacts.RoutineFix := TArray<TTextEdit>.Create(
    TTextEdit.Create(TTextRange.Create(AOuter.StartPos.Line, 0, AOuter.StartPos.Line, 0),
      '{$OPTIMIZATION OFF}' + ALineEnd),
    TTextEdit.Create(TTextRange.Create(AOuter.EndPos.Line + 1, 0, AOuter.EndPos.Line + 1, 0),
      '{$OPTIMIZATION ON}' + ALineEnd));
end;

procedure TFactsCollector.ScanDeclarations;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
  mToken: TPascalToken;
begin
  // Parameter: Name in der Parameterliste des Kopfs; deklariert: Name vor dem Rumpf (Parameter, var-Abschnitt).
  mParams := nil;
  if FRoutine.FindChild(TSyntaxKind.RoutineHeader) <> nil then
  begin
    mParams := FRoutine.FindChild(TSyntaxKind.RoutineHeader).FindChild(TSyntaxKind.Parameters);
  end;
  FDeclared := SameText(FName, 'Result');
  for mIndex := TSyntaxTree.FirstTokenOf(FTokens, FRoutine.StartOffset) to High(FTokens) do
  begin
    mToken := FTokens[mIndex];
    if mToken.Offset >= FBody.StartOffset then
    begin
      Break;
    end;
    if (mToken.Offset < FRoutine.StartOffset) or (mToken.Kind <> TPascalTokenKind.Identifier) or
      not SameText(mToken.Text, FName) then
    begin
      Continue;
    end;
    if (mParams <> nil) and (mParams.StartOffset <= mToken.Offset) and (mToken.Offset < mParams.EndOffset) then
    begin
      FFacts.IsParameter := True;
    end;
    if not SameText(LastPart(FRoutine.Name), FName) then
    begin
      FDeclared := True;
    end;
  end;
end;

procedure TFactsCollector.CollectLoops;
var
  mLoops: TList<TSyntaxNode>;
begin
  mLoops := FLoops;
  FBody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if IsLoop(ANode) then
      begin
        mLoops.Add(ANode);
      end;
      // Anonyme Methoden haben eigene Lebensdauern.
      Result := ANode.Kind <> TSyntaxKind.AnonymousMethod;
    end);
end;

function TFactsCollector.IsUse(AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  Result := (FTokens[AIndex].Offset >= FBody.StartOffset) and (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    SameText(FTokens[AIndex].Text, FName) and not FTree.IsControlCharPart(AIndex);
  if not Result then
  begin
    Exit;
  end;
  mBefore := AIndex - 1;
  while (mBefore >= 0) and not Significant(FTokens[mBefore]) do
  begin
    Dec(mBefore);
  end;
  // Mitglied eines anderen Ausdrucks (X.Name) ist ein anderer Name.
  Result := (mBefore < 0) or not FTokens[mBefore].IsSymbol('.');
  // Inline-Variable (var Name) bzw. Schleifenvariable (for var Name) ist lokal.
  if Result and (mBefore >= 0) and SameText(FTokens[mBefore].Text, 'var') then
  begin
    FDeclared := True;
  end;
end;

procedure TFactsCollector.ResolveOnce(const AToken: TPascalToken);
var
  mSymbol: TResolvedSymbol;
begin
  if FResolved or (FResolver = nil) then
  begin
    Exit;
  end;
  mSymbol := FResolver.Resolve(FTree, FFileName, AToken.StartPos);
  FFacts.Local := (mSymbol.Kind = TResolvedKind.Local) and (mSymbol.SymbolKind = TIndexSymbolKind.Variable);
  FResolved := True;
end;

procedure TFactsCollector.AddUse(const AToken: TPascalToken);
var
  mFirstLine, mLastLine: Integer;
  mLoop: TSyntaxNode;
begin
  // Eine Verwendung in einer Schleife zählt für die ganze Schleife.
  mFirstLine := AToken.StartPos.Line;
  mLastLine := AToken.StartPos.Line;
  for mLoop in FLoops do
  begin
    if (mLoop.StartOffset <= AToken.Offset) and (AToken.Offset < mLoop.EndOffset) then
    begin
      mFirstLine := Min(mFirstLine, mLoop.StartPos.Line);
      mLastLine := Max(mLastLine, mLoop.EndPos.Line);
    end;
  end;
  if (FFacts.FirstUse < 0) or (mFirstLine < FFacts.FirstUse) then
  begin
    FFacts.FirstUse := mFirstLine;
  end;
  if mLastLine > FFacts.LastUse then
  begin
    FFacts.LastUse := mLastLine;
  end;
end;

procedure TFactsCollector.ScanBody;
var
  mIndex: Integer;
begin
  for mIndex := TSyntaxTree.FirstTokenOf(FTokens, FBody.StartOffset) to High(FTokens) do
  begin
    if FTokens[mIndex].Offset >= FBody.EndOffset then
    begin
      Break;
    end;
    if IsUse(mIndex) then
    begin
      ResolveOnce(FTokens[mIndex]);
      AddUse(FTokens[mIndex]);
    end;
  end;
end;

function TFactsCollector.Run(const AText: string; AStoppedLine: Integer): TUnavailableFacts;
var
  mOffset: Integer;
  mLineEnd: string;
begin
  FFacts := Default(TUnavailableFacts);
  FFacts.FirstUse := -1;
  FFacts.LastUse := -1;
  mLineEnd := TTextLines.LineBreakOf(AText);
  FFacts.UnitFix := TArray<TTextEdit>.Create(TTextEdit.Create(TTextRange.Create(LineAfterHeader(FTokens), 0,
    LineAfterHeader(FTokens), 0), '{$O-}' + mLineEnd));
  Result := FFacts;
  mOffset := LineOffset(FTokens, AStoppedLine);
  FRoutine := nil;
  if mOffset >= 0 then
  begin
    FRoutine := RoutineAt(FTree.Root, mOffset, False);
  end;
  if FRoutine = nil then
  begin
    Exit;
  end;
  ReadRoutine(RoutineAt(FTree.Root, mOffset, True), mLineEnd);
  Result := FFacts;
  FBody := FRoutine.FindChild(TSyntaxKind.Block);
  if FBody = nil then
  begin
    Exit;
  end;
  ScanDeclarations;
  CollectLoops;
  if FResolver <> nil then
  begin
    FResolver.PinTree(FTree, FFileName);
  end;
  try
    ScanBody;
  finally
    if FResolver <> nil then
    begin
      FResolver.UnpinTree;
    end;
  end;
  // Deklaration in der Routine zählt auch, wenn der Index den Namen anders auflöst.
  FFacts.Local := FFacts.Local or FFacts.IsParameter or FDeclared;
  if FFacts.IsParameter and (FFacts.FirstUse >= 0) then
  begin
    FFacts.FirstUse := FFacts.RoutineStartLine;
  end;
  FFacts.Lifetime := LifetimeAt(FFacts, AStoppedLine);
  Result := FFacts;
end;

{ TLspDebugUnavailable }

constructor TLspDebugUnavailable.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc; const AContextFor: TCompilerSwitchContextFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FContextFor := AContextFor;
end;

procedure TLspDebugUnavailable.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspDebugUnavailable.Facts(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText, AName: string; AStoppedLine: Integer): TUnavailableFacts;
var
  mCollector: TFactsCollector;
begin
  mCollector := TFactsCollector.Create(AResolver, ATree, AFileName, AName);
  try
    Result := mCollector.Run(AText, AStoppedLine);
  finally
    mCollector.Free;
  end;
end;

class function TLspDebugUnavailable.ToJson(const AFacts: TUnavailableFacts; const AState: TCompilerSwitchState;
  const AFileName: string): TJSONObject;
var
  Switches: TJSONArray;
  Entry: TSwitchEntry;
  Routine, Variable, Fixes: TJSONObject;
begin
  Result := TJSONObject.Create;
  Switches := TJSONArray.Create;
  for Entry in AState.Switches do
  begin
    if (Entry.Name = 'D') or (Entry.Name = 'L') or (Entry.Name = 'O') then
    begin
      Switches.AddElement(TLspCompilerSwitches.EntryToJson(Entry));
    end;
  end;
  Result.AddPair('switches', Switches);
  if AFacts.HasRoutine then
  begin
    Routine := TJSONObject.Create;
    Routine.AddPair('name', AFacts.RoutineName);
    Routine.AddPair('inline', TJSONBool.Create(AFacts.RoutineInline));
    Routine.AddPair('startLine', TJSONNumber.Create(AFacts.RoutineStartLine));
    Routine.AddPair('endLine', TJSONNumber.Create(AFacts.RoutineEndLine));
    Result.AddPair('routine', Routine);
  end;
  Variable := TJSONObject.Create;
  Variable.AddPair('local', TJSONBool.Create(AFacts.Local));
  Variable.AddPair('parameter', TJSONBool.Create(AFacts.IsParameter));
  Variable.AddPair('firstUse', TJSONNumber.Create(AFacts.FirstUse));
  Variable.AddPair('lastUse', TJSONNumber.Create(AFacts.LastUse));
  Variable.AddPair('lifetime', LifetimeNames[AFacts.Lifetime]);
  Result.AddPair('variable', Variable);
  Fixes := TJSONObject.Create;
  if Length(AFacts.RoutineFix) > 0 then
  begin
    Fixes.AddPair('routineOptimization', TLspApplyEdit.TextEdits(AFileName, AFacts.RoutineFix));
  end;
  if Length(AFacts.UnitFix) > 0 then
  begin
    Fixes.AddPair('unitOptimization', TLspApplyEdit.TextEdits(AFileName, AFacts.UnitFix));
  end;
  Result.AddPair('fixes', Fixes);
end;

function TLspDebugUnavailable.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri, Name, FileName: string;
  PositionValue: TJSONValue;
  Position: TTextPosition;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Context: TCompilerSwitchContext;
  Facts: TUnavailableFacts;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue) and
    TJSONObject(AParams).TryGetValue<string>('name', Name)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      cTexts[TDebugUnavailableText.FieldsTextDocumentUriPositionAnd].Text + Method);
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  ACancellation.ThrowIfCancellationRequested;
  Position := TLspPositions.ReadPosition(PositionValue);
  FileName := TDocumentUris.ToPath(Uri);
  Context := Default(TCompilerSwitchContext);
  if Assigned(FContextFor) then
  begin
    Context := FContextFor(Uri);
  end;
  Resolver := nil;
  if FIndex <> nil then
  begin
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  end;
  try
    Facts := TLspDebugUnavailable.Facts(Resolver, Shared.Tree, FileName, Document.Text, Name, Position.Line);
  finally
    Resolver.Free;
  end;
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(Facts, TLspCompilerSwitches.StateAt(Document.Text, Position, Context), FileName);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DebugUnavailable', cTexts);

end.
