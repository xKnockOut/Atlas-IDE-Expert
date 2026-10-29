unit Atlas.Common.Lsp.MissingUnit.Tests;

// Tests für die Code-Aktionen zu „Unit nicht gefunden“ (#550): Ordner in den
// Suchpfad, Unit ins Projekt, Hinweise für andere Plattformen und ohne Fund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspMissingUnitTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: F2613 bietet den Unterordner an, relativ zur .dproj.</summary>
    [Test]
    procedure OffersSubfolderRelative;
    [Test]
    procedure OffersSearchPathOfOtherConfiguration;
    [Test]
    procedure OtherPlatformOnlyGivesHint;
    [Test]
    procedure NothingFoundListsPlaces;
    [Test]
    procedure OnlyOnSelectedLinesAndOncePerUnit;
    [Test]
    procedure SwitchedOff;
    [Test]
    procedure DcuIsNotAddedToProject;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Lsp.MissingUnit;

var
  /// <summary>Unechte Platte: Ordner (klein) → Dateien bzw. Unterordner.</summary>
  Files: TDictionary<string, TArray<string>>;
  Folders: TDictionary<string, TArray<string>>;
  /// <summary>Wie oft die Suche vorbereitet wurde.</summary>
  Resolved: Integer;

procedure AddFile(const AFileName: string);
var
  Folder: string;
  Items: TArray<string>;
