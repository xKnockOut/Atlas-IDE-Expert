unit Atlas.Core.Tasks.Commands;

// Befehlszeile einer Projektaufgabe (#900), ohne Betriebssystem prüfbar:
// - FindProgram: mit Pfad gegen den Arbeitsordner, sonst im Arbeitsordner und
//   in PATH, jeweils auch mit den Endungen aus PATHEXT. Ohne Treffer ''.
// - MergeEnvironment: Umgebung des Plugins, darüber env der Aufgabe (Namen
//   ohne Groß-/Kleinschreibung).
// - QuoteArgument/BuildCommandLine nach den Regeln von CommandLineToArgvW;
//   .bat und .cmd laufen über cmd.exe /d /s /c.
// Den Prozess selbst startet Atlas.Core.Tasks.Adapters.Process.

interface

uses
  System.SysUtils,
  Atlas.Core.Tasks.Matchers;

type
  TAtlasTaskCommands = class
  public
    /// <summary>Pfad des Programms ACommand oder ''. APath und APathExt wie die Umgebungsvariablen PATH und
    /// PATHEXT (durch ; getrennt).</summary>
    class function FindProgram(const ACommand, ACwd, APath, APathExt: string;
      const AExists: TAtlasTaskFileExists): string; static;
    /// <summary>ACurrent („NAME=Wert“) mit ANames/AValues überschrieben bzw. ergänzt.</summary>
    class function MergeEnvironment(const ACurrent, ANames, AValues: TArray<string>): TArray<string>; static;
    /// <summary>Argument nach den Regeln von CommandLineToArgvW.</summary>
    class function QuoteArgument(const AArgument: string): string; static;
    /// <summary>Befehlszeile für CreateProcess; ABatch: über cmd.exe /d /s /c.</summary>
    class function BuildCommandLine(const AProgram: string; const AArgs: TArray<string>; ABatch: Boolean): string;
      static;
    /// <summary>True für .bat und .cmd.</summary>
    class function IsBatch(const AProgram: string): Boolean; static;
  end;

implementation

