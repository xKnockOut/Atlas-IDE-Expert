unit Atlas.UI.Diagnostics.PluginParts;

// Teile des Diagnose-Fensters, reine VCL:
// - TAtlasDiagnosticTabs: gezeichnete Reiterleiste (braucht vor dem Zeigen
//   kein Fenster, anders als TTabControl.Tabs).
// - TAtlasDiagnosticBar: Belegung des Hauptthreads (Verlauf der letzten 60 s
//   und Mittel), Schwelle, Anhalten/Weiter, Zurücksetzen, Bericht kopieren und
//   ein kurzer Hinweis. Passen Angaben und Knöpfe nicht nebeneinander (das
//   Fenster in seiner Startgröße), stehen die Knöpfe in einer zweiten Zeile;
//   vorher lagen sie über Verlauf und Schwelle.
// - TAtlasTablePage: eine Seite mit Kopfzeile und Tabelle (Server,
//   Hintergrund, Hänger).
// - TAtlasFeatureMenu: Kontextmenü der Funktionen (nur diese zeigen, alle
//   zeigen, bis zum Neustart ausschalten, Zeile kopieren).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Grid;

type
{$SCOPEDENUMS ON}
  TAtlasDiagnosticPage = (MainThread, Server, Background, Hangs, Completion);
{$SCOPEDENUMS OFF}

  TAtlasDiagnosticTabs = class(TPaintBox)
  private
    FRects: array[TAtlasDiagnosticPage] of TRect;
    FActive: TAtlasDiagnosticPage;
    FColors: TAtlasColors;
    FOnChange: TNotifyEvent;
    procedure SetActive(AValue: TAtlasDiagnosticPage);
    procedure SetColors(const AValue: TAtlasColors);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    class function Caption(APage: TAtlasDiagnosticPage): string; static;
    /// <summary>Reiter an der Stelle AX (nach dem ersten Zeichnen); False daneben.</summary>
    function PageAt(AX, AY: Integer; out APage: TAtlasDiagnosticPage): Boolean;
    property Active: TAtlasDiagnosticPage read FActive write SetActive;
    property Colors: TAtlasColors read FColors write SetColors;
    /// <summary>Nach einem Klick auf einen anderen Reiter.</summary>
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  /// <summary>Verlauf der Belegung: immer 60 Sekunden breit, neueste rechts; 0 % unten, 100 % oben.</summary>
  TAtlasBusySpark = class(TPaintBox)
  private
    FColors: TAtlasColors;
    FValues: TArray<Double>;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Belegung je Sekunde in Prozent, älteste zuerst.</summary>
    procedure SetValues(const AValues: TArray<Double>);
    procedure SetColors(const AColors: TAtlasColors);
  end;

  TAtlasDiagnosticBar = class(TPanel)
  private
    FButtons: TPanel;
    FSpark: TAtlasBusySpark;
    FBusy: TLabel;
    FThreshold: TLabel;
    FPause: TButton;
    FReset: TButton;
    FCopy: TButton;
    FNote: TLabel;
    FPaused: Boolean;
    FOnPause: TProc<Boolean>;
    FOnReset: TProc;
    FOnCopy: TProc;
    FArranging: Boolean;
    /// <summary>Breite der Knöpfe nebeneinander; in der zweiten Zeile ist FButtons so breit wie die Leiste.</summary>
    FButtonsWidth: Integer;
    function NewButton(AId: TAtlasTextId; AClick: TNotifyEvent): TButton;
    function NewLabel: TLabel;
    function RowHeight: Integer;
    function InfoWidth: Integer;
    procedure Arrange;
    procedure PauseClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Angaben links und Knöpfe rechts passen nicht in eine Zeile: Knöpfe darunter.</summary>
    class function NeedsTwoRows(AInfoWidth, AButtonsWidth, AClientWidth: Integer): Boolean; static;
    procedure SetSnapshot(const ASnapshot: TAtlasPluginSnapshot);
    procedure SetColors(const AColors: TAtlasColors);
    procedure ShowNote(const AText: string);
    property Busy: TLabel read FBusy;
    property Threshold: TLabel read FThreshold;
    property Note: TLabel read FNote;
    property Spark: TAtlasBusySpark read FSpark;
    /// <summary>Knöpfe Anhalten, Zurücksetzen, Bericht kopieren; rechts bzw. (schmal) in der zweiten Zeile.</summary>
    property Buttons: TPanel read FButtons;
    property PauseButton: TButton read FPause;
    property ResetButton: TButton read FReset;
    property CopyButton: TButton read FCopy;
    /// <summary>Anhalten (True) bzw. Weiter (False).</summary>
    property OnPause: TProc<Boolean> read FOnPause write FOnPause;
    property OnReset: TProc read FOnReset write FOnReset;
    property OnCopy: TProc read FOnCopy write FOnCopy;
  end;

  TAtlasTablePage = class(TPanel)
  private
    FHeader: TLabel;
    FGrid: TAtlasDiagnosticGrid;
  public
    /// <summary>AWithHeader: Zeile über der Tabelle (Arbeiter, Zahl der Hänger).</summary>
    constructor CreatePage(AOwner: TComponent; AWithHeader: Boolean);
    property Header: TLabel read FHeader;
    property Grid: TAtlasDiagnosticGrid read FGrid;
  end;

  TAtlasFeatureMenu = class(TPopupMenu)
  private
    FOnly: TMenuItem;
    FAll: TMenuItem;
    FDisable: TMenuItem;
    FCopyRow: TMenuItem;
    function NewItem: TMenuItem;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Beschriftung und Sichtbarkeit für die gewählte Funktion AName ('' = keine gewählt).</summary>
    procedure Prepare(const AName: string; AFiltered: Boolean);
    property OnlyItem: TMenuItem read FOnly;
    property AllItem: TMenuItem read FAll;
    property DisableItem: TMenuItem read FDisable;
    property CopyRowItem: TMenuItem read FCopyRow;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  Atlas.UI.Diagnostics.Strings,
  Winapi.Windows,
  Atlas.Core.Diagnostics.PluginReport;

