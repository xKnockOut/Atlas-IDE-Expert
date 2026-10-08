unit BDLsp.Common.Lsp.Formatting.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFormattingTests = class
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
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Editing.EditorConfig,
  BDLsp.Common.Lsp.Formatting;

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

{ TLspFormattingTests }

procedure TLspFormattingTests.EditorOptionsAreTheBase;
var
  Json: TJSONObject;
  Style: TFormatStyle;
begin
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', TFormatStyle.Default, nil);
    Assert.AreEqual(4, Style.IndentSize);
    Assert.IsTrue(Style.UseTabs);
    Assert.IsTrue(Style.InsertFinalNewline);
  finally
    Json.Free;
  end;
end;

procedure TLspFormattingTests.EditorConfigOverridesEditor;
var
  Json: TJSONObject;
  Style: TFormatStyle;
begin
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', TFormatStyle.Default, ReadTabsConfig);
    Assert.AreEqual(3, Style.IndentSize);
    Assert.IsFalse(Style.UseTabs);
  finally
    Json.Free;
  end;
end;

procedure TLspFormattingTests.ConfiguredKeysOverrideEditorConfig;
var
  Json: TJSONObject;
  Configured, Style: TFormatStyle;
begin
  Configured := TFormatStyle.Default;
  Configured.IndentSize := 8;
  Configured.KeywordCase := TKeywordCase.Upper;
  Configured.Given := [TFormatKey.IndentSize];
  Json := Options;
  try
    Style := TLspFormatting.Resolve(Json, 'C:\P\Unit1.pas', Configured, ReadTabsConfig);
    Assert.AreEqual(8, Style.IndentSize);
    // Nicht ausdrücklich gesetzt: bleibt beim Wert aus .editorconfig bzw. der Vorgabe.
    Assert.IsFalse(Style.UseTabs);
    Assert.IsTrue(Style.KeywordCase = TKeywordCase.Preserve);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspFormattingTests);

end.
