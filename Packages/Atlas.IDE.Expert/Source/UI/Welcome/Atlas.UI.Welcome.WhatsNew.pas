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
  Atlas.UI.Strings;

var
  // Lebende Karten: Klicks auf Überschriften wirken über die Nachrichtenschleife, die Karte kann bis dahin frei
  // sein.
  Live: TList<TAtlasWelcomeWhatsNewFrame>;

{ TAtlasWhatsNewMenu }

constructor TAtlasWhatsNewMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurrentItem := TMenuItem.Create(Self);
  FCurrentItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsShowCurrent);
  FCurrentItem.Tag := Ord(TAtlasWhatsNewView.Current);
  FCurrentItem.OnClick := ItemClick;
  Items.Add(FCurrentItem);
  FAllItem := TMenuItem.Create(Self);
  FAllItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsShowAll);
  FAllItem.Tag := Ord(TAtlasWhatsNewView.All);
  FAllItem.OnClick := ItemClick;
  Items.Add(FAllItem);
end;

procedure TAtlasWhatsNewMenu.ItemClick(Sender: TObject);
var
  View: TAtlasWhatsNewView;
  Source: IAtlasWhatsNewSource;
begin
  View := TAtlasWhatsNewView(TMenuItem(Sender).Tag);
  Source := FSource;
  // Die Quelle baut Karte und Bereiche neu; das Menü darf nicht in seinem eigenen Klick verschwinden.
  if Source <> nil then
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        Source.Show(View);
      end);
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
    FMenu.Source := nil;
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
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsTitle, [AVersions[0].Version])
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsTitlePlain);
end;

class function TAtlasWelcomeWhatsNewFrame.HeadingText(const AVersion: string; ACollapsible,
  AExpanded: Boolean): string;
begin
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsVersion, [AVersion]);
  if not ACollapsible then
    Exit;
  if AExpanded then
    Result := #$25BE' ' + Result
  else
    Result := #$25B8' ' + Result;
end;

function TAtlasWelcomeWhatsNewFrame.Collapsible: Boolean;
begin
  Result := FView = TAtlasWhatsNewView.All;
end;

function TAtlasWelcomeWhatsNewFrame.IsExpanded(const AVersion: string): Boolean;
begin
  if not Collapsible then
    Exit(True);
  if not FExpanded.TryGetValue(AVersion, Result) then
    Result := False;
end;

procedure TAtlasWelcomeWhatsNewFrame.Toggle(const AVersion: string);
begin
  if not Collapsible then
    Exit;
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
    Exit;
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
      FExpanded.AddOrSetValue(FVersions[0].Version, True);
  end;
  FView := View;
  Build;
  inherited;
end;

procedure TAtlasWelcomeWhatsNewFrame.Build;
var
  Version: TAtlasWhatsNewVersion;
  Item: TAtlasWhatsNewItem;
  Row: TAtlasWhatsNewRow;
  Heading: TLabel;
  Switch: TAtlasWhatsNewSwitch;
  KeyText: string;
  Headed, InExperimental: Boolean;
  Section: TLabel;
