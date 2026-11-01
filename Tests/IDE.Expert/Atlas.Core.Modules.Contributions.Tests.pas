unit Atlas.Core.Modules.Contributions.Tests;

// Tests zu TAtlasModuleContributions (#1455): Beiträge kommen und gehen mit
// dem Modul, Fehler eines Hörers halten die übrigen nicht an.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModuleContributionsTests = class
  public
    [Test]
    procedure CommandsFollowTheModule;
    [Test]
    procedure MenuEntriesAndVisibility;
    [Test]
    procedure ListenersRunAndReportFailures;
    [Test]
    procedure HoverValueTakesFirstNonEmpty;
    [Test]
    procedure WithoutRegistryNothing;
    [Test]
    procedure KeysWithoutKeyOrAttemptAreLeftOut;
    [Test]
    procedure EditorViewListenersRun;
    [Test]
    procedure StoppedModuleContributesNothing;
    [Test]
    procedure MenuEntriesWithoutCommand;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions;

type
  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FId: string;
    FStopped: Boolean;
  public
    constructor Create(const AId: string);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

  TSource = class(TInterfacedObject, IAtlasCommandSource, IAtlasMenuSource, IAtlasAppliesSettings,
    IAtlasFollowsTheme, IAtlasHoverValueSource, IAtlasKeySource, IAtlasFollowsEditorView)
  private
    FPrefix: string;
    FFail: Boolean;
    FHover: string;
  public
    Log: string;
    constructor Create(const APrefix: string; AFail: Boolean; const AHover: string);
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
    function HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
    function Keys: TArray<TAtlasModuleKey>;
    procedure EditorViewActivated;
  end;

constructor TFakeModule.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := FId;
end;

procedure TFakeModule.Start;
begin
  FStopped := False;
end;

procedure TFakeModule.Stop;
begin
  FStopped := True;
end;

// Läuft ab der Anmeldung, bis Stop: Beiträge zählen nur von laufenden Modulen.
function TFakeModule.IsActive: Boolean;
begin
  Result := not FStopped;
end;

constructor TSource.Create(const APrefix: string; AFail: Boolean; const AHover: string);
begin
  inherited Create;
  FPrefix := APrefix;
  FFail := AFail;
  FHover := AHover;
end;

function TSource.Commands: TArray<TAtlasModuleCommand>;
var
  mCommand: TAtlasModuleCommand;
begin
  mCommand := Default(TAtlasModuleCommand);
  mCommand.Id := FPrefix + '.Run';
  mCommand.Caption := FPrefix;
  mCommand.Visible :=
    function: Boolean
    begin
      Result := False;
    end;
  Result := [mCommand];
end;

function TSource.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
begin
  mEntry := Default(TAtlasMenuEntry);
  mEntry.CommandId := FPrefix + '.Run';
  mEntry.Section := 'Debug';
  Result := [mEntry];
  mEntry.Place := TAtlasMenuPlace.EditorContext;
  mEntry.Section := '';
  Result := Result + [mEntry];
  mEntry.Place := TAtlasMenuPlace.ViewMenu;
  mEntry.CommandId := FPrefix + '.Window';
  Result := Result + [mEntry];
end;

function TSource.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  mKey := Default(TAtlasModuleKey);
  mKey.Id := FPrefix + '.Run';
  mKey.Key := 16449;
  mKey.Attempt :=
    function: Boolean
    begin
      Result := True;
    end;
  Result := [mKey];
  // Ohne Taste und ohne Attempt: fehlen in Keys.
  mKey.Key := 0;
  Result := Result + [mKey];
  mKey.Key := 16450;
  mKey.Attempt := nil;
  Result := Result + [mKey];
  // Ohne Attempt, aber mit Run: läuft nach der Tastenverarbeitung.
  mKey.Id := FPrefix + '.Later';
  mKey.Key := 16451;
  mKey.Run :=
    procedure
    begin
      Log := Log + 'key;';
    end;
  Result := Result + [mKey];
end;

procedure TSource.EditorViewActivated;
begin
  Log := Log + 'view;';
  if FFail then
    raise EInvalidOp.Create('kaputt');
end;

procedure TSource.ApplySettings;
begin
  Log := Log + 'settings;';
  if FFail then
    raise EInvalidOp.Create('kaputt');
end;

procedure TSource.ThemeChanged;
begin
  Log := Log + 'theme;';
end;

function TSource.HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
begin
  Result := FHover;
end;

function Provide(const AScope: IAtlasModuleScope; ASource: TSource): TSource;
var
  mRef: IInterface;
begin
  Result := ASource;
  mRef := ASource;
  AScope.Provide(IAtlasCommandSource, mRef);
  AScope.Provide(IAtlasMenuSource, mRef);
  AScope.Provide(IAtlasAppliesSettings, mRef);
  AScope.Provide(IAtlasFollowsTheme, mRef);
  AScope.Provide(IAtlasHoverValueSource, mRef);
  AScope.Provide(IAtlasKeySource, mRef);
  AScope.Provide(IAtlasFollowsEditorView, mRef);
