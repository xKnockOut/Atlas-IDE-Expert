unit Atlas.Core.Commands.SettingsPalette;

// Einstellungen in der Befehlspalette (#1884, palette.settingsPrefix), ohne VCL und ohne Open Tools API.
// - TAtlasSettingsPaletteSource: Beginnt die Eingabe mit „@“, zeigt sie die passenden Einstellungen als Gruppe
//   „Einstellungen“ (Beschriftung, Weg, Zustand; Abzeichen „an“/„aus“ bei Schnellschaltern). Enter öffnet die
//   Optionen an der Stelle (OnOpen), Alt+Enter schaltet einen Schnellschalter direkt um (OnToggle), bei anderen
//   Einstellungen öffnet es ebenfalls die Optionen.
// - TAtlasPaletteSources: Die Palette kennt nur eine Zusatzquelle. Diese Verteilung reicht jede Eingabe an die
//   Einstellungen und an die Quelle der Module (Issues, #1270) weiter und zeigt mit „@“ die Gruppe der
//   Einstellungen, sonst die der Module. Ausgeführt wird bei der Quelle, deren Gruppe gerade steht.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.Search;

type
  TAtlasSettingsPaletteSource = class(TInterfacedObject, IAtlasPaletteSource)
  public const
    cPrefix = '@';
    cMaxHits = 30;
  private
    FCatalogOf: TFunc<TAtlasSettingsCatalog>;
    FCatalog: TAtlasSettingsCatalog;
    FGroups: TAtlasSettingsGroups;
    FShow: TProc<TAtlasPaletteGroup>;
    FSettings: TFunc<TAtlasPluginSettings>;
    FIsOn: TFunc<string, Boolean>;
    FInstalled: TAtlasModuleInstalled;
    FOnOpen: TProc<string>;
    FOnToggle: TProc<string>;
    FEnglish: Boolean;
    FHits: TArray<TAtlasSettingHit>;
    function ItemOf(const AHit: TAtlasSettingHit): TAtlasCommand;
    function HitOf(const AId: string; out AHit: TAtlasSettingHit): Boolean;
    /// <summary>Katalog erst beim ersten „@“ anlegen: Die Palette öffnet meist ohne.</summary>
    function Ready: Boolean;
  public
    /// <summary>ACatalogOf liefert den Katalog beim ersten „@“; er gehört danach der Quelle.</summary>
    constructor Create(const ACatalogOf: TFunc<TAtlasSettingsCatalog>; AEnglish: Boolean);
    destructor Destroy; override;
    /// <summary>Text hinter „@“; '' ohne Präfix.</summary>
    class function QueryOf(const APattern: string; out AQuery: string): Boolean; static;
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    procedure Changed(const APattern: string);
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure Closed;
    /// <summary>Treffer der letzten Eingabe (Tests).</summary>
    property Hits: TArray<TAtlasSettingHit> read FHits;
    /// <summary>Aktuelle Werte für den Zustand; nil = ohne.</summary>
    property Settings: TFunc<TAtlasPluginSettings> read FSettings write FSettings;
    /// <summary>Wirksamer Zustand eines Schnellschalters (Name); nil = ohne Abzeichen.</summary>
    property IsOn: TFunc<string, Boolean> read FIsOn write FIsOn;
    property Installed: TAtlasModuleInstalled read FInstalled write FInstalled;
    /// <summary>Enter: Optionen an der Einstellung (Name) öffnen.</summary>
    property OnOpen: TProc<string> read FOnOpen write FOnOpen;
    /// <summary>Alt+Enter auf einem Schnellschalter: umschalten (Name).</summary>
    property OnToggle: TProc<string> read FOnToggle write FOnToggle;
  end;

  TAtlasPaletteSources = class(TInterfacedObject, IAtlasPaletteSource)
  private
    FSettings: IAtlasPaletteSource;
    FOther: IAtlasPaletteSource;
    FShow: TProc<TAtlasPaletteGroup>;
    FSettingsGroup: TAtlasPaletteGroup;
    FOtherGroup: TAtlasPaletteGroup;
    FPrefixed: Boolean;
    procedure Refresh;
  public
    /// <summary>ASettings bzw. AOther darf nil sein.</summary>
    constructor Create(const ASettings, AOther: IAtlasPaletteSource);
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    procedure Changed(const APattern: string);
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure Closed;
  end;

