unit Atlas.UI.Welcome.WhatsNew;

// Karte „Neu in Atlas“ der Willkommensseite (#756), ohne Open Tools API.
// Je neue Funktion eine Zeile: Titel, Tastenkürzel mit tatsächlicher
// Belegung, ein Satz Erklärung, Schalter für die zugehörige Einstellung und
// „Ausprobieren“. Bei mehreren Versionen (Sprung über Versionen, „Alle
// Versionen“) steht je Version eine Überschrift; in „Alle Versionen“ lässt
// sich jede Version mit einem Klick auf- und zuklappen, aufgeklappt ist
// zunächst die neueste. Unten „Gelesen“ (nach einem Update) bzw.
// „Schließen“. Das Kontextmenü (TAtlasWhatsNewMenu, auch für den Frame
// „Atlas“ und den Kopf) bietet „Neuigkeiten dieser Version zeigen“ und
// „Alle Versionen“.
// Daten und Aktionen kommen über IAtlasWhatsNewSource aus der IDE-Schicht.
// Klicks rufen die Quelle über die Nachrichtenschleife auf: Die Quelle baut
// die Karte daraufhin neu, und ein Steuerelement darf nicht in seinem eigenen
// Klick freigegeben werden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Graphics,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Frame;

type
{$SCOPEDENUMS ON}
  /// <summary>Schalter einer Zeile: keiner (keine oder unbekannte Einstellung), aus, an.</summary>
  TAtlasWhatsNewSwitch = (None, Off, On);
{$SCOPEDENUMS OFF}

  IAtlasWhatsNewSource = interface
    ['{6B0F3E52-8D1A-4C7E-9A35-2E4D7C1B8F60}']
    /// <summary>Was die Karte gerade zeigt.</summary>
    function View: TAtlasWhatsNewView;
    /// <summary>Versionen zu View, neueste zuerst.</summary>
    function Versions: TAtlasWhatsNewVersions;
    function SwitchOf(const ASetting: string): TAtlasWhatsNewSwitch;
    /// <summary>Tatsächliche Belegung der Tasten-Einstellung AKey als Text; '' ohne.</summary>
    function KeyText(const AKey: string): string;
    /// <summary>Hat der Eintrag einen ausführbaren Befehl oder eine vorhandene Beispieldatei?</summary>
    function CanTry(const AItem: TAtlasWhatsNewItem): Boolean;
    procedure SetSwitch(const ASetting: string; AOn: Boolean);
    procedure TryItem(const AItem: TAtlasWhatsNewItem);
    /// <summary>„Gelesen“ nach einem Update, sonst „Schließen“: zurück zur Vorgabe der Einstellung.</summary>
    procedure Dismiss;
    procedure Show(AView: TAtlasWhatsNewView);
  end;

  /// <summary>Kontextmenü mit „Neuigkeiten dieser Version zeigen“ und „Alle Versionen“.</summary>
  TAtlasWhatsNewMenu = class(TPopupMenu)
  private
    FSource: IAtlasWhatsNewSource;
    FCurrentItem: TMenuItem;
    FAllItem: TMenuItem;
    procedure ItemClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property CurrentItem: TMenuItem read FCurrentItem;
    property AllItem: TMenuItem read FAllItem;
    /// <summary>Empfängt die Wahl (über die Nachrichtenschleife); nil = Menü ohne Wirkung.</summary>
    property Source: IAtlasWhatsNewSource read FSource write FSource;
  end;

  /// <summary>Steuerelemente einer Zeile; Switch und TryButton sind nil, wenn die Zeile keine hat.</summary>
  TAtlasWhatsNewRow = record
    Version: string;
    Item: TAtlasWhatsNewItem;
    /// <summary>Überschrift „Experimentell“ vor der ersten experimentellen Zeile (#834); sonst nil.</summary>
    Section: TLabel;
    Title: TLabel;
    Key: TLabel;
    Text: TLabel;
    Switch: TCheckBox;
    TryButton: TButton;
  end;

  TAtlasWelcomeWhatsNewFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    RowGap = 10;
    SwitchWidth = 52;
    TryWidth = 100;
    ButtonHeight = 24;
  private
    FSource: IAtlasWhatsNewSource;
    FMenu: TAtlasWhatsNewMenu;
    FScroll: TScrollBox;
    FControls: TObjectList<TControl>;
    FRows: TArray<TAtlasWhatsNewRow>;
    FHeadings: TArray<TLabel>;
    FHeadingVersions: TArray<string>;
    FDismiss: TButton;
    FVersions: TAtlasWhatsNewVersions;
    FView: TAtlasWhatsNewView;
    FExpanded: TDictionary<string, Boolean>;
    FContentHeight: Integer;
    FUpdating: Boolean;
    FArranging: Boolean;
    procedure SetSource(const AValue: IAtlasWhatsNewSource);
    procedure Clear;
    function Add<T: TControl>(AControl: T): T;
    procedure Build;
    procedure Arrange;
    procedure ScrollResize(Sender: TObject);
    procedure HeadingClick(Sender: TObject);
    procedure SwitchClick(Sender: TObject);
    procedure TryClick(Sender: TObject);
    procedure DismissClick(Sender: TObject);
    function Collapsible: Boolean;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateContent; override;
    /// <summary>Version auf- oder zuklappen (nur in „Alle Versionen“).</summary>
    procedure Toggle(const AVersion: string);
    function IsExpanded(const AVersion: string): Boolean;
    /// <summary>„Neu in Atlas 1.1.0“ für eine Version, sonst „Neu in Atlas“.</summary>
    class function TitleFor(AView: TAtlasWhatsNewView; const AVersions: TAtlasWhatsNewVersions): string; static;
    /// <summary>Überschrift einer Version; in „Alle Versionen“ mit ▸/▾.</summary>
    class function HeadingText(const AVersion: string; ACollapsible, AExpanded: Boolean): string; static;
    property Source: IAtlasWhatsNewSource read FSource write SetSource;
    property Menu: TAtlasWhatsNewMenu read FMenu;
    property Rows: TArray<TAtlasWhatsNewRow> read FRows;
    property Headings: TArray<TLabel> read FHeadings;
    property DismissButton: TButton read FDismiss;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.Math,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings;

