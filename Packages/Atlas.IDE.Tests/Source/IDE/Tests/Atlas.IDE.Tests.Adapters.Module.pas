unit Atlas.IDE.Tests.Adapters.Module;

// Modulklasse der Tests (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Tests.Composition) über den Scope des Moduls bereitstellt: Befehle in Palette und Menüs, die
// Einträge im Atlas-Menü (Untermenü „Tests“), im Kontextmenü des Editors (Testunits, normale Units, Debug-Halt
// #1873), der Projektverwaltung (#1817, #1880) und in Datei › Neu › Weitere (#1821), die Taste der zuletzt benutzten
// Testliste (#2167), Einstellungen und Thema. Befehle, Tasten, Einstellungen und Thema hängen an den Teilen der
// Composition (Läufer, Fenster „Atlas-Tests“, Mutationslauf); sie reicht sie als TAtlasTestsModuleHooks herein.
// Läufe, Build und Speichern stehen in Atlas.IDE.Tests.Adapters.Runs, „Vergleichen“ in Atlas.IDE.Tests.Adapters.Values.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules;

type
  /// <summary>Was die Modulklasse aus den Teilen der Composition braucht.</summary>
  TAtlasTestsModuleHooks = record
    Commands: TFunc<TArray<TAtlasModuleCommand>>;
    Keys: TFunc<TArray<TAtlasModuleKey>>;
    ApplySettings: TProc;
    ThemeChanged: TProc;
  end;

  TAtlasTestsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasKeySource)
  public const
    cModuleId = 'atlas.tests';
    cSwitch = 'tests';
  private
    FActive: Boolean;
    FHooks: TAtlasTestsModuleHooks;
  public
    constructor Create(const AHooks: TAtlasTestsModuleHooks);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Tests.FromDebugStop,
  Atlas.UI.Tests.Strings;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Eintrag im Untermenü „Tests“ des Atlas-Menüs („-“ = Trennlinie).</summary>
function AtlasEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.AtlasMenu);
  Result.Section := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsEditorMenuGroup);
end;

/// <summary>Ist die Datei eine DUnitX-Testunit?</summary>
function InTestUnit(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.TestUnit;
end;

/// <summary>Läuft eine Debug-Sitzung?</summary>
function WhileDebugging(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging;
end;

/// <summary>Eintrag im Untermenü „Tests“ von Atlas im Kontextmenü des Editors; nur in einer Testunit.</summary>
function ContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsEditorMenuGroup);
  Result.Group := 'tests';
  Result.When := InTestUnit;
end;

/// <summary>Eintrag im Untermenü „Tests“ des Kontextmenüs, nur beim Debuggen (#1873).</summary>
function DebugContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := ContextEntry(ACommandId);
  Result.When := WhileDebugging;
end;

/// <summary>Ist die Datei eine Unit (.pas), aber keine Testunit?</summary>
function InCodeUnit(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := not AContext.TestUnit and SameText(ExtractFileExt(AContext.FileName), '.pas');
end;

/// <summary>Wie ContextEntry, aber nur außerhalb von Testunits.</summary>
function CodeContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := ContextEntry(ACommandId);
  Result.When := InCodeUnit;
end;

{ TAtlasTestsModule }

constructor TAtlasTestsModule.Create(const AHooks: TAtlasTestsModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasTestsModule.Info: TAtlasModuleInfo;
begin
  // Der Läufer baut und startet Programme: nur im normalen Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Tests', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Normal, cSwitch);
end;

procedure TAtlasTestsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasTestsModule.Stop;
begin
  FActive := False;
end;

function TAtlasTestsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasTestsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := FHooks.Commands();
end;

function TAtlasTestsModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    // Fenster „Atlas-Tests“ (#1776) unter Ansicht › Atlas und im Atlas-Menü.
    MenuEntry('Atlas.TestExplorer', TAtlasMenuPlace.ViewMenu),
    // Untermenü Tests im Atlas-Menü: Fenster; ausführen; Auswertungen; Mutationen; vergleichen; aufräumen.
    AtlasEntry('Atlas.TestExplorer'),
    AtlasEntry('-'),
    AtlasEntry('Atlas.RunAffectedTests'),
    AtlasEntry('Atlas.RunStaleTests'),
    AtlasEntry('-'),
    AtlasEntry('Atlas.ShowSlowestTests'),
    AtlasEntry('Atlas.ShowFlakyTests'),
    AtlasEntry('Atlas.LoadTestCoverage'),
    AtlasEntry('Atlas.ClearTestCoverage'),
    AtlasEntry('Atlas.ListUntestedMethods'),
    AtlasEntry('-'),
    AtlasEntry('Atlas.MutateUnit'),
    AtlasEntry('Atlas.MutateChanged'),
    AtlasEntry('Atlas.CancelMutation'),
    AtlasEntry('-'),
    AtlasEntry('Atlas.CompareTestValues'),
    AtlasEntry('-'),
    AtlasEntry('Atlas.CleanApprovalFiles'),
    // Test am Cursor (#585) im Untermenü „Atlas“ des Editors.
    ContextEntry('Atlas.RunTest'),
    ContextEntry('Atlas.DebugTest'),
    ContextEntry('Atlas.RepeatTest'),
    ContextEntry('Atlas.ShuffleTests'),
    ContextEntry('Atlas.ShuffleTestsAgain'),
    ContextEntry('Atlas.CancelTestSeries'),
    DebugContextEntry(TAtlasIdeTestFromDebug.cCommand),
    ContextEntry('Atlas.CompareTestValues'),
    ContextEntry('Atlas.EditTestCases'),
    // Grenzfälle (#2173) an Routinen normaler Units.
    CodeContextEntry('Atlas.SuggestBoundaryCases'),
    // Mutationslauf (#1460) an Methoden normaler Units.
    CodeContextEntry('Atlas.MutateMethod'),
    CodeContextEntry('Atlas.MutateUnit'),
    CodeContextEntry('Atlas.CancelMutation'),
    MenuEntry('-', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectRunUnitTests', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.LeakSetup', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.NewTestUnitFor', TAtlasMenuPlace.Gallery)];
end;

function TAtlasTestsModule.Keys: TArray<TAtlasModuleKey>;
begin
  // Zuletzt benutzte Testliste (#2167).
  Result := FHooks.Keys();
end;

procedure TAtlasTestsModule.ApplySettings;
begin
  FHooks.ApplySettings();
end;

procedure TAtlasTestsModule.ThemeChanged;
begin
  FHooks.ThemeChanged();
end;

end.
