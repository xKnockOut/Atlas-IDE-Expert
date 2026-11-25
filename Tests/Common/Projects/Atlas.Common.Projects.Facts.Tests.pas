unit Atlas.Common.Projects.Facts.Tests;

// Tests für das, was Prüfungen über ein Projekt aus seinen Dateien wissen: Anwendungsart, automatisch erzeugte
// Formulare, Package einer Unit und Warnschalter der .dproj.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectFactsTests = class
  public
    [Test]
    procedure ApplicationKinds;
    [Test]
    procedure ServicesAndLibraries;
    [Test]
    procedure AutoCreatedForms;
    [Test]
    procedure PackageOfUnit;
    [Test]
    procedure WarningEntries;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Projects.PackageReader,
  Atlas.Common.Projects.Facts;

{ TProjectFactsTests }

procedure TProjectFactsTests.ApplicationKinds;
begin
  Assert.AreEqual(Ord(TApplicationKind.Gui), Ord(TProjectFacts.ApplicationKind('',
    'program P;'#10'uses Vcl.Forms;'#10'{$R *.res}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Console), Ord(TProjectFacts.ApplicationKind('',
    'program P;'#10'{$APPTYPE CONSOLE}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Console), Ord(TProjectFacts.ApplicationKind('',
    'program P;'#10'{$IFNDEF TESTINSIGHT}'#10'{$apptype console}'#10'{$ENDIF}'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Console), Ord(TProjectFacts.ApplicationKind('true',
    'program P;'#10'begin'#10'end.')));
  // Auskommentiert zählt nicht.
  Assert.AreEqual(Ord(TApplicationKind.Gui), Ord(TProjectFacts.ApplicationKind('false',
    '// Werkzeug'#10'program P;'#10'// {$APPTYPE CONSOLE}'#10'begin'#10'end.')));
  // DLL ohne Formulare (#1060); writeln-in-gui-app bleibt dort still.
  Assert.AreEqual(Ord(TApplicationKind.Library_), Ord(TProjectFacts.ApplicationKind('',
    'library L;'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Unknown), Ord(TProjectFacts.ApplicationKind('', '')));
  // Packages (#943).
  Assert.AreEqual(Ord(TApplicationKind.Package), Ord(TProjectFacts.ApplicationKind('',
    '// Kopf'#10'package Atlas.IDE.Expert;'#10'requires rtl;'#10'end.')));
end;

procedure TProjectFactsTests.ServicesAndLibraries;
begin
  Assert.AreEqual(Ord(TApplicationKind.Service), Ord(TProjectFacts.ApplicationKind('',
    'program Dienst;'#10'uses'#10'  Vcl.SvcMgr,'#10'  DatenDienst in ''DatenDienst.pas'' {Dienst: TService};'#10 +
    'begin'#10'  Application.Run;'#10'end.')));
  // Dienst, der auch mit Oberfläche startet.
  Assert.AreEqual(Ord(TApplicationKind.Gui), Ord(TProjectFacts.ApplicationKind('',
    'program Dienst;'#10'uses'#10'  Vcl.Forms,'#10'  Vcl.SvcMgr;'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Library_), Ord(TProjectFacts.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  System.SysUtils,'#10'  Formeln in ''Formeln.pas'';'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Library_), Ord(TProjectFacts.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Daten in ''Daten.pas'' {Daten: TDataModule};'#10'begin'#10'end.')));
  // DLL mit Formular: Unknown wie bisher.
  Assert.AreEqual(Ord(TApplicationKind.Unknown), Ord(TProjectFacts.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Haupt in ''Haupt.pas'' {frmHaupt};'#10'begin'#10'end.')));
  Assert.AreEqual(Ord(TApplicationKind.Unknown), Ord(TProjectFacts.ApplicationKind('',
    'library Rechner;'#10'uses'#10'  Vcl.Forms;'#10'begin'#10'end.')));
end;

procedure TProjectFactsTests.AutoCreatedForms;
begin
  // Reihenfolge aus der .dpr.
  Assert.AreEqual('frmHaupt,dmDaten', string.Join(',', TProjectFacts.AutoCreatedForms(
    'program P;'#10'uses Vcl.Forms;'#10'begin'#10'  Application.Initialize;'#10 +
    '  Application.CreateForm(TfrmHaupt, frmHaupt);'#10'  // Application.CreateForm(TfrmAlt, frmAlt);'#10 +
    '  Application.CreateForm(TdmDaten, dmDaten);'#10'  Application.Run;'#10'end.')));
  // Programm, dessen uses die Unit nennt.
  Assert.AreEqual('frmB', string.Join(',', TProjectFacts.FormsOfProgram([
    'program A;'#10'uses Vcl.Forms, Andere;'#10'begin'#10'  Application.CreateForm(TfrmA, frmA);'#10'end.',
    'program B;'#10'uses Vcl.Forms, Haupt in ''Haupt.pas'' {frmB};'#10'begin'#10 +
    '  Application.CreateForm(TfrmB, frmB);'#10'end.'], 'Haupt')));
  Assert.AreEqual(0, Integer(Length(TProjectFacts.FormsOfProgram(['program A;'#10'begin'#10'end.'],
    'Haupt'))));
end;

procedure TProjectFactsTests.PackageOfUnit;
var
  mPackages: TArray<TPackageSource>;
begin
  mPackages := [TPackageReader.Read('package Werkzeuge;'#10'requires rtl;'#10'contains'#10 +
    '  Laden in ''Laden.pas'';'#10'end.')];
  Assert.AreEqual('Werkzeuge', TProjectFacts.PackageNameOf(mPackages, 'laden'));
  Assert.AreEqual('', TProjectFacts.PackageNameOf(mPackages, 'Andere'));
end;

procedure TProjectFactsTests.WarningEntries;
begin
  Assert.AreEqual('SYMBOL_PLATFORM=false', TProjectFacts.WarningEntry('DCC_SYMBOL_PLATFORM', 'false'));
  Assert.AreEqual('UNSAFE_CODE=true', TProjectFacts.WarningEntry('dcc_unsafe_code', ' True '));
  Assert.AreEqual('WARNINGS=false', TProjectFacts.WarningEntry('DCC_Warnings', 'false'));
  Assert.AreEqual('', TProjectFacts.WarningEntry('DCC_UnitSearchPath', 'C:\X'));
  Assert.AreEqual('', TProjectFacts.WarningEntry('DCC_Define', 'DEBUG'));
  Assert.AreEqual('', TProjectFacts.WarningEntry('SYMBOL_PLATFORM', 'false'));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectFactsTests);

end.
