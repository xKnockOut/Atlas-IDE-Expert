unit Atlas.UI.Foundation.WndProcHook.Tests;

// Eingehängte Fensterprozedur mit Kettenprüfung (#1976): Aushängen setzt den
// Vorgänger nur zurück, wenn der Haken noch oben liegt; sonst bleibt er als
// Durchreicher in der fremden Kette und ruft den Besitzer nicht mehr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWndProcHookTests = class
  public
    [Test]
    procedure HandlerGetsMessagesAndPassesThemOn;
    [Test]
    procedure UnhookOnTopRestoresPrevious;
    /// <summary>Eine andere Erweiterung hängt sich danach ein: Ihre Prozedur bleibt oben, der Haken reicht durch.
    /// </summary>
    [Test]
    procedure ForeignProcOnTopStaysInChain;
    [Test]
    procedure UnhookOfNilIsClean;
  end;

implementation

uses
  Winapi.Messages,
  System.Classes,
  Vcl.Controls,
  Atlas.UI.Foundation.WndProcHook;

const
  cProbe = WM_USER + 4711;

type
  /// <summary>Zählt Nachrichten und reicht sie an Old bzw. an den Haken weiter.</summary>
  TRecorder = class
  public
    Count: Integer;
    Old: TWndMethod;
    Hook: TAtlasWndProcHook;
    procedure Handle(var AMessage: TMessage);
  end;

procedure TRecorder.Handle(var AMessage: TMessage);
begin
  if AMessage.Msg = cProbe then
  begin
    Inc(Count);
  end;
  if Hook <> nil then
  begin
    Hook.CallOld(AMessage);
  end
  else if Assigned(Old) then
  begin
    Old(AMessage);
  end;
end;

procedure Send(AControl: TControl);
var
  mMessage: TMessage;
  mProc: TWndMethod;
begin
  mMessage := Default(TMessage);
  mMessage.Msg := cProbe;
  mProc := AControl.WindowProc;
  mProc(mMessage);
end;

function Same(const ALeft, ARight: TWndMethod): Boolean;
begin
  Result := (TMethod(ALeft).Code = TMethod(ARight).Code) and (TMethod(ALeft).Data = TMethod(ARight).Data);
end;

{ TAtlasWndProcHookTests }

procedure TAtlasWndProcHookTests.HandlerGetsMessagesAndPassesThemOn;
var
  mControl: TControl;
  mBottom, mOwner: TRecorder;
  mHook: TAtlasWndProcHook;
begin
  mControl := TControl.Create(nil);
  mBottom := TRecorder.Create;
  mOwner := TRecorder.Create;
  try
    mBottom.Old := mControl.WindowProc;
    mControl.WindowProc := mBottom.Handle;
    mHook := TAtlasWndProcHook.Create(mControl, mOwner.Handle);
    mOwner.Hook := mHook;
    Assert.IsTrue(mHook.Active);
    Send(mControl);
    Assert.AreEqual(1, mOwner.Count, 'Besitzer');
    Assert.AreEqual(1, mBottom.Count, 'Vorgänger über CallOld');
    Assert.IsTrue(TAtlasWndProcHook.Unhook(mHook));
  finally
    mOwner.Free;
    mBottom.Free;
    mControl.Free;
  end;
end;

procedure TAtlasWndProcHookTests.UnhookOnTopRestoresPrevious;
var
  mControl: TControl;
  mOwner: TRecorder;
  mHook: TAtlasWndProcHook;
  mOriginal: TWndMethod;
begin
  mControl := TControl.Create(nil);
  mOwner := TRecorder.Create;
  try
    mOriginal := mControl.WindowProc;
    mHook := TAtlasWndProcHook.Create(mControl, mOwner.Handle);
    mOwner.Hook := mHook;
    Assert.IsFalse(Same(mOriginal, mControl.WindowProc), 'eingehängt');
    Assert.IsTrue(TAtlasWndProcHook.Unhook(mHook));
    Assert.IsNull(mHook);
    Assert.IsTrue(Same(mOriginal, mControl.WindowProc), 'Vorgänger wieder oben');
  finally
    mOwner.Free;
    mControl.Free;
  end;
end;

procedure TAtlasWndProcHookTests.ForeignProcOnTopStaysInChain;
var
  mControl: TControl;
  mOwner, mForeign: TRecorder;
  mHook: TAtlasWndProcHook;
begin
  mControl := TControl.Create(nil);
  mOwner := TRecorder.Create;
  mForeign := TRecorder.Create;
  mHook := nil;
  try
    mHook := TAtlasWndProcHook.Create(mControl, mOwner.Handle);
    mOwner.Hook := mHook;
    mForeign.Old := mControl.WindowProc;
    mControl.WindowProc := mForeign.Handle;
    Assert.IsFalse(mHook.Release, 'fremde Prozedur darüber');
    Assert.IsFalse(mHook.Active);
    Assert.IsTrue(Same(mForeign.Handle, mControl.WindowProc), 'fremde Prozedur bleibt oben');
    Send(mControl);
    Assert.AreEqual(1, mForeign.Count, 'fremde Prozedur');
    Assert.AreEqual(0, mOwner.Count, 'Besitzer nach dem Aushängen nicht mehr gerufen');
  finally
    mControl.Free;
    // Die Kette lebt nur so lange wie das Steuerelement; danach darf der Haken gehen.
    TAtlasWndProcHook.Forget(mHook);
    mForeign.Free;
    mOwner.Free;
  end;
end;

procedure TAtlasWndProcHookTests.UnhookOfNilIsClean;
var
  mHook: TAtlasWndProcHook;
begin
  mHook := nil;
  Assert.IsTrue(TAtlasWndProcHook.Unhook(mHook));
  Assert.IsNull(mHook);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWndProcHookTests);

end.