const
  cTabFlags = DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_CENTER;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasDiagnosticTabs }

constructor TAtlasDiagnosticTabs.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Align := alTop;
  Height := MulDiv(26, CurrentPPI, 96);
end;

class function TAtlasDiagnosticTabs.Caption(APage: TAtlasDiagnosticPage): string;
begin
  case APage of
    TAtlasDiagnosticPage.MainThread:
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagTabMainThread);
    TAtlasDiagnosticPage.Server:
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagTabServer);
    TAtlasDiagnosticPage.Background:
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagTabBackground);
    TAtlasDiagnosticPage.Hangs:
      Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagTabHangs);
  else
    Result := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagTabCompletion);
  end;
end;

procedure TAtlasDiagnosticTabs.SetActive(AValue: TAtlasDiagnosticPage);
begin
  FActive := AValue;
  Invalidate;
end;

procedure TAtlasDiagnosticTabs.SetColors(const AValue: TAtlasColors);
begin
  FColors := AValue;
  Invalidate;
end;

function TAtlasDiagnosticTabs.PageAt(AX, AY: Integer; out APage: TAtlasDiagnosticPage): Boolean;
var
  mPage: TAtlasDiagnosticPage;
begin
  APage := FActive;
  for mPage := Low(TAtlasDiagnosticPage) to High(TAtlasDiagnosticPage) do
  begin
    if PtInRect(FRects[mPage], Point(AX, AY)) then
    begin
      APage := mPage;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasDiagnosticTabs.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mPage: TAtlasDiagnosticPage;
begin
  inherited;
  if PageAt(X, Y, mPage) and (mPage <> FActive) then
  begin
    Active := mPage;
    if Assigned(FOnChange) then
    begin
      FOnChange(Self);
    end;
  end;
end;

procedure TAtlasDiagnosticTabs.Paint;
var
  mPage: TAtlasDiagnosticPage;
  mLeft, mWidth: Integer;
  mText: string;
  mRect: TRect;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  mLeft := 0;
  for mPage := Low(TAtlasDiagnosticPage) to High(TAtlasDiagnosticPage) do
  begin
    mText := Caption(mPage);
    mWidth := Canvas.TextWidth(mText) + MulDiv(20, CurrentPPI, 96);
    mRect := Rect(mLeft, 0, mLeft + mWidth, Height);
    FRects[mPage] := mRect;
    Canvas.Font.Color := ToColor(FColors.Muted);
    if mPage = FActive then
    begin
      Canvas.Font.Color := ToColor(FColors.Text);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Accent);
      Canvas.FillRect(Rect(mRect.Left, mRect.Bottom - MulDiv(2, CurrentPPI, 96), mRect.Right, mRect.Bottom));
    end;
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect, cTabFlags);
    Inc(mLeft, mWidth);
  end;
