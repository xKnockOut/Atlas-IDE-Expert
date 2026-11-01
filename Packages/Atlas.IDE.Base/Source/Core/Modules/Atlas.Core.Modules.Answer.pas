unit Atlas.Core.Modules.Answer;

// Antwort an ein Modul, die erst später kommt (#1455, Regel 3): Base hält
// den Rückruf des Moduls nur, solange dessen Scope offen ist. Open
// übergibt die Anmeldung dem Scope (Own); beim Abmelden des Moduls löst der
// Scope sie und gibt den Rückruf frei, solange der Code des Moduls noch
// geladen ist. Deliver ruft ihn danach nicht mehr. Ist der Scope schon zu,
// ist die Anmeldung sofort gelöst. Deliver und Revoke dürfen aus
// verschiedenen Threads kommen; der Rückruf läuft außerhalb der Sperre.
// Nach dem Liefern ist die Anmeldung gelöst (der Scope räumt sie auf).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registration;

type
  /// <summary>Ausstehende Antwort; nur innerhalb von Base.</summary>
  IAtlasModuleAnswer = interface(IAtlasRegistration)
    ['{5CB6EEE2-A8B4-4234-941B-92E35AC4C162}']
    /// <summary>AText an das Modul, höchstens einmal; False, wenn das Modul abgemeldet ist oder schon geliefert
    /// wurde.</summary>
    function Deliver(const AText: string): Boolean;
  end;

  TAtlasModuleAnswer = class(TAtlasRegistration, IAtlasModuleAnswer)
  private
    FDoneLock: TCriticalSection;
    FDone: TProc<string>;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(const ADone: TProc<string>);
    destructor Destroy; override;
    function Deliver(const AText: string): Boolean;
    /// <summary>Antwort für das Modul von AScope anlegen; ohne Scope oder mit geschlossenem sofort gelöst.</summary>
    class function Open(const AScope: IAtlasModuleScope; const ADone: TProc<string>): IAtlasModuleAnswer; static;
  end;

implementation

{ TAtlasModuleAnswer }

constructor TAtlasModuleAnswer.Create(const ADone: TProc<string>);
begin
  inherited Create;
  FDoneLock := TCriticalSection.Create;
  FDone := ADone;
end;

destructor TAtlasModuleAnswer.Destroy;
begin
  FDoneLock.Free;
  inherited;
end;

class function TAtlasModuleAnswer.Open(const AScope: IAtlasModuleScope;
  const ADone: TProc<string>): IAtlasModuleAnswer;
begin
  Result := TAtlasModuleAnswer.Create(ADone);
  // Own löst sofort, wenn der Scope schon zu ist; ohne Scope gibt es niemanden, der lösen könnte.
  if AScope = nil then
    Result.Revoke
  else
    AScope.Own(Result);
end;

procedure TAtlasModuleAnswer.DoRevoke;
begin
  // Freigabe des Rückrufs hier, solange das Modul noch geladen ist.
  FDoneLock.Acquire;
  try
    FDone := nil;
  finally
    FDoneLock.Release;
  end;
end;

function TAtlasModuleAnswer.Deliver(const AText: string): Boolean;
var
  mDone: TProc<string>;
begin
  FDoneLock.Acquire;
  try
    mDone := FDone;
    FDone := nil;
  finally
    FDoneLock.Release;
  end;
  // Geliefert: Anmeldung lösen, damit der Scope sie beim nächsten Own aufräumt.
  Revoke;
  Result := Assigned(mDone);
  if Result then
    mDone(AText);
end;

end.
