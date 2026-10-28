unit Atlas.UI.Tracker.Capture;

// Bilder für „An Issue anhängen“ (#1276), reine VCL und Windows-API ohne Open
// Tools API:
// - TAtlasWindowCapture.WindowsOf: sichtbare Hauptfenster eines Prozesses (das
//   debuggte Programm), das Fenster ohne Besitzer zuerst. GetWindowText liest
//   bei fremden Prozessen den gespeicherten Titel, ohne eine Nachricht zu
//   senden.
// - Capture: Antwortet das Fenster (SendMessageTimeout mit WM_NULL), zeichnet
//   PrintWindow es samt verdeckter Teile; ein angehaltenes Programm (Halt im
//   Debugger) bekäme keine Nachricht und würde die IDE blockieren, dort nimmt
//   Atlas den Bildschirmbereich des Fensters (es sollte sichtbar sein).
// - TAtlasWindowPicker: „Fenster per Klick wählen“. Ein Maus-Hook (nur bis zum
//   nächsten Klick, höchstens TimeoutMs, Esc bricht ab) schluckt den Klick,
//   damit im Programm nichts ausgelöst wird, und meldet das Hauptfenster
//   unter dem Zeiger.
// - TAtlasAttachImages: Verkleinern auf issues.attach.maxImageWidth, PNG,
//   Bilder untereinander (GitHub: ein Bild in der Zwischenablage).
// Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.ExtCtrls;

type
  TAtlasWindowInfo = record
    Handle: HWND;
    Caption: string;
  end;

  TAtlasWindowCapture = record
  public const
    /// <summary>So lange darf ein Fenster für WM_NULL brauchen, sonst gilt es als angehalten.</summary>
    ResponseMs = 300;
  public
    /// <summary>Sichtbare Fenster ohne Eltern mit Titel von AProcessId; das ohne Besitzer zuerst.</summary>
    class function WindowsOf(AProcessId: DWORD): TArray<TAtlasWindowInfo>; static;
    /// <summary>Antwortet AWindow auf Nachrichten (nicht angehalten, nicht hängend)?</summary>
    class function Responds(AWindow: HWND): Boolean; static;
    /// <summary>Bild von AWindow; nil, wenn es nicht geht (ungültig, minimiert, leer).</summary>
    class function Capture(AWindow: HWND): TBitmap; static;
    /// <summary>Hauptfenster unter APoint.</summary>
    class function RootAt(const APoint: TPoint): HWND; static;
    /// <summary>Prozess eines Fensters.</summary>
    class function ProcessOf(AWindow: HWND): DWORD; static;
  end;

  TAtlasWindowPicked = reference to procedure(AWindow: HWND);

  /// <summary>Ein Klick auf ein beliebiges Fenster wählt es (Hook bis zum Klick).</summary>
  TAtlasWindowPicker = class
  public const
    TimeoutMs = 15000;
  private
    FTimer: TTimer;
    FOnPicked: TAtlasWindowPicked;
    FStarted: UInt64;
    procedure Tick(Sender: TObject);
    procedure Finish(AWindow: HWND);
  public
    destructor Destroy; override;
    /// <summary>Auf den nächsten Klick warten; AOnPicked bekommt das Fenster bzw. 0 (Esc, Zeitgrenze).</summary>
    procedure Start(const AOnPicked: TAtlasWindowPicked);
    procedure Cancel;
    function Active: Boolean;
  end;

  TAtlasAttachImages = record
  public
    /// <summary>Kopie von ABitmap, höchstens AMaxWidth breit (TAtlasAttachImage.ScaledSize), weich verkleinert.
    /// </summary>
    class function Scaled(ABitmap: TBitmap; AMaxWidth: Integer): TBitmap; static;
    /// <summary>ABitmap als PNG.</summary>
    class function PngBytes(ABitmap: TBitmap): TBytes; static;
    /// <summary>PNG-Bytes als Bitmap; nil bei ungültigen Daten.</summary>
    class function FromPng(const ABytes: TBytes): TBitmap; static;
    /// <summary>Bilder untereinander mit AGap Pixeln Abstand auf Weiß; nil ohne Bilder.</summary>
    class function Stacked(const ABitmaps: TArray<TBitmap>; AGap: Integer): TBitmap; static;
  end;

implementation

uses
  Winapi.Messages,
  Winapi.Dwmapi,
  Vcl.Imaging.pngimage,
  Atlas.Core.Tracker.Attach;

const
  // Fehlt in älteren Winapi.Windows: auch Inhalte von DirectX und WinUI zeichnen (ab Windows 8.1).
  PW_RENDERFULLCONTENT = 2;

type
  TCollect = record
    ProcessId: DWORD;
    Items: TArray<TAtlasWindowInfo>;
  end;
  PCollect = ^TCollect;

function CollectWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  mCollect: PCollect;
  mProcess: DWORD;
  mBuffer: array[0..255] of Char;
  mInfo: TAtlasWindowInfo;
