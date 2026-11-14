unit Atlas.Common.Pascal.LanguageGaps.Tests;

// Tests für kleinere Sprachlücken in Parser, Index und Namensauflösung (#849).
// Je Punkt des Issues ein Test; die Quellen stammen aus den nachgestellten
// Fällen in planung/parser-luecken-faelle (05, 07, 08, 09, 12) bzw. sind
// Fixtures zu den Korpusfunden (Punkte 10 bis 15). Dazu die Sprungmarke @@End
// im asm-Block (#861), Steuerzeichen wie ^C und die Ersatzklammern (. .) (#862).

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
    /// <summary>#861: JNZ @@End und @@End: beenden den asm-Block nicht; G liegt auf Unit-Ebene.</summary>
    [Test]
    procedure AsmLabelEndKeepsBlockOpen;
    /// <summary>#861: dasselbe klein geschrieben, mit @@Loop: und end in Kommentaren.</summary>
    [Test]
    procedure AsmLowerCaseLabelsAndComments;
    /// <summary>#862: ^C, ^M, ^[ als Zeichenliterale in Konstanten, Ausdrücken, Mengen und case-Marken.</summary>
    [Test]
    procedure ControlCharLiterals;
    /// <summary>#862: ^TFoo als Zeigertyp und P^.Feld als Dereferenzierung bleiben.</summary>
    [Test]
    procedure PointerSyntaxUnchanged;
    /// <summary>#862: (. und .) wie [ und ].</summary>
    [Test]
    procedure AlternativeBrackets;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
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
  cMainFile = 'C:\P\U.pas';
  cUnitSystem =
    'unit System;'#10'interface'#10'type'#10'  Integer = -2147483648..2147483647;'#10 +
    '  TObject = class'#10'  end;'#10'implementation'#10'end.';
  cScopedUnit =
    'unit U;'#10'interface'#10'type'#10'  {$SCOPEDENUMS ON}'#10'  TState = (None, Busy, Error);'#10 +
    '  {$SCOPEDENUMS OFF}'#10'  TColor = (Red, Green);'#10'implementation'#10'procedure P(S: TState; C: TColor);'#10 +
    'begin'#10'  if S = Error then'#10'    S := TState.Busy;'#10'  C := Red;'#10'end;'#10'end.';
  cCaseFive =
    'unit U5;'#10'interface'#10'type'#10'  TFoo<T: IFoo, IBar; V: class, constructor> = class'#10'  end;'#10 +
    '  TBaz<T: interface; U: unmanaged> = class'#10'  end;'#10'var'#10'  F: TFoo<TObject, TObject>;'#10 +
    'implementation'#10'end.';
  cCaseSeven =
    'unit U7;'#10'interface'#10'implementation'#10'procedure X(W: OleVariant);'#10'begin'#10 +
    '  W.Documents.Open(FileName := ''a.docx'', ReadOnly := True);'#10'  D := dict(a := 1, b := 2);'#10 +
    'end;'#10'end.';
  cCaseEight =
    'unit U8;'#10'interface'#10'type'#10'  IFoo = interface'#10'    procedure Bar;'#10'  end;'#10 +
    '  TFoo = class(TInterfacedObject, IFoo)'#10'    procedure IFoo.Bar = MyBar;'#10'    procedure MyBar;'#10 +
    '  end;'#10'  [Attr]'#10'  TAttr = class'#10'  strict private'#10'    const C = 1;'#10 +
    '    [Test] procedure T1;'#10'  end;'#10'implementation'#10'procedure TFoo.MyBar;'#10'begin'#10'end;'#10 +
    'procedure TAttr.T1;'#10'begin'#10'  Z := NameOf(T1);'#10'end;'#10'end.';
  cCaseNine =
    'unit U9;'#10'interface'#10'type'#10'  TFoo = class'#10'  public'#10'    {$I members.inc}'#10 +
    '    procedure After;'#10'  end;'#10'implementation'#10'end.';
  cMembersInc = 'procedure A;'#10'procedure B;'#10;
  cCaseTwelve =
    'unit U12;'#10'interface'#10'type'#10'  TFilter = record'#10'    Field, Value: string;'#10 +
    '    Operator: string;'#10'    Negate: Boolean;'#10'  end;'#10'implementation'#10'end.';
  cDirectives =
    'unit P10;'#10'interface'#10'function F(A: Integer): Integer stdcall;'#10 +
    'function G(A: Integer): Integer cdecl; external ''x.dll'';'#10'type'#10 +
    '  TCb = function(A: PAnsiChar): Integer cdecl varargs;'#10'  TCb2 = procedure(A: Integer) cdecl;'#10 +
    'implementation'#10'function F(A: Integer): Integer stdcall;'#10'begin'#10'  Result := A;'#10'end;'#10 +
    'procedure X; assembler'#10'asm'#10'  mov eax, 1'#10'end;'#10'procedure Y;'#10'begin'#10'end;'#10'end.';
  cLastField =
    'unit P11;'#10'interface'#10'type'#10'  TFColor = record B, G, R: Byte end;'#10'  TV = record'#10 +
    '    case Integer of'#10'      0: (A: Integer);'#10'      1: (C: Byte)'#10'  end;'#10'implementation'#10'end.';
  cAnonymousLocal =
    'unit P12;'#10'interface'#10'implementation'#10'procedure X;'#10'var'#10'  P: TProc;'#10'begin'#10 +
    '  P := procedure'#10'    procedure Inner;'#10'    begin'#10'    end;'#10'    function Calc: Integer;'#10 +
    '    begin'#10'      Result := 1;'#10'    end;'#10'  var'#10'    I: Integer;'#10'  begin'#10'    Inner;'#10 +
    '    I := Calc;'#10'  end;'#10'end;'#10'procedure Z;'#10'begin'#10'end;'#10'end.';
  cSubrangeConst =
    'unit P14;'#10'interface'#10'const'#10'  D2D: array [0..9] of 1..3 = (1, 2, 3, 1, 2, 3, 1, 2, 3, 1);'#10 +
    'var'#10'  X: 1..3 = 2;'#10'implementation'#10'end.';
  cIncludeValue =
    'unit P15;'#10'interface'#10'const'#10'  SYNOPSE_FRAMEWORK_VERSION = {$I mormot.commit.inc};'#10 +
    'implementation'#10'end.';

  cAsmLabel =
    'unit P16;'#10'interface'#10'implementation'#10'function F: Integer;'#10'asm'#10'  JNZ @@End;'#10 +
    '  MOV EAX, 1;'#10'@@End:'#10'end;'#10'function G: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.';
  cAsmLower =
    'unit P17;'#10'interface'#10'implementation'#10'function F: Integer;'#10'asm'#10'@@loop:'#10 +
    '  DEC ECX { end }'#10'  JNZ @@loop'#10'  JMP @@end // end'#10'  (* end *)'#10'@@end:'#10'end;'#10 +
    'function G: Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.';

  cControlChars =
    'unit P18;'#10'interface'#10'const'#10'  CtrlC = ^C;'#10'  Next = 1;'#10'  C = 2;'#10'  Esc = ^[;'#10 +
    '  CrLf = ''a''^M^J''b'';'#10'implementation'#10'procedure P(Key: Char);'#10'begin'#10 +
    '  if Key = ^M then'#10'    Exit;'#10'  if Key in [^H, #32..#255] then'#10'    Exit;'#10 +
    '  case Key of'#10'    ^C: ;'#10'    ^@, ^?: ;'#10'  end;'#10'end;'#10'end.';
  cPointers =
    'unit P19;'#10'interface'#10'type'#10'  TFoo = record Feld: Integer; end;'#10'  P = ^TFoo;'#10 +
    '  T = Integer;'#10'  PT = ^T;'#10 +
    'implementation'#10'procedure Q(F: P);'#10'var'#10'  X: Integer;'#10'begin'#10'  X := F^.Feld;'#10'end;'#10'end.';
  cBrackets =
    'unit P20;'#10'interface'#10'implementation'#10'procedure Q(C: Char; var A: array of Integer);'#10'begin'#10 +
    '  if C in (. ''a''..''z'' .) then'#10'    A(.1.) := 2;'#10'end;'#10'end.';

