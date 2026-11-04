unit Atlas.Core.Settings.Plugin.Snippets;

// Einstellungen des IDE-Plugins, Bereich Vorlagen und Snippets (snippets.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Vorlagen und Snippets.</summary>
  TAtlasPluginSnippetsSettings = record
    /// <summary>Code-Vorlagen in der Vervollständigung (#51, completion.snippets).</summary>
    Snippets: Boolean;
    /// <summary>Live Templates der IDE als Code-Vorlagen einlesen (#51, completion.importIdeTemplates).</summary>
    ImportIdeTemplates: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginSnippetsSettings; static;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

{ TAtlasPluginSnippetsSettings }

class function TAtlasPluginSnippetsSettings.Defaults: TAtlasPluginSnippetsSettings;
begin
  Result.Snippets := True;
  Result.ImportIdeTemplates := True;
end;

procedure TAtlasPluginSnippetsSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('Snippets', Snippets);
  AIo.Flag('ImportIdeTemplates', ImportIdeTemplates);
end;

end.
