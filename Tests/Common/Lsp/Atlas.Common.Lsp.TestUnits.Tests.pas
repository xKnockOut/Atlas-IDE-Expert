unit Atlas.Common.Lsp.TestUnits.Tests;

// Tests für Code-Aktion und Befehl rund um Testunits (#274, #189): Gegenstück
// finden, Gerüst samt Einträgen in .dpr und .dproj, Wechsel in beide Richtungen.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.TestUnits;

type
  [TestFixture]
  TLspTestUnitsTests = class
  private
    FStore: IDocumentStore;
    FFiles: TDictionary<string, string>;
    FUnits: TDictionary<string, string>;
    FTestUnits: TLspTestUnits;
    FTestProgram: string;
    function Context: TTestUnitContext;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MissingTestUnitCanBeCreated;
    [Test]
    procedure CreateEditAddsFileProgramAndProject;
    [Test]
    procedure CodeActionOnClassCreates;
    [Test]
    procedure DraftActionCreatesTestUnitWithDraft;
    [Test]
    procedure DraftActionAddsToExistingTestUnit;
    [Test]
    procedure SwitchesBothWays;
    [Test]
    procedure WithoutTestProjectNoCreate;
    [Test]
    procedure ProgramIsNoUnit;
    [Test]
    procedure CommandAnswers;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore;

const
  KundenFile = 'C:\P\Quelle\Kunden.pas';
  TestsDpr = 'C:\P\Tests\Tests.dpr';
  TestsDproj = 'C:\P\Tests\Tests.dproj';
  KundenText =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKunde = class'#10 +
    '  public'#10 +
    '    procedure Speichern;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKunde.Speichern;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  DprText =
    'program Tests;'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'begin'#13#10 +
    'end.';
  DprojText =
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="Tests.dpr"/>'#13#10 +
    '        <DCCReference Include="..\Quelle\Alt.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>';
  KundenTestsText =
    'unit Kunden.Tests;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework, Kunden;'#10 +
    'implementation'#10 +
    'end.';

procedure TLspTestUnitsTests.WarmUpFirstUse;
begin
  Setup;
  try
    MissingTestUnitCanBeCreated;
  finally
    TearDown;
  end;
end;

procedure TLspTestUnitsTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FUnits := TDictionary<string, string>.Create;
  FFiles.Add(TestsDpr, DprText);
  FFiles.Add(TestsDproj, DprojText);
  FUnits.Add('kunden', KundenFile);
  FTestProgram := TestsDpr;
  FStore.Open(TDocumentUris.FromPath(KundenFile), 'pascal', 1, KundenText);
  FTestUnits := TLspTestUnits.Create(FStore,
    function(const AUri: string; out AContext: TTestUnitContext): Boolean
    begin
      AContext := Context;
      Result := True;
    end);
end;

procedure TLspTestUnitsTests.TearDown;
begin
  FTestUnits.Free;
  FUnits.Free;
  FFiles.Free;
  FStore := nil;
  FTestProgram := '';
end;

function TLspTestUnitsTests.Context: TTestUnitContext;
var
  Files, Units: TDictionary<string, string>;
