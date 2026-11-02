unit Atlas.UI.Popup.Accessibility;

// Barrierefreiheit der Atlas-Fenster (#447): UI-Automation-Provider für Popup,
// Parameter-Hint und Tooltip. Die Fenster bekommen nie den Fokus; deshalb sagt
// die Sprachausgabe sie nicht von selbst an. Atlas löst stattdessen
// Benachrichtigungen aus (UiaRaiseNotificationEvent, ab Windows 10 1709), die
// Narrator und andere Screenreader vorlesen.
// Listen (Vervollständigung) sind ein Fragment-Baum: Die Liste ist die Wurzel
// mit Auswahlmuster, jeder Eintrag ein Kind mit Rolle „Listeneintrag“, Position,
// Zustand („deprecated, Helper“) und Kurzbeschreibung; Überschriften sind Text.
// Beim Auswahlwechsel kommt ElementSelected für den neuen Eintrag. Die Einträge
// liefert das Fenster über IAtlasAccessibleItems; schließt es, löst Detach die
// Verbindung, und Elemente, die UI Automation noch hält, melden „nicht verfügbar“.
// Schnittstelle und Funktionen sind selbst deklariert und werden zur Laufzeit
// geladen: So übersetzt die Unit auch mit Delphi 12 und läuft auf Systemen
// ohne die neueren Einsprungpunkte (dann ohne Ansage).

interface

uses
  Winapi.Windows,
  System.Types;

const
  UiaListControlType = 50008;
  UiaListItemControlType = 50007;
  UiaTextControlType = 50020;
  UiaToolTipControlType = 50022;
  /// <summary>Richtungen für Navigate (NavigateDirection).</summary>
  UiaNavigateParent = 0;
  UiaNavigateNextSibling = 1;
  UiaNavigatePreviousSibling = 2;
  UiaNavigateFirstChild = 3;
  UiaNavigateLastChild = 4;

