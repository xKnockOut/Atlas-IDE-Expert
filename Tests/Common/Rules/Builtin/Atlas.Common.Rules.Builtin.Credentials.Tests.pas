unit Atlas.Common.Rules.Builtin.Credentials.Tests;

// Tests für die Sicherheitsregel security-hardcoded-credential (#57).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCredentialRuleTests = class
  public
    [Test]
    procedure ConnectionStringPasswordReports;
    [Test]
    procedure ComposedOrSqlPasswordIsSilent;
    [Test]
    procedure PasswordConstantReports;
    [Test]
    procedure EmptyOrPlaceholderIsSilent;
    [Test]
    procedure GitHubTokenIsHighConfidence;
    [Test]
    procedure ResourceStringReportsOnlyKeyFormats;
    [Test]
    procedure CommentsAreSilent;
    [Test]
    procedure NameMustEndWithCredentialWord;
    [Test]
    procedure ValuesIndexReports;
    [Test]
    procedure FormConnectionStringReports;
    [Test]
    procedure FormWithoutPasswordIsSilent;
    [Test]
    procedure PatternsOptionAddsKeyFormats;
    [Test]
    procedure MaskedShowsAtMostFourChars;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Credentials,
  Atlas.Tests.RuleAssert;

const
  cGitHubToken = 'ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8';
  cFormSource = 'unit Daten;'#10'interface'#10'type'#10'  TdmDaten = class(TDataModule)'#10 +
    '    conMain: TADOConnection;'#10'  end;'#10'implementation'#10'end.';

