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
    [Test]
    procedure ListsHotspotsTool;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  Shell.Mcp;

function DocumentationFile: string;
var
  mFolder: string;
begin
  // Vom Testprogramm aufwärts bis zum Repository.
  mFolder := ExtractFileDir(ParamStr(0));
  while mFolder <> ExtractFileDir(mFolder) do
  begin
    Result := TPath.Combine(mFolder, 'docs\MCP.md');
    if FileExists(Result) then
    begin
      Exit;
    end;
    mFolder := ExtractFileDir(mFolder);
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
  begin
    Result := Copy(Result, 1, mEnd);
  end;
end;

procedure TMcpShellTests.ToolsListMatchesDocumentation;
var
  mListed, mDocumented: TArray<string>;
  mMatch: TMatch;
  mName: string;
  mFileName: string;
begin
  mFileName := DocumentationFile;
  Assert.IsTrue(mFileName <> '', 'docs\MCP.md nicht gefunden');
  mDocumented := nil;
  for mMatch in TRegEx.Matches(ToolSection(TFile.ReadAllText(mFileName, TEncoding.UTF8)), '^\| `(\w+)` \|', [roMultiLine]) do
  begin
    mDocumented := mDocumented + [mMatch.Groups[1].Value];
  end;
  mListed := TMcpShell.ToolNames;
  Assert.IsTrue(Length(mListed) >= 11, 'zu wenige Werkzeuge registriert');
  for mName in mDocumented do
  begin
    Assert.Contains(string.Join(' ', mListed), mName, 'in docs/MCP.md, aber nicht in tools/list: ' + mName);
  end;
  for mName in mListed do
  begin
    Assert.Contains(string.Join(' ', mDocumented), mName, 'in tools/list, aber nicht in docs/MCP.md: ' + mName);
  end;
end;

procedure TMcpShellTests.ListsArchitectureTool;
var
  mName: string;
  mFound: Boolean;
begin
  mFound := False;
  for mName in TMcpShell.ToolNames do
  begin
    mFound := mFound or (mName = 'get_architecture');
  end;
  Assert.IsTrue(mFound, 'get_architecture fehlt in tools/list');
end;

procedure TMcpShellTests.ListsFindPathTool;
var
  mName: string;
  mFound: Boolean;
begin
  // Weg zwischen Symbolen (#1117).
  mFound := False;
  for mName in TMcpShell.ToolNames do
  begin
    mFound := mFound or (mName = 'find_path');
  end;
  Assert.IsTrue(mFound, 'find_path fehlt in tools/list');
end;

procedure TMcpShellTests.ListsHotspotsTool;
var
  mName: string;
  mFound: Boolean;
begin
  // Hotspots (#1354).
  mFound := False;
  for mName in TMcpShell.ToolNames do
  begin
    mFound := mFound or (mName = 'get_hotspots');
  end;
  Assert.IsTrue(mFound, 'get_hotspots fehlt in tools/list');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpShellTests);

end.