unit Atlas.Core.Tests.Debug.Tests;

// Tests für „Test debuggen“ (#585) ohne IDE: Auswahl an einer Zeile und zum
// vollen Namen, Namen für --run (je [TestCase]-Fall), Haltepunktzeile,
// Startparameter (vorhandene bleiben, störende Optionen fallen weg) und die
// Schalter für Lens, Befehle und Haltepunkt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestDebugTests = class
  public
    [Test]
    procedure SelectAtTestCaseAndFixture;
    [Test]
    procedure SelectAtOutsideTests;
    [Test]
    procedure SelectByNameWithAndWithoutUnit;
    [Test]
    procedure SplitArgumentsKeepsQuotes;
    [Test]
    procedure OptionNames;
    [Test]
    procedure ParametersReplaceFilterAndKeepOthers;
    [Test]
    procedure SwitchesFollowSettings;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Debug;

function Sample: TArray<string>;
begin
  Result := [
    'unit Rechner.Tests;',                                      // 0
    'interface',                                                // 1
    'uses DUnitX.TestFramework;',                               // 2
    'type',                                                     // 3
    '  [TestFixture]',                                          // 4
    '  TRechnerTests = class',                                  // 5
    '  public',                                                 // 6
    '    [Test]',                                               // 7
    '    procedure Addiert;',                                   // 8
    '    [TestCase(''Klein'', ''1,2,3'')]',                     // 9
    '    [TestCase(''Gross'', ''10,20,30'')]',                  // 10
    '    procedure Summe(A, B, C: Integer);',                   // 11
    '  end;',                                                   // 12
    'implementation',                                           // 13
    'procedure TRechnerTests.Addiert;',                         // 14
    'var',                                                      // 15
    '  X: Integer;',                                            // 16
    'begin',                                                    // 17
    '  X := 1 + 2;',                                            // 18
    '  Assert.AreEqual(3, X);',                                 // 19
    'end;',                                                     // 20
    'procedure TRechnerTests.Summe(A, B, C: Integer);',         // 21
    'begin',                                                    // 22
    '  Assert.AreEqual(C, A + B);',                             // 23
    'end;',                                                     // 24
    'end.'];                                                    // 25
end;

{ TAtlasTestDebugTests }

procedure TAtlasTestDebugTests.SelectAtTestCaseAndFixture;
var
  mFound: TDUnitXUnit;
  mSelection: TAtlasTestSelection;
begin
  mFound := TDUnitXSource.Scan(Sample);
  // Im Rumpf: der Test, Haltepunkt an der ersten Anweisung.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(mFound, 19, mSelection));
  Assert.AreEqual('Rechner.Tests', mSelection.UnitName);
  Assert.AreEqual('TRechnerTests', mSelection.Fixture);
  Assert.AreEqual('Addiert', mSelection.Method);
  Assert.AreEqual('', mSelection.CaseName);
  Assert.AreEqual(18, mSelection.BreakLine);
  Assert.AreEqual(1, Integer(Length(mSelection.Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert', mSelection.Names[0]);
  Assert.AreEqual('TRechnerTests.Addiert', mSelection.Caption);
  // Zeile eines Falls: nur dieser Fall.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(mFound, 10, mSelection));
  Assert.AreEqual('Summe', mSelection.Method);
  Assert.AreEqual('Gross', mSelection.CaseName);
  Assert.AreEqual(23, mSelection.BreakLine);
  Assert.AreEqual(1, Integer(Length(mSelection.Names)));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mSelection.Names[0]);
  Assert.AreEqual('TRechnerTests.Summe.Gross', mSelection.Caption);
  // Deklaration: alle Fälle.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(mFound, 11, mSelection));
  Assert.AreEqual('', mSelection.CaseName);
  Assert.AreEqual(2, Integer(Length(mSelection.Names)));
  // Fixture: ohne Methode und ohne Haltepunkt.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(mFound, 4, mSelection));
  Assert.AreEqual('', mSelection.Method);
  Assert.AreEqual(-1, mSelection.BreakLine);
  Assert.AreEqual('Rechner.Tests.TRechnerTests', mSelection.Names[0]);
  Assert.AreEqual('TRechnerTests', mSelection.Caption);
end;

procedure TAtlasTestDebugTests.SelectAtOutsideTests;
var
  mFound: TDUnitXUnit;
  mSelection: TAtlasTestSelection;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.IsFalse(TAtlasTestDebug.SelectAt(mFound, 2, mSelection));
  Assert.AreEqual(0, Integer(Length(mSelection.Names)));
  Assert.AreEqual(-1, mSelection.BreakLine);
  Assert.IsFalse(TAtlasTestDebug.SelectAt(mFound, 13, mSelection));
  Assert.IsFalse(TAtlasTestDebug.SelectAt(Default(TDUnitXUnit), 0, mSelection), 'Unit ohne Tests');
end;

procedure TAtlasTestDebugTests.SelectByNameWithAndWithoutUnit;
var
  mFound: TDUnitXUnit;
  mSelection: TAtlasTestSelection;
begin
  mFound := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(mFound, 'Rechner.Tests.TRechnerTests.Addiert', mSelection));
  Assert.AreEqual('Addiert', mSelection.Method);
  Assert.AreEqual(18, mSelection.BreakLine);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(mFound, 'trechnertests.summe.klein', mSelection), 'ohne Unit, klein');
  Assert.AreEqual('Summe', mSelection.Method);
  Assert.AreEqual('Klein', mSelection.CaseName);
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Klein', mSelection.Names[0]);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(mFound, 'Rechner.Tests.TRechnerTests.Summe', mSelection));
  Assert.AreEqual(2, Integer(Length(mSelection.Names)), 'alle Fälle');
  Assert.IsTrue(TAtlasTestDebug.SelectByName(mFound, ' Rechner.Tests.TRechnerTests ', mSelection));
  Assert.AreEqual('', mSelection.Method);
  Assert.IsFalse(TAtlasTestDebug.SelectByName(mFound, 'Rechner.Tests.TRechnerTests.Fehlt', mSelection));
  Assert.IsFalse(TAtlasTestDebug.SelectByName(mFound, 'Andere.TAndere.Addiert', mSelection));
  Assert.IsFalse(TAtlasTestDebug.SelectByName(mFound, '', mSelection));
