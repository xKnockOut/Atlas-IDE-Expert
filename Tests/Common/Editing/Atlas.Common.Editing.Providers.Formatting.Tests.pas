unit Atlas.Common.Editing.Providers.Formatting.Tests;

// Tests für TEditingFormattingProvider: ganze Datei, Zeilenbereich, Syntaxfehler und Formatregeln einer Datei.

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
    /// <summary>StyleOf liest .editorconfig von der Platte; ausdrücklich gesetzte Werte gewinnen.</summary>
    [Test]
    procedure StyleOfReadsEditorConfig;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
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

procedure TEditingFormattingProviderTests.StyleOfReadsEditorConfig;
var
  mFormatting: IEditingFormatting;
  mFolder, mFileName: string;
  mConfigured, mStyle: TFormatStyle;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'Atlas.EditorConfig.' + TGUID.NewGuid.ToString);
  ForceDirectories(mFolder);
  try
    TFile.WriteAllText(TPath.Combine(mFolder, '.editorconfig'),
      'root = true'#10'[*.pas]'#10'indent_style = space'#10'indent_size = 3');
    mFileName := TPath.Combine(mFolder, 'U.pas');
    mFormatting := TEditingFormattingProvider.Create;
    mStyle := mFormatting.StyleOf(mFileName, TFormatStyle.Default);
    Assert.AreEqual(3, mStyle.IndentSize);
    Assert.IsFalse(mStyle.UseTabs);
    mConfigured := TFormatStyle.Default;
    mConfigured.IndentSize := 8;
    mConfigured.Given := [TFormatKey.IndentSize];
    Assert.AreEqual(8, mFormatting.StyleOf(mFileName, mConfigured).IndentSize);
    // Ohne .editorconfig bleibt die Vorgabe.
    Assert.AreEqual(TFormatStyle.Default.IndentSize,
      mFormatting.StyleOf(TPath.Combine(TPath.GetTempPath, 'Fehlt.pas'), TFormatStyle.Default).IndentSize);
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingFormattingProviderTests);

end.
