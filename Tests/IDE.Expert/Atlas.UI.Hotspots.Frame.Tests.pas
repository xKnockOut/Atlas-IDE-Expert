unit Atlas.UI.Hotspots.Frame.Tests;

// Fenster „Atlas-Hotspots“ (#1354), Fensterinhalt: Rangliste, Kopplung und
// Verlauf aus den Daten des Servers, Ebene und Filter, Auswahl zwischen
// Diagramm und Liste, Springen, „Verlauf zeigen“, „Auswirkungen anzeigen“
// und Hinweise statt Daten (keine Versionsverwaltung, Rechnen läuft).

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Hotspots.Frame;

type
  [TestFixture]
  TAtlasHotspotsFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasHotspotsFrame;
    FOpened: string;
    FLine: Integer;
    FImpactMethod: string;
  public
    /// <summary>Einmalige VCL-Puffer (PageControl, Listen, Diagramm) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsListsOnUnitLevel;
    [Test]
    procedure SwitchesLevelAndKeepsUnit;
    [Test]
    procedure FilterNarrowsListAndChart;
    [Test]
    procedure SelectionFollowsChartAndList;
    [Test]
    procedure OpensHistoryAndImpact;
    [Test]
    procedure MessagesInsteadOfData;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.Core.Hotspots.Model,
  Atlas.Core.Hotspots.Model.Tests;

procedure TAtlasHotspotsFrameTests.WarmUpFirstUse;
begin
  SetUp;
  try
    FillsListsOnUnitLevel;
  finally
    TearDown;
  end;
end;

procedure TAtlasHotspotsFrameTests.SetUp;
var
  mModel: TAtlasHotspotModel;
  mEnabled, mHasVcs: Boolean;
  mMessage: string;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 700;
  FFrame := TAtlasHotspotsFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.OnOpen :=
    procedure(AFileName: string; ALine: Integer)
    begin
      FOpened := AFileName;
      FLine := ALine;
    end;
  FFrame.OnImpact :=
    procedure(AFileName: string; ALine: Integer; AMethod: string)
    begin
      FOpened := AFileName;
      FLine := ALine;
      FImpactMethod := AMethod;
    end;
  TAtlasHotspotModel.Parse(SampleHotspotAnswer, mModel, mEnabled, mHasVcs, mMessage);
  FFrame.SetModel(mModel);
end;

procedure TAtlasHotspotsFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
  FOpened := '';
  FImpactMethod := '';
end;

procedure TAtlasHotspotsFrameTests.FillsListsOnUnitLevel;
var
  mText: string;
