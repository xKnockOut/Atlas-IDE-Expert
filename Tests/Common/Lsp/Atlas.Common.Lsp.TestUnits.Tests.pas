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
  cKundenFile = 'C:\P\Quelle\Kunden.pas';
  cTestsDpr = 'C:\P\Tests\Tests.dpr';
  cTestsDproj = 'C:\P\Tests\Tests.dproj';
  cKundenText =
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
  cDprText =
    'program Tests;'#13#10 +
    'uses'#13#10 +
    '  DUnitX.TestFramework;'#13#10 +
    'begin'#13#10 +
    'end.';
  cDprojText =
    '<Project>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="Tests.dpr"/>'#13#10 +
    '        <DCCReference Include="..\Quelle\Alt.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>';
  cKundenTestsText =
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
  FFiles.Add(cTestsDpr, cDprText);
  FFiles.Add(cTestsDproj, cDprojText);
  FUnits.Add('kunden', cKundenFile);
  FTestProgram := cTestsDpr;
  FStore.Open(TDocumentUris.FromPath(cKundenFile), 'pascal', 1, cKundenText);
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
  mFiles, mUnits: TDictionary<string, string>;
begin
  mFiles := FFiles;
  mUnits := FUnits;
  Result := Default(TTestUnitContext);
  Result.Settings := TTestUnitSettings.Default;
  Result.Root := 'C:\P';
  Result.TestProgram := FTestProgram;
  Result.ReadText :=
    function(const AFileName: string): string
    begin
      if not mFiles.TryGetValue(AFileName, Result) then
      begin
        Result := '';
      end;
    end;
  Result.Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := mFiles.ContainsKey(AFileName);
    end;
  Result.FindUnit :=
    function(const AUnitName: string): string
    begin
      if not mUnits.TryGetValue(LowerCase(AUnitName), Result) then
      begin
        Result := '';
      end;
    end;
end;

procedure TLspTestUnitsTests.MissingTestUnitCanBeCreated;
var
  mTarget: TTestUnitTarget;
begin
  mTarget := TLspTestUnits.Resolve(cKundenFile, cKundenText, 3, Context);
  Assert.AreEqual('Kunden', mTarget.UnitName);
  Assert.IsFalse(mTarget.IsTest);
  Assert.AreEqual('Kunden.Tests', mTarget.Counterpart);
  Assert.AreEqual('', mTarget.CounterpartFile);
  Assert.IsTrue(mTarget.CanCreate, mTarget.Reason);
  Assert.AreEqual('C:\P\Tests\Kunden.Tests.pas', mTarget.NewFile);
  Assert.AreEqual('TKunde', mTarget.ClassName);
  Assert.IsTrue(mTarget.ClassAtLine);
  mTarget := TLspTestUnits.Resolve(cKundenFile, cKundenText, 1, Context);
  Assert.AreEqual('TKunde', mTarget.ClassName, 'ohne Klasse an der Zeile: die erste');
  Assert.IsFalse(mTarget.ClassAtLine);
end;

function Find(const AChanges: TJSONArray; const AUri: string): TJSONObject;
var
  mItem: TJSONValue;
  mUri: string;
begin
  Result := nil;
  for mItem in AChanges do
  begin
    if TJSONObject(mItem).TryGetValue<string>('textDocument.uri', mUri) and TDocumentUris.SameFile(mUri, AUri) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

function FirstNewText(const AChange: TJSONObject): string;
begin
  Result := TJSONObject(AChange.GetValue<TJSONArray>('edits').Items[0]).GetValue<string>('newText');
end;

procedure TLspTestUnitsTests.CreateEditAddsFileProgramAndProject;
var
  mEdit: TJSONObject;
  mChanges: TJSONArray;
  mNewUri, mKind: string;
  mChange: TJSONObject;
