unit Atlas.UI.Status.Window.Tests;

// Fenster des Atlas-Statusfelds (#591): zeigt jede Zeile der Registry ohne
// eigene Kenntnis der Zeile, Farben nach Zustand, Knöpfe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ShowsEveryRegisteredLine;
    [Test]
    procedure DotColorsFollowState;
    [Test]
    procedure ButtonsRunAfterClosing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.UI.Strings,
  Atlas.UI.Status.Window;

function Line(const AId: string; AOrder: Integer; AState: TAtlasStatusState; const AText: string): IAtlasStatusItem;
var
  mItem: TAtlasStatusLine;
begin
  mItem := TAtlasStatusLine.Create(nil, AId, AOrder);
  Result := mItem;
  mItem.Update(AText, AState);
end;

procedure TAtlasStatusWindowTests.WarmUpFirstUse;
begin
  ShowsEveryRegisteredLine;
end;

procedure TAtlasStatusWindowTests.ShowsEveryRegisteredLine;
var
  mRegistry: IAtlasStatusRegistry;
  mWindow: TAtlasStatusWindow;
  mHeight2: Integer;
begin
  mRegistry := TAtlasStatusRegistry.Create;
  mRegistry.Add(Line('atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft'));
  mRegistry.Add(Line('atlas.index', 10, TAtlasStatusState.Yellow, 'Index: wird aufgebaut'));
  mWindow := TAtlasStatusWindow.CreateStatus(nil, TAtlasColors.Light);
  try
    mWindow.SetItems(mRegistry.Items);
    Assert.AreEqual(2, Integer(Length(mWindow.Items)));
    mHeight2 := mWindow.ClientHeight;
    // Eine Testzeile eines anderen Issues erscheint ohne Änderung am Fenster.
    mRegistry.Add(Line('test.zeile', 5, TAtlasStatusState.Red, 'Testzeile mit einem recht langen Text, der das ' +
      'Fenster breiter machen muss als die Vorgabe'));
    mWindow.SetItems(mRegistry.Items);
    Assert.AreEqual(3, Integer(Length(mWindow.Items)));
    Assert.AreEqual('test.zeile', mWindow.Items[1].Id);
    Assert.IsTrue(mWindow.ClientHeight > mHeight2, 'eine Zeile höher');
    Assert.IsTrue(mWindow.ClientWidth > 280, 'breiter für den langen Text');
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasStatusWindowTests.DotColorsFollowState;
var
  mColors: TAtlasColors;
begin
  // Signalfarben (#1255) statt der Textfarben Add/Warn/Error/Muted.
  mColors := TAtlasColors.Dark;
  Assert.AreEqual(Int64(mColors.Signals.Get(TAtlasSignalKind.Ok).Fill),
    Int64(mColors.Signals.ForStatus(TAtlasStatusState.Green).Fill));
  Assert.AreEqual(Int64(mColors.Signals.Get(TAtlasSignalKind.Warn).Fill),
    Int64(mColors.Signals.ForStatus(TAtlasStatusState.Yellow).Fill));
  Assert.AreEqual(Int64(mColors.Signals.Get(TAtlasSignalKind.Error).Fill),
    Int64(mColors.Signals.ForStatus(TAtlasStatusState.Red).Fill));
  Assert.AreEqual(Int64(mColors.Signals.Get(TAtlasSignalKind.Idle).Fill),
    Int64(mColors.Signals.ForStatus(TAtlasStatusState.Neutral).Fill));
  Assert.AreNotEqual<TAtlasColor>(mColors.Add, mColors.Signals.ForStatus(TAtlasStatusState.Green).Fill);
end;

procedure TAtlasStatusWindowTests.ButtonsRunAfterClosing;
var
  mWindow: TAtlasStatusWindow;
  mRestarted, mLogged: Integer;
begin
  mRestarted := 0;
  mLogged := 0;
  mWindow := TAtlasStatusWindow.CreateStatus(nil, TAtlasColors.Light);
  try
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.StatusRestartServer), mWindow.RestartButton.Caption);
    mWindow.OnRestart :=
      procedure
      begin
        Inc(mRestarted);
      end;
    mWindow.OnOpenLog :=
      procedure
      begin
        Inc(mLogged);
      end;
    mWindow.RestartButton.Click;
    mWindow.LogButton.Click;
    // Aktionen laufen erst nach dem Schließen; nur die erste zählt.
    Application.ProcessMessages;
    CheckSynchronize;
    Assert.AreEqual(1, mRestarted);
    Assert.AreEqual(0, mLogged);
  finally
    Application.ProcessMessages;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusWindowTests);

end.