begin
  FUpdating := True;
  try
    Clear;
    // Überschriften je Version, sobald es mehr als eine gibt oder alle gezeigt werden.
    Headed := (Length(FVersions) > 1) or Collapsible;
    for Version in FVersions do
    begin
      if Headed then
      begin
        Heading := Add(TLabel.Create(nil));
        Heading.Caption := HeadingText(Version.Version, Collapsible, IsExpanded(Version.Version));
        Heading.Font.Style := [fsBold];
        if Collapsible then
        begin
          Heading.Cursor := crHandPoint;
          Heading.OnClick := HeadingClick;
        end;
        Heading.Tag := Length(FHeadings);
        FHeadings := FHeadings + [Heading];
        FHeadingVersions := FHeadingVersions + [Version.Version];
      end;
      if not IsExpanded(Version.Version) then
        Continue;
      InExperimental := False;
      // Experimentelle Einträge nach den übrigen unter eigener Überschrift (#834).
      for Item in TAtlasWhatsNew.Ordered(Version.Items) do
      begin
        Section := nil;
        if Item.Experimental and not InExperimental then
        begin
          InExperimental := True;
          Section := Add(TLabel.Create(nil));
          Section.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsExperimental);
          Section.Font.Style := [fsItalic];
          Section.Font.Color := clGrayText;
        end;
        Row := Default(TAtlasWhatsNewRow);
        Row.Section := Section;
        Row.Version := Version.Version;
        Row.Item := Item;
        Row.Title := Add(TLabel.Create(nil));
        Row.Title.Caption := Item.Title;
        Row.Title.Font.Style := [fsBold];
        KeyText := '';
        if (FSource <> nil) and (Item.Key <> '') then
          KeyText := FSource.KeyText(Item.Key);
        if KeyText <> '' then
        begin
          Row.Key := Add(TLabel.Create(nil));
          Row.Key.Caption := KeyText;
          Row.Key.Font.Color := clGrayText;
        end;
        if Item.Text <> '' then
        begin
          Row.Text := Add(TLabel.Create(nil));
          Row.Text.AutoSize := True;
          Row.Text.WordWrap := True;
          Row.Text.Caption := Item.Text;
        end;
        Switch := TAtlasWhatsNewSwitch.None;
        if (FSource <> nil) and (Item.Setting <> '') then
          Switch := FSource.SwitchOf(Item.Setting);
        if Switch <> TAtlasWhatsNewSwitch.None then
        begin
          Row.Switch := Add(TCheckBox.Create(nil));
          Row.Switch.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsSwitch);
          Row.Switch.Checked := Switch = TAtlasWhatsNewSwitch.On;
          Row.Switch.Hint := TAtlasStrings.Fmt(TAtlasTextId.WelcomeNewsSwitchHint, [Item.Setting]);
          Row.Switch.ShowHint := True;
          Row.Switch.Tag := Length(FRows);
          Row.Switch.OnClick := SwitchClick;
        end;
        if (FSource <> nil) and FSource.CanTry(Item) then
        begin
          Row.TryButton := Add(TButton.Create(nil));
          Row.TryButton.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsTry);
          Row.TryButton.Tag := Length(FRows);
          Row.TryButton.OnClick := TryClick;
        end;
        FRows := FRows + [Row];
      end;
    end;
    if FView = TAtlasWhatsNewView.Unread then
    begin
      FDismiss := Add(TButton.Create(nil));
      FDismiss.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsRead);
    end
    else if FView <> TAtlasWhatsNewView.Hidden then
    begin
      FDismiss := Add(TButton.Create(nil));
      FDismiss.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeNewsClose);
    end;
    if FDismiss <> nil then
      FDismiss.OnClick := DismissClick;
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
  Width, Top, Gap, ButtonH, Index: Integer;
  Version: TAtlasWhatsNewVersion;
  Row: TAtlasWhatsNewRow;

  procedure PlaceRow(const ARow: TAtlasWhatsNewRow);
  var
    Left, Right, Bottom: Integer;
  begin
    Left := ScaleValue(Indent);
    Right := Width - ScaleValue(Indent);
    if ARow.Section <> nil then
    begin
      ARow.Section.SetBounds(Left, Top, ARow.Section.Width, ARow.Section.Height);
      Inc(Top, ARow.Section.Height + Gap div 2);
    end;
    if ARow.TryButton <> nil then
    begin
      Dec(Right, ScaleValue(TryWidth));
      ARow.TryButton.SetBounds(Right, Top, ScaleValue(TryWidth), ButtonH);
      Dec(Right, Gap);
    end;
    if ARow.Switch <> nil then
    begin
      Dec(Right, ScaleValue(SwitchWidth));
      ARow.Switch.SetBounds(Right, Top + (ButtonH - ARow.Switch.Height) div 2, ScaleValue(SwitchWidth),
        ARow.Switch.Height);
      Dec(Right, Gap);
    end;
    ARow.Title.SetBounds(Left, Top + (ButtonH - ARow.Title.Height) div 2, ARow.Title.Width, ARow.Title.Height);
    if ARow.Key <> nil then
      ARow.Key.SetBounds(Left + ARow.Title.Width + Gap, ARow.Title.Top, ARow.Key.Width, ARow.Key.Height);
    Bottom := Top + ButtonH;
    if ARow.Text <> nil then
    begin
      // Breite zuerst: Das Label bricht danach um und passt seine Höhe an.
      ARow.Text.Width := Max(Right - Left, ScaleValue(120));
      // AutoSize neu setzen: Erst das misst den umbrochenen Text für die neue Breite.
      ARow.Text.AutoSize := False;
      ARow.Text.AutoSize := True;
      ARow.Text.Left := Left;
      ARow.Text.Top := Bottom + 2;
      Bottom := ARow.Text.Top + ARow.Text.Height;
    end;
    Top := Bottom + Gap;
  end;

begin
  if FArranging or (FControls = nil) then
    Exit;
  FArranging := True;
  try
    Gap := ScaleValue(RowGap);
    ButtonH := ScaleValue(ButtonHeight);
    // Breite des Frames statt der Scrollbox: Die richtet sich erst später nach dem Frame aus.
    Width := ClientWidth;
    if FScroll.VertScrollBar.IsScrollBarVisible then
      Dec(Width, GetSystemMetrics(SM_CXVSCROLL));
    Top := Gap div 2 - FScroll.VertScrollBar.Position;
    for Version in FVersions do
    begin
      for Index := 0 to High(FHeadings) do
        if FHeadingVersions[Index] = Version.Version then
        begin
          FHeadings[Index].SetBounds(ScaleValue(Indent), Top, FHeadings[Index].Width, FHeadings[Index].Height);
          Inc(Top, FHeadings[Index].Height + Gap div 2);
        end;
      for Row in FRows do
        if Row.Version = Version.Version then
          PlaceRow(Row);
    end;
    if FDismiss <> nil then
    begin
      FDismiss.SetBounds(Width - ScaleValue(Indent) - ScaleValue(TryWidth), Top, ScaleValue(TryWidth), ButtonH);
      Inc(Top, ButtonH + Gap div 2);
    end;
    FContentHeight := Top + FScroll.VertScrollBar.Position;
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
    Result := ScaleValue(40);
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
        Frame.Toggle(Version);
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.SwitchClick(Sender: TObject);
var
  Source: IAtlasWhatsNewSource;
  Setting: string;
  Value: Boolean;
begin
  if FUpdating or (FSource = nil) then
    Exit;
  Source := FSource;
  Setting := FRows[TCheckBox(Sender).Tag].Item.Setting;
  Value := TCheckBox(Sender).Checked;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.SetSwitch(Setting, Value);
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.TryClick(Sender: TObject);
var
  Source: IAtlasWhatsNewSource;
  Item: TAtlasWhatsNewItem;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  Item := FRows[TButton(Sender).Tag].Item;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.TryItem(Item);
    end);
end;

procedure TAtlasWelcomeWhatsNewFrame.DismissClick(Sender: TObject);
var
  Source: IAtlasWhatsNewSource;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Dismiss;
    end);
end;

initialization
  Live := TList<TAtlasWelcomeWhatsNewFrame>.Create;

finalization
  FreeAndNil(Live);

end.
