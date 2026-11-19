unit Atlas.Core.Debug.RoutinePattern.Tests;

// Tests für Muster auf Routinen im Aufrufstapel (#2548) ohne IDE: ganze
// Namen, Klasse.Methode, ganze Unit und Klasse, Platzhalter, Groß- und
// Kleinschreibung, leere Eingaben und die Suche im Stapel.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.RoutinePattern;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasRoutinePatternTests = class
  public
    [Test]
    procedure FullAndTrailingNames;
    [Test]
    procedure WholeUnitAndClass;
    [Test]
    procedure Wildcards;
    [Test]
    procedure EmptyNeverMatches;
    [Test]
    procedure FirstMatchFromIndex;
  end;

implementation

const
  cRoutine = 'Kunden.Import.TKundenImport.LeseZeile';

{ TAtlasRoutinePatternTests }

procedure TAtlasRoutinePatternTests.FullAndTrailingNames;
begin
  Assert.IsTrue(TAtlasRoutinePattern.Matches(cRoutine, cRoutine));
  Assert.IsTrue(TAtlasRoutinePattern.Matches('TKundenImport.LeseZeile', cRoutine));
  Assert.IsTrue(TAtlasRoutinePattern.Matches('tkundenimport.lesezeile', cRoutine), 'Groß-/Kleinschreibung egal');
  Assert.IsTrue(TAtlasRoutinePattern.Matches('LeseZeile', cRoutine));
  // Nur ganze Namensteile: „Zeile“ ist kein Teil für sich.
  Assert.IsFalse(TAtlasRoutinePattern.Matches('Zeile', cRoutine));
  Assert.IsFalse(TAtlasRoutinePattern.Matches('TKundenImport.Schreibe', cRoutine));
end;

procedure TAtlasRoutinePatternTests.WholeUnitAndClass;
begin
  Assert.IsTrue(TAtlasRoutinePattern.Matches('Kunden.Import', cRoutine), 'ganze Unit');
  Assert.IsTrue(TAtlasRoutinePattern.Matches('Kunden', cRoutine), 'Unit-Präfix bis zum Punkt');
  Assert.IsTrue(TAtlasRoutinePattern.Matches('TKundenImport', cRoutine), 'ganze Klasse');
  Assert.IsFalse(TAtlasRoutinePattern.Matches('Kunde', cRoutine), 'nur bis zu einem Punkt');
  Assert.IsFalse(TAtlasRoutinePattern.Matches('Lieferanten.Import', cRoutine));
end;

procedure TAtlasRoutinePatternTests.Wildcards;
begin
  Assert.IsTrue(TAtlasRoutinePattern.Matches('Kunden.*', cRoutine));
  Assert.IsTrue(TAtlasRoutinePattern.Matches('*.LeseZeile', cRoutine));
  Assert.IsTrue(TAtlasRoutinePattern.Matches('TKunden*.Lese*', cRoutine));
  Assert.IsTrue(TAtlasRoutinePattern.Matches('*', cRoutine));
  Assert.IsFalse(TAtlasRoutinePattern.Matches('Lieferanten.*', cRoutine));
  Assert.IsFalse(TAtlasRoutinePattern.Matches('*.Schreibe*', cRoutine));
end;

procedure TAtlasRoutinePatternTests.EmptyNeverMatches;
begin
  Assert.IsFalse(TAtlasRoutinePattern.Matches('', cRoutine));
  Assert.IsFalse(TAtlasRoutinePattern.Matches('  ', cRoutine));
  Assert.IsFalse(TAtlasRoutinePattern.Matches('*', ''), 'Rahmen ohne Namen zählt nie');
end;

procedure TAtlasRoutinePatternTests.FirstMatchFromIndex;
var
  mRoutines: TArray<string>;
begin
  mRoutines := TArray<string>.Create('Kunden.TKunde.SetName', '', 'Kunden.TKundenImport.LeseZeile',
    'Haupt.TForm1.Button1Click');
  Assert.AreEqual(2, TAtlasRoutinePattern.FirstMatch('*.LeseZeile', mRoutines, 1));
  Assert.AreEqual(0, TAtlasRoutinePattern.FirstMatch('Kunden', mRoutines, 0));
  Assert.AreEqual(2, TAtlasRoutinePattern.FirstMatch('Kunden', mRoutines, 1));
  Assert.AreEqual(-1, TAtlasRoutinePattern.FirstMatch('TForm2', mRoutines, 0));
  Assert.AreEqual(-1, TAtlasRoutinePattern.FirstMatch('TForm1', mRoutines, 4), 'hinter dem Ende');
  Assert.AreEqual(-1, TAtlasRoutinePattern.FirstMatch('TForm1', nil, 0), 'leerer Stapel');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRoutinePatternTests);

end.
