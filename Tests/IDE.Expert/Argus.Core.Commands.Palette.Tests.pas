unit Argus.Core.Commands.Palette.Tests;

// Tests für die Befehlspalette (#502).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusCommandPaletteTests = class
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Argus.Core.Commands.Palette;

function Command(const AId, ACaption: string; const APath: string = ''): TArgusCommand;
begin
  Result := Default(TArgusCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Path := APath;
end;

function Captions(const ACommands: TArray<TArgusCommand>; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
    Result := Result + ACommands[Index].Caption + '|';
end;

function Sample: TArray<TArgusCommand>;
begin
  Result := [Command('ProjectBuild', 'Build Project', 'Project'), Command('ProjectCompile', 'Compile Project', 'Project'),
    Command('FileOpen', 'Open', 'File'), Command('Argus.Options', 'Argus: Optionen')];
end;

procedure TArgusCommandPaletteTests.FuzzyFindsBuildProject;
var
  Commands: TArray<TArgusCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Build Project|', Captions(Commands, TArgusCommandPalette.Order(Commands, 'bpj', nil)));
end;

procedure TArgusCommandPaletteTests.LastExecutedFirst;
var
  Commands: TArray<TArgusCommand>;
  History: TArgusCommandHistory;
begin
  Commands := Sample;
  History := TArgusCommandHistory.Create;
  try
    // Ohne Eingabe alphabetisch, der eben ausgeführte Befehl oben.
    Assert.AreEqual('Argus: Optionen|Build Project|Compile Project|Open|',
      Captions(Commands, TArgusCommandPalette.Order(Commands, '', History)));
    History.Executed('FileOpen');
    Assert.AreEqual('Open|Argus: Optionen|Build Project|Compile Project|',
      Captions(Commands, TArgusCommandPalette.Order(Commands, '', History)));
    History.Executed('ProjectCompile');
    Assert.AreEqual('Compile Project|Open|', Copy(Captions(Commands, TArgusCommandPalette.Order(Commands, '', History)), 1, 21));
  finally
    History.Free;
  end;
end;

procedure TArgusCommandPaletteTests.PathHelpsWhenCaptionDoesNot;
var
  Commands: TArray<TArgusCommand>;
begin
  Commands := Sample;
  Assert.AreEqual('Open|', Captions(Commands, TArgusCommandPalette.Order(Commands, 'file open', nil)));
end;

procedure TArgusCommandPaletteTests.CleansCaptions;
begin
  Assert.AreEqual('Datei öffnen', TArgusCommandPalette.CleanCaption('&Datei öffnen...'));
  Assert.AreEqual('Suchen & Ersetzen', TArgusCommandPalette.CleanCaption('Suchen && &Ersetzen'));
end;

procedure TArgusCommandPaletteTests.HistoryRoundTrip;
var
  History, Loaded: TArgusCommandHistory;
  FileName: string;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'argus-palette-test.json');
  History := TArgusCommandHistory.Create;
  Loaded := TArgusCommandHistory.Create;
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

initialization
  TDUnitX.RegisterTestFixture(TArgusCommandPaletteTests);

end.