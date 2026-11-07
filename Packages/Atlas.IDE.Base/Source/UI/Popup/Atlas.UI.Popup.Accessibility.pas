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
  cUiaRootObjectId = -25;
  cUiaAppendRuntimeId = 3;
  cProviderOptionsServerSide = $2;
  cProviderOptionsUseComThreading = $20;
  cUiaSelectionPatternId = 10001;
  cUiaSelectionItemPatternId = 10010;
  cUiaControlTypeProperty = 30003;
  cUiaNameProperty = 30005;
  cUiaHasKeyboardFocusProperty = 30008;
  cUiaIsKeyboardFocusableProperty = 30009;
  cUiaIsEnabledProperty = 30010;
  cUiaHelpTextProperty = 30013;
  cUiaIsOffscreenProperty = 30022;
  cUiaFrameworkIdProperty = 30024;
  cUiaItemStatusProperty = 30026;
  cUiaPositionInSetProperty = 30152;
  cUiaSizeOfSetProperty = 30153;
  cUiaElementSelectedEvent = 20012;
  cStructureChangeChildrenInvalidated = 2;
  cNotificationKindOther = 4;
  cNotificationProcessingImportantMostRecent = 1;
  cUiaElementNotAvailable = HResult($80040201);
  cVarTypeInteger = 3;
  cVarTypeUnknown = 13;

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
  mModule: HMODULE;
begin
  if Loaded then
  begin
    Exit;
  end;
  Loaded := True;
  mModule := LoadLibrary('UIAutomationCore.dll');
  if mModule = 0 then
  begin
    Exit;
  end;
  @ReturnRawElementProvider := GetProcAddress(mModule, 'UiaReturnRawElementProvider');
  @HostProviderFromHwnd := GetProcAddress(mModule, 'UiaHostProviderFromHwnd');
  @RaiseNotificationEvent := GetProcAddress(mModule, 'UiaRaiseNotificationEvent');
  @RaiseAutomationEvent := GetProcAddress(mModule, 'UiaRaiseAutomationEvent');
  @RaiseStructureChangedEvent := GetProcAddress(mModule, 'UiaRaiseStructureChangedEvent');
  @ClientsAreListening := GetProcAddress(mModule, 'UiaClientsAreListening');
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
  ARetVal := cProviderOptionsServerSide or cProviderOptionsUseComThreading;
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
    cUiaControlTypeProperty:
      ARetVal := FControlType;
    cUiaNameProperty:
      ARetVal := FName;
    cUiaIsKeyboardFocusableProperty, cUiaHasKeyboardFocusProperty:
      ARetVal := False;
    cUiaFrameworkIdProperty:
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
  begin
    Result := HostProviderFromHwnd(FWindow, ARetVal);
  end
  else
  begin
    Result := S_OK;
  end;
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
  if (APatternId = cUiaSelectionPatternId) and (FSource <> nil) then
  begin
    ARetVal := IAtlasSelectionProvider(Self);
    Result := S_OK;
  end
  else
  begin
    Result := inherited GetPatternProvider(APatternId, ARetVal);
  end;
end;

function TAtlasAccessibleList.Item(APosition: Integer): IAtlasRawElementProvider;
begin
  Result := nil;
  if (FSource <> nil) and (APosition >= 0) and (APosition < FSource.AccessibleCount) then
  begin
    Result := TAtlasAccessibleItem.Create(Self, APosition);
  end;
end;

function TAtlasAccessibleList.Navigate(ADirection: Integer; out ARetVal: IAtlasRawElementFragment): HResult;
var
  mTarget: Integer;
begin
  ARetVal := nil;
  Result := S_OK;
  // Eltern und Geschwister der Liste liefert der Host (das Fenster).
  if (FSource = nil) or ((ADirection <> UiaNavigateFirstChild) and (ADirection <> UiaNavigateLastChild)) then
  begin
    Exit;
  end;
  mTarget := TAtlasAccessibility.NavigateTarget(ADirection, -1, FSource.AccessibleCount);
  if mTarget >= 0 then
  begin
    ARetVal := Item(mTarget) as IAtlasRawElementFragment;
  end;
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
  mPosition: Integer;
  mBounds: TRect;
begin
  ARetVal := nil;
  Result := S_OK;
  if FSource = nil then
  begin
    Exit;
  end;
  for mPosition := 0 to FSource.AccessibleCount - 1 do
  begin
    if FSource.AccessibleBounds(mPosition, mBounds) and (AX >= mBounds.Left) and (AX < mBounds.Right) and
      (AY >= mBounds.Top) and (AY < mBounds.Bottom) then
    begin
      ARetVal := Item(mPosition) as IAtlasRawElementFragment;
      Exit;
    end;
  end;
