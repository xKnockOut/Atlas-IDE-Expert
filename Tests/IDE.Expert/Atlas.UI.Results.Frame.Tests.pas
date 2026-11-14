unit Atlas.UI.Results.Frame.Tests;

// Tests für das Ergebnisfenster mit Treffersicherheit (#1119): Abschnitte
// „Sicher“ und „Erschlossen“, Filter „Nur sichere“, Markierung und Hinweis
// erschlossener Zeilen und Aufrufer. Issues zu einer Methode (#1275).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasResultsFrameRatedTests = class
  public
    [Test]
    procedure WithoutInferredLikeShowEntries;
    [Test]
    procedure SectionsForSureAndInferred;
    [Test]
    procedure OnlySureHidesInferred;
    [Test]
    procedure MarksInferredEntriesAndCallers;
  end;

  /// <summary>Auswirkungsanalyse (#1120): Abschnitte, Baum nach Ursachen, Tiefe und Testlauf.</summary>
  [TestFixture]
  TAtlasResultsFrameImpactTests = class
  public
    /// <summary>Einmal vorab zeigen: Zwischenspeicher der ersten Benutzung (Texte, Symbole) zählen sonst als Leck.
    /// </summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure SectionsAndCauseTree;
    [Test]
    procedure DepthAndRunTestsCallBack;
    [Test]
    procedure TextsOfPlacesFormsAndLimits;
    [Test]
    procedure OtherListsHideImpactControls;
  end;

  /// <summary>Issues zu einer Methode (#1275): Issues mit Commits, Öffnen, Text nachtragen.</summary>
  [TestFixture]
  TAtlasResultsFrameIssueTests = class
  public
    [Test]
    procedure IssuesWithCommitsAndActions;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.UI.Results.Strings,
  Atlas.UI.Results.Texts,
  Atlas.UI.Results.Frame;

function Entry(const AFileName: string; ALine: Integer; const AText, AReason: string): TAtlasResultEntry;
begin
  Result := TAtlasResultEntry.Create(AFileName, ALine, 2);
  Result.Text := AText;
  if AReason <> '' then
  begin
    Result.Confidence.Inferred := True;
    Result.Confidence.Reason := AReason;
    Result.Confidence.Explanation := 'Erklärung ' + AReason;
  end;
end;

function Sample: TArray<TAtlasResultEntry>;
begin
  Result := TArray<TAtlasResultEntry>.Create(Entry('C:\P\Haupt.pas', 6, 'K.Speichern;', ''),
    Entry('C:\P\Haupt.pas', 7, 'S.Speichern;', 'interface'), Entry('C:\P\Kunden.pas', 16, 'procedure TKunde.Speichern;',
    ''), Entry('C:\P\Haupt.pas', 8, 'B.Speichern;', 'virtual'));
end;

