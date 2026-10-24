unit Atlas.UI.Results.Frame.Tests;

// Tests für das Ergebnisfenster mit Treffersicherheit (#1119): Abschnitte
// „Sicher“ und „Erschlossen“, Filter „Nur sichere“, Markierung und Hinweis
// erschlossener Zeilen und Aufrufer.

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
    [Test]
    procedure SectionsAndCauseTree;
    [Test]
    procedure DepthAndRunTestsCallBack;
    [Test]
    procedure TextsOfPlacesFormsAndLimits;
    [Test]
    procedure OtherListsHideImpactControls;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Results.Model,
  Atlas.Core.Lsp.Contract,
  Atlas.UI.Strings,
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
  Host: TForm;
  Frame: TAtlasResultsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.ShowRated('Verwendungen', TAtlasResults.SureOnly(Sample), 'Sicher (%d)', 'Erschlossen (%d)');
    Assert.IsFalse(Frame.OnlySure.Visible);
    Assert.AreEqual(4, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual('Haupt.pas (1)', Frame.Tree.Items[0].Text);
    Assert.AreEqual('7: K.Speichern;', Frame.Tree.Items[1].Text);
  finally
    Host.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.SectionsForSureAndInferred;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.ShowRated('Verwendungen', Sample, 'Sicher (%d)', 'Erschlossen (%d)');
    Assert.IsTrue(Frame.OnlySure.Visible);
    // Sicher (2): Haupt.pas (1), Kunden.pas (1); Erschlossen (2): Haupt.pas (2).
    Assert.AreEqual(9, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual('Sicher (2)', Frame.Tree.Items[0].Text);
    Assert.AreEqual('Haupt.pas (1)', Frame.Tree.Items[1].Text);
    Assert.AreEqual('Kunden.pas (1)', Frame.Tree.Items[3].Text);
    Assert.AreEqual('Erschlossen (2)', Frame.Tree.Items[5].Text);
    Assert.AreEqual('Haupt.pas (2)', Frame.Tree.Items[6].Text);
    Assert.IsTrue(Frame.Tree.Items[0].Expanded);
    Assert.IsTrue(Frame.Tree.Items[5].Expanded);
  finally
    Host.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.OnlySureHidesInferred;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.ShowRated('Verwendungen', Sample, 'Sicher (%d)', 'Erschlossen (%d)');
    Frame.OnlySure.Checked := True;
    // Der Filter bleibt sichtbar, damit er sich wieder ausschalten lässt.
    Assert.IsTrue(Frame.OnlySure.Visible);
    Assert.AreEqual(4, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual('Haupt.pas (1)', Frame.Tree.Items[0].Text);
    Frame.OnlySure.Checked := False;
    Assert.AreEqual(9, Integer(Frame.Tree.Items.Count));
    // Andere Listen blenden den Filter aus.
    Frame.ShowEntries('Implementierungen', TAtlasResults.Group(TAtlasResults.SureOnly(Sample)));
    Assert.IsFalse(Frame.OnlySure.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasResultsFrameRatedTests.MarksInferredEntriesAndCallers;
var
  Item: TAtlasHierarchyItem;
  Text: string;
begin
  Text := TAtlasResultsFrame.EntryText(Entry('C:\P\Haupt.pas', 7, 'S.Speichern;', 'interface'));
  Assert.AreEqual('≈ 8: S.Speichern;  [' + TAtlasStrings.Text(TAtlasTextId.ReferenceReasonInterface) + ']', Text);
  Assert.AreEqual('7: K.Speichern;', TAtlasResultsFrame.EntryText(Entry('C:\P\Haupt.pas', 6, 'K.Speichern;', '')));
  // Unbekannte Gründe neuerer Server erscheinen wie geliefert.
  Assert.AreEqual('neu', TAtlasResultsFrame.ReasonText(Entry('A.pas', 0, '', 'neu').Confidence));
  Item := Default(TAtlasHierarchyItem);
  Item.Name := 'Lauf';
  Item.FileName := 'C:\P\Haupt.pas';
  Item.Line := 4;
  Assert.AreEqual('Lauf  (Haupt.pas:5)', TAtlasResultsFrame.HierarchyText(Item));
  Item.Confidence := Entry('A.pas', 0, '', 'virtual').Confidence;
  Assert.AreEqual('≈ Lauf  (Haupt.pas:5)  [' + TAtlasStrings.Text(TAtlasTextId.ReferenceReasonVirtual) + ']',
    TAtlasResultsFrame.HierarchyText(Item));
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
  Form: TAtlasImpactForm;
  Test: TAtlasImpactTest;
begin
  Result := Default(TAtlasImpact);
  Result.Symbol.Name := 'Ziel';
  Result.Depth := 2;
  Result.Places := TArray<TAtlasImpactPlace>.Create(Place('Hilfe', 'C:\P\Werkzeug.pas', 31, 1, -1),
    Place('Button1Click', 'C:\P\Haupt.pas', 9, 2, 0), Place('PrueftHilfe', 'C:\P\Werkzeug.Tests.pas', 11, 2, 0));
  Result.Places[0].UseCount := 2;
  Form := Default(TAtlasImpactForm);
  Form.FileName := 'C:\P\Haupt.dfm';
  Form.Line := 2;
  Form.Text := 'OnClick = Button1Click';
  Result.Places[1].Forms := TArray<TAtlasImpactForm>.Create(Form);
  Result.Places[2].Test := 'Werkzeug.Tests.TWerkzeugTests.PrueftHilfe';
  Test := Default(TAtlasImpactTest);
  Test.Name := 'Werkzeug.Tests.TWerkzeugTests.PrueftHilfe';
  Test.RunNames := TArray<string>.Create(Test.Name);
  Test.FileName := 'C:\P\Werkzeug.Tests.pas';
  Test.Line := 11;
  Test.Level := 2;
  Result.Tests := TArray<TAtlasImpactTest>.Create(Test);
  Result.DepthReached := True;
  Result.Unexpanded := 2;
end;

procedure TAtlasResultsFrameImpactTests.SectionsAndCauseTree;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.ShowImpact('Auswirkungen', SampleImpact);
    Assert.IsTrue(Frame.ShowsImpact);
    // Direkt (1): Hilfe; Indirekt (2): Hilfe › Button1Click › Formular, PrueftHilfe; Tests (1); Grenze.
    Assert.AreEqual(10, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactDirect, [1]), Frame.Tree.Items[0].Text);
    Assert.AreEqual('Hilfe  (Werkzeug.pas:32)  ×2', Frame.Tree.Items[1].Text);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactIndirect, [2]), Frame.Tree.Items[2].Text);
    Assert.AreEqual(2, Frame.Tree.Items[4].Level, 'Button1Click unter Hilfe');
    Assert.AreEqual(3, Frame.Tree.Items[5].Level, 'Formular unter dem Handler');
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactForm, ['OnClick = Button1Click', 'Haupt.dfm', 3]),
      Frame.Tree.Items[5].Text);
    Assert.AreEqual('PrueftHilfe  (Werkzeug.Tests.pas:12)  · Test', Frame.Tree.Items[6].Text);
    Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactTests, [1]), Frame.Tree.Items[7].Text);
    Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe  (Werkzeug.Tests.pas:12)', Frame.Tree.Items[8].Text);
    Assert.AreEqual('⚠ ' + TAtlasStrings.Fmt(TAtlasTextId.ImpactLimitDepth, [2, 2]), Frame.Tree.Items[9].Text);
  finally
    Host.Free;
  end;
