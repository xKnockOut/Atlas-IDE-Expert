unit Atlas.Common.Profiling.Report.Tests;

// Tests für die Auswertung eines Profils (#2057): Eigen- und Gesamtanteil, heißeste Zeile, „Nur eigener Code“
// (Bibliotheksrahmen zusammengefasst), Zeilen für das Wärmeband und Vergleich zweier Läufe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProfileAnalysisTests = class
  public
    [Test]
    procedure ExpensiveMethodComesFirst;
    [Test]
    procedure HotLineIsTheBusiestLine;
    [Test]
    procedure OwnCodeCollapsesLibraryFrames;
    [Test]
    procedure RecursionCountsOncePerSample;
    [Test]
    procedure LinesForHeatBand;
    [Test]
    procedure CompareOrdersByChange;
    [Test]
    procedure PercentWithoutSamples;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Profiling.Profile,
  Atlas.Common.Profiling.Report;

function Frame(const ARoutine: string; ALine: Integer): TAtlasProfileFrame;
begin
  Result := Default(TAtlasProfileFrame);
  Result.Routine := ARoutine;
  Result.UnitName := ARoutine.Substring(0, ARoutine.IndexOf('.'));
  Result.FileName := Result.UnitName + '.pas';
  Result.Line := ALine;
  Result.IsLibrary := TAtlasLibraryUnits.IsLibrary(Result.UnitName);
end;

procedure Add(ABuilder: TAtlasProfileBuilder; const AFrames: array of TAtlasProfileFrame; ATimes: Integer);
var
  mFrames: TArray<TAtlasProfileFrame>;
  mIndex: Integer;
begin
  SetLength(mFrames, Length(AFrames));
  for mIndex := 0 to High(AFrames) do
  begin
    mFrames[mIndex] := AFrames[mIndex];
  end;
  for mIndex := 1 to ATimes do
  begin
    ABuilder.AddSample(mFrames);
  end;
end;

/// <summary>Proben: Expensive AExpensive (Zeile 49 einmal, sonst 48), System.JSON.Parse aus App.Load 3, Main allein
/// 1; die Bibliotheksrahmen liegen in System.pas.</summary>
function Run(AExpensive: Integer): TAtlasProfile;
var
  mBuilder: TAtlasProfileBuilder;
begin
  Result := Default(TAtlasProfile);
  mBuilder := TAtlasProfileBuilder.Create;
  try
    Add(mBuilder, [Frame('App.Expensive', 48), Frame('App.Main', 90)], AExpensive - 1);
    Add(mBuilder, [Frame('App.Expensive', 49), Frame('App.Main', 90)], 1);
    Add(mBuilder, [Frame('System.JSON.Inner', 700), Frame('System.JSON.Parse', 300), Frame('App.Load', 20),
      Frame('App.Main', 91)], 3);
    Add(mBuilder, [Frame('App.Main', 92)], 1);
    mBuilder.FillProfile(Result);
  finally
    mBuilder.Free;
  end;
end;

function Find(const AMethods: TArray<TAtlasProfileMethod>; const ARoutine: string): TAtlasProfileMethod;
var
  mMethod: TAtlasProfileMethod;
begin
  for mMethod in AMethods do
  begin
    if mMethod.Routine = ARoutine then
    begin
      Exit(mMethod);
    end;
  end;
  Result := Default(TAtlasProfileMethod);
end;

procedure TAtlasProfileAnalysisTests.ExpensiveMethodComesFirst;
var
  mMethods: TArray<TAtlasProfileMethod>;
begin
  mMethods := TAtlasProfileAnalysis.Methods(Run(6), False);
  Assert.AreEqual('App.Expensive', mMethods[0].Routine);
  Assert.AreEqual(6, mMethods[0].SelfCount);
  Assert.AreEqual(6, mMethods[0].TotalCount);
  Assert.AreEqual(1, Find(mMethods, 'App.Main').SelfCount);
  Assert.AreEqual(10, Find(mMethods, 'App.Main').TotalCount);
  Assert.AreEqual(3, Find(mMethods, 'System.JSON.Inner').SelfCount);
  Assert.AreEqual(0, Find(mMethods, 'System.JSON.Parse').SelfCount);
  Assert.AreEqual(3, Find(mMethods, 'System.JSON.Parse').TotalCount);
