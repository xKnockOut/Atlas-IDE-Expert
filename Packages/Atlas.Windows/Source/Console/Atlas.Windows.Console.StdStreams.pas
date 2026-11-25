unit Atlas.Windows.Console.StdStreams;

// Standardein- und -ausgabe als Streams für die Protokollschicht.
// Die Streams arbeiten direkt auf den Handles, ohne Textmodus und ohne
// Pufferung der RTL, damit die Bytezählung des Protokolls stimmt.
// Der Stream für das Protokoll erkennt, dass der Client das Leseende der Pipe
// geschlossen hat (ERROR_NO_DATA, ERROR_BROKEN_PIPE), und meldet das als
// EJsonRpcPeerClosed statt als allgemeinen Schreibfehler.

interface

uses
  System.Classes;

type
  TStdStreams = record
  public
    /// <summary>Stream auf stdin. Der Aufrufer gibt ihn frei; das Handle bleibt offen.</summary>
    class function CreateInput: TStream; static;
    /// <summary>Stream auf stdout. Der Aufrufer gibt ihn frei; das Handle bleibt offen.</summary>
    class function CreateOutput: TStream; static;
    /// <summary>Stream auf stderr. Der Aufrufer gibt ihn frei; das Handle bleibt offen.</summary>
    class function CreateError: TStream; static;
    /// <summary>
    /// Leitet die Textdatei Output (Write/Writeln ohne Dateiangabe) auf stderr um,
    /// damit versehentliche Ausgaben das Protokoll auf stdout nicht zerstören.
    /// </summary>
    class procedure RedirectTextOutputToStdErr; static;
    /// <summary>
    /// Liefert einen Stream auf das echte stdout und biegt danach alle anderen
    /// Wege dorthin auf stderr um: das Standard-Handle des Prozesses (für
    /// Bibliotheken, die GetStdHandle verwenden) und die Textdatei Output.
    /// Meldungen der RTL zu Laufzeitfehlern werden unterdrückt.
    /// Danach erreicht nur noch der zurückgegebene Stream stdout. Hat der Client
    /// die Pipe geschlossen, löst das Schreiben EJsonRpcPeerClosed aus.
    /// </summary>
    class function ReserveOutputForProtocol: TStream; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract;

const
  // Selbst deklariert, nicht jede Fassung von Winapi.Windows kennt beide.
  /// <summary>Die Pipe wird gerade geschlossen: Das Leseende ist zu.</summary>
  cErrorNoData = 232;
  /// <summary>Die Pipe wurde beendet: Der Prozess am anderen Ende ist fort.</summary>
  cErrorBrokenPipe = 109;

type
  /// <summary>stdout für das Protokoll: wie THandleStream, aber ein vom Client geschlossenes Leseende ist
  /// EJsonRpcPeerClosed. Andere Schreibfehler bleiben, was sie waren (WriteBuffer: EWriteError).</summary>
  TProtocolOutputStream = class(THandleStream)
  private
    function WriteChecked(const ABuffer; ACount: Longint): Longint;
  public
    function Write(const ABuffer; ACount: Longint): Longint; overload; override;
{$IFNDEF FPC}{$IF RTLVersion >= 37.0}
    // Ab Delphi 13 ruft WriteBuffer unter Win64 die NativeInt-Überladung auf, die an der Longint-Fassung
    // vorbeigeht. Unter Win32 sind beide Signaturen gleich, dort genügt die obere.
  {$IF SizeOf(Longint) <> SizeOf(NativeInt)}
    function Write(const ABuffer; ACount: NativeInt): NativeInt; overload; override;
  {$IFEND}
{$IFEND}{$ENDIF}
  end;

{ TProtocolOutputStream }

function TProtocolOutputStream.WriteChecked(const ABuffer; ACount: Longint): Longint;
var
  mError: DWORD;
begin
  Result := FileWrite(Handle, ABuffer, ACount);
  if Result >= 0 then
  begin
    Exit;
  end;
  mError := GetLastError;
  // Leseende geschlossen bzw. Client beendet: Die Pipe nimmt nie wieder etwas an.
  if (mError = cErrorNoData) or (mError = cErrorBrokenPipe) then
  begin
    raise EJsonRpcPeerClosed.Create(SysErrorMessage(mError));
  end;
  // Wie THandleStream: 0 geschrieben, WriteBuffer meldet den Schreibfehler.
  Result := 0;
end;

function TProtocolOutputStream.Write(const ABuffer; ACount: Longint): Longint;
begin
  Result := WriteChecked(ABuffer, ACount);
end;

{$IFNDEF FPC}{$IF RTLVersion >= 37.0}
  {$IF SizeOf(Longint) <> SizeOf(NativeInt)}
function TProtocolOutputStream.Write(const ABuffer; ACount: NativeInt): NativeInt;
begin
  // Nachrichten sind höchstens 256 MiB groß; mehr als MaxInt auf einmal schreibt auch FileWrite nicht.
  if ACount > MaxInt then
  begin
    ACount := MaxInt;
  end;
  Result := WriteChecked(ABuffer, Longint(ACount));
end;
  {$IFEND}
{$IFEND}{$ENDIF}

/// <summary>Standard-Handle AStdHandle; löst EStreamError aus, wenn es fehlt.</summary>
function ValidStdHandle(AStdHandle: DWORD; const AName: string): THandle;
begin
  Result := GetStdHandle(AStdHandle);
  if (Result = 0) or (Result = INVALID_HANDLE_VALUE) then
  begin
    raise EStreamError.CreateFmt('Kein gültiges Handle für %s', [AName]);
  end;
end;

function CreateHandleStream(AStdHandle: DWORD; const AName: string): TStream;
begin
  Result := THandleStream.Create(ValidStdHandle(AStdHandle, AName));
end;

{ TStdStreams }

class function TStdStreams.CreateInput: TStream;
begin
  Result := CreateHandleStream(STD_INPUT_HANDLE, 'stdin');
end;

class function TStdStreams.CreateOutput: TStream;
begin
  Result := CreateHandleStream(STD_OUTPUT_HANDLE, 'stdout');
end;

class function TStdStreams.CreateError: TStream;
begin
  Result := CreateHandleStream(STD_ERROR_HANDLE, 'stderr');
end;

class procedure TStdStreams.RedirectTextOutputToStdErr;
var
  mErrorHandle: THandle;
begin
  mErrorHandle := GetStdHandle(STD_ERROR_HANDLE);
  if (mErrorHandle = 0) or (mErrorHandle = INVALID_HANDLE_VALUE) then
  begin
    Exit;
  end;
  if TTextRec(Output).Mode = fmOutput then
  begin
    Flush(Output);
  end;
  TTextRec(Output).Handle := mErrorHandle;
end;

class function TStdStreams.ReserveOutputForProtocol: TStream;
var
  mErrorHandle: THandle;
begin
  Result := TProtocolOutputStream.Create(ValidStdHandle(STD_OUTPUT_HANDLE, 'stdout'));
  mErrorHandle := GetStdHandle(STD_ERROR_HANDLE);
  if (mErrorHandle <> 0) and (mErrorHandle <> INVALID_HANDLE_VALUE) then
  begin
    SetStdHandle(STD_OUTPUT_HANDLE, mErrorHandle);
  end;
  RedirectTextOutputToStdErr;
  // "Runtime error ..." nicht auf die Konsole schreiben. NoErrMsg ist als
  // plattformspezifisch markiert; dieses Package ist ohnehin nur für Windows.
  {$WARN SYMBOL_PLATFORM OFF}
  NoErrMsg := True;
  {$WARN SYMBOL_PLATFORM DEFAULT}
end;

end.
