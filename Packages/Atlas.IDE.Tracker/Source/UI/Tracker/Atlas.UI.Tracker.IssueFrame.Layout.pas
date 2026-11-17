unit Atlas.UI.Tracker.IssueFrame.Layout;

// Ablage des Inhalts im Bildlauf des Fensters „Atlas-Issue“ (#1264): Teile stehen untereinander in der Reihenfolge,
// in der sie angelegt werden, direkt im Bildlauf oder in einer Karte (Kopf, Kommentar). Grundbausteine:
// Abschnittsüberschrift mit Linie, umbrechender Text, gedämpfte Zeile, Verweis in Akzentfarbe, Liste und Knopf.
// Klicks gehen an AOnClick, der Tag ist cAtlasIssuePartTag + Ord(TAtlasIssuePart). Clear gibt alles wieder frei.
// Welche Abschnitte ein Issue hat, baut Atlas.UI.Tracker.IssueFrame.Sections.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.UI.Tracker.IssueBoxes,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.IssueFrame.Contract;

type
  /// <summary>Legt die Teile des Inhalts in ABox ab; sie gehören AOwner.</summary>
  TAtlasIssueLayout = class
  private
    FOwner: TComponent;
    FBox: TScrollBox;
    FOnClick: TNotifyEvent;
    FColors: TAtlasColors;
    FMono: TFont;
    /// <summary>Alle Teile direkt im Bildlauf (für Clear); Teile in Karten gibt ihre Karte frei.</summary>
    FControls: TList<TControl>;
    /// <summary>Behälter für Place: nil = Bildlauf, sonst eine Karte.</summary>
    FTarget: TAtlasIssueCard;
    FNextTop: Integer;
  public
    constructor Create(AOwner: TComponent; ABox: TScrollBox; AOnClick: TNotifyEvent);
    destructor Destroy; override;
    /// <summary>Alle Teile freigeben; die nächste Ablage beginnt oben.</summary>
    procedure Clear;
    /// <summary>AControl unter die bisherigen Teile legen, in die offene Karte oder in den Bildlauf.</summary>
    procedure Place(AControl: TControl);
    /// <summary>Farben für Inhalt an der Stelle von Place: in einer Karte deren Fläche statt Surface.</summary>
    function ContentColors: TAtlasColors;
    /// <summary>Neue Karte; Place legt danach in ihr ab, bis EndCard. AFillAlpha: Deckkraft der Schrift über der
    /// Fläche.</summary>
    function BeginCard(AFillAlpha: Double): TAtlasIssueCard;
    procedure EndCard;
    /// <summary>Überschrift eines Abschnitts mit Linie.</summary>
    procedure AddSection(const ACaption: string);
    function AddText(const ACaption: string; ABold: Boolean): TLabel;
    /// <summary>Gedämpfte Zeile (Hinweis).</summary>
    procedure AddMuted(const ACaption: string; ABold: Boolean);
    /// <summary>Unterstrichener Verweis in Akzentfarbe.</summary>
    function AddLinkText(const ACaption: string; APart: TAtlasIssuePart): TLabel;
    /// <summary>Liste mit Spaltenköpfen; Höhe setzt der Aufrufer (RowsHeight).</summary>
    function AddList(const AColumns: TArray<string>; APart: TAtlasIssuePart): TListView;
    /// <summary>Knopf links in AParent hinter den bisherigen.</summary>
    function AddButton(AParent: TWinControl; AText: TAtlasIssueTextId; AMinWidth: Integer;
      APart: TAtlasIssuePart): TButton;
    /// <summary>Höhe für ARows Zeilen einer Liste oder eines Baums.</summary>
    function RowsHeight(ARows: Integer): Integer;
    /// <summary>Bildlauf so, dass AControl (bzw. seine Karte) oben steht.</summary>
    procedure ScrollTo(AControl: TControl);
    property Owner: TComponent read FOwner;
    property Box: TScrollBox read FBox;
    property OnClick: TNotifyEvent read FOnClick;
    property Colors: TAtlasColors read FColors write FColors;
    /// <summary>Editorschrift für Code (Vorgabe Consolas).</summary>
    property Mono: TFont read FMono;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Winapi.Windows,
  Atlas.Core.Style.Color,
  Atlas.UI.Foundation.WrapLabel;

const
  /// <summary>Abstand von Top zwischen zwei Teilen: alTop ordnet nach Top, Lücken lassen Platz.</summary>
  cPlaceStep = 1000;
  /// <summary>Zeilenhöhe von Listen und Bäumen und Breite je Zeichen eines Knopfs bei 96 dpi.</summary>
  cRowHeight = 20;
  cCharWidth = 8;
  /// <summary>Left je vorhandenem Knopf: alLeft reiht nach Left.</summary>
  cButtonStep = 200;
  cMonoSize = 10;