function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := Find(ANode[mIndex], AKind, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = AKind then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + ANode[mIndex].Name;
    end;
  end;
end;

function Diagnostics(const AText: string): string;
var
  mTree: TSyntaxTree;
  mDiagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mDiagnostic in mTree.Diagnostics do
    begin
      Result := Result + Format('%d:%d %s; ', [mDiagnostic.StartPos.Line, mDiagnostic.StartPos.Character,
        mDiagnostic.Message]);
    end;
  finally
    mTree.Free;
  end;
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function SymbolOf(const AUnit: TUnitIndex; const AContainer, AName: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName) then
    begin
      Exit(mSymbol);
    end;
  end;
  raise Exception.CreateFmt('%s.%s fehlt im Index', [AContainer, AName]);
end;

function HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function IncludeFiles: TIncludeResolver;
begin
  Result :=
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      AFileName := 'C:\P\' + AName;
      if SameText(AName, 'members.inc') then
      begin
        AText := cMembersInc;
      end
      else if SameText(AName, 'mormot.commit.inc') then
      begin
        AText := '''2.3.11221'''#10;
      end
      else
      begin
        Exit(False);
      end;
      Result := True;
    end;
end;

{ TLanguageGapsTests }

procedure TLanguageGapsTests.ScopedEnumValuesNeedTypePrefix;
var
  U: TUnitIndex;
  mLoaded: TArray<TUnitIndex>;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mFound: TResolvedSymbol;
begin
  U := TIndexExtractor.ExtractText(cScopedUnit, cMainFile, nil);
  Assert.IsTrue(SymbolOf(U, '', 'TState').ScopedEnum);
  Assert.IsTrue(SymbolOf(U, 'TState', 'Error').ScopedEnum);
  Assert.IsFalse(SymbolOf(U, '', 'TColor').ScopedEnum);
  Assert.IsFalse(SymbolOf(U, 'TColor', 'Red').ScopedEnum);
  // Der Schalter übersteht den Cache.
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.IsTrue(SymbolOf(mLoaded[0], 'TState', 'Error').ScopedEnum);
  Assert.IsFalse(SymbolOf(mLoaded[0], 'TColor', 'Red').ScopedEnum);
  mIndex := TSymbolIndex.Create;
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cScopedUnit);
  try
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cScopedUnit, 'Error then'));
    Assert.IsFalse(mFound.Found, 'unqualifiziert');
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cScopedUnit, 'Busy;'));
    Assert.IsTrue(mFound.Found, 'TState.Busy');
    Assert.AreEqual('TState', mFound.Container);
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cScopedUnit, 'Red;'));
    Assert.IsTrue(mFound.Found, 'Red ohne SCOPEDENUMS');
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
end;

