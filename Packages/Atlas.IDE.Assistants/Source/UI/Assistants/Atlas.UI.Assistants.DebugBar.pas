unit Atlas.UI.Assistants.DebugBar;

// Leiste im Editorfenster, solange ein KI-Assistent den Debugger steuert (#1874): links, wer debuggt, wie viele
// Aufträge und das letzte Werkzeug; rechts „Pause für KI“ (bzw. „Fortsetzen“) und „Übernehmen“. Gezeichnet wie die
// übrigen Editorleisten (TAtlasEditorBar: Höhe nach DPI, Klick beim Loslassen, Tooltips). Texte und Klicks setzt
// die IDE-Schicht (Atlas.IDE.Assistants.DebugBar).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Atlas.UI.Editor.Bar;

type
  {$SCOPEDENUMS ON}
  /// <summary>Knöpfe der Leiste; der Wert ist der Teil (PartAt).</summary>
  TAtlasAssistantDebugButton = (Pause, TakeOver);
  {$SCOPEDENUMS OFF}

  /// <summary>Inhalt der Leiste.</summary>
  TAtlasAssistantDebugView = record
    Text: string;
    PauseCaption: string;
    PauseHint: string;
    TakeOverCaption: string;
    TakeOverHint: string;
    /// <summary>Ohne eigene Sitzung des Assistenten gibt es nichts zu übernehmen.</summary>
    CanTakeOver: Boolean;
  end;

  TAtlasAssistantDebugBar = class(TAtlasEditorBar)
  private
    FView: TAtlasAssistantDebugView;
    FButtons: array[TAtlasAssistantDebugButton] of TRect;
    FOnButton: TProc<TAtlasAssistantDebugButton>;
    procedure Layout;
    function Caption(AButton: TAtlasAssistantDebugButton): string;
    function Shown(AButton: TAtlasAssistantDebugButton): Boolean;
  protected
    function PartAt(AX, AY: Integer): Integer; override;
    function PartHint(APart: Integer): string; override;
    procedure PartClicked(APart: Integer; AShift: TShiftState; AX, AY: Integer); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    procedure SetView(const AView: TAtlasAssistantDebugView);
    /// <summary>Fläche eines Knopfs (Client); leer, wenn er fehlt.</summary>
    function ButtonRect(AButton: TAtlasAssistantDebugButton): TRect;
    /// <summary>Wie ein Klick auf den Knopf am Punkt (Client): meldet OnButton, wenn dort einer ist.</summary>
    procedure ClickAt(AX, AY: Integer);
    property View: TAtlasAssistantDebugView read FView;
    property OnButton: TProc<TAtlasAssistantDebugButton> read FOnButton write FOnButton;
  end;

implementation

uses
  Vcl.Graphics;

const
  cPad = 8;
  cGap = 6;
  cInset = 3;

{ TAtlasAssistantDebugBar }

function TAtlasAssistantDebugBar.Caption(AButton: TAtlasAssistantDebugButton): string;
begin
  if AButton = TAtlasAssistantDebugButton.Pause then
  begin
    Exit(FView.PauseCaption);
  end;
  Result := FView.TakeOverCaption;
end;

function TAtlasAssistantDebugBar.Shown(AButton: TAtlasAssistantDebugButton): Boolean;
begin
  Result := (AButton = TAtlasAssistantDebugButton.Pause) or FView.CanTakeOver;
end;

procedure TAtlasAssistantDebugBar.Layout;
var
  mButton: TAtlasAssistantDebugButton;
  mRight, mWidth: Integer;