{ TAtlasIssueLayout }

constructor TAtlasIssueLayout.Create(AOwner: TComponent; ABox: TScrollBox; AOnClick: TNotifyEvent);
begin
  inherited Create;
  FOwner := AOwner;
  FBox := ABox;
  FOnClick := AOnClick;
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := cMonoSize;
  FControls := TList<TControl>.Create;
end;

destructor TAtlasIssueLayout.Destroy;
begin
  // Die Teile gehören dem Besitzer und sind mit ihm schon frei.
  FControls.Free;
  FMono.Free;
  inherited;
end;

procedure TAtlasIssueLayout.Clear;
var
  mPart: TControl;
begin
  for mPart in FControls do
  begin
    mPart.Free;
  end;
  FControls.Clear;
  FTarget := nil;
  FNextTop := 0;
end;

procedure TAtlasIssueLayout.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  Inc(FNextTop, cPlaceStep);
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
  if FTarget <> nil then
  begin
    // Die Karte gibt ihre Kinder mit sich frei: nicht in FControls.
    AControl.Parent := FTarget;
    Exit;
  end;
  AControl.Parent := FBox;
  FControls.Add(AControl);
end;

function TAtlasIssueLayout.ContentColors: TAtlasColors;
begin
  Result := FColors;
  if FTarget <> nil then
  begin
    Result.Surface := FTarget.Fill;
  end;
end;

function TAtlasIssueLayout.BeginCard(AFillAlpha: Double): TAtlasIssueCard;
begin
  Result := TAtlasIssueCard.Create(FOwner);
  Place(Result);
  Result.SetColors(TAtlasColorMath.Mix(FColors.Text, FColors.Surface, AFillAlpha), FColors.Line);
  FTarget := Result;
end;

procedure TAtlasIssueLayout.EndCard;
begin
  FTarget := nil;
end;

procedure TAtlasIssueLayout.AddSection(const ACaption: string);
var
  mHead: TAtlasIssueSectionHead;
begin
  mHead := TAtlasIssueSectionHead.Create(FOwner);
  Place(mHead);
  mHead.Caption := ACaption;
  mHead.SetColors(ContentColors);
end;

function TAtlasIssueLayout.AddText(const ACaption: string; ABold: Boolean): TLabel;
begin
  Result := TAtlasWrapLabel.Create(FOwner);
  Place(Result);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Result.Font.Color := TColor(FColors.Text);
  if ABold then
  begin
    Result.Font.Style := [fsBold];
  end;
end;

procedure TAtlasIssueLayout.AddMuted(const ACaption: string; ABold: Boolean);
begin
  AddText(ACaption, ABold).Font.Color := TColor(FColors.Muted);
end;

function TAtlasIssueLayout.AddLinkText(const ACaption: string; APart: TAtlasIssuePart): TLabel;
begin
  Result := AddText(ACaption, False);
  Result.Font.Color := TColor(FColors.Accent);
  Result.Font.Style := [fsUnderline];
  Result.Cursor := crHandPoint;
  Result.Tag := cAtlasIssuePartTag + Ord(APart);
  Result.OnClick := FOnClick;
end;

function TAtlasIssueLayout.AddList(const AColumns: TArray<string>; APart: TAtlasIssuePart): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(FOwner);
  Place(Result);
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ShowColumnHeaders := True;
  for mCaption in AColumns do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := mCaption;
    mColumn.AutoSize := True;
  end;
  Result.Tag := cAtlasIssuePartTag + Ord(APart);
end;

function TAtlasIssueLayout.AddButton(AParent: TWinControl; AText: TAtlasIssueTextId; AMinWidth: Integer;
  APart: TAtlasIssuePart): TButton;
begin
  Result := TButton.Create(FOwner);
  Result.Parent := AParent;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Left := AParent.ControlCount * cButtonStep;
  Result.Caption := TAtlasIssueStrings.Text(AText);
  Result.Width := Max(AMinWidth, Length(Result.Caption) * cCharWidth);
  Result.Tag := cAtlasIssuePartTag + Ord(APart);
  Result.OnClick := FOnClick;
end;

function TAtlasIssueLayout.RowsHeight(ARows: Integer): Integer;
begin
  Result := ARows * MulDiv(cRowHeight, FBox.CurrentPPI, USER_DEFAULT_SCREEN_DPI);
end;

procedure TAtlasIssueLayout.ScrollTo(AControl: TControl);
var
  mItem: TControl;
begin
  mItem := AControl;
  // Teile einer Karte: zur Karte blättern.
  while (mItem.Parent <> nil) and (mItem.Parent <> FBox) do
  begin
    mItem := mItem.Parent;
  end;
  FBox.VertScrollBar.Position := mItem.Top - mItem.Margins.Top;
end;

end.
