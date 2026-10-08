unit BDLsp.Common.Lsp.FileOperations.Tests;

// Tests für Dateioperationen im Editor (#181).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspFileOperationsTests = class
  public
    [Test]
    procedure RenameEditsAllFiles;
    [Test]
    procedure RenameIgnoresOtherExtensions;
    [Test]
    procedure FindsReferencesToDeletedUnit;
    [Test]
    procedure SkeletonOnlyForEmptyUnits;
    [Test]
    procedure WorkspaceEditGroupsByFile;
    [Test]
    procedure CapabilityFiltersPascalFiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Lsp.References,
  BDLsp.Common.Lsp.FileOperations;

var
  Files: TDictionary<string, string>;

function ReadText: TReferenceReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(AFileName, AText);
    end;
end;

procedure Setup;
begin
  Files.Clear;
  Files.Add('C:\App\Alt.pas', 'unit Alt;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Files.Add('C:\App\Main.pas', 'unit Main;'#13#10'interface'#13#10'uses Alt;'#13#10'implementation'#13#10'end.');
  Files.Add('C:\App\Other.pas', 'unit Other;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Files.Add('C:\App\App.dpr', 'program App;'#13#10'uses'#13#10'  Alt in ''Alt.pas'';'#13#10'begin'#13#10'end.');
  Files.Add('C:\App\App.dproj', '<Project>'#13#10'  <DCCReference Include="Alt.pas"/>'#13#10'</Project>');
  Files.Add('C:\App\Leer.pas', '  '#13#10);
end;

procedure TLspFileOperationsTests.RenameEditsAllFiles;
var
  Edits: TArray<TFileEdit>;
  Edit: TFileEdit;
  PerFile: string;
begin
  Setup;
  // Main.pas doppelt (Projekt und geöffnet) darf keine doppelten Edits ergeben.
  Edits := TLspFileOperations.RenameEdits('C:\App\Alt.pas', 'C:\App\Neu.pas',
    ['C:\App\Main.pas', 'C:\App\Other.pas', 'C:\App\Main.pas'], ['C:\App\App.dproj', 'C:\App\App.dpr'], ReadText);
  PerFile := '';
  for Edit in Edits do
    PerFile := PerFile + ExtractFileName(Edit.FileName) + '=' + Edit.NewText + ';';
  Assert.AreEqual('Main.pas=Neu;App.dpr=Neu;App.dpr=''Neu.pas'';Alt.pas=Neu;App.dproj=Neu.pas;', PerFile);
end;

procedure TLspFileOperationsTests.RenameIgnoresOtherExtensions;
begin
  Setup;
  Assert.AreEqual(0, Integer(Length(TLspFileOperations.RenameEdits('C:\App\Alt.dfm', 'C:\App\Neu.dfm',
    ['C:\App\Main.pas'], nil, ReadText))));
end;

procedure TLspFileOperationsTests.FindsReferencesToDeletedUnit;
var
  Found: TArray<TUnitReference>;
begin
  Setup;
  Found := TLspFileOperations.References('C:\App\Alt.pas', ['C:\App\Alt.pas', 'C:\App\Main.pas', 'C:\App\Other.pas'],
    ['C:\App\App.dproj', 'C:\App\App.dpr'], ReadText);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('C:\App\Main.pas', Found[0].FileName);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual('C:\App\App.dpr', Found[1].FileName);
end;

procedure TLspFileOperationsTests.SkeletonOnlyForEmptyUnits;
var
  Text: string;
begin
  Setup;
  Assert.IsTrue(TLspFileOperations.SkeletonFor('C:\App\Leer.pas', ReadText, Text));
  Assert.IsTrue(Text.StartsWith('unit Leer;'#13#10));
  Assert.IsFalse(TLspFileOperations.SkeletonFor('C:\App\Main.pas', ReadText, Text));
  Assert.IsFalse(TLspFileOperations.SkeletonFor('C:\App\Fehlt.pas', ReadText, Text));
  Assert.IsFalse(TLspFileOperations.SkeletonFor('C:\App\App.dproj', ReadText, Text));
end;

procedure TLspFileOperationsTests.WorkspaceEditGroupsByFile;
var
  Edits: TArray<TFileEdit>;
  Json: TJSONObject;
  Changes: TJSONObject;
begin
  SetLength(Edits, 3);
  Edits[0].FileName := 'C:\App\A.pas';
  Edits[0].Range := TTextRange.Create(0, 5, 0, 6);
  Edits[0].NewText := 'X';
  Edits[1] := Edits[0];
  Edits[1].Range := TTextRange.Create(2, 0, 2, 1);
  Edits[2] := Edits[0];
  Edits[2].FileName := 'C:\App\B.pas';
  Json := TLspFileOperations.WorkspaceEdit(Edits);
  try
    Changes := Json.GetValue('changes') as TJSONObject;
    Assert.AreEqual(2, Changes.Count);
    Assert.AreEqual(2, (Changes.GetValue(TDocumentUris.FromPath('C:\App\A.pas')) as TJSONArray).Count);
  finally
    Json.Free;
  end;
end;

procedure TLspFileOperationsTests.CapabilityFiltersPascalFiles;
var
  Json: TJSONObject;
begin
  Json := TLspFileOperations.Capability;
  try
    Assert.AreEqual('**/*.pas', Json.GetValue<string>('willRename.filters[0].pattern.glob'));
    Assert.IsNotNull(Json.GetValue('didCreate'));
    Assert.IsNotNull(Json.GetValue('didDelete'));
  finally
    Json.Free;
  end;
end;

initialization
  Files := TDictionary<string, string>.Create;
  TDUnitX.RegisterTestFixture(TLspFileOperationsTests);

finalization
  Files.Free;

end.
