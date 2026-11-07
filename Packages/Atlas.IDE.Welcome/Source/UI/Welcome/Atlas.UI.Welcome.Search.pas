unit Atlas.UI.Welcome.Search;

// Suchfeld im Kopf der Willkommensseite (#760): ein Eingabefeld, darunter
// beim Tippen eine Liste in Gruppen (Projekte, Dateien, Symbole, Befehle)
// im Stil der Atlas-Popups. Die Liste nimmt nie den Fokus (WS_EX_NOACTIVATE),
// der bleibt im Eingabefeld: Pfeiltasten wählen, Enter öffnet, Esc leert das
// Feld, Klick öffnet direkt. OnQuery liefert die Gruppen 150 ms nach der
// letzten Eingabe (Muster wie die Palette, #502), OnOpen öffnet den Treffer.
// Die Liste hängt am Fenster des Felds und verschwindet, sobald das Feld den
// Fokus verliert.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Welcome.Search;

type
  TAtlasWelcomeSearchQuery = reference to function(const APattern: string): TArray<TAtlasWelcomeSearchResult>;
  TAtlasWelcomeSearchOpen = reference to procedure(const AHit: TAtlasWelcomeHit);

  TAtlasWelcomeSearchBox = class;

  /// <summary>Eingabefeld, das Enter, Esc und Pfeiltasten selbst behandelt (nicht der Dialog der IDE).</summary>
  TAtlasWelcomeSearchEdit = class(TEdit)
  private
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  end;

  /// <summary>Ergebnisliste unter dem Feld; aktiviert sich nie.</summary>
  TAtlasWelcomeSearchList = class(TCustomControl)
  private
    FBox: TAtlasWelcomeSearchBox;
    FOwnerWindow: HWND;
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure DrawRow(ARow: Integer; const ARect: TRect);
    procedure DrawHit(AIndex: Integer; const ARect: TRect; APart: TRect);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    function RowHeight: Integer;
    function RowAt(AY: Integer): Integer;
  end;

  TAtlasWelcomeSearchBox = class(TCustomPanel)
  private
    FEdit: TAtlasWelcomeSearchEdit;
    FList: TAtlasWelcomeSearchList;
    FTimer: TTimer;
    FColors: TAtlasColors;
    FResults: TArray<TAtlasWelcomeSearchResult>;
    FHits: TArray<TAtlasWelcomeHit>;
    FRows: TArray<TAtlasWelcomeSearchRow>;
    FSelected: Integer;
    FOnQuery: TAtlasWelcomeSearchQuery;
    FOnOpen: TAtlasWelcomeSearchOpen;
    procedure EditChange(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure TimerTick(Sender: TObject);
    procedure ShowList;
    procedure HideList;
    procedure SetColors(const AValue: TAtlasColors);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Gruppen zum aktuellen Text sofort holen (ohne Tipppause).</summary>
    procedure Query;
    /// <summary>Feld leeren und Liste schließen (Esc).</summary>
    procedure Clear;
    /// <summary>Fokus ins Feld, Text markiert (Strg+E).</summary>
    procedure FocusSearch;
    /// <summary>Treffer AIndex (in Hits) wählen; außerhalb wird begrenzt.</summary>
    procedure Select(AIndex: Integer);
    /// <summary>Gewählten Treffer öffnen; das Feld wird danach geleert.</summary>
    procedure OpenSelected;
    /// <summary>Überschrift einer Gruppe in der Sprache der IDE.</summary>
    class function GroupCaption(AGroup: TAtlasWelcomeSearchGroup): string; static;
    property Edit: TAtlasWelcomeSearchEdit read FEdit;
    property Results: TArray<TAtlasWelcomeSearchResult> read FResults;
    property Hits: TArray<TAtlasWelcomeHit> read FHits;
    property Rows: TArray<TAtlasWelcomeSearchRow> read FRows;
    /// <summary>Index in Hits; -1 ohne Treffer.</summary>
    property Selected: Integer read FSelected;
    property Colors: TAtlasColors read FColors write SetColors;
    property OnQuery: TAtlasWelcomeSearchQuery read FOnQuery write FOnQuery;
    property OnOpen: TAtlasWelcomeSearchOpen read FOnOpen write FOnOpen;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Style.Color,
  Atlas.UI.Welcome.Strings;

const
  cVisibleRows = 18;
  cListWidth = 460;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasWelcomeSearchEdit }

