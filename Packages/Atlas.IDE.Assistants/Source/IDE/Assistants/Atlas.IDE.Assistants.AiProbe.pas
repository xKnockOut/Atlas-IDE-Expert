unit Atlas.IDE.Assistants.AiProbe;

// „Verbindung testen“ und „Modelle abrufen“ auf der Optionsseite (#2056): eine
// kleine Anfrage bzw. GET /models im Hintergrund mit den Werten, wie sie gerade
// auf der Seite stehen; das Ergebnis kommt als Text im Hauptthread an
// (TAtlasMainThread, verworfen, wenn das Modul abgemeldet ist).
// - Probe: Dauer und Modell; dauert die Antwort länger als die Tipppause
//   (suggestions.delayMs), sagt der Text, dass der Schattentext darauf wartet.
// - Modelle: nur der OpenAI-kompatible Anbieter kennt eine Liste; ohne Liste
//   bleibt das Feld zum Eintragen.
// Destroy bricht laufende Anfragen ab und wartet die Threads ab (Regel 3).

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.Catalog,
  Atlas.UI.Assistants.SettingsSection;

type
  TAtlasIdeAiProbe = class
  private
    FWorkers: TAtlasWorkerSlot;
    FHttp: IAtlasAiHttp;
    FKeys: TAtlasAiKeyReader;
    function ProviderOf(const AInput: TAtlasAssistantsProbeInput): IAtlasAiProvider;
  public
    constructor Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader);
    destructor Destroy; override;
    procedure Probe(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsProbeDone);
    procedure Models(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsModelsDone);
    /// <summary>Text zum Ergebnis einer Probe; ADelayMs ist die Tipppause.</summary>
    class function ProbeText(const AResult: TAtlasAiProbeResult; ADelayMs: Integer): string; static;
    /// <summary>Text zum Ergebnis der Modellliste.</summary>
    class function ModelsText(const AAnswer: TAtlasAiAnswer; ACount: Integer): string; static;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.AiGhost,
  Atlas.UI.Assistants.Strings;

{ TAtlasIdeAiProbe }

constructor TAtlasIdeAiProbe.Create(const AHttp: IAtlasAiHttp; const AKeys: TAtlasAiKeyReader);
begin
  inherited Create;
  FHttp := AHttp;
  FKeys := AKeys;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeAiProbe.Destroy;
begin
  if FHttp <> nil then
  begin
    FHttp.Cancel;
  end;
  if FWorkers <> nil then
  begin
    // Die Threads halten Transport und Schlüsselleser roh: erst nach ihrem Ende freigeben.
    FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  end;
  FreeAndNil(FWorkers);
  FHttp := nil;
  FKeys := nil;
  inherited Destroy;
end;

function TAtlasIdeAiProbe.ProviderOf(const AInput: TAtlasAssistantsProbeInput): IAtlasAiProvider;
var
  mSettings: TAtlasAiProviderSettings;
begin
  mSettings := Default(TAtlasAiProviderSettings);
  mSettings.Id := AInput.ProviderId;
  mSettings.Model := AInput.Model;
  mSettings.Url := AInput.Url;
  mSettings.TimeoutMs := AInput.TimeoutMs;
  Result := TAtlasAiProviders.Create(mSettings, FHttp, FKeys);
end;

/// <summary>Fehlertext mit der Meldung des Anbieters, wenn er eine hat.</summary>
function FailureText(const AAnswer: TAtlasAiAnswer): string;
begin
  Result := TAtlasIdeAiGhost.ErrorText(AAnswer.Error);
  if AAnswer.Detail <> '' then
  begin
    Result := Result + ' (' + AAnswer.Detail + ')';
  end;
end;

class function TAtlasIdeAiProbe.ProbeText(const AResult: TAtlasAiProbeResult; ADelayMs: Integer): string;
var
  mSeconds: string;
begin
  if not AResult.Answer.Ok then
  begin
    Exit(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ProbeFailed, [FailureText(AResult.Answer)]));
  end;
  mSeconds := FormatFloat('0.0', AResult.Ms / 1000, FormatSettings);
  if AResult.Ms > ADelayMs then
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ProbeSlow, [mSeconds, AResult.Answer.Model,
      ADelayMs]);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ProbeOk, [mSeconds, AResult.Answer.Model]);
  end;
end;

class function TAtlasIdeAiProbe.ModelsText(const AAnswer: TAtlasAiAnswer; ACount: Integer): string;
begin
  if AAnswer.Ok and (ACount > 0) then
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ModelsFound, [ACount]);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ModelsFailed, [FailureText(AAnswer)]);
  end;
end;

/// <summary>Thread der Probe; ADone im Hauptthread.</summary>
function ProbeThread(const AProvider: IAtlasAiProvider; ADelayMs: Integer; const ADone: TAtlasAssistantsProbeDone):
  TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mText: string;
    begin
      mText := TAtlasIdeAiProbe.ProbeText(TAtlasAiProviders.Probe(AProvider), ADelayMs);
      TAtlasMainThread.Queue(TAtlasFeature.Settings,
        procedure
        begin
          ADone(mText);
        end);
    end);
end;

/// <summary>Thread der Modellliste; ADone im Hauptthread.</summary>
function ModelsThread(const AModels: IAtlasAiModels; const ADone: TAtlasAssistantsModelsDone): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mList: TArray<string>;
      mText: string;
    begin
      mText := TAtlasIdeAiProbe.ModelsText(AModels.Models(mList), Length(mList));
      TAtlasMainThread.Queue(TAtlasFeature.Settings,
        procedure
        begin
          ADone(mList, mText);
        end);
    end);
end;

procedure TAtlasIdeAiProbe.Probe(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsProbeDone);
var
  mProvider: IAtlasAiProvider;
  mThread: TThread;
begin
  mProvider := ProviderOf(AInput);
  if mProvider = nil then
  begin
    ADone(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.KeyNoProvider));
    Exit;
  end;
  mThread := ProbeThread(mProvider, TAtlasIdeSettings.Current.SuggestionsDelayMs, ADone);
  FWorkers.Start(mThread);
end;

procedure TAtlasIdeAiProbe.Models(const AInput: TAtlasAssistantsProbeInput; const ADone: TAtlasAssistantsModelsDone);
var
  mModels: IAtlasAiModels;
  mThread: TThread;
begin
  if not Supports(ProviderOf(AInput), IAtlasAiModels, mModels) then
  begin
    ADone(nil, TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.ModelsFailed,
      [TAtlasIdeAiGhost.ErrorText(TAtlasAiError.BadAnswer)]));
    Exit;
  end;
  mThread := ModelsThread(mModels, ADone);
  FWorkers.Start(mThread);
end;

end.
