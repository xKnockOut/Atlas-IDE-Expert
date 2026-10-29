unit Atlas.Common.Lsp.ExtractInterface.Tests;

// Tests für „Interface aus Klasse herauslösen“ über das Protokoll (#664):
// Angebot der Code-Aktion, Antwort auf prepare, WorkspaceEdit in derselben
// Unit (neue, gültige GUID), in einer vorhandenen Unit (uses der Typen) und
// in einer neuen Unit (Projekt), Abbruch bei Kreisverweis.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspExtractInterfaceTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffersOnClassHeader;
    [Test]
    procedure PrepareListsCandidates;
    [Test]
    procedure SameUnitWithNewGuid;
    [Test]
    procedure ExistingUnitGetsUses;
    [Test]
    procedure NewUnitJoinsProject;
    [Test]
    procedure RefusesCircularReference;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ExtractInterface;

const
  BasisFile = 'C:\P\Basis.pas';
  KundenFile = 'C:\P\Kunden.pas';
  ZielFile = 'C:\P\Ziel.pas';
  ProgramFile = 'C:\P\Projekt.dpr';
  ProjectFile = 'C:\P\Projekt.dproj';

  UnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10'implementation'#10'end.'#10;
  UnitKunden =
    'unit Kunden;'#10 +                                       // 0
    'interface'#10 +                                          // 1
    'uses'#10 +                                               // 2
    '  Basis;'#10 +                                           // 3
    'type'#10 +                                               // 4
    '  TCustomer = class'#10 +                                // 5
    '  public'#10 +                                           // 6
    '    function Items: TItems;'#10 +                        // 7
    '    procedure Clear;'#10 +                               // 8
    '  end;'#10 +                                             // 9
    'implementation'#10 +                                     // 10
    'function TCustomer.Items: TItems;'#10 +
    'begin'#10 +
    '  Result := nil;'#10 +
    'end;'#10 +
    'procedure TCustomer.Clear;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.'#10;
  UnitZiel =
    'unit Ziel;'#10'interface'#10'uses'#10'  System.Classes;'#10'implementation'#10'end.'#10;
  TextProgram =
    'program Projekt;'#10'uses'#10'  Basis in ''Basis.pas'','#10'  Kunden in ''Kunden.pas'','#10 +
    '  Ziel in ''Ziel.pas'';'#10'begin'#10'end.'#10;
  TextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Basis.pas"/>'#10'    <DCCReference Include="Kunden.pas"/>'#10 +
    '    <DCCReference Include="Ziel.pas"/>'#10'  </ItemGroup>'#10'</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, BasisFile) then
    Result := UnitBasis
  else if SameText(AFileName, KundenFile) then
    Result := UnitKunden
  else if SameText(AFileName, ZielFile) then
    Result := UnitZiel
  else if SameText(AFileName, ProgramFile) then
    Result := TextProgram
  else if SameText(AFileName, ProjectFile) then
    Result := TextProject
  else
    Result := '';
end;

function ProjectUnit(const AName, AFileName: string): TProjectUnit;
begin
  Result.Name := AName;
  Result.FileName := AFileName;
end;

function Context(const AIndex: ISymbolIndex): TExtractInterfaceContext;
begin
  Result := Default(TExtractInterfaceContext);
  Result.Index := AIndex;
  Result.HasProject := True;
  Result.Project.FileName := ProjectFile;
  Result.Project.MainSource := ProgramFile;
  Result.Project.Units := [ProjectUnit('Basis', BasisFile), ProjectUnit('Kunden', KundenFile),
    ProjectUnit('Ziel', ZielFile)];
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := TextOf(AFileName) <> '';
    end;
  Result.Guid := '{11111111-2222-3333-4444-555555555555}';
end;

function Request(const AName, AUnit: string; const AMembers: array of Integer): TJSONObject;
var
  Members: TJSONArray;
  Id: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('unit', AUnit);
  Members := TJSONArray.Create;
  for Id in AMembers do
    Members.AddElement(TJSONNumber.Create(Id));
  Result.AddPair('members', Members);
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer; neue Dateien aus ihrem Inhalt.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  Item, Edit: TJSONValue;
  Document, Range: TJSONObject;
  Edits: TArray<TTextEdit>;
  Uri: string;
