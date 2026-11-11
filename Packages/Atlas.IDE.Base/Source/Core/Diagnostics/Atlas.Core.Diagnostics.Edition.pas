unit Atlas.Core.Diagnostics.Edition;

// Kommandozeilen-Compiler der IDE (#1822), ohne VCL und Open Tools API. RAD Studio Starter (und je nach Version
// Community) liefert weder dcc32/dcc64 noch die Ziele für MSBuild; was über die Kommandozeile baut, scheitert dort
// erst beim Lauf. Detect sieht im Ordner der Installation ($(BDS)) unter bin und bin64 nach; das ist die eigentliche
// Frage, unabhängig vom Namen der Edition. NeedsCommandLine erkennt Aufrufe, die einen solchen Compiler brauchen
// (Projektaufgaben). Mit diagnostics.editionCheck aus gilt der Compiler immer als vorhanden (Verhalten wie vorher).

interface

uses
  System.SysUtils;

type
  TAtlasFileExistsFunc = reference to function(const AFileName: string): Boolean;

  /// <summary>Ergebnis von TAtlasEdition.Detect.</summary>
  TAtlasCompilerTools = record
    /// <summary>Ordner der Installation bekannt und geprüft; sonst gilt der Compiler als vorhanden.</summary>
    Checked: Boolean;
    Dcc32: Boolean;
    Dcc64: Boolean;
    /// <summary>Ein Kommandozeilen-Compiler ist da (oder nicht geprüft).</summary>
    function CommandLine: Boolean;
    /// <summary>Zusatz der Startzeile im Protokoll, englisch: "command-line compiler: dcc32, dcc64".</summary>
    function LogText: string;
  end;

  TAtlasEdition = class
  public const
    /// <summary>Programme, die einen Kommandozeilen-Compiler brauchen (ohne Endung, klein).</summary>
    cCompilers: array[0..7] of string = ('dcc32', 'dcc64', 'dccosx64', 'dccosxarm64', 'dcclinux64', 'dccaarm64',
      'dcciosarm64', 'msbuild');
  public
    /// <summary>Sucht dcc32.exe und dcc64.exe unter ABdsDir\bin und ABdsDir\bin64; ABdsDir '' = nicht geprüft.
    /// </summary>
    class function Detect(const ABdsDir: string; const AExists: TAtlasFileExistsFunc): TAtlasCompilerTools; static;
    /// <summary>Braucht das Programm AProgram (Name oder Pfad, mit oder ohne .exe) einen Kommandozeilen-Compiler?
    /// </summary>
    class function NeedsCommandLine(const AProgram: string): Boolean; static;
    /// <summary>Fehlt der Compiler für Atlas? AEnabled = diagnostics.editionCheck.</summary>
    class function Missing(const ATools: TAtlasCompilerTools; AEnabled: Boolean): Boolean; static;
    /// <summary>Einmalige Benachrichtigung zeigen? AShown = schon einmal gezeigt.</summary>
    class function ShouldNotify(const ATools: TAtlasCompilerTools; AEnabled, AShown: Boolean): Boolean; static;
  end;

implementation

{ TAtlasCompilerTools }

function TAtlasCompilerTools.CommandLine: Boolean;
begin
  Result := (not Checked) or Dcc32 or Dcc64;
end;

function TAtlasCompilerTools.LogText: string;
begin
  if not Checked then
  begin
    Result := 'command-line compiler: not checked';
  end
  else if Dcc32 and Dcc64 then
  begin
    Result := 'command-line compiler: dcc32, dcc64';
  end
  else if Dcc32 then
  begin
    Result := 'command-line compiler: dcc32';
  end
  else if Dcc64 then
  begin
    Result := 'command-line compiler: dcc64';
  end
  else
  begin
    Result := 'command-line compiler: none (Starter or Community edition), builds run through the IDE';
  end;
end;

{ TAtlasEdition }

class function TAtlasEdition.Detect(const ABdsDir: string; const AExists: TAtlasFileExistsFunc): TAtlasCompilerTools;
var
  mRoot: string;

  function Has(const AName: string): Boolean;
  begin
    Result := AExists(mRoot + 'bin\' + AName) or AExists(mRoot + 'bin64\' + AName);
  end;

begin
  Result.Checked := False;
  Result.Dcc32 := False;
  Result.Dcc64 := False;
  mRoot := Trim(ABdsDir);
  if (mRoot = '') or not Assigned(AExists) then
  begin
    Exit;
  end;
  if not mRoot.EndsWith('\') then
  begin
    mRoot := mRoot + '\';
  end;
  Result.Checked := True;
  Result.Dcc32 := Has('dcc32.exe');
  Result.Dcc64 := Has('dcc64.exe');
end;

class function TAtlasEdition.NeedsCommandLine(const AProgram: string): Boolean;
var
  mName, mCompiler: string;
  mSlash: Integer;
begin
  mName := StringReplace(Trim(AProgram), '"', '', [rfReplaceAll]);
  mSlash := mName.LastDelimiter('\/');
  if mSlash >= 0 then
  begin
    mName := mName.Substring(mSlash + 1);
  end;
  mName := LowerCase(mName);
  if mName.EndsWith('.exe') then
  begin
    mName := mName.Substring(0, mName.Length - 4);
  end;
  for mCompiler in cCompilers do
  begin
    if mName = mCompiler then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasEdition.Missing(const ATools: TAtlasCompilerTools; AEnabled: Boolean): Boolean;
begin
  Result := AEnabled and not ATools.CommandLine;
end;

class function TAtlasEdition.ShouldNotify(const ATools: TAtlasCompilerTools; AEnabled, AShown: Boolean): Boolean;
begin
  Result := Missing(ATools, AEnabled) and not AShown;
end;

end.