type
  /// <summary>Legt die Steuerelemente der Karte an: Überschriften, Zeilen mit Schalter und „Ausprobieren“, den
  /// Knopf zum Schließen. Schreibt in die Felder der Karte.</summary>
  TWhatsNewRowBuilder = record
  private
    FFrame: TAtlasWelcomeWhatsNewFrame;
  public
    constructor Create(AFrame: TAtlasWelcomeWhatsNewFrame);
    procedure AddHeading(const AVersion: string);
    procedure AddRows(const AVersion: TAtlasWhatsNewVersion);
    function NewRow(const AVersion: string; const AItem: TAtlasWhatsNewItem; ASection: TLabel): TAtlasWhatsNewRow;
    function NewSwitch(const ASetting: string): TCheckBox;
    procedure AddDismiss;
  end;

var
  // Lebende Karten: Klicks auf Überschriften wirken über die Nachrichtenschleife, die Karte kann bis dahin frei
  // sein.
  Live: TList<TAtlasWelcomeWhatsNewFrame>;

{ TWhatsNewRowBuilder }

constructor TWhatsNewRowBuilder.Create(AFrame: TAtlasWelcomeWhatsNewFrame);
begin
  FFrame := AFrame;
end;

procedure TWhatsNewRowBuilder.AddHeading(const AVersion: string);
var
  mHeading: TLabel;
begin
  mHeading := FFrame.Add(TLabel.Create(nil));
  mHeading.Caption := FFrame.HeadingText(AVersion, FFrame.Collapsible, FFrame.IsExpanded(AVersion));
  mHeading.Font.Style := [fsBold];
  if FFrame.Collapsible then
  begin
    mHeading.Cursor := crHandPoint;
    mHeading.OnClick := FFrame.HeadingClick;
  end;
  mHeading.Tag := Length(FFrame.FHeadings);
  FFrame.FHeadings := FFrame.FHeadings + [mHeading];
  FFrame.FHeadingVersions := FFrame.FHeadingVersions + [AVersion];
