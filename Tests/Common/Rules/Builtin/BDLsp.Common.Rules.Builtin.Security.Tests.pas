unit BDLsp.Common.Rules.Builtin.Security.Tests;

// Tests für die Sicherheitsregeln, Teil 2 (#149).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSecurityRulesTests = class
  public
    [Test]
    procedure ComposedShellCommandReports;
    [Test]
    procedure LiteralShellCommandIsSilent;
    [Test]
    procedure FileFromInputReports;
    [Test]
    procedure CheckedOrConstantPathIsSilent;
    [Test]
    procedure ChecksumMd5IsLowConfidence;
    [Test]
    procedure PasswordHashWithSha1IsMedium;
    [Test]
    procedure IndyVerifyModeReports;
    [Test]
    procedure AcceptAllCertificatesReports;
    [Test]
    procedure CheckedCertificateIsSilent;
    [Test]
    procedure HttpUrlReportsWithFix;
    [Test]
    procedure LocalAndSchemaUrlsAreSilent;
    [Test]
    procedure RandomTokenReports;
    [Test]
    procedure RandomForOtherValuesIsSilent;
    [Test]
    procedure SqlFromEditIsHighConfidence;
    [Test]
    procedure SqlFromVariableIsMedium;
    [Test]
    procedure ParameterizedOrConstantSqlIsSilent;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.Security,
  BDLsp.Tests.RuleAssert;

const
  LowConfidence = '{"minConfidence": "low"}';

function Body(const AStatements: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Run;'#10'begin'#10 + AStatements + #10 +
    'end;'#10'end.';
end;

procedure TSecurityRulesTests.ComposedShellCommandReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSecurityCommandInjectionRule.Create,
    Body('  ShellExecute(0, ''open'', PChar(''cmd /c '' + Edit1.Text), nil, nil, SW_SHOW);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  TRuleAssert.Reports(TSecurityCommandInjectionRule.Create,
    Body('  WinExec(PAnsiChar(AnsiString(Format(''tool.exe %s'', [Datei]))), SW_HIDE);'));
end;

procedure TSecurityRulesTests.LiteralShellCommandIsSilent;
begin
  TRuleAssert.Silent(TSecurityCommandInjectionRule.Create,
    Body('  ShellExecute(0, ''open'', ''notepad.exe'', nil, nil, SW_SHOW);'#10 +
    '  ShellExecute(0, ''open'', PChar(''cmd /c '' + ''dir''), nil, nil, SW_SHOW);'));
end;

procedure TSecurityRulesTests.FileFromInputReports;
begin
  TRuleAssert.Reports(TSecurityPathTraversalRule.Create,
    Body('  Liste.LoadFromFile(''C:\Daten\'' + Edit1.Text);'), 0);
  // Experimentell: läuft nur, wenn eingeschaltet.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TSecurityPathTraversalRule.Create,
    Body('  Liste.LoadFromFile(''C:\Daten\'' + Edit1.Text);'),
    '{"rules": {"security-path-traversal": "warning"}}'))));
end;

procedure TSecurityRulesTests.CheckedOrConstantPathIsSilent;
const
  Enabled = '{"rules": {"security-path-traversal": "warning"}}';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSecurityPathTraversalRule.Create,
    Body('  Liste.LoadFromFile(TPath.GetFullPath(Edit1.Text));'#10'  Liste.LoadFromFile(''config.ini'');'),
    Enabled))));
end;

procedure TSecurityRulesTests.ChecksumMd5IsLowConfidence;
var
  Findings: TArray<TRuleFinding>;
begin
  // Unter der Vorgabe minConfidence medium bleibt die Prüfsumme still.
  TRuleAssert.Silent(TSecurityWeakCryptoRule.Create, Body('  Summe := THashMD5.GetHashString(Dateiinhalt);'));
  Findings := TRuleAssert.Findings(TSecurityWeakCryptoRule.Create,
    Body('  Summe := THashMD5.GetHashString(Dateiinhalt);'), LowConfidence);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
end;

