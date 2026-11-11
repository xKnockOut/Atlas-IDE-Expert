unit Atlas.Core.Settings.Search.Tests;

// Suche über die Einstellungen (#1884): Rangfolge, Synonyme, beide Sprachen, Tippfehler, Module, Zustand und die
// Einstellungen mit „@“ in der Befehlspalette.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups;

type
  [Category('Atlas.IDE.Base')]
  [TestFixture]
  TAtlasSettingsSearchTests = class
  private
    FCatalog: TAtlasSettingsCatalog;
    FGroups: TAtlasSettingsGroups;
    /// <summary>Position der Einstellung AName in den Treffern zu AText; -1 ohne.</summary>
    function RankOf(const AText, AName: string; AEnglish: Boolean = False): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EmptyTextFindsNothing;
    [Test]
    procedure KeepsLimit;
    [Test]
    procedure KeyFindsSettingFirst;
    [Test]
    procedure CaptionRanksMainSwitchFirst;
    [Test]
    procedure SynonymFindsHoverAndChildren;
    [Test]
    procedure GermanWordsFindInEnglish;
    [Test]
    procedure ToleratesTypo;
    [Test]
    procedure AllWordsMustMatch;
    [Test]
    procedure ShortcutFindsKeys;
    [Test]
    procedure MissingModuleIsHidden;
    [Test]
    procedure LabelOfPageCounts;
    [Test]
    procedure AnnotateMarksModifiedAndLocked;
    [Test]
    procedure AnnotateMarksModuleOff;
    [Test]
    procedure StateTextNamesTeamPath;
    [Test]
    procedure CatalogReadsKeywordsAndQuickToggle;
  end;

  [Category('Atlas.IDE.Base')]
  [TestFixture]
  TAtlasSettingsPaletteSearchTests = class
  public
    [Test]
    procedure PrefixIsRecognized;
    [Test]
    procedure ShowsSettingsAfterPrefix;
    [Test]
    procedure WithoutPrefixShowsNothing;
    [Test]
    procedure AltEnterTogglesQuickToggle;
    [Test]
    procedure EnterOpensOptions;
    [Test]
    procedure SourcesRouteByPrefix;
    [Test]
    procedure AltEnterIsToggleAction;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Search,
  Atlas.Core.Commands.SettingsPalette;

{ TAtlasSettingsSearchTests }

procedure TAtlasSettingsSearchTests.Setup;
begin
  FCatalog := TAtlasSettingsCatalog.CreateDefault;
  FGroups := TAtlasSettingsGroups.Create(FCatalog);
end;

procedure TAtlasSettingsSearchTests.TearDown;
begin
  FreeAndNil(FGroups);
  FreeAndNil(FCatalog);
end;

function TAtlasSettingsSearchTests.RankOf(const AText, AName: string; AEnglish: Boolean): Integer;
var
  mHits: TArray<TAtlasSettingHit>;
  mIndex: Integer;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, AText, AEnglish, 1000);
  for mIndex := 0 to High(mHits) do
  begin
    if mHits[mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasSettingsSearchTests.EmptyTextFindsNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsSearch.Find(FCatalog, FGroups, '  ', False, 10))));
end;

procedure TAtlasSettingsSearchTests.KeepsLimit;
begin
  Assert.AreEqual(2, Integer(Length(TAtlasSettingsSearch.Find(FCatalog, FGroups, 'e', False, 2))));
end;

procedure TAtlasSettingsSearchTests.KeyFindsSettingFirst;
var
  mHits: TArray<TAtlasSettingHit>;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'hover.membersMaxLines', False, 10);
  Assert.IsTrue(Length(mHits) > 0);
  Assert.AreEqual('HoverMembersMaxLines', mHits[0].Name);
  Assert.AreEqual('hover.membersMaxLines', mHits[0].Key);
  Assert.AreEqual(0, RankOf('completion.enabled', 'Enabled'));
end;

procedure TAtlasSettingsSearchTests.CaptionRanksMainSwitchFirst;
var
  mHits: TArray<TAtlasSettingHit>;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'minimap', False, 50);
  Assert.IsTrue(Length(mHits) > 3, 'Minimap und Unteroptionen');
  Assert.AreEqual('Minimap', mHits[0].Name);
  Assert.AreEqual('Editor', mHits[0].AreaCaption);
  Assert.IsTrue(RankOf('minimap', 'MinimapWidth') > 0, 'Breite über den Schlüssel');
end;

procedure TAtlasSettingsSearchTests.SynonymFindsHoverAndChildren;
var
  mHover, mChild: Integer;