end;

procedure TWhatsNewRowBuilder.AddRows(const AVersion: TAtlasWhatsNewVersion);
var
  mItem: TAtlasWhatsNewItem;
  mInExperimental: Boolean;
  mSection: TLabel;
  mRow: TAtlasWhatsNewRow;
begin
  mInExperimental := False;
  // Experimentelle Einträge nach den übrigen unter eigener Überschrift (#834).
  for mItem in TAtlasWhatsNew.Ordered(AVersion.Items) do
  begin
    mSection := nil;
    if mItem.Experimental and not mInExperimental then
    begin
      mInExperimental := True;
      mSection := FFrame.Add(TLabel.Create(nil));
      mSection.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsExperimental);
      mSection.Font.Style := [fsItalic];
      mSection.Font.Color := clGrayText;
    end;
    // NewRow vergibt Length(FFrame.FRows) als Tag, darum erst danach anhängen.
    mRow := NewRow(AVersion.Version, mItem, mSection);
    FFrame.FRows := FFrame.FRows + [mRow];
  end;
end;

function TWhatsNewRowBuilder.NewRow(const AVersion: string; const AItem: TAtlasWhatsNewItem;
  ASection: TLabel): TAtlasWhatsNewRow;
var
  mKeyText: string;
begin
  Result := Default(TAtlasWhatsNewRow);
  Result.Section := ASection;
  Result.Version := AVersion;
  Result.Item := AItem;
  Result.Title := FFrame.Add(TLabel.Create(nil));
  // Englisch mit englischer IDE (#1458).
  Result.Title.Caption := AItem.TitleFor(TAtlasStrings.Language = TAtlasLanguage.English);
  Result.Title.Font.Style := [fsBold];
  mKeyText := '';
  if (FFrame.FSource <> nil) and (AItem.Key <> '') then
  begin
    mKeyText := FFrame.FSource.KeyText(AItem.Key);
  end;
  if mKeyText <> '' then
  begin
    Result.Key := FFrame.Add(TLabel.Create(nil));
    Result.Key.Caption := mKeyText;
    Result.Key.Font.Color := clGrayText;
  end;
  if AItem.Text <> '' then
  begin
    Result.Text := FFrame.Add(TLabel.Create(nil));
    Result.Text.AutoSize := True;
    Result.Text.WordWrap := True;
    Result.Text.Caption := AItem.TextFor(TAtlasStrings.Language = TAtlasLanguage.English);
  end;
  Result.Switch := NewSwitch(AItem.Setting);
  if (FFrame.FSource <> nil) and FFrame.FSource.CanTry(AItem) then
  begin
    Result.TryButton := FFrame.Add(TButton.Create(nil));
    Result.TryButton.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsTry);
    Result.TryButton.Tag := Length(FFrame.FRows);
    Result.TryButton.OnClick := FFrame.TryClick;
  end;
end;

function TWhatsNewRowBuilder.NewSwitch(const ASetting: string): TCheckBox;
var
  mSwitch: TAtlasWhatsNewSwitch;
begin
  Result := nil;
  mSwitch := TAtlasWhatsNewSwitch.None;
  if (FFrame.FSource <> nil) and (ASetting <> '') then
  begin
    mSwitch := FFrame.FSource.SwitchOf(ASetting);
  end;
  if mSwitch = TAtlasWhatsNewSwitch.None then
  begin
    Exit;
  end;
  Result := FFrame.Add(TCheckBox.Create(nil));
  Result.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsSwitch);
  Result.Checked := mSwitch = TAtlasWhatsNewSwitch.On;
  Result.Hint := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeNewsSwitchHint, [ASetting]);
  Result.ShowHint := True;
  Result.Tag := Length(FFrame.FRows);
  Result.OnClick := FFrame.SwitchClick;
end;

