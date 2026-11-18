unit Atlas.UI.Foundation.ListBox.Tests;

// Liste ohne Flackern: WM_ERASEBKGND füllt nur die Fläche unter der letzten
// Zeile (ohne Zeilen die ganze Liste), am Bildschirm wie beim Löschen in
// einen Puffer (wParam = lParam); die Zeilen bleiben unberührt.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Foundation.ListBox;

type
  [TestFixture]
  TAtlasListBoxTests = class
  private
    FForm: TForm;
    FList: TAtlasListBox;
    FRowPixel: Integer;
    FFreePixel: Integer;
    FResult: NativeInt;
    /// <summary>Bild in Rot in der Größe der Liste, WM_ERASEBKGND mit dessen DC; merkt die Farbe mitten in der
    /// ersten Zeile und unter der letzten. AIntoBuffer wie beim Löschen in einen Puffer (wParam = lParam).</summary>
    procedure Erase(AIntoBuffer: Boolean);
    procedure AddRows(ACount: Integer);
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsRowsOnScreen;
    [Test]
    procedure KeepsRowsIntoBuffer;
    [Test]
    procedure WithoutRowsFillsAll;
    [Test]
    procedure FullListLeavesNothingFree;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics;

const
  cRowHeight = 16;

{ TAtlasListBoxTests }

procedure TAtlasListBoxTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FList := TAtlasListBox.Create(FForm);
  FList.Parent := FForm;
  FList.Style := lbOwnerDrawFixed;
  FList.ItemHeight := cRowHeight;
  FList.BorderStyle := bsNone;
  FList.SetBounds(0, 0, 120, 10 * cRowHeight);
  FList.Color := clLime;
  FList.HandleNeeded;
end;

procedure TAtlasListBoxTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FList := nil;
end;

procedure TAtlasListBoxTests.AddRows(ACount: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 1 to ACount do
  begin
    FList.Items.Add('Zeile');
  end;
end;

procedure TAtlasListBoxTests.Erase(AIntoBuffer: Boolean);
var
  mBitmap: Vcl.Graphics.TBitmap;
  mDC: HDC;
  mLParam: LPARAM;
begin
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.SetSize(FList.ClientWidth, FList.ClientHeight);
    mBitmap.Canvas.Brush.Color := clRed;
    mBitmap.Canvas.FillRect(TRect.Create(0, 0, mBitmap.Width, mBitmap.Height));
    mDC := mBitmap.Canvas.Handle;
    mLParam := 0;
    if AIntoBuffer then
    begin
      mLParam := LPARAM(mDC);
    end;
    // Count und ItemRect schicken der Liste Nachrichten; nach jeder gibt TWinControl.MainWndProc alle
    // ungesperrten Bitmap-DCs frei (FreeMemoryContexts). Gesperrt bleibt mDC gültig.
    mBitmap.Canvas.Lock;
    try
      FResult := FList.Perform(WM_ERASEBKGND, WPARAM(mDC), mLParam);
    finally
      mBitmap.Canvas.Unlock;
    end;
    FRowPixel := ColorToRGB(mBitmap.Canvas.Pixels[4, cRowHeight div 2]);
    FFreePixel := ColorToRGB(mBitmap.Canvas.Pixels[4, mBitmap.Height - 2]);
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasListBoxTests.KeepsRowsOnScreen;
begin
  AddRows(2);
  Erase(False);
  // Die Zeile malt sich selbst; vorher leer gefüllt blitzte sie auf.
  Assert.AreEqual(Integer(ColorToRGB(clRed)), FRowPixel);
  Assert.AreEqual(Integer(ColorToRGB(clLime)), FFreePixel);
  Assert.AreEqual(Integer(1), Integer(FResult));
end;

procedure TAtlasListBoxTests.KeepsRowsIntoBuffer;
begin
  AddRows(2);
  Erase(True);
  Assert.AreEqual(Integer(ColorToRGB(clRed)), FRowPixel);
  Assert.AreEqual(Integer(ColorToRGB(clLime)), FFreePixel);
end;

procedure TAtlasListBoxTests.WithoutRowsFillsAll;
begin
  Erase(False);
  Assert.AreEqual(Integer(ColorToRGB(clLime)), FRowPixel);
  Assert.AreEqual(Integer(ColorToRGB(clLime)), FFreePixel);
end;

procedure TAtlasListBoxTests.FullListLeavesNothingFree;
begin
  AddRows(20);
  Assert.IsTrue(FList.FreeArea.IsEmpty);
  Erase(False);
  Assert.AreEqual(Integer(ColorToRGB(clRed)), FFreePixel);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasListBoxTests);

end.
