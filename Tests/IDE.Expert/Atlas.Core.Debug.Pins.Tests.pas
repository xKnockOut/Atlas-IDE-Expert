unit Atlas.Core.Debug.Pins.Tests;

// Tests für angeheftete Debug-Werte (#526): Einträge, Speichern, Werte je Halt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Pins;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TDebugPinsTests = class
  private
    FPins: TAtlasDebugPins;
    function Pin(const AFile: string; ALine: Integer; const AExpression: string): TAtlasDebugPin;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure AddRejectsDuplicatesAndEmpty;
    [Test]
    procedure SameFileIgnoresCase;
    [Test]
    procedure LimitPerProject;
    [Test]
    procedure InFileSortsByLineKeepingOrder;
    [Test]
    procedure RemoveForgetsValue;
    [Test]
    procedure RoundTripThroughText;
    [Test]
    procedure BrokenTextLeavesListEmpty;
    [Test]
    procedure ValueIsPendingUntilPut;
    [Test]
    procedure ChangedComparesWithPreviousStop;
    [Test]
    procedure FailedValueShowsQuestionMark;
    [Test]
    procedure EndSessionForgetsValuesButKeepsPins;
    [Test]
    procedure LongValuesAreShortened;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.InlineValues;

const
  cProject = 'C:\Projekte\Kasse.dproj';

procedure TDebugPinsTests.Setup;
begin
  FPins := TAtlasDebugPins.Create;
end;

procedure TDebugPinsTests.TearDown;
begin
  FreeAndNil(FPins);
end;

function TDebugPinsTests.Pin(const AFile: string; ALine: Integer; const AExpression: string): TAtlasDebugPin;
begin
  Result := TAtlasDebugPin.Create(cProject, AFile, ALine, AExpression);
end;

procedure TDebugPinsTests.AddRejectsDuplicatesAndEmpty;
begin
  Assert.IsTrue(FPins.Add(Pin('Kasse.pas', 12, 'Summe')));
  Assert.IsFalse(FPins.Add(Pin('Kasse.pas', 12, ' Summe ')), 'derselbe Ausdruck an derselben Zeile');
  Assert.IsTrue(FPins.Add(Pin('Kasse.pas', 13, 'Summe')), 'andere Zeile');
  Assert.IsFalse(FPins.Add(Pin('Kasse.pas', 14, '  ')), 'leerer Ausdruck');
  Assert.IsFalse(FPins.Add(Pin('Kasse.pas', 0, 'Summe')), 'keine Zeile');
  Assert.AreEqual(2, FPins.Count);
end;

procedure TDebugPinsTests.SameFileIgnoresCase;
begin
  FPins.Add(Pin('C:\Src\Kasse.pas', 12, 'Summe'));
  Assert.IsFalse(FPins.Add(TAtlasDebugPin.Create(UpperCase(cProject), 'c:\src\KASSE.pas', 12, 'Summe')));
  Assert.AreEqual(1, Integer(Length(FPins.InFile(cProject, 'c:\src\kasse.PAS'))));
end;

procedure TDebugPinsTests.LimitPerProject;
var
  mIndex: Integer;
begin
  for mIndex := 1 to TAtlasDebugPins.cLimit do
  begin
    Assert.IsTrue(FPins.Add(Pin('Kasse.pas', mIndex, 'X')));
  end;
  Assert.IsFalse(FPins.Add(Pin('Kasse.pas', 1000, 'X')), 'Projekt voll');
  Assert.IsTrue(FPins.Add(TAtlasDebugPin.Create('Anderes.dproj', 'Kasse.pas', 1, 'X')), 'anderes Projekt');
end;

procedure TDebugPinsTests.InFileSortsByLineKeepingOrder;
var
  mList: TAtlasDebugPinList;
begin
  FPins.Add(Pin('Kasse.pas', 30, 'B'));
  FPins.Add(Pin('Kasse.pas', 10, 'A2'));
  FPins.Add(Pin('Andere.pas', 5, 'Z'));
  FPins.Add(Pin('Kasse.pas', 10, 'A1'));
  mList := FPins.InFile(cProject, 'Kasse.pas');
  Assert.AreEqual(3, Integer(Length(mList)));
  Assert.AreEqual('A2', mList[0].Expression);
  Assert.AreEqual('A1', mList[1].Expression);
  Assert.AreEqual('B', mList[2].Expression);
  Assert.AreEqual(4, Integer(Length(FPins.All(cProject))));
  Assert.AreEqual(0, Integer(Length(FPins.All('Fremd.dproj'))));
end;

