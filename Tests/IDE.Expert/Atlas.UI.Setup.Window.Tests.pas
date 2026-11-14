unit Atlas.UI.Setup.Window.Tests;

// Fenster „Atlas-Einrichtung“ (#625): Texte je Befund, ein Knopf je gelbem
// oder rotem Punkt, „Warum?“ erklärt im Fenster, die übrigen Knöpfe rufen
// OnFix, Unterzeilen je Projekt mit Balken, Prozent und Stufe (#2142), Bericht
// und Einstieg „Probier es aus“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSetupWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextsFollowFindings;
    [Test]
    procedure ButtonOnlyForNonGreenPoints;
    [Test]
    procedure FixButtonCallsOnFix;
    [Test]
    procedure WhyExplainsInTheWindow;
    [Test]
    procedure ProjectsBecomeSubLines;
    /// <summary>#2142: Stand je Projekt mit Prozent, Stufe oder „wartet“ und Füllung des Balkens.</summary>
    [Test]
    procedure ProjectStatusShowsPercentAndStage;
    [Test]
    procedure ReportLinesAndProgress;
    [Test]
    procedure ShowAtStartWithoutEcho;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Setup.Checklist,
  Atlas.UI.Strings,
  Atlas.UI.Setup.Strings,
  Atlas.UI.Setup.Window;

var
  Language: TAtlasLanguage;

function Input: TAtlasSetupInput;
var
  mWorkspace: TAtlasSetupWorkspace;
begin
  Result := Default(TAtlasSetupInput);
  Result.ServerFound := True;
  Result.Server.Phase := TAtlasServerPhase.Running;
  Result.Server.Version := '0.1.0';
  Result.PluginVersion := '0.1.0';
  Result.BdsVersion := '37.0';
  Result.Platform := 'Win64';
  Result.Projects := ['Kunden', 'Export'];
  Result.Status.Known := True;
  Result.Status.Units := 1569;
  mWorkspace := Default(TAtlasSetupWorkspace);
  mWorkspace.Name := 'Kunden';
  mWorkspace.Done := True;
  mWorkspace.LibraryCacheBytes := 0;
  Result.Status.Workspaces := [mWorkspace];
  Result.ErrorInsight := True;
  Result.AtlasProblems := True;
end;

procedure TAtlasSetupWindowTests.WarmUpFirstUse;
begin
  Setup;
  try
    ButtonOnlyForNonGreenPoints;
  finally
    TearDown;
  end;
end;

procedure TAtlasSetupWindowTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasSetupWindowTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasSetupWindowTests.TextsFollowFindings;
var
  mResults: TArray<TAtlasSetupResult>;
begin
  mResults := TAtlasSetupChecklist.Evaluate(Input);
  Assert.AreEqual('Server gefunden, gestartet, Version passt', TAtlasSetupTexts.ResultText(mResults[0]));
  Assert.AreEqual('AtlasServer 0.1.0', TAtlasSetupTexts.DetailText(mResults[0]));
  Assert.AreEqual('Delphi 13 (37.0) erkannt', TAtlasSetupTexts.ResultText(mResults[1]));
  Assert.AreEqual('Plattform Win64', TAtlasSetupTexts.DetailText(mResults[1]));
  Assert.AreEqual('Projektgruppe: 1 von 2 Projekten nicht im Index (Export)',
    TAtlasSetupTexts.ResultText(mResults[2]));
  Assert.AreEqual('Bibliotheks-Cache fehlt, erster Start dauert länger', TAtlasSetupTexts.ResultText(mResults[3]));
  Assert.AreEqual('Error Insight der IDE ist noch an (doppelte Meldungen)', TAtlasSetupTexts.ResultText(mResults[4]));
  Assert.AreEqual('Tastenkürzel ohne Konflikt', TAtlasSetupTexts.ResultText(mResults[5]));
  Assert.AreEqual('Server-Pfad wählen…', TAtlasSetupTexts.FixCaption(TAtlasSetupFix.ChooseServerPath));
  Assert.AreEqual('Index neu aufbauen', TAtlasSetupTexts.FixCaption(TAtlasSetupFix.RebuildIndex));
  Assert.AreEqual('Error Insight abschalten', TAtlasSetupTexts.FixCaption(TAtlasSetupFix.DisableErrorInsight));
  Assert.AreEqual('', TAtlasSetupTexts.FixCaption(TAtlasSetupFix.None));