procedure TLanguageGapsTests.UnresolvedScopedValueSuggestsPrefix;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mNames: TArray<TUnresolvedName>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSystem, 'C:\Lib\System.pas', nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cScopedUnit);
  try
    mNames := TUnresolvedNames.Find(mResolver, mTree, cMainFile);
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
  Assert.AreEqual(1, Integer(Length(mNames)));
  Assert.AreEqual('Error', mNames[0].Name);
  Assert.AreEqual('TState.Error', mNames[0].Suggestion);
end;

procedure TLanguageGapsTests.GenericConstraintsKeepParameters;
var
  mTree: TSyntaxTree;
  U: TUnitIndex;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mFound: TResolvedSymbol;
begin
  Assert.AreEqual('', Diagnostics(cCaseFive));
  mTree := TPascalParser.Parse(cCaseFive);
  try
    Assert.AreEqual('T,V', ChildNames(Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TFoo'),
      TSyntaxKind.GenericParams, ''), TSyntaxKind.Identifier));
    Assert.AreEqual('T,U', ChildNames(Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TBaz'),
      TSyntaxKind.GenericParams, ''), TSyntaxKind.Identifier));
  finally
    mTree.Free;
  end;
  U := TIndexExtractor.ExtractText(cCaseFive, cMainFile, nil);
  Assert.AreEqual('T,V', SymbolOf(U, '', 'TFoo').TypeParams);
  // Gehe zu auf TFoo<TObject, TObject>: Stelligkeit 2 passt.
  mIndex := TSymbolIndex.Create;
  mResolver := TNameResolver.Create(mIndex);
  mTree := TPascalParser.Parse(cCaseFive);
  try
    mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cCaseFive, 'TFoo<TObject'));
    Assert.IsTrue(mFound.Found);
    Assert.AreEqual('TFoo', mFound.Name);
  finally
    mTree.Free;
    mResolver.Free;
  end;
  mIndex := nil;
