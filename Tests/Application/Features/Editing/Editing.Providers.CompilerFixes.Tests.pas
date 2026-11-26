unit Editing.Providers.CompilerFixes.Tests;

// Tests für TEditingCompilerFixesProvider: Korrektur zu einer Meldung, keine Vorschläge für fehlende Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingCompilerFixesProviderTests = class
  public
    [Test]
    procedure H2443AddsUnit;
    [Test]
    procedure E2003WithoutUnitSuggestions;
  end;

implementation

uses
  Editing.Contract.CompilerFixes,
  Editing.Providers.CompilerFixes;

const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'procedure P;'#10 +
    'begin'#10'  X := TStringList.Create;'#10'end;'#10'end.';

{ TEditingCompilerFixesProviderTests }

procedure TEditingCompilerFixesProviderTests.H2443AddsUnit;
var
  mFixes: IEditingCompilerFixes;
  mResult: TArray<TCompilerFix>;
begin
  mFixes := TEditingCompilerFixesProvider.Create;
  mResult := mFixes.Fixes(cSource, TFixMessage.Create(' h2443 ', 7, -1, 'Inline function ''Add'' has not been ' +
    'expanded because unit ''System.Generics.Collections'' is not specified in USES list'));
  Assert.AreEqual(1, Integer(Length(mResult)));
  Assert.AreEqual('H2443', mResult[0].Code);
  Assert.Contains(mResult[0].Edits[0].NewText, 'System.Generics.Collections');
end;

procedure TEditingCompilerFixesProviderTests.E2003WithoutUnitSuggestions;
var
  mFixes: IEditingCompilerFixes;
begin
  mFixes := TEditingCompilerFixesProvider.Create;
  Assert.AreEqual(0, Integer(Length(mFixes.Fixes(cSource, TFixMessage.Create('E2003', 7, 7,
    'Undeclared identifier: ''TStringList''')))));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingCompilerFixesProviderTests);

end.
