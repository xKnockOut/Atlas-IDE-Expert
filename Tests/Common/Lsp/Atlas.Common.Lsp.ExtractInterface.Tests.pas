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
  cBasisFile = 'C:\P\Basis.pas';
  cKundenFile = 'C:\P\Kunden.pas';
  cZielFile = 'C:\P\Ziel.pas';
  cProgramFile = 'C:\P\Projekt.dpr';
  cProjectFile = 'C:\P\Projekt.dproj';

  cUnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10'implementation'#10'end.'#10;
  cUnitKunden =
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
  cUnitZiel =
    'unit Ziel;'#10'interface'#10'uses'#10'  System.Classes;'#10'implementation'#10'end.'#10;
  cTextProgram =
    'program Projekt;'#10'uses'#10'  Basis in ''Basis.pas'','#10'  Kunden in ''Kunden.pas'','#10 +
    '  Ziel in ''Ziel.pas'';'#10'begin'#10'end.'#10;
  cTextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Basis.pas"/>'#10'    <DCCReference Include="Kunden.pas"/>'#10 +
    '    <DCCReference Include="Ziel.pas"/>'#10'  </ItemGroup>'#10'</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, cBasisFile) then
  begin
    Result := cUnitBasis;
  end
  else if SameText(AFileName, cKundenFile) then
  begin
    Result := cUnitKunden;
  end
  else if SameText(AFileName, cZielFile) then
  begin
    Result := cUnitZiel;
  end
  else if SameText(AFileName, cProgramFile) then
  begin
    Result := cTextProgram;
  end
  else if SameText(AFileName, cProjectFile) then
  begin
    Result := cTextProject;
  end
  else
  begin
    Result := '';
  end;
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
  Result.Project.FileName := cProjectFile;
  Result.Project.MainSource := cProgramFile;
  Result.Project.Units := [ProjectUnit('Basis', cBasisFile), ProjectUnit('Kunden', cKundenFile),
    ProjectUnit('Ziel', cZielFile)];
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
  mMembers: TJSONArray;
  mId: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('unit', AUnit);
  mMembers := TJSONArray.Create;
  for mId in AMembers do
  begin
    mMembers.AddElement(TJSONNumber.Create(mId));
  end;
  Result.AddPair('members', mMembers);
end;

/// <summary>Text von AFileName nach dem WorkspaceEdit in AAnswer; neue Dateien aus ihrem Inhalt.</summary>
function After(AAnswer: TJSONObject; const AFileName: string): string;
var
  mItem, mEdit: TJSONValue;
  mDocument, mRange: TJSONObject;
  mEdits: TArray<TTextEdit>;
  mUri: string;
begin
  Result := TextOf(AFileName);
  for mItem in (AAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
  begin
    mDocument := TJSONObject(mItem);
    if mDocument.GetValue('textDocument') = nil then
    begin
      Continue;
    end;
    mUri := (mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value;
    if not SameText(TDocumentUris.ToPath(mUri), AFileName) then
    begin
      Continue;
    end;
    mEdits := nil;
    for mEdit in mDocument.GetValue('edits') as TJSONArray do
    begin
      mRange := TJSONObject(mEdit).GetValue('range') as TJSONObject;
      mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
        TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mEdit).GetValue('newText').Value)];
    end;
    Result := TTextChanges.Apply(Result, mEdits);
  end;
end;

function Run(const AIndex: ISymbolIndex; const AText: string; ARequest: TJSONObject;
  const AContext: TExtractInterfaceContext): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mContext: TExtractInterfaceContext;
begin
  mTree := TPascalParser.Parse(AText);
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    mContext := AContext;
    mContext.Resolver := mResolver;
    Result := TLspExtractInterface.Execute(mTree, cKundenFile, AText, TTextPosition.Create(5, 4), ARequest, mContext);
  finally
    mResolver.Free;
    mTree.Free;
    ARequest.Free;
  end;
end;

procedure TLspExtractInterfaceTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitKunden, cKundenFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitZiel, cZielFile, nil));
end;

procedure TLspExtractInterfaceTests.TearDown;
begin
  FIndex := nil;
end;

procedure FreeAll(const AItems: TArray<TJSONObject>);
var
  mItem: TJSONObject;
begin
  for mItem in AItems do
  begin
    mItem.Free;
  end;
end;

