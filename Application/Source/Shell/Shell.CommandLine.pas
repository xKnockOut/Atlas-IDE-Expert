unit Shell.CommandLine;

// Host-Rolle Shell: Kommandozeilenparameter des Servers.
//
//   --log <Datei>         Logdatei (wird fortgeschrieben)
//   --log-level <Stufe>   debug, info, warning, error (Standard: info)
//   --trace <Datei>       Mitschnitt aller JSON-Nachrichten
//
// Linter-Modus ohne Editor (#95):
//   --check <Ziel>        .dproj, Ordner oder einzelne Datei prüfen
//   --format <Art>        text (Standard), json, sarif
//   --output <Datei>      Ergebnis in Datei statt auf stdout
//   --rules <a,b>         nur diese Regeln
//   --units <a,b>         nur diese Units (Name oder Glob-Muster für Pfade)
//   --min-severity <S>    hint, info, warning, error
//   --profile <Name>      Regelprofil (#146), vor "profile" aus atlas.json
//   --changed [<Basis>]   nur Dateien, die sich gegenüber der Merge-Base mit <Basis>
//                         (Standard main) geändert haben (Git, #157)
//   --diff <Ref>          nur Dateien, die sich gegenüber <Ref> geändert haben
//   --include-uncommitted mit --changed/--diff auch Index und Arbeitsverzeichnis
//   --changed-lines       nur Treffer in geänderten Zeilen
//
// MCP-Modus (#48):
//   --mcp                 Symbolindex über das Model Context Protocol anbieten
//   --root <Ordner>       Projektordner (Standard: aktuelles Verzeichnis)
//
// Werte können auch mit "=" angegeben werden (--log=server.log). --stdio, das
// Editoren anhängen, wird ignoriert; --clientProcessId=<PID> nennt den Editor-
// Prozess, dessen Ende auch den Server beendet (#283).

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Output;

type
  TCommandLineOptions = record
  public const
    DefaultLogLevel = TLogLevel.Info;
    DefaultChangedBase = 'main';
  public
    LogFile: string;
    LogLevel: TLogLevel;
    TraceFile: string;
    /// <summary>Ziel des Linter-Modus; '' = Server-Modus.</summary>
    CheckTarget: string;
    CheckFormat: TFindingsFormat;
    OutputFile: string;
    RuleFilter: TArray<string>;
    UnitFilter: TArray<string>;
    MinSeverity: TRuleSeverity;
    /// <summary>Regelprofil für --check (#146); '' = aus atlas.json.</summary>
    Profile: string;
    /// <summary>Statt der Treffer die Unterdrückungen je Regel ausgeben (#147).</summary>
    SuppressionStats: Boolean;
    /// <summary>Baseline-Datei (#97); '' = atlas-baseline.json neben atlas.json, falls vorhanden.</summary>
    BaselineFile: string;
    /// <summary>Baseline aus den aktuellen Treffern neu schreiben statt zu prüfen.</summary>
    UpdateBaseline: Boolean;
    /// <summary>Git-Ref, gegen den --changed/--diff vergleicht (#157); '' = alle Dateien.</summary>
    ChangedRef: string;
    /// <summary>True bei --changed: Vergleich mit der Merge-Base von ChangedRef und HEAD.</summary>
    ChangedMergeBase: Boolean;
    /// <summary>Index und Arbeitsverzeichnis einbeziehen.</summary>
    IncludeUncommitted: Boolean;
    /// <summary>Nur Treffer in geänderten Zeilen ausgeben.</summary>
    ChangedLines: Boolean;
    /// <summary>Index-Caches löschen und beenden (#184).</summary>
    ClearCache: Boolean;
    /// <summary>Nicht vertrauenswürdiger Arbeitsbereich (#186): nichts ausführen, was Code aus dem Projekt startet.</summary>
    Restricted: Boolean;
    /// <summary>MCP-Modus statt LSP (#48).</summary>
    Mcp: Boolean;
    /// <summary>Projektordner im MCP-Modus; '' = aktuelles Verzeichnis.</summary>
    McpRoot: string;
    /// <summary>Prozess-ID des Editors aus --clientProcessId; 0 = unbekannt.</summary>
    ClientProcessId: Cardinal;
    /// <summary>Hinweise zu ungültigen oder unbekannten Parametern, für das Log.</summary>
    Warnings: TArray<string>;
    class function Parse(const AArgs: TArray<string>): TCommandLineOptions; static;
    /// <summary>Parameter des laufenden Prozesses.</summary>
    class function FromProcess: TCommandLineOptions; static;
    class function TryParseLogLevel(const AText: string; out ALevel: TLogLevel): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Filter;

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

