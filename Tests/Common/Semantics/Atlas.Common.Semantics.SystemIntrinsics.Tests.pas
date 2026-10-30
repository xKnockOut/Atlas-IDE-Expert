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
  Atlas.Common.Lsp.Hover;

const
  HauptFile = 'C:\P\Haupt.pas';

  // Ohne uses: System ist trotzdem eingebunden.
  UnitHaupt =
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
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
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

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  |', ACode, []);
end;

function CountNamed(const AItems: TCompletionItems; const AName: string): Integer;
var
  Item: TCompletionItem;
begin
  Result := 0;
  for Item in AItems.Items do
    if SameText(Item.Name, AName) then
      Inc(Result);
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
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := WithCode(ACode);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(Text, AMarker),
      TCompletionMatching.Prefix);
  finally
    Tree.Free;
  end;
end;

procedure TSystemIntrinsicsTests.ListKnowsRoutinesTypesAndOverloads;
var
  Found: TArray<TSystemIntrinsic>;
begin
  Found := TSystemIntrinsics.Find('inc');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(1, Found[0].MinArgs);
  Assert.AreEqual(1, Found[0].MaxArgs);
  Assert.AreEqual(2, Found[1].MaxArgs);
  Found := TSystemIntrinsics.Find('SetLength');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(2, Found[0].MinArgs);
  Found := TSystemIntrinsics.Find('AtomicIncrement');
  // Standardwert zählt nicht zur Mindestzahl.
  Assert.AreEqual(1, Found[0].MinArgs);
  Assert.AreEqual(2, Found[0].MaxArgs);
  Assert.IsTrue(TSystemIntrinsics.Find('Integer')[0].Kind = TIndexSymbolKind.RecordType);
  Assert.IsTrue(TSystemIntrinsics.Find('Assigned')[0].Kind = TIndexSymbolKind.Routine);
  Assert.IsTrue(TSystemIntrinsics.IsKnown('NativeInt'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('Cardinal'));
  Assert.IsFalse(TSystemIntrinsics.IsKnown('Unbekannt'));
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
  // Speicher-Routinen: FreeMem mit und ohne Größe (Marco 30.10.2026, GetMem/FreeMem gemeldet).
  Assert.IsTrue(TSystemIntrinsics.IsKnown('GetMem'));
  Assert.IsTrue(TSystemIntrinsics.IsKnown('ReallocMem'));
  Assert.AreEqual(1, TSystemIntrinsics.Find('FreeMem')[0].MinArgs);
  Assert.AreEqual(2, TSystemIntrinsics.Find('FreeMem')[0].MaxArgs);
  Assert.IsTrue(TSystemIntrinsics.IsType('OleVariant'));
end;

procedure TSystemIntrinsicsTests.NameAtSkipsMembersAfterDot;
var
  Text, Name: string;
  Tree: TSyntaxTree;
begin
  Text := WithCode('  X := Liste.Length + Length(Liste);');
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsFalse(TSystemIntrinsics.NameAt(Tree, PositionOf(Text, 'Liste.Len'), Name));
    Assert.IsTrue(TSystemIntrinsics.NameAt(Tree, PositionOf(Text, '+ Len'), Name));
    Assert.AreEqual('Length', Name);
    Assert.IsFalse(TSystemIntrinsics.NameAt(Tree, PositionOf(Text, '  X'), Name));
  finally
    Tree.Free;
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
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  // Liegt System.pas im Index, kommt der Eintrag von dort, nicht doppelt aus der Liste.
  FIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10 +
    'function Length(const S: string): Integer;'#10'implementation'#10 +
    'function Length(const S: string): Integer; begin end;'#10'end.', 'C:\Lib\System.pas', nil));
  Items := ItemsAt('  Leng', '  Leng');
  Assert.AreEqual(1, CountNamed(Items, 'Length'));
  for Item in Items.Items do
    if SameText(Item.Name, 'Length') then
      Assert.AreEqual('C:\Lib\System.pas', Item.SourceFile);
end;

procedure TSystemIntrinsicsTests.OwnDeclarationHidesIntrinsic;
var
  Text: string;
  Tree: TSyntaxTree;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  // Ohne Eingabe keine Liste von System (die Antwort ist dann ohnehin unvollständig).
  Items := ItemsAt('  ', #10'begin'#10'  ');
  Assert.AreEqual(0, CountNamed(Items, 'Assigned'));
  Assert.IsTrue(Items.Incomplete);
  // Eine eigene Routine gleichen Namens verdeckt den Eintrag.
  Text := StringReplace(WithCode('  Assi'), 'procedure TFoo.Bar;',
    'function Assigned(P: Pointer): Boolean;'#10'begin'#10'end;'#10'procedure TFoo.Bar;', []);
  Tree := TPascalParser.Parse(Text);
  try
    Items := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(Text, '  Assi'),
      TCompletionMatching.Prefix);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(1, CountNamed(Items, 'Assigned'));
  for Item in Items.Items do
    if SameText(Item.Name, 'Assigned') then
      Assert.AreEqual(HauptFile, Item.SourceFile);
end;

procedure TSystemIntrinsicsTests.SignatureHelpForIntrinsics;
var
  Text: string;
  Tree: TSyntaxTree;
  Help: TSignatureHelp;
begin
  Text := WithCode('  SetLength(Liste, ');
  Tree := TPascalParser.Parse(Text);
  try
    Help := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'Liste, '), NoText);
    Assert.IsTrue(Help.Found);
    Assert.AreEqual(1, Integer(Length(Help.Signatures)));
    Assert.AreEqual('procedure SetLength(var S; NewLength: NativeInt)', Help.Signatures[0].Text);
    Assert.AreEqual(1, Help.ActiveParameter);
    Assert.AreNotEqual('', Help.Signatures[0].Documentation);
  finally
    Tree.Free;
  end;
  Text := WithCode('  Inc(Liste[0], ');
  Tree := TPascalParser.Parse(Text);
  try
    Help := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, '[0], '), NoText);
    Assert.AreEqual(2, Integer(Length(Help.Signatures)));
    // Die erste Überladung hat nur einen Parameter.
    Assert.AreEqual(1, Help.ActiveSignature);
  finally
    Tree.Free;
  end;
  // Nach einem Punkt ist Length ein Mitglied, keine Routine von System.
  Text := WithCode('  Liste.Length(');
  Tree := TPascalParser.Parse(Text);
  try
    Help := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'Length('), NoText);
    Assert.IsFalse(Help.Found);
  finally
    Tree.Free;
  end;
end;

procedure TSystemIntrinsicsTests.HoverForIntrinsicsAndTypes;
var
  Text: string;
  Tree: TSyntaxTree;
  Info: THoverInfo;
begin
  Text := WithCode('  if Assigned(Self) then Exit;');
  Tree := TPascalParser.Parse(Text);
  try
    Info := TLspHover.InfoAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'if Assi'), NoText);
    Assert.AreEqual('function Assigned(const P): Boolean;', Info.Declaration);
    Assert.AreEqual('System', Info.UnitName);
    Assert.AreNotEqual('', Info.Documentation);
  finally
    Tree.Free;
  end;
  Text := StringReplace(WithCode('  '), 'TArray<Integer>', 'Int64', []);
  Tree := TPascalParser.Parse(Text);
  try
    Info := TLspHover.InfoAt(FResolver, FIndex, Tree, Text, HauptFile, PositionOf(Text, 'Liste: Int'), NoText);
    Assert.IsTrue(Info.Declaration.StartsWith('type Int64'), Info.Declaration);
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSystemIntrinsicsTests);

end.
