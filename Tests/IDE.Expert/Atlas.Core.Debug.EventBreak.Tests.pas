unit Atlas.Core.Debug.EventBreak.Tests;

// Beim nächsten Ereignis anhalten (#856), Kern: Antwort lesen, Ereignisarten,
// häufige Ereignisse, Einschränkung auf Formulare, Haltestellen und welcher
// Handler beim Halt gemeint ist.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.EventBreak,
  Atlas.Core.Settings.EventBreakNames;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TCoreDebugEventBreakTests = class
  private
    FAnswer: TAtlasEventAnswer;
    procedure Load;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure Categories;
    [Test]
    procedure MouseSelectsClicksOnly;
    [Test]
    procedure FrequentExcludedUnlessChosen;
    [Test]
    procedure ScopeOneFormAndVisibleForms;
    [Test]
    procedure SharedHandlerOneLocationIdentifiedBySender;
    [Test]
    procedure CaptionNamesComponentEventAndHandler;
    [Test]
    procedure HelpersAndExpressions;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

const
  cAnswer =
    '{"format":1,"unresolved":2,"handlers":[' +
    '{"form":"TfrmKunde","component":"btnSpeichern","componentClass":"TButton","event":"OnClick",' +
    '"handler":"btnSpeichernClick","container":"TfrmKunde","origin":"form","file":"C:\\P\\Kunde.pas","line":41},' +
    '{"form":"TfrmKunde","component":"btnOk","componentClass":"TButton","event":"OnClick",' +
    '"handler":"btnSpeichernClick","container":"TfrmKunde","origin":"form","file":"C:\\P\\Kunde.pas","line":41},' +
    '{"form":"TfrmKunde","component":"frmKunde","componentClass":"TfrmKunde","event":"OnPaint",' +
    '"handler":"FormPaint","container":"TfrmKunde","origin":"form","file":"C:\\P\\Kunde.pas","line":50},' +
    '{"form":"TfrmKunde","component":"Timer1","componentClass":"TTimer","event":"OnTimer",' +
    '"handler":"Timer1Timer","container":"TfrmKunde","origin":"form","file":"C:\\P\\Kunde.pas","line":60,"interval":50},' +
    '{"form":"TdmDaten","component":"Tabelle","componentClass":"TFDQuery","event":"BeforePost",' +
    '"handler":"TabelleBeforePost","container":"TdmDaten","origin":"form","file":"C:\\P\\Daten.pas","line":19,' +
    '"bodyLine":20},' +
    '{"form":"TfrmHaupt","component":"FTimer","componentClass":"","event":"OnTimer",' +
    '"handler":"Tick","container":"TfrmHaupt","origin":"code","file":"C:\\P\\Haupt.pas","line":30},' +
    '{"form":"TfrmHaupt","component":"actDrucken","componentClass":"TAction","event":"OnExecute",' +
    '"handler":"actDruckenExecute","container":"TfrmHaupt","origin":"form","file":"C:\\P\\Haupt.pas","line":40},' +
    '{"form":"TfrmHaupt","component":"actDrucken","componentClass":"TAction","event":"OnUpdate",' +
    '"handler":"actDruckenUpdate","container":"TfrmHaupt","origin":"form","file":"C:\\P\\Haupt.pas","line":45},' +
    '{"form":"TfrmHaupt","component":"x","event":"OnClick","handler":"Ohne","file":"","line":-1}]}';

procedure TCoreDebugEventBreakTests.TearDown;
begin
  FAnswer := Default(TAtlasEventAnswer);
end;

procedure TCoreDebugEventBreakTests.Load;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(cAnswer);
  try
    Assert.IsTrue(TAtlasEventBreak.ReadAnswer(mJson, FAnswer));
  finally
    mJson.Free;
  end;
end;

procedure TCoreDebugEventBreakTests.ReadsAnswer;
var
  mJson: TJSONValue;
  mOther: TAtlasEventAnswer;
