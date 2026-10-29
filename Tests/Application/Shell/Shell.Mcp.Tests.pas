unit Shell.Mcp.Tests;

// tools/list enthält alle in docs/MCP.md genannten Werkzeuge und umgekehrt (#48).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpShellTests = class
  public
    [Test]
    procedure ToolsListMatchesDocumentation;
    [Test]
    procedure ListsArchitectureTool;
    [Test]
    procedure ListsFindPathTool;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  Shell.Mcp;

function DocumentationFile: string;
var
  Folder: string;
begin
  // Vom Testprogramm aufwärts bis zum Repository.
  Folder := ExtractFileDir(ParamStr(0));
  while Folder <> ExtractFileDir(Folder) do
  begin
    Result := TPath.Combine(Folder, 'docs\MCP.md');
    if FileExists(Result) then
      Exit;
    Folder := ExtractFileDir(Folder);
  end;
  Result := '';
end;

// Nur der Abschnitt „## Werkzeuge“: Die Tabellen der Ressourcen und Prompts (#1357) haben dieselbe Form.
function ToolSection(const AText: string): string;
var
  mText: string;
  mStart: Integer;
  mEnd: Integer;
begin
  mText := AText.Replace(#13#10, #10);
  mStart := Pos(#10'## Werkzeuge'#10, mText);
  Assert.IsTrue(mStart > 0, 'Abschnitt „## Werkzeuge“ fehlt in docs\MCP.md');
  Result := Copy(mText, mStart + 1, MaxInt);
  mEnd := Pos(#10'## ', Result);
  if mEnd > 0 then
    Result := Copy(Result, 1, mEnd);
end;

procedure TMcpShellTests.ToolsListMatchesDocumentation;
var
  Listed, Documented: TArray<string>;
  Match: TMatch;
  Name: string;
  FileName: string;
begin
  FileName := DocumentationFile;
  Assert.IsTrue(FileName <> '', 'docs\MCP.md nicht gefunden');
  Documented := nil;
  for Match in TRegEx.Matches(ToolSection(TFile.ReadAllText(FileName, TEncoding.UTF8)), '^\| `(\w+)` \|', [roMultiLine]) do
    Documented := Documented + [Match.Groups[1].Value];
  Listed := TMcpShell.ToolNames;
  Assert.IsTrue(Length(Listed) >= 11, 'zu wenige Werkzeuge registriert');
  for Name in Documented do
    Assert.Contains(string.Join(' ', Listed), Name, 'in docs/MCP.md, aber nicht in tools/list: ' + Name);
  for Name in Listed do
    Assert.Contains(string.Join(' ', Documented), Name, 'in tools/list, aber nicht in docs/MCP.md: ' + Name);
end;

procedure TMcpShellTests.ListsArchitectureTool;
var
  Name: string;
  Found: Boolean;
begin
  Found := False;
  for Name in TMcpShell.ToolNames do
    Found := Found or (Name = 'get_architecture');
  Assert.IsTrue(Found, 'get_architecture fehlt in tools/list');
end;

procedure TMcpShellTests.ListsFindPathTool;
var
  Name: string;
  Found: Boolean;
begin
  // Weg zwischen Symbolen (#1117).
  Found := False;
  for Name in TMcpShell.ToolNames do
    Found := Found or (Name = 'find_path');
  Assert.IsTrue(Found, 'find_path fehlt in tools/list');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpShellTests);

end.