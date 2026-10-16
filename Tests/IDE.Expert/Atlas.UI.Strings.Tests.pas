unit Atlas.UI.Strings.Tests;

// Tests für die Oberflächentexte (#446).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguagesWithSamePlaceholders;
    [Test]
    procedure SwitchesLanguage;
    [Test]
    procedure ConfidenceLineForRuleFindings;
    [Test]
    procedure DocLabelsGerman;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Strings;

function Placeholders(const AText: string): string;
var
  Index: Integer;
begin
  // %d und %s in Reihenfolge, z. B. "ds".
  Result := '';
  for Index := 1 to Length(AText) - 1 do
    if AText[Index] = '%' then
      Result := Result + AText[Index + 1];
end;

procedure TAtlasStringsTests.EveryTextExistsInBothLanguagesWithSamePlaceholders;
var
  Id: TAtlasTextId;
  German, English: string;
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    for Id := Low(TAtlasTextId) to High(TAtlasTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      German := TAtlasStrings.Text(Id);
      TAtlasStrings.Language := TAtlasLanguage.English;
      English := TAtlasStrings.Text(Id);
      Assert.IsTrue((German <> '') and (English <> ''), Ord(Id).ToString);
      Assert.AreEqual(Placeholders(German), Placeholders(English), German + ' / ' + English);
    end;
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.ConfidenceLineForRuleFindings;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Konfidenz: mittel', TAtlasStrings.Confidence('medium'));
    Assert.AreEqual('Konfidenz: hoch', TAtlasStrings.Confidence('high'));
    Assert.AreEqual('', TAtlasStrings.Confidence(''), 'Syntax- und Compilermeldungen ohne Konfidenz');
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Confidence: low', TAtlasStrings.Confidence('low'));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.SwitchesLanguage;
var
  Saved: TAtlasLanguage;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Enter übernehmen · Esc schließen', TAtlasStrings.Text(TAtlasTextId.FooterKeys));
    Assert.AreEqual('3 von 84', TAtlasStrings.Fmt(TAtlasTextId.CountOf, [3, 84]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Enter to accept · Esc to close', TAtlasStrings.Text(TAtlasTextId.FooterKeys));
    Assert.AreEqual('3 of 84', TAtlasStrings.Fmt(TAtlasTextId.CountOf, [3, 84]));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasStringsTests.DocLabelsGerman;
var
  Saved: TAtlasLanguage;
  Labels, Expected: TAtlasDocLabels;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Labels := TAtlasStrings.DocLabels;
    Expected := TAtlasDocLabels.German;
    Assert.AreEqual(Expected.TypeParams, Labels.TypeParams);
    Assert.AreEqual(Expected.Value, Labels.Value);
    Assert.AreEqual(Expected.Example, Labels.Example);
    Assert.AreEqual(Expected.SeeAlso, Labels.SeeAlso);
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStringsTests);

end.