begin
  Load;
  // Der Eintrag ohne Datei fällt weg.
  Assert.AreEqual(8, Integer(Length(FAnswer.Handlers)));
  Assert.AreEqual(2, FAnswer.Unresolved);
  Assert.AreEqual('btnSpeichern', FAnswer.Handlers[0].Component);
  Assert.AreEqual(41, FAnswer.Handlers[0].Line);
  Assert.AreEqual(41, FAnswer.Handlers[0].BreakLine, 'ohne bodyLine das begin');
  Assert.AreEqual(19, FAnswer.Handlers[4].Line);
  Assert.AreEqual(20, FAnswer.Handlers[4].BreakLine);
  Assert.AreEqual(50, FAnswer.Handlers[3].Interval);
  Assert.AreEqual(-1, FAnswer.Handlers[0].Interval);
  Assert.IsTrue(FAnswer.Handlers[5].Code);
  Assert.IsFalse(FAnswer.Handlers[0].Code);
  mJson := TJSONObject.ParseJSONValue('{"format":2}');
  try
    Assert.IsFalse(TAtlasEventBreak.ReadAnswer(mJson, mOther));
  finally
    mJson.Free;
  end;
end;

procedure TCoreDebugEventBreakTests.Categories;
begin
  Assert.AreEqual(Ord(TAtlasEventCategory.Mouse), Ord(TAtlasEventBreak.CategoryOf('OnClick')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Mouse), Ord(TAtlasEventBreak.CategoryOf('onmousedown')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Keyboard), Ord(TAtlasEventBreak.CategoryOf('OnKeyPress')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Timer), Ord(TAtlasEventBreak.CategoryOf('OnTimer')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Window), Ord(TAtlasEventBreak.CategoryOf('OnCloseQuery')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Database), Ord(TAtlasEventBreak.CategoryOf('BeforePost')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Database), Ord(TAtlasEventBreak.CategoryOf('AfterScroll')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Database), Ord(TAtlasEventBreak.CategoryOf('OnCalcFields')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Actions), Ord(TAtlasEventBreak.CategoryOf('OnExecute')));
  Assert.AreEqual(Ord(TAtlasEventCategory.Other), Ord(TAtlasEventBreak.CategoryOf('OnChange')));
end;

procedure TCoreDebugEventBreakTests.MouseSelectsClicksOnly;
var
  mChoice: TAtlasEventChoice;
  mSelected: TArray<Integer>;
begin
  Load;
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Categories := [TAtlasEventCategory.Mouse];
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice,
    TAtlasEventBreakSettings.ExcludedList(TAtlasEventBreakSettings.cDefaultExcluded), nil);
  Assert.AreEqual(2, Integer(Length(mSelected)));
  Assert.AreEqual(0, mSelected[0]);
  Assert.AreEqual(1, mSelected[1]);
end;

procedure TCoreDebugEventBreakTests.FrequentExcludedUnlessChosen;
var
  mChoice: TAtlasEventChoice;
  mExcluded: TArray<string>;
  mSelected: TArray<Integer>;
begin
  Load;
  mExcluded := TAtlasEventBreakSettings.ExcludedList(TAtlasEventBreakSettings.cDefaultExcluded);
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Categories := TAtlasEventBreak.cAllCategories;
  // Ohne häufige: OnPaint, Timer mit 50 ms und OnUpdate fehlen; der Timer im Code (ohne Interval) bleibt.
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, mExcluded, nil);
  Assert.AreEqual(5, Integer(Length(mSelected)));
  Assert.IsTrue(TAtlasEventBreak.IsFrequent(FAnswer.Handlers[2], mExcluded), 'OnPaint');
  Assert.IsTrue(TAtlasEventBreak.IsFrequent(FAnswer.Handlers[3], mExcluded), 'Timer 50 ms');
  Assert.IsFalse(TAtlasEventBreak.IsFrequent(FAnswer.Handlers[5], mExcluded), 'Timer ohne Interval');
  Assert.IsTrue(TAtlasEventBreak.IsFrequent(FAnswer.Handlers[7], mExcluded), 'OnUpdate');
  mChoice.Frequent := True;
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, mExcluded, nil);
  Assert.AreEqual(8, Integer(Length(mSelected)));
end;

procedure TCoreDebugEventBreakTests.ScopeOneFormAndVisibleForms;
var
  mChoice: TAtlasEventChoice;
  mSelected: TArray<Integer>;
  mIndex: Integer;
begin
  Load;
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Categories := TAtlasEventBreak.cAllCategories;
  mChoice.Frequent := True;
  mChoice.Scope := TAtlasEventScope.OneForm;
  mChoice.Form := 'tdmdaten';
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, nil, nil);
  Assert.AreEqual(1, Integer(Length(mSelected)));
  Assert.AreEqual(4, mSelected[0]);
  mChoice.Scope := TAtlasEventScope.VisibleForms;
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, nil, TArray<string>.Create('TfrmHaupt'));
  Assert.AreEqual(3, Integer(Length(mSelected)));
  for mIndex in mSelected do
  begin
    Assert.AreEqual('TfrmHaupt', FAnswer.Handlers[mIndex].Form);
  end;
  mSelected := TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, nil, nil);
  Assert.AreEqual(0, Integer(Length(mSelected)), 'kein Formular sichtbar');
