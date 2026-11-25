unit Atlas.Tests.AiTextFake;

// Gefälschter KI-Text (Vertrag IAtlasAiText) für die Tests der Quelle für einfache Aufgaben und der Brücke zur IDE
// (#2744, #2745): merkt sich Anfragen und Abbrüche; Complete stellt ein Ergebnis zu wie der echte Dienst im
// Hauptthread.

interface

uses
  System.Generics.Collections,
  Atlas.IDE.Base.Foundation.AiText;

type
  TAtlasFakeAiText = class(TInterfacedObject, IAtlasAiText)
  private type
    TAsk = record
      Ticket: Integer;
      Request: TAtlasAiTextRequest;
      Done: TAtlasAiTextDone;
    end;
  private
    FReady: Boolean;
    FName: string;
    FAsks: TList<TAsk>;
    FCancelled: TList<Integer>;
    FNext: Integer;
  public
    constructor Create(AReady: Boolean; const AName: string);
    destructor Destroy; override;
    function Ready: Boolean;
    function ProviderName: string;
    function Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
    procedure Cancel(ATicket: Integer);
    /// <summary>Ergebnis der Anfrage ATicket zustellen (nur, wenn sie noch offen ist).</summary>
    procedure Complete(ATicket: Integer; AStatus: TAtlasAiTextStatus; const AText: string);
    /// <summary>Letzte Anfrage.</summary>
    function LastRequest: TAtlasAiTextRequest;
    function AskCount: Integer;
    function CancelledCount: Integer;
    function WasCancelled(ATicket: Integer): Boolean;
    property IsReady: Boolean read FReady write FReady;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasFakeAiText }

constructor TAtlasFakeAiText.Create(AReady: Boolean; const AName: string);
begin
  inherited Create;
  FReady := AReady;
  FName := AName;
  FAsks := TList<TAsk>.Create;
  FCancelled := TList<Integer>.Create;
end;

destructor TAtlasFakeAiText.Destroy;
begin
  FreeAndNil(FCancelled);
  FreeAndNil(FAsks);
  inherited Destroy;
end;

function TAtlasFakeAiText.Ready: Boolean;
begin
  Result := FReady;
end;

function TAtlasFakeAiText.ProviderName: string;
begin
  Result := FName;
end;

function TAtlasFakeAiText.Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
var
  mAsk: TAsk;
  mResult: TAtlasAiTextResult;
begin
  if not FReady then
  begin
    mResult := Default(TAtlasAiTextResult);
    mResult.Status := TAtlasAiTextStatus.NotReady;
    ADone(mResult);
    Exit(0);
  end;
  Inc(FNext);
  mAsk.Ticket := FNext;
  mAsk.Request := ARequest;
  mAsk.Done := ADone;
  FAsks.Add(mAsk);
  Result := FNext;
end;

procedure TAtlasFakeAiText.Cancel(ATicket: Integer);
begin
  FCancelled.Add(ATicket);
end;

procedure TAtlasFakeAiText.Complete(ATicket: Integer; AStatus: TAtlasAiTextStatus; const AText: string);
var
  mAsk: TAsk;
  mResult: TAtlasAiTextResult;
begin
  if WasCancelled(ATicket) then
  begin
    Exit;
  end;
  for mAsk in FAsks do
  begin
    if mAsk.Ticket = ATicket then
    begin
      mResult := Default(TAtlasAiTextResult);
      mResult.Status := AStatus;
      if AStatus = TAtlasAiTextStatus.Ok then
      begin
        mResult.Text := AText;
      end
      else
      begin
        mResult.Error := AText;
      end;
      mAsk.Done(mResult);
      Exit;
    end;
  end;
end;

function TAtlasFakeAiText.LastRequest: TAtlasAiTextRequest;
begin
  Result := Default(TAtlasAiTextRequest);
  if FAsks.Count > 0 then
  begin
    Result := FAsks[FAsks.Count - 1].Request;
  end;
end;

function TAtlasFakeAiText.AskCount: Integer;
begin
  Result := FAsks.Count;
end;

function TAtlasFakeAiText.CancelledCount: Integer;
begin
  Result := FCancelled.Count;
end;

function TAtlasFakeAiText.WasCancelled(ATicket: Integer): Boolean;
begin
  Result := FCancelled.Contains(ATicket);
end;

end.