procedure TAtlasResultsFrameRatedTests.WithoutInferredLikeShowEntries;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Entries.ShowRated('Verwendungen', TAtlasResults.SureOnly(Sample), 'Sicher (%d)', 'Erschlossen (%d)');
    Assert.IsFalse(mFrame.Entries.OnlySure.Visible);
    Assert.AreEqual(4, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual('Haupt.pas (1)', mFrame.Tree.Items[0].Text);
    Assert.AreEqual('7: K.Speichern;', mFrame.Tree.Items[1].Text);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.SectionsForSureAndInferred;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Entries.ShowRated('Verwendungen', Sample, 'Sicher (%d)', 'Erschlossen (%d)');
    Assert.IsTrue(mFrame.Entries.OnlySure.Visible);
    // Sicher (2): Haupt.pas (1), Kunden.pas (1); Erschlossen (2): Haupt.pas (2).
    Assert.AreEqual(9, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual('Sicher (2)', mFrame.Tree.Items[0].Text);
    Assert.AreEqual('Haupt.pas (1)', mFrame.Tree.Items[1].Text);
    Assert.AreEqual('Kunden.pas (1)', mFrame.Tree.Items[3].Text);
    Assert.AreEqual('Erschlossen (2)', mFrame.Tree.Items[5].Text);
    Assert.AreEqual('Haupt.pas (2)', mFrame.Tree.Items[6].Text);
    Assert.IsTrue(mFrame.Tree.Items[0].Expanded);
    Assert.IsTrue(mFrame.Tree.Items[5].Expanded);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.OnlySureHidesInferred;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Entries.ShowRated('Verwendungen', Sample, 'Sicher (%d)', 'Erschlossen (%d)');
    mFrame.Entries.OnlySure.Checked := True;
    // Der Filter bleibt sichtbar, damit er sich wieder ausschalten lässt.
    Assert.IsTrue(mFrame.Entries.OnlySure.Visible);
    Assert.AreEqual(4, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual('Haupt.pas (1)', mFrame.Tree.Items[0].Text);
    mFrame.Entries.OnlySure.Checked := False;
    Assert.AreEqual(9, Integer(mFrame.Tree.Items.Count));
    // Andere Listen blenden den Filter aus.
    mFrame.Entries.Show('Implementierungen', TAtlasResults.Group(TAtlasResults.SureOnly(Sample)));
    Assert.IsFalse(mFrame.Entries.OnlySure.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.MarksInferredEntriesAndCallers;
var
  mItem: TAtlasHierarchyItem;
  mText: string;
begin
  mText := TAtlasResultsTexts.EntryText(Entry('C:\P\Haupt.pas', 7, 'S.Speichern;', 'interface'));
  Assert.AreEqual('≈ 8: S.Speichern;  [' + TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonInterface) +
    ']', mText);
  Assert.AreEqual('7: K.Speichern;', TAtlasResultsTexts.EntryText(Entry('C:\P\Haupt.pas', 6, 'K.Speichern;', '')));
  // Unbekannte Gründe neuerer Server erscheinen wie geliefert.
  Assert.AreEqual('neu', TAtlasResultsTexts.ReasonText(Entry('A.pas', 0, '', 'neu').Confidence));
  mItem := Default(TAtlasHierarchyItem);
  mItem.Name := 'Lauf';
  mItem.FileName := 'C:\P\Haupt.pas';
  mItem.Line := 4;
  Assert.AreEqual('Lauf  (Haupt.pas:5)', TAtlasResultsTexts.HierarchyText(mItem));
  mItem.Confidence := Entry('A.pas', 0, '', 'virtual').Confidence;
  Assert.AreEqual('≈ Lauf  (Haupt.pas:5)  [' + TAtlasResultsStrings.Text(TAtlasResultsTextId.ReferenceReasonVirtual) +
    ']',
    TAtlasResultsTexts.HierarchyText(mItem));
end;

{ TAtlasResultsFrameImpactTests }

function Place(const AName, AFileName: string; ALine, ALevel, ACause: Integer): TAtlasImpactPlace;
begin
  Result := Default(TAtlasImpactPlace);
  Result.Item.Name := AName;
  Result.Item.FileName := AFileName;
  Result.Item.Line := ALine;
  Result.Level := ALevel;
  Result.Edge := 'call';
  Result.Cause := ACause;
  Result.UseLine := ALine + 2;
  Result.UseCount := 1;
end;

function SampleImpact: TAtlasImpact;
var
  mForm: TAtlasImpactForm;
  mTest: TAtlasImpactTest;
begin
  Result := Default(TAtlasImpact);
  Result.Symbol.Name := 'Ziel';
  Result.Depth := 2;
  Result.Places := TArray<TAtlasImpactPlace>.Create(Place('Hilfe', 'C:\P\Werkzeug.pas', 31, 1, -1),
    Place('Button1Click', 'C:\P\Haupt.pas', 9, 2, 0), Place('PrueftHilfe', 'C:\P\Werkzeug.Tests.pas', 11, 2, 0));
  Result.Places[0].UseCount := 2;
  mForm := Default(TAtlasImpactForm);
  mForm.FileName := 'C:\P\Haupt.dfm';
  mForm.Line := 2;
  mForm.Text := 'OnClick = Button1Click';
  Result.Places[1].Forms := TArray<TAtlasImpactForm>.Create(mForm);
  Result.Places[2].Test := 'Werkzeug.Tests.TWerkzeugTests.PrueftHilfe';
  mTest := Default(TAtlasImpactTest);
  mTest.Name := 'Werkzeug.Tests.TWerkzeugTests.PrueftHilfe';
  mTest.RunNames := TArray<string>.Create(mTest.Name);
  mTest.FileName := 'C:\P\Werkzeug.Tests.pas';
  mTest.Line := 11;
  mTest.Level := 2;
  Result.Tests := TArray<TAtlasImpactTest>.Create(mTest);
  Result.DepthReached := True;
  Result.Unexpanded := 2;
end;

procedure TAtlasResultsFrameImpactTests.WarmUp;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Impact.Show('Auswirkungen', SampleImpact);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsFrameImpactTests.SectionsAndCauseTree;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Impact.Show('Auswirkungen', SampleImpact);
    Assert.IsTrue(mFrame.Impact.Shows);
    // Direkt (1): Hilfe; Indirekt (2): Hilfe › Button1Click › Formular, PrueftHilfe; Tests (1); Grenze.
    Assert.AreEqual(10, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactDirect, [1]), mFrame.Tree.Items[0].Text);
    Assert.AreEqual('Hilfe  (Werkzeug.pas:32)  ×2', mFrame.Tree.Items[1].Text);
    Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactIndirect, [2]), mFrame.Tree.Items[2].Text);
    Assert.AreEqual(2, mFrame.Tree.Items[4].Level, 'Button1Click unter Hilfe');
    Assert.AreEqual(3, mFrame.Tree.Items[5].Level, 'Formular unter dem Handler');
    Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactForm, ['OnClick = Button1Click', 'Haupt.dfm',
      3]),
      mFrame.Tree.Items[5].Text);
    Assert.AreEqual('PrueftHilfe  (Werkzeug.Tests.pas:12)  · Test', mFrame.Tree.Items[6].Text);
    Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactTests, [1]), mFrame.Tree.Items[7].Text);
    Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe  (Werkzeug.Tests.pas:12)', mFrame.Tree.Items[8].Text);
    Assert.AreEqual('⚠ ' + TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactLimitDepth, [2, 2]),
      mFrame.Tree.Items[9].Text);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasResultsFrameImpactTests.DepthAndRunTestsCallBack;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mDepth: Integer;
  mNames: TArray<string>;
