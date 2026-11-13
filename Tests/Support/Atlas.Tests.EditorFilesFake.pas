unit Atlas.Tests.EditorFilesFake;

// Fälschung für IAtlasEditorFiles (#1967): Tests legen offene Dateien mit Put an und lesen danach,
// welche Dateien gespeichert wurden. Nicht genannte Dateien gelten als geschlossen.
// Dazu die Fälschung für IAtlasActiveEditor: meldet die beim Anlegen genannte Schreibmarke.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Files.Contract;

type
  TAtlasEditorFilesFake = class(TInterfacedObject, IAtlasEditorFiles)
  private
    FFiles: TDictionary<string, TAtlasEditorFile>;
    FSaved: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Die Datei AFileName ist offen mit Text AText; AModified = ungespeichert geändert.</summary>
    procedure Put(const AFileName, AText: string; AModified: Boolean);
    /// <summary>Gespeicherte Dateien in der Reihenfolge der Aufrufe.</summary>
    function Saved: TArray<string>;
    function Buffer(const AFileName: string): TAtlasEditorFile;
    function Save(const AFileName: string): Boolean;
  end;

  TAtlasActiveEditorFake = class(TInterfacedObject, IAtlasActiveEditor)
  private
    FCaret: TAtlasActiveEditorPos;
  public
    /// <summary>Der obere Editor steht auf ACaret; TAtlasActiveEditorPos.None = kein Editor.</summary>
    constructor Create(const ACaret: TAtlasActiveEditorPos);
    function Caret: TAtlasActiveEditorPos;
  end;

implementation

constructor TAtlasEditorFilesFake.Create;
begin
  inherited Create;
  FFiles := TDictionary<string, TAtlasEditorFile>.Create;
  FSaved := TList<string>.Create;
end;

destructor TAtlasEditorFilesFake.Destroy;
begin
  FSaved.Free;
  FFiles.Free;
  inherited Destroy;
end;

procedure TAtlasEditorFilesFake.Put(const AFileName, AText: string; AModified: Boolean);
begin
  FFiles.AddOrSetValue(AFileName, TAtlasEditorFile.Opened(AText, AModified));
end;

function TAtlasEditorFilesFake.Saved: TArray<string>;
begin
  Result := FSaved.ToArray;
end;

function TAtlasEditorFilesFake.Buffer(const AFileName: string): TAtlasEditorFile;
begin
  if not FFiles.TryGetValue(AFileName, Result) then
  begin
    Result := TAtlasEditorFile.Closed;
  end;
end;

function TAtlasEditorFilesFake.Save(const AFileName: string): Boolean;
var
  mFile: TAtlasEditorFile;
begin
  Result := FFiles.TryGetValue(AFileName, mFile);
  if Result then
  begin
    FSaved.Add(AFileName);
    mFile.Modified := False;
    FFiles.AddOrSetValue(AFileName, mFile);
  end;
end;

constructor TAtlasActiveEditorFake.Create(const ACaret: TAtlasActiveEditorPos);
begin
  inherited Create;
  FCaret := ACaret;
end;

function TAtlasActiveEditorFake.Caret: TAtlasActiveEditorPos;
begin
  Result := FCaret;
end;

end.
