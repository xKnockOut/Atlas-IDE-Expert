unit Atlas.Common.Profiling.Sampling.Tests;

// Tests zwischen Prober und Profildatei (#2057): gleiche rohe Stapel zusammenfassen, Adressen im Hauptmodul über
// die Map auflösen (Bibliotheks-Units erkennen), andere Module und unbekannte Adressen, Hauptmodul ohne Map.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProfileSamplingTests = class
  public
    [Test]
    procedure RawStacksMergeEqualStacks;
    [Test]
    procedure ResolverUsesMapForMainModule;
    [Test]
    procedure ResolverWithoutMap;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Common.Profiling.Contract,
  Atlas.Common.Profiling.Profile,
  Atlas.Common.Profiling.Sampling;

const
  cExeBase = $400000;
  cExeSize = $20000;
  cDllBase = $7FF00000;
  cDllSize = $1000;
  // Ausschnitt einer detaillierten Map wie in Atlas.Text.MapFile.Tests: Codesegment ab Modulbasis + $1000.
  cSampleMap =
    ''#13#10 +
    ' Start         Length     Name                   Class'#13#10 +
    ' 0001:00401000 0000A000H .text                   CODE'#13#10 +
    ' 0002:0040B000 00001000H .data                   DATA'#13#10 +
    ''#13#10 +
    ''#13#10 +
    'Detailed map of segments'#13#10 +
    ''#13#10 +
    ' 0001:00000000 00000100 C=CODE     S=.text    G=(none)   M=System   ACBP=A9'#13#10 +
    ' 0001:00000100 00000200 C=CODE     S=.text    G=(none)   M=Shell.Composition ACBP=A9'#13#10 +
    ''#13#10 +
    ''#13#10 +
    '  Address             Publics by Name'#13#10 +
    ''#13#10 +
    ' 0001:00000100       Shell.Composition.TComposition.Run'#13#10 +
    ''#13#10 +
    '  Address             Publics by Value'#13#10 +
    ''#13#10 +
    ' 0001:00000000       System.TObject.Create'#13#10 +
    ' 0001:00000040       System.TObject.Free'#13#10 +
    ' 0001:00000100       Shell.Composition.TComposition.Run'#13#10 +
    ' 0001:00000180       Shell.Composition.TComposition.Stop'#13#10 +
    ' 0002:00000010       Shell.Composition.GlobaleVariable'#13#10 +
    ''#13#10 +
    ''#13#10 +
    'Line numbers for System(System.pas) segment .text'#13#10 +
    ''#13#10 +
    '   100 0001:00000000   101 0001:00000010   110 0001:00000040'#13#10 +
    ''#13#10 +
    'Line numbers for Shell.Composition(Shell.Composition.pas) segment .text'#13#10 +
    ''#13#10 +
    '   500 0001:00000100   501 0001:00000108   503 0001:00000120'#13#10 +
    '   520 0001:00000180'#13#10 +
    ''#13#10 +
    'Bound resource files'#13#10 +
    ''#13#10 +
    'Program entry point at 0001:00000180';

function SampleRun(const AStacks: array of TArray<UInt64>; const ACounts: array of Integer): TAtlasSampleRun;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasSampleRun);
  SetLength(Result.Modules, 2);
  Result.Modules[0].Base := cDllBase;
  Result.Modules[0].Size := cDllSize;
  Result.Modules[0].FileName := 'C:\Windows\System32\ntdll.dll';
  Result.Modules[1].Base := cExeBase;
  Result.Modules[1].Size := cExeSize;
  Result.Modules[1].FileName := 'C:\Bin\App.exe';
  Result.MainModule := 1;
  Result.DurationMs := 1500;
  SetLength(Result.Stacks, Length(AStacks));
  for mIndex := 0 to High(AStacks) do
  begin
    Result.Stacks[mIndex].Addresses := AStacks[mIndex];
    Result.Stacks[mIndex].Count := ACounts[mIndex];
  end;
end;

function FrameNamed(const AProfile: TAtlasProfile; const ARoutine: string): TAtlasProfileFrame;
var
  mFrame: TAtlasProfileFrame;
begin
  for mFrame in AProfile.Frames do
  begin
    if mFrame.Routine = ARoutine then
    begin
      Exit(mFrame);
    end;
  end;
  Assert.Fail('Rahmen fehlt: ' + ARoutine);
  Result := Default(TAtlasProfileFrame);
