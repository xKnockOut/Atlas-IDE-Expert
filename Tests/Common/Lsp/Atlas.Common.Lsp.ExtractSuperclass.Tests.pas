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
  BasisFile = 'C:\P\Basis.pas';
  AusgabeFile = 'C:\P\Ausgabe.pas';
  NewFile = 'C:\P\ExportBase.pas';
  ProgramFile = 'C:\P\Projekt.dpr';
  ProjectFile = 'C:\P\Projekt.dproj';

  UnitBasis =
    'unit Basis;'#10'interface'#10'type'#10'  TItems = class'#10'  end;'#10'implementation'#10'end.'#10;
  UnitAusgabe =
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
  TextProgram =
    'program Projekt;'#10'uses'#10'  Basis in ''Basis.pas'','#10'  Ausgabe in ''Ausgabe.pas'';'#10'begin'#10 +
    'end.'#10;
  TextProject =
    '<Project>'#10'  <ItemGroup>'#10'    <DelphiCompile Include="Projekt.dpr"/>'#10 +
    '    <DCCReference Include="Basis.pas"/>'#10'    <DCCReference Include="Ausgabe.pas"/>'#10 +
    '  </ItemGroup>'#10'</Project>'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, BasisFile) then
    Result := UnitBasis
  else if SameText(AFileName, AusgabeFile) then
    Result := UnitAusgabe
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

function Context(const AIndex: ISymbolIndex): TExtractSuperclassContext;
begin
  Result := Default(TExtractSuperclassContext);
  Result.Index := AIndex;
  Result.HasProject := True;
  Result.Project.FileName := ProjectFile;
  Result.Project.MainSource := ProgramFile;
  Result.Project.Units := [ProjectUnit('Basis', BasisFile), ProjectUnit('Ausgabe', AusgabeFile)];
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
  Result.AddPair('abstract', TJSONArray.Create);
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
  const AContext: TExtractSuperclassContext): TJSONObject;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(AIndex, nil);
  try
    Result := TLspExtractSuperclass.Execute(Resolver, Tree, AusgabeFile, AText, TTextPosition.Create(5, 2), ARequest,
      AContext);
  finally
    Resolver.Free;
    Tree.Free;
    ARequest.Free;
  end;
end;

procedure TLspExtractSuperclassTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAusgabe, AusgabeFile, nil));
end;

procedure TLspExtractSuperclassTests.TearDown;
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

procedure TLspExtractSuperclassTests.OffersOnClassHeader;
var
  Tree: TSyntaxTree;
  Actions: TArray<TJSONObject>;
