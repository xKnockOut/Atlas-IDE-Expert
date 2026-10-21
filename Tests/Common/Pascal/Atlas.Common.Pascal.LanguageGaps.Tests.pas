unit Atlas.Common.Pascal.LanguageGaps.Tests;

// Tests für kleinere Sprachlücken in Parser, Index und Namensauflösung (#849).
// Je Punkt des Issues ein Test; die Quellen stammen aus den nachgestellten
// Fällen in planung/parser-luecken-faelle (05, 07, 08, 09, 12) bzw. sind
// Fixtures zu den Korpusfunden (Punkte 10 bis 15).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLanguageGapsTests = class
  public
    /// <summary>Punkt 1: {$SCOPEDENUMS ON} steht im Index; unqualifiziert ist der Wert unbekannt.</summary>
    [Test]
    procedure ScopedEnumValuesNeedTypePrefix;
    /// <summary>Punkt 1: Die Prüfung meldet den unqualifizierten Wert und nennt TState.Error.</summary>
    [Test]
    procedure UnresolvedScopedValueSuggestsPrefix;
    /// <summary>Punkt 2 (Fall 05): Kommas nach ":" gehören zu den Einschränkungen.</summary>
    [Test]
    procedure GenericConstraintsKeepParameters;
    /// <summary>Punkt 3 (Fall 09): Mitglieder aus {$I members.inc} gehören zur Klasse.</summary>
    [Test]
    procedure IncludeInClassBodyAddsMembers;
    /// <summary>Punkt 4 (Fall 07): benannte Argumente der OLE-Automation.</summary>
    [Test]
    procedure NamedArgumentsParse;
    /// <summary>Punkt 5 (Fall 12): Feld namens Operator.</summary>
    [Test]
    procedure OperatorFieldIsField;
    /// <summary>Punkt 6 (Fall 08): Attribut nach const-Abschnitt gehört zur Methode.</summary>
    [Test]
    procedure AttributeAfterConstSectionEndsSection;
    /// <summary>Punkt 7: NameOf ist ein Intrinsic.</summary>
    [Test]
    procedure NameOfIsIntrinsic;
    /// <summary>Punkt 9 (Fall 08): Methodenzuordnung ist kein Mitglied, Gehe zu auf MyBar trifft die Methode.
    /// </summary>
    [Test]
    procedure MethodResolutionIsNoMember;
    /// <summary>Punkt 10: Aufrufkonvention ohne Semikolon, cdecl varargs, assembler asm.</summary>
    [Test]
    procedure DirectivesWithoutSemicolon;
    /// <summary>Punkt 11: letztes Feld ohne Semikolon vor end.</summary>
    [Test]
    procedure LastFieldWithoutSemicolon;
    /// <summary>Punkt 12: lokale Routinen in anonymen Methoden.</summary>
    [Test]
    procedure LocalRoutinesInAnonymousMethod;
    /// <summary>Punkt 13: 312 else if hintereinander, die Routine danach bleibt im Baum.</summary>
    [Test]
    procedure LongElseIfChainStaysFlat;
    /// <summary>Punkt 14: Teilbereich als Elementtyp einer typisierten Konstanten.</summary>
    [Test]
    procedure SubrangeBoundStopsBeforeValue;
    /// <summary>Punkt 15: {$I datei.inc} als Wert; der Index setzt den Inhalt in die Signatur.</summary>
    [Test]
    procedure IncludeAsValue;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Lsp.DocumentSymbols;

