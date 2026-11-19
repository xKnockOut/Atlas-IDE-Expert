unit Atlas.Core.AiProviders.Catalog;

// Welche Anbieter es gibt (#1922, #2056): aus den Einstellungen den Anbieter
// bauen. "none" und unbekannte Werte ergeben nil. Dazu die kleine Probe für
// „Verbindung testen“ auf der Optionsseite.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.AiProviders.Contract;

type
  /// <summary>Was ein Anbieter aus den Einstellungen braucht (auch ungespeicherte Werte der Optionsseite).
  /// </summary>
  TAtlasAiProviderSettings = record
    Id: string;
    Model: string;
    /// <summary>Nur OpenAI-kompatibel: Adresse und Zeitlimit.</summary>
    Url: string;
    TimeoutMs: Integer;
  end;

  /// <summary>Ergebnis von „Verbindung testen“.</summary>
  TAtlasAiProbeResult = record
    Answer: TAtlasAiAnswer;
    /// <summary>Dauer der Anfrage.</summary>
    Ms: Int64;
  end;

  TAtlasAiProviders = class
  public const
    cNone = 'none';
    /// <summary>Zeitlimit der Probe; großzügig, damit auch ein lokales Modell beim ersten Laden antwortet.
    /// </summary>
    cProbeTimeoutMs = 30000;
    /// <summary>Kleinste Aufgabe der Probe; an den Anbieter, deshalb englisch.</summary>
    cProbeTask = 'Reply with the single word OK.';
    cProbeMaxTokens = 16;
  public
    /// <summary>Anbieter nach ASettings; nil für "none" und unbekannte Werte.</summary>
    class function Create(const ASettings: TAtlasAiProviderSettings; const AHttp: IAtlasAiHttp;
      const AKeys: TAtlasAiKeyReader): IAtlasAiProvider; static;
    /// <summary>Anbietereinstellungen aus den gespeicherten Einstellungen.</summary>
    class function SettingsOf(const ASettings: TAtlasPluginSettings): TAtlasAiProviderSettings; static;
    /// <summary>Braucht der Anbieter AId einen Schlüssel (ohne geht nichts hinaus)?</summary>
    class function NeedsKey(const AId: string): Boolean; static;
    /// <summary>Kann der Anbieter AId einen Schlüssel brauchen (Knöpfe auf der Optionsseite)?</summary>
    class function TakesKey(const AId: string): Boolean; static;
    /// <summary>Kleine Anfrage für „Verbindung testen“; misst die Dauer. Im Hintergrund-Thread.</summary>
    class function Probe(const AProvider: IAtlasAiProvider): TAtlasAiProbeResult; static;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.AiProviders.Anthropic,
  Atlas.Core.AiProviders.OpenAiCompatible;

{ TAtlasAiProviders }

class function TAtlasAiProviders.Create(const ASettings: TAtlasAiProviderSettings; const AHttp: IAtlasAiHttp;
  const AKeys: TAtlasAiKeyReader): IAtlasAiProvider;
begin
  Result := nil;
  if SameText(ASettings.Id, TAtlasAnthropicApi.cId) then
  begin
    Result := TAtlasAnthropicProvider.Create(AHttp, AKeys, ASettings.Model);
  end
  else if SameText(ASettings.Id, TAtlasOpenAiApi.cId) then
  begin
    Result := TAtlasOpenAiProvider.Create(AHttp, AKeys, ASettings.Url, ASettings.Model, ASettings.TimeoutMs);
  end;
end;

class function TAtlasAiProviders.SettingsOf(const ASettings: TAtlasPluginSettings): TAtlasAiProviderSettings;
begin
  Result := Default(TAtlasAiProviderSettings);
  Result.Id := ASettings.AssistantsProvider;
  Result.Model := ASettings.AssistantsModel;
  if SameText(Result.Id, TAtlasOpenAiApi.cId) then
  begin
    Result.Model := ASettings.AssistantsOpenAiModel;
    Result.Url := ASettings.AssistantsOpenAiUrl;
    Result.TimeoutMs := ASettings.AssistantsOpenAiTimeoutMs;
  end;
end;

class function TAtlasAiProviders.NeedsKey(const AId: string): Boolean;
begin
  Result := SameText(AId, TAtlasAnthropicApi.cId);
end;

class function TAtlasAiProviders.TakesKey(const AId: string): Boolean;
begin
  Result := SameText(AId, TAtlasAnthropicApi.cId) or SameText(AId, TAtlasOpenAiApi.cId);
end;

class function TAtlasAiProviders.Probe(const AProvider: IAtlasAiProvider): TAtlasAiProbeResult;
var
  mPrompt: TAtlasAiPrompt;
  mWatch: TStopwatch;
begin
  Result := Default(TAtlasAiProbeResult);
  mPrompt := Default(TAtlasAiPrompt);
  mPrompt.Task := cProbeTask;
  mPrompt.MaxTokens := cProbeMaxTokens;
  mPrompt.TimeoutMs := cProbeTimeoutMs;
  mWatch := TStopwatch.StartNew;
  Result.Answer := AProvider.Complete(mPrompt);
  Result.Ms := mWatch.ElapsedMilliseconds;
end;

end.
