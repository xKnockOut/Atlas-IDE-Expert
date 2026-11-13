unit Shell.AffectedTests.Tests;

// Tests für die Host-Rolle der betroffenen Tests (#1353): Testprogramme unter den Projektdateien, Testunits aus
// Muster und uses, Abschalten über tests.affected. Die Zuordnung und Verfolgung testet
// Atlas.Common.Lsp.AffectedTests.Tests, das Holen des Unterschieds Shell.VersionControlChanges.Tests.

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
    /// <summary>#1775: Tests beim Speichern zählen nur die gespeicherten Dateien.</summary>
    [Test]
    procedure OnlyFilesKeepsTheSavedOnes;
    /// <summary>#1775: SinceCommit vergleicht ohne eigene Basis mit HEAD; eine eigene Basis gilt weiter.</summary>
    [Test]
    procedure SinceCommitComparesWithHead;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact,
  Atlas.Common.Lsp.AffectedTests.Contract,
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
      begin
        AText := cTestProgram;
      end
      else if SameText(ExtractFileName(AFileName), 'Mehr.dpr') then
      begin
        AText := cOtherTestProgram;
      end
      else if SameText(ExtractFileName(AFileName), 'App.dpr') then
      begin
        AText := cApplication;
      end
      else
      begin
        AText := '';
      end;
      Result := AText <> '';
    end;
end;

procedure TShellAffectedTestsTests.TestProgramsAreDUnitXMainFiles;
var
  mPrograms: TArray<string>;
begin
  mPrograms := TShellAffectedTests.TestPrograms(TArray<string>.Create('C:\P\App.dpr', 'C:\P\Tests.dpr',
    'C:\P\Kasse.pas', 'C:\P\Fehlt.dpr'), ReadText());
  Assert.AreEqual(1, Integer(Length(mPrograms)));
  Assert.AreEqual('C:\P\Tests.dpr', mPrograms[0]);
end;

procedure TShellAffectedTestsTests.TestScopeJoinsAllPrograms;
var
  mScope: TImpactTestScope;
begin
  mScope := TShellAffectedTests.TestScope('{unit}.Tests', TArray<string>.Create('C:\P\Tests.dpr', 'C:\P\Mehr.dpr'),
    ReadText());
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
    TShellAffectedTests.Run(nil, mSettings, mQuery, TShellAffectedSources.New(nil, nil, ReadText()), mRequest, nil);
  except
    on E: EAffectedTestsOff do
      mMessage := E.Message;
  end;
  Assert.AreEqual(TShellAffectedTests.OffMessage, mMessage);
end;

function Input(const AFileName: string): TAffectedInput;
begin
  Result := Default(TAffectedInput);
  Result.FileName := AFileName;
end;

procedure TShellAffectedTestsTests.OnlyFilesKeepsTheSavedOnes;
var
  mInputs, mKept: TArray<TAffectedInput>;
begin
  mInputs := [Input('C:\Src\Kasse.pas'), Input('C:\Src\Lager.pas'), Input('C:\Src\Kasse.dfm')];
  mKept := TShellAffectedTests.OnlyFiles(mInputs, ['c:/src/kasse.pas', 'C:\Src\Kasse.dfm']);
  Assert.AreEqual(2, Integer(Length(mKept)));
  Assert.AreEqual('C:\Src\Kasse.pas', mKept[0].FileName);
  Assert.AreEqual('C:\Src\Kasse.dfm', mKept[1].FileName);
  Assert.AreEqual(3, Integer(Length(TShellAffectedTests.OnlyFiles(mInputs, nil))), 'ohne Dateien alle');
  Assert.AreEqual(0, Integer(Length(TShellAffectedTests.OnlyFiles(mInputs, ['C:\Src\Neu.pas']))),
    'ungeändert: nichts');
  mInputs := nil;
  mKept := nil;
end;

procedure TShellAffectedTestsTests.SinceCommitComparesWithHead;
var
  mQuery: TShellAffectedQuery;
begin
  mQuery := Default(TShellAffectedQuery);
  Assert.AreEqual('main', TShellAffectedTests.RefOf(mQuery), 'Vorgabe: Merge-Base mit main');
  mQuery.SinceCommit := True;
  Assert.AreEqual('HEAD', TShellAffectedTests.RefOf(mQuery));
  mQuery.Base := 'develop';
  Assert.AreEqual('develop', TShellAffectedTests.RefOf(mQuery), 'eigene Basis gilt');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellAffectedTestsTests);

end.