end;

procedure TLanguageGapsTests.IncludeInClassBodyAddsMembers;
var
  U: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText(cCaseNine, cMainFile, nil, IncludeFiles());
  mSymbol := SymbolOf(U, 'TFoo', 'A');
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Method, mSymbol.Kind);
  Assert.AreEqual('C:\P\members.inc', mSymbol.FileName);
  Assert.AreEqual(0, mSymbol.SelectionRange.StartPos.Line);
  Assert.AreEqual<TIndexVisibility>(TIndexVisibility.Public, mSymbol.Visibility);
  mSymbol := SymbolOf(U, 'TFoo', 'B');
  Assert.AreEqual(1, mSymbol.SelectionRange.StartPos.Line);
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'After'));
  // Keine freien Routinen und kein Hilfstyp.
  Assert.IsFalse(HasSymbol(U, '', 'A'));
  Assert.IsFalse(HasSymbol(U, '', 'B'));
  for mSymbol in U.Symbols do
  begin
    Assert.IsFalse(mSymbol.Name.StartsWith('TAtlasIncludeHost'), mSymbol.Name);
  end;
end;

procedure TLanguageGapsTests.NamedArgumentsParse;
var
  mTree: TSyntaxTree;
  mCall: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cCaseSeven));
  mTree := TPascalParser.Parse(cCaseSeven);
  try
    mCall := Find(mTree.Root, TSyntaxKind.Call, 'Open');
    Assert.IsNotNull(mCall);
    // Ziel und zwei Werte; die Namen der Argumente stehen nicht als Bezeichner im Baum.
    Assert.AreEqual(3, mCall.ChildCount);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Literal, mCall[1].Kind);
    Assert.IsNull(Find(mTree.Root, TSyntaxKind.Identifier, 'FileName'));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.OperatorFieldIsField;
var
  mTree: TSyntaxTree;
  mRec: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cCaseTwelve));
  mTree := TPascalParser.Parse(cCaseTwelve);
  try
    mRec := Find(mTree.Root, TSyntaxKind.RecordType, '');
    Assert.AreEqual('Field,Value,Operator,Negate', ChildNames(mRec, TSyntaxKind.Field));
    Assert.AreEqual('', ChildNames(mRec, TSyntaxKind.RoutineHeader));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.AttributeAfterConstSectionEndsSection;
var
  mTree: TSyntaxTree;
  mBody, mSection: TSyntaxNode;
  mIndex: Integer;
begin
  mTree := TPascalParser.Parse(cCaseEight);
  try
    mBody := Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TAttr'), TSyntaxKind.ClassType, '');
    mSection := Find(mBody, TSyntaxKind.ConstSection, '');
    Assert.IsNotNull(mSection);
    Assert.AreEqual('', ChildNames(mSection, TSyntaxKind.Attribute));
    // Das Attribut steht im Rumpf direkt vor dem Methodenkopf.
    mIndex := mBody.ChildCount - 1;
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.RoutineHeader, mBody[mIndex].Kind);
    Assert.AreEqual('T1', mBody[mIndex].Name);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Attribute, mBody[mIndex - 1].Kind);
    Assert.AreEqual('Test', mBody[mIndex - 1].Name);
  finally
    mTree.Free;
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
  mLoaded: TArray<TUnitIndex>;
  mTree: TSyntaxTree;
  mOutline: TJSONArray;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mFound: TResolvedSymbol;
  mText: string;
