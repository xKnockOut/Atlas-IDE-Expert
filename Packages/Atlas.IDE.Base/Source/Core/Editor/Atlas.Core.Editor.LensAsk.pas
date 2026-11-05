unit Atlas.Core.Editor.LensAsk;

// Ausstehende Frage eines Code-Lens-Abrufs (TAtlasLensPoll): Der Befehl läuft
// im Hintergrund, die Antwort kommt über die Nachrichtenschleife. Sie gilt nur
// für die jüngste Frage und nur, solange der Abruf weder vergessen (Drop)
// noch geschlossen (Close, Ende des Besitzers) ist; sonst erreicht sie nichts.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>Zähler der Fragen eines Abrufs; lebt, solange ein Rückruf ihn hält.</summary>
  IAtlasLensTickets = interface
    ['{02FF1674-D4D6-49E5-B539-F24913DEF4B8}']
    /// <summary>Gilt ATicket noch (jüngste Frage, nicht geschlossen)?</summary>
    function Current(ATicket: Cardinal): Boolean;
    /// <summary>Neue Frage; ältere gelten nicht mehr.</summary>
    function Next: Cardinal;
    /// <summary>Keine Frage gilt mehr.</summary>
    procedure Drop;
    procedure Close;
  end;

  TAtlasLensAsk = record
  private
    FTickets: IAtlasLensTickets;
    function Tickets: IAtlasLensTickets;
  public
    /// <summary>Stand der ausstehenden Frage; Waiting, bis die Antwort da ist.</summary>
    FileName: string;
    Text: string;
    Waiting: Boolean;
    /// <summary>Merkt AFileName und AText als gefragt; Ergebnis: Rückruf für den Befehl, der AOnAnswer im
    /// Hauptthread, gesichert über AFeature, nur für diese Frage aufruft.</summary>
    function Start(const AFileName, AText: string; AFeature: TAtlasFeature;
      const AOnAnswer: TProc<TJSONValue>): TProc<TJSONValue>;
    /// <summary>Antwort eingetroffen; True mit Antwort, False ohne (Fehler, Zeitlimit, kein Server).</summary>
    function Answered(AAnswer: TJSONValue): Boolean;
    /// <summary>Ausstehende Antwort verwerfen.</summary>
    procedure Drop;
    /// <summary>Ende des Besitzers: Keine ausstehende Antwort erreicht ihn mehr.</summary>
    procedure Close;
  end;

implementation

type
  TTickets = class(TInterfacedObject, IAtlasLensTickets)
  private
    FTicket: Cardinal;
    FClosed: Boolean;
  public
    function Current(ATicket: Cardinal): Boolean;
    function Next: Cardinal;
    procedure Drop;
    procedure Close;
  end;

{ TTickets }

function TTickets.Current(ATicket: Cardinal): Boolean;
begin
  Result := not FClosed and (ATicket = FTicket);
end;

function TTickets.Next: Cardinal;
begin
  Inc(FTicket);
  Result := FTicket;
end;

procedure TTickets.Drop;
begin
  Inc(FTicket);
end;

procedure TTickets.Close;
begin
  FClosed := True;
end;

/// <summary>Rückruf; eigene Routine, damit der Rahmen nur Zähler, Ticket und Ziel hält.</summary>
function Deliver(const ATickets: IAtlasLensTickets; ATicket: Cardinal; AFeature: TAtlasFeature;
  const AOnAnswer: TProc<TJSONValue>): TProc<TJSONValue>;
begin
  Result :=
    procedure(AAnswer: TJSONValue)
    var
      mAnswer: TJSONValue;
    begin
      // Vergessen, geschlossen oder eine neuere Frage: Die Antwort gilt nicht mehr.
      if not ATickets.Current(ATicket) then
      begin
        Exit;
      end;
      mAnswer := AAnswer;
      TAtlasGuard.Run(AFeature,
        procedure
        begin
          AOnAnswer(mAnswer);
        end);
    end;
end;

{ TAtlasLensAsk }

function TAtlasLensAsk.Tickets: IAtlasLensTickets;
begin
  if FTickets = nil then
  begin
    FTickets := TTickets.Create;
  end;
  Result := FTickets;
end;

function TAtlasLensAsk.Start(const AFileName, AText: string; AFeature: TAtlasFeature;
  const AOnAnswer: TProc<TJSONValue>): TProc<TJSONValue>;
var
  mTickets: IAtlasLensTickets;
begin
  FileName := AFileName;
  Text := AText;
  Waiting := True;
  mTickets := Tickets;
  Result := Deliver(mTickets, mTickets.Next, AFeature, AOnAnswer);
end;

function TAtlasLensAsk.Answered(AAnswer: TJSONValue): Boolean;
begin
  Waiting := False;
  Result := AAnswer <> nil;
end;

procedure TAtlasLensAsk.Drop;
begin
  if Waiting then
  begin
    Waiting := False;
    Tickets.Drop;
  end;
end;

procedure TAtlasLensAsk.Close;
begin
  Waiting := False;
  if FTickets <> nil then
  begin
    FTickets.Close;
    FTickets := nil;
  end;
end;

end.