begin
  Result := True;
  mCollect := PCollect(AParam);
  mProcess := 0;
  GetWindowThreadProcessId(AWindow, @mProcess);
  if (mProcess <> mCollect.ProcessId) or not IsWindowVisible(AWindow) then
    Exit;
  if GetWindowText(AWindow, mBuffer, Length(mBuffer)) = 0 then
    Exit;
  mInfo.Handle := AWindow;
  mInfo.Caption := mBuffer;
  // Das Hauptfenster (ohne Besitzer) zuerst, Dialoge danach.
  if GetWindow(AWindow, GW_OWNER) = 0 then
    mCollect.Items := [mInfo] + mCollect.Items
  else
    mCollect.Items := mCollect.Items + [mInfo];
end;

{ TAtlasWindowCapture }

class function TAtlasWindowCapture.WindowsOf(AProcessId: DWORD): TArray<TAtlasWindowInfo>;
var
  mCollect: TCollect;
begin
  Result := nil;
  if AProcessId = 0 then
    Exit;
  mCollect.ProcessId := AProcessId;
  mCollect.Items := nil;
  EnumWindows(@CollectWindow, LPARAM(@mCollect));
  Result := mCollect.Items;
end;

class function TAtlasWindowCapture.Responds(AWindow: HWND): Boolean;
var
  mResult: DWORD_PTR;
begin
  Result := IsWindow(AWindow) and (SendMessageTimeout(AWindow, WM_NULL, 0, 0, SMTO_ABORTIFHUNG or SMTO_BLOCK,
    ResponseMs, @mResult) <> 0);
end;

class function TAtlasWindowCapture.ProcessOf(AWindow: HWND): DWORD;
begin
  Result := 0;
  GetWindowThreadProcessId(AWindow, @Result);
end;

class function TAtlasWindowCapture.RootAt(const APoint: TPoint): HWND;
begin
  Result := WindowFromPoint(APoint);
  if Result <> 0 then
    Result := GetAncestor(Result, GA_ROOT);
end;

/// <summary>Sichtbarer Rahmen ohne den unsichtbaren Rand von Windows 10/11.</summary>
function FrameOf(AWindow: HWND): TRect;
begin
  if Failed(DwmGetWindowAttribute(AWindow, DWMWA_EXTENDED_FRAME_BOUNDS, @Result, SizeOf(Result))) then
    GetWindowRect(AWindow, Result);
end;

class function TAtlasWindowCapture.Capture(AWindow: HWND): TBitmap;
var
  mRect, mWindow: TRect;
  mScreen: HDC;
  mPrinted: Boolean;
  mFull: TBitmap;
begin
  Result := nil;
  if not IsWindow(AWindow) or IsIconic(AWindow) then
    Exit;
  mRect := FrameOf(AWindow);
  if (mRect.Width <= 0) or (mRect.Height <= 0) then
    Exit;
  mPrinted := False;
  if Responds(AWindow) then
  begin
    // Ganzes Fenster samt verdeckter Teile; danach auf den sichtbaren Rahmen zuschneiden.
    GetWindowRect(AWindow, mWindow);
    mFull := TBitmap.Create;
    try
      mFull.PixelFormat := pf32bit;
      mFull.SetSize(mWindow.Width, mWindow.Height);
      mPrinted := PrintWindow(AWindow, mFull.Canvas.Handle, PW_RENDERFULLCONTENT);
      if mPrinted then
      begin
        Result := TBitmap.Create;
        Result.PixelFormat := pf24bit;
        Result.SetSize(mRect.Width, mRect.Height);
        BitBlt(Result.Canvas.Handle, 0, 0, mRect.Width, mRect.Height, mFull.Canvas.Handle, mRect.Left - mWindow.Left,
          mRect.Top - mWindow.Top, SRCCOPY);
      end;
    finally
      mFull.Free;
    end;
  end;
  if mPrinted then
    Exit;
  // Angehalten oder PrintWindow abgelehnt: Bildschirmbereich, ohne dem Fenster eine Nachricht zu schicken.
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(mRect.Width, mRect.Height);
  mScreen := GetDC(0);
  try
    BitBlt(Result.Canvas.Handle, 0, 0, mRect.Width, mRect.Height, mScreen, mRect.Left, mRect.Top,
      SRCCOPY or CAPTUREBLT);
  finally
    ReleaseDC(0, mScreen);
  end;
end;

{ TAtlasWindowPicker }

var
  // Der Hook ist eine einfache Funktion: Zustand des laufenden Wählens.
  PickHook: HHOOK;
  PickWindow: HWND;
  PickDone: Boolean;

function PickMouse(ACode: Integer; AParam: WPARAM; AData: LPARAM): LRESULT; stdcall;
begin
  if (ACode = HC_ACTION) and not PickDone then
    case AParam of
      WM_LBUTTONDOWN, WM_RBUTTONDOWN:
        // Den Klick schlucken: Im Programm soll nichts ausgelöst werden.
        Exit(1);
      WM_LBUTTONUP:
        begin
          PickWindow := TAtlasWindowCapture.RootAt(PMSLLHookStruct(AData).pt);
          PickDone := True;
          Exit(1);
        end;
      WM_RBUTTONUP:
        begin
          // Rechtsklick bricht ab.
          PickWindow := 0;
          PickDone := True;
          Exit(1);
        end;
    end;
  Result := CallNextHookEx(PickHook, ACode, AParam, AData);
