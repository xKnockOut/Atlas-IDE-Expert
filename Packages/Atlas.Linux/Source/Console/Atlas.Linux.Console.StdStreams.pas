unit Atlas.Linux.Console.StdStreams;

// Platform-Feature "Console" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Console.StdStreams. stdin, stdout und stderr sind die
// Dateideskriptoren 0, 1 und 2. ReserveOutputForProtocol behält eine Kopie von
// stdout für das Protokoll und legt Deskriptor 1 auf stderr, damit kein
// Writeln einer Unit die Nachrichten von LSP oder MCP stört.

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
    /// stdout zielt (Deskriptor 1, Writeln), nach stderr.</summary>
    class function ReserveOutputForProtocol: TStream; static;
  end;

implementation

uses
  System.SysUtils,
  BaseUnix;

const
  StdInputFd = 0;
  StdOutputFd = 1;
  StdErrorFd = 2;

function CreateFdStream(AFd: THandle; const AName: string): TStream;
begin
  if FpFcntl(AFd, F_GETFD) < 0 then
    raise EStreamError.CreateFmt('Kein gültiger Deskriptor für %s', [AName]);
  Result := THandleStream.Create(AFd);
end;

{ TStdStreams }

class function TStdStreams.CreateInput: TStream;
begin
  Result := CreateFdStream(StdInputFd, 'stdin');
end;

class function TStdStreams.CreateOutput: TStream;
begin
  Result := CreateFdStream(StdOutputFd, 'stdout');
end;

class function TStdStreams.CreateError: TStream;
begin
  Result := CreateFdStream(StdErrorFd, 'stderr');
end;

class procedure TStdStreams.RedirectTextOutputToStdErr;
begin
  if FpFcntl(StdErrorFd, F_GETFD) < 0 then
    Exit;
  if TTextRec(Output).Mode = fmOutput then
    Flush(Output);
  TTextRec(Output).Handle := StdErrorFd;
end;

class function TStdStreams.ReserveOutputForProtocol: TStream;
var
  Protocol: cint;
begin
  // Eigener Deskriptor für das Protokoll; FD_CLOEXEC, damit Kindprozesse (git, dcc) ihn nicht erben.
  Protocol := FpFcntl(StdOutputFd, F_DUPFD_CLOEXEC, 3);
  if Protocol < 0 then
    raise EStreamError.Create('stdout lässt sich nicht für das Protokoll reservieren');
  Result := THandleStream.Create(Protocol);
  if FpFcntl(StdErrorFd, F_GETFD) >= 0 then
    FpDup2(StdErrorFd, StdOutputFd);
  RedirectTextOutputToStdErr;
end;

end.
