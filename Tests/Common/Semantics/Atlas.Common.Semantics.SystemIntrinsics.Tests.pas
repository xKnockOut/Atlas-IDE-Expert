unit Atlas.Common.Semantics.SystemIntrinsics.Tests;

// #880: Bezeichner der Unit System ohne Quelltext (Assigned, SetLength, Integer ...) in Vervollständigung,
// Parameter-Hinweis und Hover, auch ohne indexierte RTL.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest;

type
  [TestFixture]
  TSystemIntrinsicsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const ACode, AMarker: string): TCompletionItems;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListKnowsRoutinesTypesAndOverloads;
    [Test]
    procedure EnglishTextsFollowLanguage;
    [Test]
    procedure NameAtSkipsMembersAfterDot;
    [Test]
    procedure CompletionOffersIntrinsicsWithoutUses;
    [Test]
    procedure CompletionOffersBuiltinTypes;
    [Test]
    procedure IndexedSystemDeclarationWins;
    [Test]
    procedure OwnDeclarationHidesIntrinsic;
    [Test]
    procedure SignatureHelpForIntrinsics;
    [Test]
    procedure HoverForIntrinsicsAndTypes;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.SystemIntrinsics,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Localization.Texts;

const
  cHauptFile = 'C:\P\Haupt.pas';

  // Ohne uses: System ist trotzdem eingebunden.
  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
    'var'#10 +
    '  Liste: TArray<Integer>;'#10 +
    'begin'#10 +
    '  |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  // Cursor hinter AMarker.
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(mIndex, Length(AMarker));
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

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(cUnitHaupt, '  |', ACode, []);
end;

function CountNamed(const AItems: TCompletionItems; const AName: string): Integer;
var
  mItem: TCompletionItem;
begin
  Result := 0;
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Inc(Result);
    end;
  end;
end;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

{ TSystemIntrinsicsTests }

procedure TSystemIntrinsicsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TSystemIntrinsicsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TSystemIntrinsicsTests.ItemsAt(const ACode, AMarker: string): TCompletionItems;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := WithCode(ACode);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile, PositionOf(mText, AMarker),
      TCompletionMatching.Prefix);
  finally
    mTree.Free;
  end;
end;

procedure TSystemIntrinsicsTests.EnglishTextsFollowLanguage;
var
  mFound: TArray<TSystemIntrinsic>;
begin
  // #1458: Beschreibung und Platzhalter im Kopf folgen der Sprache, die Köpfe sonst nicht.
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mFound := TSystemIntrinsics.Find('Abs');
    Assert.AreEqual('Absolute value of a number.', mFound[0].Documentation);
    Assert.AreEqual('function Abs(X): <type of X>;', mFound[0].Declaration);
    Assert.AreEqual('Integer, 32 bits signed.', TSystemIntrinsics.Find('Integer')[0].Documentation);
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
  mFound := TSystemIntrinsics.Find('Abs');
  Assert.AreEqual('Betrag einer Zahl.', mFound[0].Documentation);
  Assert.AreEqual('function Abs(X): <Typ von X>;', mFound[0].Declaration);
end;

procedure TSystemIntrinsicsTests.ListKnowsRoutinesTypesAndOverloads;
var
  mFound: TArray<TSystemIntrinsic>;
