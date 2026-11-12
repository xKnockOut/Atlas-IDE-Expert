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
  Atlas.UI.Welcome.Arrange;

type
  TAtlasIdeWelcomeLayouts = class(TInterfacedObject, IAtlasWelcomeArrangeSource)
  public const
    /// <summary>Befehl der Befehlspalette: Bearbeitungsmodus an/aus.</summary>
    cCommandId = 'Atlas.WelcomeCustomize';
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
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.QuickToggles,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Strings,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeWelcomeLayouts }

constructor TAtlasIdeWelcomeLayouts.Create(const ARefresh: TProc);
begin
  inherited Create;
  FRefresh := ARefresh;
end;

/// <summary>Beschreibung, die der Bereich selbst mitbringt (Kacheln anderer Module, #1455); '' ohne.</summary>
function DescriptionOfSection(const AId: string): string;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := '';
  if TAtlasWelcomeSections.Default.Find(AId, mSection) then
  begin
    Result := mSection.Description;
  end;
end;

class function TAtlasIdeWelcomeLayouts.Description(const AId: string): string;
begin
  if SameText(AId, TAtlasWelcomeIds.cContinue) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescContinue);
  end
  else if SameText(AId, TAtlasWelcomeIds.cProjects) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescProjects);
  end
  else if SameText(AId, TAtlasWelcomeIds.cHistory) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescHistory);
  end
  else if SameText(AId, TAtlasWelcomeIds.cTests) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescTests);
  end
  else if SameText(AId, TAtlasWelcomeIds.cState) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescState);
  end
  else if SameText(AId, TAtlasWelcomeIds.cUnsaved) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescUnsaved);
  end
  else if SameText(AId, TAtlasWelcomeIds.cNews) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescNews);
  end
  else if SameText(AId, TAtlasWelcomeIds.cDiscover) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescDiscover);
  end
  else if SameText(AId, TAtlasWelcomeIds.cSetup) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescSetup);
  end
  else if SameText(AId, TAtlasWelcomeIds.cIssues) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescIssues);
  end
  else if SameText(AId, TAtlasWelcomeIds.cSprint) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescSprint);
  end
  else if SameText(AId, TAtlasWelcomeIds.cHelp) then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDescHelp);
  end
  else
  begin
    Result := DescriptionOfSection(AId);
  end;
end;

function TAtlasIdeWelcomeLayouts.Registered: TArray<string>;
var
  mSection: TAtlasWelcomeSection;
begin
  // Auch ausgeschaltete Bereiche: Sie sind angemeldet, ihr Schalter ist nur aus.
  Result := nil;
  for mSection in TAtlasWelcomeSections.Default.All do
  begin
    Result := Result + [mSection.Id];
  end;
end;

function TAtlasIdeWelcomeLayouts.BoardLayout(const AWeight: TAtlasWelcomeWeight): TAtlasWelcomeLayout;
var
  mCurrent: TAtlasPluginSettings;
  mAdded: TArray<string>;
  mIds: TArray<string>;
  mAdopted: TAtlasWelcomeLayout;
  mKeep: IAtlasWelcomeArrangeSource;
begin
  mCurrent := TAtlasIdeSettings.Current;
  if not mCurrent.WelcomePageCustomLayout then
  begin
    Exit(TAtlasWelcomeLayout.Atlas);
  end;
  mIds := Registered;
  Result := TAtlasWelcomeCustomizing.Load(mCurrent).Current.Adopted(mIds, AWeight, mAdded);
  if (Length(mAdded) = 0) or FAdopting or (Trim(TAtlasIdeSettings.Stored.WelcomePageLayouts) = '') then
  begin
    Exit;
  end;
  // Ein eigenes Layout ist gespeichert: neue Bereiche dort aufnehmen und melden. Nicht mitten im Füllen der
  // Tafel speichern, das füllte sie gleich noch einmal.
  FAdopting := True;
  mAdopted := Result;
  // Hält die Quelle bis zum Eintrag in der Warteschlange am Leben.
  mKeep := Self;
  // Den Platz von eben speichern (die Gewichte kennen nur die Tafeln, die bis dahin weg sein können).
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    var
      Stored: TAtlasPluginSettings;
    begin
      FAdopting := False;
      if mKeep = nil then
      begin
        Exit;
      end;
      Stored := TAtlasIdeSettings.Stored;
      Save(TAtlasWelcomeCustomizing.Stored(Stored, TAtlasWelcomeCustomizing.Load(Stored).WithCurrent(mAdopted)));
      if Assigned(FOnAnnounce) then
      begin
        FOnAnnounce(mAdded);
      end;
    end);
