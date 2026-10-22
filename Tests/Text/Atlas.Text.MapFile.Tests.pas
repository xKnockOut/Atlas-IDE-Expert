unit Atlas.Text.MapFile.Tests;

// Tests für das Lesen der Map-Datei und das Auflösen von Stacktraces (#282).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMapFileTests = class
  public
    [Test]
    procedure ReadsPublicsAndLines;
    [Test]
    procedure ResolvesOffsetToRoutineAndLine;
    [Test]
    procedure OffsetsOutsideCodeAreNotFound;
    [Test]
    procedure SymbolizesStackTrace;
    [Test]
    procedure OtherTextGivesEmptyMap;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile;

const
  // Ausschnitt einer detaillierten Map (DCC_MapFile=3) im Aufbau des Delphi-Linkers.
  SampleMap =
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

procedure TMapFileTests.ReadsPublicsAndLines;
var
  Map: TMapFile;
begin
  Map := TMapFile.Create(SampleMap);
  try
    // Publics by Name wird übergangen, Datensegment zählt nicht.
    Assert.AreEqual(4, Map.SymbolCount);
  finally
    Map.Free;
  end;
end;

procedure TMapFileTests.ResolvesOffsetToRoutineAndLine;
var
  Map: TMapFile;
  Location: TMapLocation;
begin
  Map := TMapFile.Create(SampleMap);
  try
    // Codesegment ab Modulbasis + $1000: Offset $1124 ist Adresse $124 in TComposition.Run.
    Location := Map.Resolve($1124);
    Assert.IsTrue(Location.Found);
    Assert.AreEqual('Shell.Composition.TComposition.Run', Location.Routine);
    Assert.AreEqual('Shell.Composition', Location.UnitName);
    Assert.AreEqual('Shell.Composition.pas', Location.FileName);
    Assert.AreEqual(503, Location.Line);
    Assert.AreEqual('Shell.Composition.TComposition.Run (Shell.Composition.pas:503)', Location.ToString);
    Location := Map.Resolve($1044);
    Assert.AreEqual('System.TObject.Free', Location.Routine);
    Assert.AreEqual(110, Location.Line);
  finally
    Map.Free;
  end;
end;

procedure TMapFileTests.OffsetsOutsideCodeAreNotFound;
var
  Map: TMapFile;
begin
  Map := TMapFile.Create(SampleMap);
  try
    Assert.IsFalse(Map.Resolve($200).Found);
    Assert.AreEqual('', Map.Resolve($10).ToString);
  finally
    Map.Free;
  end;
end;

procedure TMapFileTests.SymbolizesStackTrace;
var
  Map: TMapFile;
  Trace: string;
begin
  Map := TMapFile.Create(SampleMap);
  try
    Trace := Map.Symbolize('AtlasServer.exe+$1124'#13#10'kernel32.dll+$1A2B'#13#10'AtlasServer.exe+$1004'#13#10,
      'AtlasServer.exe');
    Assert.AreEqual(
      'AtlasServer.exe+$1124 Shell.Composition.TComposition.Run (Shell.Composition.pas:503)' + sLineBreak +
      'kernel32.dll+$1A2B' + sLineBreak +
      'AtlasServer.exe+$1004 System.TObject.Create (System.pas:100)' + sLineBreak, Trace);
  finally
    Map.Free;
  end;
end;

procedure TMapFileTests.OtherTextGivesEmptyMap;
var
  Map: TMapFile;
begin
  Map := TMapFile.Create('keine Map');
  try
    Assert.AreEqual(0, Map.SymbolCount);
    Assert.IsFalse(Map.Resolve($1000).Found);
    Assert.AreEqual('A+$1000' + sLineBreak, Map.Symbolize('A+$1000', 'A'));
  finally
    Map.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMapFileTests);

end.
