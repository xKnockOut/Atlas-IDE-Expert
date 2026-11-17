unit Atlas.UI.Foundation.Dialog;

// Gemeinsame Basis der im Code gebauten Atlas-Dialoge (#2062). Vorher setzte
// jeder der 61 Dialoge Rahmen, Position, Schrift und Breite selbst, baute
// eigene Knopf-Helfer (46 Units) und färbte Fehlertexte mit clRed; 36 Dialoge
// bekamen nie das Thema der IDE. TAtlasDialog bringt mit:
// - CreateDialog: CreateNew, bsDialog, poMainFormCenter, Dialogschrift aus
//   TAtlasUiTheme, Breite in logischen Pixeln (96 dpi), Abo beim Themendienst.
//   Das Fenster entsteht nur, wenn eine Breite übergeben wird (ClientWidth
//   braucht es); sonst erst mit dem Dialog selbst. Nachfahren mit eigenem
//   CreateWnd, Resize oder CreateParams sehen dann ein fertiges Objekt;
// - DoShow: IDE-Thema an der Wurzel (Kinder erben den Stil), ThemeChanged bei
//   jedem Wechsel, solange der Dialog lebt; Abmelden im Destroy;
// - AddRow, AddLabel, AddButtonRow, AddNote: Zeilen von oben nach unten,
//   Größen in logischen Pixeln, skaliert über das Formular;
// - FitHeight: Höhe bis unter das letzte Element;
// - AllowResize: Rahmen ziehbar, die gebaute Größe ist die kleinste; eine
//   Zeile (Liste, Textfeld) nimmt zusätzliche Höhe, alles darunter bleibt
//   unten. Felder, die mitwachsen sollen, verankert der Dialog rechts
//   (FitRight).
// TAtlasButtonRow misst die Knöpfe nach ihrem Text, TAtlasNoteLabel zeigt
// Hinweise in der Textfarbe der Palette (Fehler, Warnung, Ok); Hinweise ohne
// Aussage zeichnet der Stil. Eigene Farben holt ein Dialog in ThemeChanged.
// TAtlasPopupForm ist die Basis der selbst gezeichneten Fenster, die anders
// als TAtlasPopupWindow den Fokus nehmen (Erzeugen-Menü, Unit-Suche,
// Befehlspalette, Komponentensuche, Statusfeld, Schnellschalter,
// Benachrichtigungen, Beschriftung im Designer): ohne Rahmen, mit Schatten
// und Dialogschrift, Farben aus TAtlasUiTheme, ohne Fenster im Konstruktor.
// Rahmenlose Fenster gehören hierher, nicht auf TAtlasDialog mit bsNone.
// Es setzt keinen VCL-Stil (das Fenster zeichnet alles selbst und behandelt
// seinen Rand teils selbst), folgt aber jedem Themenwechsel mit neuen Farben.
// Mit ThemedControls bekommen Knöpfe und Auswahllisten im Fenster das
// IDE-Thema wie in einem Dialog (vor dem Zeigen und bei jedem Wechsel).
// Mit Rounded rundet ab Windows 11 der Fenstermanager die Ecken und zeichnet
// den Rand in der Akzentfarbe (ältere Systeme übergehen beides).

interface

uses
  System.Types,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal;