procedure TWhatsNewRowBuilder.AddDismiss;
begin
  if FFrame.FView = TAtlasWhatsNewView.Unread then
  begin
    FFrame.FDismiss := FFrame.Add(TButton.Create(nil));
    FFrame.FDismiss.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsRead);
  end
  else if FFrame.FView <> TAtlasWhatsNewView.Hidden then
  begin
    FFrame.FDismiss := FFrame.Add(TButton.Create(nil));
    FFrame.FDismiss.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsClose);
  end;
  if FFrame.FDismiss <> nil then
  begin
    FFrame.FDismiss.OnClick := FFrame.DismissClick;
  end;
end;

{ TAtlasWhatsNewMenu }

constructor TAtlasWhatsNewMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurrentItem := TMenuItem.Create(Self);
  FCurrentItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsShowCurrent);
  FCurrentItem.Tag := Ord(TAtlasWhatsNewView.Current);
  FCurrentItem.OnClick := ItemClick;
  Items.Add(FCurrentItem);
  FAllItem := TMenuItem.Create(Self);
  FAllItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsShowAll);
  FAllItem.Tag := Ord(TAtlasWhatsNewView.All);
  FAllItem.OnClick := ItemClick;
  Items.Add(FAllItem);
end;

procedure TAtlasWhatsNewMenu.ItemClick(Sender: TObject);
var
  View: TAtlasWhatsNewView;
  mSource: IAtlasWhatsNewSource;
begin
  View := TAtlasWhatsNewView(TMenuItem(Sender).Tag);
  mSource := FSource;
  // Die Quelle baut Karte und Bereiche neu; das Menü darf nicht in seinem eigenen Klick verschwinden.
  if mSource <> nil then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.Show(View);
      end);
  end;
end;

{ TAtlasWelcomeWhatsNewFrame }

constructor TAtlasWelcomeWhatsNewFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FControls := TObjectList<TControl>.Create(True);
  FExpanded := TDictionary<string, Boolean>.Create;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Body;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.ParentBackground := True;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.OnResize := ScrollResize;
  FMenu := TAtlasWhatsNewMenu.Create(Self);
  PopupMenu := FMenu;
  FView := TAtlasWhatsNewView.Hidden;
  Live.Add(Self);
end;

destructor TAtlasWelcomeWhatsNewFrame.Destroy;
begin
  Live.Remove(Self);
  if FMenu <> nil then
  begin
    FMenu.Source := nil;
  end;
  FreeAndNil(FControls);
  FreeAndNil(FExpanded);
  inherited;
end;

procedure TAtlasWelcomeWhatsNewFrame.SetSource(const AValue: IAtlasWhatsNewSource);
begin
  FSource := AValue;
  FMenu.Source := AValue;
  UpdateContent;
end;

class function TAtlasWelcomeWhatsNewFrame.TitleFor(AView: TAtlasWhatsNewView;
  const AVersions: TAtlasWhatsNewVersions): string;
begin
  if (AView <> TAtlasWhatsNewView.All) and (Length(AVersions) = 1) then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeNewsTitle, [AVersions[0].Version]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeNewsTitlePlain);
  end;
end;

class function TAtlasWelcomeWhatsNewFrame.HeadingText(const AVersion: string; ACollapsible,
  AExpanded: Boolean): string;
begin
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeNewsVersion, [AVersion]);
  if not ACollapsible then
  begin
    Exit;
  end;
  if AExpanded then
  begin
    Result := #$25BE' ' + Result;
  end
  else
  begin
    Result := #$25B8' ' + Result;
  end;
end;

function TAtlasWelcomeWhatsNewFrame.Collapsible: Boolean;
begin
  Result := FView = TAtlasWhatsNewView.All;
end;

function TAtlasWelcomeWhatsNewFrame.IsExpanded(const AVersion: string): Boolean;
begin
  if not Collapsible then
  begin
    Exit(True);
  end;
  if not FExpanded.TryGetValue(AVersion, Result) then
  begin
    Result := False;
  end;
end;