begin
  Assert.AreEqual('unit', FFrame.LevelValue, 'Vorgabe Units, auch wenn der Server Methoden mitliefert');
  Assert.AreEqual(3, Integer(Length(FFrame.HotspotText)));
  mText := FFrame.HotspotText[0];
  // Der Wert hängt vom Dezimaltrenner ab; Änderungen, Autoren, Komplexität und Zeilen nicht.
  Assert.IsTrue(mText.StartsWith('1'#9'App.Kern'#9), mText);
  Assert.IsTrue(mText.Contains(#9'12'#9'2'#9'80'#9'400'#9), mText);
  Assert.IsTrue(mText.EndsWith(#9'2026-10-20'), mText);
  Assert.AreEqual(1, Integer(Length(FFrame.CouplingText)));
  Assert.AreEqual('App.Daten'#9'App.Form'#9'6'#9'92 %', FFrame.CouplingText[0]);
  Assert.AreEqual(3, Integer(Length(FFrame.Chart.Bubbles)));
  Assert.IsTrue(string(FFrame.StatusLabel.Caption).Contains('42'), FFrame.StatusLabel.Caption);
end;

procedure TAtlasHotspotsFrameTests.SwitchesLevelAndKeepsUnit;
begin
  FFrame.Select(1);
  FFrame.LevelValue := 'method';
  Assert.AreEqual(2, Integer(Length(FFrame.HotspotText)));
  Assert.IsTrue(FFrame.HotspotText[0].Contains('TKern.Rechne'));
  Assert.AreEqual(1, FFrame.Selected, 'Methode der gewählten Unit App.Daten');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.HotspotsColMethod), FFrame.HotspotList.Columns[1].Caption);
  FFrame.LevelValue := 'unit';
  Assert.AreEqual(3, Integer(Length(FFrame.HotspotText)));
  Assert.AreEqual(1, FFrame.Selected);
end;

procedure TAtlasHotspotsFrameTests.FilterNarrowsListAndChart;
begin
  FFrame.Filter.Text := 'form';
  Assert.AreEqual(1, Integer(Length(FFrame.HotspotText)));
  Assert.IsTrue(FFrame.HotspotText[0].StartsWith('3'#9'App.Form'), 'Rang aus der ganzen Liste');
  Assert.AreEqual(1, Integer(Length(FFrame.Chart.Bubbles)));
  Assert.AreEqual(1, Integer(Length(FFrame.CouplingText)));
  FFrame.Filter.Text := 'kern';
  Assert.AreEqual(0, Integer(Length(FFrame.CouplingText)));
  FFrame.Filter.Text := '';
  Assert.AreEqual(3, Integer(Length(FFrame.HotspotText)));
end;

procedure TAtlasHotspotsFrameTests.SelectionFollowsChartAndList;
begin
  FFrame.HotspotList.Items[2].Selected := True;
  Assert.AreEqual(2, FFrame.Selected);
  Assert.AreEqual(2, FFrame.Chart.Selected, 'Diagramm folgt der Liste');
  FFrame.Select(0);
  Assert.IsTrue(FFrame.HotspotList.Items[0].Selected, 'Liste folgt dem Diagramm');
  Assert.AreEqual(0, FFrame.Chart.Selected);
  Assert.IsTrue(FFrame.Chart.BubbleText(0).StartsWith('App.Kern: 12 '), FFrame.Chart.BubbleText(0));
end;

procedure TAtlasHotspotsFrameTests.OpensHistoryAndImpact;
begin
  FFrame.OpenEntry(0);
  Assert.IsTrue(FOpened.EndsWith('Kern.pas'), FOpened);
  Assert.AreEqual(1, FLine);
  FFrame.LevelValue := 'method';
  FFrame.ShowHistory(0);
  Assert.AreEqual(120, FLine, 'springt zur Methode');
  Assert.AreEqual(2, Integer(Length(FFrame.HistoryText)));
  Assert.IsTrue(FFrame.HistoryText[0].StartsWith('0123456'#9'2026-10-20'#9'anna'#9'Rechnung'#9'+3'),
    FFrame.HistoryText[0]);
  Assert.IsTrue(FFrame.HistoryText[1].EndsWith(#9), 'Zeilen unbekannt');
  Assert.IsTrue(string(FFrame.HistoryInfo.Caption).Contains('TKern.Rechne'));
  Assert.AreEqual(2, FFrame.Pages.ActivePageIndex, 'Reiter Verlauf');
  FFrame.ShowImpact(1);
  Assert.AreEqual('TDaten.Lade', FImpactMethod);
  Assert.AreEqual(40, FLine);
end;

procedure TAtlasHotspotsFrameTests.MessagesInsteadOfData;
begin
  FFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.HotspotsLoading), True);
  Assert.AreEqual(3, Integer(Length(FFrame.HotspotText)), 'Daten bleiben, während gerechnet wird');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.HotspotsLoading), FFrame.StatusLabel.Caption);
  FFrame.SetMessage(TAtlasStrings.Fmt(TAtlasTextId.HotspotsNoVcs, ['kein Repository']), False);
  Assert.AreEqual(0, Integer(Length(FFrame.HotspotText)));
  Assert.IsFalse(FFrame.HasModel);
  Assert.IsTrue(string(FFrame.StatusLabel.Caption).Contains('kein Repository'));
  Assert.AreEqual(0, Integer(Length(FFrame.Chart.Bubbles)));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.HotspotsChartHint), FFrame.Chart.EmptyText);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHotspotsFrameTests);

end.