type
{$SCOPEDENUMS ON}
  /// <summary>Rolle eines Knopfs: normal, Vorgabe (Eingabetaste) oder Abbrechen (Esc, mrCancel).</summary>
  TAtlasButtonKind = (Plain, Default, Cancel);
{$SCOPEDENUMS OFF}

  /// <summary>Knopfleiste eines Dialogs; Knöpfe von links nach rechts, Breite nach Text.</summary>
  TAtlasButtonRow = class(TFlowPanel)
  public const
    /// <summary>Mindestbreite und Rand rechts und links des Texts, logische Pixel.</summary>
    cButtonMinWidth = 75;
    cButtonPadding = 32;
    cButtonGap = 8;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Knopf anfügen; Breite aus dem Text in der Schrift der Leiste.</summary>
    function AddButton(const ACaption: string; AKind: TAtlasButtonKind): TButton; overload;
    /// <summary>Normalen Knopf anfügen.</summary>
    function AddButton(const ACaption: string): TButton; overload;
    /// <summary>Breite eines Knopfs mit ACaption in Gerätepixeln.</summary>
    function ButtonWidth(const ACaption: string): Integer;
  end;

  /// <summary>Hinweis- oder Fehlerzeile eines Dialogs in der Textfarbe der Palette; folgt dem Thema.</summary>
  TAtlasNoteLabel = class(TLabel)
  private
    FKind: TAtlasSignalKind;
    procedure ApplyKind;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Text und Bedeutung setzen; leerer Text leert die Zeile.</summary>
    procedure ShowNote(const AText: string; AKind: TAtlasSignalKind);
    property Kind: TAtlasSignalKind read FKind;
  end;

  TAtlasDialog = class(TForm)
  public const
    /// <summary>Abstand am Rand und zwischen Zeilen, logische Pixel.</summary>
    cRowGap = 8;
    /// <summary>Abstand einer Beschriftung vom oberen Rand ihrer Zeile, logische Pixel.</summary>
    cRowLabelTop = 4;
    /// <summary>Höchstens dieser Anteil (Prozent) der Arbeitsfläche als Anfangsgröße eines Dialogs.</summary>
    cMaxScreenShare = 80;
  private
    procedure HandleThemeChanged;
  protected
    /// <summary>Thema anwenden, bevor das Fenster sichtbar wird: Das IDE-Thema setzt StyleName und erzeugt das
    /// Fenster neu; mitten im Anzeigen (DoShow) bricht die VCL das mit einem Fehler ab.</summary>
    procedure VisibleChanging; override;
    /// <summary>Thema der IDE hat gewechselt (nach dem Anwenden an der Wurzel): eigene Farben neu holen.</summary>
    procedure ThemeChanged; virtual;
    /// <summary>Oberkante unter dem bisher untersten Element (alTop stapelt nach Top).</summary>
    function NextTop: Integer;
  public
    /// <summary>Breite von AText in AFont, Gerätepixel (Font.Height ist schon in Gerätepixeln des Steuerelements).
    /// </summary>
    class function TextWidth(AFont: TFont; const AText: string): Integer; static;
    /// <summary>Arbeitsfläche des Monitors, auf dem das Hauptfenster liegt; ohne Hauptfenster die des
    /// Hauptmonitors. Dialoge erscheinen über dem Hauptfenster (poMainFormCenter), dessen Monitor begrenzt ihre
    /// Größe.</summary>
    class function MainFormWorkArea: TRect; static;
    /// <summary>Größte Anfangsgröße eines Dialogs: cMaxScreenShare Prozent der Arbeitsfläche aus MainFormWorkArea,
    /// Gerätepixel.</summary>
    class function MaxInitialSize: TSize; static;
    /// <summary>Leeren Dialog mit Titel ACaption und Innenbreite AWidth96 (logische Pixel) anlegen. Mit 0 setzt
    /// der Dialog die Breite selbst; das Fenster entsteht dann noch nicht im Konstruktor.</summary>
    constructor CreateDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer);
    destructor Destroy; override;
    /// <summary>Zeile ohne Rahmen mit Höhe AHeight96 (logische Pixel) unter dem bisher Untersten.</summary>
    function AddRow(AHeight96: Integer): TPanel;
    /// <summary>Beschriftung links in AParent.</summary>
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    /// <summary>Knopfleiste unter dem bisher Untersten.</summary>
    function AddButtonRow: TAtlasButtonRow;
    /// <summary>Hinweiszeile mit Höhe AHeight96 (logische Pixel) unter dem bisher Untersten; anfangs leer.</summary>
    function AddNote(AHeight96: Integer): TAtlasNoteLabel;
    /// <summary>Innenhöhe bis unter das unterste Element plus Rand.</summary>
    procedure FitHeight;
    /// <summary>Größe ziehbar machen, nachdem alles gebaut ist: Rahmen bsSizeable, die jetzige Größe ist die
    /// kleinste. AGrow (direktes Kind, alTop) nimmt zusätzliche Höhe auf, die alTop-Elemente darunter bleiben
    /// am unteren Rand; ohne AGrow (nil) nur breiter. In frei gesetzten Dialogen (alNone) wird AGrow unten
    /// verankert und alles darunter vom oberen an den unteren Rand umgehängt.</summary>
    procedure AllowResize(AGrow: TControl);
    /// <summary>AControl wächst mit der Breite seiner Zeile: rechter Rand wie der linke Abstand zur Zeile, oder
    /// bündig, wenn es links bei 0 steht.</summary>
    procedure FitRight(AControl: TControl);
  end;

  /// <summary>Selbst gezeichnetes Fenster ohne Rahmen, das den Fokus nimmt; Farben folgen dem IDE-Thema.</summary>
  TAtlasPopupForm = class(TForm)
  private
    FColors: TAtlasColors;
    FRounded: Boolean;
    FThemedControls: Boolean;
    procedure HandleThemeChanged;
    /// <summary>Runde Ecken und Rand in der Akzentfarbe beim Fenstermanager setzen (nur mit Rounded und Fenster).
    /// </summary>
    procedure ApplyFrame;
  protected
    /// <summary>Schatten wie die Popups (CS_DROPSHADOW).</summary>
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    /// <summary>Mit ThemedControls das IDE-Thema anwenden, bevor das Fenster sichtbar wird (wie TAtlasDialog).
    /// </summary>
    procedure VisibleChanging; override;
    /// <summary>Thema der IDE hat gewechselt, Colors und Color sind neu gesetzt; danach wird neu gezeichnet.
    /// </summary>
    procedure ColorsChanged; virtual;
  public
    /// <summary>Leeres Fenster ohne Rahmen in den Farben AColors (bis zum nächsten Themenwechsel).</summary>
    constructor CreatePopup(AOwner: TComponent; const AColors: TAtlasColors);
    destructor Destroy; override;
    property Colors: TAtlasColors read FColors;
    /// <summary>Ecken rund und Rand in der Akzentfarbe vom Fenstermanager (ab Windows 11); vor dem Zeigen setzen.
    /// </summary>
    property Rounded: Boolean read FRounded write FRounded;
    /// <summary>VCL-Steuerelemente im Fenster (Knöpfe, Auswahllisten) bekommen das IDE-Thema, vor dem Zeigen und
    /// bei jedem Wechsel; ohne bleibt das Fenster beim VCL-Stil außen vor. Vor dem Zeigen setzen.</summary>
    property ThemedControls: Boolean read FThemedControls write FThemedControls;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Dwmapi,
  System.Math,
  Atlas.UI.Foundation.Theme;

