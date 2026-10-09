unit Argus.UI.Strings.Tests;

// Tests für die Oberflächentexte (#446).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguagesWithSamePlaceholders;
    [Test]
    procedure SwitchesLanguage;
  end;

implementation

uses
  System.SysUtils,
  Argus.UI.Strings;

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

procedure TArgusStringsTests.EveryTextExistsInBothLanguagesWithSamePlaceholders;
var
  Id: TArgusTextId;
  German, English: string;
  Saved: TArgusLanguage;
begin
  Saved := TArgusStrings.Language;
  try
    for Id := Low(TArgusTextId) to High(TArgusTextId) do
    begin
      TArgusStrings.Language := TArgusLanguage.German;
      German := TArgusStrings.Text(Id);
      TArgusStrings.Language := TArgusLanguage.English;
      English := TArgusStrings.Text(Id);
      Assert.IsTrue((German <> '') and (English <> ''), Ord(Id).ToString);
      Assert.AreEqual(Placeholders(German), Placeholders(English), German + ' / ' + English);
    end;
  finally
    TArgusStrings.Language := Saved;
  end;
end;

procedure TArgusStringsTests.SwitchesLanguage;
var
  Saved: TArgusLanguage;
begin
  Saved := TArgusStrings.Language;
  try
    TArgusStrings.Language := TArgusLanguage.German;
    Assert.AreEqual('Enter übernehmen · Esc schließen', TArgusStrings.Text(TArgusTextId.FooterKeys));
    Assert.AreEqual('3 von 84', TArgusStrings.Fmt(TArgusTextId.CountOf, [3, 84]));
    TArgusStrings.Language := TArgusLanguage.English;
    Assert.AreEqual('Enter to accept · Esc to close', TArgusStrings.Text(TArgusTextId.FooterKeys));
    Assert.AreEqual('3 of 84', TArgusStrings.Fmt(TArgusTextId.CountOf, [3, 84]));
  finally
    TArgusStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusStringsTests);

end.
