unit Shell.CommandLine;

// Host-Rolle Shell: Kommandozeilenparameter des Servers.
//
//   --log <Datei>         Logdatei (wird fortgeschrieben)
//   --log-level <Stufe>   debug, info, warning, error (Standard: info)
//   --trace <Datei>       Mitschnitt aller JSON-Nachrichten
//
// Werte können auch mit "=" angegeben werden (--log=server.log). Parameter,
// die Editoren selbst anhängen (--stdio, --clientProcessId), werden ignoriert.

interface

uses
  BDLsp.Common.Logging.Contract;

type
  TCommandLineOptions = record
  public const
    DefaultLogLevel = TLogLevel.Info;
  public
    LogFile: string;
    LogLevel: TLogLevel;
    TraceFile: string;
    /// <summary>Hinweise zu ungültigen oder unbekannten Parametern, für das Log.</summary>
    Warnings: TArray<string>;
    class function Parse(const AArgs: TArray<string>): TCommandLineOptions; static;
    /// <summary>Parameter des laufenden Prozesses.</summary>
    class function FromProcess: TCommandLineOptions; static;
    class function TryParseLogLevel(const AText: string; out ALevel: TLogLevel): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TCommandLineOptions }

class function TCommandLineOptions.TryParseLogLevel(const AText: string; out ALevel: TLogLevel): Boolean;
var
  Text: string;
begin
  Text := AText.Trim.ToLower;
  Result := True;
  if Text = 'debug' then
    ALevel := TLogLevel.Debug
  else if Text = 'info' then
    ALevel := TLogLevel.Info
  else if (Text = 'warning') or (Text = 'warn') then
    ALevel := TLogLevel.Warning
  else if Text = 'error' then
    ALevel := TLogLevel.Error
  else
    Result := False;
end;

class function TCommandLineOptions.Parse(const AArgs: TArray<string>): TCommandLineOptions;
var
  Index: Integer;
  Arg: string;
  Name: string;
  Value: string;
  HasValue: Boolean;
  Separator: Integer;

  procedure AddWarning(const AText: string);
  begin
    Result.Warnings := Result.Warnings + [AText];
  end;

  function TakeValue: Boolean;
  begin
    if HasValue then
      Exit(True);
    if Index < High(AArgs) then
    begin
      Inc(Index);
      Value := AArgs[Index];
      Exit(True);
    end;
    AddWarning(Format('Parameter %s erwartet einen Wert', [Name]));
    Result := False;
  end;

var
  Level: TLogLevel;
begin
  Result := Default(TCommandLineOptions);
  Result.LogLevel := DefaultLogLevel;

  Index := Low(AArgs);
  while Index <= High(AArgs) do
  begin
    Arg := AArgs[Index];
    Separator := Arg.IndexOf('=');
    HasValue := Separator > 0;
    if HasValue then
    begin
      Name := Arg.Substring(0, Separator).ToLower;
      Value := Arg.Substring(Separator + 1);
    end
    else
    begin
      Name := Arg.ToLower;
      Value := '';
    end;

    if Name = '--log' then
    begin
      if TakeValue then
        Result.LogFile := Value;
    end
    else if Name = '--log-level' then
    begin
      if TakeValue then
        if TryParseLogLevel(Value, Level) then
          Result.LogLevel := Level
        else
          AddWarning(Format('Unbekannte Log-Stufe "%s", verwendet wird info', [Value]));
    end
    else if Name = '--trace' then
    begin
      if TakeValue then
        Result.TraceFile := Value;
    end
    else if (Name = '--stdio') or (Name = '--clientprocessid') then
      // von Editoren angehängt, ohne Bedeutung für den Server
    else
      AddWarning(Format('Unbekannter Parameter "%s" wird ignoriert', [Arg]));

    Inc(Index);
  end;
end;

class function TCommandLineOptions.FromProcess: TCommandLineOptions;
var
  Args: TArray<string>;
  I: Integer;
begin
  SetLength(Args, ParamCount);
  for I := 1 to ParamCount do
    Args[I - 1] := ParamStr(I);
  Result := Parse(Args);
end;

end.
