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
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.UI.Strings,
  Atlas.UI.Status.Window;

function Line(const AId: string; AOrder: Integer; AState: TAtlasStatusState; const AText: string): IAtlasStatusItem;
var
  Item: TAtlasStatusLine;
begin
  Item := TAtlasStatusLine.Create(nil, AId, AOrder);
  Result := Item;
  Item.Update(AText, AState);
end;

procedure TAtlasStatusWindowTests.ShowsEveryRegisteredLine;
var
  Registry: IAtlasStatusRegistry;
  Window: TAtlasStatusWindow;
  Height2: Integer;
begin
  Registry := TAtlasStatusRegistry.Create;
  Registry.Add(Line('atlas.server', 0, TAtlasStatusState.Green, 'Server: läuft'));
  Registry.Add(Line('atlas.index', 10, TAtlasStatusState.Yellow, 'Index: wird aufgebaut'));
  Window := TAtlasStatusWindow.CreateStatus(nil, TAtlasColors.Light);
  try
    Window.SetItems(Registry.Items);
    Assert.AreEqual(2, Integer(Length(Window.Items)));
    Height2 := Window.ClientHeight;
    // Eine Testzeile eines anderen Issues erscheint ohne Änderung am Fenster.
    Registry.Add(Line('test.zeile', 5, TAtlasStatusState.Red, 'Testzeile mit einem recht langen Text, der das ' +
      'Fenster breiter machen muss als die Vorgabe'));
    Window.SetItems(Registry.Items);
    Assert.AreEqual(3, Integer(Length(Window.Items)));
    Assert.AreEqual('test.zeile', Window.Items[1].Id);
    Assert.IsTrue(Window.ClientHeight > Height2, 'eine Zeile höher');
    Assert.IsTrue(Window.ClientWidth > 280, 'breiter für den langen Text');
  finally
    Window.Free;
  end;
end;

procedure TAtlasStatusWindowTests.DotColorsFollowState;
var
  Colors: TAtlasColors;
begin
  Colors := TAtlasColors.Dark;
  Assert.AreEqual(Int64(Colors.Add), Int64(TAtlasStatusWindow.StateColor(Colors, TAtlasStatusState.Green)));
  Assert.AreEqual(Int64(Colors.Warn), Int64(TAtlasStatusWindow.StateColor(Colors, TAtlasStatusState.Yellow)));
  Assert.AreEqual(Int64(Colors.Error), Int64(TAtlasStatusWindow.StateColor(Colors, TAtlasStatusState.Red)));
  Assert.AreEqual(Int64(Colors.Muted), Int64(TAtlasStatusWindow.StateColor(Colors, TAtlasStatusState.Neutral)));
end;

procedure TAtlasStatusWindowTests.ButtonsRunAfterClosing;
var
  Window: TAtlasStatusWindow;
  Restarted, Logged: Integer;
begin
  Restarted := 0;
  Logged := 0;
  Window := TAtlasStatusWindow.CreateStatus(nil, TAtlasColors.Light);
  try
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.StatusRestartServer), Window.RestartButton.Caption);
    Window.OnRestart :=
      procedure
      begin
        Inc(Restarted);
      end;
    Window.OnOpenLog :=
      procedure
      begin
        Inc(Logged);
      end;
    Window.RestartButton.Click;
    Window.LogButton.Click;
    // Aktionen laufen erst nach dem Schließen; nur die erste zählt.
    Application.ProcessMessages;
    CheckSynchronize;
    Assert.AreEqual(1, Restarted);
    Assert.AreEqual(0, Logged);
  finally
    Application.ProcessMessages;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusWindowTests);

end.
