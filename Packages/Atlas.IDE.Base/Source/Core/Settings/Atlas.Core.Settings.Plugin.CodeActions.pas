unit Atlas.Core.Settings.Plugin.CodeActions;

// Einstellungen des IDE-Plugins, Bereich Code-Aktionen (codeActions.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Code-Aktionen und Befehle zum Erzeugen.</summary>
  TAtlasPluginCodeActionsSettings = record
    /// <summary>Zwischen Deklaration und Implementierung wechseln (#775); aus: Atlas belegt die Tasten nicht,
    /// die Klassennavigation der IDE gilt.</summary>
    MethodToggle: Boolean;
    /// <summary>Schnellbefehle mit „/“ nach Enter und „///“-Gerüste beim Server auslösen (#399).</summary>
    SlashCommands: Boolean;
    /// <summary>Erzeugen-Menü (#719, keys.generateMenu): Alt+Einfg, Kontextmenü und Befehlspalette; aus = die Funktion
    /// ruht und das Kürzel bleibt frei.</summary>
    GenerateMenu: Boolean;
    /// <summary>Gruppen in ihrer Reihenfolge (#719, keys.generateMenu.groups): generate, surround, templates,
    /// kommagetrennt; fehlt eine, fehlt sie im Menü.</summary>
    GenerateMenuGroups: string;
    /// <summary>Ausgeblendete Einträge (#719, keys.generateMenu.hidden): Kennungen wie slash:json oder Namen wie /json,
    /// tryf; kommagetrennt.</summary>
    GenerateMenuHidden: string;
    /// <summary>Zuletzt gewählte Einträge oben (#719, keys.generateMenu.recentFirst).</summary>
    GenerateMenuRecentFirst: Boolean;
    /// <summary>Befehlsnamen (/name) rechts in der Zeile (#719, keys.generateMenu.showCommandNames).</summary>
    GenerateMenuShowCommandNames: Boolean;
    /// <summary>Untermenü „Atlas“ im Kontextmenü der Projektverwaltung (#1817, commands.projectContextMenu).</summary>
    ProjectContextMenu: Boolean;
    /// <summary>Kategorie „Atlas“ in Datei › Neu › Weitere (#1821, generate.galleryWizards).</summary>
    GalleryWizards: Boolean;
    /// <summary>Kontextmenü Atlas im Editor: nur Einträge, die zur Lage passen
    /// (commands.editorContextMenu.contextual).</summary>
    EditorContextMenuContextual: Boolean;
    /// <summary>Gezeigte Untermenüs im Kontextmenü Atlas des Editors (commands.editorContextMenu.groups),
    /// kommagetrennt: navigation, edit, analysis, findings, debug, tests, notes.</summary>
    EditorContextMenuGroups: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginCodeActionsSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  Atlas.Core.Generate.Contract,
  Atlas.Core.Settings.ContextMenuGroups;

{ TAtlasPluginCodeActionsSettings }

class function TAtlasPluginCodeActionsSettings.Defaults: TAtlasPluginCodeActionsSettings;
begin
  Result.MethodToggle := True;
  Result.SlashCommands := True;
  Result.GenerateMenu := True;
  Result.GenerateMenuGroups := 'generate,surround,templates';
  Result.GenerateMenuHidden := '';
  Result.GenerateMenuRecentFirst := True;
  Result.GenerateMenuShowCommandNames := True;
  Result.ProjectContextMenu := True;
  Result.GalleryWizards := True;
  Result.EditorContextMenuContextual := True;
  Result.EditorContextMenuGroups := TAtlasContextMenuGroupNames.Text(TAtlasContextMenuGroupNames.cAll);
end;

procedure TAtlasPluginCodeActionsSettings.Normalize;
begin
  GenerateMenuGroups := TAtlasGenerateLists.NormalizeGroups(GenerateMenuGroups);
  GenerateMenuHidden := TAtlasGenerateLists.NormalizeHidden(GenerateMenuHidden);
  EditorContextMenuGroups := TAtlasContextMenuGroupNames.Normalize(EditorContextMenuGroups);
end;

procedure TAtlasPluginCodeActionsSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('MethodToggle', MethodToggle);
  AIo.Flag('SlashCommands', SlashCommands);
  AIo.Flag('GenerateMenu', GenerateMenu);
  AIo.Text('GenerateMenuGroups', GenerateMenuGroups);
  AIo.Text('GenerateMenuHidden', GenerateMenuHidden);
  AIo.Flag('GenerateMenuRecentFirst', GenerateMenuRecentFirst);
  AIo.Flag('GenerateMenuShowCommandNames', GenerateMenuShowCommandNames);
  AIo.Flag('ProjectContextMenu', ProjectContextMenu);
  AIo.Flag('GalleryWizards', GalleryWizards);
  AIo.Flag('EditorContextMenuContextual', EditorContextMenuContextual);
  AIo.Text('EditorContextMenuGroups', EditorContextMenuGroups);
end;

end.