begin
  mFound := TSystemIntrinsics.Find('inc');
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[0].MinArgs);
  Assert.AreEqual(1, mFound[0].MaxArgs);
  Assert.AreEqual(2, mFound[1].MaxArgs);
  mFound := TSystemIntrinsics.Find('SetLength');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(2, mFound[0].MinArgs);
  mFound := TSystemIntrinsics.Find('AtomicIncrement');
  // Standardwert zählt nicht zur Mindestzahl.
  Assert.AreEqual(1, mFound[0].MinArgs);
  Assert.AreEqual(2, mFound[0].MaxArgs);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.RecordType, TSystemIntrinsics.Find('Integer')[0].Kind);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Routine, TSystemIntrinsics.Find('Assigned')[0].Kind);
  Assert.IsTrue(TSystemIntrinsics.IsKnown('NativeInt'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('Cardinal'));
  Assert.IsFalse(TSystemIntrinsics.IsKnown('Unbekannt'));
  // CompilerVersion steht in System.pas nur im Kommentar; der Compiler setzt sie.
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Constant, TSystemIntrinsics.Find('CompilerVersion')[0].Kind);
  // Typen des Compilers ohne Deklaration in System.pas und Fail der alten object-Syntax (#1382).
  Assert.IsTrue(TSystemIntrinsics.IsType('TextFile'));
  Assert.IsTrue(TSystemIntrinsics.IsType('Text'));
  Assert.IsTrue(TSystemIntrinsics.IsType('Real48'));
  Assert.IsFalse(TSystemIntrinsics.IsType('Fail'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('Fail'));
  // Datei-Routinen ohne Deklaration in System.pas (#1382); Eof gibt es mit und ohne Datei.
  Assert.IsTrue(TSystemIntrinsics.IsKnown('AssignFile'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('Append'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('CloseFile'));
  Assert.IsFalse(TSystemIntrinsics.IsType('CloseFile'));
  Assert.AreEqual(2, Integer(Length(TSystemIntrinsics.Find('Eof'))));
  Assert.AreEqual(2, TSystemIntrinsics.Find('AssignFile')[0].MinArgs);
  Assert.AreEqual(3, TSystemIntrinsics.Find('AssignFile')[0].MaxArgs);
  // Speicher-Routinen: FreeMem mit und ohne Größe (GetMem/FreeMem gemeldet).
  Assert.IsTrue(TSystemIntrinsics.IsKnown('GetMem'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('ReallocMem'));
  Assert.AreEqual(1, TSystemIntrinsics.Find('FreeMem')[0].MinArgs);
  Assert.AreEqual(2, TSystemIntrinsics.Find('FreeMem')[0].MaxArgs);
  Assert.IsTrue(TSystemIntrinsics.IsType('OleVariant'));
end;

procedure TSystemIntrinsicsTests.NameAtSkipsMembersAfterDot;
var
  mText, mName: string;
  mTree: TSyntaxTree;
begin
  mText := WithCode('  X := Liste.Length + Length(Liste);');
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsFalse(TSystemIntrinsics.NameAt(mTree, PositionOf(mText, 'Liste.Len'), mName));
    Assert.IsTrue(TSystemIntrinsics.NameAt(mTree, PositionOf(mText, '+ Len'), mName));
    Assert.AreEqual('Length', mName);
    Assert.IsFalse(TSystemIntrinsics.NameAt(mTree, PositionOf(mText, '  X'), mName));
  finally
    mTree.Free;
  end;
end;

procedure TSystemIntrinsicsTests.CompletionOffersIntrinsicsWithoutUses;
begin
  Assert.AreEqual(1, CountNamed(ItemsAt('  Assi', '  Assi'), 'Assigned'));
  Assert.AreEqual(1, CountNamed(ItemsAt('  SetLe', '  SetLe'), 'SetLength'));
  Assert.AreEqual(1, CountNamed(ItemsAt('  Leng', '  Leng'), 'Length'));
  // Überladungen erscheinen einmal.
  Assert.AreEqual(1, CountNamed(ItemsAt('  Inc', '  Inc'), 'Inc'));
end;

procedure TSystemIntrinsicsTests.CompletionOffersBuiltinTypes;
begin
  Assert.AreEqual(1, CountNamed(ItemsAt('  Int6', '  Int6'), 'Int64'));
  Assert.AreEqual(1, CountNamed(ItemsAt('  Card', '  Card'), 'Cardinal'));
  Assert.AreEqual(1, CountNamed(ItemsAt('  NativeI', '  NativeI'), 'NativeInt'));
  Assert.AreEqual(1, CountNamed(ItemsAt('  Integ', '  Integ'), 'Integer'));
end;

procedure TSystemIntrinsicsTests.IndexedSystemDeclarationWins;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Liegt System.pas im Index, kommt der Eintrag von dort, nicht doppelt aus der Liste.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10 +
    'function Length(const S: string): Integer;'#10'implementation'#10 +
    'function Length(const S: string): Integer; begin end;'#10'end.', 'C:\Lib\System.pas', nil));
  mItems := ItemsAt('  Leng', '  Leng');
  Assert.AreEqual(1, CountNamed(mItems, 'Length'));
  for mItem in mItems.Items do
  begin
    if SameText(mItem.Name, 'Length') then
    begin
      Assert.AreEqual('C:\Lib\System.pas', mItem.SourceFile);
    end;
  end;
end;

procedure TSystemIntrinsicsTests.OwnDeclarationHidesIntrinsic;
var
  mText: string;
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Ohne Eingabe keine Liste von System (die Antwort ist dann ohnehin unvollständig).
  mItems := ItemsAt('  ', #10'begin'#10'  ');
  Assert.AreEqual(0, CountNamed(mItems, 'Assigned'));
  Assert.IsTrue(mItems.Incomplete);
  // Eine eigene Routine gleichen Namens verdeckt den Eintrag.
  mText := StringReplace(WithCode('  Assi'), 'procedure TFoo.Bar;',
    'function Assigned(P: Pointer): Boolean;'#10'begin'#10'end;'#10'procedure TFoo.Bar;', []);
  mTree := TPascalParser.Parse(mText);
  try
    mItems := TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile, PositionOf(mText, '  Assi'),
      TCompletionMatching.Prefix);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, CountNamed(mItems, 'Assigned'));
  for mItem in mItems.Items do
  begin
    if SameText(mItem.Name, 'Assigned') then
    begin
      Assert.AreEqual(cHauptFile, mItem.SourceFile);
    end;
  end;
end;

procedure TSystemIntrinsicsTests.SignatureHelpForIntrinsics;
var
  mText: string;
  mTree: TSyntaxTree;
  mHelp: TSignatureHelp;
begin
  mText := WithCode('  SetLength(Liste, ');
  mTree := TPascalParser.Parse(mText);
  try
    mHelp := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile, NoText),
      PositionOf(mText, 'Liste, '));
    Assert.IsTrue(mHelp.Found);
    Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
    Assert.AreEqual('procedure SetLength(var S; NewLength: NativeInt)', mHelp.Signatures[0].Text);
    Assert.AreEqual(1, mHelp.ActiveParameter);
    Assert.AreNotEqual('', mHelp.Signatures[0].Documentation);
  finally
    mTree.Free;
  end;
  mText := WithCode('  Inc(Liste[0], ');
  mTree := TPascalParser.Parse(mText);
  try
    mHelp := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile, NoText),
      PositionOf(mText, '[0], '));
    Assert.AreEqual(2, Integer(Length(mHelp.Signatures)));
    // Die erste Überladung hat nur einen Parameter.
    Assert.AreEqual(1, mHelp.ActiveSignature);
  finally
    mTree.Free;
  end;
  // Nach einem Punkt ist Length ein Mitglied, keine Routine von System.
  mText := WithCode('  Liste.Length(');
  mTree := TPascalParser.Parse(mText);
  try
    mHelp := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile, NoText),
      PositionOf(mText, 'Length('));
    Assert.IsFalse(mHelp.Found);
  finally
    mTree.Free;
  end;
end;

procedure TSystemIntrinsicsTests.HoverForIntrinsicsAndTypes;
var
  mText: string;
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
begin
  mText := WithCode('  if Assigned(Self) then Exit;');
  mTree := TPascalParser.Parse(mText);
  try
    mInfo := TLspHover.InfoAt(THoverSource.Create(FResolver, FIndex, NoText), mTree, mText, cHauptFile,
      PositionOf(mText, 'if Assi'));
    Assert.AreEqual('function Assigned(const P): Boolean;', mInfo.Declaration);
    Assert.AreEqual('System', mInfo.UnitName);
    Assert.AreNotEqual('', mInfo.Documentation);
  finally
    mTree.Free;
  end;
  mText := StringReplace(WithCode('  '), 'TArray<Integer>', 'Int64', []);
  mTree := TPascalParser.Parse(mText);
  try
    mInfo := TLspHover.InfoAt(THoverSource.Create(FResolver, FIndex, NoText), mTree, mText, cHauptFile,
      PositionOf(mText, 'Liste: Int'));
    Assert.IsTrue(mInfo.Declaration.StartsWith('type Int64'), mInfo.Declaration);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSystemIntrinsicsTests);

end.
