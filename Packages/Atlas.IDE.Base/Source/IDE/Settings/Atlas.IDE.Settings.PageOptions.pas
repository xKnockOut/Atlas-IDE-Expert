unit Atlas.IDE.Settings.PageOptions;

// Haken der Optionsseite „Atlas“ zu anderen Teilen der IDE-Schicht: Version des Servers (#227), angeheftete Favoriten
// (#458), Befehle für „Leiste anpassen …“ (#1101), Projektdatei .atlas (#486),
// Export, Import und „Alles zurücksetzen“ (#723), F1 zur Einstellung unter dem Fokus (#1886), Symbolindex (#492). Ohne
// Zustand; die Seite hält die Methodenreferenzen.

interface

uses
  System.SysUtils,
  System.JSON,
  Vcl.Controls,
  Atlas.UI.EditorToolbar.Customize,
  Atlas.UI.Settings.Page;

type
  /// <summary>Befehl an den Server im Hintergrund; AText macht aus der Antwort (nil ohne Server) den Text für die
  /// Seite.</summary>
  TAtlasIndexRun = reference to procedure(const ACommand: string; const AText: TFunc<TJSONValue, string>);

  TAtlasPageOptions = class
  public
    /// <summary>Symbolindex (#492): Kennzahlen, „Index neu aufbauen“ und „Index löschen“ über ARun.</summary>
    class procedure ConnectIndex(APage: TAtlasSettingsPage; const ARun: TAtlasIndexRun); static;
    /// <summary>Version der gewählten AtlasServer.exe (#227). Wege zu den Regeln und Baseline liefert das Modul
    /// Prüfregeln als Abschnitt (#1755).</summary>
    class procedure ConnectServerVersion(APage: TAtlasSettingsPage); static;
    /// <summary>Angeheftete Favoriten (#458) und Befehle für „Leiste anpassen …“ (#1101); AToolbarCommands nil =
    /// keine Befehle.</summary>
    class procedure ConnectFavorites(APage: TAtlasSettingsPage;
      const AToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>>); static;
    /// <summary>Projektdatei .atlas (#486), Export, Import und „Alles zurücksetzen“ (#723).</summary>
    class procedure ConnectTransfer(APage: TAtlasSettingsPage); static;
    /// <summary>F1 (#1886): Hilfe zur Einstellung unter dem Fokus, sonst zur Optionsseite.</summary>
    class procedure ConnectHelp(APage: TAtlasSettingsPage); static;
    /// <summary>Schlüssel (x-key) der Einstellung an AControl oder einem seiner Eltern in APage; '' ohne.</summary>
    class function SettingKeyAt(APage: TAtlasSettingsPage; AControl: TControl): string; static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.Index,
  Atlas.Core.Settings.Catalog,
  Atlas.IDE.Contracts.Help,
  Atlas.IDE.ElementHelp.Keys,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Completion.Favorites,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Settings.ServerTool,
  Atlas.IDE.Settings.Transfer,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.EditorView,
  Atlas.UI.Settings.Page.TeamFile,
  Atlas.UI.Settings.Page.Transfer,
  Atlas.IDE.Foundation.Files;

/// <summary>Text der Antwort auf „Index neu aufbauen“.</summary>
function RebuildText(AAnswer: TJSONValue): string;
begin
  if AAnswer <> nil then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
  end;
end;

/// <summary>Text der Antwort auf „Index löschen“.</summary>
function ClearText(AAnswer: TJSONValue): string;
begin
  if AAnswer <> nil then
  begin
    Result := TLspIndexStatus.ClearedText(AAnswer);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
  end;
end;

class procedure TAtlasPageOptions.ConnectIndex(APage: TAtlasSettingsPage; const ARun: TAtlasIndexRun);
begin
  APage.Part<TAtlasSettingsIndexPart>.OnIndexMetrics :=
    procedure
    begin
      ARun('atlas.server.status',
        function(AAnswer: TJSONValue): string
        begin
          Result := TLspIndexStatus.Metrics(AAnswer).Text;
        end);
    end;
  APage.Part<TAtlasSettingsIndexPart>.OnIndexRebuild :=
    procedure
    begin
      ARun('atlas.server.rebuildIndex',
        function(AAnswer: TJSONValue): string
        begin
          Result := RebuildText(AAnswer);
        end);
    end;
  APage.Part<TAtlasSettingsIndexPart>.OnIndexClear :=
    procedure
    begin
      ARun('atlas.server.clearIndex',
        function(AAnswer: TJSONValue): string
        begin
          Result := ClearText(AAnswer);
        end);
    end;