begin
  mDepth := 0;
  mNames := nil;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Impact.OnDepth :=
      procedure(ADepth: Integer)
      begin
        mDepth := ADepth;
      end;
    mFrame.Impact.OnRunTests :=
      procedure(const AImpact: TAtlasImpact)
      begin
        mNames := AImpact.RunNames;
      end;
    mFrame.Impact.Show('Auswirkungen', SampleImpact);
    Assert.IsTrue(mFrame.Impact.DepthBox.Visible);
    Assert.AreEqual(5, Integer(mFrame.Impact.DepthBox.Items.Count));
    Assert.AreEqual(1, mFrame.Impact.DepthBox.ItemIndex, 'Tiefe 2');
    Assert.AreEqual(0, mDepth, 'Anzeigen löst keine neue Anfrage aus');
    mFrame.Impact.DepthBox.ItemIndex := 3;
    mFrame.Impact.DepthBox.OnChange(mFrame.Impact.DepthBox);
    Assert.AreEqual(4, mDepth);
    Assert.IsTrue(mFrame.Impact.RunTestsButton.Enabled);
    mFrame.Impact.RunTestsButton.Click;
    Assert.AreEqual(1, Integer(Length(mNames)));
    Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', mNames[0]);
  finally
    mHost.Free;
  end;
  mNames := nil;
end;

procedure TAtlasResultsFrameImpactTests.TextsOfPlacesFormsAndLimits;
var
  mItem: TAtlasImpactPlace;
  mImpact: TAtlasImpact;
  mLimits: TArray<string>;
begin
  mItem := Place('TKind', 'C:\P\Werkzeug.pas', 10, 1, -1);
  mItem.Edge := 'override';
  Assert.AreEqual('TKind  (Werkzeug.pas:11)  · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeOverride),
    TAtlasResultsTexts.ImpactPlaceText(mItem));
  mItem.Edge := 'reference';
  mItem.Terminal := True;
  mItem.Item.Name := 'Haupt';
  Assert.AreEqual('Haupt · ' + TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactUnitLevel) +
    '  (Werkzeug.pas:13)  · ' +
    TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactEdgeReference), TAtlasResultsTexts.ImpactPlaceText(mItem));
  mImpact := Default(TAtlasImpact);
  mImpact.CountReached := True;
  mImpact.MaxPlaces := 1000;
  mImpact.TimeReached := True;
  mImpact.TimeoutMs := 8000;
  mLimits := TAtlasResultsTexts.ImpactLimitTexts(mImpact);
  Assert.AreEqual(2, Integer(Length(mLimits)));
  Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactLimitCount, [1000]), mLimits[0]);
  Assert.AreEqual(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ImpactLimitTime, [8000]), mLimits[1]);
  mLimits := nil;
