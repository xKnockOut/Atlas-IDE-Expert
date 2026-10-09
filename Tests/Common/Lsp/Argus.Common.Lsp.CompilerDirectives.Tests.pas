unit Argus.Common.Lsp.CompilerDirectives.Tests;

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
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Lsp.CompilerDirectives;

procedure TCompilerDirectivesTests.EveryDirectiveHasTextAndLinkForDelphi12And13;
var
  Info: TDirectiveInfo;
begin
  Assert.IsTrue(Length(TCompilerDirectives.All) > 40);
  for Info in TCompilerDirectives.All do
  begin
    Assert.IsTrue(Info.Text <> '', Info.Name);
    Assert.IsTrue(Info.Topic <> '', Info.Name);
    Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Athens/en/' + Info.Topic,
      TCompilerDirectives.Url('23.0', Info.Topic));
    Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Florence/en/' + Info.Topic,
      TCompilerDirectives.Url('37.0', Info.Topic));
  end;
end;

procedure TCompilerDirectivesTests.SwitchLetterExplainsRangeChecks;
var
  Markdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R+}', '23.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'RANGECHECKS'));
  Assert.IsTrue(ContainsText(Markdown, 'Bereichsprüfung'));
  Assert.IsTrue(ContainsText(Markdown, 'eingeschaltet'));
  Assert.IsTrue(ContainsText(Markdown, 'https://docwiki.embarcadero.com/RADStudio/Athens/en/Range_checking'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$RANGECHECKS OFF}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'ausgeschaltet'));
end;

procedure TCompilerDirectivesTests.SeveralSwitchesAreAllDescribed;
var
  Markdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R+,Q-}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'RANGECHECKS'));
  Assert.IsTrue(ContainsText(Markdown, 'OVERFLOWCHECKS'));
end;

procedure TCompilerDirectivesTests.FileDirectivesAreNotSwitches;
var
  Markdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$R *.res}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'RESOURCE'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$I Defines.inc}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'INCLUDE'));
  Assert.IsTrue(TCompilerDirectives.Describe('{$I-}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'IOCHECKS'));
end;

procedure TCompilerDirectivesTests.WarnNamesTheWarning;
var
  Markdown: string;
begin
  Assert.IsTrue(TCompilerDirectives.Describe('{$WARN SYMBOL_DEPRECATED OFF}', '37.0', Markdown));
  Assert.IsTrue(ContainsText(Markdown, 'SYMBOL_DEPRECATED'));
  Assert.IsTrue(ContainsText(Markdown, 'Warning_messages_(Delphi)'));
end;

procedure TCompilerDirectivesTests.UnknownDirectiveIsNotDescribed;
var
  Markdown: string;
begin
  Assert.IsFalse(TCompilerDirectives.Describe('{$GIBTSNICHT}', '37.0', Markdown));
end;

procedure TCompilerDirectivesTests.CompletesDirectiveNames;
var
  Names: TArray<string>;
  IsWarning: Boolean;
begin
  Assert.IsTrue(TCompilerDirectives.CompletionAt('  {$IFD', Names, IsWarning));
  Assert.IsFalse(IsWarning);
  Assert.IsTrue(MatchText('IFDEF', Names));
  Assert.IsTrue(TCompilerDirectives.CompletionAt('{$', Names, IsWarning));
end;

procedure TCompilerDirectivesTests.CompletesWarningsAfterWarn;
var
  Names: TArray<string>;
  IsWarning: Boolean;
begin
  Assert.IsTrue(TCompilerDirectives.CompletionAt('{$WARN SYM', Names, IsWarning));
  Assert.IsTrue(IsWarning);
  Assert.AreEqual(Length(TCompilerDirectives.Warnings), Length(Names));
  Assert.IsTrue(MatchText('SYMBOL_PLATFORM', Names));
  // Hinter dem Bezeichner (ON/OFF) nichts mehr.
  Assert.IsFalse(TCompilerDirectives.CompletionAt('{$WARN SYMBOL_PLATFORM O', Names, IsWarning));
end;

procedure TCompilerDirectivesTests.NoCompletionOutsideDirective;
var
  Names: TArray<string>;
  IsWarning: Boolean;
begin
  Assert.IsFalse(TCompilerDirectives.CompletionAt('  {$R+} Wert := ', Names, IsWarning));
  Assert.IsFalse(TCompilerDirectives.CompletionAt('  Wert := ', Names, IsWarning));
  Assert.IsFalse(TCompilerDirectives.CompletionAt('{$IFDEF DEBUG', Names, IsWarning));
end;

procedure TCompilerDirectivesTests.HoverFindsDirectiveToken;
var
  Tree: TSyntaxTree;
  Markdown: string;
  Position: TTextPosition;
begin
  Tree := TPascalParser.Parse('unit U;'#10'{$Q+}'#10'interface'#10'implementation'#10'end.');
  try
    Position.Line := 1;
    Position.Character := 2;
    Assert.IsTrue(TCompilerDirectives.HoverAt(Tree, Position, '37.0', Markdown));
    Assert.IsTrue(ContainsText(Markdown, 'OVERFLOWCHECKS'));
    Position.Line := 0;
    Assert.IsFalse(TCompilerDirectives.HoverAt(Tree, Position, '37.0', Markdown));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerDirectivesTests);

end.