begin
  Assert.AreEqual('', Diagnostics(cCaseEight));
  U := TIndexExtractor.ExtractText(cCaseEight, cMainFile, nil);
  Assert.IsFalse(HasSymbol(U, 'TFoo', 'IFoo.Bar'));
  Assert.IsFalse(HasSymbol(U, 'TFoo', 'Bar'));
  Assert.IsTrue(HasSymbol(U, 'TFoo', 'MyBar'));
  // Die Zuordnung steht an der Klasse und übersteht den Cache (interface-not-implemented, hresult-integer-mix).
  Assert.AreEqual(1, Integer(Length(SymbolOf(U, '', 'TFoo').Resolutions)));
  Assert.AreEqual('IFoo.Bar=MyBar', SymbolOf(U, '', 'TFoo').Resolutions[0]);
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.AreEqual(1, Integer(Length(SymbolOf(mLoaded[0], '', 'TFoo').Resolutions)));
  Assert.AreEqual('IFoo.Bar=MyBar', SymbolOf(mLoaded[0], '', 'TFoo').Resolutions[0]);
  Assert.AreEqual(0, Integer(Length(SymbolOf(U, '', 'IFoo').Resolutions)));
  mTree := TPascalParser.Parse(cCaseEight);
  try
    mOutline := TLspDocumentSymbols.BuildSymbols(mTree);
    try
      mText := mOutline.ToJSON;
    finally
      mOutline.Free;
    end;
    Assert.IsFalse(mText.Contains('"IFoo.Bar"'), mText);
    Assert.IsTrue(mText.Contains('"MyBar"'), mText);
    mIndex := TSymbolIndex.Create;
    mResolver := TNameResolver.Create(mIndex);
    try
      mFound := mResolver.Resolve(mTree, cMainFile, PositionOf(cCaseEight, 'MyBar;'));
      Assert.IsTrue(mFound.Found);
      Assert.AreEqual('MyBar', mFound.Name);
      Assert.AreEqual('TFoo', mFound.Container);
      Assert.AreEqual(PositionOf(cCaseEight, 'MyBar;'#10'  end').Line, mFound.SelectionRange.StartPos.Line);
    finally
      mResolver.Free;
    end;
    mIndex := nil;
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.DirectivesWithoutSemicolon;
var
  mTree: TSyntaxTree;
  mHeader, mRoutine: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cDirectives));
  mTree := TPascalParser.Parse(cDirectives);
  try
    mHeader := Find(mTree.Root, TSyntaxKind.RoutineHeader, 'F');
    Assert.AreEqual('stdcall', ChildNames(mHeader, TSyntaxKind.Directive));
    mHeader := Find(mTree.Root, TSyntaxKind.RoutineHeader, 'G');
    Assert.AreEqual('cdecl,external', ChildNames(mHeader, TSyntaxKind.Directive));
    mRoutine := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'X');
    Assert.IsNotNull(Find(mRoutine, TSyntaxKind.AsmBlock, ''));
    Assert.AreEqual('assembler', ChildNames(Find(mRoutine, TSyntaxKind.RoutineHeader, 'X'), TSyntaxKind.Directive));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Y'));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.LastFieldWithoutSemicolon;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cLastField));
  mTree := TPascalParser.Parse(cLastField);
  try
    Assert.AreEqual('B,G,R', ChildNames(Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TFColor'),
      TSyntaxKind.RecordType, ''), TSyntaxKind.Field));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.TypeDecl, 'TV'));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.LocalRoutinesInAnonymousMethod;
var
  mTree: TSyntaxTree;
  mAnonymous: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cAnonymousLocal));
  mTree := TPascalParser.Parse(cAnonymousLocal);
  try
    mAnonymous := Find(mTree.Root, TSyntaxKind.AnonymousMethod, '');
    Assert.AreEqual('Inner,Calc', ChildNames(mAnonymous, TSyntaxKind.RoutineDecl));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'Z'));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.LongElseIfChainStaysFlat;