end;

procedure TAtlasResultsFrameImpactTests.OtherListsHideImpactControls;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mImpact: TAtlasImpact;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mImpact := SampleImpact;
    mImpact.Tests := nil;
    mFrame.Impact.Show('Auswirkungen', mImpact);
    Assert.IsFalse(mFrame.Impact.RunTestsButton.Enabled, 'ohne Tests nichts auszuführen');
    Assert.AreEqual(TAtlasResultsStrings.Text(TAtlasResultsTextId.ImpactNoTests), mFrame.Tree.Items[7].Text);
    mFrame.Entries.Show('Implementierungen', TAtlasResults.Group(Sample));
    Assert.IsFalse(mFrame.Impact.Shows);
    Assert.IsFalse(mFrame.Impact.DepthBox.Visible);
    Assert.IsFalse(mFrame.Impact.RunTestsButton.Visible);
  finally
    mHost.Free;
  end;
end;

{ TAtlasResultsFrameIssueTests }

function Issue(AId: Integer; const AText: string; const ACommits: TArray<string>): TAtlasResultIssue;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasResultIssue);
  Result.Id := AId;
  Result.Text := AText;
  SetLength(Result.Commits, Length(ACommits));
  for mIndex := 0 to High(ACommits) do
  begin
    Result.Commits[mIndex].Id := AId * 10 + mIndex;
    Result.Commits[mIndex].Text := ACommits[mIndex];
  end;
end;

procedure TAtlasResultsFrameIssueTests.IssuesWithCommitsAndActions;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mOpened, mShown: string;
begin
  mOpened := '';
  mShown := '';
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Issues.OnOpen :=
      procedure(AList, AId: Integer)
      begin
        mOpened := mOpened + Format('%d/%d ', [AList, AId]);
      end;
    mFrame.Issues.OnCommit :=
      procedure(AList, AId: Integer)
      begin
        mShown := mShown + Format('%d/%d ', [AList, AId]);
      end;
    mFrame.Issues.Show('Issues zu TKunde.Laden', 7, TArray<TAtlasResultIssue>.Create(
      Issue(0, 'ATL-3 · 2 Commits', TArray<string>.Create('c1', 'c2')),
      Issue(1, 'ATL-1 · 1 Commit', TArray<string>.Create('c3'))));
    Assert.IsTrue(mFrame.Issues.Shows);
    Assert.AreEqual(5, Integer(mFrame.Tree.Items.Count));
    Assert.AreEqual('ATL-3 · 2 Commits', mFrame.Tree.Items[0].Text);
    Assert.IsFalse(mFrame.Tree.Items[0].Expanded, 'Commits zugeklappt');
    Assert.AreEqual('c2', mFrame.Tree.Items[2].Text);
    // Enter auf dem Issue öffnet es, auf dem Commit zeigt es den Commit.
    mFrame.Tree.Selected := mFrame.Tree.Items[3];
    mFrame.Issues.OpenSelected;
    mFrame.Tree.Selected := mFrame.Tree.Items[2];
    mFrame.Issues.OpenSelected;
    Assert.AreEqual('7/1 ', mOpened);
    Assert.AreEqual('7/1 ', mShown);
    // Titel nachtragen: nur für die gezeigte Liste.
    Assert.IsTrue(mFrame.Issues.SetText(7, 1, 'ATL-1 · Rabatt · Offen · 1 Commit'));
    Assert.AreEqual('ATL-1 · Rabatt · Offen · 1 Commit', mFrame.Tree.Items[3].Text);
    Assert.IsFalse(mFrame.Issues.SetText(8, 1, 'alt'), 'andere Liste');
    Assert.IsFalse(mFrame.Issues.SetText(7, 5, 'fehlt'));
    mFrame.Entries.Show('Andere Liste', nil);
    Assert.IsFalse(mFrame.Issues.Shows);
    Assert.IsFalse(mFrame.Issues.SetText(7, 1, 'weg'));
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameRatedTests);
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameImpactTests);
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameIssueTests);

end.