end;

procedure TAtlasProfileSamplingTests.RawStacksMergeEqualStacks;
var
  mStacks: TAtlasRawStacks;
  mResult: TArray<TAtlasRawStack>;
begin
  mStacks := TAtlasRawStacks.Create;
  try
    mStacks.Add(TArray<UInt64>.Create(1, 2));
    mStacks.Add(TArray<UInt64>.Create(3));
    mStacks.Add(TArray<UInt64>.Create(1, 2));
    // Leerer Stapel zählt nicht; gleiche Adressen in anderer Reihenfolge sind ein anderer Stapel.
    mStacks.Add(nil);
    mStacks.Add(TArray<UInt64>.Create(2, 1));
    Assert.AreEqual(4, mStacks.Samples);
    mResult := mStacks.ToArray;
    Assert.AreEqual(3, Integer(Length(mResult)));
    Assert.AreEqual(2, mResult[0].Count);
    Assert.AreEqual(Int64(2), Int64(mResult[0].Addresses[1]));
    Assert.AreEqual(1, mResult[1].Count);
    Assert.AreEqual(1, mResult[2].Count);
    mStacks.Clear;
    Assert.AreEqual(0, mStacks.Samples);
    Assert.AreEqual(0, Integer(Length(mStacks.ToArray)));
  finally
    mStacks.Free;
  end;
end;

procedure TAtlasProfileSamplingTests.ResolverUsesMapForMainModule;
var
  mMap: TMapFile;
  mResolver: TAtlasProfileResolver;
  mProfile: TAtlasProfile;
  mFrame: TAtlasProfileFrame;
begin
  mMap := TMapFile.Create(cSampleMap);
  try
    // $401124: TComposition.Run Zeile 503; $401044: System.TObject.Free; $7FF00010: ntdll; $10: kein Modul.
    mResolver := TAtlasProfileResolver.Create(SampleRun([TArray<UInt64>.Create($401044, $401124),
      TArray<UInt64>.Create($7FF00010, $401124), TArray<UInt64>.Create($10)], [3, 2, 1]), mMap);
    try
      mProfile := Default(TAtlasProfile);
      mResolver.FillProfile(mProfile);
    finally
      mResolver.Free;
    end;
  finally
    mMap.Free;
  end;
  Assert.AreEqual(6, mProfile.Samples);
  Assert.AreEqual(Int64(1500), mProfile.DurationMs);
  Assert.AreEqual(3, Integer(Length(mProfile.Stacks)));
  mFrame := FrameNamed(mProfile, 'Shell.Composition.TComposition.Run');
  Assert.AreEqual('Shell.Composition', mFrame.UnitName);
  Assert.AreEqual('Shell.Composition.pas', mFrame.FileName);
  Assert.AreEqual(503, mFrame.Line);
  Assert.IsFalse(mFrame.IsLibrary);
  mFrame := FrameNamed(mProfile, 'System.TObject.Free');
  Assert.AreEqual(110, mFrame.Line);
  Assert.IsTrue(mFrame.IsLibrary);
  mFrame := FrameNamed(mProfile, '[ntdll.dll]');
  Assert.IsTrue(mFrame.IsLibrary);
  Assert.AreEqual('', mFrame.FileName);
  Assert.IsTrue(FrameNamed(mProfile, '$10').IsLibrary);
end;

procedure TAtlasProfileSamplingTests.ResolverWithoutMap;
var
  mResolver: TAtlasProfileResolver;
  mFrame: TAtlasProfileFrame;
begin
  mResolver := TAtlasProfileResolver.Create(SampleRun([TArray<UInt64>.Create($401124)], [1]), nil);
  try
    // Ohne Map bleibt der Modulname, zählt aber als eigener Code; dieselbe Adresse liefert denselben Rahmen.
    mFrame := mResolver.Frame($401124);
    Assert.AreEqual('[App.exe]', mFrame.Routine);
    Assert.IsFalse(mFrame.IsLibrary);
    Assert.AreEqual(0, mFrame.Line);
    Assert.AreEqual('[App.exe]', mResolver.Frame($401124).Routine);
  finally
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProfileSamplingTests);

end.