end;

{ TAtlasBusySpark }

constructor TAtlasBusySpark.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
end;

procedure TAtlasBusySpark.SetValues(const AValues: TArray<Double>);
begin
  FValues := AValues;
  Invalidate;
end;

procedure TAtlasBusySpark.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasBusySpark.Paint;
var
  mIndex, mX, mY, mCount, mSeconds: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  mCount := Length(FValues);
  if mCount = 0 then
  begin
    Exit;
  end;
  mSeconds := TAtlasBusyMeter.cSeconds;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  for mIndex := 0 to mCount - 1 do
  begin
    mX := MulDiv(mSeconds - mCount + mIndex, Width - 1, mSeconds - 1);
    mY := Height - 2 - Round(FValues[mIndex] * (Height - 4) / 100);
    if mIndex = 0 then
    begin
      Canvas.MoveTo(mX, mY);
    end
    else
    begin
      Canvas.LineTo(mX, mY);
    end;
  end;
end;

{ TAtlasDiagnosticBar }

constructor TAtlasDiagnosticBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  Height := RowHeight;
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.BevelOuter := bvNone;
  FButtons.ParentBackground := True;
  FButtons.Align := alRight;
  // alRight von rechts nach links: Kopieren, Zurücksetzen, Anhalten.
  FCopy := NewButton(TAtlasTextId.DiagnosticCopy, CopyClick);
  FReset := NewButton(TAtlasTextId.DiagReset, ResetClick);
  FPause := NewButton(TAtlasTextId.DiagPause, PauseClick);
  // alLeft in Reihenfolge der Left-Werte: Belegung, Verlauf, Schwelle, Hinweis.
  FBusy := NewLabel;
  FSpark := TAtlasBusySpark.Create(Self);
  FSpark.Parent := Self;
  FSpark.Align := alLeft;
  FSpark.AlignWithMargins := True;
  FSpark.Width := MulDiv(150, CurrentPPI, 96);
  FSpark.Left := MulDiv(400, CurrentPPI, 96);
  FThreshold := NewLabel;
  FThreshold.Left := MulDiv(600, CurrentPPI, 96);
  FNote := NewLabel;
  FNote.Left := MulDiv(800, CurrentPPI, 96);
  FNote.Font.Color := clGrayText;
  FButtonsWidth := FCopy.Width + FReset.Width + FPause.Width + 3 * (FCopy.Margins.Left + FCopy.Margins.Right);
  FButtons.Width := FButtonsWidth;
  Arrange;
end;

function TAtlasDiagnosticBar.RowHeight: Integer;
begin
  Result := MulDiv(32, CurrentPPI, 96);
end;

function TAtlasDiagnosticBar.InfoWidth: Integer;
var
  mControl: TControl;
begin
  Result := 0;
  for mControl in TArray<TControl>.Create(FBusy, FSpark, FThreshold, FNote) do
  begin
    // Ein leerer Hinweis braucht keinen Platz.
    if (mControl <> FNote) or (FNote.Caption <> '') then
    begin
      Inc(Result, mControl.Width + mControl.Margins.Left + mControl.Margins.Right);
    end;
  end;
end;

class function TAtlasDiagnosticBar.NeedsTwoRows(AInfoWidth, AButtonsWidth, AClientWidth: Integer): Boolean;
begin
  Result := (AClientWidth > 0) and (AInfoWidth + AButtonsWidth > AClientWidth);
end;

procedure TAtlasDiagnosticBar.Arrange;
var
  mTwoRows: Boolean;
