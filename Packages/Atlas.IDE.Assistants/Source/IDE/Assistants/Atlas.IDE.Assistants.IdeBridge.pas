unit Atlas.IDE.Assistants.IdeBridge;

// Der eigene KI-Anbieter von Atlas (#1922, #2056) als Anbieter der IDE (Smart CodeInsight, #2745), ohne Bezug auf
// ToolsAPI.AI: Der Adapter Atlas.IDE.Assistants.Adapters.IdePlugin reicht die Aufrufe der IDE hierher und die
// Rückmeldungen an die Notifier der IDE weiter.
// - Name „Atlas (<Anbieter, Modell>)“; Funktionen Chat und Anweisung, Modelle nur, wenn der Anbieter eine Liste
//   liefern kann. Bild, Sprache und Moderation meldet Atlas nicht.
// - Jede Anfrage bekommt sofort eine Kennung; die Antwort geht später mit dieser Kennung an alle Notifier, auch
//   ein sofortiger Fehler (die IDE kennt die Kennung erst nach der Rückkehr).
// - Anfragen laufen über denselben Anbieter wie Atlas selbst und zählen zur selben Tagesgrenze
//   (assistants.dailyLimit). Einen Dateibezug liefert die IDE nicht, assistants.exclude greift daher nicht.
// - Cancel bricht alle laufenden Anfragen ab; Stop ebenso und trennt die Notifier: Danach erreicht nichts mehr die
//   IDE über dieses Objekt, und Antworten aus dem Hintergrund finden es nicht mehr (Regel 3).
// Alle Aufrufe im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.IDE.Base.Foundation.AiText,
  Atlas.Core.Assistants.Contract.IdeAi;

type
  /// <summary>Modelle des eigenen Anbieters: Liste oder '' bzw. Fehlertext (Liste leer). Im Hauptthread.</summary>
  TAtlasIdeAiModelsDone = reference to procedure(const AModels: TArray<string>; const AError: string);
  /// <summary>Holt die Modelle im Hintergrund.</summary>
  TAtlasIdeAiModelLister = reference to procedure(const ADone: TAtlasIdeAiModelsDone);
  /// <summary>Zählt eine Anfrage zur Tagesgrenze: '' wenn sie zählt, sonst der Grund.</summary>
  TAtlasIdeAiTake = reference to function: string;
  /// <summary>AWork später im Hauptthread ausführen.</summary>
  TAtlasIdeAiPost = reference to procedure(const AWork: TProc);

  /// <summary>Notifier der IDE; nach Cut leer. Rückmeldungen aus dem Hintergrund halten nur diese Liste.</summary>
  IAtlasIdeAiNotifierList = interface
    ['{D84E7B21-5C0A-4F3E-8B69-1A2F7C9E4D05}']
    function Add(const ANotifier: IAtlasIdeAiAnswers): Integer;
    procedure Remove(AIndex: Integer);
    function Snapshot: TArray<IAtlasIdeAiAnswers>;
    procedure Cut;
  end;

  /// <summary>Texte der Brücke (Sprache der IDE).</summary>
  TAtlasIdeAiBridgeTexts = record
    /// <summary>Kein eigener Anbieter eingerichtet.</summary>
    NotReady: string;
    /// <summary>Anbieter liefert keine Modellliste.</summary>
    NoModels: string;
  end;

  TAtlasIdeAiBridge = class
  private
    FText: IAtlasAiText;
    FTake: TAtlasIdeAiTake;
    FModels: TAtlasIdeAiModelLister;
    FPost: TAtlasIdeAiPost;
    FNewId: TFunc<string>;
    FTexts: TAtlasIdeAiBridgeTexts;
    FNotifiers: IAtlasIdeAiNotifierList;
    /// <summary>Kennung der IDE → Ticket beim eigenen Anbieter (0, solange Ask noch läuft).</summary>
    FTickets: TDictionary<string, Integer>;
    FStopped: Boolean;
    function Send(const AInstructions, ATask: string): string;
    function DoneFor(const AId: string): TAtlasAiTextDone;
    procedure Finished(const AId: string; const AResult: TAtlasAiTextResult);
    procedure Deliver(const AId, AText: string; AIsError: Boolean);
  public
    /// <summary>AText: eigener Anbieter; ATake: Tagesgrenze; AModels: Modellliste oder nil; APost: später im
    /// Hauptthread; ANewId: neue Kennung (nil = GUID).</summary>
    constructor Create(const AText: IAtlasAiText; const ATake: TAtlasIdeAiTake; const AModels: TAtlasIdeAiModelLister;
      const APost: TAtlasIdeAiPost; const ATexts: TAtlasIdeAiBridgeTexts; const ANewId: TFunc<string>);
    destructor Destroy; override;
    function Name: string;
    function Enabled: Boolean;
    function Features: TAtlasIdeAiFeatures;
    function Chat(const AQuestion: string): string;
    function Instruction(const AInput, AInstruction: string): string;
    function LoadModels: string;
    /// <summary>Alle laufenden Anfragen abbrechen; ihre Antworten kommen nicht mehr.</summary>
    procedure Cancel;
    function AddNotifier(const ANotifier: IAtlasIdeAiAnswers): Integer;
    procedure RemoveNotifier(AIndex: Integer);
    /// <summary>Alles abbrechen und die Notifier trennen.</summary>
    procedure Stop;
    /// <summary>Anfragen, auf die noch eine Antwort aussteht.</summary>
    function OpenCount: Integer;
  end;

