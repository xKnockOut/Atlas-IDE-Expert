unit Atlas.Common.Editing.Providers.Formatting.Tests;

// Tests für TEditingFormattingProvider: ganze Datei, Zeilenbereich und Syntaxfehler.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingFormattingProviderTests = class
  public
    [Test]
    procedure FormatsWholeFile;
    [Test]
    procedure KeepsLinesOutsideRange;
    [Test]
    procedure ReportsSyntaxError;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract.Formatting,
  Atlas.Common.Editing.Providers.Formatting;

const
  cSchief = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'if True then'#10 +
    'X:=1;'#10'end;'#10'end.';

function Request(const AText: string; AWholeFile: Boolean; AFirstLine, ALastLine: Integer): TEditingFormatRequest;
begin
  Result := Default(TEditingFormatRequest);
  Result.Text := AText;
  Result.Style := TFormatStyle.Default;
  Result.Source := TPascalSource.Default;
  Result.WholeFile := AWholeFile;
  Result.FirstLine := AFirstLine;
  Result.LastLine := ALastLine;
end;

{ TEditingFormattingProviderTests }

procedure TEditingFormattingProviderTests.FormatsWholeFile;
var
  mFormatting: IEditingFormatting;
  mResult: TEditingFormatResult;
begin
  mFormatting := TEditingFormattingProvider.Create;
  mResult := mFormatting.Check(Request(cSchief, True, 0, 0));
  Assert.IsTrue(mResult.Changed);
  Assert.IsFalse(mResult.HasSyntaxError);
  Assert.IsTrue(Length(mResult.Deviations) > 0, 'Abweichungen');
  Assert.Contains(mResult.Formatted, 'X := 1;');
end;

procedure TEditingFormattingProviderTests.KeepsLinesOutsideRange;
var
  mFormatting: IEditingFormatting;
  mResult: TEditingFormatResult;
begin
  mFormatting := TEditingFormattingProvider.Create;
  mResult := mFormatting.Check(Request(cSchief, False, 0, 2));
  Assert.Contains(mResult.Formatted, 'X:=1;');
end;

procedure TEditingFormattingProviderTests.ReportsSyntaxError;
var
  mFormatting: IEditingFormatting;
  mResult: TEditingFormatResult;
begin
  mFormatting := TEditingFormattingProvider.Create;
  mResult := mFormatting.Check(Request('unit U;'#10'interface'#10'procedure ('#10'implementation'#10'end.', True, 0,
    0));
  Assert.IsTrue(mResult.HasSyntaxError);
  Assert.AreNotEqual('', mResult.SyntaxErrorMessage);
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingFormattingProviderTests);

end.
