unit Atlas.Core.Settings.RuleChecksNotice.Tests;

// Tests zum Hinweis „Prüfregeln sind aus“ (#1454).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleChecksNoticeTests = class
  public
    [Test]
    procedure HasRulesNeedsRulesOrProfile;
    [Test]
    procedure WantedOncePerFileAndOnlyWhenOff;
    [Test]
    procedure ResetShowsAgain;
    [Test]
    procedure ConfigForWalksUp;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.RuleChecksNotice;

const
  cRules = '{ // Projekt' + sLineBreak + '  "rules": { "no-with": "error" } }';

procedure TRuleChecksNoticeTests.HasRulesNeedsRulesOrProfile;
begin
  Assert.IsTrue(TAtlasRuleChecksNotice.HasRules(cRules));
  Assert.IsTrue(TAtlasRuleChecksNotice.HasRules('{"profile": "strict"}'));
  Assert.IsFalse(TAtlasRuleChecksNotice.HasRules('{"rules": {}}'));
  Assert.IsFalse(TAtlasRuleChecksNotice.HasRules('{"profile": " "}'));
  Assert.IsFalse(TAtlasRuleChecksNotice.HasRules('{"encoding": "utf-8"}'));
  Assert.IsFalse(TAtlasRuleChecksNotice.HasRules('kein json'));
  Assert.IsFalse(TAtlasRuleChecksNotice.HasRules(''));
end;

procedure TRuleChecksNoticeTests.WantedOncePerFileAndOnlyWhenOff;
var
  mNotice: TAtlasRuleChecksNotice;
begin
  mNotice := TAtlasRuleChecksNotice.Create;
  try
    Assert.IsFalse(mNotice.Wanted('C:\A\atlas.json', cRules, True), 'Modul an');
    Assert.IsTrue(mNotice.Wanted('C:\A\atlas.json', cRules, False), 'erstes Mal');
    Assert.IsFalse(mNotice.Wanted('c:\a\ATLAS.json', cRules, False), 'schon gezeigt');
    Assert.IsFalse(mNotice.Wanted('C:\B\atlas.json', '{}', False), 'ohne Regeln');
    Assert.IsTrue(mNotice.Wanted('C:\B\atlas.json', cRules, False), 'andere Datei, jetzt mit Regeln');
    Assert.IsFalse(mNotice.Wanted('', cRules, False), 'ohne Datei');
  finally
    mNotice.Free;
  end;
end;

procedure TRuleChecksNoticeTests.ResetShowsAgain;
var
  mNotice: TAtlasRuleChecksNotice;
begin
  mNotice := TAtlasRuleChecksNotice.Create;
  try
    Assert.IsTrue(mNotice.Wanted('C:\A\atlas.json', cRules, False));
    mNotice.Reset;
    Assert.IsTrue(mNotice.Wanted('C:\A\atlas.json', cRules, False));
  finally
    mNotice.Free;
  end;
end;

procedure TRuleChecksNoticeTests.ConfigForWalksUp;
var
  mRoot, mExpected: string;
  mExists: TAtlasConfigExists;
begin
  mRoot := IncludeTrailingPathDelimiter('Repo');
  mExpected := mRoot + 'atlas.json';
  mExists :=
    function(const AFile: string): Boolean
    begin
      Result := SameText(AFile, mExpected);
    end;
  Assert.AreEqual(mExpected, TAtlasRuleChecksNotice.ConfigFor(mRoot + 'Src' + PathDelim + 'App.dproj', mExists));
  Assert.AreEqual(mExpected, TAtlasRuleChecksNotice.ConfigFor(mRoot + 'App.dproj', mExists));
  Assert.AreEqual('', TAtlasRuleChecksNotice.ConfigFor('Anders' + PathDelim + 'App.dproj', mExists));
  Assert.AreEqual('', TAtlasRuleChecksNotice.ConfigFor('', mExists));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleChecksNoticeTests);

end.
