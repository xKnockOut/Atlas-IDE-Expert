unit Atlas.UI.Designer.EventFrame.Tests;

// Ereignis-Karte (#612): Die IDE legt den Frame über die Klasse aus GetFrameClass an
// (TCustomFrame.Create). Ohne DFM-Ressource bricht das mit EResNotFound ab und
// das Fenster öffnet nicht; zwei Frames am selben Besitzer dürfen sich nicht
// über den Namen aus der DFM stören.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasEventFrameTests = class
  public
    /// <summary>Anlegen wie die IDE: über die Frame-Klasse, mit Formular als Besitzer.</summary>
    [Test]
    procedure CreatesLikeTheIde;
    /// <summary>Zwei Frames am selben Besitzer: kein doppelter Name.</summary>
    [Test]
    procedure TwoFramesShareAnOwner;
    /// <summary>OnPainted erst, wenn das Fenster zu sehen ist: Daran wacht der ruhende Takt wieder auf, wenn
    /// ein Reiter, eine Leiste oder der Desktop das Fenster wieder zeigt.</summary>
    [Test]
    procedure PaintedOnlyWhenVisible;
  end;

implementation

uses
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.UI.Designer.EventFrame;

{ TAtlasEventFrameTests }

procedure TAtlasEventFrameTests.CreatesLikeTheIde;
var
  mHost: TForm;
  mClass: TCustomFrameClass;
  mFrame: TCustomFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mClass := TAtlasEventFrame;
    mFrame := mClass.Create(mHost);
    mFrame.Parent := mHost;
    Assert.IsTrue(mFrame is TAtlasEventFrame);
    Assert.AreEqual('', mFrame.Name, 'Name aus der DFM zurückgesetzt');
    Assert.IsTrue(mFrame.ControlCount > 0, 'Steuerelemente im Code angelegt');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasEventFrameTests.TwoFramesShareAnOwner;
var
  mHost: TForm;
  mFirst, mSecond: TCustomFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFirst := TAtlasEventFrame.Create(mHost);
    mSecond := TAtlasEventFrame.Create(mHost);
    Assert.AreNotSame(mFirst, mSecond);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasEventFrameTests.PaintedOnlyWhenVisible;
var
  mHost: TForm;
  mFrame: TAtlasEventFrame;
  mCount: Integer;
  mBitmap: TBitmap;
begin
  mCount := 0;
  mHost := TForm.CreateNew(nil);
  try
    mHost.SetBounds(0, 0, 300, 300);
    mFrame := TAtlasEventFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Align := alClient;
    mFrame.OnPainted :=
      procedure
      begin
        Inc(mCount);
      end;
    mHost.HandleNeeded;
    Application.ProcessMessages;
    Assert.AreEqual(0, mCount, 'versteckt: nichts gezeichnet');
    // Zeichnen ohne Bildschirm: Der Testlauf startet versteckt, ein gezeigtes Formular bekäme dort kein WM_PAINT.
    mBitmap := TBitmap.Create;
    try
      mBitmap.SetSize(mHost.ClientWidth, mHost.ClientHeight);
      mFrame.PaintTo(mBitmap.Canvas, 0, 0);
    finally
      mBitmap.Free;
    end;
    Assert.IsTrue(mCount > 0, 'Liste gezeichnet, also zu sehen');
    mFrame.OnPainted := nil;
  finally
    mHost.Free;
  end;
end;

end.
