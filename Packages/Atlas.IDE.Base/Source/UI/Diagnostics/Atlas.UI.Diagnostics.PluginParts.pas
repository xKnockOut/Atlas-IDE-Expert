unit Atlas.UI.Diagnostics.PluginParts;

// Teile des Diagnose-Fensters, reine VCL:
// - TAtlasDiagnosticTabs: gezeichnete Reiterleiste (braucht vor dem Zeigen
//   kein Fenster, anders als TTabControl.Tabs).
// - TAtlasDiagnosticBar: Belegung des Hauptthreads (Verlauf der letzten 60 s
//   und Mittel), Schwelle, Anhalten/Weiter, Zurücksetzen, Bericht kopieren und
//   ein kurzer Hinweis.
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
  Atlas.Core.Style.Color,
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

  TAtlasDiagnosticBar = class(TPanel)
  private
    FSpark: TPaintBox;
    FBusy: TLabel;
    FThreshold: TLabel;
    FPause: TButton;
    FReset: TButton;
    FCopy: TButton;
    FNote: TLabel;
    FColors: TAtlasColors;
    FValues: TArray<Double>;
    FPaused: Boolean;
    FOnPause: TProc<Boolean>;
    FOnReset: TProc;
    FOnCopy: TProc;
    function NewButton(AId: TAtlasTextId; AClick: TNotifyEvent): TButton;
    function NewLabel: TLabel;
    procedure SparkPaint(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetSnapshot(const ASnapshot: TAtlasPluginSnapshot);
    procedure SetColors(const AColors: TAtlasColors);
    procedure ShowNote(const AText: string);
    property Busy: TLabel read FBusy;
    property Threshold: TLabel read FThreshold;
    property Note: TLabel read FNote;
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
      Result := TAtlasStrings.Text(TAtlasTextId.DiagTabMainThread);
    TAtlasDiagnosticPage.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.DiagTabServer);
    TAtlasDiagnosticPage.Background:
      Result := TAtlasStrings.Text(TAtlasTextId.DiagTabBackground);
    TAtlasDiagnosticPage.Hangs:
      Result := TAtlasStrings.Text(TAtlasTextId.DiagTabHangs);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.DiagTabCompletion);
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

{ TAtlasDiagnosticBar }

constructor TAtlasDiagnosticBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  Height := MulDiv(32, CurrentPPI, 96);
  FColors := TAtlasColors.Light;
  // alRight von rechts nach links: Kopieren, Zurücksetzen, Anhalten.
  FCopy := NewButton(TAtlasTextId.DiagnosticCopy, CopyClick);
  FReset := NewButton(TAtlasTextId.DiagReset, ResetClick);
  FPause := NewButton(TAtlasTextId.DiagPause, PauseClick);
  // alLeft in Reihenfolge der Left-Werte: Belegung, Verlauf, Schwelle, Hinweis.
  FBusy := NewLabel;
  FSpark := TPaintBox.Create(Self);
  FSpark.Parent := Self;
  FSpark.Align := alLeft;
  FSpark.AlignWithMargins := True;
  FSpark.Width := MulDiv(150, CurrentPPI, 96);
  FSpark.Left := MulDiv(400, CurrentPPI, 96);
  FSpark.OnPaint := SparkPaint;
  FThreshold := NewLabel;
  FThreshold.Left := MulDiv(600, CurrentPPI, 96);
  FNote := NewLabel;
  FNote.Left := MulDiv(800, CurrentPPI, 96);
  FNote.Font.Color := clGrayText;
end;

function TAtlasDiagnosticBar.NewButton(AId: TAtlasTextId; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
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
  FValues := ASnapshot.Busy;
  FPaused := ASnapshot.Paused;
  FBusy.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagBusy, [Length(ASnapshot.Busy),
    TAtlasPluginRows.Percent(ASnapshot.BusyPercent)]);
  FThreshold.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagThreshold, [ASnapshot.ThresholdMs]);
  FPause.Caption := TAtlasStrings.Text(TAtlasTextId.DiagPause);
  if FPaused then
  begin
    FPause.Caption := TAtlasStrings.Text(TAtlasTextId.DiagResume);
  end;
  FSpark.Invalidate;
end;

procedure TAtlasDiagnosticBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FSpark.Invalidate;
end;

procedure TAtlasDiagnosticBar.ShowNote(const AText: string);
begin
  FNote.Caption := AText;
end;

procedure TAtlasDiagnosticBar.SparkPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mIndex, mX, mY, mCount, mSeconds: Integer;
begin
  mCanvas := FSpark.Canvas;
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Brush.Color := ToColor(FColors.Surface);
  mCanvas.FillRect(FSpark.ClientRect);
  mCount := Length(FValues);
  if mCount = 0 then
  begin
    Exit;
  end;
  // Immer 60 Sekunden breit, neueste rechts; 0 % unten, 100 % oben.
  mSeconds := TAtlasBusyMeter.cSeconds;
  mCanvas.Pen.Color := ToColor(FColors.Accent);
  for mIndex := 0 to mCount - 1 do
  begin
    mX := MulDiv(mSeconds - mCount + mIndex, FSpark.Width - 1, mSeconds - 1);
    mY := FSpark.Height - 2 - Round(FValues[mIndex] * (FSpark.Height - 4) / 100);
    if mIndex = 0 then
    begin
      mCanvas.MoveTo(mX, mY);
    end
    else
    begin
      mCanvas.LineTo(mX, mY);
    end;
  end;
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
  FGrid.EmptyText := TAtlasStrings.Text(TAtlasTextId.DiagEmpty);
end;

{ TAtlasFeatureMenu }

constructor TAtlasFeatureMenu.Create(AOwner: TComponent);
var
  mLine: TMenuItem;
begin
  inherited Create(AOwner);
  FOnly := NewItem;
  FAll := NewItem;
  FAll.Caption := TAtlasStrings.Text(TAtlasTextId.DiagMenuAll);
  FDisable := NewItem;
  mLine := NewItem;
  mLine.Caption := '-';
  FCopyRow := NewItem;
  FCopyRow.Caption := TAtlasStrings.Text(TAtlasTextId.DiagMenuCopyRow);
  Prepare('', False);
end;

function TAtlasFeatureMenu.NewItem: TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Items.Add(Result);
end;

procedure TAtlasFeatureMenu.Prepare(const AName: string; AFiltered: Boolean);
begin
  FOnly.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagMenuOnly, [AName]);
  FOnly.Visible := AName <> '';
  FAll.Visible := AFiltered;
  FDisable.Caption := TAtlasStrings.Fmt(TAtlasTextId.DiagMenuDisable, [AName]);
  FDisable.Visible := AName <> '';
  FCopyRow.Visible := AName <> '';
end;

end.
