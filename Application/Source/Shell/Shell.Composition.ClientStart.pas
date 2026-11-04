unit Shell.Composition.ClientStart;

// Start des Clients nach initialized: Name, Fähigkeiten und Editor-Einstellungen aus initialize, Wächter des
// Editor-Prozesses, Projektkontext der IDE, erste Arbeitsbereiche und Beobachtung der Dateien.

interface

uses
  System.JSON,
  Shell.Composition.Parts;

type
  /// <summary>Was nach initialized mit den Teilen der Komposition geschieht.</summary>
  TShellClientStart = class abstract
  private
    /// <summary>Name, Fähigkeiten und Editor-Einstellungen des Clients aus initialize.</summary>
    class procedure ApplyClientInfo(AParts: TShellParts; const AParams: TJSONObject); static;
  public
    /// <summary>Nach initialized: Client, Einstellungen, Beobachtung und erste Arbeitsbereiche.</summary>
    class procedure Initialized(AParts: TShellParts); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.Completion;

class procedure TShellClientStart.Initialized(AParts: TShellParts);
var
  mParams: TJSONObject;
  mFolders: TArray<TWorkspaceFolder>;
  mFolder: TWorkspaceFolder;
begin
  mParams := AParts.Protocol.Lifecycle.InitializeParams;
  AParts.Session.WatchParent(mParams);
  ApplyClientInfo(AParts, mParams);
  mFolders := TLspWorkspaceFolders.FromInitialize(mParams);
  // Vor dem ersten Laden, damit die Projekte nicht zweimal indiziert werden (#396).
  AParts.IdeArea.Ide.Project.LoadInitialize(mParams);
  // Meldet der Client nur Projektdateien (IDE-Plugin, #648), bekommen Dateien außerhalb dieser
  // Projekte weiter einen abgeleiteten Arbeitsbereich.
  AParts.DeriveWorkspaces := True;
  for mFolder in mFolders do
  begin
    if mFolder.ProjectFile = '' then
    begin
      AParts.DeriveWorkspaces := False;
    end;
  end;
  if Length(mFolders) = 0 then
  begin
    AParts.Channel.Logger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
  end;
  AParts.Core.Configuration.Start;
  for mFolder in mFolders do
  begin
    AParts.Core.Folders.Add(mFolder);
  end;
  AParts.Core.Configuration.UpdateWatchedFiles;
  AParts.IdeArea.FileChanges.RegisterWatchers(mParams);
end;

class procedure TShellClientStart.ApplyClientInfo(AParts: TShellParts; const AParams: TJSONObject);
begin
  if AParams <> nil then
  begin
    // Name des Clients für die Anmeldung am Index-Cache (#62); vor dem Anlegen der Arbeitsbereiche.
    AParts.Session.ClientName := AParams.GetValue<string>('clientInfo.name', '');
    // Absturzfälle nennen den Client (#1355).
    AParts.Protocol.CrashCases.Client := Trim(AParts.Session.ClientName + ' ' +
      AParams.GetValue<string>('clientInfo.version', ''));
  end;
  // Sprache des Clients (#1458) vor SetEditorSettings, das die Sprache der Texte wählt.
  AParts.Core.Settings.SetClientLocale(TLspClientLocale.FromInitialize(AParams));
  // Der neue Client erfährt, was nach Abstürzen übersprungen wird.
  AParts.Protocol.CrashCases.Announce;
  // Editor-Ebene: initializationOptions.settings.atlas wie bei didChangeConfiguration, schon vor dem
  // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
  // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
  if AParams <> nil then
  begin
    AParts.Core.Settings.SetEditorSettings(
      TLspConfiguration.EditorSettingsFromParams(AParams.GetValue('initializationOptions')));
  end
  else
  begin
    // Ohne Parameter bleibt die Editor-Ebene leer; die Einstellungen ohne Arbeitsbereich gelten trotzdem neu.
    AParts.Core.Settings.SetEditorSettings(AParts.Core.Settings.EditorSettings);
  end;
  AParts.CodeArea.Navigation.Hover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  AParts.CodeArea.Completion.Completion.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  AParts.CodeArea.Completion.Completion.DocumentationMarkdown := TLspCompletion.ClientPrefersMarkdown(AParams);
end;

end.