/// <summary>"-log" und "–log" (Gedankenstrich, z. B. aus Word oder Chat kopiert) gelten als "--log" (#647).</summary>
function NormalizeDashes(const AArg: string): string;
begin
  Result := AArg;
  if (Result <> '') and ((Result[1] = #$2013) or (Result[1] = #$2014)) then
    Result := '--' + Result.Substring(1)
  else if (Length(Result) > 1) and (Result[1] = '-') and CharInSet(Result[2], ['A'..'Z', 'a'..'z']) then
    Result := '-' + Result;
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
  CheckFormat: TFindingsFormat;
  Severity: TRuleSeverity;
  ProcessId: Cardinal;
begin
  Result := Default(TCommandLineOptions);
  Result.LogLevel := DefaultLogLevel;

  Index := Low(AArgs);
  while Index <= High(AArgs) do
  begin
    Arg := NormalizeDashes(AArgs[Index]);
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
    else if Name = '--check' then
    begin
      if TakeValue then
        Result.CheckTarget := Value;
    end
    else if Name = '--format' then
    begin
      if TakeValue then
        if TFindingsOutput.TryParseFormat(Value, CheckFormat) then
          Result.CheckFormat := CheckFormat
        else
          AddWarning(Format('Unbekanntes Format "%s", verwendet wird text', [Value]));
    end
    else if Name = '--output' then
    begin
      if TakeValue then
        Result.OutputFile := Value;
    end
    else if Name = '--rules' then
    begin
      if TakeValue then
        Result.RuleFilter := TFindingFilter.SplitList(Value);
    end
    else if Name = '--units' then
    begin
      if TakeValue then
        Result.UnitFilter := TFindingFilter.SplitList(Value);
    end
    else if Name = '--min-severity' then
    begin
      if TakeValue then
        if TConfigurationParser.TryParseSeverity(Value, Severity) and (Severity <> TRuleSeverity.Off) then
          Result.MinSeverity := Severity
        else
          AddWarning(Format('Unbekannter Schweregrad "%s", gemeldet wird alles', [Value]));
    end
    else if Name = '--profile' then
    begin
      if TakeValue then
        Result.Profile := Value;
    end
    else if Name = '--baseline' then
    begin
      if TakeValue then
        Result.BaselineFile := Value;
    end
    else if Name = '--changed' then
    begin
      // Basis optional: --changed, --changed=dev oder --changed dev
      Result.ChangedMergeBase := True;
      if HasValue then
        Result.ChangedRef := Value
      else if (Index < High(AArgs)) and not AArgs[Index + 1].StartsWith('-') then
      begin
        Inc(Index);
        Result.ChangedRef := AArgs[Index];
      end
      else
        Result.ChangedRef := DefaultChangedBase;
    end
    else if Name = '--diff' then
    begin
      if TakeValue then
      begin
        Result.ChangedRef := Value;
        Result.ChangedMergeBase := False;
      end;
    end
    else if Name = '--root' then
    begin
      if TakeValue then
        Result.McpRoot := Value;
    end
    else if Name = '--mcp' then
      Result.Mcp := True
    else if Name = '--restricted' then
      Result.Restricted := True
    else if Name = '--clear-cache' then
      Result.ClearCache := True
    else if Name = '--include-uncommitted' then
      Result.IncludeUncommitted := True
    else if Name = '--changed-lines' then
      Result.ChangedLines := True
    else if Name = '--update-baseline' then
      Result.UpdateBaseline := True
    else if Name = '--suppression-stats' then
      Result.SuppressionStats := True
    else if Name = '--clientprocessid' then
    begin
      if TakeValue then
        if TryStrToUInt(Value, ProcessId) then
          Result.ClientProcessId := ProcessId
        else
          AddWarning(Format('Ungültige Prozess-ID "%s" wird ignoriert', [Value]));
    end
    else if Name = '--stdio' then
      // von Editoren angehängt, ohne Bedeutung für den Server
    else
      AddWarning(Format('Unbekannter Parameter "%s" wird ignoriert', [Arg]));

    Inc(Index);
  end;
  if (Result.IncludeUncommitted or Result.ChangedLines) and (Result.ChangedRef = '') then
  begin
    // Ohne Ref gilt --changed mit der Standardbasis.
    Result.ChangedRef := DefaultChangedBase;
    Result.ChangedMergeBase := True;
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