implementation

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TPaletteText = (Title, Keys, Prompt, NoHits, On, Off);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TPaletteText] of string = (
    ('Einstellungen', 'Enter öffnet die Optionen · Alt+Enter schaltet einen Schnellschalter um',
      'Einstellung nach @ eingeben, z. B. @minimap', 'Keine Einstellung gefunden.', 'an', 'aus'),
    ('Settings', 'Enter opens the options · Alt+Enter flips a quick toggle',
      'Type a setting after @, e.g. @minimap', 'No setting found.', 'on', 'off'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TPaletteText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasSettingsPaletteSource }

constructor TAtlasSettingsPaletteSource.Create(const ACatalogOf: TFunc<TAtlasSettingsCatalog>; AEnglish: Boolean);
begin
  inherited Create;
  FCatalogOf := ACatalogOf;
  FEnglish := AEnglish;
end;

function TAtlasSettingsPaletteSource.Ready: Boolean;
begin
  if (FCatalog = nil) and Assigned(FCatalogOf) then
  begin
    FCatalog := FCatalogOf();
    FCatalogOf := nil;
    if FCatalog <> nil then
    begin
      FGroups := TAtlasSettingsGroups.Create(FCatalog);
    end;
  end;
  Result := FGroups <> nil;
end;

destructor TAtlasSettingsPaletteSource.Destroy;
begin
  FHits := nil;
  FreeAndNil(FGroups);
  FreeAndNil(FCatalog);
  inherited Destroy;
end;

class function TAtlasSettingsPaletteSource.QueryOf(const APattern: string; out AQuery: string): Boolean;
var
  mPattern: string;
begin
  mPattern := TrimLeft(APattern);
  Result := mPattern.StartsWith(cPrefix);
  AQuery := '';
  if Result then
  begin
    AQuery := Trim(Copy(mPattern, Length(cPrefix) + 1, MaxInt));
  end;
end;

function TAtlasSettingsPaletteSource.ItemOf(const AHit: TAtlasSettingHit): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AHit.Name;
  Result.Caption := AHit.Caption;
  Result.Path := AHit.Path;
  Result.ShortCut := AHit.Key;
  Result.Description := TAtlasSettingsSearch.StateText(AHit);
  if AHit.QuickToggle and Assigned(FIsOn) then
  begin
    if FIsOn(AHit.Name) then
    begin
      Result.Badge := UiText(TPaletteText.On);
    end
    else
    begin
      Result.Badge := UiText(TPaletteText.Off);
    end;
  end;
end;

procedure TAtlasSettingsPaletteSource.Opened(const AShow: TProc<TAtlasPaletteGroup>);
begin
  FShow := AShow;
end;

procedure TAtlasSettingsPaletteSource.Changed(const APattern: string);
var
  mQuery, mStatus: string;
  mItems: TArray<TAtlasCommand>;
  mHit: TAtlasSettingHit;
begin
  if not Assigned(FShow) then
  begin
    Exit;
  end;
  FHits := nil;
  if not QueryOf(APattern, mQuery) or not Ready then
  begin
    FShow(TAtlasPaletteGroup.None);
    Exit;
  end;
  FHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, mQuery, FEnglish, cMaxHits,
    TAtlasSettingsSearchHooks.Create(FInstalled, nil));
  if Assigned(FSettings) then
  begin
    TAtlasSettingsSearch.Annotate(FCatalog, FGroups, FSettings(), FHits, FEnglish);
  end;
  mItems := nil;
  for mHit in FHits do
  begin
    mItems := mItems + [ItemOf(mHit)];
  end;
  mStatus := UiText(TPaletteText.Keys);
  if mQuery = '' then
  begin
    mStatus := UiText(TPaletteText.Prompt);
  end
  else if Length(mItems) = 0 then
  begin
    mStatus := UiText(TPaletteText.NoHits);
  end;
  FShow(TAtlasPaletteGroup.Create(UiText(TPaletteText.Title), mStatus, mQuery, mItems));