begin
  mEdit := TLspTestUnits.CreateEdit(TLspTestUnits.Resolve(cKundenFile, cKundenText, 3, Context), Context);
  try
    mChanges := mEdit.GetValue<TJSONArray>('documentChanges');
    Assert.AreEqual(4, Integer(mChanges.Count));
    mNewUri := TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas');
    Assert.IsTrue(TJSONObject(mChanges.Items[0]).TryGetValue<string>('kind', mKind));
    Assert.AreEqual('create', mKind);
    Assert.IsTrue(TDocumentUris.SameFile(mNewUri, TJSONObject(mChanges.Items[0]).GetValue<string>('uri')));
    mChange := Find(mChanges, mNewUri);
    Assert.IsNotNull(mChange);
    Assert.IsTrue(FirstNewText(mChange).StartsWith('unit Kunden.Tests;'#13#10));
    Assert.IsTrue(Pos('procedure TestSpeichern;', FirstNewText(mChange)) > 0);
    mChange := Find(mChanges, TDocumentUris.FromPath(cTestsDpr));
    Assert.IsNotNull(mChange, '.dpr');
    Assert.AreEqual(','#13#10'  Kunden.Tests in ''Kunden.Tests.pas''', FirstNewText(mChange));
    mChange := Find(mChanges, TDocumentUris.FromPath(cTestsDproj));
    Assert.IsNotNull(mChange, '.dproj');
    Assert.AreEqual(#13#10'        <DCCReference Include="Kunden.Tests.pas"/>', FirstNewText(mChange));
  finally
    mEdit.Free;
  end;
end;

procedure TLspTestUnitsTests.CodeActionOnClassCreates;
var
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
begin
  mActions := FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 4);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('DUnitX-Testunit für TKunde anlegen', mActions[0].GetValue<string>('title'));
    Assert.IsNotNull(mActions[0].GetValue('edit'));
    Assert.AreEqual(TLspTestUnits.cOpenFileCommand, mActions[0].GetValue<string>('command.command'));
  finally
    for mAction in mActions do
    begin
      mAction.Free;
    end;
  end;
  // Außerhalb der Klasse kein Anlegen (Code-Aktion auf einer Klasse, #274).
  mActions := FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 1);
  Assert.AreEqual(0, Integer(Length(mActions)));
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  mAction: TJSONObject;
begin
  for mAction in AActions do
  begin
    mAction.Free;
  end;
end;

procedure TLspTestUnitsTests.DraftActionCreatesTestUnitWithDraft;
var
  mActions: TArray<TJSONObject>;
  mChanges: TJSONArray;
  mText: string;
begin
  // Zeile 9: Rumpf von TKunde.Speichern. Der Entwurf ersetzt Assert.Fail im neuen Gerüst.
  mActions := FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 9);
  try
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual('Testfall f' + #$FC + 'r TKunde.Speichern anlegen', mActions[0].GetValue<string>('title'));
    mChanges := mActions[0].GetValue<TJSONArray>('edit.documentChanges');
    Assert.AreEqual(4, Integer(mChanges.Count));
    mText := FirstNewText(Find(mChanges, TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas')));
    Assert.IsTrue(Pos('procedure TKundeTests.TestSpeichern;'#13#10'begin'#13#10, mText) > 0, mText);
    Assert.IsTrue(Pos('  FSubject.Speichern;', mText) > 0, mText);
    Assert.IsTrue(Pos('  FSubject := TKunde.Create;', mText) > 0, mText);
    Assert.AreEqual('DUnitX-Testunit f' + #$FC + 'r TKunde anlegen', mActions[1].GetValue<string>('title'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspTestUnitsTests.DraftActionAddsToExistingTestUnit;
const
  cTestText =
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
  mActions: TArray<TJSONObject>;
  mChanges: TJSONArray;
  mEdits: TJSONArray;
  mText: string;
  mItem: TJSONValue;
begin
  FFiles.Add('C:\P\Tests\Kunden.Tests.pas', cTestText);
  FUnits.Add('kunden.tests', 'C:\P\Tests\Kunden.Tests.pas');
  mActions := FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 5);
  try
    Assert.AreEqual(2, Integer(Length(mActions)), 'Entwurf und Wechsel');
    mChanges := mActions[0].GetValue<TJSONArray>('edit.documentChanges');
    Assert.AreEqual(1, Integer(mChanges.Count));
    mEdits := TJSONObject(mChanges.Items[0]).GetValue<TJSONArray>('edits');
    mText := '';
    for mItem in mEdits do
    begin
      mText := mText + TJSONObject(mItem).GetValue<string>('newText');
    end;
    Assert.IsTrue(Pos('procedure TestSpeichern;', mText) > 0, mText);
    Assert.IsTrue(Pos('    Subject.Speichern;', mText) > 0, mText);
    Assert.IsTrue(Pos('Kunden', mText) > 0, 'uses: ' + mText);
    Assert.AreEqual('Zur Testunit Kunden.Tests wechseln', mActions[1].GetValue<string>('title'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspTestUnitsTests.SwitchesBothWays;
var
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
  mArguments: TJSONArray;
  mTarget: TTestUnitTarget;
begin
  FFiles.Add('C:\P\Tests\Kunden.Tests.pas', cKundenTestsText);
  mActions := FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 4);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Zur Testunit Kunden.Tests wechseln', mActions[0].GetValue<string>('title'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas'),
      mArguments.Items[0].Value));
  finally
    for mAction in mActions do
    begin
      mAction.Free;
    end;
  end;
  mTarget := TLspTestUnits.Resolve('C:\P\Tests\Kunden.Tests.pas', cKundenTestsText, 0, Context);
  Assert.IsTrue(mTarget.IsTest);
  Assert.AreEqual('Kunden', mTarget.Counterpart);
  Assert.AreEqual(cKundenFile, mTarget.CounterpartFile);
  Assert.IsFalse(mTarget.CanCreate);
end;

procedure TLspTestUnitsTests.WithoutTestProjectNoCreate;
var
  mTarget: TTestUnitTarget;
begin
  FTestProgram := '';
  mTarget := TLspTestUnits.Resolve(cKundenFile, cKundenText, 3, Context);
  Assert.IsFalse(mTarget.CanCreate);
  Assert.IsTrue(Pos('testUnits.project', mTarget.Reason) > 0, mTarget.Reason);
  Assert.AreEqual(0, Integer(Length(FTestUnits.Actions(TDocumentUris.FromPath(cKundenFile), 3))));
end;

procedure TLspTestUnitsTests.ProgramIsNoUnit;
begin
  Assert.AreEqual('', TLspTestUnits.Resolve(cTestsDpr, cDprText, 0, Context).UnitName);
end;

procedure TLspTestUnitsTests.CommandAnswers;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TDocumentUris.FromPath(cKundenFile));
    mAnswer := FTestUnits.Execute(mArguments);
    try
      Assert.AreEqual('Kunden', mAnswer.GetValue<string>('unit'));
      Assert.AreEqual('Kunden.Tests', mAnswer.GetValue<string>('counterpart'));
      Assert.IsTrue(mAnswer.GetValue<Boolean>('canCreate'));
      Assert.IsTrue(TJSONObject(mAnswer).GetValue('uri') is TJSONNull);
      Assert.IsNotNull(TJSONObject(mAnswer).GetValue('edit'));
      Assert.IsTrue(TDocumentUris.SameFile(TDocumentUris.FromPath('C:\P\Tests\Kunden.Tests.pas'),
        mAnswer.GetValue<string>('newUri')));
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTestUnitsTests);

end.
