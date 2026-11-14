unit Atlas.Common.Dfm.FormInfo.Tests;

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
    [Test]
    procedure FieldMarkdownParsesTheForm;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormInfo;

const
  cFormText =
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
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(cFormText);
  try
    Result := TFormInfo.ComponentMarkdown(TFormInfo.FindComponent(mDocument, 'TForm1', AName), 'C:\P\Unit1.dfm');
  finally
    mDocument.Free;
  end;
end;

procedure TFormInfoTests.ShowsPropertiesEventsAndLink;
var
  mText: string;
begin
  mText := Markdown('btnSpeichern');
  Assert.AreEqual(1, Pos('**In Unit1.dfm** ([Zeile 3](file:///', mText), mText);
  Assert.IsTrue(Pos('#L3)', mText) > 0, mText);
  Assert.IsTrue(Pos('- Caption = `''Speichern''`', mText) > 0, mText);
  Assert.IsTrue(Pos('- OnClick → `btnSpeichernClick`', mText) > 0, mText);
  Assert.IsTrue(Pos('- Left = `8`', mText) > 0, mText);
end;

procedure TFormInfoTests.PictureDataShowsSize;
var
  mText: string;
begin
  mText := Markdown('Bild');
  Assert.IsTrue(Pos('- Picture.Data = `Bild, 13 Bytes`', mText) > 0, mText);
  Assert.AreEqual(0, Pos('4A504547', mText), 'keine Hex-Daten');
end;

procedure TFormInfoTests.OtherBinaryDataShowsSize;
begin
  Assert.IsTrue(Pos('- Params.Data = `Binärdaten, 2 Bytes`', Markdown('Daten')) > 0);
end;

procedure TFormInfoTests.LongListIsShortened;
var
  mText: string;
begin
  mText := Markdown('Liste');
  Assert.IsTrue(Pos('''9'' ''10'' … 2 weitere)', mText) > 0, mText);
  Assert.AreEqual(0, Pos('''11''', mText), mText);
end;

procedure TFormInfoTests.HoverAndDescribeAgree;
var
  mDescribed: string;
begin
  // get_dfm_info und Hover zeigen dieselben Werte.
  mDescribed := TFormInfo.Describe(cFormText);
  Assert.IsTrue(Pos('Picture.Data = Bild, 13 Bytes', mDescribed) > 0, mDescribed);
  Assert.IsTrue(Pos('Caption = ''Speichern''', mDescribed) > 0, mDescribed);
  Assert.IsTrue(Pos('… 2 weitere)', mDescribed) > 0, mDescribed);
  Assert.IsTrue(Pos('Ereignisse: OnClick → btnSpeichernClick', mDescribed) > 0, mDescribed);
end;

procedure TFormInfoTests.FindsOnlyInMatchingForm;
var
  mDocument: TDfmDocument;
begin
  mDocument := TDfmParser.Parse(cFormText);
  try
    Assert.IsNotNull(TFormInfo.FindComponent(mDocument, 'TForm1', 'Liste'));
    Assert.IsNull(TFormInfo.FindComponent(mDocument, 'TAnders', 'Liste'));
    Assert.IsNull(TFormInfo.FindComponent(mDocument, 'TForm1', 'Fehlt'));
  finally
    mDocument.Free;
  end;
end;

procedure TFormInfoTests.FieldMarkdownParsesTheForm;
begin
  Assert.AreEqual(Markdown('Liste'), TFormInfo.FieldMarkdown(cFormText, 'C:\P\Unit1.dfm', 'TForm1', 'Liste'));
  Assert.AreEqual('', TFormInfo.FieldMarkdown(cFormText, 'C:\P\Unit1.dfm', 'TAnders', 'Liste'));
  Assert.AreEqual('', TFormInfo.FieldMarkdown('', 'C:\P\Unit1.dfm', 'TForm1', 'Liste'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFormInfoTests);

end.