procedure TAtlasWelcomeWhatsNewFrame.Toggle(const AVersion: string);
begin
  if not Collapsible then
  begin
    Exit;
  end;
  FExpanded.AddOrSetValue(AVersion, not IsExpanded(AVersion));
  Build;
  HeightChanged;
end;

procedure TAtlasWelcomeWhatsNewFrame.Clear;
begin
  FRows := nil;
  FHeadings := nil;
  FHeadingVersions := nil;
  FDismiss := nil;
  FControls.Clear;
end;

function TAtlasWelcomeWhatsNewFrame.Add<T>(AControl: T): T;
begin
  Result := AControl;
  Result.Parent := FScroll;
  FControls.Add(Result);
end;

procedure TAtlasWelcomeWhatsNewFrame.UpdateContent;
var
  View: TAtlasWhatsNewView;
begin
  // Ohne Fenster später: Die Tafel ruft UpdateContent nach dem Einhängen.
  if not HasWindow then
  begin
    Exit;
  end;
  View := TAtlasWhatsNewView.Hidden;
  FVersions := nil;
  if FSource <> nil then
  begin
    View := FSource.View;
    FVersions := FSource.Versions;
  end;
  // Beim Wechsel nach „Alle Versionen“ ist nur die neueste aufgeklappt.
  if (View = TAtlasWhatsNewView.All) and (FView <> TAtlasWhatsNewView.All) then
  begin
    FExpanded.Clear;
    if Length(FVersions) > 0 then
    begin
      FExpanded.AddOrSetValue(FVersions[0].Version, True);
    end;
  end;
  FView := View;
  Build;
  inherited;
end;

procedure TAtlasWelcomeWhatsNewFrame.Build;
var
  mVersion: TAtlasWhatsNewVersion;
  mHeaded: Boolean;
  mBuilder: TWhatsNewRowBuilder;
begin
  mBuilder := TWhatsNewRowBuilder.Create(Self);
  FUpdating := True;
  try
    Clear;
    // Überschriften je Version, sobald es mehr als eine gibt oder alle gezeigt werden.
    mHeaded := (Length(FVersions) > 1) or Collapsible;
    for mVersion in FVersions do
    begin
      if mHeaded then
      begin
        mBuilder.AddHeading(mVersion.Version);
      end;
      if IsExpanded(mVersion.Version) then
      begin
        mBuilder.AddRows(mVersion);
      end;
    end;
    mBuilder.AddDismiss;
  finally
    FUpdating := False;
  end;
  Arrange;
end;

procedure TAtlasWelcomeWhatsNewFrame.ScrollResize(Sender: TObject);
begin
  Arrange;
end;

procedure TAtlasWelcomeWhatsNewFrame.Arrange;
var
  mWidth, mTop, Gap, ButtonH, Index: Integer;
  Version: TAtlasWhatsNewVersion;
  Row: TAtlasWhatsNewRow;

  procedure PlaceRow(const ARow: TAtlasWhatsNewRow);
  var
    mLeft, Right, Bottom: Integer;
  begin
    mLeft := ScaleValue(Indent);
    Right := mWidth - ScaleValue(Indent);
    if ARow.Section <> nil then
    begin
      ARow.Section.SetBounds(mLeft, mTop, ARow.Section.Width, ARow.Section.Height);
      Inc(mTop, ARow.Section.Height + Gap div 2);
    end;
    if ARow.TryButton <> nil then
    begin
      Dec(Right, ScaleValue(TryWidth));
      ARow.TryButton.SetBounds(Right, mTop, ScaleValue(TryWidth), ButtonH);
      Dec(Right, Gap);
    end;
    if ARow.Switch <> nil then
    begin
      Dec(Right, ScaleValue(SwitchWidth));
      ARow.Switch.SetBounds(Right, mTop + (ButtonH - ARow.Switch.Height) div 2, ScaleValue(SwitchWidth),
        ARow.Switch.Height);
      Dec(Right, Gap);
    end;
    ARow.Title.SetBounds(mLeft, mTop + (ButtonH - ARow.Title.Height) div 2, ARow.Title.Width, ARow.Title.Height);
    if ARow.Key <> nil then
    begin
      ARow.Key.SetBounds(mLeft + ARow.Title.Width + Gap, ARow.Title.Top, ARow.Key.Width, ARow.Key.Height);
    end;
    Bottom := mTop + ButtonH;
    if ARow.Text <> nil then
    begin
      // Breite zuerst: Das Label bricht danach um und passt seine Höhe an.
      ARow.Text.Width := Max(Right - mLeft, ScaleValue(120));
      // AutoSize neu setzen: Erst das misst den umbrochenen Text für die neue Breite.
      ARow.Text.AutoSize := False;
      ARow.Text.AutoSize := True;
      ARow.Text.Left := mLeft;
      ARow.Text.Top := Bottom + 2;
      Bottom := ARow.Text.Top + ARow.Text.Height;
    end;
    mTop := Bottom + Gap;
  end;