var
  mText: string;
  mTree: TSyntaxTree;
  mNode: TSyntaxNode;
  mCount, mIndex: Integer;
begin
  mText := 'unit P13;'#10'interface'#10'implementation'#10'procedure ReadFrame(I: Integer);'#10'begin'#10 +
    '  if I = 0 then'#10'    X(0)';
  for mIndex := 1 to 312 do
  begin
    mText := mText + Format(#10'  else if I = %d then'#10'    X(%d)', [mIndex, mIndex]);
  end;
  mText := mText + ';'#10'end;'#10'procedure WriteFrame;'#10'begin'#10'end;'#10'end.';
  Assert.AreEqual('', Diagnostics(mText));
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.RoutineDecl, 'WriteFrame'));
    // Weiterhin je else if ein IfStatement im else-Zweig des vorigen.
    mNode := Find(mTree.Root, TSyntaxKind.IfStatement, '');
    mCount := 0;
    while mNode <> nil do
    begin
      Inc(mCount);
      if mNode.ChildCount = 3 then
      begin
        mNode := mNode[2];
      end
      else
      begin
        mNode := nil;
      end;
      if (mNode <> nil) and (mNode.Kind <> TSyntaxKind.IfStatement) then
      begin
        mNode := nil;
      end;
    end;
    Assert.AreEqual(313, mCount);
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.SubrangeBoundStopsBeforeValue;
var
  mTree: TSyntaxTree;
  mDecl, mSubrange: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(cSubrangeConst));
  mTree := TPascalParser.Parse(cSubrangeConst);
  try
    // Der Wert (1, 2, …) steht als eigenes Kind hinter dem Typ, nicht in der Obergrenze 3.
    mDecl := Find(mTree.Root, TSyntaxKind.ConstDecl, 'D2D');
    Assert.AreEqual(2, mDecl.ChildCount);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.ArrayType, mDecl[0].Kind);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.ParenExpr, mDecl[1].Kind);
    mDecl := Find(mTree.Root, TSyntaxKind.VarDecl, 'X');
    mSubrange := Find(mDecl, TSyntaxKind.SubrangeType, '');
    Assert.AreEqual(2, mSubrange.ChildCount);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Literal, mSubrange[1].Kind);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Literal, mDecl[mDecl.ChildCount - 1].Kind);
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.IncludeAsValue;
var
  mTree: TSyntaxTree;
  mDecl: TSyntaxNode;
  U: TUnitIndex;
begin
  Assert.AreEqual('', Diagnostics(cIncludeValue));
  mTree := TPascalParser.Parse(cIncludeValue);
  try
    mDecl := Find(mTree.Root, TSyntaxKind.ConstDecl, 'SYNOPSE_FRAMEWORK_VERSION');
    Assert.AreEqual(1, mDecl.ChildCount);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Literal, mDecl[0].Kind);
    Assert.AreEqual('{$I mormot.commit.inc}', mDecl[0].Name);
  finally
    mTree.Free;
  end;
  // Ohne Include-Auflösung bleibt die Direktive, mit ihr steht der Inhalt in der Signatur.
  U := TIndexExtractor.ExtractText(cIncludeValue, cMainFile, nil);
  Assert.AreEqual('SYNOPSE_FRAMEWORK_VERSION = {$I mormot.commit.inc}',
    SymbolOf(U, '', 'SYNOPSE_FRAMEWORK_VERSION').Signature);
  U := TIndexExtractor.ExtractText(cIncludeValue, cMainFile, nil, IncludeFiles());
  Assert.AreEqual('SYNOPSE_FRAMEWORK_VERSION = ''2.3.11221''', SymbolOf(U, '', 'SYNOPSE_FRAMEWORK_VERSION').Signature);
  Assert.AreEqual(1, Integer(Length(U.Includes)));
end;