end;

function TAtlasAccessibleList.GetFocus(out ARetVal: IAtlasRawElementFragment): HResult;
begin
  ARetVal := nil;
  Result := S_OK;
end;

function TAtlasAccessibleList.GetSelection(out ARetVal: Pointer): HResult;
var
  mSelected: IAtlasRawElementProvider;
  mIndex: Integer;
begin
  ARetVal := nil;
  Result := S_OK;
  if FSource = nil then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  mSelected := Item(FSource.AccessibleSelected);
  if (mSelected = nil) or FSource.AccessibleIsHeader(FSource.AccessibleSelected) then
  begin
    ARetVal := SafeArrayCreateVector(cVarTypeUnknown, 0, 0);
    Exit;
  end;
  ARetVal := SafeArrayCreateVector(cVarTypeUnknown, 0, 1);
  mIndex := 0;
  if ARetVal <> nil then
  begin
    Result := SafeArrayPutElement(ARetVal, mIndex, Pointer(mSelected));
  end;
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
  mSelected: IAtlasRawElementProvider;
begin
  if (FSource = nil) or not TAtlasAccessibility.Listening or not Assigned(RaiseAutomationEvent) then
  begin
    Exit;
  end;
  if FSource.AccessibleIsHeader(FSource.AccessibleSelected) then
  begin
    Exit;
  end;
  mSelected := Item(FSource.AccessibleSelected);
  if mSelected <> nil then
  begin
    RaiseAutomationEvent(mSelected, cUiaElementSelectedEvent);
  end;
end;

procedure TAtlasAccessibleList.ItemsChanged;
begin
  if (FSource = nil) or not TAtlasAccessibility.Listening or not Assigned(RaiseStructureChangedEvent) then
  begin
    Exit;
  end;
  RaiseStructureChangedEvent(Self, cStructureChangeChildrenInvalidated, nil, 0);
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
  mSource: IAtlasAccessibleItems;
  mIndex: Integer;
begin
  Result := -1;
  mSource := FList.Source;
  if mSource = nil then
  begin
    Exit;
  end;
  // Meist steht der Eintrag noch an derselben Stelle; nach dem Filtern wird er gesucht.
  if (FPosition < mSource.AccessibleCount) and (mSource.AccessibleId(FPosition) = FId) then
  begin
    Exit(FPosition);
  end;
  for mIndex := 0 to mSource.AccessibleCount - 1 do
  begin
    if mSource.AccessibleId(mIndex) = FId then
    begin
      FPosition := mIndex;
      Exit(mIndex);
    end;
  end;
end;

function TAtlasAccessibleItem.get_ProviderOptions(out ARetVal: Integer): HResult;
begin
  ARetVal := cProviderOptionsServerSide or cProviderOptionsUseComThreading;
  Result := S_OK;
end;

function TAtlasAccessibleItem.GetPatternProvider(APatternId: Integer; out ARetVal: IUnknown): HResult;
var
  mCurrent: Integer;
begin
  ARetVal := nil;
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  if (APatternId = cUiaSelectionItemPatternId) and not FList.Source.AccessibleIsHeader(mCurrent) then
  begin
    ARetVal := IAtlasSelectionItemProvider(Self);
  end;
  Result := S_OK;
end;

function TAtlasAccessibleItem.GetPropertyValue(APropertyId: Integer; out ARetVal: OleVariant): HResult;
var
  mCurrent: Integer;
  mSource: IAtlasAccessibleItems;
  mBounds: TRect;
begin
  ARetVal := Unassigned;
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  mSource := FList.Source;
  case APropertyId of
    cUiaControlTypeProperty:
      if mSource.AccessibleIsHeader(mCurrent) then
      begin
        ARetVal := UiaTextControlType;
      end
      else
      begin
        ARetVal := UiaListItemControlType;
      end;
    cUiaNameProperty:
      ARetVal := mSource.AccessibleName(mCurrent);
    cUiaHelpTextProperty:
      if mSource.AccessibleHelp(mCurrent) <> '' then
      begin
        ARetVal := mSource.AccessibleHelp(mCurrent);
      end;
    cUiaItemStatusProperty:
      if mSource.AccessibleStatus(mCurrent) <> '' then
      begin
        ARetVal := mSource.AccessibleStatus(mCurrent);
      end;
    cUiaIsKeyboardFocusableProperty, cUiaHasKeyboardFocusProperty:
      ARetVal := False;
    cUiaIsEnabledProperty:
      ARetVal := True;
    cUiaIsOffscreenProperty:
      ARetVal := not mSource.AccessibleBounds(mCurrent, mBounds);
    cUiaPositionInSetProperty:
      ARetVal := mCurrent + 1;
    cUiaSizeOfSetProperty:
      ARetVal := mSource.AccessibleCount;
    cUiaFrameworkIdProperty:
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
  mCurrent, mTarget: Integer;