end;

procedure Unhook;
begin
  if PickHook <> 0 then
    UnhookWindowsHookEx(PickHook);
  PickHook := 0;
end;

destructor TAtlasWindowPicker.Destroy;
begin
  Cancel;
  FTimer.Free;
  inherited;
end;

function TAtlasWindowPicker.Active: Boolean;
begin
  Result := (FTimer <> nil) and FTimer.Enabled;
end;

procedure TAtlasWindowPicker.Start(const AOnPicked: TAtlasWindowPicked);
begin
  Cancel;
  FOnPicked := AOnPicked;
  PickWindow := 0;
  PickDone := False;
  PickHook := SetWindowsHookEx(WH_MOUSE_LL, @PickMouse, HInstance, 0);
  if PickHook = 0 then
  begin
    Finish(0);
    Exit;
  end;
  FStarted := GetTickCount64;
  // Der Takt bleibt bis zum Freigeben bestehen: Finish läuft in seinem OnTimer.
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Interval := 50;
    FTimer.OnTimer := Tick;
  end;
  FTimer.Enabled := True;
end;

procedure TAtlasWindowPicker.Tick(Sender: TObject);
begin
  if PickDone then
    Finish(PickWindow)
  else if (GetAsyncKeyState(VK_ESCAPE) < 0) or (GetTickCount64 - FStarted > TimeoutMs) then
    Finish(0);
end;

procedure TAtlasWindowPicker.Finish(AWindow: HWND);
var
  mOnPicked: TAtlasWindowPicked;
begin
  Unhook;
  if FTimer <> nil then
    FTimer.Enabled := False;
  mOnPicked := FOnPicked;
  FOnPicked := nil;
  if Assigned(mOnPicked) then
    mOnPicked(AWindow);
end;

procedure TAtlasWindowPicker.Cancel;
begin
  Unhook;
  if FTimer <> nil then
    FTimer.Enabled := False;
  FOnPicked := nil;
end;

{ TAtlasAttachImages }

class function TAtlasAttachImages.Scaled(ABitmap: TBitmap; AMaxWidth: Integer): TBitmap;
var
  mWidth, mHeight: Integer;
begin
  Result := TBitmap.Create;
  try
    if not TAtlasAttachImage.ScaledSize(ABitmap.Width, ABitmap.Height, AMaxWidth, mWidth, mHeight) then
    begin
      Result.Assign(ABitmap);
      Exit;
    end;
    Result.PixelFormat := pf24bit;
    Result.SetSize(mWidth, mHeight);
    // HALFTONE mittelt die Pixel: Schrift bleibt lesbar.
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    StretchBlt(Result.Canvas.Handle, 0, 0, mWidth, mHeight, ABitmap.Canvas.Handle, 0, 0, ABitmap.Width,
      ABitmap.Height, SRCCOPY);
  except
    Result.Free;
    raise;
  end;
end;

class function TAtlasAttachImages.PngBytes(ABitmap: TBitmap): TBytes;
var
  mPng: TPngImage;
  mStream: TBytesStream;
begin
  mPng := TPngImage.Create;
  mStream := TBytesStream.Create;
  try
    mPng.Assign(ABitmap);
    mPng.SaveToStream(mStream);
    Result := Copy(mStream.Bytes, 0, mStream.Size);
  finally
    mStream.Free;
    mPng.Free;
  end;
end;

class function TAtlasAttachImages.FromPng(const ABytes: TBytes): TBitmap;
var
  mPng: TPngImage;
  mStream: TBytesStream;
begin
  Result := nil;
  if Length(ABytes) = 0 then
    Exit;
  mPng := TPngImage.Create;
  mStream := TBytesStream.Create(ABytes);
  try
    try
      mPng.LoadFromStream(mStream);
    except
      on EInvalidGraphic do
        Exit;
      on EPNGError do
        Exit;
    end;
    Result := TBitmap.Create;
    Result.Assign(mPng);
  finally
    mStream.Free;
    mPng.Free;
  end;
end;

class function TAtlasAttachImages.Stacked(const ABitmaps: TArray<TBitmap>; AGap: Integer): TBitmap;
var
  mBitmap: TBitmap;
  mWidth, mHeight, mTop: Integer;
begin
  Result := nil;
  if Length(ABitmaps) = 0 then
    Exit;
  mWidth := 0;
  mHeight := 0;
  for mBitmap in ABitmaps do
  begin
    if mBitmap.Width > mWidth then
      mWidth := mBitmap.Width;
    Inc(mHeight, mBitmap.Height + AGap);
  end;
  Dec(mHeight, AGap);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(mWidth, mHeight);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(Rect(0, 0, mWidth, mHeight));
  mTop := 0;
  for mBitmap in ABitmaps do
  begin
    Result.Canvas.Draw(0, mTop, mBitmap);
    Inc(mTop, mBitmap.Height + AGap);
  end;
end;

initialization

finalization
  Unhook;

end.
