unit Atlas.Core.Welcome.Sections;

// Bereiche der Atlas-Willkommensseite (#753), ohne VCL und Open Tools API.
// Jeder Bereich (Zustandskachel #754, Weiterarbeiten #755, Projekte #592 …)
// meldet sich mit Kennung, Titel, Reihenfolge, Vorgabespalte und der Abfrage
// seines Einstellungsschalters an. Die IDE-Schicht zeigt nur Bereiche, deren
// Schalter an ist; ein Bereich mit ausgeschaltetem Schalter wird nicht
// registriert. Ändert sich der Inhalt eines Bereichs oder die Auswahl,
// benachrichtigt TAtlasWelcomeSections ihre Beobachter (aus jedem Thread; die
// Beobachter wechseln selbst in den Hauptthread).

interface

uses
  System.SysUtils,
  Atlas.Plugin.Notifications.Listeners,
  Atlas.Plugin.Notifications.OrderedItems,
  Atlas.Core.Welcome.Contract;

type
  TAtlasWelcomeColumn = Atlas.Core.Welcome.Contract.TAtlasWelcomeColumn;
  TAtlasWelcomeSection = Atlas.Core.Welcome.Contract.TAtlasWelcomeSection;

  /// <summary>Kennungen der Bereiche und der Plugins auf der Willkommensseite der IDE.</summary>
  TAtlasWelcomeIds = class
  public const
    /// <summary>Kopf mit Symbol, Grußzeile, Version und Kurzstatus (#753).</summary>
    cHeader = 'atlas.header';
    /// <summary>Alle Atlas-Bereiche im Atlas-Layout als ein Bereich der IDE (#753).</summary>
    cBoard = 'atlas.board';
    cState = 'atlas.state';
    cContinue = 'atlas.continue';
    cProjects = 'atlas.projects';
    cHistory = 'atlas.history';
    cNews = 'atlas.news';
    cDiscover = 'atlas.discover';
    cSetup = 'atlas.setup';
    cSearch = 'atlas.search';
    cUnsaved = 'atlas.unsaved';
    cTests = 'atlas.tests';
    cIssues = 'atlas.issues';
    /// <summary>Sprint-Kachel mit Burndown (#1277).</summary>
    cSprint = 'atlas.sprint';
    cHelp = 'atlas.help';
    /// <summary>Vorsilbe der Plugin-Kennungen in der IDE.</summary>
    cPluginPrefix = 'Atlas.Welcome.';
  public
    /// <summary>"atlas.state" → "Atlas.Welcome.state".</summary>
    class function PluginId(const ASectionId: string): string; static;
    /// <summary>Umkehrung von PluginId; '' für fremde Plugins.</summary>
    class function SectionOf(const APluginId: string): string; static;
  end;

  /// <summary>Bereiche nach Order und Kennung.</summary>
  TAtlasWelcomeSectionItems = class(TAtlasOrderedItems<TAtlasWelcomeSection>)
  protected
    function IdOf(const AItem: TAtlasWelcomeSection): string; override;
    function OrderOf(const AItem: TAtlasWelcomeSection): Integer; override;
  end;

  TAtlasWelcomeSections = class
  private
    FItems: TAtlasWelcomeSectionItems;
    FListeners: TAtlasListeners<string>;
    class var FDefault: TAtlasWelcomeSections;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bereiche des Plugins; Tests legen eigene an.</summary>
    class function Default: TAtlasWelcomeSections; static;
    class procedure ReleaseDefault; static;
    /// <summary>Meldet ASection an; ein Bereich mit derselben Kennung wird ersetzt.</summary>
    procedure Add(const ASection: TAtlasWelcomeSection);
    procedure Remove(const AId: string);
    function Find(const AId: string; out ASection: TAtlasWelcomeSection): Boolean;
    /// <summary>Alle angemeldeten Bereiche nach Order, dann Kennung.</summary>
    function All: TArray<TAtlasWelcomeSection>;
    /// <summary>Nur die Bereiche, deren Schalter an ist, in derselben Reihenfolge.</summary>
    function Visible: TArray<TAtlasWelcomeSection>;
    /// <summary>Kennungen von Visible.</summary>
    function VisibleIds: TArray<string>;
    /// <summary>Inhalt des Bereichs AId hat sich geändert (Beobachter erhalten AId).</summary>
    procedure Changed(const AId: string); overload;
    /// <summary>Auswahl oder Schalter geändert (Beobachter erhalten '').</summary>
    procedure Changed; overload;
    /// <summary>Zählt jede Meldung.</summary>
    function Version: Integer;
    /// <summary>Beobachter; AId = geänderter Bereich oder '' für alle.</summary>
    function AddListener(const AListener: TProc<string>): Integer;
    procedure RemoveListener(AHandle: Integer);
  end;

  /// <summary>Welche Plugins auf der Willkommensseite der IDE stehen und was nach einer Meldung neu zu zeichnen
  /// ist (Kennungen ohne Groß-/Kleinschreibung).</summary>
  TAtlasWelcomePlugins = class
  public
    /// <summary>Gewünschte Plugins: ohne AIdePage keins, im Atlas-Layout nur die Tafel, sonst der Kopf (AHeader)
    /// und je sichtbarem Bereich mit Ansicht (ASections, in ihrer Reihenfolge) eins.</summary>
    class function Wanted(AIdePage, AAtlasLayout, AHeader: Boolean; const ASections: TArray<string>):
      TArray<string>; static;
    class function Contains(const AList: TArray<string>; const AValue: string): Boolean; static;
    /// <summary>Angemeldete Plugins aus ARegistered, die nicht mehr in AWanted stehen.</summary>
    class function Stale(const ARegistered, AWanted: TArray<string>): TArray<string>; static;
    /// <summary>AIds der gesammelten Meldungen enthält '' (Bereiche kamen, gingen oder wurden geschaltet): alles
    /// abgleichen statt einzelne Bereiche neu zu zeichnen.</summary>
    class function NeedsSync(const AIds: TArray<string>): Boolean; static;
    /// <summary>AId zu AIds hinzufügen, wenn sie dort noch fehlt; False, wenn sie schon da war.</summary>
    class function Mark(var AIds: TArray<string>; const AId: string): Boolean; static;
  end;