function HasPathPart(const ACommand: string): Boolean;
begin
  Result := (Pos('\', ACommand) > 0) or (Pos('/', ACommand) > 0) or ((Length(ACommand) >= 2) and
    (ACommand[2] = ':'));
end;

function JoinPath(const AFolder, AName: string): string;
var
  mFolder: string;
begin
  mFolder := AFolder;
  while (mFolder <> '') and CharInSet(mFolder[Length(mFolder)], ['\', '/']) do
  begin
    SetLength(mFolder, Length(mFolder) - 1);
  end;
  Result := mFolder + '\' + AName;
  // Unter Linux (Tests unter FPC) gilt / als Trenner.
  if PathDelim <> '\' then
  begin
    Result := StringReplace(Result, '\', PathDelim, [rfReplaceAll]);
  end;
end;

/// <summary>Endungen aus PATHEXT (klein); ohne Angabe .com, .exe, .bat, .cmd.</summary>
function ProgramExtensions(const APathExt: string): TArray<string>;
var
  mExtension: string;
begin
  Result := nil;
  for mExtension in APathExt.Split([';']) do
  begin
    if Trim(mExtension) <> '' then
    begin
      Result := Result + [AnsiLowerCase(Trim(mExtension))];
    end;
  end;
  if Length(Result) = 0 then
  begin
    Result := TArray<string>.Create('.com', '.exe', '.bat', '.cmd');
  end;
end;

/// <summary>Arbeitsordner (falls angegeben) und die Ordner aus PATH ohne Anführungszeichen.</summary>
function ProgramFolders(const ACwd, APath: string): TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  if ACwd <> '' then
  begin
    Result := Result + [ACwd];
  end;
  for mFolder in APath.Split([';']) do
  begin
    if Trim(mFolder) <> '' then
    begin
      Result := Result + [Trim(StringReplace(mFolder, '"', '', [rfReplaceAll]))];
    end;
  end;
end;

/// <summary>ACandidate mit eigener Endung, sonst mit einer der Endungen AExtensions; '' ohne Treffer.</summary>
function ProbeProgram(const ACandidate: string; const AExtensions: TArray<string>;
  const AExists: TAtlasTaskFileExists): string;
var
  mExt: string;
begin
  // Mit eigener Endung zuerst so, wie sie dasteht.
  if (ExtractFileExt(ACandidate) <> '') and AExists(ACandidate) then
  begin
    Exit(ACandidate);
  end;
  for mExt in AExtensions do
  begin
    if AExists(ACandidate + mExt) then
    begin
      Exit(ACandidate + mExt);
    end;
  end;
  Result := '';
end;

{ TAtlasTaskCommands }

class function TAtlasTaskCommands.FindProgram(const ACommand, ACwd, APath, APathExt: string;
  const AExists: TAtlasTaskFileExists): string;
var
  mExtensions: TArray<string>;
  mFolder, mBase: string;
begin
  Result := '';
  if Trim(ACommand) = '' then
  begin
    Exit;
  end;
  mExtensions := ProgramExtensions(APathExt);
  if HasPathPart(ACommand) then
  begin
    mBase := ACommand;
    if not ((Length(mBase) >= 2) and (mBase[2] = ':')) and not CharInSet(mBase[1], ['\', '/']) and (ACwd <> '') then
    begin
      mBase := JoinPath(ACwd, mBase);
    end;
    Exit(ProbeProgram(mBase, mExtensions, AExists));
  end;
  for mFolder in ProgramFolders(ACwd, APath) do
  begin
    Result := ProbeProgram(JoinPath(mFolder, ACommand), mExtensions, AExists);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

class function TAtlasTaskCommands.MergeEnvironment(const ACurrent, ANames, AValues: TArray<string>): TArray<string>;
var
  mIndex, mItem, mSplit: Integer;
  mFound: Boolean;
begin
  Result := Copy(ACurrent);
  for mIndex := 0 to High(ANames) do
  begin
    if (Trim(ANames[mIndex]) = '') or (mIndex > High(AValues)) then
    begin
      Continue;
    end;
    mFound := False;
    for mItem := 0 to High(Result) do
    begin
      // Einträge wie „=C:=C:\“ beginnen mit „=“ und gehören zum Prozess.
      mSplit := Pos('=', Copy(Result[mItem], 2, MaxInt)) + 1;
      if (mSplit > 1) and SameText(Copy(Result[mItem], 1, mSplit - 1), ANames[mIndex]) then
      begin
        Result[mItem] := ANames[mIndex] + '=' + AValues[mIndex];
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [ANames[mIndex] + '=' + AValues[mIndex]];
    end;
  end;
end;

class function TAtlasTaskCommands.QuoteArgument(const AArgument: string): string;
var
  mIndex, mBackslashes: Integer;
begin
  if (AArgument <> '') and (LastDelimiter(' '#9'"', AArgument) = 0) then
  begin
    Exit(AArgument);
  end;
  Result := '"';
  mBackslashes := 0;
  for mIndex := 1 to Length(AArgument) do
  begin
    if AArgument[mIndex] = '\' then
    begin
      Inc(mBackslashes);
    end
    else
    begin
      if AArgument[mIndex] = '"' then
      begin
        Result := Result + StringOfChar('\', mBackslashes + 1);
      end;
      mBackslashes := 0;
    end;
    Result := Result + AArgument[mIndex];
  end;
  Result := Result + StringOfChar('\', mBackslashes) + '"';
end;

class function TAtlasTaskCommands.BuildCommandLine(const AProgram: string; const AArgs: TArray<string>;
  ABatch: Boolean): string;
var
  mArg: string;
begin
  Result := QuoteArgument(AProgram);
  for mArg in AArgs do
  begin
    Result := Result + ' ' + QuoteArgument(mArg);
  end;
  // /s: cmd nimmt nur die äußeren Anführungszeichen weg, der Rest bleibt wie geschrieben.
  if ABatch then
  begin
    Result := 'cmd.exe /d /s /c "' + Result + '"';
  end;
end;

class function TAtlasTaskCommands.IsBatch(const AProgram: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AProgram), '.bat') or SameText(ExtractFileExt(AProgram), '.cmd');
end;

end.