begin
  // Text messen braucht ein Fenster; Resize und Paint holen es nach.
  if not HandleAllocated then
  begin
    Exit;
  end;
  Canvas.Font := Font;
  mRight := ClientWidth - Scale(cPad);
  for mButton := High(TAtlasAssistantDebugButton) downto Low(TAtlasAssistantDebugButton) do
  begin
    FButtons[mButton] := TRect.Empty;
    if not Shown(mButton) then
    begin
      Continue;
    end;
    mWidth := Canvas.TextWidth(Caption(mButton)) + Scale(2 * cPad);
    FButtons[mButton] := Rect(mRight - mWidth, Scale(cInset), mRight, ClientHeight - Scale(cInset));
    mRight := mRight - mWidth - Scale(cGap);
  end;
end;

procedure TAtlasAssistantDebugBar.SetView(const AView: TAtlasAssistantDebugView);
begin
  FView := AView;
  Layout;
  Invalidate;
end;

function TAtlasAssistantDebugBar.ButtonRect(AButton: TAtlasAssistantDebugButton): TRect;
begin
  Result := FButtons[AButton];
end;

procedure TAtlasAssistantDebugBar.ClickAt(AX, AY: Integer);
begin
  PartClicked(PartAt(AX, AY), [], AX, AY);
end;

procedure TAtlasAssistantDebugBar.Resize;
begin
  inherited Resize;
  Layout;
end;

function TAtlasAssistantDebugBar.PartAt(AX, AY: Integer): Integer;
var
  mButton: TAtlasAssistantDebugButton;
begin
  for mButton := Low(TAtlasAssistantDebugButton) to High(TAtlasAssistantDebugButton) do
  begin
    if not FButtons[mButton].IsEmpty and FButtons[mButton].Contains(Point(AX, AY)) then
    begin
      Exit(Ord(mButton));
    end;
  end;
  Result := cPartNone;
end;

function TAtlasAssistantDebugBar.PartHint(APart: Integer): string;
begin
  case APart of
    Ord(TAtlasAssistantDebugButton.Pause):
      Result := FView.PauseHint;
    Ord(TAtlasAssistantDebugButton.TakeOver):
      Result := FView.TakeOverHint;
  else
    Result := FView.Text;
  end;
end;

procedure TAtlasAssistantDebugBar.PartClicked(APart: Integer; AShift: TShiftState; AX, AY: Integer);
begin
  if (APart < Ord(Low(TAtlasAssistantDebugButton))) or (APart > Ord(High(TAtlasAssistantDebugButton))) or
    not Assigned(FOnButton) then
  begin
    Exit;
  end;
  FOnButton(TAtlasAssistantDebugButton(APart));
end;

procedure TAtlasAssistantDebugBar.Paint;
var
  mButton: TAtlasAssistantDebugButton;
  mRect: TRect;
  mText: string;
  mY, mRight: Integer;
begin
  Layout;
  PaintChrome(True);
  Canvas.Font := Font;
  mY := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  mRight := ClientWidth;
  for mButton := Low(TAtlasAssistantDebugButton) to High(TAtlasAssistantDebugButton) do
  begin
    mRect := FButtons[mButton];
    if mRect.IsEmpty then
    begin
      Continue;
    end;
    if mRect.Left < mRight then
    begin
      mRight := mRect.Left;
    end;
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Color := TColor(Colors.Line);
    Canvas.Brush.Color := TColor(Colors.Surface);
    if Hot = Ord(mButton) then
    begin
      Canvas.Brush.Color := TColor(Colors.AccentSoft);
    end;
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, Scale(4), Scale(4));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(Colors.Text);
    mText := Caption(mButton);
    Canvas.TextOut(mRect.Left + (mRect.Width - Canvas.TextWidth(mText)) div 2, mY, mText);
  end;
  // Text links, vor den Knöpfen abgeschnitten.
  mRect := Rect(Scale(cPad), 0, mRight - Scale(cGap), ClientHeight);
  if mRect.Right > mRect.Left then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := TColor(Colors.Accent);
    mText := FView.Text;
    Canvas.TextRect(mRect, mText, [tfSingleLine, tfVerticalCenter, tfEndEllipsis, tfNoPrefix]);
  end;
end;

end.