end;

procedure TAtlasIdeWelcomeLayouts.Save(const ASettings: TAtlasPluginSettings);
begin
  // Update meldet die Änderung; die Komposition füllt daraufhin die Tafeln neu (Sync).
  TAtlasIdeSettings.Update(ASettings);
end;

procedure TAtlasIdeWelcomeLayouts.DropSession(const AId: string);
var
  mSession: TAtlasToggleSession;
  mKey: string;
  mValue: Boolean;
begin
  // Ein Schnellschalter für diese Sitzung überdeckt die gespeicherte Einstellung; Auge und Leiste meinen sie.
  mKey := TAtlasWelcomeCustomizing.SettingOf(AId);
  mSession := TAtlasIdeSettings.Session;
  if (mKey = '') or not mSession.TryGet(mKey, mValue) then
  begin
    Exit;
  end;
  mSession.Drop(mKey);
  TAtlasIdeSettings.SetSession(mSession);
end;

function TAtlasIdeWelcomeLayouts.CanCustomize: Boolean;
var
  mCurrent: TAtlasPluginSettings;
begin
  mCurrent := TAtlasIdeSettings.Current;
  Result := mCurrent.WelcomePage and mCurrent.WelcomePageCustomLayout;
end;

function TAtlasIdeWelcomeLayouts.Editing: Boolean;
begin
  Result := FEditing and CanCustomize;
end;

procedure TAtlasIdeWelcomeLayouts.SetEditing(AOn: Boolean);
begin
  if FEditing = AOn then
  begin
    Exit;
  end;
  FEditing := AOn;
  if Assigned(FRefresh) then
  begin
    FRefresh();
  end;
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
  mItem: TAtlasWelcomeCatalogItem;
  mSection: TAtlasWelcomeSection;
  mCurrent: TAtlasPluginSettings;
begin
  Result := nil;
  mCurrent := TAtlasIdeSettings.Current;
  for mItem in TAtlasWelcomeCustomizing.Catalog do
  begin
    // Nur angemeldete Bereiche; dazu gehören auch die, die noch nie gezeigt wurden (Schalter aus).
    if TAtlasWelcomeSections.Default.Find(mItem.Id, mSection) then
    begin
      Result := Result + [TAtlasWelcomeCatalogEntry.Create(mItem.Id, mSection.Title, Description(mItem.Id),
        TAtlasWelcomeCustomizing.IsOn(mCurrent, mItem.Id))];
    end;
  end;
end;

procedure TAtlasIdeWelcomeLayouts.Arrange(const ALayout: TAtlasWelcomeLayout);
var
  mStored, mNext: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mStored := TAtlasIdeSettings.Stored;
  mLayouts := TAtlasWelcomeCustomizing.Load(mStored);
  mNext := TAtlasWelcomeCustomizing.Stored(mStored, mLayouts.WithCurrent(ALayout));
  if (mNext.WelcomePageLayouts <> mStored.WelcomePageLayouts) or
    (mNext.WelcomePageColumns <> mStored.WelcomePageColumns)
    or (mNext.WelcomePageActiveLayout <> mStored.WelcomePageActiveLayout) then
  begin
    Save(mNext);
  end;
end;