begin
  Result := TextOf(AFileName);
  for Item in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    Document := TJSONObject(Item);
    if Document.GetValue('textDocument') = nil then
      Continue;
    Uri := (Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(Uri), AFileName) then
      Continue;
    Edits := nil;
    for Edit in Document.GetValue('edits') as TJSONArray do
    begin
      Range := TJSONObject(Edit).GetValue('range') as TJSONObject;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
        TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Edit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, Edits);
  end;
end;

function Run(const AIndex: ISymbolIndex; const AText: string; ARequest: TJSONObject;
  const AContext: TExtractInterfaceContext): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspExtractInterface.Execute(Resolver, Tree, KundenFile, AText, TTextPosition.Create(5, 4), ARequest,
      AContext);
  finally
    Resolver.Free;
    Tree.Free;
    ARequest.Free;
  end;
end;

procedure TLspExtractInterfaceTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitKunden, KundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitZiel, ZielFile, nil));
end;

procedure TLspExtractInterfaceTests.TearDown;
begin
  FIndex := nil;
end;

procedure FreeAll(const AItems: TArray<TJSONObject>);
var
  Item: TJSONObject;
begin
  for Item in AItems do
    Item.Free;
end;

procedure TLspExtractInterfaceTests.OffersOnClassHeader;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  try
    Actions := TLspExtractInterface.Actions(True, Tree, UnitKunden, 'file:///C:/P/Kunden.pas',
      TTextPosition.Create(5, 4));
    try
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('Interface aus TCustomer herauslösen …', Actions[0].GetValue('title').Value);
      Assert.AreEqual(TLspExtractInterface.ClientCommand,
        (Actions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(Actions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspExtractInterface.Actions(False, Tree, UnitKunden, 'u',
      TTextPosition.Create(5, 4)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspExtractInterface.Actions(True, Tree, UnitKunden, 'u',
      TTextPosition.Create(7, 4)))), 'nicht auf einem Mitglied');
  finally
    Tree.Free;
  end;
end;

procedure TLspExtractInterfaceTests.PrepareListsCandidates;
var
  Tree: TSyntaxTree;
  Answer: TJSONObject;
  Candidates: TJSONArray;
begin
  Tree := TPascalParser.Parse(UnitKunden);
  Answer := nil;
  try
    Answer := TLspExtractInterface.Prepare(Tree, UnitKunden, TTextPosition.Create(5, 2), Context(FIndex));
    Assert.AreEqual('ICustomer', Answer.GetValue('name').Value);
    Assert.AreEqual('TCustomer', Answer.GetValue('className').Value);
    Assert.AreEqual('Kunden', Answer.GetValue('ownUnit').Value);
    Candidates := Answer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(2, Integer(Candidates.Count));
    Assert.AreEqual('Items', (Candidates.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.AreEqual('method', (Candidates.Items[0] as TJSONObject).GetValue('kind').Value);
    Assert.AreEqual('public', (Candidates.Items[0] as TJSONObject).GetValue('visibility').Value);
    Assert.AreEqual(3, Integer((Answer.GetValue('units') as TJSONArray).Count));
  finally
    Answer.Free;
    Tree.Free;
  end;
end;

procedure TLspExtractInterfaceTests.SameUnitWithNewGuid;
var
  Answer: TJSONObject;
  Text, Guid1, Guid2: string;
  Fresh: TExtractInterfaceContext;
  Parsed: TGUID;
begin
  Answer := Run(FIndex, UnitKunden, Request('ICustomer', '', [0, 1]), Context(FIndex));
  try
    Text := After(Answer, KundenFile);
    Assert.IsTrue(Text.Contains('  ICustomer = interface'#10'    [''{11111111-2222-3333-4444-555555555555}'']'#10 +
      '    function Items: TItems;'#10'    procedure Clear;'#10'  end;'#10#10 +
      '  TCustomer = class(TInterfacedObject, ICustomer)'#10), Text);
    Assert.IsNotNull((Answer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations'));
  finally
    Answer.Free;
  end;
  // Ohne vorgegebene GUID: jedes Mal eine neue, gültige.
  Fresh := Context(FIndex);
  Fresh.Guid := '';
  Answer := Run(FIndex, UnitKunden, Request('ICustomer', 'Kunden', [1]), Fresh);
  try
    Text := After(Answer, KundenFile);
    Guid1 := Copy(Text, Pos('[''', Text) + 2, 38);
  finally
    Answer.Free;
  end;
  Answer := Run(FIndex, UnitKunden, Request('ICustomer', '', [1]), Fresh);
  try
    Text := After(Answer, KundenFile);
    Guid2 := Copy(Text, Pos('[''', Text) + 2, 38);
  finally
    Answer.Free;
  end;
  Parsed := StringToGUID(Guid1);
  Assert.AreEqual(Guid1, GUIDToString(Parsed));
  Assert.AreNotEqual(Guid1, Guid2);
end;

procedure TLspExtractInterfaceTests.ExistingUnitGetsUses;
var
  Answer: TJSONObject;
  Text: string;
begin
  Answer := Run(FIndex, UnitKunden, Request('ICustomer', 'Ziel', [0, 1]), Context(FIndex));
  try
    Text := After(Answer, ZielFile);
    Assert.IsTrue(Text.Contains('uses'#10'  System.Classes,'#10'  Basis;'), Text);
    Assert.IsTrue(Text.Contains('type'#10'  ICustomer = interface'#10), Text);
    Assert.IsTrue(Text.Contains('  end;'#10#10'implementation'), Text);
    Text := After(Answer, KundenFile);
    Assert.IsTrue(Text.Contains('  Basis,'#10'  Ziel;'), Text);
    Assert.IsFalse(Text.Contains('= interface'), Text);
    Assert.AreEqual(TDocumentUris.FromPath(ZielFile), Answer.GetValue('file').Value);
  finally
    Answer.Free;
  end;
end;

procedure TLspExtractInterfaceTests.NewUnitJoinsProject;
var
  Answer: TJSONObject;
  Changes: TJSONArray;
  Created: string;
begin
  Answer := Run(FIndex, UnitKunden, Request('ICustomer', 'KundenIntf', [0]), Context(FIndex));
  try
    Changes := (Answer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual('create', (Changes.Items[0] as TJSONObject).GetValue('kind').Value);
    Created := ((Changes.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Items[0].GetValue<string>(
      'newText');
    Assert.IsTrue(Created.StartsWith('unit KundenIntf;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'type'#10 +
      '  ICustomer = interface'#10), Created);
    Assert.IsTrue(After(Answer, ProgramFile).Contains('KundenIntf in ''KundenIntf.pas'''), After(Answer, ProgramFile));
    Assert.IsTrue(After(Answer, ProjectFile).Contains('<DCCReference Include="KundenIntf.pas"/>'),
      After(Answer, ProjectFile));
    Assert.IsTrue(After(Answer, KundenFile).Contains('  KundenIntf;'), After(Answer, KundenFile));
  finally
    Answer.Free;
  end;
end;

procedure TLspExtractInterfaceTests.RefusesCircularReference;
var
  Text: string;
  Index: ISymbolIndex;
begin
  // Clear liefert jetzt TCustomer aus der eigenen Unit.
  Text := StringReplace(UnitKunden, 'procedure Clear;', 'function Clone: TCustomer;', []);
  Text := StringReplace(Text, 'procedure TCustomer.Clear;', 'function TCustomer.Clone: TCustomer;', []);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(Text, KundenFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(UnitZiel, ZielFile, nil));
  Assert.WillRaise(
    procedure
    begin
      Run(Index, Text, Request('ICustomer', 'Ziel', [1]), Context(Index)).Free;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspExtractInterfaceTests);

end.