implementation

uses
  Atlas.Core.Assistants.IdeProviders;

type
  TNotifierList = class(TInterfacedObject, IAtlasIdeAiNotifierList)
  private
    FItems: TDictionary<Integer, IAtlasIdeAiAnswers>;
    FNext: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const ANotifier: IAtlasIdeAiAnswers): Integer;
    procedure Remove(AIndex: Integer);
    function Snapshot: TArray<IAtlasIdeAiAnswers>;
    procedure Cut;
  end;

{ TNotifierList }

constructor TNotifierList.Create;
begin
  inherited Create;
  FItems := TDictionary<Integer, IAtlasIdeAiAnswers>.Create;
end;

destructor TNotifierList.Destroy;
begin
  FreeAndNil(FItems);
  inherited Destroy;
end;

function TNotifierList.Add(const ANotifier: IAtlasIdeAiAnswers): Integer;
begin
  Result := FNext;
  Inc(FNext);
  FItems.Add(Result, ANotifier);
end;

procedure TNotifierList.Remove(AIndex: Integer);
begin
  FItems.Remove(AIndex);
end;

function TNotifierList.Snapshot: TArray<IAtlasIdeAiAnswers>;
var
  mKeys: TArray<Integer>;
  mIndex: Integer;
begin
  Result := nil;
  mKeys := FItems.Keys.ToArray;
  TArray.Sort<Integer>(mKeys);
  SetLength(Result, Length(mKeys));
  for mIndex := 0 to High(mKeys) do
  begin
    Result[mIndex] := FItems[mKeys[mIndex]];
  end;
end;

procedure TNotifierList.Cut;
begin
  FItems.Clear;
end;

/// <summary>Rückmeldung an alle Notifier der Liste, wie sie bei der Ausführung ist.</summary>
function DeliveryOf(const AList: IAtlasIdeAiNotifierList; const AId, AText: string; AIsError: Boolean): TProc;
begin
  Result :=
    procedure
    var
      mNotifier: IAtlasIdeAiAnswers;
    begin
      for mNotifier in AList.Snapshot do
      begin
        if AIsError then
        begin
          mNotifier.Error(AText, AId);
        end
        else
        begin
          mNotifier.Answer(AText, AId);
        end;
      end;
    end;
end;

/// <summary>Modelle an alle Notifier der Liste.</summary>
function ModelsDeliveryOf(const AList: IAtlasIdeAiNotifierList; const AId: string): TAtlasIdeAiModelsDone;
begin
  Result :=
    procedure(const AModels: TArray<string>; const AError: string)
    var
      mNotifier: IAtlasIdeAiAnswers;
    begin
      for mNotifier in AList.Snapshot do
      begin
        if (Length(AModels) = 0) and (AError <> '') then
        begin
          mNotifier.Error(AError, AId);
        end
        else
        begin
          mNotifier.Models(AModels, AId);
        end;
      end;
    end;
end;

function NewGuidText: string;
var
  mGuid: TGUID;
begin
  CreateGUID(mGuid);
  Result := GUIDToString(mGuid);
end;

{ TAtlasIdeAiBridge }

constructor TAtlasIdeAiBridge.Create(const AText: IAtlasAiText; const ATake: TAtlasIdeAiTake;
  const AModels: TAtlasIdeAiModelLister; const APost: TAtlasIdeAiPost; const ATexts: TAtlasIdeAiBridgeTexts;
  const ANewId: TFunc<string>);
begin
  inherited Create;
  FText := AText;
  FTake := ATake;
  FModels := AModels;
  FPost := APost;
  FTexts := ATexts;
  FNewId := ANewId;
  if not Assigned(FNewId) then
  begin
    FNewId := NewGuidText;
  end;
  FNotifiers := TNotifierList.Create;
  FTickets := TDictionary<string, Integer>.Create;
end;

destructor TAtlasIdeAiBridge.Destroy;
begin
  Stop;
  FreeAndNil(FTickets);
  inherited Destroy;
end;

function TAtlasIdeAiBridge.Name: string;
var
  mProvider: string;
