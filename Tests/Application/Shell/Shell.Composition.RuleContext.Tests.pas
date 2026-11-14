unit Shell.Composition.RuleContext.Tests;

// Umfeld der Prüfregeln ohne Arbeitsbereich: Einstellungen ohne Ordner, eingebaute Regeln, Index, Formulardatei
// neben der Unit und die Prüfung im Editor.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.RuleContext;

type
  [TestFixture]
  TShellRuleContextTests = class
  private
    FRegistry: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FRuleContext: TShellRuleContext;
    FIndex: ISymbolIndex;
    function ReadForm(const AFileName: string; out AText: string): Boolean;
    function NoUnit(const AUnitName: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Arbeitsbereich: Datei, Regeln, Index und Formular neben der Unit stehen im Umfeld.</summary>
    [Test]
    procedure ContextWithoutWorkspace;
    /// <summary>Die Prüfung im Editor behält die Regeln, solange ruleChecks.enabled an ist.</summary>
    [Test]
    procedure LiveContextKeepsRules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Query.Contract,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.SyntaxDiagnostics;

function NoSelection(const AOrigin: string): string;
begin
  Result := '';
end;

function NoActive: string;
begin
  Result := '';
end;

function NoLanguage(const AUri: string): string;
begin
  Result := '';
end;

function TShellRuleContextTests.ReadForm(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm');
  AText := '';
  if Result then
  begin
    AText := 'object Form1: TForm1 end';
  end;
end;

function TShellRuleContextTests.NoUnit(const AUnitName: string): Boolean;
begin
  Result := False;
end;

procedure TShellRuleContextTests.Setup;
var
  mRegistry: TShellWorkspaceRegistryServices;
  mServices: TShellRuleContextServices;
  mIndex: ISymbolIndex;
begin
  mRegistry := Default(TShellWorkspaceRegistryServices);
  mRegistry.Logger := TLogger.Create;
  mRegistry.SelectedProject := NoSelection;
  mRegistry.ActiveProject := NoActive;
  mRegistry.ReadText := ReadForm;
  FRegistry := TShellWorkspaceRegistry.Create(mRegistry);
  FSettings := TShellSettings.Create(FRegistry, NoLanguage);
  FIndex := TSymbolIndex.Create;
  mIndex := FIndex;
  mServices := Default(TShellRuleContextServices);
  mServices.Logger := TLogger.Create;
  mServices.Workspaces := FRegistry;
  mServices.Settings := FSettings;
  mServices.Index :=
    function: ISymbolIndex
    begin
      Result := mIndex;
    end;
  mServices.UsesGraph :=
    function: TUsesGraphService
    begin
      Result := nil;
    end;
  mServices.Queries :=
    function: ICodeQueries
    begin
      Result := nil;
    end;
  mServices.EnsureUnit := NoUnit;
  mServices.ReadText := ReadForm;
  FRuleContext := TShellRuleContext.Create(mServices);
end;

procedure TShellRuleContextTests.TearDown;
begin
  FreeAndNil(FRuleContext);
  FreeAndNil(FSettings);
  FreeAndNil(FRegistry);
  FIndex := nil;
end;

procedure TShellRuleContextTests.ContextWithoutWorkspace;
var
  mContext: TRuleCheckContext;
  mFileName: string;
begin
  mFileName := ExpandFileName('Unit1.pas');
  Assert.IsTrue(FRuleContext.RuleContextFor(TDocumentUris.FromPath(mFileName), mContext));
  Assert.AreEqual(mFileName, mContext.FileName);
  Assert.IsTrue(Length(mContext.Rules) > 0, 'Regeln');
  Assert.AreSame(FIndex, mContext.Services.Index, 'Index');
  Assert.IsTrue(mContext.Live);
  Assert.AreEqual(ChangeFileExt(mFileName, '.dfm'), mContext.FormFile);
  Assert.AreEqual('object Form1: TForm1 end', mContext.FormText);
  Assert.IsTrue(Assigned(mContext.ReadFile) and Assigned(mContext.FileExists));
end;

procedure TShellRuleContextTests.LiveContextKeepsRules;
var
  mContext: TRuleCheckContext;
begin
  Assert.IsTrue(FRuleContext.LiveRuleContextFor(TDocumentUris.FromPath(ExpandFileName('Unit1.pas')), mContext));
  Assert.IsTrue(Length(mContext.Rules) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellRuleContextTests);

end.
