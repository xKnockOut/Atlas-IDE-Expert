unit Atlas.UI.Designer.StructureFrame.Tests;

// Fenster „Atlas-Struktur“ (#609): Die IDE legt den Frame über die Klasse aus GetFrameClass an
// (TCustomFrame.Create). Ohne DFM-Ressource bricht das mit EResNotFound ab und
// das Fenster öffnet nicht; zwei Frames am selben Besitzer dürfen sich nicht
// über den Namen aus der DFM stören.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasStructureFrameTests = class
  public
    /// <summary>Anlegen wie die IDE: über die Frame-Klasse, mit Formular als Besitzer.</summary>
    [Test]
    procedure CreatesLikeTheIde;
    /// <summary>Zwei Frames am selben Besitzer: kein doppelter Name.</summary>
    [Test]
    procedure TwoFramesShareAnOwner;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.UI.Designer.StructureFrame;

{ TAtlasStructureFrameTests }

procedure TAtlasStructureFrameTests.CreatesLikeTheIde;
var
  mHost: TForm;
  mClass: TCustomFrameClass;
  mFrame: TCustomFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mClass := TAtlasStructureFrame;
    mFrame := mClass.Create(mHost);
    mFrame.Parent := mHost;
    Assert.IsTrue(mFrame is TAtlasStructureFrame);
    Assert.AreEqual('', mFrame.Name, 'Name aus der DFM zurückgesetzt');
    Assert.IsTrue(mFrame.ControlCount > 0, 'Steuerelemente im Code angelegt');
    TAtlasStructureFrame(mFrame).ShowNodes(nil, nil);
    TAtlasStructureFrame(mFrame).MarkName('');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasStructureFrameTests.TwoFramesShareAnOwner;
var
  mHost: TForm;
  mFirst, mSecond: TCustomFrame;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFirst := TAtlasStructureFrame.Create(mHost);
    mSecond := TAtlasStructureFrame.Create(mHost);
    Assert.AreNotSame(mFirst, mSecond);
  finally
    mHost.Free;
  end;
end;

end.
