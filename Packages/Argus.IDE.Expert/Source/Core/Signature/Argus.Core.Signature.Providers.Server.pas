unit Argus.Core.Signature.Providers.Server;

// Signaturen für den Parameter-Hint (#436) vom Argus-Server
// (textDocument/signatureHelp, #32). Query gleicht im Hauptthread den
// Editortext ab und fragt im Hintergrund; das Ergebnis kommt per TThread.Queue
// im Hauptthread an, aber nur für die jüngste Anfrage. Vor dem Freigeben der
// Sitzung Shutdown aufrufen (wartet auf laufende Anfragen).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  Argus.Core.Signature.Contract,
  Argus.Core.Completion.Providers.Server,
  Argus.Core.Lsp.Session;

type
  TArgusSignatureCallback = reference to procedure(const AHelp: TArgusSignatureHelp);

  TArgusServerSignatureProvider = class
  public const
    DefaultTimeoutMs = 2000;
  private type
    /// <summary>Hält eingereihte Aufrufe davon ab, eine freigegebene Quelle zu benutzen.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private
    FSession: TArgusSessionFunc;
    FTimeoutMs: Cardinal;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    procedure ReapWorkers;
  public
    constructor Create(const ASession: TArgusSessionFunc; ATimeoutMs: Cardinal = DefaultTimeoutMs);
    destructor Destroy; override;
    /// <summary>Fragt die Signaturen an ALine/ACharacter (0-basiert) an; ACallback im Hauptthread.
    /// False, wenn kein Server verfügbar ist.</summary>
    function Query(const AFileName, AText: string; ALine, ACharacter: Integer;
      const ACallback: TArgusSignatureCallback): Boolean;
    procedure Cancel;
    procedure Shutdown;
    /// <summary>Antwort auf textDocument/signatureHelp.</summary>
    class function HelpFromLsp(AResponse: TJSONValue): TArgusSignatureHelp; static;
  end;

implementation

{ TArgusServerSignatureProvider }

constructor TArgusServerSignatureProvider.Create(const ASession: TArgusSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
end;

destructor TArgusServerSignatureProvider.Destroy;
begin
  Shutdown;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function DocumentationText(AValue: TJSONValue): string;
begin
  // string oder MarkupContent.
  if AValue is TJSONString then
    Result := TJSONString(AValue).Value
  else if AValue is TJSONObject then
    Result := TJSONObject(AValue).GetValue<string>('value', '')
  else
    Result := '';
end;

class function TArgusServerSignatureProvider.HelpFromLsp(AResponse: TJSONValue): TArgusSignatureHelp;
var
  Signatures, Parameters, LabelValue: TJSONValue;
  Signature: TArgusSignature;
  Parameter: TArgusSignatureParameter;
  Item, ParameterItem: TJSONValue;
  Position: Integer;
begin
  Result := Default(TArgusSignatureHelp);
  Result.ActiveSignature := -1;
  Result.ActiveParameter := -1;
  if not (AResponse is TJSONObject) then
    Exit;
  Result.ActiveSignature := TJSONObject(AResponse).GetValue<Integer>('activeSignature', -1);
  Result.ActiveParameter := TJSONObject(AResponse).GetValue<Integer>('activeParameter', -1);
  Signatures := TJSONObject(AResponse).GetValue('signatures');
  if not (Signatures is TJSONArray) then
    Exit;
  for Item in TJSONArray(Signatures) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Signature := Default(TArgusSignature);
    Signature.Label_ := TJSONObject(Item).GetValue<string>('label', '');
    Signature.Documentation := DocumentationText(TJSONObject(Item).GetValue('documentation'));
    Parameters := TJSONObject(Item).GetValue('parameters');
    if Parameters is TJSONArray then
      for ParameterItem in TJSONArray(Parameters) do
      begin
        if not (ParameterItem is TJSONObject) then
          Continue;
        Parameter := Default(TArgusSignatureParameter);
        Parameter.Start := -1;
        Parameter.Stop := -1;
        // label: [Start, Ende] im Signaturtext oder der Text selbst.
        LabelValue := TJSONObject(ParameterItem).GetValue('label');
        if (LabelValue is TJSONArray) and (TJSONArray(LabelValue).Count = 2) and
          (TJSONArray(LabelValue).Items[0] is TJSONNumber) and (TJSONArray(LabelValue).Items[1] is TJSONNumber) then
        begin
          Parameter.Start := TJSONNumber(TJSONArray(LabelValue).Items[0]).AsInt;
          Parameter.Stop := TJSONNumber(TJSONArray(LabelValue).Items[1]).AsInt;
        end
        else if LabelValue is TJSONString then
        begin
          Position := Pos(TJSONString(LabelValue).Value, Signature.Label_);
          if Position > 0 then
          begin
            Parameter.Start := Position - 1;
            Parameter.Stop := Parameter.Start + Length(TJSONString(LabelValue).Value);
          end;
        end;
        Parameter.Documentation := DocumentationText(TJSONObject(ParameterItem).GetValue('documentation'));
        Signature.Parameters := Signature.Parameters + [Parameter];
      end;
    Result.Signatures := Result.Signatures + [Signature];
  end;
end;

procedure TArgusServerSignatureProvider.ReapWorkers;
var
  Index: Integer;
begin
  FLock.Enter;
  try
    for Index := FWorkers.Count - 1 downto 0 do
      if FWorkers[Index].Finished then
      begin
        FWorkers[Index].Free;
        FWorkers.Delete(Index);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TArgusServerSignatureProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TArgusServerSignatureProvider.Shutdown;
var
  Workers: TArray<TThread>;
  Worker: TThread;
begin
  Cancel;
  FLock.Enter;
  try
    Workers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for Worker in Workers do
  begin
    Worker.WaitFor;
    Worker.Free;
  end;
end;

function TArgusServerSignatureProvider.Query(const AFileName, AText: string; ALine, ACharacter: Integer;
  const ACallback: TArgusSignatureCallback): Boolean;
var
  Session: TLspSession;
  Generation: Integer;
  FileName: string;
  Worker: TThread;
  Provider: TArgusServerSignatureProvider;
  Flag: TAliveFlag;
  FlagRef: IInterface;
begin
  Generation := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  Result := (Session <> nil) and (AFileName <> '');
  if not Result then
    Exit;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  Session.Sync(AFileName, AText);
  FileName := AFileName;
  Provider := Self;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Response: TJSONValue;
      Help: TArgusSignatureHelp;
    begin
      Help := Default(TArgusSignatureHelp);
      try
        Response := Session.SignatureHelp(FileName, ALine, ACharacter, Provider.FTimeoutMs);
        try
          Help := HelpFromLsp(Response);
        finally
          Response.Free;
        end;
      except
        // Server weg oder Zeitlimit: kein Hint.
        Help := Default(TArgusSignatureHelp);
      end;
      if TInterlocked.CompareExchange(Provider.FGeneration, 0, 0) <> Generation then
        Exit;
      // Im Hauptthread erst prüfen, ob die Quelle noch lebt und dies die jüngste Anfrage ist.
      TThread.Queue(nil,
        procedure
        begin
          if Flag.Alive and (FlagRef <> nil) and
            (TInterlocked.CompareExchange(Provider.FGeneration, 0, 0) = Generation) then
            ACallback(Help);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(Worker);
  finally
    FLock.Leave;
  end;
  Worker.Start;
end;

end.
