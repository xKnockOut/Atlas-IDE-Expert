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
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Settings.ChoiceBox;

const
  // Linke Kante der Eingabefelder; Platz für die längste Beschriftung („Breite der Blocklinien …“).
  cFieldLeft = 280;
  /// <summary>Oberkante der Knöpfe in einer Zeile der Seite.</summary>
  cRowButtonTop = 3;

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
    /// <summary>Zeile mit Beschriftung links und AControl rechts daneben (Verbindungen, Projekte).</summary>
    function AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    class procedure AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer); static;
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
  Vcl.Graphics;

{ TAtlasSettingsRow }

constructor TAtlasSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

{ TAtlasSettingsPageSheets }

function TAtlasSettingsPageSheets.AddFieldRow(AId: TAtlasTextId; AControl: TWinControl;
  AWidth: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Result;
  mCaption.Caption := TAtlasStrings.Text(AId) + ':';
  mCaption.Left := 0;
  mCaption.Top := 5;
  AControl.Parent := Result;
  AControl.Left := 90;
  AControl.Top := 1;
  AControl.Width := AWidth;
end;

function TAtlasSettingsPageSheets.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(AId);
  Result.Left := ALeft;
  Result.Top := cRowButtonTop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

class procedure TAtlasSettingsPageSheets.AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(AId);
  mColumn.Width := AWidth;
end;

function TAtlasSettingsPageSheets.AddTextLine(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mHeading: TLabel;
begin
  mPanel := AddPanel(20);
  mHeading := TLabel.Create(Self);
  mHeading.Parent := mPanel;
  mHeading.Caption := ACaption;
  mHeading.Left := 0;
  mHeading.Top := 3;
  // Eigene Zeile für das Feld: Adressen und Pfade brauchen die Breite.
  mPanel := AddPanel(26);
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := 0;
  Result.Top := 1;
  Result.Width := 466;
  Result.Anchors := [akLeft, akTop, akRight];
end;

procedure TAtlasSettingsPageSheets.AddSheet(AId: TAtlasTextId);
begin
  AddSheetCaption(TAtlasStrings.Text(AId));
end;

function TAtlasSettingsPageSheets.ListReady(AControl: TWinControl): Boolean;
begin
  if not AControl.HandleAllocated and HandleAllocated then
  begin
    AControl.HandleNeeded;
  end;
  Result := AControl.HandleAllocated;
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
  mPanel := AddPanel(22);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Font.Style := [fsBold];
  mCaption.Left := 0;
  mCaption.Top := 4;
end;

function TAtlasSettingsPageSheets.AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TAtlasChoiceBox.Create(Self);
  Result.Parent := mPanel;
  Result.Left := cFieldLeft;
  Result.Top := 1;
  Result.Width := 180;
  Result.SetChoices(AItems);
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
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TAtlasSettingsPageSheets.AddKey(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := StringReplace(ACaption, '…', '', []);
  mCaption.Left := 0;
  mCaption.Top := 5;
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := cFieldLeft;
  Result.Top := 1;
  Result.Width := 140;
end;

function TAtlasSettingsPageSheets.AddNumber(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := cFieldLeft;
  Result.Top := 1;
  Result.Width := 60;
  Result.NumbersOnly := True;
end;

function TAtlasSettingsPageSheets.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
var
  mPanel: TWinControl;
begin
  mPanel := AddPanel(AHeight);
  Result := TLabel.Create(Self);
  Result.Parent := mPanel;
  Result.AutoSize := False;
  Result.Align := alClient;
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
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

end.