procedure TAtlasWelcomeSearchEdit.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTALLKEYS or DLGC_WANTARROWS;
end;

{ TAtlasWelcomeSearchList }

procedure TAtlasWelcomeSearchList.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP or WS_BORDER;
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
  // Am Fenster des Felds: bleibt darüber, verschwindet mit ihm, liegt nicht über anderen Programmen.
  Params.WndParent := FOwnerWindow;
end;

procedure TAtlasWelcomeSearchList.WMMouseActivate(var Message: TWMMouseActivate);
begin
  Message.Result := MA_NOACTIVATE;
end;

function TAtlasWelcomeSearchList.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + MulDiv(8, Screen.PixelsPerInch, 96);
end;

function TAtlasWelcomeSearchList.RowAt(AY: Integer): Integer;
begin
  Result := AY div RowHeight;
  if (Result < 0) or (Result > High(FBox.FRows)) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasWelcomeSearchList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mRow: Integer;
begin
  inherited;
  mRow := RowAt(Y);
  if (mRow < 0) or (FBox.FRows[mRow].Kind <> TAtlasWelcomeRowKind.Hit) then
  begin
    Exit;
  end;
  FBox.Select(FBox.FRows[mRow].Index);
  FBox.OpenSelected;
end;

procedure TAtlasWelcomeSearchList.DrawRow(ARow: Integer; const ARect: TRect);
var
  mRow: TAtlasWelcomeSearchRow;
  mText: string;
  mPart: TRect;
begin
  mRow := FBox.FRows[ARow];
  mPart := ARect;
  InflateRect(mPart, -MulDiv(10, Screen.PixelsPerInch, 96), 0);
  Canvas.Brush.Style := bsClear;
  case mRow.Kind of
    TAtlasWelcomeRowKind.Group:
      begin
        Canvas.Font.Style := [fsBold];
        Canvas.Font.Color := ToColor(FBox.FColors.Muted);
        mText := TAtlasWelcomeSearchBox.GroupCaption(mRow.Group);
        DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
        Canvas.Font.Style := [];
      end;
    TAtlasWelcomeRowKind.Hint, TAtlasWelcomeRowKind.More:
      begin
        Canvas.Font.Style := [fsItalic];
        Canvas.Font.Color := ToColor(FBox.FColors.Muted);
        if mRow.Kind = TAtlasWelcomeRowKind.Hint then
        begin
          mText := mRow.Text;
        end
        else
        begin
          mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSearchMore, [mRow.Index]);
        end;
        Inc(mPart.Left, MulDiv(12, Screen.PixelsPerInch, 96));
        DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
        Canvas.Font.Style := [];
      end;
  else
    DrawHit(mRow.Index, ARect, mPart);
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasWelcomeSearchList.DrawHit(AIndex: Integer; const ARect: TRect; APart: TRect);
var
  mHit: TAtlasWelcomeHit;
  mCell: TRect;
  mWidth: Integer;
