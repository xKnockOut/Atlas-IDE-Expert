unit Atlas.UI.Popup.Accessibility;

// Barrierefreiheit der Atlas-Fenster (#447): UI-Automation-Provider für Popup,
// Parameter-Hint und Tooltip. Die Fenster bekommen nie den Fokus; deshalb sagt
// die Sprachausgabe sie nicht von selbst an. Atlas löst stattdessen
// Benachrichtigungen aus (UiaRaiseNotificationEvent, ab Windows 10 1709), die
// Narrator und andere Screenreader vorlesen.
// Schnittstelle und Funktionen sind selbst deklariert und werden zur Laufzeit
// geladen: So übersetzt die Unit auch mit Delphi 12 und läuft auf Systemen
// ohne die neueren Einsprungpunkte (dann ohne Ansage).

interface

uses
  Winapi.Windows;

const
  UiaListControlType = 50008;
  UiaToolTipControlType = 50022;

type
  /// <summary>IRawElementProviderSimple aus UIAutomationCore.h.</summary>
  IAtlasRawElementProvider = interface(IUnknown)
    ['{D6DD68D1-86FD-4332-8666-9ABEDEA2D24C}']
    function get_ProviderOptions(out ARetVal: Integer): HResult; stdcall;
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; stdcall;
    function GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult; stdcall;
    function get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
  end;

  /// <summary>Element eines Atlas-Fensters: Rolle, Name, Ansagen.</summary>
  TAtlasAccessibleElement = class(TInterfacedObject, IAtlasRawElementProvider)
  private
    FWindow: HWND;
    FControlType: Integer;
    FName: string;
  public
    constructor Create(AWindow: HWND; AControlType: Integer; const AName: string);
    function get_ProviderOptions(out ARetVal: Integer): HResult; stdcall;
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; stdcall;
    function GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult; stdcall;
    function get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
    property Name: string read FName write FName;
  end;

  TAtlasAccessibility = class
  public
    /// <summary>Antwort auf WM_GETOBJECT; 0, wenn nicht für UI Automation oder nicht verfügbar.</summary>
    class function Answer(AWindow: HWND; AWParam: WPARAM; ALParam: LPARAM;
      const AElement: IAtlasRawElementProvider): LRESULT; static;
    /// <summary>Fenster wird zerstört: Verweise von UI Automation lösen.</summary>
    class procedure Release(AWindow: HWND); static;
    /// <summary>Hört gerade ein Screenreader zu?</summary>
    class function Listening: Boolean; static;
    /// <summary>Text ansagen lassen; ersetzt eine noch laufende Ansage desselben Elements.</summary>
    class procedure Announce(const AElement: IAtlasRawElementProvider; const AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Variants;

const
  UiaRootObjectId = -25;
  ProviderOptionsServerSide = $2;
  ProviderOptionsUseComThreading = $20;
  UiaControlTypeProperty = 30003;
  UiaNameProperty = 30005;
  UiaIsKeyboardFocusableProperty = 30009;
  UiaHasKeyboardFocusProperty = 30008;
  UiaFrameworkIdProperty = 30024;
  NotificationKindOther = 4;
  NotificationProcessingImportantMostRecent = 1;

type
  TUiaReturnRawElementProvider = function(AWindow: HWND; AWParam: WPARAM; ALParam: LPARAM;
    AElement: IAtlasRawElementProvider): LRESULT; stdcall;
  TUiaHostProviderFromHwnd = function(AWindow: HWND; out AProvider: IAtlasRawElementProvider): HResult; stdcall;
  TUiaRaiseNotificationEvent = function(AProvider: IAtlasRawElementProvider; AKind, AProcessing: Integer;
    ADisplay, AActivity: PWideChar): HResult; stdcall;
  TUiaClientsAreListening = function: BOOL; stdcall;

var
  Loaded: Boolean;
  ReturnRawElementProvider: TUiaReturnRawElementProvider;
  HostProviderFromHwnd: TUiaHostProviderFromHwnd;
  RaiseNotificationEvent: TUiaRaiseNotificationEvent;
  ClientsAreListening: TUiaClientsAreListening;

procedure Load;
var
  Module: HMODULE;
begin
  if Loaded then
    Exit;
  Loaded := True;
  Module := LoadLibrary('UIAutomationCore.dll');
  if Module = 0 then
    Exit;
  @ReturnRawElementProvider := GetProcAddress(Module, 'UiaReturnRawElementProvider');
  @HostProviderFromHwnd := GetProcAddress(Module, 'UiaHostProviderFromHwnd');
  @RaiseNotificationEvent := GetProcAddress(Module, 'UiaRaiseNotificationEvent');
  @ClientsAreListening := GetProcAddress(Module, 'UiaClientsAreListening');
end;

{ TAtlasAccessibleElement }

constructor TAtlasAccessibleElement.Create(AWindow: HWND; AControlType: Integer; const AName: string);
begin
  inherited Create;
  FWindow := AWindow;
  FControlType := AControlType;
  FName := AName;
end;

function TAtlasAccessibleElement.get_ProviderOptions(out ARetVal: Integer): HResult;
begin
  ARetVal := ProviderOptionsServerSide or ProviderOptionsUseComThreading;
  Result := S_OK;
end;

function TAtlasAccessibleElement.GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult;
begin
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleElement.GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult;
begin
  case APropertyId of
    UiaControlTypeProperty:
      ARetVal := FControlType;
    UiaNameProperty:
      ARetVal := FName;
    UiaIsKeyboardFocusableProperty, UiaHasKeyboardFocusProperty:
      ARetVal := False;
    UiaFrameworkIdProperty:
      ARetVal := 'Atlas';
  else
    ARetVal := Unassigned;
  end;
  Result := S_OK;
end;

function TAtlasAccessibleElement.get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult;
begin
  ARetVal := nil;
  Load;
  if Assigned(HostProviderFromHwnd) then
    Result := HostProviderFromHwnd(FWindow, ARetVal)
  else
    Result := S_OK;
end;

{ TAtlasAccessibility }

class function TAtlasAccessibility.Answer(AWindow: HWND; AWParam: WPARAM; ALParam: LPARAM;
  const AElement: IAtlasRawElementProvider): LRESULT;
begin
  Result := 0;
  if (Integer(ALParam) <> UiaRootObjectId) or (AElement = nil) then
    Exit;
  Load;
  if Assigned(ReturnRawElementProvider) then
    Result := ReturnRawElementProvider(AWindow, AWParam, ALParam, AElement);
end;

class procedure TAtlasAccessibility.Release(AWindow: HWND);
begin
  Load;
  if Assigned(ReturnRawElementProvider) then
    ReturnRawElementProvider(AWindow, 0, 0, nil);
end;

class function TAtlasAccessibility.Listening: Boolean;
begin
  Load;
  Result := Assigned(ClientsAreListening) and Assigned(RaiseNotificationEvent) and ClientsAreListening;
end;

class procedure TAtlasAccessibility.Announce(const AElement: IAtlasRawElementProvider; const AText: string);
begin
  if (AElement = nil) or (AText = '') or not Listening then
    Exit;
  RaiseNotificationEvent(AElement, NotificationKindOther, NotificationProcessingImportantMostRecent,
    PWideChar(AText), 'Atlas');
end;

end.
