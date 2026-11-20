unit Atlas.IDE.Assistants.Adapters.TextRequests;

// Text für einfache Aufgaben von einem KI-Anbieter der IDE (Smart CodeInsight, #2744) hinter dem Vertrag
// IAtlasAiText. Die IDE antwortet asynchron mit der Kennung der Anfrage; diese Klasse ordnet die Antwort dem
// Aufrufer zu.
// - Ready: assistants.ideProvider an und ein passender Anbieter (TAtlasIdeAiProviders.Pick) da.
// - Hat der Anbieter „Anweisung“, geht Aufgabe und Anweisung getrennt hinaus, sonst beides als ein Chat-Text.
// - Antworten mit unbekannter Kennung (abgebrochen, fremd) werden verworfen; gleichzeitige Anfragen vermischen
//   sich nicht.
// - Cancel eines Tickets bricht beim Anbieter erst ab, wenn keine andere Anfrage an ihn mehr offen ist: Die IDE
//   kennt nur „alles abbrechen“.
// - Stop (Abmelden des Moduls) bricht alles ab und meldet offenen Tickets Cancelled; danach erreicht keine
//   Antwort mehr einen Aufrufer (Regel 3).
// Alle Aufrufe im Hauptthread; der Adapter reiht die Antworten der IDE über TAtlasMainThread ein.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.IDE.Contracts.AiText,
  Atlas.Core.Assistants.Contract.IdeAi;

type
  /// <summary>Einstellungen, bei jeder Anfrage neu gelesen.</summary>
  TAtlasIdeAiTextOptions = record
    /// <summary>assistants.ideProvider</summary>
    Enabled: Boolean;
    /// <summary>assistants.ideProvider.name; '' = erster passender.</summary>
    Wanted: string;
  end;

  TAtlasIdeAiTextOptionsOf = reference to function: TAtlasIdeAiTextOptions;

  TAtlasIdeAiTextRequests = class(TInterfacedObject, IAtlasAiText)
  private type
    TPending = record
      Ticket: Integer;
      Provider: string;
      Done: TAtlasAiTextDone;
    end;
  private
    FEngine: IAtlasIdeAiEngine;
    FOptions: TAtlasIdeAiTextOptionsOf;
    /// <summary>Text bei abgelehnter Anfrage, %s = Anbieter.</summary>
    FRefused: string;
    /// <summary>Offene Anfragen nach der Kennung der IDE.</summary>
    FPending: TDictionary<string, TPending>;
    FNext: Integer;
    FStopped: Boolean;
    function Current(out AProvider: TAtlasIdeAiProvider): Boolean;
    function Busy(const AProvider: string): Boolean;
    /// <summary>Offene Anfrage zur Kennung AId herausnehmen; False, wenn sie nicht (mehr) offen ist.</summary>
    function Take(const AId: string; out APending: TPending): Boolean;
  public
    /// <summary>ARefused: Fehlertext, wenn die IDE die Anfrage nicht annimmt (%s = Anbieter).</summary>
    constructor Create(const AEngine: IAtlasIdeAiEngine; const AOptions: TAtlasIdeAiTextOptionsOf;
      const ARefused: string);
    destructor Destroy; override;
    /// <summary>Alles abbrechen und offenen Tickets Cancelled melden; danach nie mehr bereit.</summary>
    procedure Stop;
    function Ready: Boolean;
    function ProviderName: string;
    function Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
    procedure Cancel(ATicket: Integer);
    /// <summary>Antwort der IDE auf die Anfrage AId.</summary>
    procedure Answered(const AId, AText: string);
    /// <summary>Fehler der IDE zur Anfrage AId.</summary>
    procedure Failed(const AId, AMessage: string);
    /// <summary>Anfragen, auf die noch eine Antwort aussteht.</summary>
    function OpenCount: Integer;
    /// <summary>Text für einen Anbieter ohne Anweisung: Anweisung, Leerzeile, Aufgabe.</summary>
    class function ChatText(const AInstructions, ATask: string): string; static;
  end;

implementation

uses
  Atlas.Core.Assistants.IdeProviders;

function ResultWith(AStatus: TAtlasAiTextStatus; const AText, AError: string): TAtlasAiTextResult;
begin
  Result := Default(TAtlasAiTextResult);
  Result.Status := AStatus;
  Result.Text := AText;
  Result.Error := AError;
end;

{ TAtlasIdeAiTextRequests }

constructor TAtlasIdeAiTextRequests.Create(const AEngine: IAtlasIdeAiEngine; const AOptions: TAtlasIdeAiTextOptionsOf;
  const ARefused: string);
begin
  inherited Create;
  FEngine := AEngine;
  FOptions := AOptions;
  FRefused := ARefused;
  FPending := TDictionary<string, TPending>.Create;
end;

destructor TAtlasIdeAiTextRequests.Destroy;
begin
  Stop;
  FreeAndNil(FPending);
  inherited Destroy;