end;

function TAtlasSettingsPaletteSource.HitOf(const AId: string; out AHit: TAtlasSettingHit): Boolean;
var
  mHit: TAtlasSettingHit;
begin
  for mHit in FHits do
  begin
    if mHit.Name = AId then
    begin
      AHit := mHit;
      Exit(True);
    end;
  end;
  AHit := Default(TAtlasSettingHit);
  Result := False;
end;

procedure TAtlasSettingsPaletteSource.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
var
  mHit: TAtlasSettingHit;
begin
  if not HitOf(AItem.Id, mHit) then
  begin
    Exit;
  end;
  if (AAction = TAtlasPaletteAction.Toggle) and mHit.QuickToggle and Assigned(FOnToggle) then
  begin
    FOnToggle(mHit.Name);
  end
  else if (AAction <> TAtlasPaletteAction.Copy) and Assigned(FOnOpen) then
  begin
    FOnOpen(mHit.Name);
  end;
end;

procedure TAtlasSettingsPaletteSource.Closed;
begin
  FShow := nil;
end;

{ TAtlasPaletteSources }

constructor TAtlasPaletteSources.Create(const ASettings, AOther: IAtlasPaletteSource);
begin
  inherited Create;
  FSettings := ASettings;
  FOther := AOther;
  FSettingsGroup := TAtlasPaletteGroup.None;
  FOtherGroup := TAtlasPaletteGroup.None;
end;

procedure TAtlasPaletteSources.Refresh;
begin
  if not Assigned(FShow) then
  begin
    Exit;
  end;
  if FPrefixed and (FSettings <> nil) then
  begin
    FShow(FSettingsGroup);
  end
  else
  begin
    FShow(FOtherGroup);
  end;
end;

procedure TAtlasPaletteSources.Opened(const AShow: TProc<TAtlasPaletteGroup>);
begin
  FShow := AShow;
  if FSettings <> nil then
  begin
    FSettings.Opened(
      procedure(AGroup: TAtlasPaletteGroup)
      begin
        FSettingsGroup := AGroup;
        Refresh;
      end);
  end;
  if FOther <> nil then
  begin
    FOther.Opened(
      procedure(AGroup: TAtlasPaletteGroup)
      begin
        FOtherGroup := AGroup;
        Refresh;
      end);
  end;
end;

procedure TAtlasPaletteSources.Changed(const APattern: string);
var
  mQuery: string;
begin
  FPrefixed := TAtlasSettingsPaletteSource.QueryOf(APattern, mQuery);
  if FSettings <> nil then
  begin
    FSettings.Changed(APattern);
  end;
  // Mit „@“ fragt die Quelle der Module nicht (kein Netz für eine Einstellungssuche).
  if (FOther <> nil) and not (FPrefixed and (FSettings <> nil)) then
  begin
    FOther.Changed(APattern);
  end;
  Refresh;
end;

procedure TAtlasPaletteSources.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
begin
  if FPrefixed and (FSettings <> nil) then
  begin
    FSettings.Execute(AItem, AAction);
  end
  else if FOther <> nil then
  begin
    FOther.Execute(AItem, AAction);
  end;
end;

procedure TAtlasPaletteSources.Closed;
begin
  FShow := nil;
  if FSettings <> nil then
  begin
    FSettings.Closed;
  end;
  if FOther <> nil then
  begin
    FOther.Closed;
  end;
  FSettings := nil;
  FOther := nil;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Commands.SettingsPalette', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
