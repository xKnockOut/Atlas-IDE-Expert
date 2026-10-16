unit Atlas.Common.Compiler.IdeCommand;

// Kompilieren über eine eigene IDE mit cc.ps1 (#261, ADR 0007), ohne
// Prozessstart: Aufrufe und Auswertung der Antworten. Ablauf im Host:
//   1. cc.ps1 start -Project <dproj> -TimeoutSec 180 startet eine
//      Scratch-IDE; ihre pid steht in der Ausgabe („IDE started : pid 1234“).
//      Der Host prüft, dass die pid zu keiner schon vorher laufenden IDE
//      gehört (die IDE des Benutzers wird nie angesprochen).
//   2. cc.ps1 build -Instance <pid> -Project <dproj> -Platform <p> -Json baut
//      in genau dieser IDE und liefert JSON mit ok, outputWritten und logFile.
//      Weitere Läufe nutzen dieselbe Instanz, solange sie läuft.
//   3. Das logFile enthält Zeilen wie „[dcc64 Fehler] Unit1.pas(12): E2003 …“;
//      sie liest der vorhandene TCompilerOutputParser.
//   4. cc.ps1 quit -Instance <pid> beim Beenden des Servers.
// Jeder Aufruf außer start trägt -Instance.

interface

uses
  System.SysUtils,
  Atlas.Common.Compiler.Contract;

type
  /// <summary>Antwort von "cc.ps1 build … -Json".</summary>
  TIdeBuildReport = record
    Ok: Boolean;
    OutputWritten: Boolean;
    /// <summary>Build-Log der IDE; '' ohne.</summary>
    LogFile: string;
    /// <summary>Fehlertext von cc.ps1 ("error" oder "message"); '' ohne.</summary>
    Error: string;
  end;

  TCompilerIdeCommand = class
  public const
    StartTimeoutSec = 180;
  public
    /// <summary>Aufruf von AScript (cc.ps1) über PowerShell APowerShell (pwsh.exe oder powershell.exe).</summary>
    class function Request(const APowerShell, AScript: string; const AArguments: TArray<string>;
      const AWorkingDir: string): TCompilerRequest; static;
    class function StartArguments(const AProject: string): TArray<string>; static;
    /// <summary>Plattform nur, wenn angegeben; sonst gilt die des Projekts.</summary>
    class function BuildArguments(APid: Cardinal; const AProject, APlatform: string): TArray<string>; static;
    class function QuitArguments(APid: Cardinal): TArray<string>; static;
    /// <summary>pid der gestarteten IDE aus der Ausgabe von start ("… pid 1234"); False ohne.</summary>
    class function ParsePid(const AOutput: TArray<string>; out APid: Cardinal): Boolean; static;
    /// <summary>JSON-Antwort von build (cc.ps1 kann davor Text ausgeben); False ohne lesbares JSON.</summary>
    class function ParseBuild(const AOutput: TArray<string>; out AReport: TIdeBuildReport): Boolean; static;
    /// <summary>Meldungen aus den Zeilen des logFile; relative Dateinamen gelten im Ordner von AProject.</summary>
    class function Messages(const ALogLines: TArray<string>; const AProject: string): TArray<TCompilerMessage>;
      static;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Compiler.OutputParser;

class function TCompilerIdeCommand.Request(const APowerShell, AScript: string; const AArguments: TArray<string>;
  const AWorkingDir: string): TCompilerRequest;
begin
  Result := Default(TCompilerRequest);
  Result.Executable := APowerShell;
  Result.Arguments := TArray<string>.Create('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
    AScript) + AArguments;
  Result.WorkingDir := AWorkingDir;
end;

class function TCompilerIdeCommand.StartArguments(const AProject: string): TArray<string>;
begin
  Result := ['start', '-Project', AProject, '-TimeoutSec', IntToStr(StartTimeoutSec)];
end;

class function TCompilerIdeCommand.BuildArguments(APid: Cardinal; const AProject, APlatform: string): TArray<string>;
begin
  Result := ['build', '-Instance', IntToStr(APid), '-Project', AProject];
  if APlatform <> '' then
    Result := Result + ['-Platform', APlatform];
  Result := Result + ['-Json'];
end;

class function TCompilerIdeCommand.QuitArguments(APid: Cardinal): TArray<string>;
begin
  Result := ['quit', '-Instance', IntToStr(APid)];
end;

class function TCompilerIdeCommand.ParsePid(const AOutput: TArray<string>; out APid: Cardinal): Boolean;
var
  Line, Lower: string;
  Index, Start: Integer;
  Value: Int64;
begin
  APid := 0;
  for Line in AOutput do
  begin
    Lower := LowerCase(Line);
    Index := Pos('pid', Lower);
    if Index = 0 then
      Continue;
    Index := Index + 3;
    // "pid N", "pid: N", "pid=N"
    while (Index <= Length(Lower)) and not CharInSet(Lower[Index], ['0'..'9']) and
      CharInSet(Lower[Index], [' ', ':', '=', #9]) do
      Inc(Index);
    Start := Index;
    while (Index <= Length(Lower)) and CharInSet(Lower[Index], ['0'..'9']) do
      Inc(Index);
    if (Index > Start) and TryStrToInt64(Copy(Lower, Start, Index - Start), Value) and (Value > 0) and
      (Value <= High(Cardinal)) then
    begin
      APid := Cardinal(Value);
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompilerIdeCommand.ParseBuild(const AOutput: TArray<string>; out AReport: TIdeBuildReport): Boolean;
var
  Text: string;
  First, Last: Integer;
  Value: TJSONValue;
  Root: TJSONObject;
begin
  AReport := Default(TIdeBuildReport);
  Text := string.Join(#10, AOutput);
  First := Pos('{', Text);
  Last := LastDelimiter('}', Text);
  if (First = 0) or (Last < First) then
    Exit(False);
  Value := TJSONObject.ParseJSONValue(Copy(Text, First, Last - First + 1));
  try
    Result := Value is TJSONObject;
    if not Result then
      Exit;
    Root := TJSONObject(Value);
    AReport.Ok := Root.GetValue<Boolean>('ok', False);
    AReport.OutputWritten := Root.GetValue<Boolean>('outputWritten', False);
    AReport.LogFile := Root.GetValue<string>('logFile', '');
    AReport.Error := Root.GetValue<string>('error', '');
    if AReport.Error = '' then
      AReport.Error := Root.GetValue<string>('message', '');
  finally
    Value.Free;
  end;
end;

class function TCompilerIdeCommand.Messages(const ALogLines: TArray<string>;
  const AProject: string): TArray<TCompilerMessage>;
begin
  Result := TCompilerOutputParser.Parse(ALogLines, TProjectPaths.DirectoryOf(AProject));
end;

end.