begin
  mHit := FBox.FHits[AIndex];
  if AIndex = FBox.FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FBox.FColors.Selection);
    Canvas.FillRect(ARect);
    Canvas.Brush.Style := bsClear;
  end;
  Inc(APart.Left, MulDiv(12, Screen.PixelsPerInch, 96));
  Canvas.Font.Color := ToColor(FBox.FColors.Text);
  mWidth := Min(Canvas.TextWidth(mHit.Caption) + MulDiv(4, Screen.PixelsPerInch, 96), APart.Width);
  mCell := Rect(APart.Left, APart.Top, APart.Left + mWidth, APart.Bottom);
  DrawText(Canvas.Handle, PChar(mHit.Caption), -1, mCell, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  if mHit.Detail <> '' then
  begin
    Canvas.Font.Color := ToColor(FBox.FColors.Muted);
    mCell := Rect(APart.Left + mWidth + MulDiv(10, Screen.PixelsPerInch, 96), APart.Top, APart.Right, APart.Bottom);
    DrawText(Canvas.Handle, PChar(mHit.Detail), -1, mCell,
      DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_PATH_ELLIPSIS);
  end;
end;

procedure TAtlasWelcomeSearchList.Paint;
var
  mRow, mHeight_: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FBox.FColors.Surface);
  Canvas.FillRect(ClientRect);
  mHeight_ := RowHeight;
  for mRow := 0 to Min(High(FBox.FRows), cVisibleRows - 1) do
  begin
    DrawRow(mRow, Rect(0, mRow * mHeight_, ClientWidth, (mRow + 1) * mHeight_));
  end;
end;

{ TAtlasWelcomeSearchBox }

constructor TAtlasWelcomeSearchBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  ShowCaption := False;
  FColors := TAtlasColors.Light;
  FEdit := TAtlasWelcomeSearchEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.TextHint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchHint);
  FEdit.OnChange := EditChange;
  FEdit.OnExit := EditExit;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnKeyPress := EditKeyPress;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 150;
  FTimer.OnTimer := TimerTick;
  FSelected := -1;
end;

destructor TAtlasWelcomeSearchBox.Destroy;
begin
  HideList;
  inherited;
end;

class function TAtlasWelcomeSearchBox.GroupCaption(AGroup: TAtlasWelcomeSearchGroup): string;
begin
  case AGroup of
    TAtlasWelcomeSearchGroup.Projects:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchProjects);
    TAtlasWelcomeSearchGroup.Files:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchFiles);
    TAtlasWelcomeSearchGroup.Symbols:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchSymbols);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSearchCommands);
  end;
end;

procedure TAtlasWelcomeSearchBox.SetColors(const AValue: TAtlasColors);
begin
  FColors := AValue;
  if FList <> nil then
  begin
    FList.Invalidate;
  end;
end;

procedure TAtlasWelcomeSearchBox.EditChange(Sender: TObject);
begin
  // Neu starten: erst nach einer Tipppause fragen.
  FTimer.Enabled := False;
  if Trim(FEdit.Text) = '' then
  begin
    FResults := nil;
    FHits := nil;
    FRows := nil;
    FSelected := -1;
    HideList;
    Exit;
  end;
  FTimer.Enabled := True;
end;

procedure TAtlasWelcomeSearchBox.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  Query;
end;

procedure TAtlasWelcomeSearchBox.Query;
begin
  FTimer.Enabled := False;
  FResults := nil;
  if Assigned(FOnQuery) and (Trim(FEdit.Text) <> '') then
  begin
    FResults := FOnQuery(FEdit.Text);
  end;
  FHits := TAtlasWelcomeSearch.Flatten(FResults);
  FRows := TAtlasWelcomeSearch.Rows(FResults);
  FSelected := -1;
  if Length(FHits) > 0 then
  begin
    FSelected := 0;
  end;
  if (Length(FRows) > 0) and FEdit.Focused then
  begin
    ShowList;
  end
  else
  begin
    HideList;
  end;
end;

procedure TAtlasWelcomeSearchBox.Clear;
begin
  FTimer.Enabled := False;
  FEdit.Text := '';
  FResults := nil;
  FHits := nil;
  FRows := nil;
  FSelected := -1;
  HideList;
end;

procedure TAtlasWelcomeSearchBox.FocusSearch;
begin
  if not FEdit.CanFocus then
  begin
    Exit;
  end;
  FEdit.SetFocus;
  FEdit.SelectAll;
end;

