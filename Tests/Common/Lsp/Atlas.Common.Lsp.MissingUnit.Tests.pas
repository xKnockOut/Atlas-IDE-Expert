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
  mFolder: string;
  mItems: TArray<string>;
begin
  mFolder := Copy(AFileName, 1, LastDelimiter('\', AFileName) - 1);
  if not Files.TryGetValue(LowerCase(mFolder), mItems) then
  begin
    mItems := nil;
  end;
  Files.AddOrSetValue(LowerCase(mFolder), mItems + [AFileName]);
end;

procedure AddFolder(const AParent, AChild: string);
var
  mItems: TArray<string>;
begin
  if not Folders.TryGetValue(LowerCase(AParent), mItems) then
  begin
    mItems := nil;
  end;
  Folders.AddOrSetValue(LowerCase(AParent), mItems + [AParent + '\' + AChild]);
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
      begin
        Result := nil;
      end;
    end;
  Result.ListFolders :=
    function(AFolder: string): TArray<string>
    begin
      if not Folders.TryGetValue(LowerCase(AFolder), Result) then
      begin
        Result := nil;
      end;
    end;
end;

function Resolver(const ASetup: TMissingUnitSetup): TMissingUnitResolve;
var
  mPrepared: TMissingUnitSetup;
begin
  mPrepared := ASetup;
  Result :=
    function(const AUnitName: string; out AResolved: TMissingUnitSetup): Boolean
    begin
      Inc(Resolved);
      AResolved := mPrepared;
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
  mAction: TJSONObject;
  mCommand: TJSONObject;
  mValues: TJSONArray;
  mText: string;
  mIndex: Integer;
begin
  Result := nil;
  for mAction in AActions do
    try
      mCommand := mAction.GetValue('command') as TJSONObject;
      mValues := mCommand.GetValue('arguments') as TJSONArray;
      mText := '';
      for mIndex := 0 to mValues.Count - 1 do
      begin
        if mIndex > 0 then
        begin
          mText := mText + '|';
        end;
        mText := mText + mValues.Items[mIndex].Value;
      end;
      if mAction.GetValue('isPreferred') <> nil then
      begin
        mText := mText + ' *';
      end;
      Result := Result + [mAction.GetValue<string>('title', '') + ' => ' + mCommand.GetValue<string>('command', '') +
        ' [' + mText + ']'];
    finally
      mAction.Free;
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
  mLines: TArray<string>;
begin
  mLines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Werkzeug'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(3, Integer(Length(mLines)), string.Join(sLineBreak, mLines));
  Assert.AreEqual('Ordner Source\Common in den Suchpfad von Release aufnehmen => atlas.addSearchPath ' +
    '[C:\Projekt\Kasse.dproj|Source\Common|Release *]', mLines[0]);
  Assert.AreEqual('Ordner Source\Common in den Suchpfad aller Konfigurationen aufnehmen => atlas.addSearchPath ' +
    '[C:\Projekt\Kasse.dproj|Source\Common|]', mLines[1]);
  Assert.AreEqual('Werkzeug.pas ins Projekt aufnehmen => atlas.addUnitToProject ' +
    '[C:\Projekt\Kasse.dproj|C:\Projekt\Source\Common\Werkzeug.pas]', mLines[2]);
end;

procedure TLspMissingUnitTests.OffersSearchPathOfOtherConfiguration;
var
  mSetup: TMissingUnitSetup;
  mTarget: TMissingUnitTarget;
  mLines: TArray<string>;
begin
  AddFile('C:\Gemeinsam\Debug\Protokoll.dcu');
  mSetup := BaseSetup;
  mTarget.Config := 'Debug';
  mTarget.Platform := 'Win64';
  mTarget.SearchPaths := ['C:\Gemeinsam\Debug'];
  mSetup.Targets := [mTarget];
  mLines := Describe(TLspMissingUnit.Actions(True, 0, 10, [Msg(3, 'F1026',
    'File not found: ''Protokoll.dcu''')], Resolver(mSetup)));
  Assert.AreEqual(2, Integer(Length(mLines)), string.Join(sLineBreak, mLines));
  Assert.AreEqual('Ordner ..\Gemeinsam\Debug in den Suchpfad von Release aufnehmen (steht in Debug, Win64) => ' +
    'atlas.addSearchPath [C:\Projekt\Kasse.dproj|..\Gemeinsam\Debug|Release *]', mLines[0]);
end;

procedure TLspMissingUnitTests.OtherPlatformOnlyGivesHint;
var
  mSetup: TMissingUnitSetup;
  mLines: TArray<string>;
begin
  AddFile('C:\Delphi\lib\win32\release\Winapi.Windows.dcu');
  AddFile('C:\Delphi\lib\win64\release\Winapi.Windows.dcu');
  mSetup := BaseSetup;
  mSetup.Project.Platform := 'Linux64';
  mSetup.Platforms := ['Win32', 'Win64', 'Linux64'];
  mSetup.LibraryPaths :=
    function(APlatform: string): TArray<string>
    begin
      Result := ['C:\Delphi\lib\' + LowerCase(APlatform) + '\release'];
    end;
  mLines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Winapi.Windows'' not found.')],
    Resolver(mSetup)));
  Assert.AreEqual(1, Integer(Length(mLines)), string.Join(sLineBreak, mLines));
  Assert.AreEqual('Winapi.Windows gibt es für Linux64 nicht (nur Win32, Win64) => atlas.showInfo ' +
    '[Winapi.Windows gibt es für Linux64 nicht (nur Win32, Win64)]', mLines[0]);
end;

procedure TLspMissingUnitTests.NothingFoundListsPlaces;
var
  mLines: TArray<string>;
begin
  mLines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Fehlt'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('Fehlt nicht gefunden: durchsuchte Orte anzeigen => atlas.showInfo ' +
    '[Fehlt nicht gefunden. Durchsucht: Projektordner C:\Projekt und Unterordner]', mLines[0]);
end;

procedure TLspMissingUnitTests.OnlyOnSelectedLinesAndOncePerUnit;
var
  mLines: TArray<string>;
begin
  mLines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Werkzeug'' not found.'),
    Msg(3, 'F1026', 'File not found: ''Werkzeug.dcu'''), Msg(5, 'F2613', 'Unit ''Anderes'' not found.'),
    Msg(3, 'E2003', 'Undeclared identifier: ''Foo''')], Resolver(BaseSetup)));
  Assert.AreEqual(3, Integer(Length(mLines)), string.Join(sLineBreak, mLines));
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
  mLines: TArray<string>;
begin
  AddFile('C:\Projekt\Source\Common\Fertig.dcu');
  mLines := Describe(TLspMissingUnit.Actions(True, 3, 3, [Msg(3, 'F2613', 'Unit ''Fertig'' not found.')],
    Resolver(BaseSetup)));
  Assert.AreEqual(2, Integer(Length(mLines)), 'nur die Suchpfade, eine .dcu kommt nicht ins Projekt');
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