begin
  Folder := Copy(AFileName, 1, LastDelimiter('\', AFileName) - 1);
  if not Files.TryGetValue(LowerCase(Folder), Items) then
    Items := nil;
  Files.AddOrSetValue(LowerCase(Folder), Items + [AFileName]);
end;

procedure AddFolder(const AParent, AChild: string);
var
  Items: TArray<string>;
begin
  if not Folders.TryGetValue(LowerCase(AParent), Items) then
    Items := nil;
  Folders.AddOrSetValue(LowerCase(AParent), Items + [AParent + '\' + AChild]);
end;

function BaseSetup: TMissingUnitSetup;
begin
  Result := Default(TMissingUnitSetup);
  Result.Project.FileName := 'C:\Projekt\Kasse.dproj';
  Result.Project.Config := 'Release';
  Result.Project.Platform := 'Win64';
  Result.ListFiles :=
    function(AFolder: string): TArray<string>
    begin
      if not Files.TryGetValue(LowerCase(AFolder), Result) then
        Result := nil;
    end;
  Result.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      if not Folders.TryGetValue(LowerCase(AFolder), Result) then
        Result := nil;
    end;
end;

function Resolver(const ASetup: TMissingUnitSetup): TMissingUnitResolve;
var
  Prepared: TMissingUnitSetup;
begin
  Prepared := ASetup;
  Result :=
    function(const AUnitName: string; out AResolved: TMissingUnitSetup): Boolean
    begin
      Inc(Resolved);
      AResolved := Prepared;
      Result := True;
    end;
end;

function Msg(ALine: Integer; const ACode, AText: string): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := 'C:\Projekt\Kasse.dpr';
  Result.Line := ALine;
  Result.Column := 2;
  Result.Severity := TCompilerSeverity.Fatal;
  Result.Code := ACode;
  Result.Text := AText;
end;

/// <summary>Titel und Argumente je Aktion: „Titel => Befehl [a|b|c]“; gibt die Aktionen frei.</summary>
function Describe(const AActions: TArray<TJSONObject>): TArray<string>;
var
  Action: TJSONObject;
  Command: TJSONObject;
  Values: TJSONArray;
  Text: string;
  Index: Integer;
begin
  Result := nil;
  for Action in AActions do
    try
      Command := Action.GetValue('command') as TJSONObject;
      Values := Command.GetValue('arguments') as TJSONArray;
      Text := '';
      for Index := 0 to Values.Count - 1 do
      begin
        if Index > 0 then
          Text := Text + '|';
        Text := Text + Values.Items[Index].Value;
      end;
      if Action.GetValue('isPreferred') <> nil then
        Text := Text + ' *';
      Result := Result + [Action.GetValue<string>('title', '') + ' => ' + Command.GetValue<string>('command', '') +
        ' [' + Text + ']'];
    finally
      Action.Free;
    end;
end;

procedure TLspMissingUnitTests.Setup;
begin
  Files.Clear;
  Folders.Clear;
  Resolved := 0;
  AddFolder('C:\Projekt', 'Source');
  AddFolder('C:\Projekt\Source', 'Common');
  AddFile('C:\Projekt\Kasse.dpr');
  AddFile('C:\Projekt\Source\Common\Werkzeug.pas');
end;

procedure TLspMissingUnitTests.TearDown;
begin
  Files.Clear;
  Folders.Clear;
end;

procedure TLspMissingUnitTests.OffersSubfolderRelative;
var
  Lines: TArray<string>;
begin
  Lines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Werkzeug'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(3, Integer(Length(Lines)), string.Join(sLineBreak, Lines));
  Assert.AreEqual('Ordner Source\Common in den Suchpfad von Release aufnehmen => atlas.addSearchPath ' +
    '[C:\Projekt\Kasse.dproj|Source\Common|Release *]', Lines[0]);
  Assert.AreEqual('Ordner Source\Common in den Suchpfad aller Konfigurationen aufnehmen => atlas.addSearchPath ' +
    '[C:\Projekt\Kasse.dproj|Source\Common|]', Lines[1]);
  Assert.AreEqual('Werkzeug.pas ins Projekt aufnehmen => atlas.addUnitToProject ' +
    '[C:\Projekt\Kasse.dproj|C:\Projekt\Source\Common\Werkzeug.pas]', Lines[2]);
end;

procedure TLspMissingUnitTests.OffersSearchPathOfOtherConfiguration;
var
  Setup: TMissingUnitSetup;
  Target: TMissingUnitTarget;
  Lines: TArray<string>;
begin
  AddFile('C:\Gemeinsam\Debug\Protokoll.dcu');
  Setup := BaseSetup;
  Target.Config := 'Debug';
  Target.Platform := 'Win64';
  Target.SearchPaths := ['C:\Gemeinsam\Debug'];
  Setup.Targets := [Target];
  Lines := Describe(TLspMissingUnit.Actions(True, 0, 10, [Msg(3, 'F1026',
    'File not found: ''Protokoll.dcu''')], Resolver(Setup)));
  Assert.AreEqual(2, Integer(Length(Lines)), string.Join(sLineBreak, Lines));
  Assert.AreEqual('Ordner ..\Gemeinsam\Debug in den Suchpfad von Release aufnehmen (steht in Debug, Win64) => ' +
    'atlas.addSearchPath [C:\Projekt\Kasse.dproj|..\Gemeinsam\Debug|Release *]', Lines[0]);
end;

procedure TLspMissingUnitTests.OtherPlatformOnlyGivesHint;
var
  Setup: TMissingUnitSetup;
  Lines: TArray<string>;
begin
  AddFile('C:\Delphi\lib\win32\release\Winapi.Windows.dcu');
  AddFile('C:\Delphi\lib\win64\release\Winapi.Windows.dcu');
  Setup := BaseSetup;
  Setup.Project.Platform := 'Linux64';
  Setup.Platforms := ['Win32', 'Win64', 'Linux64'];
  Setup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := ['C:\Delphi\lib\' + LowerCase(APlatform) + '\release'];
    end;
  Lines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Winapi.Windows'' not found.')],
    Resolver(Setup)));
  Assert.AreEqual(1, Integer(Length(Lines)), string.Join(sLineBreak, Lines));
  Assert.AreEqual('Winapi.Windows gibt es für Linux64 nicht (nur Win32, Win64) => atlas.showInfo ' +
    '[Winapi.Windows gibt es für Linux64 nicht (nur Win32, Win64)]', Lines[0]);
end;

procedure TLspMissingUnitTests.NothingFoundListsPlaces;
var
  Lines: TArray<string>;
begin
  Lines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Fehlt'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual('Fehlt nicht gefunden: durchsuchte Orte anzeigen => atlas.showInfo ' +
    '[Fehlt nicht gefunden. Durchsucht: Projektordner C:\Projekt und Unterordner]', Lines[0]);
end;

procedure TLspMissingUnitTests.OnlyOnSelectedLinesAndOncePerUnit;
var
  Lines: TArray<string>;
begin
  Lines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Werkzeug'' not found.'),
    Msg(3, 'F1026', 'File not found: ''Werkzeug.dcu'''), Msg(5, 'F2613', 'Unit ''Anderes'' not found.'),
    Msg(3, 'E2003', 'Undeclared identifier: ''Foo''')], Resolver(BaseSetup)));
  Assert.AreEqual(3, Integer(Length(Lines)), string.Join(sLineBreak, Lines));
  Assert.AreEqual(1, Resolved, 'eine Suche je Unit');
end;

procedure TLspMissingUnitTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TLspMissingUnit.Actions(False, 3, 3,
    [Msg(3, 'F2613', 'Unit ''Werkzeug'' not found.')], Resolver(BaseSetup)))));
  Assert.AreEqual(0, Resolved, 'abgeschaltet sucht Atlas nicht');
end;

procedure TLspMissingUnitTests.DcuIsNotAddedToProject;
var
  Lines: TArray<string>;
begin
  AddFile('C:\Projekt\Source\Common\Fertig.dcu');
  Lines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Fertig'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(2, Integer(Length(Lines)), 'nur die Suchpfade, eine .dcu kommt nicht ins Projekt');
end;

initialization
  // Mit Vorrat: Ein Test, der die Tabellen wachsen ließe, zählte sonst als Leck.
  Files := TDictionary<string, TArray<string>>.Create(64);
  Folders := TDictionary<string, TArray<string>>.Create(64);
  TDUnitX.RegisterTestFixture(TLspMissingUnitTests);

finalization
  Folders.Free;
  Files.Free;

end.
