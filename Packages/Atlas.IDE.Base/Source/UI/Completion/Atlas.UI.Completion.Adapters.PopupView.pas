unit Atlas.UI.Completion.Adapters.PopupView;

// Das Popup der Vervollständigung (TAtlasCompletionPopup) als Ansicht des Controllers (IAtlasCompletionView,
// IAtlasCompletionSyntaxView, IAtlasCompletionHiddenView aus Atlas.Core.Completion.Controller) und als Quelle der
// Einträge für UI Automation (IAtlasAccessibleItems, #447). Reicht nur weiter; Controller und UI-Automation-Liste
// halten den Adapter, die Kompositionswurzel setzt ihn über TAtlasCompletionViews.Factory ein.

interface

uses
  System.Types,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Controller,
  Atlas.Core.Completion.Ranking,
  Atlas.UI.Popup.Accessibility,
  Atlas.UI.Completion.Popup;

type
  TAtlasCompletionPopupView = class(TInterfacedObject, IAtlasCompletionView, IAtlasCompletionSyntaxView,
    IAtlasCompletionHiddenView, IAtlasAccessibleItems)
  private
    FPopup: TAtlasCompletionPopup;
  public
    /// <summary>APopup lebt so lange wie die Nutzer des Adapters (Controller, UI Automation).</summary>
    constructor Create(APopup: TAtlasCompletionPopup);
    { IAtlasCompletionView }
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
    { IAtlasCompletionSyntaxView }
    procedure ShowSyntax(const ANotice: TAtlasSyntaxNotice);
    { IAtlasCompletionHiddenView }
    procedure ShowInaccessible(const AItems: TAtlasCompletionItems);
    { IAtlasAccessibleItems }
    function AccessibleCount: Integer;
    function AccessibleSelected: Integer;
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    function AccessibleStatus(APosition: Integer): string;
    function AccessibleHelp(APosition: Integer): string;
    function AccessibleIsHeader(APosition: Integer): Boolean;
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
  end;

implementation

{ TAtlasCompletionPopupView }

constructor TAtlasCompletionPopupView.Create(APopup: TAtlasCompletionPopup);
begin
  inherited Create;
  FPopup := APopup;
end;

procedure TAtlasCompletionPopupView.ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  FPopup.ShowList(AItems, AOrder, ASelected, APattern);
end;

procedure TAtlasCompletionPopupView.HideList;
begin
  FPopup.HideList;
end;

procedure TAtlasCompletionPopupView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  FPopup.ShowEmpty(APrefix, ATotal);
end;

function TAtlasCompletionPopupView.PageSize: Integer;
begin
  Result := FPopup.PageSize;
end;

procedure TAtlasCompletionPopupView.ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip;
  AVisible: Boolean);
begin
  FPopup.ShowChips(ACounts, AActive, AVisible);
end;

procedure TAtlasCompletionPopupView.ShowSyntax(const ANotice: TAtlasSyntaxNotice);
begin
  FPopup.ShowSyntax(ANotice);
end;

procedure TAtlasCompletionPopupView.ShowInaccessible(const AItems: TAtlasCompletionItems);
begin
  FPopup.ShowInaccessible(AItems);
end;

function TAtlasCompletionPopupView.AccessibleCount: Integer;
begin
  Result := FPopup.AccessibleCount;
end;

function TAtlasCompletionPopupView.AccessibleSelected: Integer;
begin
  Result := FPopup.AccessibleSelected;
end;

function TAtlasCompletionPopupView.AccessibleId(APosition: Integer): Integer;
begin
  Result := FPopup.AccessibleId(APosition);
end;

function TAtlasCompletionPopupView.AccessibleName(APosition: Integer): string;
begin
  Result := FPopup.AccessibleName(APosition);
end;

function TAtlasCompletionPopupView.AccessibleStatus(APosition: Integer): string;
begin
  Result := FPopup.AccessibleStatus(APosition);
end;

function TAtlasCompletionPopupView.AccessibleHelp(APosition: Integer): string;
begin
  Result := FPopup.AccessibleHelp(APosition);
end;

function TAtlasCompletionPopupView.AccessibleIsHeader(APosition: Integer): Boolean;
begin
  Result := FPopup.AccessibleIsHeader(APosition);
end;

function TAtlasCompletionPopupView.AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
begin
  Result := FPopup.AccessibleBounds(APosition, ARect);
end;

procedure TAtlasCompletionPopupView.AccessibleSelect(APosition: Integer);
begin
  FPopup.AccessibleSelect(APosition);
end;

end.
