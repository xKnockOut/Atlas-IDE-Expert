unit Shell.Composition.Slash.Tests;

// Host der Schnellbefehle der Komposition: Einstellungen slashCommands.*, Kopfvorlage ohne Ordner, Testunit ohne
// Arbeitsbereich und Regeltreffer ohne Prüfkontext.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.TestUnits,
  Shell.Composition.Slash;

type
  [TestFixture]
  TShellSlashTests = class
  private
    function SettingsFor(const AUri: string): TServerSettings;
    function NoWorkspaceSettings(const AUri: string; out ASettings: TServerSettings): Boolean;
    function NoTestContext(const AUri: string; out AContext: TTestUnitContext): Boolean;
    function NoRuleContext(const AUri: string; out AContext: TRuleCheckContext): Boolean;
    function NewServices: TShellSlashServices;
  public
    /// <summary>Der Host liest slashCommands.* aus den Einstellungen der Datei, als Text.</summary>
    [Test]
    procedure SettingsAsText;
    /// <summary>Ohne Ordner gibt es keine Kopfvorlage und keine Testunit.</summary>
    [Test]
    procedure WithoutWorkspaceNoHeaderAndNoTestUnit;
    /// <summary>Ohne Prüfkontext meldet die Zeile keine Regeltreffer.</summary>
    [Test]
    procedure WithoutRuleContextNoRuleIds;
  end;

implementation

uses
  Atlas.Common.Editing.Contract;

function TShellSlashTests.SettingsFor(const AUri: string): TServerSettings;
begin
  Result := Default(TServerSettings);
  Result.SlashLogCall := 'Log.Info';
  Result.SlashEnumHelper := True;
  Result.Completion.InterfaceSection := TCompletionInterfaceSection.Protected;
end;

function TShellSlashTests.NoWorkspaceSettings(const AUri: string; out ASettings: TServerSettings): Boolean;
begin
  ASettings := Default(TServerSettings);
  Result := False;
end;

function TShellSlashTests.NoTestContext(const AUri: string; out AContext: TTestUnitContext): Boolean;
begin
  AContext := Default(TTestUnitContext);
  Result := False;
end;

function TShellSlashTests.NoRuleContext(const AUri: string; out AContext: TRuleCheckContext): Boolean;
begin
  AContext := Default(TRuleCheckContext);
  Result := False;
end;

function TShellSlashTests.NewServices: TShellSlashServices;
begin
  Result := Default(TShellSlashServices);
  Result.SettingsFor := SettingsFor;
  Result.WorkspaceSettingsOf := NoWorkspaceSettings;
  Result.TestUnitContextFor := NoTestContext;
  Result.RuleContextFor := NoRuleContext;
end;

procedure TShellSlashTests.SettingsAsText;
var
  mSlash: TShellSlash;
begin
  mSlash := TShellSlash.Create(NewServices);
  try
    Assert.AreEqual('Log.Info', mSlash.Host.Setting('file:///tmp/A.pas', TSlashSettings.cLogCall));
    Assert.AreEqual('true', mSlash.Host.Setting('file:///tmp/A.pas', TSlashSettings.cEnumHelper));
    Assert.AreEqual('protected', mSlash.Host.Setting('file:///tmp/A.pas', TSlashSettings.cInterfaceSection));
    Assert.AreEqual('', mSlash.Host.Setting('file:///tmp/A.pas', 'unbekannt'));
  finally
    mSlash.Free;
  end;
end;

procedure TShellSlashTests.WithoutWorkspaceNoHeaderAndNoTestUnit;
var
  mSlash: TShellSlash;
  mTarget: TSlashTestUnit;
begin
  mSlash := TShellSlash.Create(NewServices);
  try
    Assert.AreEqual('', mSlash.Host.HeaderTemplate('file:///tmp/A.pas'));
    Assert.IsFalse(mSlash.Host.TestUnit('file:///tmp/A.pas', 'unit A;', mTarget));
    Assert.AreEqual('Datei gehört zu keinem Arbeitsbereich', mTarget.Reason);
  finally
    mSlash.Free;
  end;
end;

procedure TShellSlashTests.WithoutRuleContextNoRuleIds;
var
  mSlash: TShellSlash;
  mIds: TArray<string>;
begin
  mSlash := TShellSlash.Create(NewServices);
  try
    Assert.IsFalse(mSlash.RuleIdsAt('file:///tmp/A.pas', 'unit A;', 0, mIds));
    Assert.AreEqual(0, Integer(Length(mIds)));
  finally
    mSlash.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellSlashTests);

end.