{ TAtlasButtonRow }

constructor TAtlasButtonRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alTop;
  AutoSize := True;
  BevelOuter := bvNone;
  Caption := '';
  AlignWithMargins := True;
end;

function TAtlasButtonRow.AddButton(const ACaption: string; AKind: TAtlasButtonKind): TButton;
begin
  Result := TButton.Create(Owner);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Width := ButtonWidth(ACaption);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, ScaleValue(cButtonGap), ScaleValue(cButtonGap div 2));
  Result.Default := AKind = TAtlasButtonKind.Default;
  Result.Cancel := AKind = TAtlasButtonKind.Cancel;
  if Result.Cancel then
  begin
    Result.ModalResult := mrCancel;
  end;
end;

function TAtlasButtonRow.AddButton(const ACaption: string): TButton;
begin
  Result := AddButton(ACaption, TAtlasButtonKind.Plain);
end;

function TAtlasButtonRow.ButtonWidth(const ACaption: string): Integer;
begin
  Result := TAtlasDialog.TextWidth(Font, ACaption) + ScaleValue(cButtonPadding);
  if Result < ScaleValue(cButtonMinWidth) then
  begin
    Result := ScaleValue(cButtonMinWidth);
  end;
end;

{ TAtlasNoteLabel }

constructor TAtlasNoteLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := TAtlasSignalKind.Info;
  Caption := '';
  WordWrap := True;
  TAtlasUiTheme.Subscribe(Self,
    procedure
    begin
      ApplyKind;
    end);
end;

destructor TAtlasNoteLabel.Destroy;
begin
  TAtlasUiTheme.Unsubscribe(Self);
  inherited;
end;

