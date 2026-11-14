unit Atlas.UI.Foundation.EditorFont.Tests;

// Fassung der Editorschrift: übernimmt Name und Größe, trägt die Auszeichnung
// aus Create und baut sich nur bei geänderter Editorschrift neu auf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorFontTests = class
  public
    [Test]
    procedure FollowsNameAndSizeItalic;
    [Test]
    procedure KeepsFontWhileEditorFontIsSame;
    [Test]
    procedure FollowsChangedSize;
    [Test]
    procedure PlainDropsEditorStyle;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Foundation.EditorFont;

const
  cName = 'Consolas';
  cSize = 10;
  cBigger = 14;

procedure TAtlasEditorFontTests.FollowsNameAndSizeItalic;
var
  mEditor: TFont;
  mCopy: TAtlasEditorFont;
begin
  mEditor := TFont.Create;
  mCopy := TAtlasEditorFont.Create([fsItalic]);
  try
    mEditor.Name := cName;
    mEditor.Size := cSize;
    mEditor.Style := [fsBold];
    mCopy.Follow(mEditor);
    Assert.AreEqual(cName, mCopy.Font.Name);
    Assert.AreEqual(cSize, mCopy.Font.Size);
    Assert.AreEqual<TFontStyles>([fsItalic], mCopy.Font.Style);
  finally
    mCopy.Free;
    mEditor.Free;
  end;
end;

procedure TAtlasEditorFontTests.KeepsFontWhileEditorFontIsSame;
var
  mEditor: TFont;
  mCopy: TAtlasEditorFont;
begin
  mEditor := TFont.Create;
  mCopy := TAtlasEditorFont.Create([fsItalic]);
  try
    mEditor.Name := cName;
    mEditor.Size := cSize;
    mCopy.Follow(mEditor);
    mCopy.Font.Color := clRed;
    mEditor.Color := clBlue;
    mCopy.Follow(mEditor);
    Assert.AreEqual(Integer(clRed), Integer(mCopy.Font.Color));
  finally
    mCopy.Free;
    mEditor.Free;
  end;
end;

procedure TAtlasEditorFontTests.FollowsChangedSize;
var
  mEditor: TFont;
  mCopy: TAtlasEditorFont;
begin
  mEditor := TFont.Create;
  mCopy := TAtlasEditorFont.Create([fsItalic]);
  try
    mEditor.Name := cName;
    mEditor.Size := cSize;
    mCopy.Follow(mEditor);
    mEditor.Size := cBigger;
    mCopy.Follow(mEditor);
    Assert.AreEqual(cBigger, mCopy.Font.Size);
    Assert.AreEqual<TFontStyles>([fsItalic], mCopy.Font.Style);
  finally
    mCopy.Free;
    mEditor.Free;
  end;
end;

procedure TAtlasEditorFontTests.PlainDropsEditorStyle;
var
  mEditor: TFont;
  mCopy: TAtlasEditorFont;
begin
  mEditor := TFont.Create;
  mCopy := TAtlasEditorFont.Create([]);
  try
    mEditor.Name := cName;
    mEditor.Style := [fsBold, fsItalic];
    mCopy.Follow(mEditor);
    Assert.AreEqual<TFontStyles>([], mCopy.Font.Style);
  finally
    mCopy.Free;
    mEditor.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorFontTests);

end.
