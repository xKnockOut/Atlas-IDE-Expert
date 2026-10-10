unit Argus.Common.Dfm.FormInfo.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFormInfoTests = class
  public
    [Test]
    procedure ShowsPropertiesEventsAndLink;
    [Test]
    procedure PictureDataShowsSize;
    [Test]
    procedure OtherBinaryDataShowsSize;
    [Test]
    procedure LongListIsShortened;
    [Test]
    procedure HoverAndDescribeAgree;
    [Test]
    procedure FindsOnlyInMatchingForm;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Dfm.Contract,
  Argus.Common.Dfm.Parser,
  Argus.Common.Dfm.FormInfo;

const
  FormText =
    'object Form1: TForm1'#10 +
    '  Caption = ''Haupt'''#10 +
    '  object btnSpeichern: TButton'#10 +
    '    Left = 8'#10 +
    '    Caption = ''Speichern'''#10 +
    '    OnClick = btnSpeichernClick'#10 +
    '  end'#10 +
    '  object Bild: TImage'#10 +
    '    Picture.Data = {'#10 +
    '      0A544A504547496D616765'#10 +
    '      FFD8}'#10 +
    '    Tag = 1'#10 +
    '  end'#10 +
    '  object Daten: TClientDataSet'#10 +
    '    Params.Data = {'#10 +
    '      0102}'#10 +
    '  end'#10 +
    '  object Liste: TListBox'#10 +
    '    Items.Strings = ('#10 +
    '      ''1'''#10'      ''2'''#10'      ''3'''#10'      ''4'''#10'      ''5'''#10'      ''6'''#10 +
    '      ''7'''#10'      ''8'''#10'      ''9'''#10'      ''10'''#10'      ''11'''#10'      ''12'')'#10 +
    '  end'#10 +
    'end'#10;

function Markdown(const AName: string): string;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(FormText);
  try
    Result := TFormInfo.ComponentMarkdown(TFormInfo.FindComponent(Document, 'TForm1', AName), 'C:\P\Unit1.dfm');
  finally
    Document.Free;
  end;
end;

procedure TFormInfoTests.ShowsPropertiesEventsAndLink;
var
  Text: string;
begin
  Text := Markdown('btnSpeichern');
  Assert.IsTrue(Pos('**In Unit1.dfm** ([Zeile 3](file:///', Text) = 1, Text);
  Assert.IsTrue(Pos('#L3)', Text) > 0, Text);
  Assert.IsTrue(Pos('- Caption = `''Speichern''`', Text) > 0, Text);
  Assert.IsTrue(Pos('- OnClick → `btnSpeichernClick`', Text) > 0, Text);
  Assert.IsTrue(Pos('- Left = `8`', Text) > 0, Text);
end;

procedure TFormInfoTests.PictureDataShowsSize;
var
  Text: string;
begin
  Text := Markdown('Bild');
  Assert.IsTrue(Pos('- Picture.Data = `Bild, 13 Bytes`', Text) > 0, Text);
  Assert.AreEqual(0, Pos('4A504547', Text), 'keine Hex-Daten');
end;

procedure TFormInfoTests.OtherBinaryDataShowsSize;
begin
  Assert.IsTrue(Pos('- Params.Data = `Binärdaten, 2 Bytes`', Markdown('Daten')) > 0);
end;

procedure TFormInfoTests.LongListIsShortened;
var
  Text: string;
begin
  Text := Markdown('Liste');
  Assert.IsTrue(Pos('''9'' ''10'' … 2 weitere)', Text) > 0, Text);
  Assert.AreEqual(0, Pos('''11''', Text), Text);
end;

procedure TFormInfoTests.HoverAndDescribeAgree;
var
  Described: string;
begin
  // get_dfm_info und Hover zeigen dieselben Werte.
  Described := TFormInfo.Describe(FormText);
  Assert.IsTrue(Pos('Picture.Data = Bild, 13 Bytes', Described) > 0, Described);
  Assert.IsTrue(Pos('Caption = ''Speichern''', Described) > 0, Described);
  Assert.IsTrue(Pos('… 2 weitere)', Described) > 0, Described);
  Assert.IsTrue(Pos('Ereignisse: OnClick → btnSpeichernClick', Described) > 0, Described);
end;

procedure TFormInfoTests.FindsOnlyInMatchingForm;
var
  Document: TDfmDocument;
begin
  Document := TDfmParser.Parse(FormText);
  try
    Assert.IsNotNull(TFormInfo.FindComponent(Document, 'TForm1', 'Liste'));
    Assert.IsNull(TFormInfo.FindComponent(Document, 'TAnders', 'Liste'));
    Assert.IsNull(TFormInfo.FindComponent(Document, 'TForm1', 'Fehlt'));
  finally
    Document.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFormInfoTests);

end.