function Body(const AStatements: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Run;'#10'begin'#10 + AStatements + #10 +
    'end;'#10'end.';
end;

function Declarations(const ASection: string): string;
begin
  Result := 'unit U;'#10'interface'#10 + ASection + #10'implementation'#10'end.';
end;

function Rule: IRule;
begin
  Result := TSecurityHardcodedCredentialRule.Create;
end;

procedure TCredentialRuleTests.ConnectionStringPasswordReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(Rule,
    Body('  Verbindung.ConnectionString := ''Provider=SQLOLEDB;User ID=sa;Password=geheim;'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.IsFalse(mFindings[0].Message.Contains('geheim'), mFindings[0].Message);
  Assert.IsTrue(mFindings[0].Message.Contains('''geh****'''), mFindings[0].Message);
  // FireDAC: Params.Add mit Pwd=.
  TRuleAssert.Reports(Rule, Body('  Verbindung.Params.Add(''Pwd=Sommer2026'');'));
end;

procedure TCredentialRuleTests.ComposedOrSqlPasswordIsSilent;
begin
  TRuleAssert.Silent(Rule, Body('  Verbindung.ConnectionString := ''User ID=sa;Password='' + mKennwort + '';'';'));
  TRuleAssert.Silent(Rule, Body('  Abfrage.SQL.Text := ''SELECT * FROM Benutzer WHERE Password = :Pwd'';'));
  TRuleAssert.Silent(Rule, Body('  Verbindung.ConnectionString := Format(''Password=%s'', [mKennwort]);'));
end;

procedure TCredentialRuleTests.PasswordConstantReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(Rule, Declarations('const'#10'  DbPassword = ''geheim'';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.IsFalse(mFindings[0].Message.Contains('geheim'), mFindings[0].Message);
  // Typisierte Konstante, Vorbelegung und Zuweisung.
  TRuleAssert.Reports(Rule, Declarations('const'#10'  cKennwort: string = ''Sommer2026'';'));
  TRuleAssert.Reports(Rule, Body('  FPassword := ''Sommer2026'';'));
end;

procedure TCredentialRuleTests.EmptyOrPlaceholderIsSilent;
begin
  TRuleAssert.Silent(Rule, Declarations('const'#10'  DbPassword = '''';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  DbPassword = ''***'';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  DbPassword = ''<Kennwort>'';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  DbPassword = ''changeme'';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  DbPassword = ''%s'';'));
  // Texte mit Leerzeichen sind Meldungen, Werte wie ''Password'' sind Schlüsselnamen.
  TRuleAssert.Silent(Rule, Declarations('const'#10'  cAskPassword = ''Bitte Kennwort eingeben'';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  cPassword = ''Password'';'));
end;

procedure TCredentialRuleTests.GitHubTokenIsHighConfidence;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(Rule, Body('  mWert := ''' + cGitHubToken + ''';'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.IsFalse(mFindings[0].Message.Contains(cGitHubToken), mFindings[0].Message);
  Assert.IsTrue(mFindings[0].Message.Contains('''ghp_****'''), mFindings[0].Message);
  // Zu kurz für das Format.
  TRuleAssert.Silent(Rule, Body('  mWert := ''ghp_abc'';'));
  TRuleAssert.Reports(Rule, Body('  mWert := ''AKIAIOSFODNN7EXAMPLE'';'));
  TRuleAssert.Reports(Rule, Body('  mWert := ''-----BEGIN RSA PRIVATE KEY-----'';'));
end;

procedure TCredentialRuleTests.ResourceStringReportsOnlyKeyFormats;
begin
  TRuleAssert.Silent(Rule, Declarations('resourcestring'#10'  sPassword = ''Sommer2026'';'));
  TRuleAssert.Reports(Rule, Declarations('resourcestring'#10'  sHinweis = ''' + cGitHubToken + ''';'));
  // Hinter dem resourcestring-Abschnitt gilt wieder alles.
  TRuleAssert.Reports(Rule, Declarations('resourcestring'#10'  sTitel = ''Anmelden'';'#10'const'#10 +
    '  DbPassword = ''geheim'';'));
end;

procedure TCredentialRuleTests.CommentsAreSilent;
begin
  TRuleAssert.Silent(Rule, Body('  // Password=geheim'#10'  { ' + cGitHubToken + ' }'#10'  Run;'));
end;

procedure TCredentialRuleTests.NameMustEndWithCredentialWord;
begin
  TRuleAssert.Silent(Rule, Declarations('const'#10'  cEndToken = ''end'';'));
  TRuleAssert.Silent(Rule, Declarations('const'#10'  cTokenKind = ''identifier'';'));
  TRuleAssert.Silent(Rule, Body('  Edit1.PasswordChar := ''#'';'));
  // Schlüssel und Token erst ab acht Zeichen.
  TRuleAssert.Silent(Rule, Body('  FApiKey := ''abc123'';'));
  TRuleAssert.Reports(Rule, Body('  FApiKey := ''abcd1234efgh'';'));
  TRuleAssert.Reports(Rule, Body('  if mPassword = ''geheim'' then'#10'    Run;'));
  // Vergleich mit Token-Text und zusammengesetzte Werte sind keine Zugangsdaten.
  TRuleAssert.Silent(Rule, Body('  if (mToken = ''external'') or (mToken = ''forward'') then'#10'    Run;'));
  TRuleAssert.Silent(Rule, Body('  mToken := ''atlas-partial-'' + IntToStr(FNext);'));
  TRuleAssert.Silent(Rule, Body('  Verbindung.Params.Values[''Password''] := ''Sommer'' + mJahr;'));
end;

procedure TCredentialRuleTests.ValuesIndexReports;
begin
  TRuleAssert.Reports(Rule, Body('  Verbindung.Params.Values[''Password''] := ''geheim'';'));
  TRuleAssert.Silent(Rule, Body('  Verbindung.Params.Values[''Server''] := ''db01'';'));
end;

procedure TCredentialRuleTests.FormConnectionStringReports;
const
  cForm = 'object dmDaten: TdmDaten'#10'  object conMain: TADOConnection'#10 +
    '    ConnectionString = ''Provider=SQLOLEDB.1;Password=geheim;User ID=sa'''#10'  end'#10'end';
  cParams = 'object dmDaten: TdmDaten'#10'  object conMain: TFDConnection'#10'    Params.Strings = ('#10 +
    '      ''DriverID=MSSQL'''#10'      ''Password=Sommer2026'')'#10'  end'#10'end';
  cProperty = 'object dmDaten: TdmDaten'#10'  object conMain: TIdFTP'#10'    Password = ''geheim'''#10 +
    '  end'#10'end';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.FormFindings(Rule, cFormSource, cForm);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Line);
  Assert.IsTrue(mFindings[0].Message.Contains('conMain.ConnectionString'), mFindings[0].Message);
  Assert.IsFalse(mFindings[0].Message.Contains('geheim'), mFindings[0].Message);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(Rule, cFormSource, cParams))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(Rule, cFormSource, cProperty))));
end;

procedure TCredentialRuleTests.FormWithoutPasswordIsSilent;
const
  cForm = 'object dmDaten: TdmDaten'#10'  object conMain: TADOConnection'#10 +
    '    ConnectionString = ''Provider=SQLOLEDB.1;Integrated Security=SSPI'''#10 +
    '    LoginPrompt = False'#10'  end'#10'end';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(Rule, cFormSource, cForm))));
end;

procedure TCredentialRuleTests.PatternsOptionAddsKeyFormats;
const
  cConfig = '{"rules": {"security-hardcoded-credential": {"patterns": ["\\bACME-[0-9]{6}\\b"]}}}';
begin
  TRuleAssert.Silent(Rule, Body('  mWert := ''ACME-123456'';'));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(Rule, Body('  mWert := ''ACME-123456'';'), cConfig))));
end;

procedure TCredentialRuleTests.MaskedShowsAtMostFourChars;
begin
  Assert.AreEqual('''gehe****''', TSecurityHardcodedCredentialRule.Masked('geheimnisvoll'));
  Assert.AreEqual('''ge****''', TSecurityHardcodedCredentialRule.Masked('gehei'));
  Assert.AreEqual('''****''', TSecurityHardcodedCredentialRule.Masked('a'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCredentialRuleTests);

end.