procedure TLspExtractInterfaceTests.OffersOnClassHeader;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  try
    mActions := TLspExtractInterface.Actions(True, mTree, cUnitKunden, 'file:///C:/P/Kunden.pas',
      TTextPosition.Create(5, 4));
    try
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('Interface aus TCustomer herauslösen …', mActions[0].GetValue('title').Value);
      Assert.AreEqual(TLspExtractInterface.cClientCommand,
        (mActions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(mActions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspExtractInterface.Actions(False, mTree, cUnitKunden, 'u',
      TTextPosition.Create(5, 4)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspExtractInterface.Actions(True, mTree, cUnitKunden, 'u',
      TTextPosition.Create(7, 4)))), 'nicht auf einem Mitglied');
  finally
    mTree.Free;
  end;
end;

procedure TLspExtractInterfaceTests.PrepareListsCandidates;
var
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
  mCandidates: TJSONArray;
begin
  mTree := TPascalParser.Parse(cUnitKunden);
  mAnswer := nil;
  try
    mAnswer := TLspExtractInterface.Prepare(mTree, cUnitKunden, TTextPosition.Create(5, 2), Context(FIndex));
    Assert.AreEqual('ICustomer', mAnswer.GetValue('name').Value);
    Assert.AreEqual('TCustomer', mAnswer.GetValue('className').Value);
    Assert.AreEqual('Kunden', mAnswer.GetValue('ownUnit').Value);
    mCandidates := mAnswer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(2, Integer(mCandidates.Count));
    Assert.AreEqual('Items', (mCandidates.Items[0] as TJSONObject).GetValue('name').Value);
    Assert.AreEqual('method', (mCandidates.Items[0] as TJSONObject).GetValue('kind').Value);
    Assert.AreEqual('public', (mCandidates.Items[0] as TJSONObject).GetValue('visibility').Value);
    Assert.AreEqual(3, Integer((mAnswer.GetValue('units') as TJSONArray).Count));
  finally
    mAnswer.Free;
    mTree.Free;
  end;
end;

procedure TLspExtractInterfaceTests.SameUnitWithNewGuid;
var
  mAnswer: TJSONObject;
  mText, mGuid1, mGuid2: string;
  mFresh: TExtractInterfaceContext;
  mParsed: TGUID;
begin
  mAnswer := Run(FIndex, cUnitKunden, Request('ICustomer', '', [0, 1]), Context(FIndex));
  try
    mText := After(mAnswer, cKundenFile);
    Assert.IsTrue(mText.Contains('  ICustomer = interface'#10'    [''{11111111-2222-3333-4444-555555555555}'']'#10 +
      '    function Items: TItems;'#10'    procedure Clear;'#10'  end;'#10#10 +
      '  TCustomer = class(TInterfacedObject, ICustomer)'#10), mText);
    Assert.IsNotNull((mAnswer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations'));
  finally
    mAnswer.Free;
  end;
  // Ohne vorgegebene GUID: jedes Mal eine neue, gültige.
  mFresh := Context(FIndex);
  mFresh.Guid := '';
  mAnswer := Run(FIndex, cUnitKunden, Request('ICustomer', 'Kunden', [1]), mFresh);
  try
    mText := After(mAnswer, cKundenFile);
    mGuid1 := Copy(mText, Pos('[''', mText) + 2, 38);
  finally
    mAnswer.Free;
  end;
  mAnswer := Run(FIndex, cUnitKunden, Request('ICustomer', '', [1]), mFresh);
  try
    mText := After(mAnswer, cKundenFile);
    mGuid2 := Copy(mText, Pos('[''', mText) + 2, 38);
  finally
    mAnswer.Free;
  end;
  mParsed := StringToGUID(mGuid1);
  Assert.AreEqual(mGuid1, GUIDToString(mParsed));
  Assert.AreNotEqual(mGuid1, mGuid2);
end;

procedure TLspExtractInterfaceTests.ExistingUnitGetsUses;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  mAnswer := Run(FIndex, cUnitKunden, Request('ICustomer', 'Ziel', [0, 1]), Context(FIndex));
  try
    mText := After(mAnswer, cZielFile);
    Assert.IsTrue(mText.Contains('uses'#10'  System.Classes,'#10'  Basis;'), mText);
    Assert.IsTrue(mText.Contains('type'#10'  ICustomer = interface'#10), mText);
    Assert.IsTrue(mText.Contains('  end;'#10#10'implementation'), mText);
    mText := After(mAnswer, cKundenFile);
    Assert.IsTrue(mText.Contains('  Basis,'#10'  Ziel;'), mText);
    Assert.IsFalse(mText.Contains('= interface'), mText);
    Assert.AreEqual(TDocumentUris.FromPath(cZielFile), mAnswer.GetValue('file').Value);
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExtractInterfaceTests.NewUnitJoinsProject;
var
  mAnswer: TJSONObject;
  mChanges: TJSONArray;
  mCreated: string;
begin
  mAnswer := Run(FIndex, cUnitKunden, Request('ICustomer', 'KundenIntf', [0]), Context(FIndex));
  try
    mChanges := (mAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray;
    Assert.AreEqual('create', (mChanges.Items[0] as TJSONObject).GetValue('kind').Value);
    mCreated := ((mChanges.Items[1] as TJSONObject).GetValue('edits') as TJSONArray).Items[0].GetValue<string>(
      'newText');
    Assert.IsTrue(mCreated.StartsWith('unit KundenIntf;'#10#10'interface'#10#10'uses'#10'  Basis;'#10#10'type'#10 +
      '  ICustomer = interface'#10), mCreated);
    Assert.IsTrue(After(mAnswer, cProgramFile).Contains('KundenIntf in ''KundenIntf.pas'''), After(mAnswer, cProgramFile));
    Assert.IsTrue(After(mAnswer, cProjectFile).Contains('<DCCReference Include="KundenIntf.pas"/>'),
      After(mAnswer, cProjectFile));
    Assert.IsTrue(After(mAnswer, cKundenFile).Contains('  KundenIntf;'), After(mAnswer, cKundenFile));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExtractInterfaceTests.RefusesCircularReference;
var
  mText: string;
  mIndex: ISymbolIndex;
begin
  // Clear liefert jetzt TCustomer aus der eigenen Unit.
  mText := StringReplace(cUnitKunden, 'procedure Clear;', 'function Clone: TCustomer;', []);
  mText := StringReplace(mText, 'procedure TCustomer.Clear;', 'function TCustomer.Clone: TCustomer;', []);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(mText, cKundenFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitZiel, cZielFile, nil));
  Assert.WillRaise(
    procedure
    begin
      Run(mIndex, mText, Request('ICustomer', 'Ziel', [1]), Context(mIndex)).Free;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspExtractInterfaceTests);

end.
