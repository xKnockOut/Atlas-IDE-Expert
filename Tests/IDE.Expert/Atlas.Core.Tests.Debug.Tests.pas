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
  Found: TDUnitXUnit;
  Selection: TAtlasTestSelection;
begin
  Found := TDUnitXSource.Scan(Sample);
  // Im Rumpf: der Test, Haltepunkt an der ersten Anweisung.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(Found, 19, Selection));
  Assert.AreEqual('Rechner.Tests', Selection.UnitName);
  Assert.AreEqual('TRechnerTests', Selection.Fixture);
  Assert.AreEqual('Addiert', Selection.Method);
  Assert.AreEqual('', Selection.CaseName);
  Assert.AreEqual(18, Selection.BreakLine);
  Assert.AreEqual(1, Length(Selection.Names));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Addiert', Selection.Names[0]);
  Assert.AreEqual('TRechnerTests.Addiert', Selection.Caption);
  // Zeile eines Falls: nur dieser Fall.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(Found, 10, Selection));
  Assert.AreEqual('Summe', Selection.Method);
  Assert.AreEqual('Gross', Selection.CaseName);
  Assert.AreEqual(23, Selection.BreakLine);
  Assert.AreEqual(1, Length(Selection.Names));
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', Selection.Names[0]);
  Assert.AreEqual('TRechnerTests.Summe.Gross', Selection.Caption);
  // Deklaration: alle Fälle.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(Found, 11, Selection));
  Assert.AreEqual('', Selection.CaseName);
  Assert.AreEqual(2, Length(Selection.Names));
  // Fixture: ohne Methode und ohne Haltepunkt.
  Assert.IsTrue(TAtlasTestDebug.SelectAt(Found, 4, Selection));
  Assert.AreEqual('', Selection.Method);
  Assert.AreEqual(-1, Selection.BreakLine);
  Assert.AreEqual('Rechner.Tests.TRechnerTests', Selection.Names[0]);
  Assert.AreEqual('TRechnerTests', Selection.Caption);
end;

procedure TAtlasTestDebugTests.SelectAtOutsideTests;
var
  Found: TDUnitXUnit;
  Selection: TAtlasTestSelection;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.IsFalse(TAtlasTestDebug.SelectAt(Found, 2, Selection));
  Assert.AreEqual(0, Length(Selection.Names));
  Assert.AreEqual(-1, Selection.BreakLine);
  Assert.IsFalse(TAtlasTestDebug.SelectAt(Found, 13, Selection));
  Assert.IsFalse(TAtlasTestDebug.SelectAt(Default(TDUnitXUnit), 0, Selection), 'Unit ohne Tests');
end;

procedure TAtlasTestDebugTests.SelectByNameWithAndWithoutUnit;
var
  Found: TDUnitXUnit;
  Selection: TAtlasTestSelection;
begin
  Found := TDUnitXSource.Scan(Sample);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(Found, 'Rechner.Tests.TRechnerTests.Addiert', Selection));
  Assert.AreEqual('Addiert', Selection.Method);
  Assert.AreEqual(18, Selection.BreakLine);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(Found, 'trechnertests.summe.klein', Selection), 'ohne Unit, klein');
  Assert.AreEqual('Summe', Selection.Method);
  Assert.AreEqual('Klein', Selection.CaseName);
  Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Klein', Selection.Names[0]);
  Assert.IsTrue(TAtlasTestDebug.SelectByName(Found, 'Rechner.Tests.TRechnerTests.Summe', Selection));
  Assert.AreEqual(2, Length(Selection.Names), 'alle Fälle');
  Assert.IsTrue(TAtlasTestDebug.SelectByName(Found, ' Rechner.Tests.TRechnerTests ', Selection));
  Assert.AreEqual('', Selection.Method);
  Assert.IsFalse(TAtlasTestDebug.SelectByName(Found, 'Rechner.Tests.TRechnerTests.Fehlt', Selection));
  Assert.IsFalse(TAtlasTestDebug.SelectByName(Found, 'Andere.TAndere.Addiert', Selection));
  Assert.IsFalse(TAtlasTestDebug.SelectByName(Found, '', Selection));
end;

procedure TAtlasTestDebugTests.SplitArgumentsKeepsQuotes;
var
  Parts: TArray<string>;
begin
  Parts := TAtlasTestDebug.SplitArguments('  -a  "--xmlfile:C:\Mit Leer\r.xml"'#9'b"c d"e ');
  Assert.AreEqual(3, Length(Parts));
  Assert.AreEqual('-a', Parts[0]);
  Assert.AreEqual('"--xmlfile:C:\Mit Leer\r.xml"', Parts[1]);
  Assert.AreEqual('b"c d"e', Parts[2]);
  Assert.AreEqual(0, Length(TAtlasTestDebug.SplitArguments('   ')));
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
  Settings: TAtlasPluginSettings;
  Selection: TAtlasTestSelection;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(TAtlasTestDebug.DebugWanted(Settings));
  Assert.IsTrue(TAtlasTestDebug.RunWanted(Settings));
  Assert.IsTrue(TAtlasTestDebug.LensWanted(Settings));
  Assert.IsTrue(TAtlasTestDebug.LensDebugWanted(Settings));
  // codeLens.tests aus: keine Lens, weder „Test ausführen“ noch „Debuggen“.
  Settings.CodeLensTests := False;
  Assert.IsFalse(TAtlasTestDebug.LensWanted(Settings));
  Assert.IsFalse(TAtlasTestDebug.LensDebugWanted(Settings));
  Settings := TAtlasPluginSettings.Defaults;
  Settings.TestDebug := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(Settings));
  Assert.IsFalse(TAtlasTestDebug.LensDebugWanted(Settings));
  Assert.IsTrue(TAtlasTestDebug.LensWanted(Settings), 'Test ausführen bleibt');
  Settings := TAtlasPluginSettings.Defaults;
  Settings.TestRun := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(Settings), 'braucht Tests ausführen');
  Assert.IsFalse(TAtlasTestDebug.RunWanted(Settings));
  Assert.IsFalse(TAtlasTestDebug.LensWanted(Settings));
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Assert.IsFalse(TAtlasTestDebug.DebugWanted(Settings));
  Assert.IsFalse(TAtlasTestDebug.RunWanted(Settings));
  // Haltepunkt: Einstellung, Methode und Zeile.
  Settings := TAtlasPluginSettings.Defaults;
  Selection := Default(TAtlasTestSelection);
  Selection.Method := 'Addiert';
  Selection.BreakLine := 18;
  Assert.IsTrue(TAtlasTestDebug.BreakWanted(Settings, Selection));
  Selection.BreakLine := -1;
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(Settings, Selection), 'Rumpf unbekannt');
  Selection.BreakLine := 18;
  Selection.Method := '';
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(Settings, Selection), 'ganze Fixture');
  Selection.Method := 'Addiert';
  Settings.TestBreakAtStart := False;
  Assert.IsFalse(TAtlasTestDebug.BreakWanted(Settings, Selection));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestDebugTests);

end.
