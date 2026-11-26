unit Atlas.Common.Editing.EditorConfig.Tests;

// TFormatStyles.Resolve: Editor-Optionen als Grundlage, .editorconfig darüber, ausdrücklich gesetzte Werte zuoberst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormatStylesTests = class
  public
    [Test]
    procedure EditorOptionsAreTheBase;
    [Test]
    procedure EditorConfigOverridesEditor;
    [Test]
    procedure ConfiguredKeysOverrideEditorConfig;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.EditorConfig;

function Options: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue('{"tabSize": 4, "insertSpaces": false, "insertFinalNewline": true}') as TJSONObject;
end;

function ReadTabsConfig: TEditorConfigReadFile;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, 'C:\P\.editorconfig');
      AText := 'root = true'#10'[*.pas]'#10'indent_style = space'#10'indent_size = 3';
    end;
end;

{ TFormatStylesTests }

procedure TFormatStylesTests.EditorOptionsAreTheBase;
var
  mJson: TJSONObject;
  mStyle: TFormatStyle;
begin
  mJson := Options;
  try
    mStyle := TFormatStyles.Resolve(mJson, 'C:\P\Unit1.pas', TFormatStyle.Default, nil);
    Assert.AreEqual(4, mStyle.IndentSize);
    Assert.IsTrue(mStyle.UseTabs);
    Assert.IsTrue(mStyle.InsertFinalNewline);
  finally
    mJson.Free;
  end;
end;

procedure TFormatStylesTests.EditorConfigOverridesEditor;
var
  mJson: TJSONObject;
  mStyle: TFormatStyle;
begin
  mJson := Options;
  try
    mStyle := TFormatStyles.Resolve(mJson, 'C:\P\Unit1.pas', TFormatStyle.Default, ReadTabsConfig());
    Assert.AreEqual(3, mStyle.IndentSize);
    Assert.IsFalse(mStyle.UseTabs);
  finally
    mJson.Free;
  end;
end;

procedure TFormatStylesTests.ConfiguredKeysOverrideEditorConfig;
var
  mJson: TJSONObject;
  mConfigured, mStyle: TFormatStyle;
begin
  mConfigured := TFormatStyle.Default;
  mConfigured.IndentSize := 8;
  mConfigured.KeywordCase := TKeywordCase.Upper;
  mConfigured.Given := [TFormatKey.IndentSize];
  mJson := Options;
  try
    mStyle := TFormatStyles.Resolve(mJson, 'C:\P\Unit1.pas', mConfigured, ReadTabsConfig());
    Assert.AreEqual(8, mStyle.IndentSize);
    // Nicht ausdrücklich gesetzt: bleibt beim Wert aus .editorconfig bzw. der Vorgabe.
    Assert.IsFalse(mStyle.UseTabs);
    Assert.AreEqual<TKeywordCase>(TKeywordCase.Preserve, mStyle.KeywordCase);
  finally
    mJson.Free;
  end;
  // Schalter ohne Gegenstück im Editor gelten immer; maxLineLength nur gesetzt vor .editorconfig (#43).
  mConfigured := TFormatStyle.Default;
  mConfigured.Reindent := False;
  mConfigured.BeginPlacement := TBlockPlacement.NewLine;
  mConfigured.AlignComments := True;
  mConfigured.SortUses := True;
  mConfigured.MaxLineLength := 90;
  mStyle := TFormatStyles.Resolve(nil, 'C:\P\Unit1.pas', mConfigured, nil);
  Assert.IsFalse(mStyle.Reindent);
  Assert.AreEqual<TBlockPlacement>(TBlockPlacement.NewLine, mStyle.BeginPlacement);
  Assert.IsTrue(mStyle.AlignComments);
  Assert.IsTrue(mStyle.SortUses);
  Assert.AreEqual(0, mStyle.MaxLineLength);
  mConfigured.Given := [TFormatKey.MaxLineLength];
  mStyle := TFormatStyles.Resolve(nil, 'C:\P\Unit1.pas', mConfigured, nil);
  Assert.AreEqual(90, mStyle.MaxLineLength);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatStylesTests);

end.
