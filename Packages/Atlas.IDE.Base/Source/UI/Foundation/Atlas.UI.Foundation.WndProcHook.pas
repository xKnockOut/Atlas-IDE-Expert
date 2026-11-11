unit Atlas.UI.Foundation.WndProcHook;

// Eingehängte Fensterprozedur (WindowProc) eines Steuerelements mit
// Kettenprüfung beim Aushängen (#1976).
// - Create merkt die bisherige WindowProc und setzt WndProc des Hakens davor.
//   Der Handler des Besitzers ruft CallOld, um die Nachricht weiterzugeben.
// - Release setzt die gemerkte Prozedur nur zurück, wenn die aktuelle noch
//   die des Hakens ist. Hat sich danach eine andere Erweiterung eingehängt,
//   bliebe sie sonst ausgeschnitten und stellte später einen Zeiger auf einen
//   freigegebenen Haken wieder her (Zugriffsverletzung beim Schließen). Dann
//   bleibt der Haken als reiner Durchreicher in ihrer Kette.
// - Unhook gibt den Haken frei oder legt einen Durchreicher bis zum Entladen
//   des Packages beiseite. OrphanCount zählt diese Fälle: Nach dem Entladen
//   zeigte die fremde Kette auf entladenen Code.
// Nur im Hauptthread.

interface

uses
  Winapi.Messages,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls;

type
  TAtlasWndProcHook = class
  private
    FControl: TControl;
    FHandler: TWndMethod;
    FOld: TWndMethod;
    FActive: Boolean;
    class var FOrphans: TObjectList<TAtlasWndProcHook>;
  public
    /// <summary>AHandler vor die aktuelle WindowProc von AControl setzen.</summary>
    constructor Create(AControl: TControl; const AHandler: TWndMethod);
    class destructor Destroy;
    /// <summary>In der Kette von AControl: Handler des Besitzers, nach Release nur noch die gemerkte Prozedur.
    /// </summary>
    procedure WndProc(var AMessage: TMessage);
    /// <summary>Nachricht an die beim Einhängen gemerkte Prozedur weitergeben.</summary>
    procedure CallOld(var AMessage: TMessage);
    /// <summary>Aushängen; True, wenn die gemerkte Prozedur wieder gilt und der Haken frei ist. False: Eine fremde
    /// WindowProc liegt darüber, der Haken reicht ab jetzt nur durch und darf nicht freigegeben werden, solange das
    /// Steuerelement lebt.</summary>
    function Release: Boolean;
    /// <summary>AHook aushängen und freigeben oder als Durchreicher bis zum Entladen behalten; AHook ist danach nil.
    /// True, wenn sauber ausgehängt; nichts bei nil.</summary>
    class function Unhook(var AHook: TAtlasWndProcHook): Boolean; static;
    /// <summary>Wie Unhook, ohne das Steuerelement anzufassen: Es ist schon freigegeben.</summary>
    class procedure Forget(var AHook: TAtlasWndProcHook); static;
    /// <summary>Haken, die in einer fremden Kette verblieben sind (Entladen ohne Neustart nicht sicher).</summary>
    class function OrphanCount: Integer; static;
    /// <summary>Handler des Besitzers wird noch gerufen.</summary>
    property Active: Boolean read FActive;
    property Control: TControl read FControl;
  end;

implementation

uses
  System.SysUtils;

function SameMethod(const ALeft, ARight: TMethod): Boolean;
begin
  Result := (ALeft.Code = ARight.Code) and (ALeft.Data = ARight.Data);
end;

{ TAtlasWndProcHook }

constructor TAtlasWndProcHook.Create(AControl: TControl; const AHandler: TWndMethod);
begin
  inherited Create;
  FControl := AControl;
  FHandler := AHandler;
  FOld := AControl.WindowProc;
  FActive := True;
  AControl.WindowProc := WndProc;
end;

class destructor TAtlasWndProcHook.Destroy;
begin
  FreeAndNil(FOrphans);
end;

procedure TAtlasWndProcHook.WndProc(var AMessage: TMessage);
begin
  if FActive and Assigned(FHandler) then
  begin
    FHandler(AMessage);
  end
  else
  begin
    CallOld(AMessage);
  end;
end;

procedure TAtlasWndProcHook.CallOld(var AMessage: TMessage);
begin
  if Assigned(FOld) then
  begin
    FOld(AMessage);
  end;
end;

function TAtlasWndProcHook.Release: Boolean;
var
  mOwn, mCurrent: TWndMethod;
begin
  FActive := False;
  FHandler := nil;
  mOwn := WndProc;
  mCurrent := FControl.WindowProc;
  Result := SameMethod(TMethod(mCurrent), TMethod(mOwn));
  if Result then
  begin
    FControl.WindowProc := FOld;
  end;
end;

class function TAtlasWndProcHook.Unhook(var AHook: TAtlasWndProcHook): Boolean;
var
  mHook: TAtlasWndProcHook;
begin
  Result := True;
  mHook := AHook;
  AHook := nil;
  if mHook = nil then
  begin
    Exit;
  end;
  Result := mHook.Release;
  if Result then
  begin
    mHook.Free;
    Exit;
  end;
  // Noch in fremder Kette: Das Steuerelement ruft WndProc weiter auf.
  if FOrphans = nil then
  begin
    FOrphans := TObjectList<TAtlasWndProcHook>.Create(True);
  end;
  FOrphans.Add(mHook);
end;

class procedure TAtlasWndProcHook.Forget(var AHook: TAtlasWndProcHook);
begin
  FreeAndNil(AHook);
end;

class function TAtlasWndProcHook.OrphanCount: Integer;
begin
  Result := 0;
  if FOrphans <> nil then
  begin
    Result := FOrphans.Count;
  end;
end;

end.