end;

procedure TAtlasResultsFrameImpactTests.DepthAndRunTestsCallBack;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Depth: Integer;
  Names: TArray<string>;
begin
  Depth := 0;
  Names := nil;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnImpactDepth :=
      procedure(ADepth: Integer)
      begin
        Depth := ADepth;
      end;
    Frame.OnImpactRunTests :=
      procedure(const AImpact: TAtlasImpact)
      begin
        Names := AImpact.RunNames;
      end;
    Frame.ShowImpact('Auswirkungen', SampleImpact);
    Assert.IsTrue(Frame.DepthBox.Visible);
    Assert.AreEqual(5, Integer(Frame.DepthBox.Items.Count));
    Assert.AreEqual(1, Frame.DepthBox.ItemIndex, 'Tiefe 2');
    Assert.AreEqual(0, Depth, 'Anzeigen löst keine neue Anfrage aus');
    Frame.DepthBox.ItemIndex := 3;
    Frame.DepthBox.OnChange(Frame.DepthBox);
    Assert.AreEqual(4, Depth);
    Assert.IsTrue(Frame.RunTestsButton.Enabled);
    Frame.RunTestsButton.Click;
    Assert.AreEqual(1, Integer(Length(Names)));
    Assert.AreEqual('Werkzeug.Tests.TWerkzeugTests.PrueftHilfe', Names[0]);
  finally
    Host.Free;
  end;
  Names := nil;
end;

procedure TAtlasResultsFrameImpactTests.TextsOfPlacesFormsAndLimits;
var
  Item: TAtlasImpactPlace;
  Impact: TAtlasImpact;
  Limits: TArray<string>;
begin
  Item := Place('TKind', 'C:\P\Werkzeug.pas', 10, 1, -1);
  Item.Edge := 'override';
  Assert.AreEqual('TKind  (Werkzeug.pas:11)  · ' + TAtlasStrings.Text(TAtlasTextId.ImpactEdgeOverride),
    TAtlasResultsFrame.ImpactPlaceText(Item));
  Item.Edge := 'reference';
  Item.Terminal := True;
  Item.Item.Name := 'Haupt';
  Assert.AreEqual('Haupt · ' + TAtlasStrings.Text(TAtlasTextId.ImpactUnitLevel) + '  (Werkzeug.pas:13)  · ' +
    TAtlasStrings.Text(TAtlasTextId.ImpactEdgeReference), TAtlasResultsFrame.ImpactPlaceText(Item));
  Impact := Default(TAtlasImpact);
  Impact.CountReached := True;
  Impact.MaxPlaces := 1000;
  Impact.TimeReached := True;
  Impact.TimeoutMs := 8000;
  Limits := TAtlasResultsFrame.ImpactLimitTexts(Impact);
  Assert.AreEqual(2, Integer(Length(Limits)));
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactLimitCount, [1000]), Limits[0]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.ImpactLimitTime, [8000]), Limits[1]);
  Limits := nil;
end;

procedure TAtlasResultsFrameImpactTests.OtherListsHideImpactControls;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Impact: TAtlasImpact;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Impact := SampleImpact;
    Impact.Tests := nil;
    Frame.ShowImpact('Auswirkungen', Impact);
    Assert.IsFalse(Frame.RunTestsButton.Enabled, 'ohne Tests nichts auszuführen');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.ImpactNoTests), Frame.Tree.Items[7].Text);
    Frame.ShowEntries('Implementierungen', TAtlasResults.Group(Sample));
    Assert.IsFalse(Frame.ShowsImpact);
    Assert.IsFalse(Frame.DepthBox.Visible);
    Assert.IsFalse(Frame.RunTestsButton.Visible);
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameRatedTests);
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameImpactTests);

end.