const
  MainFile = 'C:\P\U.pas';
  UnitSystem =
    'unit System;'#10'interface'#10'type'#10'  Integer = -2147483648..2147483647;'#10 +
    '  TObject = class'#10'  end;'#10'implementation'#10'end.';
  ScopedUnit =
    'unit U;'#10'interface'#10'type'#10'  {$SCOPEDENUMS ON}'#10'  TState = (None, Busy, Error);'#10 +
    '  {$SCOPEDENUMS OFF}'#10'  TColor = (Red, Green);'#10'implementation'#10'procedure P(S: TState; C: TColor);'#10 +
    'begin'#10'  if S = Error then'#10'    S := TState.Busy;'#10'  C := Red;'#10'end;'#10'end.';
  CaseFive =
    'unit U5;'#10'interface'#10'type'#10'  TFoo<T: IFoo, IBar; V: class, constructor> = class'#10'  end;'#10 +
    '  TBaz<T: interface; U: unmanaged> = class'#10'  end;'#10'var'#10'  F: TFoo<TObject, TObject>;'#10 +
    'implementation'#10'end.';
  CaseSeven =
    'unit U7;'#10'interface'#10'implementation'#10'procedure X(W: OleVariant);'#10'begin'#10 +
    '  W.Documents.Open(FileName := ''a.docx'', ReadOnly := True);'#10'  D := dict(a := 1, b := 2);'#10 +
    'end;'#10'end.';
  CaseEight =
    'unit U8;'#10'interface'#10'type'#10'  IFoo = interface'#10'    procedure Bar;'#10'  end;'#10 +
    '  TFoo = class(TInterfacedObject, IFoo)'#10'    procedure IFoo.Bar = MyBar;'#10'    procedure MyBar;'#10 +
    '  end;'#10'  [Attr]'#10'  TAttr = class'#10'  strict private'#10'    const C = 1;'#10 +
    '    [Test] procedure T1;'#10'  end;'#10'implementation'#10'procedure TFoo.MyBar;'#10'begin'#10'end;'#10 +
    'procedure TAttr.T1;'#10'begin'#10'  Z := NameOf(T1);'#10'end;'#10'end.';
  CaseNine =
    'unit U9;'#10'interface'#10'type'#10'  TFoo = class'#10'  public'#10'    {$I members.inc}'#10 +
    '    procedure After;'#10'  end;'#10'implementation'#10'end.';
  MembersInc = 'procedure A;'#10'procedure B;'#10;
  CaseTwelve =
    'unit U12;'#10'interface'#10'type'#10'  TFilter = record'#10'    Field, Value: string;'#10 +
    '    Operator: string;'#10'    Negate: Boolean;'#10'  end;'#10'implementation'#10'end.';
  Directives =
    'unit P10;'#10'interface'#10'function F(A: Integer): Integer stdcall;'#10 +
    'function G(A: Integer): Integer cdecl; external ''x.dll'';'#10'type'#10 +
    '  TCb = function(A: PAnsiChar): Integer cdecl varargs;'#10'  TCb2 = procedure(A: Integer) cdecl;'#10 +
    'implementation'#10'function F(A: Integer): Integer stdcall;'#10'begin'#10'  Result := A;'#10'end;'#10 +
    'procedure X; assembler'#10'asm'#10'  mov eax, 1'#10'end;'#10'procedure Y;'#10'begin'#10'end;'#10'end.';
  LastField =
    'unit P11;'#10'interface'#10'type'#10'  TFColor = record B, G, R: Byte end;'#10'  TV = record'#10 +
    '    case Integer of'#10'      0: (A: Integer);'#10'      1: (C: Byte)'#10'  end;'#10'implementation'#10'end.';
  AnonymousLocal =
    'unit P12;'#10'interface'#10'implementation'#10'procedure X;'#10'var'#10'  P: TProc;'#10'begin'#10 +
    '  P := procedure'#10'    procedure Inner;'#10'    begin'#10'    end;'#10'    function Calc: Integer;'#10 +
    '    begin'#10'      Result := 1;'#10'    end;'#10'  var'#10'    I: Integer;'#10'  begin'#10'    Inner;'#10 +
    '    I := Calc;'#10'  end;'#10'end;'#10'procedure Z;'#10'begin'#10'end;'#10'end.';
  SubrangeConst =
    'unit P14;'#10'interface'#10'const'#10'  D2D: array [0..9] of 1..3 = (1, 2, 3, 1, 2, 3, 1, 2, 3, 1);'#10 +
    'var'#10'  X: 1..3 = 2;'#10'implementation'#10'end.';
  IncludeValue =
    'unit P15;'#10'interface'#10'const'#10'  SYNOPSE_FRAMEWORK_VERSION = {$I mormot.commit.inc};'#10 +
    'implementation'#10'end.';