begin
  ARetVal := nil;
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  Result := S_OK;
  if ADirection = UiaNavigateParent then
  begin
    ARetVal := FList;
    Exit;
  end;
  mTarget := TAtlasAccessibility.NavigateTarget(ADirection, mCurrent, FList.Source.AccessibleCount);
  if mTarget >= 0 then
  begin
    ARetVal := FList.Item(mTarget) as IAtlasRawElementFragment;
  end;
end;

function TAtlasAccessibleItem.GetRuntimeId(out ARetVal: Pointer): HResult;
var
  mIndex, mValue: Integer;
begin
  ARetVal := SafeArrayCreateVector(cVarTypeInteger, 0, 2);
  Result := S_OK;
  if ARetVal = nil then
  begin
    Exit(E_OUTOFMEMORY);
  end;
  mIndex := 0;
  mValue := cUiaAppendRuntimeId;
  SafeArrayPutElement(ARetVal, mIndex, @mValue);
  mIndex := 1;
  mValue := FId;
  SafeArrayPutElement(ARetVal, mIndex, @mValue);
end;

function TAtlasAccessibleItem.get_BoundingRectangle(out ARetVal: TAtlasUiaRect): HResult;
var
  mCurrent: Integer;
  mBounds: TRect;
begin
  ARetVal := EmptyUiaRect;
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  if FList.Source.AccessibleBounds(mCurrent, mBounds) then
  begin
    ARetVal := UiaRect(mBounds);
  end;
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
  mCurrent: Integer;
begin
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  if not FList.Source.AccessibleIsHeader(mCurrent) then
  begin
    FList.Source.AccessibleSelect(mCurrent);
  end;
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
  mCurrent: Integer;
begin
  ARetVal := False;
  mCurrent := Position;
  if mCurrent < 0 then
  begin
    Exit(cUiaElementNotAvailable);
  end;
  ARetVal := FList.Source.AccessibleSelected = mCurrent;
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
  if (Integer(ALParam) <> cUiaRootObjectId) or (AElement = nil) then
  begin
    Exit;
  end;
  Load;
  if Assigned(ReturnRawElementProvider) then
  begin
    Result := ReturnRawElementProvider(AWindow, AWParam, ALParam, AElement);
  end;
end;

class procedure TAtlasAccessibility.Release(AWindow: HWND);
begin
  Load;
  if Assigned(ReturnRawElementProvider) then
  begin
    ReturnRawElementProvider(AWindow, 0, 0, nil);
  end;
end;

class function TAtlasAccessibility.Listening: Boolean;
begin
  Load;
  Result := Assigned(ClientsAreListening) and Assigned(RaiseNotificationEvent) and ClientsAreListening;
end;

class procedure TAtlasAccessibility.Announce(const AElement: IAtlasRawElementProvider; const AText: string);
begin
  if (AElement = nil) or (AText = '') or not Listening then
  begin
    Exit;
  end;
  RaiseNotificationEvent(AElement, cNotificationKindOther, cNotificationProcessingImportantMostRecent,
    PWideChar(AText), 'Atlas');
end;

class function TAtlasAccessibility.NavigateTarget(ADirection, AFrom, ACount: Integer): Integer;
begin
  Result := -1;
  if ACount <= 0 then
  begin
    Exit;
  end;
  case ADirection of
    UiaNavigateFirstChild:
      if AFrom < 0 then
      begin
        Result := 0;
      end;
    UiaNavigateLastChild:
      if AFrom < 0 then
      begin
        Result := ACount - 1;
      end;
    UiaNavigateNextSibling:
      if (AFrom >= 0) and (AFrom < ACount - 1) then
      begin
        Result := AFrom + 1;
      end;
    UiaNavigatePreviousSibling:
      if (AFrom > 0) and (AFrom < ACount) then
      begin
        Result := AFrom - 1;
      end;
  end;
end;

end.