end;

procedure TModuleContributionsTests.CommandsFollowTheModule;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mCommand: TAtlasModuleCommand;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  Provide(mScope, TSource.Create('A', False, ''));
  Assert.AreEqual(1, Integer(Length(TAtlasModuleContributions.Commands(mRegistry))));
  Assert.IsTrue(TAtlasModuleContributions.FindCommand(mRegistry, 'a.run', mCommand), 'ohne Groß/klein');
  Assert.AreEqual('A', mCommand.Caption);
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Commands(mRegistry))), 'mit dem Modul weg');
  Assert.IsFalse(TAtlasModuleContributions.FindCommand(mRegistry, 'A.Run', mCommand));
  mRegistry := nil;
end;

procedure TModuleContributionsTests.MenuEntriesAndVisibility;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mEntries: TArray<TAtlasMenuEntry>;
  mCommand: TAtlasModuleCommand;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  Provide(mScope, TSource.Create('A', False, ''));
  mEntries := TAtlasModuleContributions.MenuEntries(mRegistry, TAtlasMenuPlace.AtlasMenu);
  Assert.AreEqual(1, Integer(Length(mEntries)));
  Assert.AreEqual('Debug', mEntries[0].Section);
  mEntries := TAtlasModuleContributions.MenuEntries(mRegistry, TAtlasMenuPlace.EditorContext);
  Assert.AreEqual(1, Integer(Length(mEntries)), 'je Ort getrennt');
  Assert.AreEqual('', mEntries[0].Section);
  mEntries := TAtlasModuleContributions.MenuEntries(mRegistry, TAtlasMenuPlace.ViewMenu);
  Assert.AreEqual(1, Integer(Length(mEntries)), 'Ansicht › Atlas getrennt');
  Assert.AreEqual('A.Window', mEntries[0].CommandId);
  mEntries := TAtlasModuleContributions.MenuEntries(mRegistry, TAtlasMenuPlace.EditorContext);
  TAtlasModuleContributions.FindCommand(mRegistry, mEntries[0].CommandId, mCommand);
  Assert.IsFalse(TAtlasModuleContributions.IsVisible(mCommand));
  mCommand.Visible := nil;
  Assert.IsTrue(TAtlasModuleContributions.IsVisible(mCommand), 'ohne Visible sichtbar');
  mEntries := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
end;

procedure TModuleContributionsTests.ListenersRunAndReportFailures;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mFailing, mGood: TSource;
  mFailures: TArray<string>;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mFailing := Provide(mScope, TSource.Create('A', True, ''));
  mGood := Provide(mScope, TSource.Create('B', False, ''));
  mFailures := TAtlasModuleContributions.ApplySettings(mRegistry);
  Assert.AreEqual(1, Integer(Length(mFailures)));
  Assert.IsTrue(mFailures[0].Contains('EInvalidOp'));
  Assert.AreEqual('settings;', mGood.Log, 'der zweite läuft trotzdem');
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.ThemeChanged(mRegistry))));
  Assert.AreEqual('settings;theme;', mFailing.Log);
  mFailures := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
end;

procedure TModuleContributionsTests.HoverValueTakesFirstNonEmpty;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  Provide(mScope, TSource.Create('A', False, ''));
  Provide(mScope, TSource.Create('B', False, 'Wert B'));
  Provide(mScope, TSource.Create('C', False, 'Wert C'));
  Assert.AreEqual('Wert B', TAtlasModuleContributions.HoverValue(mRegistry, 'x', nil, ''));
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
end;

procedure TModuleContributionsTests.WithoutRegistryNothing;
var
  mCommand: TAtlasModuleCommand;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Commands(nil))));
  Assert.IsFalse(TAtlasModuleContributions.FindCommand(nil, 'x', mCommand));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.ApplySettings(nil))));
  Assert.AreEqual('', TAtlasModuleContributions.HoverValue(nil, 'x', nil, ''));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Keys(nil))));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.EditorViewActivated(nil))));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.MenuEntries(nil, TAtlasMenuPlace.AtlasMenu))));
end;

procedure TModuleContributionsTests.KeysWithoutKeyOrAttemptAreLeftOut;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mKeys: TArray<TAtlasModuleKey>;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  Provide(mScope, TSource.Create('A', False, ''));
  mKeys := TAtlasModuleContributions.Keys(mRegistry);
  Assert.AreEqual(2, Integer(Length(mKeys)));
  Assert.AreEqual(16449, mKeys[0].Key);
  Assert.IsTrue(mKeys[0].Attempt());
  Assert.AreEqual('A.Later', mKeys[1].Id);
  Assert.IsFalse(Assigned(mKeys[1].Attempt));
  mKeys := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Keys(mRegistry))), 'mit dem Modul weg');
  mRegistry := nil;
