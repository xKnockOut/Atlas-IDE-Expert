unit Atlas.Windows.Compiler.Adapters.ProcessRunner;

// Startet den Compiler unsichtbar und liest stdout und stderr über eine Pipe
// (#40). Der Server spricht über die eigenen Standardkanäle mit dem Editor;
// der Kindprozess bekommt deshalb keine Eingabe und schreibt nur in die Pipe.
// Die Ausgabe von dcc32/dcc64 ist im ANSI-Zeichensatz des Systems kodiert.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract;

type
  TProcessRunner = class(TInterfacedObject, ICompilerProcess)
  public
    function Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
    /// <summary>Kommandozeile mit Anführungszeichen nach den Regeln von CommandLineToArgvW.</summary>
    class function QuoteArgument(const AArgument: string): string; static;
  end;

implementation

uses
  Winapi.Windows;

{ TProcessRunner }

class function TProcessRunner.QuoteArgument(const AArgument: string): string;
var
  Index, Backslashes: Integer;
begin
  if (AArgument <> '') and (LastDelimiter(' '#9'"', AArgument) = 0) then
    Exit(AArgument);
  Result := '"';
  Backslashes := 0;
  for Index := 1 to Length(AArgument) do
  begin
    if AArgument[Index] = '\' then
      Inc(Backslashes)
    else
    begin
      if AArgument[Index] = '"' then
        Result := Result + StringOfChar('\', Backslashes + 1);
      Backslashes := 0;
    end;
    Result := Result + AArgument[Index];
  end;
  // Backslashes vor dem schließenden Anführungszeichen verdoppeln.
  Result := Result + StringOfChar('\', Backslashes) + '"';
end;

function TProcessRunner.Run(const ARequest: TCompilerRequest; const AOnLine: TCompilerLineEvent): Integer;
var
  Security: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CommandLine, Argument: string;
  Buffer: array[0..4095] of Byte;
  BytesRead, ProcessExitCode: DWORD;
  Pending: TBytes;
  LineEnd, Start: Integer;
  WorkingDir: PChar;

  procedure EmitLine(AFrom, ACount: Integer);
  var
    Line: string;
  begin
    Line := TEncoding.ANSI.GetString(Pending, AFrom, ACount);
    if (Line <> '') and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    if Assigned(AOnLine) then
      AOnLine(Line);
  end;

begin
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @Security, 0) then
    RaiseLastOSError;
  try
    // Nur das Schreibende erbt der Kindprozess.
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdInput := 0;
    StartupInfo.hStdOutput := WritePipe;
    StartupInfo.hStdError := WritePipe;
    CommandLine := QuoteArgument(ARequest.Executable);
    for Argument in ARequest.Arguments do
      CommandLine := CommandLine + ' ' + QuoteArgument(Argument);
    UniqueString(CommandLine);
    if ARequest.WorkingDir <> '' then
      WorkingDir := PChar(ARequest.WorkingDir)
    else
      WorkingDir := nil;
    if not CreateProcess(PChar(ARequest.Executable), PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      WorkingDir, StartupInfo, ProcessInfo) then
      raise ECompilerError.CreateFmt('%s lässt sich nicht starten: %s',
        [ARequest.Executable, SysErrorMessage(GetLastError)]);
    // Eigenes Schreibende schließen, damit ReadFile beim Prozessende False liefert.
    CloseHandle(WritePipe);
    WritePipe := 0;
    try
      Pending := nil;
      while ReadFile(ReadPipe, Buffer, SizeOf(Buffer), BytesRead, nil) and (BytesRead > 0) do
      begin
        Start := Length(Pending);
        SetLength(Pending, Start + Integer(BytesRead));
        Move(Buffer[0], Pending[Start], BytesRead);
        Start := 0;
        for LineEnd := 0 to High(Pending) do
          if Pending[LineEnd] = 10 then
          begin
            EmitLine(Start, LineEnd - Start);
            Start := LineEnd + 1;
          end;
        Pending := Copy(Pending, Start, MaxInt);
      end;
      if Length(Pending) > 0 then
        EmitLine(0, Length(Pending));
      WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
      if not GetExitCodeProcess(ProcessInfo.hProcess, ProcessExitCode) then
        RaiseLastOSError;
      Result := Integer(ProcessExitCode);
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
  finally
    CloseHandle(ReadPipe);
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
  end;
end;

end.