begin
  Files := FFiles;
  Units := FUnits;
  Result := Default(TTestUnitContext);
  Result.Settings := TTestUnitSettings.Default;
  Result.Root := 'C:\P';
  Result.TestProgram := FTestProgram;
  Result.ReadText :=
    function(const AFileName: string): string
    begin
      if not Files.TryGetValue(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := Files.ContainsKey(AFileName);
    end;
  Result.FindUnit :=
    function(const AUnitName: string): string
    begin
      if not Units.TryGetValue(LowerCase(AUnitName), Result) then
      begin
        Result := '';
      end;
    end;
end;

procedure TLspTestUnitsTests.MissingTestUnitCanBeCreated;
var
  Target: TTestUnitTarget;
begin
  Target := TLspTestUnits.Resolve(KundenFile, KundenText, 3, Context);
  Assert.AreEqual('Kunden', Target.UnitName);
  Assert.IsFalse(Target.IsTest);
  Assert.AreEqual('Kunden.Tests', Target.Counterpart);
  Assert.AreEqual('', Target.CounterpartFile);
  Assert.IsTrue(Target.CanCreate, Target.Reason);
  Assert.AreEqual('C:\P\Tests\Kunden.Tests.pas', Target.NewFile);
  Assert.AreEqual('TKunde', Target.ClassName);
  Assert.IsTrue(Target.ClassAtLine);
  Target := TLspTestUnits.Resolve(KundenFile, KundenText, 1, Context);
  Assert.AreEqual('TKunde', Target.ClassName, 'ohne Klasse an der Zeile: die erste');
  Assert.IsFalse(Target.ClassAtLine);
end;

function Find(const AChanges: TJSONArray; const AUri: string): TJSONObject;
var
  Item: TJSONValue;
  Uri: string;
begin
  Result := nil;
  for Item in AChanges do
  begin
    if TJSONObject(Item).TryGetValue<string>('textDocument.uri', Uri) and TDocumentUris.SameFile(Uri, AUri) then
    begin
      Exit(TJSONObject(Item));
    end;
  end;
end;

function FirstNewText(const AChange: TJSONObject): string;
begin
  Result := TJSONObject(AChange.GetValue<TJSONArray>('edits').Items[0]).GetValue<string>('newText');
end;

procedure TLspTestUnitsTests.CreateEditAddsFileProgramAndProject;
var
  Edit: TJSONObject;
  Changes: TJSONArray;
  NewUri, Kind: string;
  Change: TJSONObject;
begin
  Edit := TLspTestUnits.CreateEdit(TLspTestUnits.Resolve(KundenFile, KundenText, 3, Context), Context);
  try
    Changes := Edit.GetValue<TJSONArray>('documentChanges');
    Assert.AreEqual(4, Integer(Changes.Count));
    NewUri := TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas');
    Assert.IsTrue(TJSONObject(Changes.Items[0]).TryGetValue<string>('kind', Kind));
    Assert.AreEqual('create', Kind);
    Assert.IsTrue(TDocumentUris.SameFile(NewUri, TJSONObject(Changes.Items[0]).GetValue<string>('uri')));
    Change := Find(Changes, NewUri);
    Assert.IsNotNull(Change);
    Assert.IsTrue(FirstNewText(Change).StartsWith('unit Kunden.Tests;'#13#10));
    Assert.IsTrue(Pos('procedure TestSpeichern;', FirstNewText(Change)) > 0);
    Change := Find(Changes, TDocumentUris.FromPath(TestsDpr));
    Assert.IsNotNull(Change, '.dpr');
    Assert.AreEqual(','#13#10'  Kunden.Tests in ''Kunden.Tests.pas''', FirstNewText(Change));
    Change := Find(Changes, TDocumentUris.FromPath(TestsDproj));
    Assert.IsNotNull(Change, '.dproj');
    Assert.AreEqual(#13#10'        <DCCReference Include="Kunden.Tests.pas"/>', FirstNewText(Change));
  finally
    Edit.Free;
  end;
end;

procedure TLspTestUnitsTests.CodeActionOnClassCreates;
var
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
begin
  Actions := FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 4);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('DUnitX-Testunit für TKunde anlegen', Actions[0].GetValue<string>('title'));
    Assert.IsNotNull(Actions[0].GetValue('edit'));
    Assert.AreEqual(TLspTestUnits.cOpenFileCommand, Actions[0].GetValue<string>('command.command'));
  finally
    for Action in Actions do
    begin
      Action.Free;
    end;
  end;
  // Außerhalb der Klasse kein Anlegen (Code-Aktion auf einer Klasse, #274).
  Actions := FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 1);
  Assert.AreEqual(0, Integer(Length(Actions)));
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  Action: TJSONObject;
begin
  for Action in AActions do
  begin
    Action.Free;
  end;
end;

procedure TLspTestUnitsTests.DraftActionCreatesTestUnitWithDraft;
var
  Actions: TArray<TJSONObject>;
  Changes: TJSONArray;
  Text: string;
begin
  // Zeile 9: Rumpf von TKunde.Speichern. Der Entwurf ersetzt Assert.Fail im neuen Gerüst.
  Actions := FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 9);
  try
    Assert.AreEqual(2, Integer(Length(Actions)));
    Assert.AreEqual('Testfall f' + #$FC + 'r TKunde.Speichern anlegen', Actions[0].GetValue<string>('title'));
    Changes := Actions[0].GetValue<TJSONArray>('edit.documentChanges');
    Assert.AreEqual(4, Integer(Changes.Count));
    Text := FirstNewText(Find(Changes, TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas')));
    Assert.IsTrue(Pos('procedure TKundeTests.TestSpeichern;'#13#10'begin'#13#10, Text) > 0, Text);
    Assert.IsTrue(Pos('  FSubject.Speichern;', Text) > 0, Text);
    Assert.IsTrue(Pos('  FSubject := TKunde.Create;', Text) > 0, Text);
    Assert.AreEqual('DUnitX-Testunit f' + #$FC + 'r TKunde anlegen', Actions[1].GetValue<string>('title'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspTestUnitsTests.DraftActionAddsToExistingTestUnit;
const
  TestText =
    'unit Kunden.Tests;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'type'#13#10 +
    '  [TestFixture]'#13#10 +
    '  TKundeTests = class'#13#10 +
    '  public'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.'#13#10;
var
  Actions: TArray<TJSONObject>;
  Changes: TJSONArray;
  Edits: TJSONArray;
  Text: string;
  Item: TJSONValue;
begin
  FFiles.Add('C:\P\Tests\Kunden.Tests.pas', TestText);
  FUnits.Add('kunden.tests', 'C:\P\Tests\Kunden.Tests.pas');
  Actions := FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 5);
  try
    Assert.AreEqual(2, Integer(Length(Actions)), 'Entwurf und Wechsel');
    Changes := Actions[0].GetValue<TJSONArray>('edit.documentChanges');
    Assert.AreEqual(1, Integer(Changes.Count));
    Edits := TJSONObject(Changes.Items[0]).GetValue<TJSONArray>('edits');
    Text := '';
    for Item in Edits do
    begin
      Text := Text + TJSONObject(Item).GetValue<string>('newText');
    end;
    Assert.IsTrue(Pos('procedure TestSpeichern;', Text) > 0, Text);
    Assert.IsTrue(Pos('    Subject.Speichern;', Text) > 0, Text);
    Assert.IsTrue(Pos('Kunden', Text) > 0, 'uses: ' + Text);
    Assert.AreEqual('Zur Testunit Kunden.Tests wechseln', Actions[1].GetValue<string>('title'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspTestUnitsTests.SwitchesBothWays;
var
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
  Arguments: TJSONArray;
  Target: TTestUnitTarget;
begin
  FFiles.Add('C:\P\Tests\Kunden.Tests.pas', KundenTestsText);
  Actions := FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 4);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('Zur Testunit Kunden.Tests wechseln', Actions[0].GetValue<string>('title'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas'),
      Arguments.Items[0].Value));
  finally
    for Action in Actions do
    begin
      Action.Free;
    end;
  end;
  Target := TLspTestUnits.Resolve('C:\P\Tests\Kunden.Tests.pas', KundenTestsText, 0, Context);
  Assert.IsTrue(Target.IsTest);
  Assert.AreEqual('Kunden', Target.Counterpart);
  Assert.AreEqual(KundenFile, Target.CounterpartFile);
  Assert.IsFalse(Target.CanCreate);
end;

procedure TLspTestUnitsTests.WithoutTestProjectNoCreate;
var
  Target: TTestUnitTarget;
begin
  FTestProgram := '';
  Target := TLspTestUnits.Resolve(KundenFile, KundenText, 3, Context);
  Assert.IsFalse(Target.CanCreate);
  Assert.IsTrue(Pos('testUnits.project', Target.Reason) > 0, Target.Reason);
  Assert.AreEqual(0, Integer(Length(FTestUnits.Actions(TDocumentUris.FromPath(KundenFile), 3))));
end;

procedure TLspTestUnitsTests.ProgramIsNoUnit;
begin
  Assert.AreEqual('', TLspTestUnits.Resolve(TestsDpr, DprText, 0, Context).UnitName);
end;

procedure TLspTestUnitsTests.CommandAnswers;
var
  Arguments: TJSONArray;
  Answer: TJSONValue;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(TDocumentUris.FromPath(KundenFile));
    Answer := FTestUnits.Execute(Arguments);
    try
      Assert.AreEqual('Kunden', Answer.GetValue<string>('unit'));
      Assert.AreEqual('Kunden.Tests', Answer.GetValue<string>('counterpart'));
      Assert.IsTrue(Answer.GetValue<Boolean>('canCreate'));
      Assert.IsTrue(TJSONObject(Answer).GetValue('uri') is TJSONNull);
      Assert.IsNotNull(TJSONObject(Answer).GetValue('edit'));
      Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas'),
        Answer.GetValue<string>('newUri')));
    finally
      Answer.Free;
    end;
  finally
    Arguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTestUnitsTests);

end.
