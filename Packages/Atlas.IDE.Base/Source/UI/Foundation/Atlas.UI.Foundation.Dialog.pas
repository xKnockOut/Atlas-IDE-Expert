unit Atlas.UI.Foundation.Dialog;

// Gemeinsame Basis der im Code gebauten Atlas-Dialoge (#2062). Vorher setzte
// jeder der 61 Dialoge Rahmen, Position, Schrift und Breite selbst, baute
// eigene Knopf-Helfer (46 Units) und färbte Fehlertexte mit clRed; 36 Dialoge
// bekamen nie das Thema der IDE. TAtlasDialog bringt mit:
// - CreateDialog: CreateNew, bsDialog, poMainFormCenter, Dialogschrift aus
//   TAtlasUiTheme, Breite in logischen Pixeln (96 dpi), Abo beim Themendienst;
// - DoShow: IDE-Thema an der Wurzel (Kinder erben den Stil), ThemeChanged bei
//   jedem Wechsel, solange der Dialog lebt; Abmelden im Destroy;
// - AddRow, AddLabel, AddButtonRow, AddNote: Zeilen von oben nach unten,
//   Größen in logischen Pixeln, skaliert über das Formular;
// - FitHeight: Höhe bis unter das letzte Element.
// TAtlasButtonRow misst die Knöpfe nach ihrem Text, TAtlasNoteLabel zeigt
// Hinweise in der Textfarbe der Palette (Fehler, Warnung, Ok); Hinweise ohne
// Aussage zeichnet der Stil. Eigene Farben holt ein Dialog in ThemeChanged.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
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
  private
    procedure HandleThemeChanged;
  protected
    procedure DoShow; override;
    /// <summary>Thema der IDE hat gewechselt (nach dem Anwenden an der Wurzel): eigene Farben neu holen.</summary>
    procedure ThemeChanged; virtual;
    /// <summary>Oberkante unter dem bisher untersten Element (alTop stapelt nach Top).</summary>
    function NextTop: Integer;
  public
    /// <summary>Leeren Dialog mit Titel ACaption und Innenbreite AWidth96 (logische Pixel) anlegen.</summary>
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
  end;

implementation

uses
  Vcl.Graphics,
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

function TAtlasButtonRow.ButtonWidth(const ACaption: string): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    // Font.Height ist schon in Gerätepixeln der Leiste.
    mBitmap.Canvas.Font.Assign(Font);
    Result := mBitmap.Canvas.TextWidth(ACaption) + ScaleValue(cButtonPadding);
  finally
    mBitmap.Free;
  end;
  if Result < ScaleValue(cButtonMinWidth) then
  begin
    Result := ScaleValue(cButtonMinWidth);
  end;
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
  ClientWidth := ScaleValue(AWidth96);
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

procedure TAtlasDialog.DoShow;
begin
  TAtlasUiTheme.Apply(Self);
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

end.