end;

procedure TAtlasProfileAnalysisTests.HotLineIsTheBusiestLine;
var
  mMethods: TArray<TAtlasProfileMethod>;
begin
  mMethods := TAtlasProfileAnalysis.Methods(Run(6), False);
  Assert.AreEqual(48, Find(mMethods, 'App.Expensive').HotLine);
  Assert.AreEqual(5, Find(mMethods, 'App.Expensive').HotLineCount);
  Assert.AreEqual(90, Find(mMethods, 'App.Main').HotLine);
end;

procedure TAtlasProfileAnalysisTests.OwnCodeCollapsesLibraryFrames;
var
  mMethods: TArray<TAtlasProfileMethod>;
  mParse: TAtlasProfileMethod;
begin
  mMethods := TAtlasProfileAnalysis.Methods(Run(6), True);
  Assert.AreEqual('', Find(mMethods, 'System.JSON.Inner').Routine, 'Innereien zusammengefasst');
  mParse := Find(mMethods, 'System.JSON.Parse');
  Assert.AreEqual(3, mParse.SelfCount, 'Anteil beim Aufruf aus eigenem Code');
  Assert.IsTrue(mParse.IsLibrary);
  Assert.AreEqual(3, Find(mMethods, 'App.Load').TotalCount);
end;

procedure TAtlasProfileAnalysisTests.RecursionCountsOncePerSample;
var
  mBuilder: TAtlasProfileBuilder;
  mProfile: TAtlasProfile;
  mMethods: TArray<TAtlasProfileMethod>;
begin
  mProfile := Default(TAtlasProfile);
  mBuilder := TAtlasProfileBuilder.Create;
  try
    Add(mBuilder, [Frame('App.Walk', 10), Frame('App.Walk', 12), Frame('App.Walk', 12), Frame('App.Main', 1)], 2);
    mBuilder.FillProfile(mProfile);
  finally
    mBuilder.Free;
  end;
  mMethods := TAtlasProfileAnalysis.Methods(mProfile, False);
  Assert.AreEqual(2, Find(mMethods, 'App.Walk').TotalCount);
  Assert.AreEqual(2, Find(mMethods, 'App.Walk').SelfCount);
  Assert.AreEqual(10, Find(mMethods, 'App.Walk').HotLine);
end;

procedure TAtlasProfileAnalysisTests.LinesForHeatBand;
var
  mLines: TArray<TAtlasProfileLine>;
begin
  mLines := TAtlasProfileAnalysis.Lines(Run(6), True);
  // App.pas: 20, 48, 49, 90, 91, 92; System.pas: 300 (700 zusammengefasst).
  Assert.AreEqual(7, Integer(Length(mLines)));
  Assert.AreEqual('App.pas', mLines[0].FileName);
  Assert.AreEqual(20, mLines[0].Line);
  Assert.AreEqual(3, mLines[0].Count);
  Assert.AreEqual(48, mLines[1].Line);
  Assert.AreEqual(5, mLines[1].Count);
  Assert.AreEqual(300, mLines[6].Line);
end;

procedure TAtlasProfileAnalysisTests.CompareOrdersByChange;
var
  mDeltas: TArray<TAtlasProfileDelta>;
begin
  // Vorher 6 von 10 Proben in Expensive, nachher 2 von 6.
  mDeltas := TAtlasProfileAnalysis.Compare(Run(6), Run(2), True);
  Assert.AreEqual('App.Expensive', mDeltas[0].Routine);
  Assert.AreEqual(60.0, mDeltas[0].SelfBefore, 0.001);
  Assert.AreEqual(100 * 2 / 6, mDeltas[0].SelfAfter, 0.001);
  Assert.IsTrue(mDeltas[0].SelfChange < 0);
end;

procedure TAtlasProfileAnalysisTests.PercentWithoutSamples;
begin
  Assert.AreEqual(0.0, TAtlasProfileAnalysis.Percent(3, 0), 0.0001);
  Assert.AreEqual(25.0, TAtlasProfileAnalysis.Percent(1, 4), 0.0001);
  Assert.AreEqual(0, Integer(Length(TAtlasProfileAnalysis.Methods(Default(TAtlasProfile), True))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProfileAnalysisTests);

end.
