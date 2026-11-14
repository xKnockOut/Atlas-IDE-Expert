unit Atlas.Common.Lsp.ExtractSuperclass.Tests;

// Tests für „Basisklasse herauslösen“ über das Protokoll (#713): Angebot der
// Code-Aktion, Antwort auf prepare (Vorschlag, Vorgaben aus den
// Einstellungen), WorkspaceEdit in derselben Unit und in einer neuen Unit
// (über „Klasse verschieben“, mit Projekteintrag), Abbruch bei Kreisverweis.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspExtractSuperclassTests = class
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
    procedure PrepareUsesSettings;
    [Test]
    procedure SameUnit;
    [Test]
    procedure NewUnitJoinsProject;
    [Test]
    procedure RefusesCircularReference;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
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
  Atlas.Common.Lsp.ExtractSuperclass;

const
  cBasisFile = 'C:\P\Basis.pas';
  cAusgabeFile = 'C:\P\Ausgabe.pas';
  cNewFile = 'C:\P\ExportBase.pas';
  cProgramFile = 'C:\P\Projekt.dpr';
  cProjectFile = 'C:\P\Projekt.dproj';

  cUnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10'implementation'#10'end.'#10;
  cUnitAusgabe =
    'unit Ausgabe;'#10 +                                      // 0
    'interface'#10 +                                          // 1
    'uses'#10 +                                               // 2
    '  Basis;'#10 +                                           // 3
    'type'#10 +                                               // 4
    '  TPdfExport = class'#10 +                               // 5
    '  private'#10 +                                          // 6
    '    FItems: TItems;'#10 +                                // 7
    '    FTitle: string;'#10 +                                // 8
    '  public'#10 +                                           // 9
    '    procedure Run;'#10 +                                 // 10
    '  end;'#10 +                                             // 11
    'implementation'#10 +                                     // 12
    #10 +
    'procedure TPdfExport.Run;'#10 +
    'begin'#10 +
    '  FTitle := ''x'';'#10 +
    'end;'#10 +
    #10 +
    'end.'#10;
  cTextProgram =
    'program Projekt;'#10'uses'#10'  Basis in ''Basis.pas'','#10'  Ausgabe in ''Ausgabe.pas'';'#10'begin'#10 +
    'end.'#10;
  cTextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Basis.pas"/>'#10'    <DCCReference Include="Ausgabe.pas"/>'#10 +
    '  </ItemGroup>'#10'</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, cBasisFile) then
  begin
    Result := cUnitBasis;
  end
  else if SameText(AFileName, cAusgabeFile) then
  begin
    Result := cUnitAusgabe;
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

function Context(const AIndex: ISymbolIndex): TExtractSuperclassContext;
begin
  Result := Default(TExtractSuperclassContext);
  Result.Index := AIndex;
  Result.HasProject := True;
  Result.Project.FileName := cProjectFile;
  Result.Project.MainSource := cProgramFile;
  Result.Project.Units := [ProjectUnit('Basis', cBasisFile), ProjectUnit('Ausgabe', cAusgabeFile)];
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
  Result.Target := 'sameUnit';
  Result.NameSuffix := 'Base';
  Result.MethodMode := 'move';
  Result.RaiseVisibility := 'protected';
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
  Result.AddPair('abstract', TJSONArray.Create);
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

/// <summary>AContext mit dem Auflöser AResolver für Execute.</summary>
function WithResolver(const AContext: TExtractSuperclassContext;
  AResolver: TNameResolver): TExtractSuperclassContext;
begin
  Result := AContext;
  Result.Resolver := AResolver;
end;

function Run(const AIndex: ISymbolIndex; const AText: string; ARequest: TJSONObject;
  const AContext: TExtractSuperclassContext): TJSONObject;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(AText);
  mResolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspExtractSuperclass.Execute(mTree, cAusgabeFile, AText, TTextPosition.Create(5, 2), ARequest,
      WithResolver(AContext, mResolver));
  finally
    mResolver.Free;
    mTree.Free;
    ARequest.Free;
  end;
