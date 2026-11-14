unit Atlas.Common.Lsp.CompilerDirectives.Tests;

// Tests für die Sprachreferenz der Compiler-Direktiven (#102, Teil 1).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerDirectivesTests = class
  public
    [Test]
    procedure EveryDirectiveHasTextAndLinkForDelphi12And13;
    [Test]
    procedure SwitchLetterExplainsRangeChecks;
    [Test]
    procedure SeveralSwitchesAreAllDescribed;
    [Test]
    procedure FileDirectivesAreNotSwitches;
    [Test]
    procedure WarnNamesTheWarning;
    [Test]
    procedure UnknownDirectiveIsNotDescribed;
    [Test]
    procedure CompletesDirectiveNames;
    [Test]
    procedure CompletesWarningsAfterWarn;
    [Test]
    procedure NoCompletionOutsideDirective;
    [Test]
    procedure HoverFindsDirectiveToken;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Lsp.CompilerDirectives;

procedure TCompilerDirectivesTests.EveryDirectiveHasTextAndLinkForDelphi12And13;
var
  mInfo: TDirectiveInfo;
begin
  Assert.IsTrue(Length(TCompilerDirectives.All) > 40);
  for mInfo in TCompilerDirectives.All do
  begin
    Assert.AreNotEqual('', mInfo.Text, mInfo.Name);
    Assert.AreNotEqual('', mInfo.Topic, mInfo.Name);
    // Die Prüfregel conditional-directive-unbalanced (#989) kennt jede Direktive der Tabelle.
    Assert.IsTrue(TDirectiveNames.IsDirective(mInfo.Name), mInfo.Name);
    Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Athens/en/' + mInfo.Topic,
      TCompilerDirectives.Url('23.0', mInfo.Topic));
    Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Florence/en/' + mInfo.Topic,
      TCompilerDirectives.Url('37.0', mInfo.Topic));
  end;
end;

procedure TCompilerDirectivesTests.SwitchLetterExplainsRangeChecks;
var
  mMarkdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R+}', '23.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'RANGECHECKS'));
  Assert.IsTrue(ContainsText(mMarkdown, 'Bereichsprüfung'));
  Assert.IsTrue(ContainsText(mMarkdown, 'eingeschaltet'));
  Assert.IsTrue(ContainsText(mMarkdown, 'https://docwiki.embarcadero.com/RADStudio/Athens/en/Range_checking'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$RANGECHECKS OFF}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'ausgeschaltet'));
end;

procedure TCompilerDirectivesTests.SeveralSwitchesAreAllDescribed;
var
  mMarkdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R+,Q-}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'RANGECHECKS'));
  Assert.IsTrue(ContainsText(mMarkdown, 'OVERFLOWCHECKS'));
end;

procedure TCompilerDirectivesTests.FileDirectivesAreNotSwitches;
var
  mMarkdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R *.res}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'RESOURCE'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$I Defines.inc}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'INCLUDE'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$I-}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'IOCHECKS'));
end;

procedure TCompilerDirectivesTests.WarnNamesTheWarning;
var
  mMarkdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$WARN SYMBOL_DEPRECATED OFF}', '37.0', mMarkdown));
  Assert.IsTrue(ContainsText(mMarkdown, 'SYMBOL_DEPRECATED'));
  Assert.IsTrue(ContainsText(mMarkdown, 'Warning_messages_(Delphi)'));
end;

procedure TCompilerDirectivesTests.UnknownDirectiveIsNotDescribed;
var
  mMarkdown: string;
begin
  Assert.IsFalse(TCompilerDirectives.Describe('{$GIBTSNICHT}', '37.0', mMarkdown));
end;

procedure TCompilerDirectivesTests.CompletesDirectiveNames;
var
  mNames: TArray<string>;
  mIsWarning: Boolean;
begin
  Assert.IsTrue(TCompilerDirectives.CompletionAt('  {$IFD', mNames, mIsWarning));
  Assert.IsFalse(mIsWarning);
  Assert.IsTrue(MatchText('IFDEF', mNames));
  Assert.IsTrue(TCompilerDirectives.CompletionAt('{$', mNames, mIsWarning));
end;

procedure TCompilerDirectivesTests.CompletesWarningsAfterWarn;
var
  mNames: TArray<string>;
  mIsWarning: Boolean;
begin
  Assert.IsTrue(TCompilerDirectives.CompletionAt('{$WARN SYM', mNames, mIsWarning));
  Assert.IsTrue(mIsWarning);
  Assert.AreEqual(Integer(Length(TCompilerDirectives.Warnings)), Integer(Length(mNames)));
  Assert.IsTrue(MatchText('SYMBOL_PLATFORM', mNames));
  // Hinter dem Bezeichner (ON/OFF) nichts mehr.
  Assert.IsFalse(TCompilerDirectives.CompletionAt('{$WARN SYMBOL_PLATFORM O', mNames, mIsWarning));
end;

procedure TCompilerDirectivesTests.NoCompletionOutsideDirective;
var
  mNames: TArray<string>;
  mIsWarning: Boolean;
begin
  Assert.IsFalse(TCompilerDirectives.CompletionAt('  {$R+} Wert := ', mNames, mIsWarning));
  Assert.IsFalse(TCompilerDirectives.CompletionAt('  Wert := ', mNames, mIsWarning));
  Assert.IsFalse(TCompilerDirectives.CompletionAt('{$IFDEF DEBUG', mNames, mIsWarning));
end;

procedure TCompilerDirectivesTests.HoverFindsDirectiveToken;
var
  mTree: TSyntaxTree;
  mMarkdown: string;
  mPosition: TTextPosition;
begin
  mTree := TPascalParser.Parse('unit U;'#10'{$Q+}'#10'interface'#10'implementation'#10'end.');
  try
    mPosition.Line := 1;
    mPosition.Character := 2;
    Assert.IsTrue(TCompilerDirectives.HoverAt(mTree, mPosition, '37.0', mMarkdown));
    Assert.IsTrue(ContainsText(mMarkdown, 'OVERFLOWCHECKS'));
    mPosition.Line := 0;
    Assert.IsFalse(TCompilerDirectives.HoverAt(mTree, mPosition, '37.0', mMarkdown));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerDirectivesTests);

end.
