unit Atlas.Core.Debug.EvalSlices.Tests;

// Tests für die Auswertung in Zeitscheiben (TAtlasEvalSlices) gegen den
// gefälschten Thread (TAtlasDebugEvaluatorFake) mit einer Uhr des Tests:
// Ort und Nebenwirkungen, Zeitgrenze der Scheibe, Reihenfolge der Listen,
// verzögerte Werte (ankommend, überfällig, verworfen, Zeile entfernt), Halt
// vorbei, Fehlertexte mit „kein Zugriff“ und ohne Meldung.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.EvalSlices,
  Atlas.Tests.DebugEvaluatorFake;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEvalSlicesTests = class
  private
    FFake: TAtlasDebugEvaluatorFake;
    FEvaluator: IAtlasDebugEvaluator;
    FSlices: TAtlasEvalSlices;
    FList: TAtlasEvalList;
    FOther: TAtlasEvalList;
    FNow: UInt64;
    FCostMs: Cardinal;
    FArrived: Integer;
    function Place: TAtlasEvalPlace;
    function Slice(out AChanged: Boolean): TAtlasEvalSliceStep; overload;
    function Slice: TAtlasEvalSliceStep; overload;
    function Row(AIndex: Integer): TAtlasEvalNode;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EvaluatesAtPlaceWithFieldNames;
    [Test]
    procedure SideEffectsArePassed;
    [Test]
    procedure SliceEndsAfterSliceMs;
    [Test]
    procedure ListsInGivenOrder;
    [Test]
    procedure DeferredValueArrivesLater;
    [Test]
    procedure WaitingSliceEvaluatesNothing;
    [Test]
    procedure OverdueValueExpires;
    [Test]
    procedure DropCancelsRowAndItsFields;
    [Test]
    procedure DropOfOtherRowKeepsWaiting;
    [Test]
    procedure RowRemovedWhileWaiting;
    [Test]
    procedure StoppedProcessStopsSlice;
    [Test]
    procedure UnavailableErrorIsMarked;
    [Test]
    procedure EmptyErrorGetsText;
    [Test]
    procedure CancelIgnoresLateAnswer;
    [Test]
    procedure ModifiedValueShowsAfterRestart;
  end;

implementation

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.EvaluateRows,
  Atlas.Core.Diagnostics.Deadline;

{ TAtlasEvalSlicesTests }

procedure TAtlasEvalSlicesTests.Setup;
begin
  FNow := 1000;
  FCostMs := 0;
  FArrived := 0;
  TAtlasTicks.SetClock(
    function: UInt64
    begin
      Result := FNow;
    end);
  FFake := TAtlasDebugEvaluatorFake.Create;
  FEvaluator := FFake;
  FFake.OnEvaluate :=
    procedure
    begin
      Inc(FNow, FCostMs);
    end;
  FSlices := TAtlasEvalSlices.Create(FEvaluator, 30, 2000);
  FSlices.TimeoutText := 'timeout';
  FSlices.OnArrived :=
    procedure
    begin
      Inc(FArrived);
    end;
  FList := TAtlasEvalList.Create;
  FOther := TAtlasEvalList.Create;
end;

procedure TAtlasEvalSlicesTests.TearDown;
begin
  FreeAndNil(FSlices);
  FreeAndNil(FOther);
  FreeAndNil(FList);
  if FFake <> nil then
  begin
    FFake.OnEvaluate := nil;
  end;
  FFake := nil;
  FEvaluator := nil;
  TAtlasTicks.SetClock(nil);
end;

function TAtlasEvalSlicesTests.Place: TAtlasEvalPlace;
begin
  Result := TAtlasEvalPlace.Create('Unit1.pas', 41, False);
end;

function TAtlasEvalSlicesTests.Slice(out AChanged: Boolean): TAtlasEvalSliceStep;
begin
  Result := FSlices.Slice(TArray<TAtlasEvalList>.Create(FList, FOther), Place, AChanged);
end;

function TAtlasEvalSlicesTests.Slice: TAtlasEvalSliceStep;
var
  mChanged: Boolean;
begin
  Result := Slice(mChanged);
end;

function TAtlasEvalSlicesTests.Row(AIndex: Integer): TAtlasEvalNode;
begin
  Result := FList.Roots[AIndex];
end;

procedure TAtlasEvalSlicesTests.EvaluatesAtPlaceWithFieldNames;
var
  mChanged: Boolean;