end;

procedure TLspExtractSuperclassTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitAusgabe, cAusgabeFile, nil));
end;

procedure TLspExtractSuperclassTests.TearDown;
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

procedure TLspExtractSuperclassTests.OffersOnClassHeader;
var
  mTree: TSyntaxTree;
  mActions: TArray<TJSONObject>;
begin
  mTree := TPascalParser.Parse(cUnitAusgabe);
  try
    mActions := TLspExtractSuperclass.Actions(True, mTree, cUnitAusgabe, 'file:///C:/P/Ausgabe.pas',
      TTextPosition.Create(5, 4));
    try
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('Basisklasse aus TPdfExport herauslösen …', mActions[0].GetValue('title').Value);
      Assert.AreEqual(TLspExtractSuperclass.cClientCommand,
        (mActions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(mActions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspExtractSuperclass.Actions(False, mTree, cUnitAusgabe, 'u',
      TTextPosition.Create(5, 4)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspExtractSuperclass.Actions(True, mTree, cUnitAusgabe, 'u',
      TTextPosition.Create(7, 4)))), 'nicht auf einem Mitglied');
  finally
    mTree.Free;
  end;
end;

procedure TLspExtractSuperclassTests.PrepareUsesSettings;
var
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
  mCandidates: TJSONArray;
  mSettings: TExtractSuperclassContext;
begin
  mTree := TPascalParser.Parse(cUnitAusgabe);
  mAnswer := nil;
  try
    mAnswer := TLspExtractSuperclass.Prepare(mTree, cUnitAusgabe, TTextPosition.Create(5, 2), Context(FIndex));
    Assert.AreEqual('TExportBase', mAnswer.GetValue('name').Value);
    Assert.AreEqual('Ausgabe', mAnswer.GetValue('ownUnit').Value);
    Assert.AreEqual('', mAnswer.GetValue('unit').Value);
    Assert.AreEqual('ExportBase', (mAnswer.GetValue('units') as TJSONArray).Items[0].Value);
    mCandidates := mAnswer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(3, Integer(mCandidates.Count));
    Assert.AreEqual('field', (mCandidates.Items[0] as TJSONObject).GetValue('kind').Value);
    Assert.AreEqual('method', (mCandidates.Items[2] as TJSONObject).GetValue('kind').Value);
    Assert.IsTrue(((mCandidates.Items[2] as TJSONObject).GetValue('canAbstract') as TJSONBool).AsBoolean);
    Assert.IsFalse(((mCandidates.Items[2] as TJSONObject).GetValue('abstract') as TJSONBool).AsBoolean);
    Assert.AreEqual(1, Integer(((mCandidates.Items[2] as TJSONObject).GetValue('needs') as TJSONArray).Count));
    FreeAndNil(mAnswer);
    mSettings := Context(FIndex);
    mSettings.Target := 'newUnit';
    mSettings.MethodMode := 'abstract';
    mSettings.NameSuffix := 'Custom';
    mAnswer := TLspExtractSuperclass.Prepare(mTree, cUnitAusgabe, TTextPosition.Create(5, 2), mSettings);
    Assert.AreEqual('TCustomExport', mAnswer.GetValue('name').Value);
    Assert.AreEqual('CustomExport', mAnswer.GetValue('unit').Value);
    mCandidates := mAnswer.GetValue('candidates') as TJSONArray;
    Assert.IsTrue(((mCandidates.Items[2] as TJSONObject).GetValue('abstract') as TJSONBool).AsBoolean);
  finally
    mAnswer.Free;
    mTree.Free;
  end;
end;

procedure TLspExtractSuperclassTests.SameUnit;
var
  mAnswer: TJSONObject;
  mText: string;
begin
  // FTitle (1) und Run (2) wandern.
  mAnswer := Run(FIndex, cUnitAusgabe, Request('TExportBase', '', [1, 2]), Context(FIndex));
  try
    mText := After(mAnswer, cAusgabeFile);
    Assert.IsTrue(ContainsStr(mText, '  TExportBase = class'#10'  private'#10'    FTitle: string;'#10 +
      '  public'#10'    procedure Run;'#10'  end;'), mText);
    Assert.IsTrue(ContainsStr(mText, 'TPdfExport = class(TExportBase)'), mText);
    Assert.IsTrue(ContainsStr(mText, 'procedure TExportBase.Run;'), mText);
    Assert.IsTrue(SameText(cAusgabeFile, TDocumentUris.ToPath(mAnswer.GetValue('file').Value)));
    Assert.AreEqual(2, (mAnswer.GetValue('moved') as TJSONNumber).AsInt);
    Assert.IsTrue(ContainsStr(((mAnswer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations') as
      TJSONObject).ToJSON, 'needsConfirmation'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExtractSuperclassTests.NewUnitJoinsProject;
var
  mAnswer: TJSONObject;
  mCreated, mText: string;
begin
  mAnswer := Run(FIndex, cUnitAusgabe, Request('TExportBase', 'ExportBase', [0, 1, 2]), Context(FIndex));
  try
    Assert.IsTrue(SameText(cNewFile, TDocumentUris.ToPath(mAnswer.GetValue('file').Value)));
    mCreated := After(mAnswer, cNewFile);
    Assert.IsTrue(ContainsStr(mCreated, 'unit ExportBase;'), mCreated);
    Assert.IsTrue(ContainsStr(mCreated, 'TExportBase = class'), mCreated);
    Assert.IsTrue(ContainsStr(mCreated, 'Basis'), mCreated);
    Assert.IsTrue(ContainsStr(mCreated, 'procedure TExportBase.Run;'), mCreated);
    mText := After(mAnswer, cAusgabeFile);
    Assert.IsFalse(ContainsStr(mText, 'TExportBase = class'), mText);
    Assert.IsTrue(ContainsStr(mText, 'ExportBase'), mText);
    Assert.IsTrue(ContainsStr(mText, 'TPdfExport = class(TExportBase)'), mText);
    // Private Felder, die die Klasse unten weiter braucht, gibt es nicht mehr: nichts gehoben.
    Assert.IsTrue(ContainsStr(After(mAnswer, cProgramFile), 'ExportBase in ''ExportBase.pas'''));
    Assert.IsTrue(ContainsStr(After(mAnswer, cProjectFile), '<DCCReference Include="ExportBase.pas"/>'));
  finally
    mAnswer.Free;
  end;
end;

procedure TLspExtractSuperclassTests.RefusesCircularReference;
var
  mText: string;
  mIndex: ISymbolIndex;
begin
  // Das Feld hat einen Typ aus der Unit der Klasse selbst.
  mText := StringReplace(cUnitAusgabe, 'type'#10, 'type'#10'  TMode = (mA, mB);'#10, []);
  mText := StringReplace(mText, '    FTitle: string;', '    FTitle: TMode;', []);
  mText := StringReplace(mText, '  FTitle := ''x'';', '  FTitle := mA;', []);
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(mText, cAusgabeFile, nil));
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
      Resolver: TNameResolver;
      Body: TJSONObject;
    begin
      Tree := TPascalParser.Parse(mText);
      Resolver := TNameResolver.Create(mIndex, nil);
      Body := Request('TExportBase', 'ExportBase', [1]);
      try
        TLspExtractSuperclass.Execute(Tree, cAusgabeFile, mText, TTextPosition.Create(6, 2), Body,
          WithResolver(Context(mIndex), Resolver)).Free;
      finally
        Body.Free;
        Resolver.Free;
        Tree.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspExtractSuperclassTests);

end.