begin
  if FArranging or (FControls = nil) then
  begin
    Exit;
  end;
  FArranging := True;
  try
    Gap := ScaleValue(RowGap);
    ButtonH := ScaleValue(ButtonHeight);
    // Breite des Frames statt der Scrollbox: Die richtet sich erst später nach dem Frame aus.
    mWidth := ClientWidth;
    if FScroll.VertScrollBar.IsScrollBarVisible then
    begin
      Dec(mWidth, GetSystemMetrics(SM_CXVSCROLL));
    end;
    mTop := Gap div 2 - FScroll.VertScrollBar.Position;
    for Version in FVersions do
    begin
      for Index := 0 to High(FHeadings) do
      begin
        if FHeadingVersions[Index] = Version.Version then
        begin
          FHeadings[Index].SetBounds(ScaleValue(Indent), mTop, FHeadings[Index].Width, FHeadings[Index].Height);
          Inc(mTop, FHeadings[Index].Height + Gap div 2);
        end;
      end;
      for Row in FRows do
      begin
        if Row.Version = Version.Version then
        begin
          PlaceRow(Row);
        end;
      end;
    end;
    if FDismiss <> nil then
    begin
      FDismiss.SetBounds(mWidth - ScaleValue(Indent) - ScaleValue(TryWidth), mTop, ScaleValue(TryWidth), ButtonH);
      Inc(mTop, ButtonH + Gap div 2);
    end;
    FContentHeight := mTop + FScroll.VertScrollBar.Position;
  finally
    FArranging := False;
  end;
end;

function TAtlasWelcomeWhatsNewFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  Arrange;
  Result := FContentHeight;
  if Result < ScaleValue(40) then
  begin
    Result := ScaleValue(40);
  end;
end;

procedure TAtlasWelcomeWhatsNewFrame.HeadingClick(Sender: TObject);
var
  Version: string;
  Frame: TAtlasWelcomeWhatsNewFrame;
begin
  Version := FHeadingVersions[TLabel(Sender).Tag];
  Frame := Self;
  // Nicht im Klick des Labels neu bauen: Toggle gibt es frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Live.Contains(Frame) then
      begin
        Frame.Toggle(Version);
      end;
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.SwitchClick(Sender: TObject);
var
  mSource: IAtlasWhatsNewSource;
  Setting: string;
  Value: Boolean;
begin
  if FUpdating or (FSource = nil) then
  begin
    Exit;
  end;
  mSource := FSource;
  Setting := FRows[TCheckBox(Sender).Tag].Item.Setting;
  Value := TCheckBox(Sender).Checked;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.SetSwitch(Setting, Value);
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.TryClick(Sender: TObject);
var
  mSource: IAtlasWhatsNewSource;
  Item: TAtlasWhatsNewItem;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  Item := FRows[TButton(Sender).Tag].Item;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.TryItem(Item);
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.DismissClick(Sender: TObject);
var
  mSource: IAtlasWhatsNewSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Dismiss;
    end);
end;

initialization
  Live := TList<TAtlasWelcomeWhatsNewFrame>.Create;

finalization
  FreeAndNil(Live);

end.