begin
  mHover := RankOf('tooltip', 'HoverTooltip');
  mChild := RankOf('tooltip', 'HoverMembersMaxLines');
  Assert.AreEqual(0, mHover, 'Synonym am Hauptschalter');
  Assert.IsTrue(mChild > mHover, 'Unteroption über das geerbte Synonym, aber dahinter');
  Assert.AreEqual(0, RankOf('lint', 'RuleChecksEnabled'));
end;

procedure TAtlasSettingsSearchTests.GermanWordsFindInEnglish;
var
  mHits: TArray<TAtlasSettingHit>;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'klammerfarben', True, 10);
  Assert.IsTrue(Length(mHits) > 0);
  Assert.AreEqual('PairColors', mHits[0].Name);
  Assert.AreEqual('Bracket colors', mHits[0].Caption, 'Beschriftung in der Sprache der IDE');
  Assert.AreEqual(0, RankOf('bracket colors', 'PairColors', False), 'englisch in deutscher IDE');
end;

procedure TAtlasSettingsSearchTests.ToleratesTypo;
begin
  Assert.AreEqual(0, RankOf('minimpa', 'Minimap'));
  Assert.AreEqual(0, Integer(Length(TAtlasSettingsSearch.Find(FCatalog, FGroups, 'qxzvw', False, 10))));
end;

procedure TAtlasSettingsSearchTests.AllWordsMustMatch;
begin
  Assert.AreEqual(0, RankOf('minimap side', 'MinimapSide'));
  Assert.AreEqual(-1, RankOf('minimap side', 'MinimapWidth'));
end;

procedure TAtlasSettingsSearchTests.ShortcutFindsKeys;
begin
  Assert.IsTrue(RankOf('shortcut befehlspalette', 'PaletteKey') = 0);
  Assert.IsTrue(RankOf('shortcut', 'PaletteKey') >= 0);
end;

procedure TAtlasSettingsSearchTests.MissingModuleIsHidden;
var
  mHits: TArray<TAtlasSettingHit>;
  mHit: TAtlasSettingHit;
  mAny: Boolean;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'debug', False, 1000);
  mAny := False;
  for mHit in mHits do
  begin
    mAny := mAny or (mHit.Module = 'debug');
  end;
  Assert.IsTrue(mAny, 'mit allen Modulen');
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'debug', False, 1000, TAtlasSettingsSearchHooks.Create(
    function(const ASwitch: string): Boolean
    begin
      Result := ASwitch <> 'debug';
    end, nil));
  for mHit in mHits do
  begin
    Assert.AreNotEqual('debug', mHit.Module, mHit.Name);
  end;
end;

procedure TAtlasSettingsSearchTests.LabelOfPageCounts;
var
  mHits: TArray<TAtlasSettingHit>;
begin
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'zebrastreifen', False, 10, TAtlasSettingsSearchHooks.Create(nil,
    function(const AName: string): string
    begin
      Result := '';
      if AName = 'SettingsMarkModified' then
      begin
        Result := 'Zebrastreifen markieren';
      end;
    end));
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual('Zebrastreifen markieren', mHits[0].Caption);
end;

procedure TAtlasSettingsSearchTests.AnnotateMarksModifiedAndLocked;
var
  mSettings: TAtlasPluginSettings;
  mHits: TArray<TAtlasSettingHit>;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.ExperimentalEnabled := True;
  mSettings.Minimap := False;
  mSettings.MinimapWidth := 200;
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'editor.minimap.width', False, 1);
  Assert.AreEqual(1, Integer(Length(mHits)));
  TAtlasSettingsSearch.Annotate(FCatalog, FGroups, mSettings, mHits, False);
  Assert.IsTrue(mHits[0].Modified, 'Breite geändert');
  Assert.IsTrue(mHits[0].LockReason = lrMasterOff, 'Minimap aus sperrt die Breite');
  Assert.AreEqual('Minimap', mHits[0].LockMaster);
  Assert.Contains(TAtlasSettingsSearch.StateText(mHits[0]), 'Minimap');
  mSettings.ExperimentalEnabled := False;
  TAtlasSettingsSearch.Annotate(FCatalog, FGroups, mSettings, mHits, False);
  Assert.IsTrue(mHits[0].LockReason = lrExperimental, 'experimentell vor Hauptschalter');
  Assert.IsTrue(mHits[0].Experimental);
end;

procedure TAtlasSettingsSearchTests.AnnotateMarksModuleOff;
var
  mSettings: TAtlasPluginSettings;
  mHits: TArray<TAtlasSettingHit>;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.AssistantsEnabled := False;
  mHits := TAtlasSettingsSearch.Find(FCatalog, FGroups, 'assistants.edit', False, 1);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual('assistants', mHits[0].Module);
  TAtlasSettingsSearch.Annotate(FCatalog, FGroups, mSettings, mHits, False);
  Assert.IsTrue(mHits[0].ModuleOff);
  mSettings.AssistantsEnabled := True;
  TAtlasSettingsSearch.Annotate(FCatalog, FGroups, mSettings, mHits, False);
  Assert.IsFalse(mHits[0].ModuleOff);