function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := Find(ANode[Index], AKind, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = AKind then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + ANode[Index].Name;
    end;
end;

function Diagnostics(const AText: string): string;
var
  Tree: TSyntaxTree;
  Diagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Diagnostic in Tree.Diagnostics do
      Result := Result + Format('%d:%d %s; ', [Diagnostic.StartPos.Line, Diagnostic.StartPos.Character,
        Diagnostic.Message]);
  finally
    Tree.Free;
  end;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  Index := Pos(AMarker, AText);
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function SymbolOf(const AUnit: TUnitIndex; const AContainer, AName: string): TIndexSymbol;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) then
      Exit(Symbol);
  raise Exception.CreateFmt('%s.%s fehlt im Index', [AContainer, AName]);
end;

function HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, AContainer) and SameText(Symbol.Name, AName) then
      Exit(True);
  Result := False;
end;

function IncludeFiles: TIncludeResolver;
begin
  Result :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      AFileName := 'C:\P\' + AName;
      if SameText(AName, 'members.inc') then
        AText := MembersInc
      else if SameText(AName, 'mormot.commit.inc') then
        AText := '''2.3.11221'''#10
      else
        Exit(False);
      Result := True;
    end;
end;

{ TLanguageGapsTests }

procedure TLanguageGapsTests.ScopedEnumValuesNeedTypePrefix;
var
  U: TUnitIndex;
  Loaded: TArray<TUnitIndex>;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Found: TResolvedSymbol;
begin
  U := TIndexExtractor.ExtractText(ScopedUnit, MainFile, nil);
  Assert.IsTrue(SymbolOf(U, '', 'TState').ScopedEnum);
  Assert.IsTrue(SymbolOf(U, 'TState', 'Error').ScopedEnum);
  Assert.IsFalse(SymbolOf(U, '', 'TColor').ScopedEnum);
  Assert.IsFalse(SymbolOf(U, 'TColor', 'Red').ScopedEnum);
  // Der Schalter übersteht den Cache.
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.IsTrue(SymbolOf(Loaded[0], 'TState', 'Error').ScopedEnum);
  Assert.IsFalse(SymbolOf(Loaded[0], 'TColor', 'Red').ScopedEnum);
  Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(ScopedUnit);
  try
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(ScopedUnit, 'Error then'));
    Assert.IsFalse(Found.Found, 'unqualifiziert');
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(ScopedUnit, 'Busy;'));
    Assert.IsTrue(Found.Found, 'TState.Busy');
    Assert.AreEqual('TState', Found.Container);
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(ScopedUnit, 'Red;'));
    Assert.IsTrue(Found.Found, 'Red ohne SCOPEDENUMS');
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
end;

procedure TLanguageGapsTests.UnresolvedScopedValueSuggestsPrefix;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  Names: TArray<TUnresolvedName>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitSystem, 'C:\Lib\System.pas', nil));
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(ScopedUnit);
  try
    Names := TUnresolvedNames.Find(Resolver, Tree, MainFile);
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
  Assert.AreEqual(1, Integer(Length(Names)));
  Assert.AreEqual('Error', Names[0].Name);
  Assert.AreEqual('TState.Error', Names[0].Suggestion);
end;

procedure TLanguageGapsTests.GenericConstraintsKeepParameters;
var
  Tree: TSyntaxTree;
  U: TUnitIndex;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Found: TResolvedSymbol;