begin
  FFake.Value('Kunde', '(Name: ''Ada'')');
  FFake.Value('I', '42');
  FList.Add('Kunde');
  FList.Add('I');
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Done), Ord(Slice(mChanged)));
  Assert.IsTrue(mChanged);
  Assert.AreEqual('Kunde,r@Unit1.pas:42' + sLineBreak + 'I,r@Unit1.pas:42', FFake.Calls.Text.TrimRight);
  Assert.AreEqual(Ord(TAtlasEvalState.Value), Ord(Row(0).State));
  Assert.AreEqual('(Name: ''Ada'')', Row(0).Value);
  Assert.AreEqual('42', Row(1).Value);
  Assert.AreEqual(0, Integer(Length(FList.Pending)));
end;

procedure TAtlasEvalSlicesTests.SideEffectsArePassed;
var
  mChanged: Boolean;
begin
  FFake.Value('Count', '3');
  FList.Add('Count');
  FSlices.Slice(TArray<TAtlasEvalList>.Create(FList), TAtlasEvalPlace.Create('A.pas', 0, True), mChanged);
  Assert.AreEqual('Count,r@A.pas:1!', FFake.Calls[0]);
end;

procedure TAtlasEvalSlicesTests.SliceEndsAfterSliceMs;
var
  mChanged: Boolean;
begin
  FCostMs := 20;
  FList.Add('A');
  FList.Add('B');
  FList.Add('C');
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.More), Ord(Slice(mChanged)));
  Assert.IsTrue(mChanged);
  Assert.AreEqual(2, FFake.Calls.Count, 'nach 40 ms ist die Scheibe von 30 ms um');
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Done), Ord(Slice));
  Assert.AreEqual(3, FFake.Calls.Count);
  Assert.AreEqual(Ord(TAtlasEvalState.Error), Ord(Row(2).State), 'unbekannter Bezeichner');
end;

procedure TAtlasEvalSlicesTests.ListsInGivenOrder;
var
  mChanged: Boolean;
begin
  FOther.Add('Zuerst');
  FList.Add('Danach');
  FSlices.Slice(TArray<TAtlasEvalList>.Create(FOther, FList), Place, mChanged);
  Assert.StartsWith('Zuerst', FFake.Calls[0]);
  Assert.StartsWith('Danach', FFake.Calls[1]);
end;

procedure TAtlasEvalSlicesTests.DeferredValueArrivesLater;
begin
  FFake.Defer('Langsam');
  FFake.Value('Schnell', '1');
  FList.Add('Langsam');
  FList.Add('Schnell');
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Wait), Ord(Slice));
  Assert.IsTrue(FSlices.Waiting);
  Assert.IsFalse(FSlices.Overdue);
  Assert.AreEqual(1, FFake.Calls.Count, 'wartet, bevor es weitergeht');
  Assert.IsTrue(FFake.Answer('7', True));
  Assert.IsFalse(FSlices.Waiting);
  Assert.AreEqual(1, FArrived);
  Assert.AreEqual('7', Row(0).Value);
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Done), Ord(Slice));
  Assert.AreEqual('1', Row(1).Value);
end;

procedure TAtlasEvalSlicesTests.WaitingSliceEvaluatesNothing;
begin
  FFake.Defer('Langsam');
  FList.Add('Langsam');
  FList.Add('Danach');
  Slice;
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Wait), Ord(Slice));
  Assert.AreEqual(1, FFake.Calls.Count);
end;

procedure TAtlasEvalSlicesTests.OverdueValueExpires;
begin
  FFake.Defer('Langsam');
  FList.Add('Langsam');
  Slice;
  Inc(FNow, 1999);
  Assert.IsFalse(FSlices.Overdue);
  Inc(FNow);
  Assert.IsTrue(FSlices.Overdue);
  FSlices.Expire;
  Assert.IsFalse(FSlices.Waiting);
  Assert.AreEqual(Ord(TAtlasEvalState.Error), Ord(Row(0).State));
  Assert.AreEqual('timeout', Row(0).Value);
  Assert.AreEqual(1, FFake.Cancels, 'der Debugger erfährt es');
  Assert.IsFalse(FFake.Answer('spät', True), 'Antwort ist verworfen');
  Assert.AreEqual(0, FArrived);
end;

procedure TAtlasEvalSlicesTests.DropCancelsRowAndItsFields;
var
  mRow: TAtlasEvalNode;