begin
  if FArranging or (FButtons = nil) or not HandleAllocated then
  begin
    Exit;
  end;
  FArranging := True;
  try
    mTwoRows := NeedsTwoRows(InfoWidth, FButtonsWidth, ClientWidth);
    if mTwoRows then
    begin
      // Knöpfe rechtsbündig in der zweiten Zeile; die Angaben behalten die erste ganz.
      FButtons.Align := alBottom;
      FButtons.Height := RowHeight;
      Height := 2 * RowHeight;
    end
    else
    begin
      FButtons.Align := alRight;
      FButtons.Width := FButtonsWidth;
      Height := RowHeight;
    end;
  finally
    FArranging := False;
  end;
end;

procedure TAtlasDiagnosticBar.CreateWnd;
begin
  inherited;
  Arrange;
end;

procedure TAtlasDiagnosticBar.Resize;
begin
  inherited;
  Arrange;
end;

function TAtlasDiagnosticBar.NewButton(AId: TAtlasTextId; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FButtons;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(110, CurrentPPI, 96);
  Result.Caption := TAtlasStrings.Text(AId);
  Result.OnClick := AClick;
end;

function TAtlasDiagnosticBar.NewLabel: TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Layout := tlCenter;
end;

procedure TAtlasDiagnosticBar.SetSnapshot(const ASnapshot: TAtlasPluginSnapshot);
begin
  FSpark.SetValues(ASnapshot.Busy);
  FPaused := ASnapshot.Paused;
  FBusy.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagBusy, [Length(ASnapshot.Busy),
    TAtlasPluginRows.Percent(ASnapshot.BusyPercent)]);
  FThreshold.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagThreshold, [ASnapshot.ThresholdMs]);
  FPause.Caption := TAtlasStrings.Text(TAtlasTextId.DiagPause);
  if FPaused then
  begin
    FPause.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagResume);
  end;
  // Längere Angaben (Prozent, Sprache) können die zweite Zeile nötig machen.
  Arrange;
end;

procedure TAtlasDiagnosticBar.SetColors(const AColors: TAtlasColors);
begin
  FSpark.SetColors(AColors);
end;

procedure TAtlasDiagnosticBar.ShowNote(const AText: string);
begin
  FNote.Caption := AText;
  Arrange;
end;

procedure TAtlasDiagnosticBar.PauseClick(Sender: TObject);
begin
  if Assigned(FOnPause) then
  begin
    FOnPause(not FPaused);
  end;
end;

procedure TAtlasDiagnosticBar.ResetClick(Sender: TObject);
begin
  if Assigned(FOnReset) then
  begin
    FOnReset();
  end;
end;

procedure TAtlasDiagnosticBar.CopyClick(Sender: TObject);
begin
  if Assigned(FOnCopy) then
  begin
    FOnCopy();
  end;
end;

{ TAtlasTablePage }

constructor TAtlasTablePage.CreatePage(AOwner: TComponent; AWithHeader: Boolean);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  if AWithHeader then
  begin
    FHeader := TLabel.Create(Self);
    FHeader.Parent := Self;
    FHeader.Align := alTop;
    FHeader.AlignWithMargins := True;
    FHeader.ShowAccelChar := False;
  end;
  FGrid := TAtlasDiagnosticGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.EmptyText := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagEmpty);
end;

{ TAtlasFeatureMenu }

constructor TAtlasFeatureMenu.Create(AOwner: TComponent);
var
  mLine: TMenuItem;
begin
  inherited Create(AOwner);
  FOnly := NewItem;
  FAll := NewItem;
  FAll.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagMenuAll);
  FDisable := NewItem;
  mLine := NewItem;
  mLine.Caption := '-';
  FCopyRow := NewItem;
  FCopyRow.Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.DiagMenuCopyRow);
  Prepare('', False);
end;

function TAtlasFeatureMenu.NewItem: TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Items.Add(Result);
end;

procedure TAtlasFeatureMenu.Prepare(const AName: string; AFiltered: Boolean);
begin
  FOnly.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagMenuOnly, [AName]);
  FOnly.Visible := AName <> '';
  FAll.Visible := AFiltered;
  FDisable.Caption := TAtlasDiagnosticsStrings.Fmt(TAtlasDiagnosticsTextId.DiagMenuDisable, [AName]);
  FDisable.Visible := AName <> '';
  FCopyRow.Visible := AName <> '';
end;

end.