begin
  Assert.AreEqual('', Diagnostics(CaseFive));
  Tree := TPascalParser.Parse(CaseFive);
  try
    Assert.AreEqual('T,V', ChildNames(Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TFoo'),
      TSyntaxKind.GenericParams, ''), TSyntaxKind.Identifier));
    Assert.AreEqual('T,U', ChildNames(Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TBaz'),
      TSyntaxKind.GenericParams, ''), TSyntaxKind.Identifier));
  finally
    Tree.Free;
  end;
  U := TIndexExtractor.ExtractText(CaseFive, MainFile, nil);
  Assert.AreEqual('T,V', SymbolOf(U, '', 'TFoo').TypeParams);
  // Gehe zu auf TFoo<TObject, TObject>: Stelligkeit 2 passt.
  Index := TSymbolIndex.Create;
  Resolver := TNameResolver.Create(Index);
  Tree := TPascalParser.Parse(CaseFive);
  try
    Found := Resolver.Resolve(Tree, MainFile, PositionOf(CaseFive, 'TFoo<TObject'));
    Assert.IsTrue(Found.Found);
    Assert.AreEqual('TFoo', Found.Name);
  finally
    Tree.Free;
    Resolver.Free;
  end;
  Index := nil;
end;

procedure TLanguageGapsTests.IncludeInClassBodyAddsMembers;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText(CaseNine, MainFile, nil, IncludeFiles);
  Symbol := SymbolOf(U, 'TFoo', 'A');
  Assert.IsTrue(Symbol.Kind = TIndexSymbolKind.Method);
  Assert.AreEqual('C:\P\members.inc', Symbol.FileName);
  Assert.AreEqual(0, Symbol.SelectionRange.StartPos.Line);
  Assert.IsTrue(Symbol.Visibility = TIndexVisibility.Public);
  Symbol := SymbolOf(U, 'TFoo', 'B');
  Assert.AreEqual(1, Symbol.SelectionRange.StartPos.Line);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'After'));
  // Keine freien Routinen und kein Hilfstyp.
  Assert.IsFalse(HasSymbol(U, '', 'A'));
  Assert.IsFalse(HasSymbol(U, '', 'B'));
  for Symbol in U.Symbols do
    Assert.IsFalse(Symbol.Name.StartsWith('TAtlasIncludeHost'), Symbol.Name);
end;

procedure TLanguageGapsTests.NamedArgumentsParse;
var
  Tree: TSyntaxTree;
  Call: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(CaseSeven));
  Tree := TPascalParser.Parse(CaseSeven);
  try
    Call := Find(Tree.Root, TSyntaxKind.Call, 'Open');
    Assert.IsNotNull(Call);
    // Ziel und zwei Werte; die Namen der Argumente stehen nicht als Bezeichner im Baum.
    Assert.AreEqual(3, Call.ChildCount);
    Assert.IsTrue(Call[1].Kind = TSyntaxKind.Literal);
    Assert.IsNull(Find(Tree.Root, TSyntaxKind.Identifier, 'FileName'));
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.OperatorFieldIsField;
var
  Tree: TSyntaxTree;
  Rec: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(CaseTwelve));
  Tree := TPascalParser.Parse(CaseTwelve);
  try
    Rec := Find(Tree.Root, TSyntaxKind.RecordType, '');
    Assert.AreEqual('Field,Value,Operator,Negate', ChildNames(Rec, TSyntaxKind.Field));
    Assert.AreEqual('', ChildNames(Rec, TSyntaxKind.RoutineHeader));
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.AttributeAfterConstSectionEndsSection;
var
  Tree: TSyntaxTree;
  Body, Section: TSyntaxNode;
  Index: Integer;