end;

procedure TAtlasSettingsSearchTests.StateTextNamesTeamPath;
var
  mHit: TAtlasSettingHit;
begin
  mHit := Default(TAtlasSettingHit);
  Assert.AreEqual('', TAtlasSettingsSearch.StateText(mHit));
  mHit.TeamPath := 'issues.tracker';
  mHit.Modified := True;
  Assert.Contains(TAtlasSettingsSearch.StateText(mHit), '.atlas: issues.tracker');
  Assert.Contains(TAtlasSettingsSearch.StateText(mHit), '●');
end;

procedure TAtlasSettingsSearchTests.CatalogReadsKeywordsAndQuickToggle;
var
  mEntry: TAtlasCatalogEntry;
begin
  mEntry := FCatalog[FCatalog.IndexOfName('HoverTooltip')];
  Assert.IsTrue(Length(mEntry.Keywords) > 0);
  Assert.IsTrue(mEntry.QuickToggle);
  mEntry := FCatalog[FCatalog.IndexOfName('SettingsSearch')];
  Assert.AreEqual('settings.search', mEntry.Key);
  Assert.IsTrue(mEntry.Description <> '');
  Assert.IsTrue(TAtlasPluginSettings.Defaults.SettingsSearch);
  Assert.IsTrue(TAtlasPluginSettings.Defaults.PaletteSettingsPrefix);
end;

{ TAtlasSettingsPaletteSearchTests }

/// <summary>Quelle mit eingebautem Katalog; ALast bekommt die zuletzt gezeigte Gruppe.</summary>
function NewSource(var ALast: TAtlasPaletteGroup): TAtlasSettingsPaletteSource;
var
  mLast: ^TAtlasPaletteGroup;
begin
  mLast := @ALast;
  Result := TAtlasSettingsPaletteSource.Create(
    function: TAtlasSettingsCatalog
    begin
      Result := TAtlasSettingsCatalog.CreateDefault;
    end, False);
  Result.Opened(
    procedure(AGroup: TAtlasPaletteGroup)
    begin
      mLast^ := AGroup;
    end);
end;

procedure TAtlasSettingsPaletteSearchTests.PrefixIsRecognized;
var
  mQuery: string;
begin
  Assert.IsTrue(TAtlasSettingsPaletteSource.QueryOf('@minimap', mQuery));
  Assert.AreEqual('minimap', mQuery);
  Assert.IsTrue(TAtlasSettingsPaletteSource.QueryOf(' @ hover tooltip', mQuery));
  Assert.AreEqual('hover tooltip', mQuery);
  Assert.IsFalse(TAtlasSettingsPaletteSource.QueryOf('minimap', mQuery));
end;

procedure TAtlasSettingsPaletteSearchTests.ShowsSettingsAfterPrefix;
var
  mGroup: TAtlasPaletteGroup;
  mSource: IAtlasPaletteSource;
begin
  mGroup := TAtlasPaletteGroup.None;
  mSource := NewSource(mGroup);
  mSource.Changed('@minimap');
  Assert.IsTrue(mGroup.Visible);
  Assert.IsTrue(Length(mGroup.Items) > 0);
  Assert.AreEqual('Minimap', mGroup.Items[0].Id);
  Assert.AreEqual('minimap', mGroup.Highlight);
  mSource.Changed('@');
  Assert.IsTrue(mGroup.Visible, 'nur Präfix: Hinweis');
  Assert.AreEqual(0, Integer(Length(mGroup.Items)));
  mSource.Closed;
end;

procedure TAtlasSettingsPaletteSearchTests.WithoutPrefixShowsNothing;
var
  mGroup: TAtlasPaletteGroup;
  mSource: IAtlasPaletteSource;
begin
  mGroup := TAtlasPaletteGroup.Create('x', '', '', nil);
  mSource := NewSource(mGroup);
  mSource.Changed('minimap');
  Assert.IsFalse(mGroup.Visible);
  mSource.Closed;
end;

procedure TAtlasSettingsPaletteSearchTests.AltEnterTogglesQuickToggle;
var
  mGroup: TAtlasPaletteGroup;
  mSource: TAtlasSettingsPaletteSource;
  mKeep: IAtlasPaletteSource;
  mToggled, mOpened: string;
