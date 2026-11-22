unit Atlas.IDE.Assistants.Adapters.AiText;

// Text vom eingestellten KI-Anbieter für andere Module (#2462, Vertrag
// Atlas.IDE.Contracts.AiText): Anbieter, Modell und Schlüssel wie beim
// KI-Schattentext (assistants.provider, Anmeldespeicher), ohne Tagesgrenze, weil
// jede Anfrage ein Knopfdruck ist.
// - Jede Anfrage bekommt ihren eigenen Transport: Cancel bricht nur sie ab.
// - Das Ergebnis kommt über TAtlasMainThread; ist das Ticket inzwischen
//   abgebrochen, wird es verworfen (Cancel und Zustellung beide im Hauptthread).
// - Stop (Abmelden des Moduls) bricht alle Anfragen ab, wartet die Threads ab
//   und meldet offenen Tickets Cancelled; danach ist der Dienst nicht mehr
//   bereit (Regel 3).
// - Protokoll und Fehlertexte nennen nie Schlüssel oder Inhalt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.Catalog,
  Atlas.IDE.Contracts.AiText;

type
  /// <summary>Neuer Transport je Anfrage.</summary>
  TAtlasAiHttpFactory = reference to function: IAtlasAiHttp;

  TAtlasIdeAiText = class(TInterfacedObject, IAtlasAiText)
  private type
    TPending = record
      Done: TAtlasAiTextDone;
      Http: IAtlasAiHttp;
    end;
  private
    FWorkers: TAtlasWorkerSlot;
    FNewHttp: TAtlasAiHttpFactory;
    FKeys: TAtlasAiKeyReader;
    FHasKey: TFunc<string, Boolean>;
    FPending: TDictionary<Integer, TPending>;
    FNext: Integer;
    FStopped: Boolean;
    function CurrentSettings: TAtlasAiProviderSettings;
    /// <summary>Ergebnis von ATicket zustellen, wenn es noch offen ist (Hauptthread).</summary>
    procedure Finish(ATicket: Integer; const AResult: TAtlasAiTextResult);
  public
    /// <summary>AHasKey: liegt ein Schlüssel für den Anbieter (Argument) im Anmeldespeicher?</summary>
    constructor Create(const ANewHttp: TAtlasAiHttpFactory; const AKeys: TAtlasAiKeyReader;
      const AHasKey: TFunc<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Alle Anfragen abbrechen, Threads abwarten, offenen Tickets Cancelled melden.</summary>
    procedure Stop;
    function Ready: Boolean;
    function ProviderName: string;
    function Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
    procedure Cancel(ATicket: Integer);
    /// <summary>Ergebnis zur Antwort des Anbieters (Fehlertext mit seiner Meldung).</summary>
    class function ResultOf(const AAnswer: TAtlasAiAnswer): TAtlasAiTextResult; static;
  end;

implementation

uses
  System.Classes,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.Core.AiProviders.OpenAiCompatible,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.AiErrors,
  Atlas.UI.Assistants.Strings;

const
  /// <summary>Zeitlimit einer Anfrage, wenn der Anbieter keins aus den Einstellungen hat.</summary>
  cTimeoutMs = 60000;

function ResultWith(AStatus: TAtlasAiTextStatus; const AError: string): TAtlasAiTextResult;
begin
  Result := Default(TAtlasAiTextResult);
  Result.Status := AStatus;
  Result.Error := AError;
end;

{ TAtlasIdeAiText }

constructor TAtlasIdeAiText.Create(const ANewHttp: TAtlasAiHttpFactory; const AKeys: TAtlasAiKeyReader;
  const AHasKey: TFunc<string, Boolean>);
begin
  inherited Create;
  FNewHttp := ANewHttp;
  FKeys := AKeys;
  FHasKey := AHasKey;
  FPending := TDictionary<Integer, TPending>.Create;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
end;

destructor TAtlasIdeAiText.Destroy;
begin
  Stop;
  FreeAndNil(FWorkers);
  FreeAndNil(FPending);
  inherited Destroy;
end;

procedure TAtlasIdeAiText.Stop;
var
  mPending: TPending;
  mOpen: TArray<TPending>;
  mDone: TAtlasAiTextDone;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  for mPending in FPending.Values do
  begin
    mPending.Http.Cancel;
  end;
  // Die Threads halten Transport und Schlüsselleser: erst nach ihrem Ende loslassen.
  FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  mOpen := FPending.Values.ToArray;
  FPending.Clear;
  for mPending in mOpen do
  begin
    mDone := mPending.Done;
    mDone(ResultWith(TAtlasAiTextStatus.Cancelled, ''));
  end;
  FNewHttp := nil;
  FKeys := nil;
  FHasKey := nil;
end;

function TAtlasIdeAiText.CurrentSettings: TAtlasAiProviderSettings;
begin
  Result := TAtlasAiProviders.SettingsOf(TAtlasIdeSettings.Current);
end;

function TAtlasIdeAiText.Ready: Boolean;
var
  mSettings: TAtlasAiProviderSettings;
begin
  if FStopped then
  begin
    Exit(False);
  end;
  mSettings := CurrentSettings;
  Result := TAtlasAiProviders.Ready(mSettings, FHasKey(mSettings.Id));
end;

function TAtlasIdeAiText.ProviderName: string;
var
  mSettings: TAtlasAiProviderSettings;
begin
  mSettings := CurrentSettings;
  if SameText(mSettings.Id, TAtlasOpenAiApi.cId) then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.ProviderOpenAi);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.ProviderAnthropic);
  end;
  if mSettings.Model <> '' then
  begin
    Result := Result + ', ' + mSettings.Model;
  end;
