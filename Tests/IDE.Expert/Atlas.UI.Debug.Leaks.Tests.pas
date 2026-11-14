unit Atlas.UI.Debug.Leaks.Tests;

// Fenster „Atlas-Lecks“ (#1875): Texte der Zeilen und der Statuszeile, der Baum
// mit Namen und Stellen, „Als bekannt markieren“ und Enter melden sich.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugLeaksTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RowTexts;
    [Test]
    procedure SummaryNamesSource;
    [Test]
    procedure FrameFillsTreeAndReports;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView,
  Atlas.UI.Debug.Leaks,
  Atlas.UI.Debug.LeaksFrame;

const
  cNl = #13#10;
  cBox = 'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl;

function Capture: TAtlasLeakCapture;
begin
  TAtlasLeakCaptures.FromWindowTexts(TArray<string>.Create(cBox), Result);
end;

function Rows: TArray<TAtlasLeakRow>;
var
  mPlace: TAtlasLeakPlace;
  mHistory: TAtlasLeakHistory;
begin
  mPlace := Default(TAtlasLeakPlace);
  mPlace.ClassName := 'TKunde';
  mPlace.FileName := 'C:\P\Kunden.pas';
  mPlace.Line := 5;
  mPlace.Rating := 'neverFreed';
  mPlace.Routine := 'Lade';
  mHistory := TAtlasLeakCaptures.HistoryFromText('count:TKunde=1');
  Result := TAtlasLeakViews.Rows(TAtlasLeakCaptures.Compare(Capture.Report, mHistory),
    TArray<TAtlasLeakPlace>.Create(mPlace), nil, False);
end;

procedure TAtlasDebugLeaksTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugLeaksTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugLeaksTests.RowTexts;
var
  mRows: TArray<TAtlasLeakRow>;
begin
  mRows := Rows;
  Assert.AreEqual('UnicodeString ×5  (neu)', TAtlasLeakTexts.RowText(mRows[0]));
  Assert.AreEqual('TKunde ×3  (+2 seit dem letzten Lauf)', TAtlasLeakTexts.RowText(mRows[2]));
  Assert.AreEqual('Kunden.pas:6  Lade  ·  nie freigegeben', TAtlasLeakTexts.RowText(mRows[3]));
  Assert.AreEqual('Owner', TAtlasLeakTexts.RatingText('owned'));
  Assert.AreEqual('xyz', TAtlasLeakTexts.RatingText('xyz'));
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.AreEqual('never freed', TAtlasLeakTexts.RatingText('neverFreed'));
end;

procedure TAtlasDebugLeaksTests.SummaryNamesSource;
begin
  Assert.AreEqual(8, TAtlasLeakTexts.LeakCount(Capture));
  Assert.AreEqual('8 Lecks unter 2 Namen · Meldungsfenster', TAtlasLeakTexts.Summary(Capture));
  Assert.AreEqual('Kein Leckbericht aus dem letzten Lauf.', TAtlasLeakTexts.Summary(Default(TAtlasLeakCapture)));
end;

procedure TAtlasDebugLeaksTests.FrameFillsTreeAndReports;
var
  mHost: TForm;
  mFrame: TAtlasDebugLeaksFrame;
  mOpened, mMarked: string;
  mKey: Word;
begin
  mOpened := '';
  mMarked := '';
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugLeaksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.SetRows(Rows, 'Status');
    Assert.AreEqual('Status', mFrame.StatusLabel.Caption);
    Assert.AreEqual(2, mFrame.Tree.Items[0].Count + mFrame.Tree.Items[mFrame.Tree.Items[0].Count + 1].Count);
    mFrame.OnOpen :=
      procedure(ARow: TAtlasLeakRow)
      begin
        mOpened := ARow.Place.Routine;
      end;
    mFrame.OnMarkKnown :=
      procedure(AName: string)
      begin
        mMarked := AName;
      end;
    mFrame.Tree.Selected := mFrame.Tree.Items[mFrame.Tree.Items.Count - 1];
    mKey := VK_RETURN;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('Lade', mOpened);
    Assert.IsTrue(mFrame.MarkKnownButton.Enabled);
    mFrame.MarkKnownButton.Click;
    Assert.AreEqual('TKunde', mMarked);
    Assert.IsTrue(mFrame.HideKnown, 'Vorgabe: bekannte ausblenden');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugLeaksTests);

end.
