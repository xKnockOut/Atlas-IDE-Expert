unit Shell.Mcp.Loading.Tests;

// Laden der Projektgruppe im Hintergrund (#3099): Werkzeugaufrufe warten oder melden „wird noch geladen“, der Name
// des Clients geht erst nach dem Laden an die Gruppe, ein Fehler beim Laden beendet das Warten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpLoadingTests = class
  public
    [Test]
    procedure EnsureReportsStillLoading;
    [Test]
    procedure ClientWaitsForLoad;
    [Test]
    procedure FailingLoadEndsWaiting;
    [Test]
    procedure StartTwiceLoadsOnce;
  end;

implementation

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Mcp.Server,
  Shell.Mcp.Loading;

type
  /// <summary>Was die Testläufe sehen: Zahl der Ladevorgänge und die an die Gruppe gegebenen Clients.</summary>
  TLoadProbe = class
  public
    Gate: TEvent;
    Loads: Integer;
    Clients: string;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TLoadProbe.Create;
begin
  inherited Create;
  Gate := TEvent.Create(nil, True, False, '');
end;

destructor TLoadProbe.Destroy;
begin
  Gate.Free;
  inherited;
end;

/// <summary>Laden, das bis zur Freigabe von AProbe.Gate wartet; in eigener Routine, damit die anonyme Methode nur
/// AProbe einfängt.</summary>
function BlockingLoad(AProbe: TLoadProbe): TProc;
begin
  Result :=
    procedure
    begin
      // Nur dieser Thread schreibt; gelesen wird nach Finish.
      Inc(AProbe.Loads);
      AProbe.Gate.WaitFor(10000);
    end;
end;

function FailingLoad: TProc;
begin
  Result :=
    procedure
    begin
      raise EInvalidOpException.Create('Projekt kaputt');
    end;
end;

function RecordClient(AProbe: TLoadProbe): TProc<string>;
begin
  Result :=
    procedure(AClient: string)
    begin
      AProbe.Clients := AProbe.Clients + AClient + ';';
    end;
end;

function NewLogger: ILogger;
begin
  Result := TLogger.Create;
end;

{ TMcpLoadingTests }

procedure TMcpLoadingTests.EnsureReportsStillLoading;
var
  mProbe: TLoadProbe;
  mLoading: TMcpLoading;
begin
  mProbe := TLoadProbe.Create;
  try
    mLoading := TMcpLoading.Create(BlockingLoad(mProbe), RecordClient(mProbe), NewLogger());
    try
      mLoading.Start;
      Assert.IsFalse(mLoading.WaitLoaded(50), 'lädt noch');
      Assert.WillRaise(
        procedure
        begin
          mLoading.Ensure(50);
        end, EMcpToolError);
      mProbe.Gate.SetEvent;
      Assert.IsTrue(mLoading.WaitLoaded(5000), 'nach der Freigabe fertig');
      mLoading.Ensure(0);
    finally
      mProbe.Gate.SetEvent;
      mLoading.Free;
    end;
  finally
    mProbe.Free;
  end;
end;

procedure TMcpLoadingTests.ClientWaitsForLoad;
var
  mProbe: TLoadProbe;
  mLoading: TMcpLoading;
begin
  mProbe := TLoadProbe.Create;
  try
    mLoading := TMcpLoading.Create(BlockingLoad(mProbe), RecordClient(mProbe), NewLogger());
    try
      mLoading.Start;
      mLoading.SetClient('Claude Code');
      Assert.AreEqual('', mProbe.Clients, 'erst nach dem Laden');
      mProbe.Gate.SetEvent;
      Assert.IsTrue(mLoading.WaitLoaded(5000));
      Assert.AreEqual('Claude Code;', mProbe.Clients);
      // Nach dem Laden sofort.
      mLoading.SetClient('Zweiter');
      Assert.AreEqual('Claude Code;Zweiter;', mProbe.Clients);
    finally
      mProbe.Gate.SetEvent;
      mLoading.Free;
    end;
  finally
    mProbe.Clients := '';
    mProbe.Free;
  end;
end;

procedure TMcpLoadingTests.FailingLoadEndsWaiting;
var
  mProbe: TLoadProbe;
  mLoading: TMcpLoading;
begin
  mProbe := TLoadProbe.Create;
  try
    mLoading := TMcpLoading.Create(FailingLoad(), RecordClient(mProbe), NewLogger());
    try
      mLoading.SetClient('Claude Code');
      mLoading.Start;
      Assert.IsTrue(mLoading.WaitLoaded(5000), 'ein Fehler beendet das Warten');
      mLoading.Ensure(0);
      Assert.AreEqual('Claude Code;', mProbe.Clients, 'der Client kommt trotzdem an');
    finally
      mLoading.Free;
    end;
  finally
    mProbe.Clients := '';
    mProbe.Free;
  end;
end;

procedure TMcpLoadingTests.StartTwiceLoadsOnce;
var
  mProbe: TLoadProbe;
  mLoading: TMcpLoading;
begin
  mProbe := TLoadProbe.Create;
  try
    mProbe.Gate.SetEvent;
    mLoading := TMcpLoading.Create(BlockingLoad(mProbe), RecordClient(mProbe), NewLogger());
    try
      mLoading.Start;
      mLoading.Start;
      Assert.IsTrue(mLoading.WaitLoaded(5000));
      mLoading.Finish;
      Assert.AreEqual(1, mProbe.Loads);
    finally
      mLoading.Free;
    end;
  finally
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpLoadingTests);

end.