begin
  mGroup := TAtlasPaletteGroup.None;
  mSource := NewSource(mGroup);
  mKeep := mSource;
  mSource.OnToggle :=
    procedure(AName: string)
    begin
      mToggled := AName;
    end;
  mSource.OnOpen :=
    procedure(AName: string)
    begin
      mOpened := AName;
    end;
  mSource.IsOn :=
    function(AName: string): Boolean
    begin
      Result := True;
    end;
  mSource.Changed('@editor.hoverTooltip');
  Assert.AreEqual('HoverTooltip', mGroup.Items[0].Id);
  Assert.AreEqual('an', mGroup.Items[0].Badge);
  mSource.Execute(mGroup.Items[0], TAtlasPaletteAction.Toggle);
  Assert.AreEqual('HoverTooltip', mToggled);
  Assert.AreEqual('', mOpened);
  // Keine Schnellschalter-Einstellung: Alt+Enter öffnet die Optionen.
  mToggled := '';
  mSource.Changed('@hover.membersMaxLines');
  mSource.Execute(mGroup.Items[0], TAtlasPaletteAction.Toggle);
  Assert.AreEqual('', mToggled);
  Assert.AreEqual('HoverMembersMaxLines', mOpened);
  mSource.Closed;
end;

procedure TAtlasSettingsPaletteSearchTests.EnterOpensOptions;
var
  mGroup: TAtlasPaletteGroup;
  mSource: TAtlasSettingsPaletteSource;
  mKeep: IAtlasPaletteSource;
  mOpened: string;
begin
  mGroup := TAtlasPaletteGroup.None;
  mSource := NewSource(mGroup);
  mKeep := mSource;
  mSource.OnOpen :=
    procedure(AName: string)
    begin
      mOpened := AName;
    end;
  mSource.Changed('@minimap');
  mSource.Execute(mGroup.Items[0], TAtlasPaletteAction.Open);
  Assert.AreEqual('Minimap', mOpened);
  mSource.Closed;
end;

type
  /// <summary>Zusatzquelle der Module für den Test: zeigt immer eine Gruppe „Issues“ und merkt Ausführungen.
  /// </summary>
  TFakeSource = class(TInterfacedObject, IAtlasPaletteSource)
  public
    Show: TProc<TAtlasPaletteGroup>;
    Patterns: Integer;
    Executed: string;
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    procedure Changed(const APattern: string);
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure Closed;
  end;

procedure TFakeSource.Opened(const AShow: TProc<TAtlasPaletteGroup>);
begin
  Show := AShow;
end;

procedure TFakeSource.Changed(const APattern: string);
var
  mItem: TAtlasCommand;
begin
  Inc(Patterns);
  mItem := Default(TAtlasCommand);
  mItem.Id := 'ISSUE-1';
  if Assigned(Show) then
  begin
    Show(TAtlasPaletteGroup.Create('Issues', '', APattern, [mItem]));
  end;
end;

procedure TFakeSource.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
begin
  Executed := AItem.Id;
end;

procedure TFakeSource.Closed;
begin
  Show := nil;
end;

procedure TAtlasSettingsPaletteSearchTests.SourcesRouteByPrefix;
var
  mFake: TFakeSource;
  mFakeRef: IAtlasPaletteSource;
  mSettings: TAtlasSettingsPaletteSource;
  mSources: IAtlasPaletteSource;
  mGroup: TAtlasPaletteGroup;
  mUnused: TAtlasPaletteGroup;
  mOpened: string;
begin
  mFake := TFakeSource.Create;
  mFakeRef := mFake;
  mUnused := TAtlasPaletteGroup.None;
  mSettings := NewSource(mUnused);
  mSettings.OnOpen :=
    procedure(AName: string)
    begin
      mOpened := AName;
    end;
  mSources := TAtlasPaletteSources.Create(mSettings, mFakeRef);
  mSources.Opened(
    procedure(AGroup: TAtlasPaletteGroup)
    begin
      mGroup := AGroup;
    end);
  mSources.Changed('build');
  Assert.AreEqual('Issues', mGroup.Title);
  mSources.Execute(mGroup.Items[0], TAtlasPaletteAction.Open);
  Assert.AreEqual('ISSUE-1', mFake.Executed);
  mSources.Changed('@minimap');
  Assert.AreEqual('Einstellungen', mGroup.Title);
  Assert.AreEqual(1, mFake.Patterns, 'mit @ fragt die Quelle der Module nicht');
  mSources.Execute(mGroup.Items[0], TAtlasPaletteAction.Open);
  Assert.AreEqual('Minimap', mOpened);
  mSources.Closed;
  Assert.IsFalse(Assigned(mFake.Show));
end;

procedure TAtlasSettingsPaletteSearchTests.AltEnterIsToggleAction;
begin
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(False, False, True) = TAtlasPaletteAction.Toggle);
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(True, True, True) = TAtlasPaletteAction.Toggle, 'Alt vor Strg');
  Assert.IsTrue(TAtlasPaletteRows.ActionOf(True, False, False) = TAtlasPaletteAction.Start);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsSearchTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsPaletteSearchTests);

end.