procedure TAtlasWelcomeSearchBox.Select(AIndex: Integer);
begin
  if Length(FHits) = 0 then
  begin
    Exit;
  end;
  FSelected := EnsureRange(AIndex, 0, High(FHits));
  if FList <> nil then
  begin
    FList.Invalidate;
  end;
end;

procedure TAtlasWelcomeSearchBox.OpenSelected;
var
  mHit: TAtlasWelcomeHit;
  mHandler: TAtlasWelcomeSearchOpen;
  mOpen: TThreadProcedure;
begin
  if (FSelected < 0) or (FSelected > High(FHits)) then
  begin
    Exit;
  end;
  mHit := FHits[FSelected];
  mHandler := FOnOpen;
  Clear;
  // Erst nach dem Schließen öffnen: Projekt laden kann dauern und Dialoge zeigen.
  if Assigned(mHandler) then
  begin
    mOpen :=
      procedure
      begin
        mHandler(mHit);
      end;
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, mOpen);
  end;
end;

procedure TAtlasWelcomeSearchBox.EditExit(Sender: TObject);
begin
  HideList;
end;

procedure TAtlasWelcomeSearchBox.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN:
      Select(FSelected + 1);
    VK_UP:
      Select(FSelected - 1);
    VK_RETURN:
      begin
        // Noch in der Tipppause: erst die Treffer zum aktuellen Text holen.
        if FTimer.Enabled then
        begin
          Query;
        end;
        OpenSelected;
      end;
    VK_ESCAPE:
      Clear;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasWelcomeSearchBox.EditKeyPress(Sender: TObject; var Key: Char);
begin
  // Kein Signalton für Enter und Esc.
  if (Key = #13) or (Key = #27) then
  begin
    Key := #0;
  end;
end;

procedure TAtlasWelcomeSearchBox.ShowList;
var
  mOrigin: TPoint;
  mArea: TRect;
  mWidth_, mHeight_: Integer;
begin
  if not FEdit.HandleAllocated then
  begin
    Exit;
  end;
  if FList = nil then
  begin
    FList := TAtlasWelcomeSearchList.Create(nil);
    FList.FBox := Self;
    FList.FOwnerWindow := GetAncestor(FEdit.Handle, GA_ROOT);
    FList.Font.Assign(Font);
    FList.Font.Name := 'Segoe UI';
    // Unsichtbar anlegen; gezeigt wird ohne Aktivieren über SetWindowPos.
    FList.Visible := False;
    FList.ParentWindow := FList.FOwnerWindow;
    FList.DoubleBuffered := True;
  end;
  mOrigin := FEdit.ClientToScreen(Point(0, FEdit.Height));
  mWidth_ := Max(FEdit.Width, MulDiv(cListWidth, Screen.PixelsPerInch, 96));
  mHeight_ := Min(Length(FRows), cVisibleRows) * FList.RowHeight + 2;
  mArea := Screen.MonitorFromPoint(mOrigin).WorkareaRect;
  // Rechts bündig unter dem Feld (es steht rechts im Kopf), nie über den Bildschirm hinaus.
  mOrigin.X := Max(mArea.Left, Min(mOrigin.X + FEdit.Width - mWidth_, mArea.Right - mWidth_));
  if mOrigin.Y + mHeight_ > mArea.Bottom then
  begin
    mOrigin.Y := Max(mArea.Top, mOrigin.Y - FEdit.Height - mHeight_);
  end;
  FList.SetBounds(mOrigin.X, mOrigin.Y, mWidth_, mHeight_);
  // SWP_NOOWNERZORDER: nicht die ganze Owner-Gruppe umsortieren (Hänger wie in TAtlasPopupWindow.ShowAt).
  SetWindowPos(FList.Handle, HWND_TOP, mOrigin.X, mOrigin.Y, mWidth_, mHeight_,
    SWP_SHOWWINDOW or SWP_NOACTIVATE or SWP_NOOWNERZORDER);
  FList.Invalidate;
end;

procedure TAtlasWelcomeSearchBox.HideList;
begin
  FreeAndNil(FList);
end;

end.
