unit Atlas.Common.Rules.Builtin.Performance.DynamicArrays.Tests;

// Tests der Erkennung dynamischer Arrays: Schreibweisen, RTL-Typen, Typen der Datei; Typen in Klassen, Records und
// Rümpfen zählen nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDynamicArrayTypesTests = class
  public
    [Test]
    procedure RecognizesSpellings;
    [Test]
    procedure FindsFileTypes;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Performance.DynamicArrays;

{ TDynamicArrayTypesTests }

procedure TDynamicArrayTypesTests.RecognizesSpellings;
begin
  Assert.IsTrue(TDynamicArrayTypes.IsDynamic(' array of Integer', nil));
  Assert.IsTrue(TDynamicArrayTypes.IsDynamic('TArray<string>', nil));
  Assert.IsTrue(TDynamicArrayTypes.IsDynamic('TBytes', nil));
  Assert.IsTrue(TDynamicArrayTypes.IsDynamic('TZahlen', TArray<string>.Create('TZahlen')));
  Assert.IsFalse(TDynamicArrayTypes.IsDynamic('string', nil));
  Assert.IsFalse(TDynamicArrayTypes.IsDynamic('array[0..3] of Integer', nil));
end;

procedure TDynamicArrayTypesTests.FindsFileTypes;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TZahlen = array of Integer;'#10'  TNamen = TArray<string>;'#10 +
    '  TFest = array[0..3] of Integer;'#10'  TKlasse = class'#10'  type'#10'    TInnen = array of Byte;'#10 +
    '  end;'#10'implementation'#10'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual('TZahlen,TNamen', string.Join(',', TDynamicArrayTypes.DeclaredIn(cSource, mTree.Root)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDynamicArrayTypesTests);

end.