end;

class function TAtlasIdeAiTextRequests.ChatText(const AInstructions, ATask: string): string;
begin
  if Trim(AInstructions) = '' then
  begin
    Exit(ATask);
  end;
  Result := AInstructions + sLineBreak + sLineBreak + ATask;
end;

function TAtlasIdeAiTextRequests.Current(out AProvider: TAtlasIdeAiProvider): Boolean;
var
  mOptions: TAtlasIdeAiTextOptions;
begin
  AProvider := Default(TAtlasIdeAiProvider);
  if FStopped then
  begin
    Exit(False);
  end;
  mOptions := FOptions();
  Result := mOptions.Enabled and TAtlasIdeAiProviders.Pick(FEngine.Providers, mOptions.Wanted, AProvider);
end;

function TAtlasIdeAiTextRequests.Ready: Boolean;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Result := Current(mProvider);
end;

function TAtlasIdeAiTextRequests.ProviderName: string;
var
  mProvider: TAtlasIdeAiProvider;
begin
  Result := '';
  if Current(mProvider) then
  begin
    Result := mProvider.Name;
  end;
end;

function TAtlasIdeAiTextRequests.Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
var
  mProvider: TAtlasIdeAiProvider;
  mId: string;
  mPending: TPending;
begin
  Result := 0;
  if not Current(mProvider) then
  begin
    ADone(ResultWith(TAtlasAiTextStatus.NotReady, '', ''));
    Exit;
  end;
  if TAtlasIdeAiFeature.Instruction in mProvider.Features then
  begin
    mId := FEngine.Instruction(mProvider.Name, ARequest.Task, ARequest.Instructions);
  end
  else
  begin
    mId := FEngine.Chat(mProvider.Name, ChatText(ARequest.Instructions, ARequest.Task));
  end;
  if mId = '' then
  begin
    ADone(ResultWith(TAtlasAiTextStatus.Failed, '', Format(FRefused, [mProvider.Name])));
    Exit;
  end;
  Inc(FNext);
  Result := FNext;
  mPending.Ticket := Result;
  mPending.Provider := mProvider.Name;
  mPending.Done := ADone;
  FPending.AddOrSetValue(mId, mPending);
end;

function TAtlasIdeAiTextRequests.Busy(const AProvider: string): Boolean;
var
  mPending: TPending;
begin
  for mPending in FPending.Values do
  begin
    if SameText(mPending.Provider, AProvider) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasIdeAiTextRequests.Cancel(ATicket: Integer);
var
  mPair: TPair<string, TPending>;
  mProvider: string;
begin
  for mPair in FPending do
  begin
    if mPair.Value.Ticket = ATicket then
    begin
      mProvider := mPair.Value.Provider;
      FPending.Remove(mPair.Key);
      if (FEngine <> nil) and not Busy(mProvider) then
      begin
        FEngine.Cancel(mProvider);
      end;
      Exit;
    end;
  end;
end;

function TAtlasIdeAiTextRequests.Take(const AId: string; out APending: TPending): Boolean;
begin
  APending := Default(TPending);
  Result := (FPending <> nil) and FPending.TryGetValue(AId, APending);
  if Result then
  begin
    FPending.Remove(AId);
  end;
end;

procedure TAtlasIdeAiTextRequests.Answered(const AId, AText: string);
var
  mPending: TPending;
begin
  if Take(AId, mPending) then
  begin
    mPending.Done(ResultWith(TAtlasAiTextStatus.Ok, AText, ''));
  end;
end;

procedure TAtlasIdeAiTextRequests.Failed(const AId, AMessage: string);
var
  mPending: TPending;
begin
  if Take(AId, mPending) then
  begin
    mPending.Done(ResultWith(TAtlasAiTextStatus.Failed, '', mPending.Provider + ': ' + AMessage));
  end;
end;

function TAtlasIdeAiTextRequests.OpenCount: Integer;
begin
  Result := 0;
  if FPending <> nil then
  begin
    Result := FPending.Count;
  end;
end;

procedure TAtlasIdeAiTextRequests.Stop;
var
  mOpen: TArray<TPending>;
  mPending: TPending;
  mCancelled: TList<string>;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  mOpen := FPending.Values.ToArray;
  FPending.Clear;
  mCancelled := TList<string>.Create;
  try
    for mPending in mOpen do
    begin
      if (FEngine <> nil) and not mCancelled.Contains(mPending.Provider) then
      begin
        mCancelled.Add(mPending.Provider);
        FEngine.Cancel(mPending.Provider);
      end;
    end;
  finally
    mCancelled.Free;
  end;
  for mPending in mOpen do
  begin
    mPending.Done(ResultWith(TAtlasAiTextStatus.Cancelled, '', ''));
  end;
  FEngine := nil;
  FOptions := nil;
end;

end.