begin
  FFake.Value('Kunde', '(Name: ''Ada'')');
  FFake.Defer('Kunde.Name');
  mRow := FList.Add('Kunde');
  Slice;
  mRow.Expanded := True;
  FList.SetFields(mRow, TArray<string>.Create('Name'));
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Wait), Ord(Slice), 'Feld wartet');
  FSlices.Drop(FOther, mRow.Key);
  Assert.IsTrue(FSlices.Waiting, 'andere Liste: nichts zu tun');
  FSlices.Drop(FList, mRow.Key);
  Assert.IsFalse(FSlices.Waiting);
  FList.Delete(0);
  Assert.IsFalse(FFake.Answer('Ada', True));
  Assert.AreEqual(0, FArrived);
end;

procedure TAtlasEvalSlicesTests.DropOfOtherRowKeepsWaiting;
begin
  FFake.Value('A', '1');
  FFake.Defer('B');
  FList.Add('A');
  FList.Add('B');
  Slice;
  FSlices.Drop(FList, Row(0).Key);
  Assert.IsTrue(FSlices.Waiting);
  Assert.IsTrue(FFake.Answer('2', True));
  Assert.AreEqual('2', Row(1).Value);
end;

procedure TAtlasEvalSlicesTests.RowRemovedWhileWaiting;
begin
  FFake.Defer('Weg');
  FList.Add('Weg');
  Slice;
  // Ohne Drop entfernt (etwa Liste ersetzt): Der Wert findet seinen Knoten nicht und fällt weg.
  FList.Delete(0);
  Assert.IsTrue(FFake.Answer('1', True));
  Assert.IsFalse(FSlices.Waiting);
  Assert.AreEqual(1, FArrived);
  Assert.AreEqual(0, FList.Count);
end;

procedure TAtlasEvalSlicesTests.StoppedProcessStopsSlice;
var
  mChanged: Boolean;
begin
  FList.Add('A');
  FFake.Stop;
  Assert.AreEqual(Ord(TAtlasEvalSliceStep.Stopped), Ord(Slice(mChanged)));
  Assert.IsFalse(mChanged);
  Assert.AreEqual(Ord(TAtlasEvalState.Pending), Ord(Row(0).State), 'bleibt offen für den nächsten Halt');
end;

procedure TAtlasEvalSlicesTests.UnavailableErrorIsMarked;
begin
  FSlices.Unavailable := TAtlasEvalUnavailable.Create('<no access>', nil);
  FFake.Fail('Optimiert', 'Inaccessible value');
  FFake.Fail('Fehlt', 'E2029 Expression expected');
  FList.Add('Optimiert');
  FList.Add('Fehlt');
  Slice;
  Assert.AreEqual('<no access> Inaccessible value', Row(0).Value);
  Assert.AreEqual('E2029 Expression expected', Row(1).Value);
end;

procedure TAtlasEvalSlicesTests.EmptyErrorGetsText;
begin
  FFake.Fail('Leer', '');
  FList.Add('Leer');
  Slice;
  Assert.AreEqual('', Row(0).Value, 'Vorgabe: bleibt leer');
  FSlices.EmptyErrorText := 'not evaluable';
  FList.BeginStop;
  Slice;
  Assert.AreEqual('not evaluable', Row(0).Value);
end;

procedure TAtlasEvalSlicesTests.CancelIgnoresLateAnswer;
begin
  FFake.Defer('A');
  FList.Add('A');
  Slice;
  FSlices.Cancel;
  Assert.IsFalse(FSlices.Waiting);
  Assert.IsFalse(FFake.Answer('1', True));
  Assert.AreEqual(Ord(TAtlasEvalState.Pending), Ord(Row(0).State));
  Assert.AreEqual(0, FArrived);
end;

procedure TAtlasEvalSlicesTests.ModifiedValueShowsAfterRestart;
var
  mResult: string;
begin
  // Ablauf von „Ändern …“: ändern, Zeile neu auswerten, als geändert markiert.
  FFake.Value('I', '1');
  FList.Add('I');
  Slice;
  // Zweiter Halt mit demselben Wert: nichts geändert.
  FList.BeginStop;
  Slice;
  Assert.IsFalse(Row(0).Changed);
  Assert.IsTrue(FEvaluator.Modify('I', 'Unit1.pas', 42, '2', mResult));
  Assert.AreEqual('2', mResult);
  TAtlasEvalRows.MarkPending(Row(0));
  Slice;
  Assert.AreEqual('2', Row(0).Value);
  Assert.IsTrue(Row(0).Changed);
  Assert.IsFalse(FEvaluator.Modify('Fehlt', 'Unit1.pas', 42, '3', mResult));
  Assert.AreEqual('cannot modify Fehlt', mResult);
end;

end.
