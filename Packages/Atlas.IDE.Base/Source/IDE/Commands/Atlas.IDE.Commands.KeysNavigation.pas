unit Atlas.IDE.Commands.KeysNavigation;

// Tasten der Editorbefehle für Navigation und Fenster, ausgelagert aus
// TAtlasIdeEditorKeys.Rebind (Atlas.IDE.Commands.Bindings, Beschreibung dort):
// Schnell öffnen (#503), Navigationsverlauf (#504), Definition und Referenzen
// einblenden (#505), Erzeugen-Menü (#719), Benachrichtigungen (#601), Sprung zum
// Gegenstück (#635), Brotkrumenleiste (#590) und nächste/vorherige Änderung
// (#507). Jede Gruppe nur, solange ihre Einstellung an ist; sonst bleibt die
// Taste der IDE bzw. frei.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Commands.KeyList;

type
  /// <summary>Tasten der Editorbefehle für Navigation und Fenster, je Gruppe.</summary>
  TAtlasNavigationKeys = record
  public
    /// <summary>Schnell öffnen, Navigationsverlauf, Definition und Referenzen einblenden.</summary>
    class procedure AddJumps(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
    /// <summary>Erzeugen-Menü, Benachrichtigungen, Sprung zum Gegenstück, Brotkrumenleiste, Änderungen.</summary>
    class procedure AddWindows(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Commands.QuickOpen,
  Atlas.IDE.Editor.NavHistory,
  Atlas.IDE.Results.Peek,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Notifications.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.Contracts.LineChanges;

function Text(AId: TAtlasTextId): string;
begin
  Result := TAtlasStrings.Text(AId);
end;

/// <summary>Sprung zum Gegenstück (#635), mit ASelect bis dorthin markiert.</summary>
function JumpToMatch(ASelect: Boolean): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasIdeEditorCommands.JumpToMatch(ASelect);
    end;
end;

/// <summary>Nächste bzw. vorherige Änderung (#507).</summary>
function GoToChange(AForward: Boolean): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasLineChangeMarks.Current.GoToChange(AForward);
    end;
end;

/// <summary>Erzeugen-Menü (#719); Show ist überladen, darum als eigene Routine.</summary>
procedure ShowGenerate;
begin
  TAtlasIdeGenerate.Show;
end;

{ TAtlasNavigationKeys }

class procedure TAtlasNavigationKeys.AddJumps(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Schnell öffnen (#503): aus = Strg+P bleibt der IDE.
  if ASettings.QuickOpen then
  begin
    AKeys.AddKey(TAtlasFeature.Palette, ASettings.QuickOpenKey, Text(TAtlasTextId.QuickOpenTitle),
      TAtlasIdeQuickOpen.Show);
  end;
  // Navigationsverlauf (#504): aus = Alt+Links/Rechts bleiben Zurück/Vor der IDE.
  if ASettings.NavHistory then
  begin
    AKeys.AddPriorityKey(TAtlasFeature.NavHistory, ASettings.NavBackKey, Text(TAtlasTextId.NavBackCommand),
      TAtlasIdeNavHistory.GoBack, True);
    AKeys.AddPriorityKey(TAtlasFeature.NavHistory, ASettings.NavForwardKey, Text(TAtlasTextId.NavForwardCommand),
      TAtlasIdeNavHistory.GoForward, True);
    AKeys.AddKey(TAtlasFeature.NavHistory, ASettings.LastEditKey, Text(TAtlasTextId.NavLastEditCommand),
      TAtlasIdeNavHistory.GoLastEdit);
  end;
  // Definition und Referenzen einblenden (#505).
  if ASettings.Peek then
  begin
    AKeys.AddKey(TAtlasFeature.Peek, ASettings.PeekDefinitionKey, Text(TAtlasTextId.PeekDefinitionCommand),
      TAtlasIdePeek.PeekDefinition);
    AKeys.AddKey(TAtlasFeature.Peek, ASettings.PeekReferencesKey, Text(TAtlasTextId.PeekReferencesCommand),
      TAtlasIdePeek.PeekReferences);
  end;
end;

class procedure TAtlasNavigationKeys.AddWindows(AKeys: TAtlasEditorKeyList; const ASettings: TAtlasPluginSettings);
begin
  // Erzeugen-Menü (#719): aus = Alt+Einfg bleibt frei.
  if ASettings.GenerateMenu then
  begin
    AKeys.AddKey(TAtlasFeature.Generate, ASettings.GenerateMenuKey, Text(TAtlasTextId.GenerateMenuCommand),
      ShowGenerate);
  end;
  // Benachrichtigungen (#601): aus = Strg+Umschalt+Alt+N bleibt frei.
  if ASettings.Notifications then
  begin
    AKeys.AddKey(TAtlasFeature.Notifications, ASettings.NotificationsKey, Text(TAtlasTextId.NotificationsCommand),
      TAtlasIdeNotifications.ShowList);
  end;
  // Sprung zum Gegenstück (#635): aus = Strg+Ü und Strg+Umschalt+Ü bleiben frei.
  if ASettings.JumpToMatch then
  begin
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.JumpToMatchKey, Text(TAtlasTextId.JumpToMatchCommand),
      JumpToMatch(False));
    AKeys.AddKey(TAtlasFeature.EditorCommands, ASettings.JumpToMatchSelectKey,
      Text(TAtlasTextId.JumpToMatchSelectCommand), JumpToMatch(True));
  end;
  // Brotkrumenleiste (#590): aus = Strg+Umschalt+. bleibt frei.
  if ASettings.Breadcrumbs then
  begin
    AKeys.AddKey(TAtlasFeature.Breadcrumbs, ASettings.BreadcrumbsKey, Text(TAtlasTextId.BreadcrumbsCommand),
      TAtlasIdeBreadcrumbs.Focus);
  end;
  // Nächste/vorherige Änderung (#507): aus = beide Tasten bleiben frei.
  if ASettings.GitGutter then
  begin
    AKeys.AddKey(TAtlasFeature.LineChanges, ASettings.NextChangeKey, Text(TAtlasTextId.NextChangeCommand),
      GoToChange(True));
    AKeys.AddKey(TAtlasFeature.LineChanges, ASettings.PreviousChangeKey, Text(TAtlasTextId.PreviousChangeCommand),
      GoToChange(False));
  end;
end;

end.