end;

procedure TCoreDebugEventBreakTests.SharedHandlerOneLocationIdentifiedBySender;
var
  mChoice: TAtlasEventChoice;
  mLocations: TArray<TAtlasEventLocation>;
  mAt: Integer;
begin
  Load;
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Categories := TAtlasEventBreak.cAllCategories;
  mChoice.Frequent := True;
  mLocations := TAtlasEventBreak.Locations(FAnswer.Handlers,
    TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, nil, nil));
  // btnSpeichern und btnOk teilen sich Zeile 41.
  Assert.AreEqual(7, Integer(Length(mLocations)));
  mAt := TAtlasEventBreak.LocationAt(mLocations, 'c:\p\kunde.pas', 41);
  Assert.AreEqual(0, mAt);
  Assert.AreEqual(2, Integer(Length(mLocations[mAt].Handlers)));
  Assert.AreEqual(1, TAtlasEventBreak.Identify(FAnswer.Handlers, mLocations[mAt], 'btnOk'));
  Assert.AreEqual(0, TAtlasEventBreak.Identify(FAnswer.Handlers, mLocations[mAt], 'BTNSPEICHERN'));
  Assert.AreEqual(-1, TAtlasEventBreak.Identify(FAnswer.Handlers, mLocations[mAt], ''));
  Assert.AreEqual(-1, TAtlasEventBreak.Identify(FAnswer.Handlers, mLocations[mAt], 'btnAnders'));
  // Eine Stelle mit einem Handler braucht keinen Sender.
  mAt := TAtlasEventBreak.LocationAt(mLocations, 'C:\P\Daten.pas', 20);
  Assert.AreEqual(4, TAtlasEventBreak.Identify(FAnswer.Handlers, mLocations[mAt], ''));
  Assert.AreEqual(-1, TAtlasEventBreak.LocationAt(mLocations, 'C:\P\Daten.pas', 21));
end;

procedure TCoreDebugEventBreakTests.CaptionNamesComponentEventAndHandler;
var
  mChoice: TAtlasEventChoice;
  mLocations: TArray<TAtlasEventLocation>;
begin
  Load;
  mChoice := TAtlasEventChoice.Defaults;
  mChoice.Categories := TAtlasEventBreak.cAllCategories;
  mLocations := TAtlasEventBreak.Locations(FAnswer.Handlers,
    TAtlasEventBreak.Select(FAnswer.Handlers, mChoice, nil, nil));
  Assert.AreEqual('btnOk.OnClick → TfrmKunde.btnSpeichernClick',
    TAtlasEventBreak.Caption(FAnswer.Handlers, mLocations[0], 1));
  Assert.AreEqual('btnSpeichern.OnClick / btnOk.OnClick → TfrmKunde.btnSpeichernClick',
    TAtlasEventBreak.Caption(FAnswer.Handlers, mLocations[0], -1));
end;

procedure TCoreDebugEventBreakTests.HelpersAndExpressions;
var
  mForms: TArray<string>;
begin
  Load;
  mForms := TAtlasEventBreak.Forms(FAnswer.Handlers);
  Assert.AreEqual(3, Integer(Length(mForms)));
  Assert.AreEqual('TdmDaten', mForms[0]);
  Assert.AreEqual('TfrmHaupt', mForms[1]);
  Assert.AreEqual('["file:///C:/P/A.dproj"]', TAtlasEventBreak.Arguments('file:///C:/P/A.dproj'));
  Assert.AreEqual('[null]', TAtlasEventBreak.Arguments(''));
  Assert.AreEqual('Screen.Forms[2].ClassName', TAtlasEventBreak.FormClassExpression(2));
  Assert.AreEqual('Screen.Forms[0].Visible', TAtlasEventBreak.FormVisibleExpression(0));
  Assert.AreEqual('btnOk', TAtlasEventBreak.Unquote('''btnOk'''));
  Assert.AreEqual('O''Neil', TAtlasEventBreak.Unquote('''O''''Neil'''));
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreDebugEventBreakTests);

end.