procedure TAtlasIdeWelcomeLayouts.ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
var
  mStored: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  if not TAtlasWelcomeCustomizing.InCatalog(AId) then
  begin
    Exit;
  end;
  mStored := TAtlasIdeSettings.Stored;
  mLayouts := TAtlasWelcomeCustomizing.Load(mStored);
  // Erst an die Einfügelinie, dann sichtbar: Stored nimmt die Sichtbarkeit aus den Einstellungen.
  mLayouts := mLayouts.WithCurrent(mLayouts.Current.MovedTo(AId, AColumn, ABefore));
  mStored := TAtlasWelcomeCustomizing.WithSection(mStored, AId, True);
  DropSession(AId);
  Save(TAtlasWelcomeCustomizing.Stored(mStored, mLayouts));
end;

procedure TAtlasIdeWelcomeLayouts.HideSection(const AId: string);
var
  mStored: TAtlasPluginSettings;
begin
  if not TAtlasWelcomeCustomizing.InCatalog(AId) then
  begin
    Exit;
  end;
  mStored := TAtlasWelcomeCustomizing.WithSection(TAtlasIdeSettings.Stored, AId, False);
  DropSession(AId);
  // Das aktive Layout merkt sich die Sichtbarkeit mit (mehrere Layouts).
  Save(TAtlasWelcomeCustomizing.Stored(mStored, TAtlasWelcomeCustomizing.Load(mStored)));
end;

procedure TAtlasIdeWelcomeLayouts.HideSectionAt(const AId: string; const APoint: TPoint);
var
  mKey: string;
begin
  mKey := TAtlasWelcomeCustomizing.SettingOf(AId);
  if mKey = '' then
  begin
    Exit;
  end;
  // Ohne den Weg von #628 (Funktion nicht gestartet) wie das Auge.
  if not (Assigned(FOnHideSetting) and FOnHideSetting(mKey, APoint)) then
  begin
    HideSection(AId);
  end;
end;

procedure TAtlasIdeWelcomeLayouts.ShowSectionSettings(const AId: string);
var
  mKey: string;
begin
  mKey := TAtlasWelcomeCustomizing.SettingOf(AId);
  if (mKey <> '') and Assigned(FOnShowSetting) then
  begin
    FOnShowSetting(mKey);
  end;
end;

procedure TAtlasIdeWelcomeLayouts.SwitchLayout(const AName: string);
var
  mStored, mNext: TAtlasPluginSettings;
begin
  mStored := TAtlasIdeSettings.Stored;
  mNext := TAtlasWelcomeCustomizing.Switched(mStored, AName);
  if mNext.WelcomePageActiveLayout <> mStored.WelcomePageActiveLayout then
  begin
    Save(mNext);
  end;
end;

function TAtlasIdeWelcomeLayouts.AddLayout(const AName: string): Boolean;
var
  mStored: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mStored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(mStored).Added(AName, mLayouts);
  if Result then
  begin
    Save(TAtlasWelcomeCustomizing.Stored(mStored, mLayouts));
  end;
end;

function TAtlasIdeWelcomeLayouts.RenameLayout(const AName: string): Boolean;
var
  mStored: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mStored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(mStored).Renamed(AName, mLayouts);
  if Result then
  begin
    Save(TAtlasWelcomeCustomizing.Stored(mStored, mLayouts));
  end;
end;

function TAtlasIdeWelcomeLayouts.DeleteLayout: Boolean;
var
  mStored: TAtlasPluginSettings;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mStored := TAtlasIdeSettings.Stored;
  Result := TAtlasWelcomeCustomizing.Load(mStored).Deleted(mLayouts);
  // Das Layout danach bringt seine Sichtbarkeit mit.
  if Result then
  begin
    Save(TAtlasWelcomeCustomizing.Applied(mStored, mLayouts));
  end;
end;

procedure TAtlasIdeWelcomeLayouts.ResetLayout;
begin
  Save(TAtlasWelcomeCustomizing.Reset(TAtlasIdeSettings.Stored));
end;

end.