end;

procedure TAtlasTestDebugTests.SplitArgumentsKeepsQuotes;
var
  mParts: TArray<string>;
begin
  mParts := TAtlasTestDebug.SplitArguments('  -a  "--xmlfile:C:\Mit Leer\r.xml"'#9'b"c d"e ');
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual('-a', mParts[0]);
  Assert.AreEqual('"--xmlfile:C:\Mit Leer\r.xml"', mParts[1]);
  Assert.AreEqual('b"c d"e', mParts[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasTestDebug.SplitArguments('   '))));
  Assert.AreEqual('"--xmlfile:C:\Mit Leer\r.xml"', TAtlasTestDebug.QuoteArgument('--xmlfile:C:\Mit Leer\r.xml'));
  Assert.AreEqual('--run:A.B', TAtlasTestDebug.QuoteArgument('--run:A.B'));
end;

procedure TAtlasTestDebugTests.OptionNames;
begin
  Assert.AreEqual('run', TAtlasTestDebug.OptionName('--RUN:A.B'));
  Assert.AreEqual('r', TAtlasTestDebug.OptionName('-r:A.B'));
  Assert.AreEqual('xmlfile', TAtlasTestDebug.OptionName('/xmlfile:x.xml'));
  Assert.AreEqual('xmlfile', TAtlasTestDebug.OptionName('"--xmlfile:C:\Mit Leer\r.xml"'));
  Assert.AreEqual('exitbehavior', TAtlasTestDebug.OptionName('--exitbehavior:Pause'));
  Assert.AreEqual('', TAtlasTestDebug.OptionName('Datei.txt'), 'kein Optionszeichen');
end;

procedure TAtlasTestDebugTests.ParametersReplaceFilterAndKeepOthers;
begin
  Assert.AreEqual('--run:U.T.A,U.T.B --exitbehavior:Continue --xmlfile:r.xml',
    TAtlasTestDebug.Parameters('', ['U.T.A', '', 'U.T.B'], 'r.xml'));
  Assert.AreEqual('-cfg "C:\Mit Leer\a.ini" --run:U.T.A --exitbehavior:Continue',
    TAtlasTestDebug.Parameters('-cfg "C:\Mit Leer\a.ini" --run:Alt -exit:Pause /xml:alt.xml -i:Langsam -e:X -h',
    ['U.T.A'], ''));
  Assert.AreEqual('--exitbehavior:Continue "--xmlfile:C:\Mit Leer\r.xml"',
    TAtlasTestDebug.Parameters('--runlist:liste.txt -rl:x --include:A --exclude:B', nil, 'C:\Mit Leer\r.xml'));
  Assert.AreEqual('"--run:U.T.Fall mit Leer" --exitbehavior:Continue',
    TAtlasTestDebug.Parameters('', ['U.T.Fall mit Leer'], ''), 'Fallname mit Leerzeichen');
end;

procedure TAtlasTestDebugTests.SwitchesFollowSettings;
var
  mSettings: TAtlasPluginSettings;
  mSelection: TAtlasTestSelection;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasTestDebug.DebugWanted(mSettings));
  Assert.IsTrue(TAtlasTestDebug.RunWanted(mSettings));
  Assert.IsTrue(TAtlasTestDebug.LensWanted(mSettings));
  Assert.IsTrue(TAtlasTestDebug.LensDebugWanted(mSettings));
  // codeLens.tests aus: keine Lens, weder „Test ausführen“ noch „Debuggen“, auch nicht über Befehl und
  // Kontextmenü (#585: Atlas verhält sich wie ohne die Funktion).
  mSettings.CodeLensTests := False;
  Assert.IsFalse(TAtlasTestDebug.LensWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.LensDebugWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.RunWanted(mSettings));
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.TestDebug := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.LensDebugWanted(mSettings));
  Assert.IsTrue(TAtlasTestDebug.LensWanted(mSettings), 'Test ausführen bleibt');
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.TestRun := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(mSettings), 'braucht Tests ausführen');
  Assert.IsFalse(TAtlasTestDebug.RunWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.LensWanted(mSettings));
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.Enabled := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(mSettings));
  Assert.IsFalse(TAtlasTestDebug.RunWanted(mSettings));
  // Haltepunkt: Einstellung, Methode und Zeile.
  mSettings := TAtlasPluginSettings.Defaults;
  mSelection := Default(TAtlasTestSelection);
  mSelection.Method := 'Addiert';
  mSelection.BreakLine := 18;
  Assert.IsTrue(TAtlasTestDebug.BreakWanted(mSettings, mSelection));
  mSelection.BreakLine := -1;
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(mSettings, mSelection), 'Rumpf unbekannt');
  mSelection.BreakLine := 18;
  mSelection.Method := '';
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(mSettings, mSelection), 'ganze Fixture');
  mSelection.Method := 'Addiert';
  mSettings.TestBreakAtStart := False;
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(mSettings, mSelection));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestDebugTests);

end.