begin
  Tree := TPascalParser.Parse(CaseEight);
  try
    Body := Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TAttr'), TSyntaxKind.ClassType, '');
    Section := Find(Body, TSyntaxKind.ConstSection, '');
    Assert.IsNotNull(Section);
    Assert.AreEqual('', ChildNames(Section, TSyntaxKind.Attribute));
    // Das Attribut steht im Rumpf direkt vor dem Methodenkopf.
    Index := Body.ChildCount - 1;
    Assert.IsTrue(Body[Index].Kind = TSyntaxKind.RoutineHeader);
    Assert.AreEqual('T1', Body[Index].Name);
    Assert.IsTrue(Body[Index - 1].Kind = TSyntaxKind.Attribute);
    Assert.AreEqual('Test', Body[Index - 1].Name);
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.NameOfIsIntrinsic;
begin
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('NameOf'));
  Assert.IsTrue(TUnresolvedNames.IsIntrinsic('nameof'));
end;

procedure TLanguageGapsTests.MethodResolutionIsNoMember;
var
  U: TUnitIndex;
  Tree: TSyntaxTree;
  Outline: TJSONArray;
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Found: TResolvedSymbol;
  Text: string;
begin
  Assert.AreEqual('', Diagnostics(CaseEight));
  U := TIndexExtractor.ExtractText(CaseEight, MainFile, nil);
  Assert.IsFalse(HasSymbol(U, 'TFoo', 'IFoo.Bar'));
  Assert.IsFalse(HasSymbol(U, 'TFoo', 'Bar'));
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'MyBar'));
  Tree := TPascalParser.Parse(CaseEight);
  try
    Outline := TLspDocumentSymbols.BuildSymbols(Tree);
    try
      Text := Outline.ToJSON;
    finally
      Outline.Free;
    end;
    Assert.IsFalse(Text.Contains('"IFoo.Bar"'), Text);
    Assert.IsTrue(Text.Contains('"MyBar"'), Text);
    Index := TSymbolIndex.Create;
    Resolver := TNameResolver.Create(Index);
    try
      Found := Resolver.Resolve(Tree, MainFile, PositionOf(CaseEight, 'MyBar;'));
      Assert.IsTrue(Found.Found);
      Assert.AreEqual('MyBar', Found.Name);
      Assert.AreEqual('TFoo', Found.Container);
      Assert.AreEqual(PositionOf(CaseEight, 'MyBar;'#10'  end').Line, Found.SelectionRange.StartPos.Line);
    finally
      Resolver.Free;
    end;
    Index := nil;
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.DirectivesWithoutSemicolon;
var
  Tree: TSyntaxTree;
  Header, Routine: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(Directives));
  Tree := TPascalParser.Parse(Directives);
  try
    Header := Find(Tree.Root, TSyntaxKind.RoutineHeader, 'F');
    Assert.AreEqual('stdcall', ChildNames(Header, TSyntaxKind.Directive));
    Header := Find(Tree.Root, TSyntaxKind.RoutineHeader, 'G');
    Assert.AreEqual('cdecl,external', ChildNames(Header, TSyntaxKind.Directive));
    Routine := Find(Tree.Root, TSyntaxKind.RoutineDecl, 'X');
    Assert.IsNotNull(Find(Routine, TSyntaxKind.AsmBlock, ''));
    Assert.AreEqual('assembler', ChildNames(Find(Routine, TSyntaxKind.RoutineHeader, 'X'), TSyntaxKind.Directive));
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'Y'));
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.LastFieldWithoutSemicolon;
var
  Tree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(LastField));
  Tree := TPascalParser.Parse(LastField);
  try
    Assert.AreEqual('B,G,R', ChildNames(Find(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TFColor'),
      TSyntaxKind.RecordType, ''), TSyntaxKind.Field));
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.TypeDecl, 'TV'));
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.LocalRoutinesInAnonymousMethod;
var
  Tree: TSyntaxTree;
  Anonymous: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(AnonymousLocal));
  Tree := TPascalParser.Parse(AnonymousLocal);
  try
    Anonymous := Find(Tree.Root, TSyntaxKind.AnonymousMethod, '');
    Assert.AreEqual('Inner,Calc', ChildNames(Anonymous, TSyntaxKind.RoutineDecl));
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'Z'));
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.LongElseIfChainStaysFlat;
var
  Text: string;
  Tree: TSyntaxTree;
  Node: TSyntaxNode;
  Count, Index: Integer;
