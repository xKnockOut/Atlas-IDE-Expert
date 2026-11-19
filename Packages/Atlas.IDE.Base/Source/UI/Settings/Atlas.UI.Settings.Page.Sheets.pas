unit Atlas.UI.Settings.Page.Sheets;

// Bausteine der Optionsseite „Atlas“ (#227): Reiter je Bereich mit rollbarem Inhalt und die Zeilen darin
// (Kontrollkästchen, Zahl, Auswahl, Taste, Textzeile, Überschrift, Hinweis, Feldzeile mit Knöpfen). Unterste Stufe
// der Klassenkette der Seite; die Teile der Seite bauen ihre Elemente über diese Methoden.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox;

const
  // Linke Kante der Eingabefelder; Platz für die längste Beschriftung („Breite der Blocklinien …“).
  cFieldLeft = 280;
  /// <summary>Oberkante der Knöpfe in einer Zeile der Seite.</summary>
  cRowButtonTop = 3;
  /// <summary>Höhe einer Zeile mit Beschriftung links und Eingabefeld rechts.</summary>
  cFieldRowHeight = 26;
  /// <summary>Oberkante der Beschriftung in einer Feldzeile: auf Höhe des Textes im Feld.</summary>
  cFieldCaptionTop = 5;
  /// <summary>Höhe einer Zeile mit Knöpfen.</summary>
  cButtonRowHeight = 32;
  /// <summary>Breite eines Knopfs in einer Knopfzeile und sein Abstand zum nächsten (Breite und Lücke).</summary>
  cRowButtonWidth = 150;
  cRowButtonStep = 160;
  /// <summary>Breite einer Auswahlliste in einer Feldzeile.</summary>
  cChoiceWidth = 180;
  /// <summary>Höhe einer Kopfzeile über einem Feld oder einer Liste und Oberkante ihres Textes.</summary>
  cHeadingHeight = 20;
  cHeadingTop = 3;
  /// <summary>Breite eines Textfelds unter einer Kopfzeile: die Seite ohne Rand; wächst mit (Anchors).</summary>
  cTextLineWidth = 466;

