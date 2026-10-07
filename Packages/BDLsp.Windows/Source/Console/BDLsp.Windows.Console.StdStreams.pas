unit BDLsp.Windows.Console.StdStreams;

// Standardein- und -ausgabe als Streams für die Protokollschicht.
// Die Streams arbeiten direkt auf den Handles, ohne Textmodus und ohne
// Pufferung der RTL, damit die Bytezählung des Protokolls stimmt.

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
    /// <summary>
    /// Leitet die Textdatei Output (Write/Writeln ohne Dateiangabe) auf stderr um,
    /// damit versehentliche Ausgaben das Protokoll auf stdout nicht zerstören.
    /// </summary>
    class procedure RedirectTextOutputToStdErr; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils;

function CreateHandleStream(AStdHandle: DWORD; const AName: string): TStream;
var
  Handle: THandle;
begin
  Handle := GetStdHandle(AStdHandle);
  if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
    raise EStreamError.CreateFmt('Kein gültiges Handle für %s', [AName]);
  Result := THandleStream.Create(Handle);
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

class procedure TStdStreams.RedirectTextOutputToStdErr;
var
  ErrorHandle: THandle;
begin
  ErrorHandle := GetStdHandle(STD_ERROR_HANDLE);
  if (ErrorHandle = 0) or (ErrorHandle = INVALID_HANDLE_VALUE) then
    Exit;
  if TTextRec(Output).Mode = fmOutput then
    Flush(Output);
  TTextRec(Output).Handle := ErrorHandle;
end;

end.