begin
  Text := 'unit P13;'#10'interface'#10'implementation'#10'procedure ReadFrame(I: Integer);'#10'begin'#10 +
    '  if I = 0 then'#10'    X(0)';
  for Index := 1 to 312 do
    Text := Text + Format(#10'  else if I = %d then'#10'    X(%d)', [Index, Index]);
  Text := Text + ';'#10'end;'#10'procedure WriteFrame;'#10'begin'#10'end;'#10'end.';
  Assert.AreEqual('', Diagnostics(Text));
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsNotNull(Find(Tree.Root, TSyntaxKind.RoutineDecl, 'WriteFrame'));
    // Weiterhin je else if ein IfStatement im else-Zweig des vorigen.
    Node := Find(Tree.Root, TSyntaxKind.IfStatement, '');
    Count := 0;
    while Node <> nil do
    begin
      Inc(Count);
      if Node.ChildCount = 3 then
        Node := Node[2]
      else
        Node := nil;
      if (Node <> nil) and (Node.Kind <> TSyntaxKind.IfStatement) then
        Node := nil;
    end;
    Assert.AreEqual(313, Count);
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.SubrangeBoundStopsBeforeValue;
var
  Tree: TSyntaxTree;
  Decl, Subrange: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(SubrangeConst));
  Tree := TPascalParser.Parse(SubrangeConst);
  try
    // Der Wert (1, 2, …) steht als eigenes Kind hinter dem Typ, nicht in der Obergrenze 3.
    Decl := Find(Tree.Root, TSyntaxKind.ConstDecl, 'D2D');
    Assert.AreEqual(2, Decl.ChildCount);
    Assert.IsTrue(Decl[0].Kind = TSyntaxKind.ArrayType);
    Assert.IsTrue(Decl[1].Kind = TSyntaxKind.ParenExpr);
    Decl := Find(Tree.Root, TSyntaxKind.VarDecl, 'X');
    Subrange := Find(Decl, TSyntaxKind.SubrangeType, '');
    Assert.AreEqual(2, Subrange.ChildCount);
    Assert.IsTrue(Subrange[1].Kind = TSyntaxKind.Literal);
    Assert.IsTrue(Decl[Decl.ChildCount - 1].Kind = TSyntaxKind.Literal);
  finally
    Tree.Free;
  end;
end;

procedure TLanguageGapsTests.IncludeAsValue;
var
  Tree: TSyntaxTree;
  Decl: TSyntaxNode;
  U: TUnitIndex;
begin
  Assert.AreEqual('', Diagnostics(IncludeValue));
  Tree := TPascalParser.Parse(IncludeValue);
  try
    Decl := Find(Tree.Root, TSyntaxKind.ConstDecl, 'SYNOPSE_FRAMEWORK_VERSION');
    Assert.AreEqual(1, Decl.ChildCount);
    Assert.IsTrue(Decl[0].Kind = TSyntaxKind.Literal);
    Assert.AreEqual('{$I mormot.commit.inc}', Decl[0].Name);
  finally
    Tree.Free;
  end;
  // Ohne Include-Auflösung bleibt die Direktive, mit ihr steht der Inhalt in der Signatur.
  U := TIndexExtractor.ExtractText(IncludeValue, MainFile, nil);
  Assert.AreEqual('SYNOPSE_FRAMEWORK_VERSION = {$I mormot.commit.inc}',
    SymbolOf(U, '', 'SYNOPSE_FRAMEWORK_VERSION').Signature);
  U := TIndexExtractor.ExtractText(IncludeValue, MainFile, nil, IncludeFiles);
  Assert.AreEqual('SYNOPSE_FRAMEWORK_VERSION = ''2.3.11221''', SymbolOf(U, '', 'SYNOPSE_FRAMEWORK_VERSION').Signature);
  Assert.AreEqual(1, Integer(Length(U.Includes)));
end;

end.