begin
  Tree := TPascalParser.Parse(UnitAusgabe);
  try
    Actions := TLspExtractSuperclass.Actions(True, Tree, UnitAusgabe, 'file:///C:/P/Ausgabe.pas',
      TTextPosition.Create(5, 4));
    try
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('Basisklasse aus TPdfExport herauslösen …', Actions[0].GetValue('title').Value);
      Assert.AreEqual(TLspExtractSuperclass.ClientCommand,
        (Actions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      FreeAll(Actions);
    end;
    Assert.AreEqual(0, Integer(Length(TLspExtractSuperclass.Actions(False, Tree, UnitAusgabe, 'u',
      TTextPosition.Create(5, 4)))), 'abgeschaltet');
    Assert.AreEqual(0, Integer(Length(TLspExtractSuperclass.Actions(True, Tree, UnitAusgabe, 'u',
      TTextPosition.Create(7, 4)))), 'nicht auf einem Mitglied');
  finally
    Tree.Free;
  end;
end;

procedure TLspExtractSuperclassTests.PrepareUsesSettings;
var
  Tree: TSyntaxTree;
  Answer: TJSONObject;
  Candidates: TJSONArray;
  Settings: TExtractSuperclassContext;
begin
  Tree := TPascalParser.Parse(UnitAusgabe);
  Answer := nil;
  try
    Answer := TLspExtractSuperclass.Prepare(Tree, UnitAusgabe, TTextPosition.Create(5, 2), Context(FIndex));
    Assert.AreEqual('TExportBase', Answer.GetValue('name').Value);
    Assert.AreEqual('Ausgabe', Answer.GetValue('ownUnit').Value);
    Assert.AreEqual('', Answer.GetValue('unit').Value);
    Assert.AreEqual('ExportBase', (Answer.GetValue('units') as TJSONArray).Items[0].Value);
    Candidates := Answer.GetValue('candidates') as TJSONArray;
    Assert.AreEqual(3, Integer(Candidates.Count));
    Assert.AreEqual('field', (Candidates.Items[0] as TJSONObject).GetValue('kind').Value);
    Assert.AreEqual('method', (Candidates.Items[2] as TJSONObject).GetValue('kind').Value);
    Assert.IsTrue(((Candidates.Items[2] as TJSONObject).GetValue('canAbstract') as TJSONBool).AsBoolean);
    Assert.IsFalse(((Candidates.Items[2] as TJSONObject).GetValue('abstract') as TJSONBool).AsBoolean);
    Assert.AreEqual(1, Integer(((Candidates.Items[2] as TJSONObject).GetValue('needs') as TJSONArray).Count));
    FreeAndNil(Answer);
    Settings := Context(FIndex);
    Settings.Target := 'newUnit';
    Settings.MethodMode := 'abstract';
    Settings.NameSuffix := 'Custom';
    Answer := TLspExtractSuperclass.Prepare(Tree, UnitAusgabe, TTextPosition.Create(5, 2), Settings);
    Assert.AreEqual('TCustomExport', Answer.GetValue('name').Value);
    Assert.AreEqual('CustomExport', Answer.GetValue('unit').Value);
    Candidates := Answer.GetValue('candidates') as TJSONArray;
    Assert.IsTrue(((Candidates.Items[2] as TJSONObject).GetValue('abstract') as TJSONBool).AsBoolean);
  finally
    Answer.Free;
    Tree.Free;
  end;
end;

procedure TLspExtractSuperclassTests.SameUnit;
var
  Answer: TJSONObject;
  Text: string;
begin
  // FTitle (1) und Run (2) wandern.
  Answer := Run(FIndex, UnitAusgabe, Request('TExportBase', '', [1, 2]), Context(FIndex));
  try
    Text := After(Answer, AusgabeFile);
    Assert.IsTrue(ContainsStr(Text, '  TExportBase = class'#10'  private'#10'    FTitle: string;'#10 +
      '  public'#10'    procedure Run;'#10'  end;'), Text);
    Assert.IsTrue(ContainsStr(Text, 'TPdfExport = class(TExportBase)'), Text);
    Assert.IsTrue(ContainsStr(Text, 'procedure TExportBase.Run;'), Text);
    Assert.IsTrue(SameText(AusgabeFile, TDocumentUris.ToPath(Answer.GetValue('file').Value)));
    Assert.AreEqual(2, (Answer.GetValue('moved') as TJSONNumber).AsInt);
    Assert.IsTrue(ContainsStr(((Answer.GetValue('edit') as TJSONObject).GetValue('changeAnnotations') as
      TJSONObject).ToJSON, 'needsConfirmation'));
  finally
    Answer.Free;
  end;
end;

procedure TLspExtractSuperclassTests.NewUnitJoinsProject;
var
  Answer: TJSONObject;
  Created, Text: string;
begin
  Answer := Run(FIndex, UnitAusgabe, Request('TExportBase', 'ExportBase', [0, 1, 2]), Context(FIndex));
  try
    Assert.IsTrue(SameText(NewFile, TDocumentUris.ToPath(Answer.GetValue('file').Value)));
    Created := After(Answer, NewFile);
    Assert.IsTrue(ContainsStr(Created, 'unit ExportBase;'), Created);
    Assert.IsTrue(ContainsStr(Created, 'TExportBase = class'), Created);
    Assert.IsTrue(ContainsStr(Created, 'Basis'), Created);
    Assert.IsTrue(ContainsStr(Created, 'procedure TExportBase.Run;'), Created);
    Text := After(Answer, AusgabeFile);
    Assert.IsFalse(ContainsStr(Text, 'TExportBase = class'), Text);
    Assert.IsTrue(ContainsStr(Text, 'ExportBase'), Text);
    Assert.IsTrue(ContainsStr(Text, 'TPdfExport = class(TExportBase)'), Text);
    // Private Felder, die die Klasse unten weiter braucht, gibt es nicht mehr: nichts gehoben.
    Assert.IsTrue(ContainsStr(After(Answer, ProgramFile), 'ExportBase in ''ExportBase.pas'''));
    Assert.IsTrue(ContainsStr(After(Answer, ProjectFile), '<DCCReference Include="ExportBase.pas"/>'));
  finally
    Answer.Free;
  end;
end;

procedure TLspExtractSuperclassTests.RefusesCircularReference;
var
  Text: string;
  Index: ISymbolIndex;
begin
  // Das Feld hat einen Typ aus der Unit der Klasse selbst.
  Text := StringReplace(UnitAusgabe, 'type'#10, 'type'#10'  TMode = (mA, mB);'#10, []);
  Text := StringReplace(Text, '    FTitle: string;', '    FTitle: TMode;', []);
  Text := StringReplace(Text, '  FTitle := ''x'';', '  FTitle := mA;', []);
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  Index.AddUnit(TIndexExtractor.ExtractText(Text, AusgabeFile, nil));
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
      Resolver: TNameResolver;
      Body: TJSONObject;
    begin
      Tree := TPascalParser.Parse(Text);
      Resolver := TNameResolver.Create(Index, nil);
      Body := Request('TExportBase', 'ExportBase', [1]);
      try
        TLspExtractSuperclass.Execute(Resolver, Tree, AusgabeFile, Text, TTextPosition.Create(6, 2), Body,
          Context(Index)).Free;
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
