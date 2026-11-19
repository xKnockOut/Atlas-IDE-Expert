unit Shell.Mcp.IssueTools.Tests;

// Tests von get_current_issue (#2051): Anmeldung, <gitdir> über dem Projektordner, Lesen mit BOM, Meldungen ohne
// Git bzw. ohne begonnenes Issue, Text und JSON, falsche Argumente.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIssueToolsTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RegistersGetCurrentIssue;
    [Test]
    procedure FindsGitDirAboveFolder;
    [Test]
    procedure ReadsFileWithoutBom;
    [Test]
    procedure WithoutGitOrIssueSaysWhy;
    [Test]
    procedure ShowsTextAndJson;
    [Test]
    procedure RejectsUnknownSection;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts,
  Atlas.Core.Tracker.CurrentIssue,
  Shell.Mcp.Context,
  Shell.Mcp.IssueTools,
  Atlas.Tests.TempFolder;

const
  cNow = 46000.5;

function Arguments(const ASection, AFormat: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  if ASection <> '' then
  begin
    Result.AddPair('section', ASection);
  end;
  if AFormat <> '' then
  begin
    Result.AddPair('format', AFormat);
  end;
end;

function Ask(const ARoot, ASection, AFormat: string): string;
var
  mArguments: TJSONObject;
begin
  mArguments := Arguments(ASection, AFormat);
  try
    Result := CurrentIssueOf(ARoot, mArguments, cNow);
  finally
    mArguments.Free;
  end;
end;

procedure WriteIssue(const AGitDir: string);
var
  mIssue: TAtlasCurrentIssue;
begin
  mIssue := TAtlasCurrentIssue.Empty;
  mIssue.Key := '#2051';
  mIssue.Title := 'get_current_issue';
  mIssue.Tracker := 'github';
  mIssue.Description := 'Beschreibung mit Ä';
  mIssue.Fetched := cNow - 1 / 24;
  TFile.WriteAllText(TAtlasCurrentIssue.FileOf(AGitDir), mIssue.ToJson, TEncoding.UTF8);
end;

{ TMcpIssueToolsTests }

procedure TMcpIssueToolsTests.Setup;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  FDir := TPath.Combine(TPath.GetTempPath, 'atlas-issue-' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FDir);
end;

procedure TMcpIssueToolsTests.TearDown;
begin
  TTestTempFolder.Remove(FDir);
end;

procedure TMcpIssueToolsTests.RegistersGetCurrentIssue;
var
  mServer: TMcpServer;
  mContext: TMcpToolContext;
  mListed: TJSONObject;
  mTools: TJSONArray;
begin
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mContext := Default(TMcpToolContext);
    mContext.Server := mServer;
    RegisterIssueTools(mContext);
    mListed := mServer.ListTools;
    try
      mTools := mListed.GetValue<TJSONArray>('tools');
      Assert.AreEqual(1, Integer(mTools.Count));
      Assert.AreEqual('get_current_issue', mTools.Items[0].GetValue<string>('name'));
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TMcpIssueToolsTests.FindsGitDirAboveFolder;
var
  mSub: string;
begin
  Assert.AreEqual('', GitDirAbove(TPath.Combine(FDir, 'fehlt')), 'ohne .git');
  TDirectory.CreateDirectory(TPath.Combine(FDir, '.git'));
  mSub := TPath.Combine(TPath.Combine(FDir, 'Src'), 'Tief');
  TDirectory.CreateDirectory(mSub);
  Assert.AreEqual(TPath.Combine(FDir, '.git'), GitDirAbove(mSub));
end;

procedure TMcpIssueToolsTests.ReadsFileWithoutBom;
begin
  TFile.WriteAllText(TPath.Combine(FDir, 'a.txt'), 'ATL-1 ', TEncoding.UTF8);
  Assert.AreEqual('ATL-1 ', ReadGitDirFile(FDir, 'a.txt', 100), 'BOM übergangen, Leerzeichen bleibt');
  Assert.AreEqual('', ReadGitDirFile(FDir, 'a.txt', 3), 'zu groß');
  Assert.AreEqual('', ReadGitDirFile(FDir, 'fehlt.txt', 100));
  Assert.AreEqual('', ReadGitDirFile('', 'a.txt', 100));
end;

procedure TMcpIssueToolsTests.WithoutGitOrIssueSaysWhy;
var
  mText: string;
begin
  mText := Ask(TPath.Combine(FDir, 'ohne'), '', '');
  Assert.IsTrue(mText.StartsWith('Kein Git-Repository'), mText);
  TDirectory.CreateDirectory(TPath.Combine(FDir, '.git'));
  mText := Ask(FDir, '', '');
  Assert.IsTrue(mText.StartsWith('Kein begonnenes Issue in dieser Arbeitskopie'), mText);
  Assert.IsTrue(Pos('issues.shareWithAssistants', mText) > 0, 'nennt den Schalter');
end;

procedure TMcpIssueToolsTests.ShowsTextAndJson;
var
  mText: string;
  mValue: TJSONValue;
begin
  TDirectory.CreateDirectory(TPath.Combine(FDir, '.git'));
  WriteIssue(TPath.Combine(FDir, '.git'));
  mText := Ask(FDir, '', '');
  Assert.IsTrue(mText.StartsWith('#2051 get_current_issue' + #10 + 'GitHub'), mText);
  Assert.IsTrue(Pos('Stand vor 1 Std.', mText) > 0, mText);
  mText := Ask(FDir, 'body', 'json');
  mValue := TJSONObject.ParseJSONValue(mText);
  try
    Assert.IsTrue(mValue is TJSONObject, mText);
    Assert.AreEqual('Beschreibung mit Ä', mValue.GetValue<string>('description'));
  finally
    mValue.Free;
  end;
end;

procedure TMcpIssueToolsTests.RejectsUnknownSection;
begin
  Assert.WillRaise(
    procedure
    begin
      Ask(FDir, 'alles', '');
    end, EMcpToolError);
  Assert.WillRaise(
    procedure
    begin
      Ask(FDir, '', 'markdown');
    end, EMcpToolError);
  TDirectory.CreateDirectory(TPath.Combine(FDir, '.git'));
  TFile.WriteAllText(TPath.Combine(TPath.Combine(FDir, '.git'), TAtlasCurrentIssue.cFileName), '{"version":9}');
  Assert.WillRaise(
    procedure
    begin
      Ask(FDir, '', '');
    end, EMcpToolError, 'fremde Version');
end;

end.