end;

procedure TAtlasSetupWindowTests.ButtonOnlyForNonGreenPoints;
var
  mWindow: TAtlasSetupWindow;
  mResults: TArray<TAtlasSetupResult>;
  mIndex: Integer;
begin
  mResults := TAtlasSetupChecklist.Evaluate(Input);
  mWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    mWindow.SetResults(mResults);
    for mIndex := 0 to High(mResults) do
    begin
      Assert.AreEqual<Boolean>(mResults[mIndex].State <> TAtlasStatusState.Green, mWindow.FixButtons[mIndex].Visible,
        'Knopf genau bei gelb oder rot: ' + IntToStr(mIndex));
    end;
    Assert.AreEqual('Jetzt aufbauen', mWindow.FixButtons[3].Caption);
    Assert.AreEqual(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupCopy), mWindow.CopyButton.Caption);
    Assert.AreEqual(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupRecheck), mWindow.RecheckButton.Caption);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSetupWindowTests.FixButtonCallsOnFix;
var
  mWindow: TAtlasSetupWindow;
  mFixed: TAtlasSetupFix;
  mCopied, mRechecked: Integer;
begin
  mFixed := TAtlasSetupFix.None;
  mCopied := 0;
  mRechecked := 0;
  mWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Dark);
  try
    mWindow.SetResults(TAtlasSetupChecklist.Evaluate(Input));
    mWindow.OnFix :=
      procedure(AResult: TAtlasSetupResult)
      begin
        mFixed := AResult.Fix;
      end;
    mWindow.OnCopy :=
      procedure
      begin
        Inc(mCopied);
      end;
    mWindow.OnRecheck :=
      procedure
      begin
        Inc(mRechecked);
      end;
    mWindow.FixButtons[4].Click;
    Assert.AreEqual(Ord(TAtlasSetupFix.DisableErrorInsight), Ord(mFixed));
    mWindow.CopyButton.Click;
    mWindow.RecheckButton.Click;
    Assert.AreEqual(1, mCopied);
    Assert.AreEqual(1, mRechecked);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSetupWindowTests.WhyExplainsInTheWindow;
var
  mWindow: TAtlasSetupWindow;
  mData: TAtlasSetupInput;
  mCalled: Boolean;
  mHeight_: Integer;
begin
  mData := Input;
  mData.Platform := '';
  mCalled := False;
  mWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    mWindow.SetResults(TAtlasSetupChecklist.Evaluate(mData));
    mWindow.OnFix :=
      procedure(AResult: TAtlasSetupResult)
      begin
        mCalled := True;
      end;
    mHeight_ := mWindow.ClientHeight;
    Assert.AreEqual('Warum?', mWindow.FixButtons[1].Caption);
    mWindow.FixButtons[1].Click;
    Assert.IsFalse(mCalled, '„Warum?“ erklärt nur');
    Assert.AreEqual(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyDelphiNoProject), mWindow.Note);
    Assert.IsTrue(mWindow.ClientHeight > mHeight_, 'Platz für die Erklärung');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSetupWindowTests.ProjectsBecomeSubLines;
var
  mWindow: TAtlasSetupWindow;
  mData: TAtlasSetupInput;
  mHeight1: Integer;
begin
  mData := Input;
  mData.Projects := nil;
  mWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    mData.Status.Workspaces := nil;
    mWindow.SetResults(TAtlasSetupChecklist.Evaluate(mData));
    mHeight1 := mWindow.ClientHeight;
    mWindow.SetResults(TAtlasSetupChecklist.Evaluate(Input));
    Assert.IsTrue(mWindow.ClientHeight > mHeight1, 'zwei Projektzeilen unter dem Index');
    Assert.AreEqual('Kunden: fertig', TAtlasSetupTexts.ProjectText(mWindow.Results[2].Projects[0]));
    Assert.AreEqual('Export: fehlt im Index', TAtlasSetupTexts.ProjectText(mWindow.Results[2].Projects[1]));
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasSetupWindowTests.ProjectStatusShowsPercentAndStage;
var
  mProject: TAtlasSetupProject;