end;

procedure TModuleContributionsTests.EditorViewListenersRun;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mFailing, mGood: TSource;
  mFailures: TArray<string>;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  mFailing := Provide(mScope, TSource.Create('A', True, ''));
  mGood := Provide(mScope, TSource.Create('B', False, ''));
  mFailures := TAtlasModuleContributions.EditorViewActivated(mRegistry);
  Assert.AreEqual(1, Integer(Length(mFailures)));
  Assert.IsTrue(mFailures[0].StartsWith('IAtlasFollowsEditorView: EInvalidOp'));
  Assert.AreEqual('view;', mFailing.Log);
  Assert.AreEqual('view;', mGood.Log, 'der zweite läuft trotzdem');
  mFailures := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
end;

type
  /// <summary>Einträge ohne Befehl, etwa je Projektaufgabe.</summary>
  TDynamicSource = class(TInterfacedObject, IAtlasMenuSource)
  public
    Runs: Integer;
    function MenuEntries: TArray<TAtlasMenuEntry>;
  end;

function TDynamicSource.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
begin
  mEntry := Default(TAtlasMenuEntry);
  mEntry.CommandId := 'task:Prüfen';
  mEntry.Section := 'Aufgaben';
  mEntry.Caption := 'Prüfen';
  mEntry.Run :=
    procedure
    begin
      Inc(Runs);
    end;
  Result := [mEntry];
end;

procedure TModuleContributionsTests.MenuEntriesWithoutCommand;
var
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mDynamic: TDynamicSource;
  mRef: IInterface;
  mEntry: TAtlasMenuEntry;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mScope := mRegistry.RegisterModule(TFakeModule.Create('atlas.a') as IAtlasModule);
  Provide(mScope, TSource.Create('A', False, ''));
  mDynamic := TDynamicSource.Create;
  mRef := mDynamic as IAtlasMenuSource;
  mScope.Provide(IAtlasMenuSource, mRef);
  Assert.IsTrue(TAtlasModuleContributions.FindMenuEntry(mRegistry, TAtlasMenuPlace.AtlasMenu, 'TASK:prüfen', mEntry));
  Assert.AreEqual('Prüfen', mEntry.Caption);
  mEntry.Run();
  Assert.AreEqual(1, mDynamic.Runs);
  Assert.IsFalse(TAtlasModuleContributions.FindMenuEntry(mRegistry, TAtlasMenuPlace.AtlasMenu, 'A.Run', mEntry),
    'Einträge mit Befehl zählen nicht');
  Assert.IsFalse(TAtlasModuleContributions.FindMenuEntry(mRegistry, TAtlasMenuPlace.EditorContext, 'task:Prüfen',
    mEntry), 'nur am eigenen Platz');
  mEntry := Default(TAtlasMenuEntry);
  mDynamic := nil;
  mRef := nil;
  mScope := nil;
  mRegistry.UnregisterModule('atlas.a');
  Assert.IsFalse(TAtlasModuleContributions.FindMenuEntry(mRegistry, TAtlasMenuPlace.AtlasMenu, 'task:Prüfen', mEntry));
  mRegistry := nil;
end;

procedure TModuleContributionsTests.StoppedModuleContributesNothing;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: IAtlasModule;
  mScope: IAtlasModuleScope;
  mSource: TSource;
  mRef: IInterface;
  mCommand: TAtlasModuleCommand;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mModule := TFakeModule.Create('atlas.a');
  mScope := mRegistry.RegisterModule(mModule);
  mSource := TSource.Create('A', False, 'Wert');
  mRef := mSource as IAtlasCommandSource;
  Provide(mScope, mSource);
  mModule.Stop;
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Commands(mRegistry))), 'Befehle');
  Assert.IsFalse(TAtlasModuleContributions.FindCommand(mRegistry, 'A.Run', mCommand));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.MenuEntries(mRegistry, TAtlasMenuPlace.AtlasMenu))));
  Assert.AreEqual(0, Integer(Length(TAtlasModuleContributions.Keys(mRegistry))), 'Tasten');
  Assert.AreEqual('', TAtlasModuleContributions.HoverValue(mRegistry, 'x', nil, ''));
  TAtlasModuleContributions.ApplySettings(mRegistry);
  TAtlasModuleContributions.ThemeChanged(mRegistry);
  TAtlasModuleContributions.EditorViewActivated(mRegistry);
  Assert.AreEqual('', mSource.Log, 'gestoppt hört nichts');
  mModule.Start;
  Assert.AreEqual(1, Integer(Length(TAtlasModuleContributions.Commands(mRegistry))), 'wieder da');
  mSource := nil;
  mRef := nil;
  mScope := nil;
  mModule := nil;
  mRegistry.UnregisterModule('atlas.a');
  mRegistry := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TModuleContributionsTests);

end.