procedure TSecurityRulesTests.PasswordHashWithSha1IsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSecurityWeakCryptoRule.Create,
    Body('  Gespeichert := THashSHA1.GetHashString(PasswordText);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TSecurityRulesTests.IndyVerifyModeReports;
begin
  TRuleAssert.Reports(TSecurityTlsVerificationDisabledRule.Create, Body('  IdSSL.SSLOptions.VerifyMode := [];'));
  TRuleAssert.Silent(TSecurityTlsVerificationDisabledRule.Create,
    Body('  IdSSL.SSLOptions.VerifyMode := [sslvrfPeer];'));
end;

procedure TSecurityRulesTests.AcceptAllCertificatesReports;
begin
  TRuleAssert.Reports(TSecurityTlsVerificationDisabledRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TForm1.Pruefen(const Sender: TObject; const ARequest: TURLRequest;'#10 +
    '  const Certificate: TCertificate; var Accepted: Boolean);'#10 +
    'begin'#10'  Accepted := True;'#10'end;'#10 +
    'function TForm1.VerifyPeer(Certificate: TIdX509; AOk: Boolean; ADepth, AError: Integer): Boolean;'#10 +
    'begin'#10'  Result := True;'#10'end;'#10'end.', 2);
end;

procedure TSecurityRulesTests.CheckedCertificateIsSilent;
begin
  TRuleAssert.Silent(TSecurityTlsVerificationDisabledRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TForm1.Pruefen(const Sender: TObject; const ARequest: TURLRequest;'#10 +
    '  const Certificate: TCertificate; var Accepted: Boolean);'#10 +
    'begin'#10'  if Certificate.Expiry > Now then'#10'    Accepted := True;'#10'end;'#10 +
    'procedure Setzen;'#10'begin'#10'  Fertig := True;'#10'end;'#10'end.');
end;

procedure TSecurityRulesTests.HttpUrlReportsWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSecurityInsecureHttpRule.Create,
    Body('  Client.Get(''http://api.example.com/daten'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(14, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(21, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('https://', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TSecurityRulesTests.LocalAndSchemaUrlsAreSilent;
begin
  TRuleAssert.Silent(TSecurityInsecureHttpRule.Create,
    Body('  Schema := ''http://www.w3.org/2001/XMLSchema'';'#10 +
    '  Client.Get(''http://localhost:8080'');'#10 +
    '  // siehe http://example.com'#10 +
    '  Client.Get(''https://api.example.com'');'));
end;

procedure TSecurityRulesTests.RandomTokenReports;
begin
  TRuleAssert.Reports(TSecurityInsecureRandomRule.Create, Body('  Token := IntToStr(Random(MaxInt));'));
end;

procedure TSecurityRulesTests.RandomForOtherValuesIsSilent;
begin
  TRuleAssert.Silent(TSecurityInsecureRandomRule.Create,
    Body('  Wurf := Random(6) + 1;'#10'  Token := TGUID.NewGuid.ToString;'));
end;

procedure TSecurityRulesTests.SqlFromEditIsHighConfidence;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSecuritySqlInjectionRule.Create,
    Body('  Q.SQL.Text := ''select * from K where N = '''''' + Edit1.Text + '''''''';'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
end;

procedure TSecurityRulesTests.SqlFromVariableIsMedium;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSecuritySqlInjectionRule.Create,
    Body('  Q.SQL.Add(''where Name = '' + Name);'#10 +
    '  Q.Open(Format(''select * from %s'', [Tabelle]));'#10 +
    '  Cmd.CommandText := ''delete from K where Id = '' + Wert;'));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TSecurityRulesTests.ParameterizedOrConstantSqlIsSilent;
begin
  TRuleAssert.Silent(TSecuritySqlInjectionRule.Create,
    'unit U;'#10'interface'#10'implementation'#10 +
    'const'#10'  Tabelle = ''Kunden'';'#10 +
    'resourcestring'#10'  Abfrage = ''select * from '';'#10 +
    'procedure Run(const Id: Integer);'#10'begin'#10 +
    '  Q.SQL.Text := ''select * from K where N = :N'';'#10 +
    '  Q.SQL.Text := Abfrage + Tabelle;'#10 +
    '  Q.SQL.Text := ''select * from K where Id = '' + IntToStr(Id);'#10 +
    '  Q.SQL.Add(''and Name = '' + QuotedStr(Edit1.Text));'#10 +
    '  Q.Open;'#10 +
    '  Q.ExecSQL(''update K set A = :A'', [Edit1.Text]);'#10 +
    'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TSecurityRulesTests);

end.
