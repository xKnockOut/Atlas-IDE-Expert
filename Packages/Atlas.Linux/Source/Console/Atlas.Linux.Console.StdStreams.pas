unit Atlas.Linux.Console.StdStreams;

// Platform-Feature "Console" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Console.StdStreams. stdin, stdout und stderr sind die
// Dateideskriptoren 0, 1 und 2. ReserveOutputForProtocol behält eine Kopie von
// stdout für das Protokoll und legt Deskriptor 1 auf stderr, damit kein
// Writeln einer Unit die Nachrichten von LSP oder MCP stört. Hat der Client das
// Leseende geschlossen (EPIPE), meldet der Stream für das Protokoll das als
// EJsonRpcPeerClosed statt als allgemeinen Schreibfehler.

interface

uses
  System.Classes;

type
  TStdStreams = record
  public
    /// <summary>Stream auf stdin; der Aufrufer gibt ihn frei, der Deskriptor bleibt offen.</summary>
    class function CreateInput: TStream; static;
    /// <summary>Stream auf stdout.</summary>
    class function CreateOutput: TStream; static;
    /// <summary>Stream auf stderr.</summary>
    class function CreateError: TStream; static;
    /// <summary>Leitet die Textdatei Output (Write/Writeln) auf stderr um.</summary>
    class procedure RedirectTextOutputToStdErr; static;
    /// <summary>Stream auf das bisherige stdout für das Protokoll; danach schreibt alles andere, das auf
    /// stdout zielt (Deskriptor 1, Writeln), nach stderr. Hat der Client die Pipe geschlossen, löst das Schreiben
    /// EJsonRpcPeerClosed aus.</summary>
    class function ReserveOutputForProtocol: TStream; static;
  end;

implementation

uses
  System.SysUtils,
  BaseUnix,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>stdout für das Protokoll: wie THandleStream, aber ein vom Client geschlossenes Leseende ist
  /// EJsonRpcPeerClosed. Andere Schreibfehler bleiben, was sie waren (WriteBuffer: EWriteError).</summary>
  TProtocolOutputStream = class(THandleStream)
  public
    function Write(const ABuffer; ACount: Longint): Longint; override;
  end;

{ TProtocolOutputStream }

function TProtocolOutputStream.Write(const ABuffer; ACount: Longint): Longint;
var
  mError: cint;
begin
  Result := FileWrite(Handle, ABuffer, ACount);
  if Result >= 0 then
  begin
    Exit;
  end;
  mError := FpGetErrno;
  // Leseende geschlossen: Die Pipe nimmt nie wieder etwas an. EPIPE kommt nur an, wenn SIGPIPE den Prozess nicht
  // schon beendet hat.
  if mError = ESysEPIPE then
  begin
    raise EJsonRpcPeerClosed.Create(SysErrorMessage(mError));
  end;
  // Wie THandleStream: 0 geschrieben, WriteBuffer meldet den Schreibfehler.
  Result := 0;
end;

const
  cStdInputFd = 0;
  cStdOutputFd = 1;
  cStdErrorFd = 2;

function CreateFdStream(AFd: THandle; const AName: string): TStream;
begin
  if FpFcntl(AFd, F_GETFD) < 0 then
  begin
    raise EStreamError.CreateFmt('Kein gültiger Deskriptor für %s', [AName]);
  end;
  Result := THandleStream.Create(AFd);
end;

{ TStdStreams }

class function TStdStreams.CreateInput: TStream;
begin
  Result := CreateFdStream(cStdInputFd, 'stdin');
end;

class function TStdStreams.CreateOutput: TStream;
begin
  Result := CreateFdStream(cStdOutputFd, 'stdout');
end;

class function TStdStreams.CreateError: TStream;
begin
  Result := CreateFdStream(cStdErrorFd, 'stderr');
end;

class procedure TStdStreams.RedirectTextOutputToStdErr;
begin
  if FpFcntl(cStdErrorFd, F_GETFD) < 0 then
  begin
    Exit;
  end;
  if TTextRec(Output).Mode = fmOutput then
  begin
    Flush(Output);
  end;
  TTextRec(Output).Handle := cStdErrorFd;
end;

class function TStdStreams.ReserveOutputForProtocol: TStream;
var
  mProtocol: cint;
begin
  // Eigener Deskriptor für das Protokoll; FD_CLOEXEC, damit Kindprozesse (git, dcc) ihn nicht erben.
  mProtocol := FpFcntl(cStdOutputFd, F_DUPFD_CLOEXEC, 3);
  if mProtocol < 0 then
  begin
    raise EStreamError.Create('stdout lässt sich nicht für das Protokoll reservieren');
  end;
  Result := TProtocolOutputStream.Create(mProtocol);
  if FpFcntl(cStdErrorFd, F_GETFD) >= 0 then
  begin
    FpDup2(cStdErrorFd, cStdOutputFd);
  end;
  RedirectTextOutputToStdErr;
end;

end.