procedure TAtlasNoteLabel.ApplyKind;
begin
  // Mit seFont zeichnet der VCL-Stil die Schrift in seiner Textfarbe und übergeht Font.Color.
  if TAtlasUiTheme.UsesStyleText(FKind) then
  begin
    StyleElements := StyleElements + [seFont];
  end
  else
  begin
    StyleElements := StyleElements - [seFont];
  end;
  Font.Color := TAtlasUiTheme.TextColor(FKind);
end;

procedure TAtlasNoteLabel.ShowNote(const AText: string; AKind: TAtlasSignalKind);
begin
  FKind := AKind;
  ApplyKind;
  Caption := AText;
end;

{ TAtlasDialog }

constructor TAtlasDialog.CreateDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer);
begin
  inherited CreateNew(AOwner);
  Caption := ACaption;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  TAtlasUiTheme.AssignDialogFont(Font);
  // ClientWidth legt das Fenster an: nur, wenn der Dialog die Breite wirklich hier setzen lässt.
  if AWidth96 > 0 then
  begin
    ClientWidth := ScaleValue(AWidth96);
  end;
  TAtlasUiTheme.Subscribe(Self,
    procedure
    begin
      HandleThemeChanged;
    end);
end;

destructor TAtlasDialog.Destroy;
begin
  TAtlasUiTheme.Unsubscribe(Self);
  inherited;
end;

class function TAtlasDialog.TextWidth(AFont: TFont; const AText: string): Integer;
var
  mBitmap: Vcl.Graphics.TBitmap;
begin
  // Ausdrücklich die Klasse: Winapi.Windows steht hinter Vcl.Graphics und hat einen Record TBitmap.
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(AFont);
    Result := mBitmap.Canvas.TextWidth(AText);
  finally
    mBitmap.Free;
  end;
end;

class function TAtlasDialog.MainFormWorkArea: TRect;
begin
  Result := Screen.WorkAreaRect;
  if (Application.MainForm <> nil) and (Application.MainForm.Monitor <> nil) then
  begin
    Result := Application.MainForm.Monitor.WorkareaRect;
  end;
end;

class function TAtlasDialog.MaxInitialSize: TSize;
var
  mArea: TRect;
begin
  mArea := MainFormWorkArea;
  Result := TSize.Create(mArea.Width * cMaxScreenShare div 100, mArea.Height * cMaxScreenShare div 100);
end;

procedure TAtlasDialog.VisibleChanging;
begin
  if not Visible then
  begin
    TAtlasUiTheme.Apply(Self);
  end;
  inherited;
end;

procedure TAtlasDialog.HandleThemeChanged;
begin
  TAtlasUiTheme.Apply(Self);
  ThemeChanged;
end;

procedure TAtlasDialog.ThemeChanged;
begin
end;

function TAtlasDialog.NextTop: Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to ControlCount - 1 do
  begin
    if Controls[mIndex].Top + Controls[mIndex].Height + 1 > Result then
    begin
      Result := Controls[mIndex].Top + Controls[mIndex].Height + 1;
    end;
  end;
end;

function TAtlasDialog.AddRow(AHeight96: Integer): TPanel;
var
  mTop: Integer;
begin
  mTop := NextTop;
  Result := TPanel.Create(Self);
  // Lage vor Align und Parent: Sonst ordnet die VCL alTop-Zeilen beim Anlegen des Fensters nach der
  // vorläufigen Lage und kann die Reihenfolge vertauschen.
  Result.Top := mTop;
  Result.Height := ScaleValue(AHeight96);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap div 2), ScaleValue(cRowGap), 0);
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Align := alTop;
  Result.Parent := Self;
end;

function TAtlasDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := 0;
  Result.Top := ScaleValue(cRowLabelTop);
end;

function TAtlasDialog.AddButtonRow: TAtlasButtonRow;
var
  mTop: Integer;
begin
  mTop := NextTop;
  Result := TAtlasButtonRow.Create(Self);
  Result.Parent := Self;
  Result.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap));
  Result.Top := mTop;
end;

function TAtlasDialog.AddNote(AHeight96: Integer): TAtlasNoteLabel;
var
  mRow: TPanel;
begin
  mRow := AddRow(AHeight96);
  Result := TAtlasNoteLabel.Create(Self);
  Result.Parent := mRow;
  Result.Align := alClient;
