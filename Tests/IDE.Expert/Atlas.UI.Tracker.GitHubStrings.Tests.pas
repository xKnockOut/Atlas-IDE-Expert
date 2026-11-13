unit Atlas.UI.Tracker.GitHubStrings.Tests;

// Texte des GitHub-Anbieters im Tracker (#2135): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasGitHubStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
    /// <summary>Zeilen zum Status im Projekt (#2134).</summary>
    [Test]
    procedure ProjectLines;
    /// <summary>Zeile zum verknüpften Branch (#2138).</summary>
    [Test]
    procedure LinkLine;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests,
  Atlas.UI.Tracker.GitHubStrings;

procedure TAtlasGitHubStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasGitHubTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasGitHubTextId) to High(TAtlasGitHubTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasGitHubStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasGitHubStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasGitHubStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasGitHubTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Moduls.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasGitHubTextId) to High(TAtlasGitHubTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasGitHubStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasGitHubStrings.Text(mId) then
      begin
        Inc(mDiffers);
      end;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.IsTrue(mDiffers > 0, 'kein Text folgt der Sprache von Base');
end;

procedure TAtlasGitHubStringsTests.ProjectLines;
var
  mStatus: TAtlasTrackerProjectStatus;
  mSaved: TAtlasLanguage;
  mLines: TArray<string>;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mStatus := Default(TAtlasTrackerProjectStatus);
    Assert.AreEqual(0, Integer(Length(TAtlasGitHubStrings.ProjectLines('#7', mStatus))), 'kein Projekt berührt');
    mStatus.Project := 'Atlas 2.1';
    mStatus.After := 'In Progress';
    mStatus.Added := True;
    mStatus.Several := True;
    mLines := TAtlasGitHubStrings.ProjectLines('#7', mStatus);
    Assert.AreEqual(3, Integer(Length(mLines)));
    Assert.AreEqual('#7: in das Projekt „Atlas 2.1“ aufgenommen', mLines[0]);
    Assert.IsTrue(Pos('issues.github.project', mLines[1]) > 0, mLines[1]);
    Assert.AreEqual('#7: Status im Projekt „Atlas 2.1“ auf In Progress gesetzt', mLines[2]);
    mStatus := Default(TAtlasTrackerProjectStatus);
    mStatus.Project := 'Atlas 2.1';
    mStatus.Before := 'todo';
    mStatus.After := 'Todo';
    mLines := TAtlasGitHubStrings.ProjectLines('#7', mStatus);
    Assert.AreEqual('#7: Status im Projekt „Atlas 2.1“ ist schon Todo', mLines[0]);
    mStatus := Default(TAtlasTrackerProjectStatus);
    mStatus.Denied := True;
    TAtlasStrings.Language := TAtlasLanguage.English;
    mLines := TAtlasGitHubStrings.ProjectLines('#7', mStatus);
    Assert.AreEqual('#7: projects not readable (token without "project" scope), state set as a label', mLines[0]);
    // Fehlende Option: der Fehler sagt es, keine Zeile.
    mStatus := Default(TAtlasTrackerProjectStatus);
    mStatus.Project := 'Atlas 2.1';
    mStatus.MissingOption := 'In Arbeit';
    Assert.AreEqual(0, Integer(Length(TAtlasGitHubStrings.ProjectLines('#7', mStatus))));
  finally
    TAtlasStrings.Language := mSaved;
  end;
  mLines := nil;
end;

procedure TAtlasGitHubStringsTests.LinkLine;
var
  mLink: TAtlasTrackerBranchLink;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mLink := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.None, 'f/7-x');
    Assert.AreEqual('', TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', '', mLink, True));
    mLink.Outcome := TAtlasTrackerBranchLinkOutcome.Created;
    Assert.AreEqual('#7: Branch f/7-x auf GitHub angelegt und mit dem Issue verknüpft',
      TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', '', mLink, True));
    Assert.AreEqual('#7: Branch f/7-x liegt auf GitHub, Abruf oder Auschecken scheiterte (Failed); ' +
      'Branch nur lokal angelegt', TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', 'Failed', mLink, False));
    mLink.Outcome := TAtlasTrackerBranchLinkOutcome.Foreign;
    Assert.AreEqual('#7: origin ist nicht das Repository beispiel/atlas; Branch nur lokal angelegt',
      TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', '', mLink, True));
    TAtlasStrings.Language := TAtlasLanguage.English;
    mLink.Outcome := TAtlasTrackerBranchLinkOutcome.Exists;
    Assert.AreEqual('#7: branch f/7-x already exists; not linked to the issue',
      TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', '', mLink, True));
    mLink.Outcome := TAtlasTrackerBranchLinkOutcome.Failed;
    Assert.AreEqual('#7: branch not created on GitHub (offline); branch created locally only',
      TAtlasGitHubStrings.LinkLine('#7', 'beispiel/atlas', 'offline', mLink, True));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGitHubStringsTests);

end.
