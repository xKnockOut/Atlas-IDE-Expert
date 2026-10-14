unit Atlas.Core.Commands.Palette.Tests;

// Tests für die Befehlspalette (#502).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCommandPaletteTests = class
  public
    [Test]
    procedure FuzzyFindsBuildProject;
    [Test]
    procedure LastExecutedFirst;
    [Test]
    procedure PathHelpsWhenCaptionDoesNot;
    [Test]
    procedure CleansCaptions;
    [Test]
    procedure HistoryRoundTrip;
    [Test]
    procedure KeepsListOrderForCodeActions;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Commands.Palette;

function Command(const AId, ACaption: string; const APath: string = ''): TAtlasCommand;
begin
  Result := Default(TAtlasCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Path := APath;
end;

function Captions(const ACommands: TArray<TAtlasCommand>; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    Result := Result + ACommands[Index].Caption + '|';
end;

function Sample: TArray<TAtlasCommand>;
begin
  Result := [Command('ProjectBuild', 'Build Project', 'Project'), Command('ProjectCompile', 'Compile Project', 'Project'),
    Command('FileOpen', 'Open', 'File'), Command('Atlas.Options', 'Atlas: Optionen')];
end;

procedure TAtlasCommandPaletteTests.FuzzyFindsBuildProject;
var
  Commands: TArray<TAtlasCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Build Project|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'bpj', nil)));
end;

procedure TAtlasCommandPaletteTests.LastExecutedFirst;
var
  Commands: TArray<TAtlasCommand>;
  History: TAtlasCommandHistory;
begin
  Commands := Sample;
  History := TAtlasCommandHistory.Create;
  try
    // Ohne Eingabe alphabetisch, der eben ausgeführte Befehl oben.
    Assert.AreEqual('Atlas: Optionen|Build Project|Compile Project|Open|',
      Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)));
    History.Executed('FileOpen');
    Assert.AreEqual('Open|Atlas: Optionen|Build Project|Compile Project|',
      Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)));
    History.Executed('ProjectCompile');
    Assert.AreEqual('Compile Project|Open|', Copy(Captions(Commands, TAtlasCommandPalette.Order(Commands, '', History)), 1, 21));
  finally
    History.Free;
  end;
end;

procedure TAtlasCommandPaletteTests.PathHelpsWhenCaptionDoesNot;
var
  Commands: TArray<TAtlasCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Open|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'file open', nil)));
end;

procedure TAtlasCommandPaletteTests.CleansCaptions;
begin
  Assert.AreEqual('Datei öffnen', TAtlasCommandPalette.CleanCaption('&Datei öffnen...'));
  Assert.AreEqual('Suchen & Ersetzen', TAtlasCommandPalette.CleanCaption('Suchen && &Ersetzen'));
end;

procedure TAtlasCommandPaletteTests.HistoryRoundTrip;
var
  History, Loaded: TAtlasCommandHistory;
  FileName: string;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'atlas-palette-test.json');
  History := TAtlasCommandHistory.Create;
  Loaded := TAtlasCommandHistory.Create;
  try
    History.Executed('A');
    History.Executed('B');
    History.SaveToFile(FileName);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(History.Boost('A'), Loaded.Boost('A'));
    Assert.AreEqual(History.Boost('B'), Loaded.Boost('B'));
    Assert.IsTrue(Loaded.Boost('B') > Loaded.Boost('A'));
  finally
    Loaded.Free;
    History.Free;
    TFile.Delete(FileName);
  end;
end;

procedure TAtlasCommandPaletteTests.KeepsListOrderForCodeActions;
var
  Commands: TArray<TAtlasCommand>;
begin
  // Code-Aktionen (#399): bevorzugte zuerst, so wie der Server sie liefert.
  Commands := [Command('0', 'try/finally ergänzen'), Command('1', 'Befund kopieren'), Command('2', 'Als Konstante')];
  Assert.AreEqual('try/finally ergänzen|Befund kopieren|Als Konstante|',
    Captions(Commands, TAtlasCommandPalette.Order(Commands, '', nil, True)));
  Assert.AreEqual('Als Konstante|Befund kopieren|try/finally ergänzen|',
    Captions(Commands, TAtlasCommandPalette.Order(Commands, '', nil)), 'ohne KeepOrder alphabetisch');
  Assert.AreEqual('Befund kopieren|', Captions(Commands, TAtlasCommandPalette.Order(Commands, 'befund', nil, True)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommandPaletteTests);

end.