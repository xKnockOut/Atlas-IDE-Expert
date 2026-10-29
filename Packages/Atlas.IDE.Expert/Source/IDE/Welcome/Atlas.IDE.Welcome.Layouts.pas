unit Atlas.IDE.Welcome.Layouts;

// Quelle für „Seite anpassen“ (#767): verbindet die Tafel (Willkommensseite
// und „Atlas-Start“) mit den gespeicherten Plugin-Einstellungen.
// - Anordnung, Breite, Spalten und Layouts landen über
//   TAtlasWelcomeCustomizing in welcomePage.layouts/.activeLayout/.columns.
// - Ein- und Ausblenden setzt die Einstellung des Bereichs (Auge direkt,
//   Rechtsklick über den Weg von #628 mit „Rückgängig“); ein Schnellschalter
//   „an für diese Sitzung“ wird dabei aufgehoben, sonst hielte er den
//   Bereich sichtbar.
// - Neue Bereiche einer späteren Version kommen ans Ende der Spalte mit dem
//   meisten Platz; ist schon ein eigenes Layout gespeichert, wird das
//   gespeichert und in „Neu in Atlas“ (#756) gemeldet (OnAnnounce).
// - Der Bearbeitungsmodus gilt für alle Tafeln zugleich und lebt nur in der
//   Sitzung.
// Rechtsklick „Ausblenden“ und „Einstellungen dazu …“ kommen als Hooks aus
// der Komposition (TAtlasIdeHide), damit Welcome nicht vom Editor abhängt.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts,
  Atlas.UI.Welcome.Arrange;

type
  TAtlasIdeWelcomeLayouts = class(TInterfacedObject, IAtlasWelcomeArrangeSource)
  public const
    /// <summary>Befehl der Befehlspalette: Bearbeitungsmodus an/aus.</summary>
    CommandId = 'Atlas.WelcomeCustomize';
  private
    FEditing: Boolean;
    FRefresh: TProc;
    FOnAnnounce: TProc<TArray<string>>;
    FOnHideSetting: TFunc<string, TPoint, Boolean>;
    FOnShowSetting: TProc<string>;
    FAdopting: Boolean;
    procedure Save(const ASettings: TAtlasPluginSettings);
    procedure DropSession(const AId: string);
    function Registered: TArray<string>;
  public
    /// <summary>ARefresh: Tafeln neu füllen (TAtlasIdeWelcome.Sync).</summary>
    constructor Create(const ARefresh: TProc);
    /// <summary>Layout für die Tafeln: mit welcomePage.customLayout das aktive (neue Bereiche ans Ende der
    /// Spalte mit dem meisten Platz, AWeight = Höhe), sonst das feste Atlas-Layout (#753).</summary>
    function BoardLayout(const AWeight: TAtlasWelcomeWeight): TAtlasWelcomeLayout;
    /// <summary>Kurze Beschreibung eines Bereichs für „Bereich hinzufügen“.</summary>
    class function Description(const AId: string): string; static;
    { IAtlasWelcomeArrangeSource }
    function CanCustomize: Boolean;
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    procedure HideSection(const AId: string);
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    function DeleteLayout: Boolean;
    procedure ResetLayout;
    /// <summary>Neue Bereiche (Kennungen), nachdem sie in das gespeicherte Layout aufgenommen wurden.</summary>
    property OnAnnounce: TProc<TArray<string>> read FOnAnnounce write FOnAnnounce;
    /// <summary>Einstellung (Registry-Name) mit „Rückgängig“ an der Bildschirmstelle ausschalten.</summary>
    property OnHideSetting: TFunc<string, TPoint, Boolean> read FOnHideSetting write FOnHideSetting;
    /// <summary>Optionsseite mit der Einstellung (Registry-Name).</summary>
    property OnShowSetting: TProc<string> read FOnShowSetting write FOnShowSetting;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeWelcomeLayouts }

constructor TAtlasIdeWelcomeLayouts.Create(const ARefresh: TProc);
begin
  inherited Create;
  FRefresh := ARefresh;
end;

class function TAtlasIdeWelcomeLayouts.Description(const AId: string): string;
begin
  if SameText(AId, TAtlasWelcomeIds.Continue) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescContinue)
  else if SameText(AId, TAtlasWelcomeIds.Projects) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescProjects)
  else if SameText(AId, TAtlasWelcomeIds.History) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescHistory)
  else if SameText(AId, TAtlasWelcomeIds.Tests) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescTests)
  else if SameText(AId, TAtlasWelcomeIds.State) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescState)
  else if SameText(AId, TAtlasWelcomeIds.Unsaved) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescUnsaved)
  else if SameText(AId, TAtlasWelcomeIds.News) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescNews)
  else if SameText(AId, TAtlasWelcomeIds.Discover) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescDiscover)
  else if SameText(AId, TAtlasWelcomeIds.Setup) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescSetup)
  else if SameText(AId, TAtlasWelcomeIds.Issues) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescIssues)
  else if SameText(AId, TAtlasWelcomeIds.Sprint) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescSprint)
  else if SameText(AId, TAtlasWelcomeIds.Help) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeDescHelp)
  else
    Result := '';