end;

class function TAtlasIdeAiText.ResultOf(const AAnswer: TAtlasAiAnswer): TAtlasAiTextResult;
begin
  if AAnswer.Ok then
  begin
    Result := ResultWith(TAtlasAiTextStatus.Ok, '');
    Result.Text := AAnswer.Text;
    Exit;
  end;
  if AAnswer.Error = TAtlasAiError.Cancelled then
  begin
    Exit(ResultWith(TAtlasAiTextStatus.Cancelled, ''));
  end;
  Result := ResultWith(TAtlasAiTextStatus.Failed, TAtlasAiErrorTexts.Text(AAnswer.Error));
  if AAnswer.Detail <> '' then
  begin
    Result.Error := Result.Error + ' (' + AAnswer.Detail + ')';
  end;
end;

/// <summary>Thread einer Anfrage; das Ergebnis geht über AOwner.Finish in den Hauptthread.</summary>
function AskThread(AOwner: TAtlasIdeAiText; ATicket: Integer; const AProvider: IAtlasAiProvider;
  const APrompt: TAtlasAiPrompt): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasAiTextResult;
    begin
      mResult := TAtlasIdeAiText.ResultOf(AProvider.Complete(APrompt));
      if mResult.Status = TAtlasAiTextStatus.Failed then
      begin
        TAtlasGuard.Log('KI-Anfrage (' + AProvider.Id + ') gescheitert: ' + TAtlasGuard.MessageText(mResult.Error));
      end;
      // Stop wartet auf diesen Thread, bevor AOwner geht; der Eintrag verfällt mit dem Modul.
      TAtlasMainThread.Queue(TAtlasFeature.Settings,
        procedure
        begin
          AOwner.Finish(ATicket, mResult);
        end);
    end);
end;

function TAtlasIdeAiText.Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
var
  mSettings: TAtlasAiProviderSettings;
  mPending: TPending;
  mProvider: IAtlasAiProvider;
  mPrompt: TAtlasAiPrompt;
begin
  Result := 0;
  if not Ready then
  begin
    ADone(ResultWith(TAtlasAiTextStatus.NotReady, ''));
    Exit;
  end;
  mSettings := CurrentSettings;
  mPending.Done := ADone;
  mPending.Http := FNewHttp();
  mProvider := TAtlasAiProviders.Create(mSettings, mPending.Http, FKeys);
  mPrompt := Default(TAtlasAiPrompt);
  mPrompt.Instructions := ARequest.Instructions;
  mPrompt.Task := ARequest.Task;
  mPrompt.MaxTokens := ARequest.MaxTokens;
  mPrompt.TimeoutMs := cTimeoutMs;
  Inc(FNext);
  Result := FNext;
  FPending.Add(Result, mPending);
  FWorkers.Start(AskThread(Self, Result, mProvider, mPrompt));
end;

procedure TAtlasIdeAiText.Cancel(ATicket: Integer);
var
  mPending: TPending;
begin
  if FPending.TryGetValue(ATicket, mPending) then
  begin
    FPending.Remove(ATicket);
    mPending.Http.Cancel;
  end;
end;

procedure TAtlasIdeAiText.Finish(ATicket: Integer; const AResult: TAtlasAiTextResult);
var
  mPending: TPending;
begin
  if (FPending = nil) or not FPending.TryGetValue(ATicket, mPending) then
  begin
    Exit;
  end;
  FPending.Remove(ATicket);
  mPending.Done(AResult);
end;

end.
