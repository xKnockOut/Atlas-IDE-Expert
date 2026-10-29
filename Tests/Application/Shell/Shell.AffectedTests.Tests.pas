unit Shell.AffectedTests.Tests;

// Tests für die Host-Rolle der betroffenen Tests (#1353): Testprogramme unter den Projektdateien, Testunits aus
// Muster und uses, Abschalten über tests.affected. Die Zuordnung und Verfolgung testet
// Atlas.Common.Lsp.AffectedTests.Tests, das Holen des Unterschieds Shell.VcsChanges.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellAffectedTestsTests = class
  public
    [Test]
    procedure TestProgramsAreDUnitXMainFiles;
    [Test]
    procedure TestScopeJoinsAllPrograms;
    [Test]
    procedure SwitchedOffRaises;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.AffectedTests,
  Shell.AffectedTests;

const
  cTestProgram =
    'program Tests;'#10 +
    'uses'#10 +
    '  DUnitX.TestFramework,'#10 +
    '  Kasse.Tests in ''Kasse.Tests.pas'';'#10 +
    'begin'#10 +
    'end.';
  cOtherTestProgram =
    'program Mehr;'#10 +
    'uses'#10 +
    '  DUnitX.TestFramework,'#10 +
    '  Pruefung.Spezial in ''Pruefung.Spezial.pas'';'#10 +
    'begin'#10 +
    'end.';
  cApplication =
    'program App;'#10 +
    'uses'#10 +
    '  Vcl.Forms;'#10 +
    'begin'#10 +
    'end.';

function ReadText: TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      if SameText(ExtractFileName(AFileName), 'Tests.dpr') then
        AText := cTestProgram
      else if SameText(ExtractFileName(AFileName), 'Mehr.dpr') then
        AText := cOtherTestProgram
      else if SameText(ExtractFileName(AFileName), 'App.dpr') then
        AText := cApplication
      else
        AText := '';
      Result := AText <> '';
    end;
end;

procedure TShellAffectedTestsTests.TestProgramsAreDUnitXMainFiles;
var
  mPrograms: TArray<string>;
begin
  mPrograms := TShellAffectedTests.TestPrograms(TArray<string>.Create('C:\P\App.dpr', 'C:\P\Tests.dpr',
    'C:\P\Kasse.pas', 'C:\P\Fehlt.dpr'), ReadText);
  Assert.AreEqual(1, Integer(Length(mPrograms)));
  Assert.AreEqual('C:\P\Tests.dpr', mPrograms[0]);
end;

procedure TShellAffectedTestsTests.TestScopeJoinsAllPrograms;
var
  mScope: TImpactTestScope;
begin
  mScope := TShellAffectedTests.TestScope('{unit}.Tests', TArray<string>.Create('C:\P\Tests.dpr', 'C:\P\Mehr.dpr'),
    ReadText);
  Assert.IsTrue(mScope.Contains('Kasse.Tests'));
  // Nicht nach dem Muster benannt, aber im zweiten Testprogramm eingebunden.
  Assert.IsTrue(mScope.Contains('Pruefung.Spezial'));
  Assert.IsFalse(mScope.Contains('Kasse'));
end;

procedure TShellAffectedTestsTests.SwitchedOffRaises;
var
  mSettings: TServerSettings;
  mQuery: TShellAffectedQuery;
  mRequest: TAffectedRequest;
  mMessage: string;
begin
  mSettings := TServerSettings.Default;
  mSettings.Tests.Affected := False;
  mQuery := Default(TShellAffectedQuery);
  mRequest := Default(TAffectedRequest);
  mMessage := '';
  try
    // Vor jedem Aufruf von git oder svn: Prozess, Index und Resolver bleiben unbenutzt.
    TShellAffectedTests.Run(nil, mSettings, mQuery, nil, nil, mRequest, ReadText, nil);
  except
    on E: EAffectedTestsOff do
      mMessage := E.Message;
  end;
  Assert.AreEqual(TShellAffectedTests.OffMessage, mMessage);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellAffectedTestsTests);

end.
