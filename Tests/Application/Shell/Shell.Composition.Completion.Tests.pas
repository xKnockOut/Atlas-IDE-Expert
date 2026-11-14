unit Shell.Composition.Completion.Tests;

// Vervollständigung des Servers: Abgleich und Postfix-Vorlagen folgen den Einstellungen und dem Sprachstand, die
// die Komposition als Dienste hereinreicht.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract,
  Shell.Composition.Completion;

type
  [TestFixture]
  TShellCompletionTests = class
  private
    FLevel: string;
    FPostfix: Boolean;
    function NewServices: TShellCompletionServices;
    function CompletionSettings(const AUri: string): TCompletionSettings;
    function RefactoringSettings(const AUri: string): TRefactoringSettings;
    function LanguageLevel(const AUri: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Der Abgleich kommt aus den Einstellungen der Vervollständigung.</summary>
    [Test]
    procedure MatchingFromSettings;
    /// <summary>Ab Delphi 10.3 mit refactoring.inlineVar erzeugen die Postfix-Vorlagen Inline-Variablen.</summary>
    [Test]
    procedure PostfixInlineVarFromLevel20;
    /// <summary>Vor Delphi 10.3 keine Inline-Variablen.</summary>
    [Test]
    procedure PostfixWithoutInlineVarBeforeLevel20;
    /// <summary>Abgeschaltete Postfix-Vorlagen bleiben aus.</summary>
    [Test]
    procedure PostfixOff;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion;

const
  cUri = 'file:///tmp/A.pas';

procedure TShellCompletionTests.Setup;
begin
  FLevel := '23.0';
  FPostfix := True;
end;

procedure TShellCompletionTests.TearDown;
begin
  FLevel := '';
end;

function TShellCompletionTests.CompletionSettings(const AUri: string): TCompletionSettings;
begin
  Result := TCompletionSettings.Default;
  Result.Matching := TCompletionMatching.Prefix;
  Result.PostfixTemplates := FPostfix;
end;

function TShellCompletionTests.RefactoringSettings(const AUri: string): TRefactoringSettings;
begin
  Result := TRefactoringSettings.Default;
  Result.InlineVar := True;
end;

function TShellCompletionTests.LanguageLevel(const AUri: string): string;
begin
  Result := FLevel;
end;

function TShellCompletionTests.NewServices: TShellCompletionServices;
begin
  Result := Default(TShellCompletionServices);
  Result.CompletionSettingsFor := CompletionSettings;
  Result.RefactoringSettingsFor := RefactoringSettings;
  Result.LanguageLevelFor := LanguageLevel;
end;

procedure TShellCompletionTests.MatchingFromSettings;
var
  mCompletion: TShellCompletion;
begin
  mCompletion := TShellCompletion.Create(NewServices);
  try
    Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Prefix, mCompletion.Completion.Hooks.MatchingFor(cUri));
  finally
    mCompletion.Free;
  end;
end;

procedure TShellCompletionTests.PostfixInlineVarFromLevel20;
var
  mCompletion: TShellCompletion;
  mOptions: TPostfixOptions;
begin
  FLevel := '20.0';
  mCompletion := TShellCompletion.Create(NewServices);
  try
    mOptions := mCompletion.Completion.Hooks.PostfixFor(cUri);
    Assert.IsTrue(mOptions.Enabled);
    Assert.IsTrue(mOptions.InlineVar);
  finally
    mCompletion.Free;
  end;
end;

procedure TShellCompletionTests.PostfixWithoutInlineVarBeforeLevel20;
var
  mCompletion: TShellCompletion;
  mOptions: TPostfixOptions;
begin
  FLevel := '19.0';
  mCompletion := TShellCompletion.Create(NewServices);
  try
    mOptions := mCompletion.Completion.Hooks.PostfixFor(cUri);
    Assert.IsTrue(mOptions.Enabled);
    Assert.IsFalse(mOptions.InlineVar);
  finally
    mCompletion.Free;
  end;
end;

procedure TShellCompletionTests.PostfixOff;
var
  mCompletion: TShellCompletion;
begin
  FPostfix := False;
  mCompletion := TShellCompletion.Create(NewServices);
  try
    Assert.IsFalse(mCompletion.Completion.Hooks.PostfixFor(cUri).Enabled);
  finally
    mCompletion.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompletionTests);

end.