end;

class procedure TAtlasPageOptions.ConnectServerVersion(APage: TAtlasSettingsPage);
begin
  APage.Part<TAtlasSettingsGeneralPart>.OnServerVersion :=
    function(APath: string): string
    begin
      Result := TAtlasServerTool.FileVersion(APath);
    end;
end;

class procedure TAtlasPageOptions.ConnectFavorites(APage: TAtlasSettingsPage;
  const AToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>>);
begin
  APage.Part<TAtlasSettingsFavoritesPart>.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeFavorites.Remove(AKeys);
        end);
    end;
  APage.Part<TAtlasSettingsFavoritesPart>.OnFavorites :=
    function: TArray<TAtlasFavorite>
    begin
      Result := TAtlasIdeFavorites.Items;
    end;
  APage.Part<TAtlasSettingsEditorViewPart>.OnToolbarCommands :=
    function: TArray<TAtlasToolbarCommandInfo>
    begin
      Result := nil;
      if Assigned(AToolbarCommands) then
      begin
        Result := AToolbarCommands();
      end;
    end;
end;

class procedure TAtlasPageOptions.ConnectTransfer(APage: TAtlasSettingsPage);
begin
  // Werte „aus .atlas“ auch bei noch ausgeschaltetem Schalter; Öffnen legt die Datei an.
  APage.Part<TAtlasSettingsTeamFilePart>.OnTeamFile :=
    function: TAtlasTeamSettings
    begin
      Result := TAtlasIdeTeamFile.Read(TAtlasIdeFiles.ActiveProjectFile);
    end;
  APage.Part<TAtlasSettingsTeamFilePart>.OnOpenTeamFile :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeTeamFile.OpenInEditor;
        end);
    end;
  // Mit den Werten der Seite; Import und Zurücksetzen speichern sofort (mit Sicherung), die Seite lädt danach neu.
  APage.Part<TAtlasSettingsTransferPart>.OnExportSettings :=
    procedure(ACurrent: TAtlasPluginSettings)
    begin
      TAtlasIdeSettingsTransfer.ExportSettings(ACurrent);
    end;
  APage.Part<TAtlasSettingsTransferPart>.OnImportSettings :=
    function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean; out AResult: TAtlasPluginSettings): Boolean
    begin
      Result := TAtlasIdeSettingsTransfer.ImportSettings(ACurrent, AProfile, AResult);
    end;
  APage.Part<TAtlasSettingsTransferPart>.OnResetAllSettings :=
    function(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean
    begin
      Result := TAtlasIdeSettingsTransfer.ResetAll(ACurrent, AResult);
    end;
end;

class function TAtlasPageOptions.SettingKeyAt(APage: TAtlasSettingsPage; AControl: TControl): string;
var
  mControl: TControl;
  mName: string;
  mIndex: Integer;
begin
  Result := '';
  mControl := AControl;
  while (Result = '') and (mControl <> nil) and (mControl <> APage) do
  begin
    for mName in APage.Marks.NamesOf(mControl) do
    begin
      mIndex := APage.Catalog.IndexOfName(mName);
      if (Result = '') and (mIndex >= 0) then
      begin
        Result := APage.Catalog.Entries[mIndex].Key;
      end;
    end;
    mControl := mControl.Parent;
  end;
end;

class procedure TAtlasPageOptions.ConnectHelp(APage: TAtlasSettingsPage);
begin
  TAtlasIdeHelp.AddKey(APage,
    function(out ATopic: TAtlasHelpTopic): Boolean
    var
      mKey: string;
    begin
      mKey := SettingKeyAt(APage, Screen.ActiveControl);
      if mKey <> '' then
      begin
        ATopic := TAtlasIdeHelp.Topic(TAtlasHelpKind.Setting, mKey);
      end
      else
      begin
        ATopic := TAtlasIdeHelp.Topic(TAtlasHelpKind.Window, TAtlasIdeHelp.cOptionsWindow);
      end;
      Result := True;
    end);
end;

end.
