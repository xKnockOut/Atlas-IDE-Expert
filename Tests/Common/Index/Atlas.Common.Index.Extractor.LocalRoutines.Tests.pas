unit Atlas.Common.Index.Extractor.LocalRoutines.Tests;

// Tests der lokalen Routinen im Index (Atlas.Common.Index.Extractor.LocalRoutines): Ebenen, Container, Namensstelle,
// nur Projekt-Units, getrennt von Symbols, Cache und kompakte Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexLocalRoutinesTests = class
  public
    [Test]
    procedure CollectsNestedLocalRoutinesWithTheirRoutine;
    [Test]
    procedure KeepsLocalRoutinesOutOfSymbols;
    [Test]
    procedure OnlyProjectUnitsCollectLocalRoutines;
    [Test]
    procedure ProgramRoutinesHaveLocalRoutinesToo;
    [Test]
    procedure CacheKeepsLocalRoutines;
    [Test]
    procedure CompactUnitDropsLocalRoutines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.Extractor;

const
  cCode =
    'unit uLokal;'#10 +                       // 0
    'interface'#10 +                          // 1
    'type'#10 +                               // 2
    '  TFoo = class'#10 +                     // 3
    '    procedure Bar;'#10 +                 // 4
    '  end;'#10 +                             // 5
    'implementation'#10 +                     // 6
    'procedure TFoo.Bar;'#10 +                // 7
    '  procedure Aussen;'#10 +                // 8
    '    function Innen: Integer;'#10 +       // 9
    '    begin'#10 +                          // 10
    '      Result := 1;'#10 +                 // 11
    '    end;'#10 +                           // 12
    '  begin'#10 +                            // 13
    '    Innen;'#10 +                         // 14
    '  end;'#10 +                             // 15
    'begin'#10 +                              // 16
    '  Aussen;'#10 +                          // 17
    'end;'#10 +                               // 18
    'procedure Frei;'#10 +                    // 19
    '  procedure Hilf; begin end;'#10 +       // 20
    'begin'#10 +                              // 21
    '  Hilf;'#10 +                            // 22
    'end;'#10 +                               // 23
    'end.';                                   // 24

/// <summary>Index-Eintrag einer Projekt-Unit (mit Folgemustern und lokalen Routinen).</summary>
function ProjectUnit(const AText: string): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, 'C:\P\uLokal.pas', nil, nil, False, True);
end;

/// <summary>"Container.Name" je lokaler Routine, durch Komma getrennt.</summary>
function LocalNames(const AUnit: TUnitIndex): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.LocalRoutines do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mSymbol.Container + '.' + mSymbol.Name;
  end;
end;

{ TIndexLocalRoutinesTests }

procedure TIndexLocalRoutinesTests.CollectsNestedLocalRoutinesWithTheirRoutine;
var
  mUnit: TUnitIndex;
begin
  mUnit := ProjectUnit(cCode);
  Assert.AreEqual('TFoo.Bar.Aussen,TFoo.Bar.Aussen.Innen,Frei.Hilf', LocalNames(mUnit));
  Assert.AreEqual(9, mUnit.LocalRoutines[1].SelectionRange.StartPos.Line, 'Name von Innen');
  Assert.AreEqual(13, mUnit.LocalRoutines[1].SelectionRange.StartPos.Character);
  Assert.AreEqual(9, mUnit.LocalRoutines[1].Range.StartPos.Line);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Routine, mUnit.LocalRoutines[0].Kind);
  Assert.AreEqual<TIndexVisibility>(TIndexVisibility.Private, mUnit.LocalRoutines[0].Visibility);
  Assert.IsFalse(mUnit.LocalRoutines[0].InInterface);
end;

procedure TIndexLocalRoutinesTests.KeepsLocalRoutinesOutOfSymbols;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ProjectUnit(cCode).Symbols do
  begin
    Assert.IsFalse(SameText(mSymbol.Name, 'Aussen') or SameText(mSymbol.Name, 'Innen') or
      SameText(mSymbol.Name, 'Hilf'), mSymbol.Name);
  end;
end;

procedure TIndexLocalRoutinesTests.OnlyProjectUnitsCollectLocalRoutines;
begin
  Assert.AreEqual(0, Integer(Length(TIndexExtractor.ExtractText(cCode, 'C:\P\uLokal.pas', nil, nil,
    True).LocalRoutines)), 'Bibliothek');
  Assert.AreEqual(0, Integer(Length(TIndexExtractor.ExtractText(cCode, 'C:\P\uLokal.pas', nil).LocalRoutines)));
end;

procedure TIndexLocalRoutinesTests.ProgramRoutinesHaveLocalRoutinesToo;
begin
  Assert.AreEqual('Start.Pruefe', LocalNames(ProjectUnit('program P;'#10 +
    'procedure Start;'#10 +
    '  procedure Pruefe; begin end;'#10 +
    'begin'#10 +
    '  Pruefe;'#10 +
    'end;'#10 +
    'begin'#10 +
    '  Start;'#10 +
    'end.')));
end;

procedure TIndexLocalRoutinesTests.CacheKeepsLocalRoutines;
var
  mRead: TArray<TUnitIndex>;
begin
  mRead := TIndexCache.Deserialize(TIndexCache.Serialize([ProjectUnit(cCode)]));
  Assert.AreEqual(1, Integer(Length(mRead)));
  Assert.AreEqual('TFoo.Bar.Aussen,TFoo.Bar.Aussen.Innen,Frei.Hilf', LocalNames(mRead[0]));
  Assert.AreEqual(20, mRead[0].LocalRoutines[2].SelectionRange.StartPos.Line);
end;

procedure TIndexLocalRoutinesTests.CompactUnitDropsLocalRoutines;
var
  mUnit: TUnitIndex;
begin
  mUnit := ProjectUnit(cCode);
  Assert.IsTrue(TIndexMemory.UnitBytes(mUnit) > TIndexMemory.UnitBytes(TIndexMemory.Compacted(mUnit)));
  Assert.AreEqual(0, Integer(Length(TIndexMemory.Compacted(mUnit).LocalRoutines)));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexLocalRoutinesTests);

end.
