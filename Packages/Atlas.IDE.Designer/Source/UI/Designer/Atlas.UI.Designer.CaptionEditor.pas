unit Atlas.UI.Designer.CaptionEditor;

// Eingabefeld für die Beschriftung direkt im Designer (#748): randloses
// Fenster genau über dem Text der Komponente, in deren Schrift, mit
// Akzentrahmen; mindestens so breit wie die Komponente, wächst beim Tippen.
//   ┌──────────────┐
//   │Name:|        │   Enter übernimmt, Esc verwirft, Tab/Umschalt+Tab
//   └──────────────┘   übernimmt und geht weiter, Strg+H: Text/TextHint.
// Umschalt+Enter fügt bei mehrzeiligen Captions einen Zeilenumbruch ein. Ein
// Klick daneben übernimmt. Tastenkürzel der IDE greifen während der Eingabe
// nicht (IsShortCut); Strg+A/C/X/V/Z bedient das Feld selbst.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Style.Palette;

type
  /// <summary>Wie die Eingabe endet: verworfen, übernommen, übernommen und weiter (vor, zurück), übernommen
  /// und Text/TextHint getauscht.</summary>
  TAtlasCaptionEnd = (Cancel, Commit, CommitNext, CommitBack, Toggle);

  TAtlasCaptionDone = reference to procedure(AEnd: TAtlasCaptionEnd; const AText: string);

  TAtlasCaptionEditor = class(TForm)
  private const
    cBorder = 2;
    cPadding = 12;
  private
    FMemo: TMemo;
    FOnDone: TAtlasCaptionDone;
    FOwnerWindow: HWND;
    FMultiLine: Boolean;
    FMinWidth: Integer;
    FMinHeight: Integer;
    FDone: Boolean;
    FPassChar: Boolean;
    procedure MemoKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var AKey: Char);
    procedure MemoChange(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
    procedure Finish(AEnd: TAtlasCaptionEnd);
    procedure Grow;
    procedure EditKey(AKey: Word);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    /// <summary>AOwnerWindow: Hauptfenster der IDE.</summary>
    constructor CreateEditor(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
    function IsShortCut(var Message: TWMKey): Boolean; override;
    /// <summary>Über AScreen (Bildschirm) öffnen; AOnDone meldet das Ende genau einmal.</summary>
    procedure Open(const AScreen: TRect; AFont: TFont; AAlignment: TAlignment; const AText: string;
      AMultiLine: Boolean; const AOnDone: TAtlasCaptionDone);
    procedure ApplyColors(const AColors: TAtlasColors);
    property Memo: TMemo read FMemo;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Designer.InlineCaption;

{ TAtlasCaptionEditor }

constructor TAtlasCaptionEditor.CreateEditor(AOwner: TComponent; AOwnerWindow: HWND; const AColors: TAtlasColors);
begin
  FOwnerWindow := AOwnerWindow;
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Padding.SetBounds(cBorder, cBorder, cBorder, cBorder);
  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.BorderStyle := bsNone;
  FMemo.WantReturns := True;
  FMemo.WantTabs := True;
  FMemo.WordWrap := False;
  FMemo.ScrollBars := ssNone;
  FMemo.OnKeyDown := MemoKeyDown;
  FMemo.OnKeyPress := MemoKeyPress;
  FMemo.OnChange := MemoChange;
  OnDeactivate := FormDeactivate;
  ApplyColors(AColors);
end;

procedure TAtlasCaptionEditor.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW;
  if FOwnerWindow <> 0 then
  begin
    Params.WndParent := FOwnerWindow;
  end;
end;

procedure TAtlasCaptionEditor.ApplyColors(const AColors: TAtlasColors);
begin
  Color := TColor(AColors.Accent);
  FMemo.Color := TColor(AColors.Surface);
end;

procedure TAtlasCaptionEditor.Open(const AScreen: TRect; AFont: TFont; AAlignment: TAlignment; const AText: string;
  AMultiLine: Boolean; const AOnDone: TAtlasCaptionDone);
begin
  FOnDone := AOnDone;
  FDone := False;
  FPassChar := False;
  FMultiLine := AMultiLine;
  if AFont <> nil then
  begin
    FMemo.Font.Assign(AFont);
  end;
  FMemo.Alignment := AAlignment;
  FMemo.OnChange := nil;
  FMemo.Text := AText;
  FMemo.OnChange := MemoChange;
  FMinWidth := AScreen.Width + 2 * cBorder;
  FMinHeight := AScreen.Height + 2 * cBorder;
  SetBounds(AScreen.Left - cBorder, AScreen.Top - cBorder, FMinWidth, FMinHeight);
  Grow;
  Show;
  FMemo.SetFocus;
  FMemo.SelectAll;
end;

procedure TAtlasCaptionEditor.Grow;
var
  mBitmap: TBitmap;
  mLine: string;
  mWidest, mLines: Integer;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(FMemo.Font);
    mWidest := 0;
    mLines := 0;
    for mLine in FMemo.Lines do
    begin
      mWidest := Max(mWidest, mBitmap.Canvas.TextWidth(mLine));
      Inc(mLines);
    end;
    ClientWidth := TAtlasInlineCaption.EditorWidth(FMinWidth, mWidest, MulDiv(cPadding, CurrentPPI, 96) +
      2 * cBorder);
    ClientHeight := Max(FMinHeight, Max(1, mLines) * mBitmap.Canvas.TextHeight('Ag') + 2 * cBorder + 2);
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasCaptionEditor.MemoChange(Sender: TObject);
begin
  Grow;
end;

procedure TAtlasCaptionEditor.Finish(AEnd: TAtlasCaptionEnd);
var
  mDone: TAtlasCaptionDone;
begin
  if FDone then
  begin
    Exit;
  end;
  FDone := True;
  mDone := FOnDone;
  FOnDone := nil;
  Hide;
  if Assigned(mDone) then
  begin
    mDone(AEnd, FMemo.Text);
  end;
end;

procedure TAtlasCaptionEditor.FormDeactivate(Sender: TObject);
begin
  Finish(TAtlasCaptionEnd.Commit);
end;

procedure TAtlasCaptionEditor.MemoKeyDown(Sender: TObject; var AKey: Word; AShift: TShiftState);
begin
  FPassChar := False;
  case AKey of
    VK_RETURN:
      if (ssShift in AShift) and FMultiLine then
      begin
        FPassChar := True;
      end
      else
      begin
        AKey := 0;
        Finish(TAtlasCaptionEnd.Commit);
      end;
    VK_ESCAPE:
      begin
        AKey := 0;
        Finish(TAtlasCaptionEnd.Cancel);
      end;
    VK_TAB:
      begin
        AKey := 0;
        if ssShift in AShift then
        begin
          Finish(TAtlasCaptionEnd.CommitBack);
        end
        else
        begin
          Finish(TAtlasCaptionEnd.CommitNext);
        end;
      end;
  end;
end;

procedure TAtlasCaptionEditor.MemoKeyPress(Sender: TObject; var AKey: Char);
begin
  if CharInSet(AKey, [#9, #13, #27]) and not FPassChar then
  begin
    AKey := #0;
  end;
  FPassChar := False;
end;

procedure TAtlasCaptionEditor.EditKey(AKey: Word);
begin
  case AKey of
    Ord('A'):
      FMemo.SelectAll;
    Ord('C'):
      FMemo.CopyToClipboard;
    Ord('X'):
      FMemo.CutToClipboard;
    Ord('V'):
      FMemo.PasteFromClipboard;
    Ord('Z'):
      FMemo.Undo;
    Ord('H'):
      Finish(TAtlasCaptionEnd.Toggle);
  end;
end;

function TAtlasCaptionEditor.IsShortCut(var Message: TWMKey): Boolean;
var
  mShift: TShiftState;
begin
  // Strg allein und Alt allein gehören hier dem Feld, nicht den Aktionen der IDE. Strg+Alt (AltGr) bleibt
  // frei für Zeichen wie @ oder €, Strg mit Pfeil-, Pos1-, Ende-, Rück- und Entf-Taste für das Feld.
  mShift := KeyDataToShiftState(Message.KeyData);
  Result := False;
  if (ssCtrl in mShift) and (ssAlt in mShift) then
  begin
    Exit;
  end;
  if (ssCtrl in mShift) and not (Message.CharCode in [VK_BACK, VK_END .. VK_DOWN, VK_DELETE]) then
  begin
    Result := True;
    EditKey(Message.CharCode);
  end
  else if ssAlt in mShift then
  begin
    Result := True;
  end;
end;

end.