begin
  mProject := TAtlasSetupProject.Create('Lager', TAtlasSetupProjectState.Building);
  Assert.AreEqual('wird aufgebaut', TAtlasSetupTexts.ProjectStatus(mProject), 'älterer Server');
  Assert.AreEqual(0, TAtlasSetupTexts.ProjectBar(mProject), 'leere Spur');
  mProject.Indexing.Active := True;
  mProject.Indexing.Percent := 62;
  mProject.Indexing.Stage := TAtlasSetupIndexStage.SearchPaths;
  Assert.AreEqual('62 % · Suchpfade', TAtlasSetupTexts.ProjectStatus(mProject));
  Assert.AreEqual('Lager: 62 % · Suchpfade', TAtlasSetupTexts.ProjectText(mProject));
  Assert.AreEqual(62, TAtlasSetupTexts.ProjectBar(mProject));
  mProject.Indexing.Waiting := True;
  mProject.Indexing.Percent := 18;
  Assert.AreEqual('18 % · wartet', TAtlasSetupTexts.ProjectStatus(mProject));
  mProject.Indexing.Waiting := False;
  mProject.Indexing.Percent := -1;
  mProject.Indexing.Stage := TAtlasSetupIndexStage.Library_;
  Assert.AreEqual('Bibliothek', TAtlasSetupTexts.ProjectStatus(mProject));
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('library', TAtlasSetupTexts.ProjectStatus(mProject));
  TAtlasStrings.Language := TAtlasLanguage.German;
  Assert.AreEqual(100, TAtlasSetupTexts.ProjectBar(TAtlasSetupProject.Create('Kunden',
    TAtlasSetupProjectState.Done)));
  Assert.AreEqual(-1, TAtlasSetupTexts.ProjectBar(TAtlasSetupProject.Create('Neu',
    TAtlasSetupProjectState.Missing)), 'fehlt: kein Balken');
end;

procedure TAtlasSetupWindowTests.ReportLinesAndProgress;
var
  mResults: TArray<TAtlasSetupResult>;
  mLines: TArray<TAtlasSetupReportLine>;
begin
  mResults := TAtlasSetupChecklist.Evaluate(Input);
  Assert.AreEqual('3 von 6 erledigt', TAtlasSetupTexts.ProgressText(mResults));
  mLines := TAtlasSetupTexts.ReportLines(mResults);
  // Sechs Prüfungen und zwei Projekte.
  Assert.AreEqual(8, Integer(Length(mLines)));
  Assert.AreEqual('Server gefunden, gestartet, Version passt (AtlasServer 0.1.0)', mLines[0].Text);
  Assert.IsTrue(mLines[3].Indent);
  Assert.AreEqual('Kunden: fertig', mLines[3].Text);
end;

procedure TAtlasSetupWindowTests.ShowAtStartWithoutEcho;
var
  mWindow: TAtlasSetupWindow;
  mCalls: Integer;
  mLast: Boolean;
begin
  mCalls := 0;
  mLast := True;
  mWindow := TAtlasSetupWindow.CreateSetup(nil, TAtlasColors.Light);
  try
    mWindow.OnShowAtStart :=
      procedure(AValue: Boolean)
      begin
        Inc(mCalls);
        mLast := AValue;
      end;
    mWindow.SetShowAtStart(False);
    Assert.AreEqual(0, mCalls, 'Setzen aus der IDE-Schicht meldet nichts zurück');
    Assert.IsFalse(mWindow.ShowAtStartBox.Checked);
    mWindow.ShowAtStartBox.Checked := True;
    Assert.AreEqual(1, mCalls);
    Assert.IsTrue(mLast);
    mWindow.SetTryKey('Strg+J');
    Assert.AreEqual('Strg+J', mWindow.TryKey);
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSetupWindowTests);

end.
