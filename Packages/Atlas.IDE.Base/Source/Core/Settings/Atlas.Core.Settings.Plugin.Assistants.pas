unit Atlas.Core.Settings.Plugin.Assistants;

// Einstellungen des IDE-Plugins, Bereich KI-Anbieter des Moduls KI-Assistenten (assistants.*, #1922, #2056):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch. Schlüssel stehen nie hier,
// nur im Anmeldespeicher von Windows.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen und Vorgabe für assistants.contextLines.</summary>
  cMinAssistantsContextLines = 10;
  cMaxAssistantsContextLines = 200;
  cDefaultAssistantsContextLines = 40;
  /// <summary>Grenzen und Vorgabe für assistants.dailyLimit.</summary>
  cMinAssistantsDailyLimit = 1;
  cMaxAssistantsDailyLimit = 100000;
  cDefaultAssistantsDailyLimit = 300;
  /// <summary>Werte für assistants.provider; der erste heißt „keiner“.</summary>
  cAssistantsProviderNames: array[0..2] of string = ('none', 'anthropic', 'openai-compatible');
  /// <summary>Vorgabe für assistants.model: kleines, schnelles Modell des ersten Anbieters.</summary>
  cDefaultAssistantsModel = 'claude-haiku-5-5';
  /// <summary>Vorgabe für assistants.openaiCompatible.url: lokaler Server auf dem üblichen Port.</summary>
  cDefaultAssistantsOpenAiUrl = 'http://localhost:1234/v1';
  /// <summary>Grenzen und Vorgabe für assistants.openaiCompatible.timeoutMs.</summary>
  cMinAssistantsOpenAiTimeoutMs = 500;
  cMaxAssistantsOpenAiTimeoutMs = 30000;
  cDefaultAssistantsOpenAiTimeoutMs = 3000;

type
  /// <summary>Plugin-Einstellungen: KI-Anbieter für Schattentext-Vorschläge.</summary>
  TAtlasPluginAssistantsSettings = record
    /// <summary>Schattentext-Vorschläge über einen KI-Anbieter (assistants.inlineSuggestions); aus = kein
    /// Netzverkehr.</summary>
    AssistantsInlineSuggestions: Boolean;
    /// <summary>Anbieter (assistants.provider), einer aus cAssistantsProviderNames.</summary>
    AssistantsProvider: string;
    /// <summary>Modell des Anbieters (assistants.model).</summary>
    AssistantsModel: string;
    /// <summary>Zeilen um die Schreibmarke, die an den Anbieter gehen (assistants.contextLines).</summary>
    AssistantsContextLines: Integer;
    /// <summary>Muster für Dateien, aus denen nichts gesendet wird (assistants.exclude), durch Semikolon getrennt.
    /// </summary>
    AssistantsExclude: string;
    /// <summary>Höchstzahl der Anfragen je Tag (assistants.dailyLimit).</summary>
    AssistantsDailyLimit: Integer;
    /// <summary>Adresse des OpenAI-kompatiblen Servers (assistants.openaiCompatible.url, #2056).</summary>
    AssistantsOpenAiUrl: string;
    /// <summary>Modell beim OpenAI-kompatiblen Server (assistants.openaiCompatible.model); leer = keine Anfrage.
    /// </summary>
    AssistantsOpenAiModel: string;
    /// <summary>Zeitlimit je Anfrage an den OpenAI-kompatiblen Server (assistants.openaiCompatible.timeoutMs).
    /// </summary>
    AssistantsOpenAiTimeoutMs: Integer;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginAssistantsSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils;

{ TAtlasPluginAssistantsSettings }

class function TAtlasPluginAssistantsSettings.Defaults: TAtlasPluginAssistantsSettings;
begin
  Result.AssistantsInlineSuggestions := False;
  Result.AssistantsProvider := cAssistantsProviderNames[0];
  Result.AssistantsModel := cDefaultAssistantsModel;
  Result.AssistantsContextLines := cDefaultAssistantsContextLines;
  Result.AssistantsExclude := '';
  Result.AssistantsDailyLimit := cDefaultAssistantsDailyLimit;
  Result.AssistantsOpenAiUrl := cDefaultAssistantsOpenAiUrl;
  Result.AssistantsOpenAiModel := '';
  Result.AssistantsOpenAiTimeoutMs := cDefaultAssistantsOpenAiTimeoutMs;
end;

procedure TAtlasPluginAssistantsSettings.Normalize;
begin
  AssistantsProvider := Choice(AssistantsProvider, cAssistantsProviderNames);
  AssistantsModel := Trim(AssistantsModel);
  if AssistantsModel = '' then
  begin
    AssistantsModel := cDefaultAssistantsModel;
  end;
  AssistantsContextLines := EnsureRange(AssistantsContextLines, cMinAssistantsContextLines,
    cMaxAssistantsContextLines);
  AssistantsExclude := Trim(AssistantsExclude);
  AssistantsDailyLimit := EnsureRange(AssistantsDailyLimit, cMinAssistantsDailyLimit, cMaxAssistantsDailyLimit);
  AssistantsOpenAiUrl := Trim(AssistantsOpenAiUrl);
  if AssistantsOpenAiUrl = '' then
  begin
    AssistantsOpenAiUrl := cDefaultAssistantsOpenAiUrl;
  end;
  AssistantsOpenAiModel := Trim(AssistantsOpenAiModel);
  AssistantsOpenAiTimeoutMs := EnsureRange(AssistantsOpenAiTimeoutMs, cMinAssistantsOpenAiTimeoutMs,
    cMaxAssistantsOpenAiTimeoutMs);
end;

procedure TAtlasPluginAssistantsSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('AssistantsInlineSuggestions', AssistantsInlineSuggestions);
  AIo.Text('AssistantsProvider', AssistantsProvider);
  AIo.Text('AssistantsModel', AssistantsModel);
  AIo.Number('AssistantsContextLines', AssistantsContextLines);
  AIo.Text('AssistantsExclude', AssistantsExclude);
  AIo.Number('AssistantsDailyLimit', AssistantsDailyLimit);
  AIo.Text('AssistantsOpenAiUrl', AssistantsOpenAiUrl);
  AIo.Text('AssistantsOpenAiModel', AssistantsOpenAiModel);
  AIo.Number('AssistantsOpenAiTimeoutMs', AssistantsOpenAiTimeoutMs);
end;

end.
