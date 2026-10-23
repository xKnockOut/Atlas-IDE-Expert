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

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Results.Model,
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsFrameRatedTests);

end.