begin
  mProvider := '';
  if FText <> nil then
  begin
    mProvider := FText.ProviderName;
  end;
  Result := TAtlasIdeAiProviders.OwnName(mProvider);
end;

function TAtlasIdeAiBridge.Enabled: Boolean;
begin
  Result := (not FStopped) and (FText <> nil) and FText.Ready;
end;

function TAtlasIdeAiBridge.Features: TAtlasIdeAiFeatures;
begin
  Result := [TAtlasIdeAiFeature.Chat, TAtlasIdeAiFeature.Instruction];
  if Assigned(FModels) then
  begin
    Include(Result, TAtlasIdeAiFeature.ListModels);
  end;
end;

procedure TAtlasIdeAiBridge.Deliver(const AId, AText: string; AIsError: Boolean);
begin
  if Assigned(FPost) then
  begin
    FPost(DeliveryOf(FNotifiers, AId, AText, AIsError));
  end;
end;

function TAtlasIdeAiBridge.DoneFor(const AId: string): TAtlasAiTextDone;
var
  mSelf: TAtlasIdeAiBridge;
begin
  mSelf := Self;
  Result :=
    procedure(const AResult: TAtlasAiTextResult)
    begin
      mSelf.Finished(AId, AResult);
    end;
end;

procedure TAtlasIdeAiBridge.Finished(const AId: string; const AResult: TAtlasAiTextResult);
begin
  if (FTickets = nil) or not FTickets.ContainsKey(AId) then
  begin
    Exit;
  end;
  FTickets.Remove(AId);
  case AResult.Status of
    TAtlasAiTextStatus.Ok:
      Deliver(AId, AResult.Text, False);
    TAtlasAiTextStatus.Failed:
      Deliver(AId, AResult.Error, True);
    TAtlasAiTextStatus.NotReady:
      Deliver(AId, FTexts.NotReady, True);
  else
    // Abgebrochen: Die IDE hat es selbst verlangt oder Atlas geht; keine Rückmeldung.
  end;
end;

function TAtlasIdeAiBridge.Send(const AInstructions, ATask: string): string;
var
  mReason: string;
  mRequest: TAtlasAiTextRequest;
  mTicket: Integer;
begin
  Result := FNewId();
  if not Enabled then
  begin
    Deliver(Result, FTexts.NotReady, True);
    Exit;
  end;
  mReason := FTake();
  if mReason <> '' then
  begin
    Deliver(Result, mReason, True);
    Exit;
  end;
  mRequest := Default(TAtlasAiTextRequest);
  mRequest.Instructions := AInstructions;
  mRequest.Task := ATask;
  FTickets.AddOrSetValue(Result, 0);
  mTicket := FText.Ask(mRequest, DoneFor(Result));
  // Kam die Antwort schon während Ask, ist die Kennung wieder weg.
  if (mTicket > 0) and FTickets.ContainsKey(Result) then
  begin
    FTickets[Result] := mTicket;
  end;
end;

function TAtlasIdeAiBridge.Chat(const AQuestion: string): string;
begin
  Result := Send('', AQuestion);
end;

function TAtlasIdeAiBridge.Instruction(const AInput, AInstruction: string): string;
begin
  Result := Send(AInstruction, AInput);
end;

function TAtlasIdeAiBridge.LoadModels: string;
begin
  Result := FNewId();
  if FStopped or not Assigned(FModels) then
  begin
    Deliver(Result, FTexts.NoModels, True);
    Exit;
  end;
  FModels(ModelsDeliveryOf(FNotifiers, Result));
end;

procedure TAtlasIdeAiBridge.Cancel;
var
  mTickets: TArray<Integer>;
  mTicket: Integer;
begin
  if FTickets = nil then
  begin
    Exit;
  end;
  mTickets := FTickets.Values.ToArray;
  FTickets.Clear;
  for mTicket in mTickets do
  begin
    if (mTicket > 0) and (FText <> nil) then
    begin
      FText.Cancel(mTicket);
    end;
  end;
end;

function TAtlasIdeAiBridge.AddNotifier(const ANotifier: IAtlasIdeAiAnswers): Integer;
begin
  Result := FNotifiers.Add(ANotifier);
end;

procedure TAtlasIdeAiBridge.RemoveNotifier(AIndex: Integer);
begin
  FNotifiers.Remove(AIndex);
end;

function TAtlasIdeAiBridge.OpenCount: Integer;
begin
  Result := 0;
  if FTickets <> nil then
  begin
    Result := FTickets.Count;
  end;
end;

procedure TAtlasIdeAiBridge.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  Cancel;
  FNotifiers.Cut;
  FText := nil;
  FTake := nil;
  FModels := nil;
  FPost := nil;
end;

end.