type
  /// <summary>Zeile der Optionsseite (Beschriftung und Eingabefeld): zeichnet nichts selbst, der
  /// Hintergrund des Reiters scheint durch.</summary>
  TAtlasSettingsRow = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TAtlasSettingsPageSheets = class(TFrame)
  protected
    /// <summary>Aktueller Reiter und sein rollbarer Inhalt; nimmt die Elemente auf.</summary>
    FSheet: TTabSheet;
    FContent: TScrollBox;
    // Reiter hängen erst mit dem Fensterhandle am PageControl (CreateWnd): Die IDE und die Tests
    // erzeugen die Seite, bevor sie ein übergeordnetes Fenster hat.
    FSheets: TArray<TTabSheet>;
    /// <summary>Rollbarer Inhalt je Bereich, gleicher Index wie FSheets.</summary>
    FBoxes: TArray<TScrollBox>;
    FNextTop: Integer;
  public
    /// <summary>AControl hat ein Fenster bzw. bekommt eines, sobald die Seite eines hat (Einträge von Listen und
    /// Bäumen leben im Fenster; auf noch nicht gezeigten Reitern fehlt es sonst).</summary>
    function ListReady(AControl: TWinControl): Boolean;
    /// <summary>Neuer Reiter; die folgenden Add… setzen ihre Elemente darauf.</summary>
    procedure AddSheet(AId: TAtlasTextId);
    procedure AddSheetCaption(const ACaption: string);
    /// <summary>Weitere Elemente auf den vorhandenen Reiter AIndex, unter die vorhandenen (Abschnitte der Module).
    /// </summary>
    procedure ContinueSheet(AIndex: Integer);
    function AddCheck(const ACaption: string): TCheckBox;
    /// <summary>Zeile der Höhe AHeight in logischen Pixeln (96 dpi); skaliert wird hier.</summary>
    function AddPanel(AHeight: Integer): TWinControl;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
    /// <summary>Fett gesetzte Überschrift eines Abschnitts.</summary>
    procedure AddTitle(AId: TAtlasTextId);
    procedure AddTitleText(const ACaption: string);
    /// <summary>Kürzel ohne eigenen Vorrang; der gilt für die Gruppe (#399). Palette und Prüfung stehen auf der
    /// Seite „Tastenkonflikte“ (#494).</summary>
    function AddKey(const ACaption: string): TEdit;
    /// <summary>Beschriftung über die ganze Breite mit Zeilenumbruch.</summary>
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    /// <summary>Zeile mit Beschriftung links und AControl rechts daneben (Verbindungen, Projekte). AWidth in
    /// logischen Pixeln (96 dpi).</summary>
    function AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    /// <summary>Knopf in AParent; ALeft und AWidth in logischen Pixeln (96 dpi).</summary>
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    /// <summary>Knopf der Breite cRowButtonWidth in der Spalte AColumn (ab 0) einer Knopfzeile.</summary>
    function AddColumnButton(AParent: TWinControl; AColumn: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    /// <summary>Zeile der Höhe cFieldRowHeight mit der Beschriftung ACaption links.</summary>
    function AddCaptionRow(const ACaption: string): TWinControl;
    /// <summary>Knopf mit Besitzer AOwner in AParent; ALeft und AWidth in logischen Pixeln (96 dpi). Auch für die
    /// Abschnitte der Module, die die Seite nicht selbst bauen.</summary>
    class function NewRowButton(AOwner: TComponent; AParent: TWinControl; ALeft, AWidth: Integer;
      const ACaption: string; AClick: TNotifyEvent): TButton; static;
    /// <summary>Zeile oben in AParent (alTop, Höhe AHeight in logischen Pixeln) unter die vorigen; ANextTop zählt
    /// die Stapelfolge. Für Seiten ohne Reiter (Tasten, Server).</summary>
    class function NewTopPanel(AParent: TWinControl; AHeight: Integer; var ANextTop: Integer): TPanel; static;
    /// <summary>Beschriftung in einer Zeile, darunter ein Textfeld über die ganze Breite (#766).</summary>
    function AddTextLine(const ACaption: string): TEdit;
    /// <summary>Reiter und ihr Inhalt in der Reihenfolge des Aufbaus.</summary>
    property Sheets: TArray<TTabSheet> read FSheets;
    property Boxes: TArray<TScrollBox> read FBoxes;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Atlas.UI.Foundation.WrapLabel;

const
  /// <summary>Breiten der Eingabefelder je Art (logische Pixel).</summary>
  cNumberWidth = 60;
  cKeyWidth = 140;
  /// <summary>Linke Kante des Feldes in einer Feldzeile mit kurzer Beschriftung (AddFieldRow).</summary>
  cShortFieldLeft = 90;
  /// <summary>Höhe einer Überschrift und Oberkante ihres Textes.</summary>
  cTitleHeight = 22;
  cTitleCaptionTop = 4;

{ TAtlasSettingsRow }

constructor TAtlasSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

{ TAtlasSettingsPageSheets }

function TAtlasSettingsPageSheets.ListReady(AControl: TWinControl): Boolean;
begin
  if not AControl.HandleAllocated and HandleAllocated then
  begin
    AControl.HandleNeeded;
  end;
  Result := AControl.HandleAllocated;
end;

procedure TAtlasSettingsPageSheets.AddSheet(AId: TAtlasTextId);
begin
  AddSheetCaption(TAtlasStrings.Text(AId));
end;

procedure TAtlasSettingsPageSheets.AddSheetCaption(const ACaption: string);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := ACaption;
  FSheets := FSheets + [FSheet];
  // Rollbar: Lange Reiter passten sonst nicht in die Optionsseite und wurden abgeschnitten.
  FContent := TScrollBox.Create(Self);
  FBoxes := FBoxes + [FContent];
  FContent.Parent := FSheet;
  FContent.Align := alClient;
  FContent.BorderStyle := bsNone;
  FContent.ParentBackground := True;
  FContent.VertScrollBar.Tracking := True;
  FContent.HorzScrollBar.Visible := False;
  FNextTop := 100;
end;

procedure TAtlasSettingsPageSheets.ContinueSheet(AIndex: Integer);
var
  mIndex: Integer;
  mControl: TControl;
begin
  FSheet := FSheets[AIndex];
  FContent := FBoxes[AIndex];
  // Neue Zeilen unter die vorhandenen: alTop ordnet nach Top.
  FNextTop := 100;
  for mIndex := 0 to FContent.ControlCount - 1 do
  begin
    mControl := FContent.Controls[mIndex];
    FNextTop := Max(FNextTop, mControl.Top + mControl.Height + 100);
  end;
end;

function TAtlasSettingsPageSheets.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TAtlasSettingsPageSheets.AddPanel(AHeight: Integer): TWinControl;
begin
  // Kein TPanel: Das zeichnet im IDE-Thema einen eigenen Hintergrund (dunkle Streifen im Reiter).
  Result := TAtlasSettingsRow.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Height := Result.ScaleValue(AHeight);
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TAtlasSettingsPageSheets.AddCaptionRow(const ACaption: string): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(cFieldRowHeight);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Result;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(cFieldCaptionTop);
end;

function TAtlasSettingsPageSheets.AddNumber(const ACaption: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AddCaptionRow(ACaption);
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(cNumberWidth);
  Result.NumbersOnly := True;
end;

function TAtlasSettingsPageSheets.AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
begin
  Result := TAtlasChoiceBox.Create(Self);
  Result.Parent := AddCaptionRow(ACaption);
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(cChoiceWidth);
  Result.SetChoices(AItems);
end;

procedure TAtlasSettingsPageSheets.AddTitle(AId: TAtlasTextId);
begin
  AddTitleText(TAtlasStrings.Text(AId));
end;

procedure TAtlasSettingsPageSheets.AddTitleText(const ACaption: string);
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(cTitleHeight);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Font.Style := [fsBold];
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(cTitleCaptionTop);
end;

function TAtlasSettingsPageSheets.AddKey(const ACaption: string): TEdit;
begin
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := AddCaptionRow(StringReplace(ACaption, '…', '', []));
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(cKeyWidth);
end;

function TAtlasSettingsPageSheets.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
var
  mPanel: TWinControl;
begin
  mPanel := AddPanel(AHeight);
  Result := TAtlasWrapLabel.Create(Self);
  Result.Parent := mPanel;
  Result.AutoSize := False;
  Result.Align := alClient;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

function TAtlasSettingsPageSheets.AddFieldRow(AId: TAtlasTextId; AControl: TWinControl;
  AWidth: Integer): TWinControl;
begin
  Result := AddCaptionRow(TAtlasStrings.Text(AId) + ':');
  AControl.Parent := Result;
  AControl.Left := AControl.ScaleValue(cShortFieldLeft);
  AControl.Top := 1;
  AControl.Width := AControl.ScaleValue(AWidth);
end;

function TAtlasSettingsPageSheets.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := NewRowButton(Self, AParent, ALeft, AWidth, TAtlasStrings.Text(AId), AClick);
end;

class function TAtlasSettingsPageSheets.NewRowButton(AOwner: TComponent; AParent: TWinControl; ALeft,
  AWidth: Integer; const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := Result.ScaleValue(ALeft);
  Result.Top := Result.ScaleValue(cRowButtonTop);
  Result.Width := Result.ScaleValue(AWidth);
  Result.OnClick := AClick;
end;

function TAtlasSettingsPageSheets.AddColumnButton(AParent: TWinControl; AColumn: Integer; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := NewRowButton(Self, AParent, AColumn * cRowButtonStep, cRowButtonWidth, ACaption, AClick);
end;

class function TAtlasSettingsPageSheets.NewTopPanel(AParent: TWinControl; AHeight: Integer;
  var ANextTop: Integer): TPanel;
const
  cStackStep = 100;
begin
  Result := TPanel.Create(AParent);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.BevelOuter := bvNone;
  Result.Height := Result.ScaleValue(AHeight);
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := ANextTop;
  Inc(ANextTop, cStackStep);
  Result.ParentBackground := True;
end;

function TAtlasSettingsPageSheets.AddTextLine(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mHeading: TLabel;
begin
  mPanel := AddPanel(cHeadingHeight);
  mHeading := TLabel.Create(Self);
  mHeading.Parent := mPanel;
  mHeading.Caption := ACaption;
  mHeading.Left := 0;
  mHeading.Top := mHeading.ScaleValue(cHeadingTop);
  // Eigene Zeile für das Feld: Adressen und Pfade brauchen die Breite.
  mPanel := AddPanel(cFieldRowHeight);
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := 0;
  Result.Top := 1;
  Result.Width := Result.ScaleValue(cTextLineWidth);
  Result.Anchors := [akLeft, akTop, akRight];
end;

end.