end;

function TAtlasIdeWelcomeLayouts.Registered: TArray<string>;
var
  Section: TAtlasWelcomeSection;
begin
  // Auch ausgeschaltete Bereiche: Sie sind angemeldet, ihr Schalter ist nur aus.
  Result := nil;
  for Section in TAtlasWelcomeSections.Default.All do
    Result := Result + [Section.Id];
end;

function TAtlasIdeWelcomeLayouts.BoardLayout(const AWeight: TAtlasWelcomeWeight): TAtlasWelcomeLayout;
var
  Current: TAtlasPluginSettings;
  Added: TArray<string>;
  Ids: TArray<string>;
  Adopted: TAtlasWelcomeLayout;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Current := TAtlasIdeSettings.Current;
  if not Current.WelcomePageCustomLayout then
    Exit(TAtlasWelcomeLayout.Atlas);
  Ids := Registered;
  Result := TAtlasWelcomeCustomizing.Load(Current).Current.Adopted(Ids, AWeight, Added);
  if (Length(Added) = 0) or FAdopting or (Trim(TAtlasIdeSettings.Stored.WelcomePageLayouts) = '') then
    Exit;
  // Ein eigenes Layout ist gespeichert: neue Bereiche dort aufnehmen und melden. Nicht mitten im Füllen der
  // Tafel speichern, das füllte sie gleich noch einmal.
  FAdopting := True;
  Adopted := Result;
  // Hält die Quelle bis zum Eintrag in der Warteschlange am Leben.
  Keep := Self;
  // Den Platz von eben speichern (die Gewichte kennen nur die Tafeln, die bis dahin weg sein können).
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    var
      Stored: TAtlasPluginSettings;
    begin
      FAdopting := False;
      if Keep = nil then
        Exit;
      Stored := TAtlasIdeSettings.Stored;
      Save(TAtlasWelcomeCustomizing.Stored(Stored, TAtlasWelcomeCustomizing.Load(Stored).WithCurrent(Adopted)));
      if Assigned(FOnAnnounce) then
        FOnAnnounce(Added);
    end);
end;

procedure TAtlasIdeWelcomeLayouts.Save(const ASettings: TAtlasPluginSettings);
begin
  // Update meldet die Änderung; die Komposition füllt daraufhin die Tafeln neu (Sync).
  TAtlasIdeSettings.Update(ASettings);
end;

procedure TAtlasIdeWelcomeLayouts.DropSession(const AId: string);
var
  Session: TAtlasToggleSession;
  Key: string;
  Value: Boolean;
begin
  // Ein Schnellschalter für diese Sitzung überdeckt die gespeicherte Einstellung; Auge und Leiste meinen sie.
  Key := TAtlasWelcomeCustomizing.SettingOf(AId);
  Session := TAtlasIdeSettings.Session;
  if (Key = '') or not Session.TryGet(Key, Value) then
    Exit;
  Session.Drop(Key);
  TAtlasIdeSettings.SetSession(Session);
end;

function TAtlasIdeWelcomeLayouts.CanCustomize: Boolean;
var
  Current: TAtlasPluginSettings;
begin
  Current := TAtlasIdeSettings.Current;
  Result := Current.WelcomePage and Current.WelcomePageCustomLayout;
end;

function TAtlasIdeWelcomeLayouts.Editing: Boolean;
begin
  Result := FEditing and CanCustomize;
end;

procedure TAtlasIdeWelcomeLayouts.SetEditing(AOn: Boolean);
begin
  if FEditing = AOn then
    Exit;
  FEditing := AOn;
  if Assigned(FRefresh) then
    FRefresh();
end;

function TAtlasIdeWelcomeLayouts.LayoutNames: TArray<string>;
begin
  Result := TAtlasWelcomeCustomizing.Load(TAtlasIdeSettings.Stored).Names;
end;

function TAtlasIdeWelcomeLayouts.ActiveLayout: string;
begin
  Result := TAtlasWelcomeCustomizing.Load(TAtlasIdeSettings.Stored).ActiveName;
end;

function TAtlasIdeWelcomeLayouts.Catalog: TArray<TAtlasWelcomeCatalogEntry>;
var
  Item: TAtlasWelcomeCatalogItem;
  Section: TAtlasWelcomeSection;
  Current: TAtlasPluginSettings;