implementation

{ TAtlasWelcomeIds }

class function TAtlasWelcomeIds.PluginId(const ASectionId: string): string;
begin
  Result := ASectionId;
  if SameText(Copy(Result, 1, 6), 'atlas.') then
  begin
    Delete(Result, 1, 6);
  end;
  Result := cPluginPrefix + Result;
end;

class function TAtlasWelcomeIds.SectionOf(const APluginId: string): string;
begin
  Result := '';
  if SameText(Copy(APluginId, 1, Length(cPluginPrefix)), cPluginPrefix) and
    (Length(APluginId) > Length(cPluginPrefix)) then
  begin
    // Kennungen der Bereiche sind klein geschrieben.
    Result := 'atlas.' + LowerCase(Copy(APluginId, Length(cPluginPrefix) + 1, MaxInt));
  end;
end;

{ TAtlasWelcomeSectionItems }

function TAtlasWelcomeSectionItems.IdOf(const AItem: TAtlasWelcomeSection): string;
begin
  Result := AItem.Id;
end;

function TAtlasWelcomeSectionItems.OrderOf(const AItem: TAtlasWelcomeSection): Integer;
begin
  Result := AItem.Order;
end;

{ TAtlasWelcomeSections }

constructor TAtlasWelcomeSections.Create;
begin
  inherited Create;
  FItems := TAtlasWelcomeSectionItems.Create;
  FListeners := TAtlasListeners<string>.Create;
end;

destructor TAtlasWelcomeSections.Destroy;
begin
  FListeners.Free;
  FItems.Free;
  inherited;
end;

class function TAtlasWelcomeSections.Default: TAtlasWelcomeSections;
begin
  if FDefault = nil then
  begin
    FDefault := TAtlasWelcomeSections.Create;
  end;
  Result := FDefault;
end;

class procedure TAtlasWelcomeSections.ReleaseDefault;
begin
  FreeAndNil(FDefault);
end;

procedure TAtlasWelcomeSections.Add(const ASection: TAtlasWelcomeSection);
begin
  if ASection.Id = '' then
  begin
    Exit;
  end;
  FItems.Put(ASection);
  FListeners.Changed('');
end;

procedure TAtlasWelcomeSections.Remove(const AId: string);
begin
  if FItems.Remove(AId) then
  begin
    FListeners.Changed('');
  end;
end;

function TAtlasWelcomeSections.Find(const AId: string; out ASection: TAtlasWelcomeSection): Boolean;
begin
  Result := FItems.Find(AId, ASection);
end;

function TAtlasWelcomeSections.All: TArray<TAtlasWelcomeSection>;
begin
  Result := FItems.ToArray;
end;

function TAtlasWelcomeSections.Visible: TArray<TAtlasWelcomeSection>;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  // Schalter außerhalb der Sperre abfragen: Sie lesen Einstellungen.
  for mSection in All do
  begin
    if mSection.IsEnabled then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

function TAtlasWelcomeSections.VisibleIds: TArray<string>;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  for mSection in Visible do
  begin
    Result := Result + [mSection.Id];
  end;
end;

procedure TAtlasWelcomeSections.Changed(const AId: string);
begin
  FListeners.Changed(AId);
end;

procedure TAtlasWelcomeSections.Changed;
begin
  FListeners.Changed('');
end;

function TAtlasWelcomeSections.Version: Integer;
begin
  Result := FListeners.Version;
end;

function TAtlasWelcomeSections.AddListener(const AListener: TProc<string>): Integer;
begin
  Result := FListeners.Add(AListener);
end;

procedure TAtlasWelcomeSections.RemoveListener(AHandle: Integer);
begin
  FListeners.Remove(AHandle);
end;

{ TAtlasWelcomePlugins }

class function TAtlasWelcomePlugins.Wanted(AIdePage, AAtlasLayout, AHeader: Boolean;
  const ASections: TArray<string>): TArray<string>;
var
  mId: string;
begin
  Result := nil;
  if not AIdePage then
  begin
    Exit;
  end;
  if AAtlasLayout then
  begin
    Result := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cBoard)];
    Exit;
  end;
  if AHeader then
  begin
    Result := [TAtlasWelcomeIds.PluginId(TAtlasWelcomeIds.cHeader)];
  end;
  for mId in ASections do
  begin
    Result := Result + [TAtlasWelcomeIds.PluginId(mId)];
  end;
end;

class function TAtlasWelcomePlugins.Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  Result := False;
  for mItem in AList do
  begin
    Result := Result or SameText(mItem, AValue);
  end;
end;

class function TAtlasWelcomePlugins.Stale(const ARegistered, AWanted: TArray<string>): TArray<string>;
var
  mPlugin: string;
begin
  Result := nil;
  for mPlugin in ARegistered do
  begin
    if not Contains(AWanted, mPlugin) then
    begin
      Result := Result + [mPlugin];
    end;
  end;
end;

class function TAtlasWelcomePlugins.NeedsSync(const AIds: TArray<string>): Boolean;
begin
  Result := Contains(AIds, '');
end;

class function TAtlasWelcomePlugins.Mark(var AIds: TArray<string>; const AId: string): Boolean;
begin
  Result := not Contains(AIds, AId);
  if Result then
  begin
    AIds := AIds + [AId];
  end;
end;

end.