type
  /// <summary>UiaRect aus UIAutomationCore.h (Bildschirmkoordinaten).</summary>
  TAtlasUiaRect = record
    Left: Double;
    Top: Double;
    Width: Double;
    Height: Double;
  end;

  /// <summary>IRawElementProviderSimple aus UIAutomationCore.h.</summary>
  IAtlasRawElementProvider = interface(IUnknown)
    ['{D6DD68D1-86FD-4332-8666-9ABEDEA2D24C}']
    function get_ProviderOptions(out ARetVal: Integer): HResult; stdcall;
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; stdcall;
    function GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult; stdcall;
    function get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
  end;

  IAtlasRawElementFragmentRoot = interface;

  /// <summary>IRawElementProviderFragment: Element in einem Baum unterhalb des Fensters.</summary>
  IAtlasRawElementFragment = interface(IUnknown)
    ['{F7063DA8-8359-439C-9297-BBC5299A7D87}']
    function Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    /// <summary>ARetVal ist ein SAFEARRAY von VT_I4.</summary>
    function GetRuntimeId(out ARetVal: Pointer): HResult; stdcall;
    function get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult; stdcall;
    function GetEmbeddedFragmentRoots(out ARetVal: Pointer): HResult; stdcall;
    function SetFocus: HResult; stdcall;
    function get_FragmentRoot(out ARetVal: IAtlasRawElementFragmentRoot): HResult; stdcall;
  end;

  /// <summary>IRawElementProviderFragmentRoot: Wurzel des Baums (das Fenster).</summary>
  IAtlasRawElementFragmentRoot = interface(IUnknown)
    ['{620CE2A5-AB8F-40A9-86CB-DE3C75599B58}']
    function ElementProviderFromPoint(AX, AY: Double; out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    function GetFocus(out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
  end;

  /// <summary>ISelectionProvider (Muster „Auswahl“ der Liste).</summary>
  IAtlasSelectionProvider = interface(IUnknown)
    ['{FB8B03AF-3BDF-48D4-BD36-1A65793BE168}']
    /// <summary>ARetVal ist ein SAFEARRAY von IRawElementProviderSimple.</summary>
    function GetSelection(out ARetVal: Pointer): HResult; stdcall;
    function get_CanSelectMultiple(out ARetVal: BOOL): HResult; stdcall;
    function get_IsSelectionRequired(out ARetVal: BOOL): HResult; stdcall;
  end;

  /// <summary>ISelectionItemProvider (Muster „Auswahlelement“ eines Eintrags).</summary>
  IAtlasSelectionItemProvider = interface(IUnknown)
    ['{2ACAD808-B2D4-452D-A407-91FF1AD167B2}']
    function Select: HResult; stdcall;
    function AddToSelection: HResult; stdcall;
    function RemoveFromSelection: HResult; stdcall;
    function get_IsSelected(out ARetVal: BOOL): HResult; stdcall;
    function get_SelectionContainer(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
  end;

  /// <summary>Einträge einer Liste für UI Automation (#447); Positionen in der Anzeigereihenfolge.</summary>
  IAtlasAccessibleItems = interface
    ['{5C0F3E52-8A47-4D3B-9E61-2B7A4C1D9F08}']
    function AccessibleCount: Integer;
    /// <summary>Gewählte Position; -1 ohne.</summary>
    function AccessibleSelected: Integer;
    /// <summary>Schlüssel des Eintrags an APosition, der beim Filtern gleich bleibt.</summary>
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    /// <summary>Zustand in Worten („deprecated, Helper“); '' ohne.</summary>
    function AccessibleStatus(APosition: Integer): string;
    /// <summary>Kurzbeschreibung (Signatur, Herkunft); '' ohne.</summary>
    function AccessibleHelp(APosition: Integer): string;
    /// <summary>Überschrift einer Gruppe statt eines Eintrags; nicht wählbar.</summary>
    function AccessibleIsHeader(APosition: Integer): Boolean;
    /// <summary>Zeile in Bildschirmkoordinaten; False, wenn sie nicht sichtbar ist.</summary>
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
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
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; virtual; stdcall;
    function GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult; virtual; stdcall;
    function get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
    /// <summary>Fenster schließt: keine Rückfragen mehr an das Fenster.</summary>
    procedure Detach; virtual;
    property Name: string read FName write FName;
  end;

  /// <summary>Liste als Wurzel eines Fragment-Baums mit Einträgen als Kindern.</summary>
  TAtlasAccessibleList = class(TAtlasAccessibleElement, IAtlasRawElementFragment, IAtlasRawElementFragmentRoot,
    IAtlasSelectionProvider)
  private
    FSource: IAtlasAccessibleItems;
  public
    constructor Create(AWindow: HWND; const AName: string; const ASource: IAtlasAccessibleItems);
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; override; stdcall;
    { IAtlasRawElementFragment }
    function Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    function GetRuntimeId(out ARetVal: Pointer): HResult; stdcall;
    function get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult; stdcall;
    function GetEmbeddedFragmentRoots(out ARetVal: Pointer): HResult; stdcall;
    function SetFocus: HResult; stdcall;
    function get_FragmentRoot(out ARetVal: IAtlasRawElementFragmentRoot): HResult; stdcall;
    { IAtlasRawElementFragmentRoot }
    function ElementProviderFromPoint(AX, AY: Double; out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    function GetFocus(out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    { IAtlasSelectionProvider }
    function GetSelection(out ARetVal: Pointer): HResult; stdcall;
    function get_CanSelectMultiple(out ARetVal: BOOL): HResult; stdcall;
    function get_IsSelectionRequired(out ARetVal: BOOL): HResult; stdcall;
    procedure Detach; override;
    /// <summary>Element des Eintrags an APosition; nil außerhalb der Liste.</summary>
    function Item(APosition: Integer): IAtlasRawElementProvider;
    /// <summary>Auswahl hat gewechselt: ElementSelected für den gewählten Eintrag.</summary>
    procedure SelectionChanged;
    /// <summary>Einträge sind neu (gefiltert, neue Liste): Kinder neu einlesen lassen.</summary>
    procedure ItemsChanged;
    property Source: IAtlasAccessibleItems read FSource;
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
    /// <summary>Ziel von Navigate unter Geschwistern: Position oder -1 (keins). AFrom -1 = von der Liste aus.</summary>
    class function NavigateTarget(ADirection, AFrom, ACount: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Variants;

const
  UiaRootObjectId = -25;
  UiaAppendRuntimeId = 3;
  ProviderOptionsServerSide = $2;
  ProviderOptionsUseComThreading = $20;
  UiaSelectionPatternId = 10001;
  UiaSelectionItemPatternId = 10010;
  UiaControlTypeProperty = 30003;
  UiaNameProperty = 30005;
  UiaHasKeyboardFocusProperty = 30008;
  UiaIsKeyboardFocusableProperty = 30009;
  UiaIsEnabledProperty = 30010;
  UiaHelpTextProperty = 30013;
  UiaIsOffscreenProperty = 30022;
  UiaFrameworkIdProperty = 30024;
  UiaItemStatusProperty = 30026;
  UiaPositionInSetProperty = 30152;
  UiaSizeOfSetProperty = 30153;
  UiaElementSelectedEvent = 20012;
  StructureChangeChildrenInvalidated = 2;
  NotificationKindOther = 4;
  NotificationProcessingImportantMostRecent = 1;
  UiaElementNotAvailable = HResult($80040201);
  VarTypeInteger = 3;
  VarTypeUnknown = 13;

type
  TUiaReturnRawElementProvider = function(AWindow: HWND; AWParam: WPARAM; ALParam: LPARAM;
    AElement: IAtlasRawElementProvider): LRESULT; stdcall;
  TUiaHostProviderFromHwnd = function(AWindow: HWND; out AProvider: IAtlasRawElementProvider): HResult; stdcall;
  TUiaRaiseNotificationEvent = function(AProvider: IAtlasRawElementProvider; AKind, AProcessing: Integer;
    ADisplay, AActivity: PWideChar): HResult; stdcall;
  TUiaRaiseAutomationEvent = function(AProvider: IAtlasRawElementProvider; AEventId: Integer): HResult; stdcall;
  TUiaRaiseStructureChangedEvent = function(AProvider: IAtlasRawElementProvider; AChangeType: Integer;
    ARuntimeId: PInteger; ALength: Integer): HResult; stdcall;
  TUiaClientsAreListening = function: BOOL; stdcall;

  /// <summary>Eintrag einer TAtlasAccessibleList.</summary>
  TAtlasAccessibleItem = class(TInterfacedObject, IAtlasRawElementProvider, IAtlasRawElementFragment,
    IAtlasSelectionItemProvider)
  private
    FList: TAtlasAccessibleList;
    // Hält die Liste am Leben, solange UI Automation den Eintrag hält.
    FListRef: IAtlasRawElementProvider;
    FId: Integer;
    FPosition: Integer;
    /// <summary>Aktuelle Position des Eintrags; -1, wenn er nicht mehr in der Liste steht.</summary>
    function Position: Integer;
  public
    constructor Create(AList: TAtlasAccessibleList; APosition: Integer);
    { IAtlasRawElementProvider }
    function get_ProviderOptions(out ARetVal: Integer): HResult; stdcall;
    function GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult; stdcall;
    function GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult; stdcall;
    function get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
    { IAtlasRawElementFragment }
    function Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult; stdcall;
    function GetRuntimeId(out ARetVal: Pointer): HResult; stdcall;
    function get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult; stdcall;
    function GetEmbeddedFragmentRoots(out ARetVal: Pointer): HResult; stdcall;
    function SetFocus: HResult; stdcall;
    function get_FragmentRoot(out ARetVal: IAtlasRawElementFragmentRoot): HResult; stdcall;
    { IAtlasSelectionItemProvider }
    function Select: HResult; stdcall;
    function AddToSelection: HResult; stdcall;
    function RemoveFromSelection: HResult; stdcall;
    function get_IsSelected(out ARetVal: BOOL): HResult; stdcall;
    function get_SelectionContainer(out ARetVal: IAtlasRawElementProvider): HResult; stdcall;
  end;

function SafeArrayCreateVector(AVarType: Word; ALowerBound: Integer; ACount: Cardinal): Pointer; stdcall;
  external 'oleaut32.dll' name 'SafeArrayCreateVector';
function SafeArrayPutElement(AArray: Pointer; var AIndex: Integer; AValue: Pointer): HResult; stdcall;
  external 'oleaut32.dll' name 'SafeArrayPutElement';

var
  Loaded: Boolean;
  ReturnRawElementProvider: TUiaReturnRawElementProvider;
  HostProviderFromHwnd: TUiaHostProviderFromHwnd;
  RaiseNotificationEvent: TUiaRaiseNotificationEvent;
  RaiseAutomationEvent: TUiaRaiseAutomationEvent;
  RaiseStructureChangedEvent: TUiaRaiseStructureChangedEvent;
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
  @RaiseAutomationEvent := GetProcAddress(Module, 'UiaRaiseAutomationEvent');
  @RaiseStructureChangedEvent := GetProcAddress(Module, 'UiaRaiseStructureChangedEvent');
  @ClientsAreListening := GetProcAddress(Module, 'UiaClientsAreListening');
end;

function UiaRect(const ARect: TRect): TAtlasUiaRect;
begin
  Result.Left := ARect.Left;
  Result.Top := ARect.Top;
  Result.Width := ARect.Width;
  Result.Height := ARect.Height;
end;

function EmptyUiaRect: TAtlasUiaRect;
begin
  Result.Left := 0;
  Result.Top := 0;
  Result.Width := 0;
  Result.Height := 0;
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
  if (FWindow <> 0) and Assigned(HostProviderFromHwnd) then
    Result := HostProviderFromHwnd(FWindow, ARetVal)
  else
    Result := S_OK;
end;

procedure TAtlasAccessibleElement.Detach;
begin
  FWindow := 0;
end;

{ TAtlasAccessibleList }

constructor TAtlasAccessibleList.Create(AWindow: HWND; const AName: string; const ASource: IAtlasAccessibleItems);
begin
  inherited Create(AWindow, UiaListControlType, AName);
  FSource := ASource;
end;

function TAtlasAccessibleList.GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult;
begin
  if (APatternId = UiaSelectionPatternId) and (FSource <> nil) then
  begin
    ARetVal := IAtlasSelectionProvider(Self);
    Result := S_OK;
  end
  else
    Result := inherited GetPatternProvider(APatternId, ARetVal);
end;

function TAtlasAccessibleList.Item(APosition: Integer): IAtlasRawElementProvider;
begin
  Result := nil;
  if (FSource <> nil) and (APosition >= 0) and (APosition < FSource.AccessibleCount) then
    Result := TAtlasAccessibleItem.Create(Self, APosition);
end;

function TAtlasAccessibleList.Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult;
var
  Target: Integer;
begin
  ARetVal := nil;
  Result := S_OK;
  // Eltern und Geschwister der Liste liefert der Host (das Fenster).
  if (FSource = nil) or ((ADirection <> UiaNavigateFirstChild) and (ADirection <> UiaNavigateLastChild)) then
    Exit;
  Target := TAtlasAccessibility.NavigateTarget(ADirection, -1, FSource.AccessibleCount);
  if Target >= 0 then
    ARetVal := Item(Target) as IAtlasRawElementFragment;
end;

function TAtlasAccessibleList.GetRuntimeId(out ARetVal: Pointer): HResult;
begin
  // Wurzel eines Fensters: Die Kennung kommt vom Host.
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleList.get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult;
begin
  // Das Rechteck des Fensters liefert der Host.
  ARetVal := EmptyUiaRect;
  Result := S_OK;
end;

function TAtlasAccessibleList.GetEmbeddedFragmentRoots(out ARetVal: Pointer): HResult;
begin
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleList.SetFocus: HResult;
begin
  // Der Editor behält den Fokus.
  Result := S_OK;
end;

function TAtlasAccessibleList.get_FragmentRoot(out ARetVal: IAtlasRawElementFragmentRoot): HResult;
begin
  ARetVal := Self;
  Result := S_OK;
end;

function TAtlasAccessibleList.ElementProviderFromPoint(AX, AY: Double; out ARetVal: IAtlasRawElementFragment): HResult;
var
  Position: Integer;
  Bounds: TRect;
begin
  ARetVal := nil;
  Result := S_OK;
  if FSource = nil then
    Exit;
  for Position := 0 to FSource.AccessibleCount - 1 do
    if FSource.AccessibleBounds(Position, Bounds) and (AX >= Bounds.Left) and (AX < Bounds.Right) and
      (AY >= Bounds.Top) and (AY < Bounds.Bottom) then
    begin
      ARetVal := Item(Position) as IAtlasRawElementFragment;
      Exit;
    end;
end;

function TAtlasAccessibleList.GetFocus(out ARetVal: IAtlasRawElementFragment): HResult;
begin
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleList.GetSelection(out ARetVal: Pointer): HResult;
var
  Selected: IAtlasRawElementProvider;
  Index: Integer;
begin
  ARetVal := nil;
  Result := S_OK;
  if FSource = nil then
    Exit(UiaElementNotAvailable);
  Selected := Item(FSource.AccessibleSelected);
  if (Selected = nil) or FSource.AccessibleIsHeader(FSource.AccessibleSelected) then
  begin
    ARetVal := SafeArrayCreateVector(VarTypeUnknown, 0, 0);
    Exit;
  end;
  ARetVal := SafeArrayCreateVector(VarTypeUnknown, 0, 1);
  Index := 0;
  if ARetVal <> nil then
    Result := SafeArrayPutElement(ARetVal, Index, Pointer(Selected));
end;

function TAtlasAccessibleList.get_CanSelectMultiple(out ARetVal: BOOL): HResult;
begin
  ARetVal := False;
  Result := S_OK;
end;

function TAtlasAccessibleList.get_IsSelectionRequired(out ARetVal: BOOL): HResult;
begin
  ARetVal := False;
  Result := S_OK;
end;

procedure TAtlasAccessibleList.Detach;
begin
  FSource := nil;
  inherited Detach;
end;

procedure TAtlasAccessibleList.SelectionChanged;
var
  Selected: IAtlasRawElementProvider;
begin
  if (FSource = nil) or not TAtlasAccessibility.Listening or not Assigned(RaiseAutomationEvent) then
    Exit;
  if FSource.AccessibleIsHeader(FSource.AccessibleSelected) then
    Exit;
  Selected := Item(FSource.AccessibleSelected);
  if Selected <> nil then
    RaiseAutomationEvent(Selected, UiaElementSelectedEvent);
end;

procedure TAtlasAccessibleList.ItemsChanged;
begin
  if (FSource = nil) or not TAtlasAccessibility.Listening or not Assigned(RaiseStructureChangedEvent) then
    Exit;
  RaiseStructureChangedEvent(Self, StructureChangeChildrenInvalidated, nil, 0);
end;

{ TAtlasAccessibleItem }

constructor TAtlasAccessibleItem.Create(AList: TAtlasAccessibleList; APosition: Integer);
begin
  inherited Create;
  FList := AList;
  FListRef := AList;
  FPosition := APosition;
  FId := AList.Source.AccessibleId(APosition);
end;

function TAtlasAccessibleItem.Position: Integer;
var
  Source: IAtlasAccessibleItems;
  Index: Integer;
begin
  Result := -1;
  Source := FList.Source;
  if Source = nil then
    Exit;
  // Meist steht der Eintrag noch an derselben Stelle; nach dem Filtern wird er gesucht.
  if (FPosition < Source.AccessibleCount) and (Source.AccessibleId(FPosition) = FId) then
    Exit(FPosition);
  for Index := 0 to Source.AccessibleCount - 1 do
    if Source.AccessibleId(Index) = FId then
    begin
      FPosition := Index;
      Exit(Index);
    end;
end;

function TAtlasAccessibleItem.get_ProviderOptions(out ARetVal: Integer): HResult;
begin
  ARetVal := ProviderOptionsServerSide or ProviderOptionsUseComThreading;
  Result := S_OK;
end;

function TAtlasAccessibleItem.GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult;
var
  Current: Integer;
begin
  ARetVal := nil;
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  if (APatternId = UiaSelectionItemPatternId) and not FList.Source.AccessibleIsHeader(Current) then
    ARetVal := IAtlasSelectionItemProvider(Self);
  Result := S_OK;
end;

function TAtlasAccessibleItem.GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult;
var
  Current: Integer;
  Source: IAtlasAccessibleItems;
  Bounds: TRect;
begin
  ARetVal := Unassigned;
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  Source := FList.Source;
  case APropertyId of
    UiaControlTypeProperty:
      if Source.AccessibleIsHeader(Current) then
        ARetVal := UiaTextControlType
      else
        ARetVal := UiaListItemControlType;
    UiaNameProperty:
      ARetVal := Source.AccessibleName(Current);
    UiaHelpTextProperty:
      if Source.AccessibleHelp(Current) <> '' then
        ARetVal := Source.AccessibleHelp(Current);
    UiaItemStatusProperty:
      if Source.AccessibleStatus(Current) <> '' then
        ARetVal := Source.AccessibleStatus(Current);
    UiaIsKeyboardFocusableProperty, UiaHasKeyboardFocusProperty:
      ARetVal := False;
    UiaIsEnabledProperty:
      ARetVal := True;
    UiaIsOffscreenProperty:
      ARetVal := not Source.AccessibleBounds(Current, Bounds);
    UiaPositionInSetProperty:
      ARetVal := Current + 1;
    UiaSizeOfSetProperty:
      ARetVal := Source.AccessibleCount;
    UiaFrameworkIdProperty:
      ARetVal := 'Atlas';
  end;
  Result := S_OK;
end;

function TAtlasAccessibleItem.get_HostRawElementProvider(out ARetVal: IAtlasRawElementProvider): HResult;
begin
  // Kein eigenes Fenster.
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleItem.Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult;
var
  Current, Target: Integer;
begin
  ARetVal := nil;
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  Result := S_OK;
  if ADirection = UiaNavigateParent then
  begin
    ARetVal := FList;
    Exit;
  end;
  Target := TAtlasAccessibility.NavigateTarget(ADirection, Current, FList.Source.AccessibleCount);
  if Target >= 0 then
    ARetVal := FList.Item(Target) as IAtlasRawElementFragment;
end;

function TAtlasAccessibleItem.GetRuntimeId(out ARetVal: Pointer): HResult;
var
  Index, Value: Integer;
begin
  ARetVal := SafeArrayCreateVector(VarTypeInteger, 0, 2);
  Result := S_OK;
  if ARetVal = nil then
    Exit(E_OUTOFMEMORY);
  Index := 0;
  Value := UiaAppendRuntimeId;
  SafeArrayPutElement(ARetVal, Index, @Value);
  Index := 1;
  Value := FId;
  SafeArrayPutElement(ARetVal, Index, @Value);
end;

function TAtlasAccessibleItem.get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult;
var
  Current: Integer;
  Bounds: TRect;
begin
  ARetVal := EmptyUiaRect;
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  if FList.Source.AccessibleBounds(Current, Bounds) then
    ARetVal := UiaRect(Bounds);
  Result := S_OK;
end;

function TAtlasAccessibleItem.GetEmbeddedFragmentRoots(out ARetVal: Pointer): HResult;
begin
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleItem.SetFocus: HResult;
begin
  Result := S_OK;
end;

function TAtlasAccessibleItem.get_FragmentRoot(out ARetVal: IAtlasRawElementFragmentRoot): HResult;
begin
  ARetVal := FList;
  Result := S_OK;
end;

function TAtlasAccessibleItem.Select: HResult;
var
  Current: Integer;
begin
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  if not FList.Source.AccessibleIsHeader(Current) then
    FList.Source.AccessibleSelect(Current);
  Result := S_OK;
end;

function TAtlasAccessibleItem.AddToSelection: HResult;
begin
  // Nur eine Auswahl: wie Select.
  Result := Select;
end;

function TAtlasAccessibleItem.RemoveFromSelection: HResult;
begin
  // Die Liste hat immer einen gewählten Eintrag; Abwählen gibt es nicht.
  Result := S_OK;
end;

function TAtlasAccessibleItem.get_IsSelected(out ARetVal: BOOL): HResult;
var
  Current: Integer;
begin
  ARetVal := False;
  Current := Position;
  if Current < 0 then
    Exit(UiaElementNotAvailable);
  ARetVal := FList.Source.AccessibleSelected = Current;
  Result := S_OK;
end;

function TAtlasAccessibleItem.get_SelectionContainer(out ARetVal: IAtlasRawElementProvider): HResult;
begin
  ARetVal := FList;
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

class function TAtlasAccessibility.NavigateTarget(ADirection, AFrom, ACount: Integer): Integer;
begin
  Result := -1;
  if ACount <= 0 then
    Exit;
  case ADirection of
    UiaNavigateFirstChild:
      if AFrom < 0 then
        Result := 0;
    UiaNavigateLastChild:
      if AFrom < 0 then
        Result := ACount - 1;
    UiaNavigateNextSibling:
      if (AFrom >= 0) and (AFrom < ACount - 1) then
        Result := AFrom + 1;
    UiaNavigatePreviousSibling:
      if (AFrom > 0) and (AFrom < ACount) then
        Result := AFrom - 1;
  end;
end;

end.
