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
  Folder: string;
begin
  Folder := AFolder;
  while (Folder <> '') and CharInSet(Folder[Length(Folder)], ['\', '/']) do
    SetLength(Folder, Length(Folder) - 1);
  Result := Folder + '\' + AName;
  // Unter Linux (Tests unter FPC) gilt / als Trenner.
  if PathDelim <> '\' then
    Result := StringReplace(Result, '\', PathDelim, [rfReplaceAll]);
end;

{ TAtlasTaskCommands }

class function TAtlasTaskCommands.FindProgram(const ACommand, ACwd, APath, APathExt: string;
  const AExists: TAtlasTaskFileExists): string;
var
  Extensions, Folders: TArray<string>;
  Folder, Extension, Base: string;

  function Probe(const ACandidate: string; out AFound: string): Boolean;
  var
    Ext: string;
  begin
    AFound := '';
    // Mit eigener Endung zuerst so, wie sie dasteht.
    if (ExtractFileExt(ACandidate) <> '') and AExists(ACandidate) then
    begin
      AFound := ACandidate;
      Exit(True);
    end;
    for Ext in Extensions do
      if AExists(ACandidate + Ext) then
      begin
        AFound := ACandidate + Ext;
        Exit(True);
      end;
    Result := False;
  end;

begin
  Result := '';
  if Trim(ACommand) = '' then
    Exit;
  Extensions := nil;
  for Extension in APathExt.Split([';']) do
    if Trim(Extension) <> '' then
      Extensions := Extensions + [AnsiLowerCase(Trim(Extension))];
  if Length(Extensions) = 0 then
    Extensions := TArray<string>.Create('.com', '.exe', '.bat', '.cmd');
  if HasPathPart(ACommand) then
  begin
    Base := ACommand;
    if not ((Length(Base) >= 2) and (Base[2] = ':')) and not CharInSet(Base[1], ['\', '/']) and (ACwd <> '') then
      Base := JoinPath(ACwd, Base);
    Probe(Base, Result);
    Exit;
  end;
  Folders := nil;
  if ACwd <> '' then
    Folders := Folders + [ACwd];
  for Folder in APath.Split([';']) do
    if Trim(Folder) <> '' then
      Folders := Folders + [Trim(StringReplace(Folder, '"', '', [rfReplaceAll]))];
  for Folder in Folders do
    if Probe(JoinPath(Folder, ACommand), Result) then
      Exit;
end;

class function TAtlasTaskCommands.MergeEnvironment(const ACurrent, ANames, AValues: TArray<string>): TArray<string>;
var
  Index, Item, Split: Integer;
  Found: Boolean;
begin
  Result := Copy(ACurrent);
  for Index := 0 to High(ANames) do
  begin
    if (Trim(ANames[Index]) = '') or (Index > High(AValues)) then
      Continue;
    Found := False;
    for Item := 0 to High(Result) do
    begin
      // Einträge wie „=C:=C:\“ beginnen mit „=“ und gehören zum Prozess.
      Split := Pos('=', Copy(Result[Item], 2, MaxInt)) + 1;
      if (Split > 1) and SameText(Copy(Result[Item], 1, Split - 1), ANames[Index]) then
      begin
        Result[Item] := ANames[Index] + '=' + AValues[Index];
        Found := True;
        Break;
      end;
    end;
    if not Found then
      Result := Result + [ANames[Index] + '=' + AValues[Index]];
  end;
end;

class function TAtlasTaskCommands.QuoteArgument(const AArgument: string): string;
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
  Result := Result + StringOfChar('\', Backslashes) + '"';
end;

class function TAtlasTaskCommands.BuildCommandLine(const AProgram: string; const AArgs: TArray<string>;
  ABatch: Boolean): string;
var
  Arg: string;
begin
  Result := QuoteArgument(AProgram);
  for Arg in AArgs do
    Result := Result + ' ' + QuoteArgument(Arg);
  // /s: cmd nimmt nur die äußeren Anführungszeichen weg, der Rest bleibt wie geschrieben.
  if ABatch then
    Result := 'cmd.exe /d /s /c "' + Result + '"';
end;

class function TAtlasTaskCommands.IsBatch(const AProgram: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AProgram), '.bat') or SameText(ExtractFileExt(AProgram), '.cmd');
end;

end.
