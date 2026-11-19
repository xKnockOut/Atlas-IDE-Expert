unit Atlas.Core.Assistants.ContextState.Tests;

// Zustand der IDE für KI-Assistenten (#2050): Schreiben erst nach Ruhe, nicht beim Tippen in derselben Methode;
// Auswahl mit Grenze und Schalter; letzter Build mit Art, Zahlen und maßgeblichen Meldungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantContextTests = class
  public
    [Test]
    procedure WritesAfterQuietTime;
    [Test]
    procedure SameKeyWritesOnce;
    [Test]
    procedure ForgetWritesAgain;
    [Test]
    procedure SelectionHonoursSwitchAndLimit;
    [Test]
    procedure BuildTakesVerdictAndMessages;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Text.IdeContext,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Assistants.ContextState;

procedure TAtlasAssistantContextTests.WritesAfterQuietTime;
var
  mPace: TAtlasContextPace;
begin
  mPace := Default(TAtlasContextPace);
  Assert.IsFalse(mPace.Due('a', 1000), 'neu: erst vormerken');
  Assert.IsFalse(mPace.Due('a', 1200), 'noch keine Ruhe');
  Assert.IsFalse(mPace.Due('b', 1400), 'Wechsel startet die Ruhe neu');
  Assert.IsFalse(mPace.Due('b', 1800));
  Assert.IsTrue(mPace.Due('b', 1900), 'nach 500 ms Ruhe');
end;

procedure TAtlasAssistantContextTests.SameKeyWritesOnce;
var
  mPace: TAtlasContextPace;
begin
  mPace := Default(TAtlasContextPace);
  mPace.Due('a', 0);
  Assert.IsTrue(mPace.Due('a', 600));
  Assert.IsFalse(mPace.Due('a', 1200), 'gleicher Stand: nicht nochmal');
  Assert.IsFalse(mPace.Due('b', 1300));
  Assert.IsFalse(mPace.Due('a', 1400), 'zurück zum geschriebenen Stand');
  Assert.IsFalse(mPace.Due('a', 2400));
end;

procedure TAtlasAssistantContextTests.ForgetWritesAgain;
var
  mPace: TAtlasContextPace;
begin
  mPace := Default(TAtlasContextPace);
  mPace.Due('a', 0);
  Assert.IsTrue(mPace.Due('a', 600));
  mPace.Forget;
  Assert.IsTrue(mPace.Due('a', 700), 'vorgemerkt seit 0, also ruhig genug');
end;

procedure TAtlasAssistantContextTests.SelectionHonoursSwitchAndLimit;
var
  mSelection: TIdeContextSelection;
begin
  mSelection := TAtlasAssistantContext.Selection(TAtlasAssistantContext.Range(3, 1, 4, 6), 'abcdef', True,
    4);
  Assert.AreEqual('abcd', mSelection.Text);
  Assert.IsTrue(mSelection.Truncated);
  Assert.AreEqual(6, mSelection.Length);
  Assert.AreEqual(4, mSelection.EndLine);
  mSelection := TAtlasAssistantContext.Selection(TAtlasAssistantContext.Range(3, 1, 4, 6), 'abcdef', False,
    4000);
  Assert.AreEqual('', mSelection.Text);
  Assert.IsTrue(mSelection.TextOmitted);
  Assert.AreEqual(6, mSelection.Length);
end;

procedure TAtlasAssistantContextTests.BuildTakesVerdictAndMessages;
var
  mProject: TAtlasCompileProject;
  mVerdict: TAtlasBuildVerdict;
  mHint, mError: TAtlasCompilerMessage;
  mBuild: TIdeContextBuild;
begin
  mProject := Default(TAtlasCompileProject);
  mProject.FileName := 'C:\Quellen\Kunde.dproj';
  mProject.Kind := TAtlasCompileKind.Check;
  mVerdict := Default(TAtlasBuildVerdict);
  mVerdict.Succeeded := False;
  mVerdict.Errors := 1;
  mVerdict.Hints := 1;
  mVerdict.Reason := TAtlasBuildVerdictReason.CompilerFailed;
  mHint := Default(TAtlasCompilerMessage);
  mHint.Severity := TAtlasCompilerSeverity.Hint;
  mHint.Text := 'Hinweis';
  mError := Default(TAtlasCompilerMessage);
  mError.Severity := TAtlasCompilerSeverity.Error;
  mError.FileName := 'C:\Quellen\Kunde.pas';
  mError.Line := 12;
  mError.Code := 'E2003';
  mError.Text := 'Undeklarierter Bezeichner';
  mBuild := TAtlasAssistantContext.Build([mHint, mError], mProject, mVerdict, EncodeDate(2026, 11, 18));
  Assert.IsTrue(mBuild.Known);
  Assert.AreEqual('check', mBuild.Kind);
  Assert.IsFalse(mBuild.Success);
  Assert.AreEqual(1, mBuild.Errors);
  Assert.AreEqual(1, Integer(Length(mBuild.Messages)), 'Hinweise fallen weg');
  Assert.AreEqual('error', mBuild.Messages[0].Severity);
  Assert.AreEqual(12, mBuild.Messages[0].Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantContextTests);

end.