begin
  Result := nil;
  Current := TAtlasIdeSettings.Current;
  for Item in TAtlasWelcomeCustomizing.Catalog do
    // Nur angemeldete Bereiche; dazu gehören auch die, die noch nie gezeigt wurden (Schalter aus).
    if TAtlasWelcomeSections.Default.Find(Item.Id, Section) then
      Result := Result + [TAtlasWelcomeCatalogEntry.Create(Item.Id, Section.Title, Description(Item.Id),
        TAtlasWelcomeCustomizing.IsOn(Current, Item.Id))];
end;

procedure TAtlasIdeWelcomeLayouts.Arrange(const ALayout: TAtlasWelcomeLayout);
var
  Stored, Next: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  Stored := TAtlasIdeSettings.Stored;
  Layouts := TAtlasWelcomeCustomizing.Load(Stored);
  Next := TAtlasWelcomeCustomizing.Stored(Stored, Layouts.WithCurrent(ALayout));
  if (Next.WelcomePageLayouts <> Stored.WelcomePageLayouts) or (Next.WelcomePageColumns <> Stored.WelcomePageColumns)
    or (Next.WelcomePageActiveLayout <> Stored.WelcomePageActiveLayout) then
    Save(Next);
end;

procedure TAtlasIdeWelcomeLayouts.ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
var
  Stored: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  if not TAtlasWelcomeCustomizing.InCatalog(AId) then
    Exit;
  Stored := TAtlasIdeSettings.Stored;
  Layouts := TAtlasWelcomeCustomizing.Load(Stored);
  // Erst an die Einfügelinie, dann sichtbar: Stored nimmt die Sichtbarkeit aus den Einstellungen.
  Layouts := Layouts.WithCurrent(Layouts.Current.MovedTo(AId, AColumn, ABefore));
  Stored := TAtlasWelcomeCustomizing.WithSection(Stored, AId, True);
  DropSession(AId);
  Save(TAtlasWelcomeCustomizing.Stored(Stored, Layouts));
end;

procedure TAtlasIdeWelcomeLayouts.HideSection(const AId: string);
var
  Stored: TAtlasPluginSettings;
begin
  if not TAtlasWelcomeCustomizing.InCatalog(AId) then
    Exit;
  Stored := TAtlasWelcomeCustomizing.WithSection(TAtlasIdeSettings.Stored, AId, False);
  DropSession(AId);
  // Das aktive Layout merkt sich die Sichtbarkeit mit (mehrere Layouts).
  Save(TAtlasWelcomeCustomizing.Stored(Stored, TAtlasWelcomeCustomizing.Load(Stored)));
end;

procedure TAtlasIdeWelcomeLayouts.HideSectionAt(const AId: string; const APoint: TPoint);
var
  Key: string;
begin
  Key := TAtlasWelcomeCustomizing.SettingOf(AId);
  if Key = '' then
    Exit;
  // Ohne den Weg von #628 (Funktion nicht gestartet) wie das Auge.
  if not (Assigned(FOnHideSetting) and FOnHideSetting(Key, APoint)) then
    HideSection(AId);
end;

procedure TAtlasIdeWelcomeLayouts.ShowSectionSettings(const AId: string);
var
  Key: string;
begin
  Key := TAtlasWelcomeCustomizing.SettingOf(AId);
  if (Key <> '') and Assigned(FOnShowSetting) then
    FOnShowSetting(Key);
end;

procedure TAtlasIdeWelcomeLayouts.SwitchLayout(const AName: string);
var
  Stored, Next: TAtlasPluginSettings;
begin
  Stored := TAtlasIdeSettings.Stored;
  Next := TAtlasWelcomeCustomizing.Switched(Stored, AName);
  if Next.WelcomePageActiveLayout <> Stored.WelcomePageActiveLayout then
    Save(Next);
end;

function TAtlasIdeWelcomeLayouts.AddLayout(const AName: string): Boolean;
var
  Stored: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  Stored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(Stored).Added(AName, Layouts);
  if Result then
    Save(TAtlasWelcomeCustomizing.Stored(Stored, Layouts));
end;

function TAtlasIdeWelcomeLayouts.RenameLayout(const AName: string): Boolean;
var
  Stored: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  Stored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(Stored).Renamed(AName, Layouts);
  if Result then
    Save(TAtlasWelcomeCustomizing.Stored(Stored, Layouts));
end;

function TAtlasIdeWelcomeLayouts.DeleteLayout: Boolean;
var
  Stored: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
begin
  Stored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(Stored).Deleted(Layouts);
  // Das Layout danach bringt seine Sichtbarkeit mit.
  if Result then
    Save(TAtlasWelcomeCustomizing.Applied(Stored, Layouts));
end;

procedure TAtlasIdeWelcomeLayouts.ResetLayout;
begin
  Save(TAtlasWelcomeCustomizing.Reset(TAtlasIdeSettings.Stored));
end;

end.
