unit Atlas.Core.Modules.Registration;

// Gemeinsame Grundlage der Anmeldungen in Base (#1455, Regel 4): Revoke löst
// eine Anmeldung genau einmal; Detach markiert sie als gelöst, ohne den
// Besitzer zu rufen, wenn die Ablage vor ihr abgebaut wird (sonst zeigte ein
// späteres Revoke in freigegebenen Speicher).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Modules.Contract;

type
  TAtlasRegistration = class(TInterfacedObject, IAtlasRegistration)
  private
    FLock: TCriticalSection;
    FRevoked: Boolean;
    function TryClaim: Boolean;
  protected
    /// <summary>Löst die Anmeldung bei ihrer Ablage; genau einmal gerufen, nie nach Detach.</summary>
    procedure DoRevoke; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Revoke;
    function IsRevoked: Boolean;
    /// <summary>Ablage abgebaut: als gelöst markieren, ohne DoRevoke.</summary>
    procedure Detach;
  end;

implementation

{ TAtlasRegistration }

constructor TAtlasRegistration.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasRegistration.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAtlasRegistration.TryClaim: Boolean;
begin
  FLock.Acquire;
  try
    Result := not FRevoked;
    FRevoked := True;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasRegistration.Revoke;
begin
  if TryClaim then
  begin
    DoRevoke;
  end;
end;

function TAtlasRegistration.IsRevoked: Boolean;
begin
  FLock.Acquire;
  try
    Result := FRevoked;
  finally
    FLock.Release;
  end;
end;

procedure TAtlasRegistration.Detach;
begin
  TryClaim;
end;

end.