procedure TDebugPinsTests.RemoveForgetsValue;
begin
  FPins.Add(Pin('Kasse.pas', 12, 'Summe'));
  FPins.Put(Pin('Kasse.pas', 12, 'Summe'), '1', True);
  Assert.IsTrue(FPins.Remove(Pin('Kasse.pas', 12, 'Summe')));
  Assert.IsFalse(FPins.Remove(Pin('Kasse.pas', 12, 'Summe')));
  Assert.IsFalse(FPins.Evaluated(Pin('Kasse.pas', 12, 'Summe')));
  Assert.AreEqual(0, FPins.Count);
end;

procedure TDebugPinsTests.RoundTripThroughText;
var
  mOther: TAtlasDebugPins;
  mList: TAtlasDebugPinList;
begin
  FPins.Add(Pin('C:\Src\Kasse.pas', 12, 'Kunde.Name'));
  FPins.Add(Pin('C:\Src\Kasse.pas', 40, 'Liste[I]'));
  mOther := TAtlasDebugPins.Create;
  try
    Assert.IsTrue(mOther.LoadFromText(FPins.ToText));
    mList := mOther.InFile(cProject, 'C:\Src\Kasse.pas');
    Assert.AreEqual(2, Integer(Length(mList)));
    Assert.AreEqual('Kunde.Name', mList[0].Expression);
    Assert.AreEqual(12, mList[0].Line);
    Assert.AreEqual('Liste[I]', mList[1].Expression);
  finally
    mOther.Free;
  end;
end;

procedure TDebugPinsTests.BrokenTextLeavesListEmpty;
begin
  FPins.Add(Pin('Kasse.pas', 12, 'Summe'));
  Assert.IsFalse(FPins.LoadFromText('{kaputt'));
  Assert.AreEqual(0, FPins.Count);
  Assert.IsFalse(FPins.LoadFromText('{"format":99,"pins":[]}'), 'unbekanntes Format');
end;

procedure TDebugPinsTests.ValueIsPendingUntilPut;
var
  mItem: TAtlasInlineValueItem;
begin
  FPins.Add(Pin('Kasse.pas', 12, 'Summe'));
  mItem := FPins.ValueOf(Pin('Kasse.pas', 12, 'Summe'));
  Assert.IsTrue(mItem.State = TAtlasInlineValueState.Pending);
  Assert.AreEqual('Summe = …', mItem.Caption);
  FPins.Put(Pin('Kasse.pas', 12, 'Summe'), '125', True);
  mItem := FPins.ValueOf(Pin('Kasse.pas', 12, 'Summe'));
  Assert.AreEqual('Summe = 125', mItem.Caption);
  Assert.IsFalse(mItem.Changed, 'kein voriger Halt');
end;

procedure TDebugPinsTests.ChangedComparesWithPreviousStop;
var
  mPin: TAtlasDebugPin;
begin
  mPin := Pin('Kasse.pas', 12, 'Summe');
  FPins.Add(mPin);
  FPins.Put(mPin, '125', True);
  FPins.NewStop;
  Assert.IsFalse(FPins.Evaluated(mPin), 'neuer Halt verwirft die Werte');
  FPins.Put(mPin, '150', True);
  Assert.IsTrue(FPins.ValueOf(mPin).Changed);
  FPins.NewStop;
  FPins.Put(mPin, '150', True);
  Assert.IsFalse(FPins.ValueOf(mPin).Changed);
end;

procedure TDebugPinsTests.FailedValueShowsQuestionMark;
var
  mPin: TAtlasDebugPin;
begin
  mPin := Pin('Kasse.pas', 12, 'Summe');
  FPins.Put(mPin, 'E2003', False);
  Assert.AreEqual('Summe = ?', FPins.ValueOf(mPin).Caption);
  Assert.IsFalse(FPins.ValueOf(mPin).Changed);
end;

procedure TDebugPinsTests.EndSessionForgetsValuesButKeepsPins;
var
  mPin: TAtlasDebugPin;
begin
  mPin := Pin('Kasse.pas', 12, 'Summe');
  FPins.Add(mPin);
  FPins.Put(mPin, '1', True);
  FPins.EndSession;
  Assert.AreEqual(1, FPins.Count);
  Assert.IsFalse(FPins.Evaluated(mPin));
  FPins.Put(mPin, '2', True);
  Assert.IsFalse(FPins.ValueOf(mPin).Changed, 'nach Sitzungsende kein Vergleich');
end;

procedure TDebugPinsTests.LongValuesAreShortened;
var
  mPin: TAtlasDebugPin;
begin
  mPin := Pin('Kasse.pas', 12, 'Text');
  FPins.Put(mPin, StringOfChar('x', 500), True);
  Assert.AreEqual(StringOfChar('x', TAtlasDebugPins.cMaxText) + ' …', FPins.ValueOf(mPin).Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebugPinsTests);

end.