/// <summary>F und G liegen nebeneinander im implementation-Teil, ohne Diagnosen (#861).</summary>
procedure AssertAsmUnit(const AText: string);
var
  mTree: TSyntaxTree;
  F, G: TSyntaxNode;
begin
  Assert.AreEqual('', Diagnostics(AText));
  mTree := TPascalParser.Parse(AText);
  try
    F := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'F');
    G := Find(mTree.Root, TSyntaxKind.RoutineDecl, 'G');
    Assert.IsNotNull(F);
    Assert.IsNotNull(G);
    Assert.IsNotNull(Find(F, TSyntaxKind.AsmBlock, ''));
    Assert.AreSame(F.Parent, G.Parent, 'G muss neben F liegen');
    Assert.IsNull(Find(mTree.Root, TSyntaxKind.InitializationSection, ''));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.AsmLabelEndKeepsBlockOpen;
begin
  AssertAsmUnit(cAsmLabel);
end;

procedure TLanguageGapsTests.AsmLowerCaseLabelsAndComments;
begin
  AssertAsmUnit(cAsmLower);
end;

/// <summary>Index des ANth-ten Tokens mit dem Text AText (ab 0) in Tree.Tokens; -1 ohne.</summary>
function TokenIndexOf(ATree: TSyntaxTree; const AText: string; ANth: Integer): Integer;
var
  mIndex, mSeen: Integer;
begin
  mSeen := 0;
  for mIndex := 0 to High(ATree.Tokens) do
  begin
    if ATree.Tokens[mIndex].Text = AText then
    begin
      if mSeen = ANth then
      begin
        Exit(mIndex);
      end;
      Inc(mSeen);
    end;
  end;
  Result := -1;
end;

/// <summary>Namen aller Literale in Baumreihenfolge, durch | getrennt.</summary>
function LiteralNames(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  if ANode.Kind = TSyntaxKind.Literal then
  begin
    Result := ANode.Name + '|';
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := Result + LiteralNames(ANode[mIndex]);
  end;
end;

procedure TLanguageGapsTests.ControlCharLiterals;
var
  mTree: TSyntaxTree;
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
begin
  mIndex := TSymbolIndex.Create;
  Assert.AreEqual('', Diagnostics(cControlChars));
  mTree := TPascalParser.Parse(cControlChars);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.ConstDecl, 'CtrlC'));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.ConstDecl, 'Next'), 'der Abschnitt bricht nicht ab');
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.ConstDecl, 'Esc'));
    Assert.AreEqual('#3|1|2|#27|''a''#13#10''b''|#13|#8|#32|#255|#3|#0|#127|', LiteralNames(mTree.Root));
    // C in ^C ist kein Verweis auf die Konstante C (Hover, Gehe zu, Hervorhebung).
    mResolver := TNameResolver.Create(mIndex);
    try
      Assert.IsFalse(mResolver.Resolve(mTree, cMainFile, PositionOf(cControlChars, 'C: ;')).Found, '^C');
      Assert.IsTrue(mResolver.Resolve(mTree, cMainFile, PositionOf(cControlChars, 'C = 2')).Found, 'Konstante C');
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.PointerSyntaxUnchanged;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cPointers));
  mTree := TPascalParser.Parse(cPointers);
  try
    Assert.IsNotNull(Find(Find(mTree.Root, TSyntaxKind.TypeDecl, 'P'), TSyntaxKind.PointerType, ''));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.Dereference, ''));
    Assert.AreEqual('', LiteralNames(mTree.Root));
    // ^T ist ein Zeigertyp: T bleibt ein Name.
    Assert.IsFalse(mTree.IsControlCharPart(TokenIndexOf(mTree, 'T', 1)));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageGapsTests.AlternativeBrackets;
var
  mTree: TSyntaxTree;
begin
  Assert.AreEqual('', Diagnostics(cBrackets));
  mTree := TPascalParser.Parse(cBrackets);
  try
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.SetConstructor, ''));
    Assert.IsNotNull(Find(mTree.Root, TSyntaxKind.IndexAccess, ''));
  finally
    mTree.Free;
  end;
end;

end.
