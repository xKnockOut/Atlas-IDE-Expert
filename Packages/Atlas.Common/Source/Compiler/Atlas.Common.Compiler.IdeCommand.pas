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
    cStartTimeoutSec = 180;
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
  Result := ['start', '-Project', AProject, '-TimeoutSec', IntToStr(cStartTimeoutSec)];
end;

class function TCompilerIdeCommand.BuildArguments(APid: Cardinal; const AProject, APlatform: string): TArray<string>;
begin
  Result := ['build', '-Instance', IntToStr(APid), '-Project', AProject];
  if APlatform <> '' then
  begin
    Result := Result + ['-Platform', APlatform];
  end;
  Result := Result + ['-Json'];
end;

class function TCompilerIdeCommand.QuitArguments(APid: Cardinal): TArray<string>;
begin
  Result := ['quit', '-Instance', IntToStr(APid)];
end;

class function TCompilerIdeCommand.ParsePid(const AOutput: TArray<string>; out APid: Cardinal): Boolean;
var
  mLine, mLower: string;
  mIndex, mStart: Integer;
  mValue: Int64;
begin
  APid := 0;
  for mLine in AOutput do
  begin
    mLower := LowerCase(mLine);
    mIndex := Pos('pid', mLower);
    if mIndex = 0 then
    begin
      Continue;
    end;
    mIndex := mIndex + 3;
    // "pid N", "pid: N", "pid=N"
    while (mIndex <= Length(mLower)) and not CharInSet(mLower[mIndex], ['0'..'9']) and
      CharInSet(mLower[mIndex], [' ', ':', '=', #9]) do
    begin
      Inc(mIndex);
    end;
    mStart := mIndex;
    while (mIndex <= Length(mLower)) and CharInSet(mLower[mIndex], ['0'..'9']) do
    begin
      Inc(mIndex);
    end;
    if (mIndex > mStart) and TryStrToInt64(Copy(mLower, mStart, mIndex - mStart), mValue) and (mValue > 0) and
      (mValue <= High(Cardinal)) then
    begin
      APid := Cardinal(mValue);
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TCompilerIdeCommand.ParseBuild(const AOutput: TArray<string>; out AReport: TIdeBuildReport): Boolean;
var
  mText: string;
  mFirst, mLast: Integer;
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  AReport := Default(TIdeBuildReport);
  mText := string.Join(#10, AOutput);
  mFirst := Pos('{', mText);
  mLast := LastDelimiter('}', mText);
  if (mFirst = 0) or (mLast < mFirst) then
  begin
    Exit(False);
  end;
  mValue := TJSONObject.ParseJSONValue(Copy(mText, mFirst, mLast - mFirst + 1));
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AReport.Ok := mRoot.GetValue<Boolean>('ok', False);
    AReport.OutputWritten := mRoot.GetValue<Boolean>('outputWritten', False);
    AReport.LogFile := mRoot.GetValue<string>('logFile', '');
    AReport.Error := mRoot.GetValue<string>('error', '');
    if AReport.Error = '' then
    begin
      AReport.Error := mRoot.GetValue<string>('message', '');
    end;
  finally
    mValue.Free;
  end;
end;

class function TCompilerIdeCommand.Messages(const ALogLines: TArray<string>;
  const AProject: string): TArray<TCompilerMessage>;
begin
  Result := TCompilerOutputParser.Parse(ALogLines, TProjectPaths.DirectoryOf(AProject));
end;

end.