end;

procedure TAtlasDialog.FitHeight;
begin
  ClientHeight := NextTop + ScaleValue(cRowGap);
end;

procedure TAtlasDialog.AllowResize(AGrow: TControl);
var
  mIndex, mClientWidth, mClientHeight: Integer;
  mControl: TControl;
begin
  mClientWidth := ClientWidth;
  mClientHeight := ClientHeight;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  // Der breitere Rahmen nimmt sonst Platz vom Inhalt.
  ClientWidth := mClientWidth;
  ClientHeight := mClientHeight;
  Constraints.MinWidth := Width;
  Constraints.MinHeight := Height;
  if AGrow = nil then
  begin
    Constraints.MaxHeight := Height;
    Exit;
  end;
  DisableAlign;
  try
    for mIndex := 0 to ControlCount - 1 do
    begin
      mControl := Controls[mIndex];
      if (mControl = AGrow) or (mControl.Top <= AGrow.Top) then
      begin
        Continue;
      end;
      if mControl.Align = alTop then
      begin
        mControl.Align := alBottom;
      end
      else if mControl.Align = alNone then
      begin
        // Frei gesetzte Dialoge: am unteren Rand verankern statt oben.
        mControl.Anchors := mControl.Anchors - [akTop] + [akBottom];
      end;
    end;
    if AGrow.Align = alTop then
    begin
      AGrow.Align := alClient;
    end
    else if AGrow.Align = alNone then
    begin
      AGrow.Anchors := AGrow.Anchors + [akBottom];
    end;
  finally
    EnableAlign;
  end;
end;

procedure TAtlasDialog.FitRight(AControl: TControl);
var
  mParent: TWinControl;
begin
  mParent := AControl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  // Ohne Fenster ordnet die VCL die Zeilen nicht an, ihre Breite wäre die vorläufige.
  HandleNeeded;
  AControl.Width := mParent.ClientWidth - AControl.Left - Min(AControl.Left, ScaleValue(cRowGap));
  AControl.Anchors := [akLeft, akTop, akRight];
end;

const
  // Ab Windows 11; in älteren Winapi.Dwmapi nicht deklariert, ältere Systeme übergehen die Attribute.
  cDwmCornerPreference = 33;
  cDwmBorderColor = 34;
  cDwmRoundCorners = 2;

{ TAtlasPopupForm }

constructor TAtlasPopupForm.CreatePopup(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  BorderStyle := bsNone;
  Position := poDesigned;
  KeyPreview := False;
  DoubleBuffered := True;
  Color := TColor(FColors.Surface);
  TAtlasUiTheme.AssignDialogFont(Font);
  TAtlasUiTheme.Subscribe(Self,
    procedure
    begin
      HandleThemeChanged;
    end);
end;

destructor TAtlasPopupForm.Destroy;
begin
  TAtlasUiTheme.Unsubscribe(Self);
  inherited;
end;

procedure TAtlasPopupForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasPopupForm.CreateWnd;
begin
  inherited CreateWnd;
  ApplyFrame;
end;

procedure TAtlasPopupForm.VisibleChanging;
begin
  if FThemedControls and not Visible then
  begin
    TAtlasUiTheme.Apply(Self);
  end;
  inherited;
end;

procedure TAtlasPopupForm.ApplyFrame;
var
  mPreference, mBorder: DWORD;
begin
  if not FRounded or not HandleAllocated then
  begin
    Exit;
  end;
  mPreference := cDwmRoundCorners;
  DwmSetWindowAttribute(Handle, cDwmCornerPreference, @mPreference, SizeOf(mPreference));
  mBorder := DWORD(FColors.Accent);
  DwmSetWindowAttribute(Handle, cDwmBorderColor, @mBorder, SizeOf(mBorder));
end;

procedure TAtlasPopupForm.HandleThemeChanged;
begin
  if FThemedControls then
  begin
    TAtlasUiTheme.Apply(Self);
  end;
  FColors := TAtlasUiTheme.Colors;
  Color := TColor(FColors.Surface);
  ApplyFrame;
  ColorsChanged;
  Invalidate;
end;

procedure TAtlasPopupForm.ColorsChanged;
begin
end;

end.
