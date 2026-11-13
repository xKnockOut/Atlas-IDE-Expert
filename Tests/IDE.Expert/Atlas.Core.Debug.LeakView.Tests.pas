unit Atlas.Core.Debug.LeakView.Tests;

// Tests für den Inhalt des Fensters „Atlas-Lecks“ (#1875): Argumente und
// Antwort von atlas.server.leakCandidates, Zeilen mit Kandidaten bzw. Gruppen,
// Hinweis bei Strings, bekannte ausblenden, Sprungziele.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLeakViewTests = class
  public
    [Test]
    procedure ArgumentsCarryProjectAndReport;
    [Test]
    procedure PlacesFromAnswer;
    [Test]
    procedure RowsWithCandidatesAndHint;
    [Test]
    procedure RowsWithGroupsSkipCandidates;
    [Test]
    procedure HideKnown;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LeakReport,
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView;

const
  cNl = #13#10;
  cBox = 'An unexpected memory leak has occurred. The unexpected small block leaks are:' + cNl + cNl +
    '1 - 12 bytes: TKunde x 3, UnicodeString x 5' + cNl;
  cAnswer = '{"classes":[{"name":"TKunde","count":3}],"hasStacks":false,"truncated":false,"candidates":[' +
    '{"uri":"file:///C:/P/Kunden.pas","line":5,"character":2,"className":"TKunde","rating":"neverFreed",' +
    '"target":"","routine":"Lade"},{"uri":"file:///C:/P/Fabrik.pas","line":9,"character":12,' +
    '"className":"TKunde","rating":"returned","target":"Result","routine":"Neu"}],"project":"C:\\P\\App.dpr"}';

function Entries(const AKnown: string): TArray<TAtlasLeakEntry>;
var
  mHistory: TAtlasLeakHistory;
begin
  mHistory := Default(TAtlasLeakHistory);
  if AKnown <> '' then
  begin
    mHistory := TAtlasLeakCaptures.MarkKnown(mHistory, AKnown, True);
  end;
  Result := TAtlasLeakCaptures.Compare(TLeakReports.Parse(cBox), mHistory);
end;

procedure TAtlasLeakViewTests.ArgumentsCarryProjectAndReport;
var
  mJson: string;
begin
  mJson := TAtlasLeakViews.CandidateArgumentsJson('C:\P\App.dproj', 'TKunde x 3');
  Assert.IsTrue(Pos('App.dproj"', mJson) > 0, mJson);
  Assert.IsTrue(Pos('{"report":"TKunde x 3"}', mJson) > 0, mJson);
  Assert.AreEqual('[', Copy(mJson, 1, 1));
end;

procedure TAtlasLeakViewTests.PlacesFromAnswer;
var
  mPlaces: TArray<TAtlasLeakPlace>;
begin
  mPlaces := TAtlasLeakViews.PlacesFromJson(cAnswer);
  Assert.AreEqual(2, Integer(Length(mPlaces)));
  Assert.AreEqual('TKunde', mPlaces[0].ClassName);
  Assert.AreEqual(5, mPlaces[0].Line);
  Assert.AreEqual(2, mPlaces[0].Character);
  Assert.AreEqual('neverFreed', mPlaces[0].Rating);
  Assert.AreEqual('Lade', mPlaces[0].Routine);
  Assert.IsTrue(Pos('Kunden.pas', mPlaces[0].FileName) > 0, mPlaces[0].FileName);
  Assert.AreEqual('Result', mPlaces[1].Target);
  Assert.AreEqual(0, Integer(Length(TAtlasLeakViews.PlacesFromJson('kein json'))));
  Assert.AreEqual(0, Integer(Length(TAtlasLeakViews.PlacesFromJson('{}'))));
end;

procedure TAtlasLeakViewTests.RowsWithCandidatesAndHint;
var
  mRows: TArray<TAtlasLeakRow>;
begin
  mRows := TAtlasLeakViews.Rows(Entries(''), TAtlasLeakViews.PlacesFromJson(cAnswer), nil, False);
  // UnicodeString x 5 steht im Bericht vor TKunde x 3 (nach Anzahl).
  Assert.AreEqual(5, Integer(Length(mRows)));
  Assert.IsTrue(mRows[0].Kind = TAtlasLeakRowKind.Name);
  Assert.AreEqual('UnicodeString', mRows[0].Entry.Name);
  Assert.IsTrue(mRows[1].Kind = TAtlasLeakRowKind.Hint, 'folgt aus Objekten');
  Assert.AreEqual('TKunde', mRows[2].Entry.Name);
  Assert.AreEqual(2, mRows[2].PlaceCount);
  Assert.IsTrue(mRows[3].Kind = TAtlasLeakRowKind.Place);
  Assert.IsTrue(TAtlasLeakViews.CanOpen(mRows[3]));
  Assert.IsFalse(TAtlasLeakViews.CanOpen(mRows[2]));
end;

procedure TAtlasLeakViewTests.RowsWithGroupsSkipCandidates;
var
  mGroup: TLeakGroup;
  mRows: TArray<TAtlasLeakRow>;
begin
  mGroup := Default(TLeakGroup);
  mGroup.Name := 'TKunde';
  mGroup.Kind := TLeakKind.Instance;
  mGroup.Count := 3;
  SetLength(mGroup.Frames, 1);
  mGroup.Frames[0].FileName := 'Kunden.pas';
  mGroup.Frames[0].Line := 42;
  mGroup.Site := 0;
  mRows := TAtlasLeakViews.Rows(Entries(''), TAtlasLeakViews.PlacesFromJson(cAnswer),
    TArray<TLeakGroup>.Create(mGroup), False);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual(1, mRows[2].PlaceCount);
  Assert.IsTrue(mRows[3].Kind = TAtlasLeakRowKind.Group);
  Assert.IsTrue(TAtlasLeakViews.CanOpen(mRows[3]));
end;

procedure TAtlasLeakViewTests.HideKnown;
var
  mRows: TArray<TAtlasLeakRow>;
begin
  mRows := TAtlasLeakViews.Rows(Entries('TKunde'), TAtlasLeakViews.PlacesFromJson(cAnswer), nil, True);
  Assert.AreEqual(2, Integer(Length(mRows)), 'nur UnicodeString mit Hinweis');
  Assert.AreEqual('UnicodeString', mRows[0].Entry.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLeakViewTests);

end.
